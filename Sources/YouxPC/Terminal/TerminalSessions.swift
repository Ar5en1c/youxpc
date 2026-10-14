// TerminalSessions.swift - Run user-approved commands in Terminal.app
//
// Terminal emulators are blocked by AppPolicy, because UI access to a shell
// prompt is shell access. This is the one controlled door: the pc_terminal
// tool, available only when the user lists commands in YOUXPC_TERMINAL_COMMANDS.
//
// What the rules guarantee:
//
// 1. Only approved commands start. A requested command line is split into
//    arguments and must begin with the arguments of an approved entry. It is
//    never handed to a shell for interpretation: every argument is written
//    single-quoted into a launcher script, so `;`, `|`, `$()` and friends are
//    inert text.
//
// 2. There is never a shell prompt to type into. The launcher `exec`s the
//    command, and Terminal runs launchers as `script; exit`, so when the
//    program ends the session ends with it.
//
// 3. Keystrokes reach only that program. They are posted to the Terminal
//    process itself (TargetedKeyboard), never to "whatever is frontmost", so
//    they cannot land in another app. Before typing we check that the process
//    we started is alive and is the foreground job of its tty, that its
//    window is Terminal's focused window, and that the window has no other
//    tab. If the program has exited, or has put a child in the foreground,
//    typing is refused. Terminal does not need to be the active app.
//
// 4. Terminal-level shortcuts (anything with Cmd, such as paste or new tab)
//    cannot be sent.
//
// What they do not guarantee: an approved program can do whatever it is able
// to do. Approving an agent CLI means the driving agent can ask it for
// anything that CLI allows. YOUXPC_TERMINAL_SANDBOX=on narrows that by running
// the command under a macOS sandbox profile that denies file writes outside
// the working directory and temp directories.
//
// Lifecycle. Sessions are written to ~/.youxpc/terminal/sessions.json, so a
// restarted server finds the programs it left running and can drive them
// again (the window is re-identified by its window-server number). Windows do
// not pile up: when a program exits, its last output is kept for reading and
// its window is closed; `close` stops a program and closes its window; and a
// session nobody has used for YOUXPC_TERMINAL_IDLE_HOURS (default 12) is
// stopped and closed.
//
// Only Apple's Terminal.app is supported.

import AppKit
import ApplicationServices
import AXorcist
import Foundation

/// Approved-command terminal sessions.
public enum TerminalSessions {

    // MARK: - Configuration

    private static let terminalBundleID = "com.apple.Terminal"

    /// Approved command prefixes, each already split into arguments.
    private static let approved: [[String]] = {
        guard let raw = ProcessInfo.processInfo.environment["YOUXPC_TERMINAL_COMMANDS"] else { return [] }
        return raw.split(separator: ",").compactMap { entry in
            let tokens = try? tokenize(String(entry))
            return (tokens?.isEmpty ?? true) ? nil : tokens
        }
    }()

    /// True when the user has approved at least one command.
    public static var isEnabled: Bool { !approved.isEmpty }

    /// Approved entries as the user wrote them, for the tool description.
    public static var approvedSummary: String {
        approved.map { $0.joined(separator: " ") }.joined(separator: ", ")
    }

    private static let sandboxEnabled = flag("YOUXPC_TERMINAL_SANDBOX", default: false)
    private static let sandboxAllowsNetwork = flag("YOUXPC_TERMINAL_SANDBOX_NETWORK", default: true)
    private static let sandboxExtraWritePaths: [String] = {
        let raw = ProcessInfo.processInfo.environment["YOUXPC_TERMINAL_SANDBOX_WRITE"] ?? ""
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }()

    private static let sessionDirectory = NSString(string: "~/.youxpc/terminal").expandingTildeInPath
    private static let maxTextLength = 4000
    private static let maxReadCharacters = 8000

    // MARK: - State

    private struct Session {
        let id: String
        let command: [String]
        let cwd: String
        let pid: pid_t
        /// Process start time in seconds. A pid alone can be reused.
        let processStart: Int
        let ttyDevice: dev_t
        /// Window-server number of the session's window, 0 if unknown. It
        /// outlives this process, which an AXUIElement reference does not.
        let windowNumber: Int
        let sandboxed: Bool
        /// Nil once closed, or when it could not be found again after a restart.
        var window: AXUIElement?
        var lastUsed: Date
        var exitedAt: Date?
        /// Output captured when the program exited, kept so it can still be read.
        var finalOutput: String?
    }

    /// What is written to disk for each session.
    private struct Record: Codable {
        let id: String
        let command: [String]
        let cwd: String
        let pid: Int32
        let processStart: Int
        let ttyDevice: Int32
        let windowNumber: Int
        let sandboxed: Bool
        let lastUsed: Double
        let exitedAt: Double?
        let finalOutput: String?
    }

    private static var sessions: [String: Session] = [:]
    private static var loaded = false
    private static var lastReap = Date.distantPast

    private static let recordsPath = sessionDirectory + "/sessions.json"
    /// How long an exited session stays readable before it is forgotten.
    private static let keepExitedSeconds: TimeInterval = 600
    private static let idleLimitSeconds: TimeInterval = {
        let hours = Double(ProcessInfo.processInfo.environment["YOUXPC_TERMINAL_IDLE_HOURS"] ?? "") ?? 12
        return max(0.1, hours) * 3600
    }()

    // MARK: - Tool entry point

    public static func handle(_ args: [String: Any]) -> ToolResult {
        guard isEnabled else {
            return ToolResult(
                success: false,
                error: "Terminal access is disabled.",
                suggestion: "Only the user can enable it, by listing approved commands in "
                    + "YOUXPC_TERMINAL_COMMANDS in the MCP server configuration."
            )
        }
        loadIfNeeded()
        reap()
        switch args["action"] as? String {
        case "run":
            return run(command: args["command"] as? String, cwd: args["cwd"] as? String)
        case "read":
            return withSession(args) { read($0, lines: args["lines"] as? Int) }
        case "type":
            return withSession(args) {
                type($0, text: args["text"] as? String, enter: args["enter"] as? Bool ?? false)
            }
        case "key":
            return withSession(args) { key($0, combo: args["key"] as? String) }
        case "close":
            if args["all"] as? Bool == true { return closeAll() }
            return withSession(args) { close($0) }
        case "list":
            return list()
        default:
            return ToolResult(success: false, error: "action must be one of: run, read, type, key, close, list")
        }
    }

    private static func withSession(_ args: [String: Any], _ body: (Session) -> ToolResult) -> ToolResult {
        let id = args["session"] as? String
        // With a single session the id is optional.
        var session = id.flatMap { sessions[$0] } ?? (id == nil && sessions.count == 1 ? sessions.values.first : nil)
        session?.lastUsed = Date()
        if let session { sessions[session.id] = session }
        guard let session else {
            return ToolResult(
                success: false,
                error: "Unknown terminal session '\(id ?? "")'",
                suggestion: "Use action:'list' to see sessions, or action:'run' to start one"
            )
        }
        return body(session)
    }

    // MARK: - run

    private static func run(command: String?, cwd: String?) -> ToolResult {
        guard let command, !command.trimmingCharacters(in: .whitespaces).isEmpty else {
            return ToolResult(success: false, error: "Missing required parameter: command")
        }
        let tokens: [String]
        do {
            tokens = try tokenize(command)
        } catch {
            return ToolResult(success: false, error: "Could not parse command: \(error.localizedDescription)")
        }
        guard approved.contains(where: { tokens.starts(with: $0) }) else {
            return ToolResult(
                success: false,
                error: "'\(tokens.first ?? command)' is not an approved terminal command.",
                suggestion: "Approved: \(approvedSummary). Only the user can add more, in YOUXPC_TERMINAL_COMMANDS."
            )
        }

        let directory = (cwd.map { NSString(string: $0).expandingTildeInPath }) ?? NSHomeDirectory()
        var isDirectory: ObjCBool = false
        guard directory.hasPrefix("/"),
              FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue
        else {
            return ToolResult(success: false, error: "cwd '\(directory)' is not an existing directory")
        }
        let realDirectory = realPath(directory)

        let id = String(UUID().uuidString.prefix(8)).lowercased()
        do {
            try FileManager.default.createDirectory(
                atPath: sessionDirectory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            return ToolResult(success: false, error: "Could not create \(sessionDirectory): \(error.localizedDescription)")
        }
        let scriptPath = sessionDirectory + "/\(id).command"
        let infoPath = sessionDirectory + "/\(id).info"

        var launch = tokens.map(shellQuote).joined(separator: " ")
        if sandboxEnabled {
            let profilePath = sessionDirectory + "/\(id).sb"
            guard let profile = sandboxProfile(writableDirectory: realDirectory) else {
                return ToolResult(success: false, error: "Sandbox profile rejected: a writable path contains a quote or backslash")
            }
            do {
                try profile.write(toFile: profilePath, atomically: true, encoding: .utf8)
            } catch {
                return ToolResult(success: false, error: "Could not write sandbox profile: \(error.localizedDescription)")
            }
            launch = "/usr/bin/sandbox-exec -f \(shellQuote(profilePath)) " + launch
        }

        // `exec` keeps the script's pid, so the pid recorded here is the program's.
        let script = """
        #!/bin/zsh
        # YouxPC terminal session \(id)
        cd -- \(shellQuote(realDirectory)) || exit 1
        print -r -- "$$ $(tty)" > \(shellQuote(infoPath))
        # Start on an empty screen: the login banner and the launcher's own command
        # line are noise for whoever reads the session.
        printf '\\033[H\\033[2J\\033[3J'
        exec \(launch)

        """
        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptPath)
        } catch {
            return ToolResult(success: false, error: "Could not write launcher: \(error.localizedDescription)")
        }

        let previousApp = NSWorkspace.shared.frontmostApplication
        let windowsBefore = terminalWindows()

        let opener = Process()
        opener.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // -g: open the window without bringing Terminal to the front.
        opener.arguments = ["-g", "-b", terminalBundleID, scriptPath]
        do {
            try opener.run()
            opener.waitUntilExit()
        } catch {
            return ToolResult(success: false, error: "Could not open Terminal: \(error.localizedDescription)")
        }
        guard opener.terminationStatus == 0 else {
            return ToolResult(success: false, error: "Terminal did not accept the launcher (open exited \(opener.terminationStatus))")
        }

        // Wait for the launcher to report its pid and tty.
        var pid: pid_t = 0
        var ttyName = ""
        for _ in 0..<60 {
            if let info = try? String(contentsOfFile: infoPath, encoding: .utf8) {
                let parts = info.split(separator: " ", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if parts.count == 2, let parsed = pid_t(parts[0]), parts[1].hasPrefix("/dev/") {
                    pid = parsed
                    ttyName = parts[1]
                    break
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        try? FileManager.default.removeItem(atPath: infoPath)
        guard pid > 0 else {
            return ToolResult(
                success: false,
                error: "The command did not start within 6 seconds",
                suggestion: "Terminal may be showing a prompt that needs the user"
            )
        }
        var ttyStat = stat()
        guard stat(ttyName, &ttyStat) == 0 else {
            kill(pid, SIGTERM)
            return ToolResult(success: false, error: "Could not identify the session's terminal device")
        }

        // The session's window is the one that was not there before.
        var newWindows: [AXUIElement] = []
        for _ in 0..<20 {
            newWindows = terminalWindows().filter { candidate in
                !windowsBefore.contains { CFEqual($0, candidate) }
            }
            if !newWindows.isEmpty { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard newWindows.count == 1, let window = newWindows.first else {
            kill(pid, SIGTERM)
            return ToolResult(
                success: false,
                error: "Could not identify the new Terminal window, so the command was stopped",
                suggestion: "Terminal must open new sessions in their own window, not as a tab "
                    + "(System Settings > Desktop & Dock > Prefer tabs: Never)"
            )
        }

        let terminalPID = Perception.runningApps()
            .first { $0.bundleIdentifier == terminalBundleID }?.processIdentifier ?? 0
        sessions[id] = Session(
            id: id, command: tokens, cwd: realDirectory, pid: pid,
            processStart: processStart(of: pid) ?? 0,
            ttyDevice: ttyStat.st_rdev,
            windowNumber: frame(of: window).map { windowNumber(matching: $0, ownerPID: terminalPID) } ?? 0,
            sandboxed: sandboxEnabled, window: window, lastUsed: Date()
        )
        save()
        FocusManager.restoreFocus(to: previousApp)
        Log.info("Terminal session \(id) started: \(tokens.first ?? "") (pid \(pid))")

        return ToolResult(
            success: true,
            data: [
                "session": id,
                "command": tokens.joined(separator: " "),
                "cwd": realDirectory,
                "sandboxed": sandboxEnabled,
                "next": "Use action:'read' to see output, 'type' and 'key' to interact.",
            ]
        )
    }

    // MARK: - read

    private static func read(_ session: Session, lines: Int?) -> ToolResult {
        let text: String
        if let window = session.window, let live = terminalText(of: window) {
            text = live
        } else if let captured = session.finalOutput {
            text = captured
        } else {
            return ToolResult(
                success: false,
                error: "The session's Terminal window is not available",
                suggestion: session.exitedAt == nil
                    ? "The window could not be found again after a restart. Use action:'close' to stop the program."
                    : "The program has exited and no output was captured."
            )
        }
        return ToolResult(
            success: true,
            data: [
                "session": session.id,
                "running": isForeground(session),
                // Program output is untrusted text, the same as any screen content.
                "output": tail(of: text, lines: lines ?? 60),
            ]
        )
    }

    private static func tail(of text: String, lines: Int) -> String {
        var rows = text.components(separatedBy: "\n")
        while let last = rows.last, last.trimmingCharacters(in: .whitespaces).isEmpty { rows.removeLast() }
        var tail = rows.suffix(max(1, min(lines, 500))).joined(separator: "\n")
        if tail.count > maxReadCharacters { tail = String(tail.suffix(maxReadCharacters)) }
        return tail
    }

    // MARK: - type / key

    private static func type(_ session: Session, text: String?, enter: Bool) -> ToolResult {
        guard let text else {
            return ToolResult(success: false, error: "Missing required parameter: text")
        }
        guard text.count <= maxTextLength else {
            return ToolResult(success: false, error: "text is longer than \(maxTextLength) characters")
        }
        guard !text.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            return ToolResult(
                success: false,
                error: "text contains control characters or newlines",
                suggestion: "Send one line at a time and pass enter:true to submit it"
            )
        }
        let terminalPID: pid_t
        switch prepareForInput(session) {
        case let .refused(result): return result
        case let .ready(pid): terminalPID = pid
        }

        if !text.isEmpty, !TargetedKeyboard.type(text, to: terminalPID) {
            return ToolResult(success: false, error: "Could not create keyboard events")
        }
        if enter {
            Thread.sleep(forTimeInterval: 0.05)
            TargetedKeyboard.press("return", to: terminalPID)
        }
        return ToolResult(success: true, data: ["session": session.id, "typed": text.count, "enter": enter])
    }

    private static func key(_ session: Session, combo: String?) -> ToolResult {
        guard let combo, !combo.isEmpty else {
            return ToolResult(success: false, error: "Missing required parameter: key")
        }
        let parts = combo.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyName = parts.last, !keyName.isEmpty else {
            return ToolResult(success: false, error: "Invalid key '\(combo)'")
        }
        let modifiers = Array(parts.dropLast())

        // Cmd and Option combinations are Terminal's own shortcuts (paste, new
        // tab, new window). Only keys the running program receives are allowed.
        let allowed: Bool = switch modifiers {
        case []: TargetedKeyboard.isNamedKey(keyName)
        case ["ctrl"], ["control"]: keyName.count == 1 && keyName.first?.isLetter == true && keyName.first?.isASCII == true
        case ["shift"]: keyName == "tab"
        default: false
        }
        guard allowed else {
            return ToolResult(
                success: false,
                error: "Key '\(combo)' is not allowed in a terminal session",
                suggestion: "Allowed: return, tab, escape, space, delete, arrows, pageup/pagedown, home, end, "
                    + "shift+tab, and ctrl+<letter>"
            )
        }
        let terminalPID: pid_t
        switch prepareForInput(session) {
        case let .refused(result): return result
        case let .ready(pid): terminalPID = pid
        }

        let sent: Bool = switch modifiers {
        case []: TargetedKeyboard.press(keyName, to: terminalPID)
        case ["shift"]: TargetedKeyboard.press(keyName, shift: true, to: terminalPID)
        default: keyName.first.map { TargetedKeyboard.pressControl($0, to: terminalPID) } ?? false
        }
        guard sent else {
            return ToolResult(success: false, error: "Could not create keyboard events")
        }
        return ToolResult(success: true, data: ["session": session.id, "key": combo])
    }

    private enum InputReadiness {
        case ready(terminalPID: pid_t)
        case refused(ToolResult)
    }

    /// Check every input precondition and make the session's window the one
    /// Terminal will deliver keys to. Terminal is not activated: input is
    /// posted to its process directly, so the user's frontmost app is untouched.
    private static func prepareForInput(_ session: Session) -> InputReadiness {
        guard isForeground(session) else {
            return .refused(ToolResult(
                success: false,
                error: "'\(session.command.first ?? "The program")' is not accepting input: it has exited "
                    + "or is running something else in the foreground",
                suggestion: "Use action:'read' to see what happened. Start a new session with action:'run' if it exited."
            ))
        }
        guard let terminal = Perception.runningApps().first(where: {
            $0.bundleIdentifier == terminalBundleID
        }) else {
            return .refused(ToolResult(success: false, error: "Terminal is not running"))
        }
        guard let window = session.window else {
            return .refused(ToolResult(
                success: false,
                error: "The session's Terminal window could not be found again after a restart, so input cannot be verified",
                suggestion: "Use action:'close' to stop the program, then start a new session"
            ))
        }
        guard tabCount(of: window) <= 1 else {
            return .refused(ToolResult(
                success: false,
                error: "The session's window has more than one tab, so the focused tab cannot be verified",
                suggestion: "Ask the user to close the extra tab"
            ))
        }

        let appElement = AXUIElementCreateApplication(terminal.processIdentifier)
        func isFocused() -> Bool {
            guard let focused = elementAttribute(kAXFocusedWindowAttribute, of: appElement) else { return false }
            return CFEqual(focused, window)
        }
        if !isFocused() {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, window)
            for _ in 0..<12 where !isFocused() {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        guard isFocused() else {
            return .refused(ToolResult(
                success: false,
                error: "Could not make the session's window Terminal's focused window, so nothing was typed"
            ))
        }
        // The program may have exited while the window was being selected.
        guard isForeground(session) else {
            return .refused(ToolResult(success: false, error: "The program exited before input could be sent"))
        }
        return .ready(terminalPID: terminal.processIdentifier)
    }

    // MARK: - list

    private static func list() -> ToolResult {
        let rows: [[String: Any]] = sessions.values.sorted { $0.id < $1.id }.map { session in
            [
                "session": session.id,
                "command": session.command.joined(separator: " "),
                "cwd": session.cwd,
                "running": isForeground(session),
                "exited": session.exitedAt != nil,
                "window": session.window != nil,
                "sandboxed": session.sandboxed,
            ]
        }
        return ToolResult(success: true, data: ["sessions": rows, "approved": approvedSummary])
    }

    // MARK: - close

    private static func close(_ session: Session) -> ToolResult {
        let wasRunning = isAlive(session)
        end(session.id, keepOutput: false)
        return ToolResult(
            success: true,
            data: ["session": session.id, "stopped": wasRunning, "window_closed": true]
        )
    }

    private static func closeAll() -> ToolResult {
        let ids = Array(sessions.keys)
        ids.forEach { end($0, keepOutput: false) }
        return ToolResult(success: true, data: ["closed": ids.count])
    }

    /// Stop a session's program if it is still running, close its window, and
    /// either forget it or keep it briefly so its last output can be read.
    private static func end(_ id: String, keepOutput: Bool) {
        guard var session = sessions[id] else { return }
        if keepOutput, session.finalOutput == nil, let window = session.window {
            session.finalOutput = terminalText(of: window).map { tail(of: $0, lines: 300) }
        }
        if isAlive(session) {
            // We started this process; stopping it is ours to do.
            kill(session.pid, SIGTERM)
            for _ in 0..<20 where isAlive(session) { Thread.sleep(forTimeInterval: 0.1) }
            if isAlive(session) {
                kill(session.pid, SIGKILL)
                Thread.sleep(forTimeInterval: 0.3)
            }
            // Give Terminal a moment to notice, or it asks before closing.
            Thread.sleep(forTimeInterval: 0.4)
        }
        if let window = session.window {
            closeWindow(window)
            session.window = nil
        }
        for suffix in [".command", ".sb", ".info"] {
            try? FileManager.default.removeItem(atPath: sessionDirectory + "/\(id)" + suffix)
        }
        if keepOutput {
            session.exitedAt = session.exitedAt ?? Date()
            sessions[id] = session
        } else {
            sessions[id] = nil
        }
        save()
        Log.info("Terminal session \(id) ended")
    }

    // MARK: - Lifecycle

    /// Called while the server waits for input. Cheap: at most one pass every two seconds.
    public static func idleTick() {
        guard isEnabled || loaded, Date().timeIntervalSince(lastReap) > 2 else { return }
        loadIfNeeded()
        reap()
    }

    /// Called when the server is shutting down. Programs still running are
    /// left alone so a restarted server can pick them up; finished ones are tidied.
    public static func shutdown() {
        guard loaded else { return }
        reap()
        save()
    }

    /// Close the windows of finished programs, forget old ones, stop idle ones.
    private static func reap() {
        lastReap = Date()
        let now = Date()
        for session in sessions.values {
            if let exitedAt = session.exitedAt {
                if now.timeIntervalSince(exitedAt) > keepExitedSeconds { end(session.id, keepOutput: false) }
            } else if !isAlive(session) {
                end(session.id, keepOutput: true)
            } else if now.timeIntervalSince(session.lastUsed) > idleLimitSeconds {
                Log.info("Terminal session \(session.id) idle too long, stopping it")
                end(session.id, keepOutput: false)
            }
        }
    }

    // MARK: - Persistence

    private static func save() {
        let records = sessions.values.map { session in
            Record(
                id: session.id, command: session.command, cwd: session.cwd, pid: session.pid,
                processStart: session.processStart, ttyDevice: session.ttyDevice,
                windowNumber: session.windowNumber, sandboxed: session.sandboxed,
                lastUsed: session.lastUsed.timeIntervalSince1970,
                exitedAt: session.exitedAt?.timeIntervalSince1970,
                finalOutput: session.finalOutput
            )
        }
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? FileManager.default.createDirectory(
            atPath: sessionDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        FileManager.default.createFile(atPath: recordsPath, contents: data, attributes: [.posixPermissions: 0o600])
    }

    /// Read sessions left by a previous server process and find their windows again.
    private static func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = FileManager.default.contents(atPath: recordsPath),
              let records = try? JSONDecoder().decode([Record].self, from: data)
        else { return }
        let windows = terminalWindows()
        for record in records where sessions[record.id] == nil {
            // Match the saved window number to a live window through its frame.
            var window: AXUIElement?
            if record.exitedAt == nil, record.windowNumber != 0,
               let saved = frame(forWindowNumber: record.windowNumber)
            {
                let matches = windows.filter { frame(of: $0) == saved }
                if matches.count == 1 { window = matches[0] }
            }
            sessions[record.id] = Session(
                id: record.id, command: record.command, cwd: record.cwd, pid: record.pid,
                processStart: record.processStart, ttyDevice: record.ttyDevice,
                windowNumber: record.windowNumber, sandboxed: record.sandboxed,
                window: window,
                lastUsed: Date(timeIntervalSince1970: record.lastUsed),
                exitedAt: record.exitedAt.map { Date(timeIntervalSince1970: $0) },
                finalOutput: record.finalOutput
            )
        }
        if !records.isEmpty {
            Log.info("Restored \(records.count) terminal session(s), \(sessions.values.filter { $0.window != nil }.count) with a window")
        }
    }

    // MARK: - Process checks

    private static func processInfo(_ pid: pid_t) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0,
              info.kp_proc.p_pid == pid
        else { return nil }
        return info
    }

    private static func processStart(of pid: pid_t) -> Int? {
        processInfo(pid).map { Int($0.kp_proc.p_un.__p_starttime.tv_sec) }
    }

    /// True when the process we started still exists. The start time is
    /// compared as well, so a recycled pid is not mistaken for it.
    private static func isAlive(_ session: Session) -> Bool {
        guard session.exitedAt == nil, let info = processInfo(session.pid),
              info.kp_proc.p_stat != UInt8(SZOMB)
        else { return false }
        return session.processStart == 0
            || Int(info.kp_proc.p_un.__p_starttime.tv_sec) == session.processStart
    }

    /// True when the program we started is alive, still on its tty, and is that
    /// tty's foreground process group.
    private static func isForeground(_ session: Session) -> Bool {
        guard isAlive(session), let info = processInfo(session.pid) else { return false }
        return info.kp_eproc.e_tdev == session.ttyDevice
            && info.kp_eproc.e_tpgid == info.kp_eproc.e_pgid
    }

    // MARK: - Terminal.app accessibility

    private static func terminalWindows() -> [AXUIElement] {
        guard let terminal = Perception.runningApps().first(where: {
            $0.bundleIdentifier == terminalBundleID
        }) else { return [] }
        let appElement = AXUIElementCreateApplication(terminal.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let items = value as? [AnyObject]
        else { return [] }
        return items.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef,
              CFGetTypeID(positionRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        // Types checked against AXValueGetTypeID above.
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func windowList(_ option: CGWindowListOption, relativeTo window: CGWindowID) -> [[String: Any]] {
        CGWindowListCopyWindowInfo(option, window) as? [[String: Any]] ?? []
    }

    private static func bounds(of entry: [String: Any]) -> CGRect? {
        guard let dictionary = entry[kCGWindowBounds as String] else { return nil }
        return CGRect(dictionaryRepresentation: dictionary as! CFDictionary)
    }

    /// Window-server number of the one window owned by `ownerPID` with this frame, or 0.
    private static func windowNumber(matching frame: CGRect, ownerPID: pid_t) -> Int {
        let matches = windowList(.optionAll, relativeTo: kCGNullWindowID).filter { entry in
            (entry[kCGWindowOwnerPID as String] as? pid_t) == ownerPID
                && (entry[kCGWindowLayer as String] as? Int) == 0
                && bounds(of: entry) == frame
        }
        return matches.count == 1 ? (matches[0][kCGWindowNumber as String] as? Int ?? 0) : 0
    }

    private static func frame(forWindowNumber number: Int) -> CGRect? {
        windowList(.optionIncludingWindow, relativeTo: CGWindowID(number)).first.flatMap(bounds(of:))
    }

    @discardableResult
    private static func closeWindow(_ window: AXUIElement) -> Bool {
        guard let button = elementAttribute(kAXCloseButtonAttribute, of: window) else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    private static func tabCount(of window: AXUIElement) -> Int {
        guard let group = firstDescendant(of: window, role: "AXTabGroup", depth: 3) else { return 1 }
        return children(of: group).filter { stringAttribute(kAXRoleAttribute, of: $0) == "AXRadioButton" }.count
    }

    private static func terminalText(of window: AXUIElement) -> String? {
        guard stringAttribute(kAXRoleAttribute, of: window) != nil,
              let area = firstDescendant(of: window, role: "AXTextArea", depth: 6)
        else { return nil }
        return stringAttribute(kAXValueAttribute, of: area) ?? ""
    }

    private static func firstDescendant(of element: AXUIElement, role: String, depth: Int) -> AXUIElement? {
        guard depth > 0 else { return nil }
        for child in children(of: element) {
            if stringAttribute(kAXRoleAttribute, of: child) == role { return child }
            if let found = firstDescendant(of: child, role: role, depth: depth - 1) { return found }
        }
        return nil
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let items = value as? [AnyObject]
        else { return [] }
        return items.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }

    private static func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func elementAttribute(_ name: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        // Type checked against AXUIElementGetTypeID above.
        return (value as! AXUIElement)
    }

    // MARK: - Sandbox

    /// A write-jail: everything stays readable and (by default) the network
    /// stays up, but files can only be written under the working directory,
    /// temp directories, and paths the user added.
    private static func sandboxProfile(writableDirectory: String) -> String? {
        let extra = sandboxExtraWritePaths.map { realPath(NSString(string: $0).expandingTildeInPath) }
        let writable = [writableDirectory, "/private/tmp", "/private/var/tmp", "/private/var/folders"] + extra
        guard !writable.contains(where: { $0.contains("\"") || $0.contains("\\") }) else { return nil }

        var lines = [
            "(version 1)",
            "(allow default)",
            "(deny file-write*)",
            "(allow file-write*",
        ]
        lines += writable.map { "  (subpath \"\($0)\")" }
        lines += [
            "  (literal \"/dev/null\") (literal \"/dev/tty\") (literal \"/dev/dtracehelper\")",
            "  (regex #\"^/dev/ttys[0-9]+$\") (regex #\"^/dev/fd/[0-9]+$\"))",
        ]
        if !sandboxAllowsNetwork { lines.append("(deny network*)") }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Resolve symlinks with realpath(3). Foundation's equivalent rewrites
    /// /private/tmp back to /tmp, which sandbox profiles do not match.
    private static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    // MARK: - Command parsing

    enum ParseError: LocalizedError {
        case unbalancedQuote
        case controlCharacter

        var errorDescription: String? {
            switch self {
            case .unbalancedQuote: "unbalanced quote"
            case .controlCharacter: "control characters and newlines are not allowed"
            }
        }
    }

    /// Split a command line into arguments. Quotes group words; nothing else
    /// is special, because the result is never interpreted by a shell.
    static func tokenize(_ line: String) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var inToken = false
        var quote: Character?
        for character in line {
            if character.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
                throw ParseError.controlCharacter
            }
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
                inToken = true
            } else if character == " " {
                if inToken { tokens.append(current); current = ""; inToken = false }
            } else {
                current.append(character)
                inToken = true
            }
        }
        guard quote == nil else { throw ParseError.unbalancedQuote }
        if inToken { tokens.append(current) }
        return tokens
    }

    /// Single-quote a string for zsh so every character is literal.
    static func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func flag(_ name: String, default fallback: Bool) -> Bool {
        guard let value = ProcessInfo.processInfo.environment[name]?.lowercased() else { return fallback }
        if ["on", "1", "true", "yes"].contains(value) { return true }
        if ["off", "0", "false", "no"].contains(value) { return false }
        return fallback
    }
}

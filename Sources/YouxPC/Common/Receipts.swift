// Receipts.swift - A local record of everything the agent did
//
// One JSON line per event in ~/.youxpc/logs/receipts.jsonl, readable only by
// the user. Every tool call is recorded with its target, its outcome, how the
// action was delivered, how long it took, and how much the screen changed.
// Server starts and stops are recorded too, so calls can be grouped into runs.
//
// What is kept is controlled by YOUXPC_RECEIPTS:
//   standard (default)  everything except typed text and screen content
//   full                also the text that was typed and commands' arguments
//   off                 nothing is written
//
// `youxpc receipts` prints the log in a readable form.
//
// Traces are a separate, opt-in record for building datasets: with
// YOUXPC_TRACE=on every call is also written, complete with its arguments and
// the full text it returned (which includes screen content), to
// ~/.youxpc/traces/<run>.jsonl. YOUXPC_TRACE_GOAL, if set, is stored as the
// task the run was working on. Goal, screen, chosen element and outcome are
// what a small decision model needs to learn from; receipts deliberately do
// not contain them.

import Foundation

/// Append-only log of tool calls and server lifecycle events.
public enum Receipts {

    public enum Level: String {
        case off, standard, full
    }

    public static let level: Level = {
        let environment = ProcessInfo.processInfo.environment
        if let value = environment["YOUXPC_RECEIPTS"]?.lowercased(), let level = Level(rawValue: value) {
            return level
        }
        return .standard
    }()

    public static let directory = NSString(string: "~/.youxpc/logs").expandingTildeInPath
    public static let path = directory + "/receipts.jsonl"
    private static let rotateAtBytes: UInt64 = 5 * 1024 * 1024

    /// Identifies this server process in the log.
    public static let runID = String(UUID().uuidString.prefix(8)).lowercased()
    private static var client = "unknown"
    private static var callCount = 0

    /// Arguments that identify a target. Recorded at every level.
    private static let targetArguments = [
        "app", "index", "query", "role", "dom_id", "x", "y", "from_x", "from_y", "to_x", "to_y",
        "key", "keys", "direction", "action", "session", "command", "cwd", "recipe", "name",
        "condition", "window", "full", "enter", "n",
    ]

    /// Arguments that carry content. Recorded only at the `full` level.
    private static let contentArguments = ["text", "into", "value", "params"]

    // MARK: - Events

    public static func serverStarted(client clientName: String?) {
        client = clientName ?? "unknown"
        write([
            "event": "server_start",
            "version": Product.version,
            "client": client,
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "receipts": level.rawValue,
            "terminal_commands": TerminalSessions.approvedSummary,
            "tools": SimpleProfile.isEnabled ? "simple" : (MCPTools.isFullProfile ? "full" : "core"),
        ])
    }

    public static func serverStopped() {
        write(["event": "server_stop", "calls": callCount])
    }

    // MARK: - Traces

    public static let traceEnabled: Bool = {
        ["on", "1", "true", "yes"].contains(ProcessInfo.processInfo.environment["YOUXPC_TRACE"]?.lowercased() ?? "")
    }()

    private static let traceDirectory = NSString(string: "~/.youxpc/traces").expandingTildeInPath

    /// Write one complete tool call to this run's trace file.
    private static func trace(tool: String, args: [String: Any], response: [String: Any], milliseconds: Int) {
        guard traceEnabled else { return }
        let content = response["content"] as? [[String: Any]] ?? []
        let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined(separator: "\n")
        var entry: [String: Any] = [
            "time": ISO8601DateFormatter().string(from: Date()),
            "run": runID,
            "tool": tool,
            "arguments": JSONSerialization.isValidJSONObject(args) ? args : [:],
            "ok": !(response["isError"] as? Bool ?? false),
            "ms": milliseconds,
            "result": text,
        ]
        if let goal = ProcessInfo.processInfo.environment["YOUXPC_TRACE_GOAL"], !goal.isEmpty {
            entry["goal"] = goal
        }
        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        let path = traceDirectory + "/\(runID).jsonl"
        let files = FileManager.default
        if !files.fileExists(atPath: path) {
            try? files.createDirectory(
                atPath: traceDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
            files.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data + Data("\n".utf8))
    }

    /// Record one tool call from its arguments and the MCP response it produced.
    public static func record(tool: String, args: [String: Any], response: [String: Any], milliseconds: Int) {
        trace(tool: tool, args: args, response: response, milliseconds: milliseconds)
        guard level != .off else { return }
        callCount += 1
        var entry: [String: Any] = [
            "event": "tool",
            "tool": tool,
            "ok": !(response["isError"] as? Bool ?? false),
            "ms": milliseconds,
        ]
        let names = level == .full ? targetArguments + contentArguments : targetArguments
        for name in names {
            guard let value = args[name] else { continue }
            if let string = value as? String {
                entry[name] = clip(string, 300)
            } else if value is NSNumber || value is [String] || value is [String: Any] {
                entry[name] = value
            }
        }
        if level == .standard, let text = args["text"] as? String {
            // Enough to show that something was typed, and how much, without keeping it.
            entry["text_length"] = text.count
        }
        entry.merge(outcome(of: response)) { current, _ in current }
        write(entry)
    }

    // MARK: - Outcome

    /// Pull the facts worth keeping out of a tool's response.
    private static func outcome(of response: [String: Any]) -> [String: Any] {
        guard let content = response["content"] as? [[String: Any]] else { return [:] }
        var result: [String: Any] = [:]
        if content.contains(where: { $0["type"] as? String == "image" }) {
            result["returned"] = "image"
        }
        guard let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String else {
            return result
        }
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            // Plain-text tools (snapshots): keep the heading and the size only.
            result["lines"] = text.split(separator: "\n", omittingEmptySubsequences: false).count
            if let heading = text.split(separator: "\n").first { result["heading"] = clip(String(heading), 120) }
            return result
        }
        if let error = json["error"] as? String { result["error"] = clip(error, 240) }
        guard let body = json["data"] as? [String: Any] else { return result }
        for key in ["method", "pointer", "element", "session", "sandboxed", "running", "stopped", "typed"] {
            if let value = body[key], value is String || value is NSNumber {
                result[key] = (value as? String).map { clip($0, 120) } ?? value
            }
        }
        if let changes = body["changes"] as? String {
            let rows = changes.split(separator: "\n")
            result["changed"] = [
                "added": rows.filter { $0.hasPrefix("+ ") }.count,
                "removed": rows.filter { $0.hasPrefix("- ") }.count,
                "altered": rows.filter { $0.hasPrefix("~ ") }.count,
            ]
        }
        return result
    }

    // MARK: - File

    private static func write(_ fields: [String: Any]) {
        guard level != .off else { return }
        var entry = fields
        entry["time"] = ISO8601DateFormatter().string(from: Date())
        entry["run"] = runID
        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }

        let files = FileManager.default
        if !files.fileExists(atPath: path) {
            try? files.createDirectory(
                atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
            files.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
        } else if let size = (try? files.attributesOfItem(atPath: path))?[.size] as? UInt64, size > rotateAtBytes {
            let previous = path + ".1"
            try? files.removeItem(atPath: previous)
            try? files.moveItem(atPath: path, toPath: previous)
            files.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data + Data("\n".utf8))
    }

    private static func clip(_ string: String, _ limit: Int) -> String {
        string.count > limit ? String(string.prefix(limit)) + "…" : string
    }
}

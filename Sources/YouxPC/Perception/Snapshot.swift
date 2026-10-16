// Snapshot.swift - Numbered, compact view of an app's UI
//
// pc_snapshot walks the focused window once and returns one short line per
// useful element. Interactive elements carry an id such as e7; action tools
// accept that id as `index`, so the agent never has to describe an element twice and
// the server never has to search for it again.
//
//   Google Chrome — "Inbox (3) - Gmail"
//   toolbar
//     [e1] button "Back"
//     [e2] textfield "Address and search bar" = "mail.google.com"
//   web "Inbox (3) - Gmail"
//     [e7] button "Compose"
//     "Primary"
//
// The id is written e7, not 7, on purpose. A calculator's keys are buttons
// named "7", "8", "9"; with bare numbers a line read `[7] button "9"`, and in
// benchmark runs a strong model pressed the label when it meant the number
// (13 x 79 for 47 x 19). A prefixed id cannot be mistaken for a label.
//
// Numbers are stable: an element keeps its number across snapshots for as long
// as its role and name stay the same. That is what makes the diff mode useful.
// After the first snapshot of a window, later ones list only what was added,
// removed or changed.
//
// Cost control:
//   - one batched AX call per element instead of one per attribute,
//   - anything outside the window's bounds is skipped, subtree included,
//   - layout containers are walked through but never printed,
//   - a node budget and a deadline bound the worst case; the result says so
//     when either was hit.

import AppKit
import ApplicationServices
import AXorcist
import Foundation

/// Builds and stores numbered UI snapshots.
public enum Snapshot {

    // MARK: - Stored state

    /// One numbered element from the latest snapshot of an app.
    public struct Entry {
        public let index: Int
        public let element: AXUIElement
        public let role: String
        public let name: String
        public let frame: CGRect?
    }

    private struct AppState {
        var appName: String
        var windowTitle: String
        var entries: [Int: Entry] = [:]
        /// Rendered line per fingerprint, in document order, from the last snapshot.
        var lines: [(fingerprint: String, text: String)] = []
        /// Fingerprint -> number, kept across snapshots so numbers stay stable.
        var numbers: [String: Int] = [:]
        var nextNumber = 1
        /// Every element given an id in this session, including ones not on
        /// screen now, so that an element that comes back gets its own id back.
        var known: [AXUIElement: Int] = [:]
        /// Where each id's element was when last seen.
        var lastFrame: [Int: CGRect] = [:]
    }

    private static var states: [pid_t: AppState] = [:]
    private static var latestPID: pid_t?

    // MARK: - Limits

    private static let maxNodes = 6000
    private static let maxKnownElements = 5000
    private static let deadlineSeconds: TimeInterval = 4.0
    private static let defaultMaxLines = 400
    private static let maxDepth = 80
    private static let nameLimit = 90
    private static let textLimit = 140
    private static let valueLimit = 80

    // MARK: - Roles

    private static let interactiveRoles: Set<String> = [
        "AXButton", "AXPopUpButton", "AXMenuButton", "AXLink", "AXCheckBox",
        "AXRadioButton", "AXTextField", "AXTextArea", "AXSecureTextField",
        "AXSearchField", "AXComboBox", "AXSlider", "AXIncrementor",
        "AXDisclosureTriangle", "AXTab", "AXSwitch", "AXToggle", "AXMenuItem",
        "AXColorWell", "AXDateField",
    ]

    /// Roles whose value is worth printing after the name.
    private static let valueRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXSearchField", "AXComboBox", "AXSlider",
        "AXPopUpButton", "AXIncrementor", "AXDateField",
    ]

    private static let textEntryRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXSearchField", "AXComboBox",
    ]

    /// Shown on a checkbox whose value the app does not report.
    private static let unreportedState = "(state not reported; a click toggles it)"

    /// Containers that become an unnumbered heading line with indented content.
    private static let sectionRoles: [String: String] = [
        "AXToolbar": "toolbar", "AXTabGroup": "tabs", "AXWebArea": "web",
        "AXSheet": "sheet", "AXDialog": "dialog", "AXMenu": "menu",
        "AXTable": "table", "AXOutline": "outline", "AXList": "list",
    ]

    private static let attributeNames: [String] = [
        kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
        kAXValueAttribute, kAXEnabledAttribute, kAXFocusedAttribute,
        kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute,
        kAXSelectedAttribute, kAXSubroleAttribute,
    ]

    /// A window's own close, minimise and zoom buttons. They are unnamed, sit
    /// in every window, and pressing one by mistake ends the task (closing
    /// Calculator's window quits it). Window management has its own tool.
    private static let windowControlSubroles: Set<String> = [
        "AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton",
    ]

    // MARK: - pc_snapshot

    /// Result of building a snapshot.
    public struct Output {
        public let text: String
        public let isError: Bool
    }

    /// Snapshot the focused window of an app (frontmost app when nil).
    public static func take(appName: String?, forceFull: Bool, maxLines: Int?) -> Output {
        let app: NSRunningApplication? = if let appName {
            Perception.findApp(named: appName)
        } else {
            NSWorkspace.shared.frontmostApplication
        }
        guard let app else {
            return Output(text: "App '\(appName ?? "frontmost")' is not running. Use pc_state to list apps.", isError: true)
        }
        let pid = app.processIdentifier
        let baseline = states[pid]
        let budget = max(20, min(maxLines ?? defaultMaxLines, 2000))

        guard var captured = capture(app, inheriting: baseline, lineBudget: budget) else {
            return Output(text: "'\(app.localizedName ?? "App")' has no open window.", isError: true)
        }
        // Electron and Chromium apps build their accessibility tree on demand.
        // An almost empty result is the sign that it has not been requested yet.
        if captured.state.entries.count < sparseTreeThreshold, requestFullAccessibility(for: app),
           let retried = capture(app, inheriting: baseline, lineBudget: budget)
        {
            captured = retried
        }
        // Chromium browsers build a page's accessibility tree only once
        // something asks for it. Without this the first snapshot of a browser
        // shows the toolbar and no page.
        if let woken = wakeWebContent(of: app, current: captured, inheriting: baseline, lineBudget: budget) {
            captured = woken
        }
        let state = captured.state
        states[pid] = state
        latestPID = pid

        var header = "\(state.appName) — \"\(clip(state.windowTitle, nameLimit))\""
        let notes = captured.notes

        // Diff against the previous snapshot of the same window when that is shorter.
        if !forceFull, let baseline, baseline.windowTitle == state.windowTitle, !baseline.lines.isEmpty {
            let diff = diffLines(old: baseline.lines, new: state.lines)
            if diff.changes.isEmpty {
                return Output(text: header + "\n(no change since the last snapshot)" + suffix(notes), isError: false)
            }
            if diff.changes.count * 2 < state.lines.count {
                header += " (changes since the last snapshot; full:true for everything)"
                let body = diff.changes.joined(separator: "\n")
                return Output(
                    text: header + "\n" + body + "\n(\(diff.unchanged) lines unchanged)" + suffix(notes),
                    isError: false
                )
            }
        }

        var allNotes = notes
        if state.lines.isEmpty {
            allNotes.append("no readable elements; try pc_screenshot")
        }
        let body = state.lines.map(\.text).joined(separator: "\n")
        return Output(text: header + "\n" + body + suffix(allNotes), isError: false)
    }

    // MARK: - Full view (simple profile)

    /// The whole window as numbered lines, never a diff. With `settle` the
    /// UI is given time to stop changing first. With `pageOnly`, a browser's
    /// own toolbar is left out and the page comes first.
    public static func view(appName: String, settle: Bool, pageOnly: Bool, maxLines: Int) -> Output {
        guard let app = Perception.findApp(named: appName) else {
            return Output(text: "App '\(appName)' is not running.", isError: true)
        }
        let pid = app.processIdentifier
        if settle, states[pid] != nil {
            _ = changesAfterAction(appName: appName, usedIndex: false)
        } else {
            let fresh = take(appName: appName, forceFull: true, maxLines: nil)
            if fresh.isError { return fresh }
        }
        guard let state = states[pid] else {
            return Output(text: "Could not read '\(appName)'.", isError: true)
        }
        var lines = state.lines.map(\.text)
        var note = ""
        if pageOnly, let page = state.lines.firstIndex(where: { $0.fingerprint.hasPrefix("section|web|") }),
           page + 1 < lines.count
        {
            // The page is the "web" heading plus everything indented under it.
            // Open menus, sheets and dialogs sit outside the page in the tree
            // (a dropdown's options, a file picker) and are kept: they are
            // what the next action has to choose from.
            func indent(_ line: String) -> Int { line.prefix { $0 == " " }.count }
            func block(from start: Int) -> Range<Int> {
                let end = lines[(start + 1)...].firstIndex { indent($0) <= indent(lines[start]) } ?? lines.count
                return start..<end
            }
            var kept = Array(lines[block(from: page)])
            for (index, entry) in state.lines.enumerated() where index != page {
                let key = entry.fingerprint
                if key.hasPrefix("section|menu|") || key.hasPrefix("section|sheet|") || key.hasPrefix("section|dialog|") {
                    let range = block(from: index)
                    if !range.overlaps(block(from: page)) { kept += lines[range] }
                }
            }
            lines = kept
            note = "\n(browser toolbar and tabs not shown)"
        }
        if lines.count > maxLines {
            note += "\n(\(lines.count - maxLines) more lines; scroll to see further down the page)"
            lines = Array(lines.prefix(maxLines))
        }
        let header = "\(state.appName) — \"\(clip(state.windowTitle, nameLimit))\""
        return Output(text: header + "\n" + lines.joined(separator: "\n") + note, isError: false)
    }

    // MARK: - Changes after an action

    /// Whether action results carry the UI changes they caused.
    public static let inlineChangesEnabled: Bool = {
        let value = ProcessInfo.processInfo.environment["YOUXPC_INLINE_CHANGES"]?.lowercased()
        return !["off", "0", "false", "no"].contains(value ?? "")
    }()

    private static let maxInlineChangeLines = 40
    /// A window with fewer numbered elements than this (just its title-bar
    /// buttons, typically) has probably not built its accessibility tree.
    private static let sparseTreeThreshold = 10
    private static let settleLimitSeconds: TimeInterval = 1.2

    /// After an action on an app that has a snapshot, wait for its UI to stop
    /// changing and describe what changed since that snapshot. This replaces
    /// the follow-up pc_snapshot call the agent would otherwise make.
    ///
    /// Returns nil when the app has no snapshot to compare against, so agents
    /// that do not use snapshots pay nothing.
    public static func changesAfterAction(appName: String?, usedIndex: Bool) -> String? {
        guard inlineChangesEnabled else { return nil }
        return changes(appName: appName, usedIndex: usedIndex, since: nil)
    }

    // MARK: - Sequences (pc_do)

    /// The screen as it was before a sequence of actions started.
    private static var sequenceStart: (pid: pid_t, state: AppState)?

    /// Name of the app the latest snapshot described.
    public static var latestAppName: String? {
        latestPID.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
    }

    /// Remember the screen before a sequence, taking a first snapshot if the
    /// app has not been looked at yet.
    public static func beginSequence(appName: String) {
        sequenceStart = nil
        guard let app = Perception.findApp(named: appName) else { return }
        let pid = app.processIdentifier
        if states[pid] == nil { _ = take(appName: appName, forceFull: true, maxLines: nil) }
        if let state = states[pid] { sequenceStart = (pid, state) }
    }

    /// Walk the window once, so that names of elements an action has just
    /// made appear can be resolved by the next step.
    public static func refresh(appName: String?) {
        let pid = appName.flatMap { Perception.findApp(named: $0)?.processIdentifier } ?? latestPID
        guard let pid, let known = states[pid],
              let app = NSRunningApplication(processIdentifier: pid),
              AppPolicy.denialReason(for: app) == nil,
              let current = capture(app, inheriting: known, lineBudget: defaultMaxLines)
        else { return }
        states[pid] = current.state
        latestPID = pid
    }

    /// Re-read the window until something named `name` is listed, or `timeout`
    /// passes. An action often makes its result appear a moment later (a menu
    /// opening, a panel switching); the step that follows should wait for the
    /// thing it names instead of acting on a screen that has not caught up.
    @discardableResult
    public static func waitFor(name: String, appName: String?, timeout: TimeInterval) -> Bool {
        let wanted = name.lowercased()
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            refresh(appName: appName)
            let pid = appName.flatMap { Perception.findApp(named: $0)?.processIdentifier } ?? latestPID
            if let pid, let state = states[pid],
               state.entries.values.contains(where: { $0.name.lowercased() == wanted })
            {
                return true
            }
            if Date() >= deadline { return false }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    /// Wait until no menu is listed for the app, or `timeout` passes.
    ///
    /// Choosing from a menu (pressing an item, or Return on the highlighted
    /// one) is finished only when the menu has gone: until then the choice has
    /// not been applied, and touching anything else throws it away. Watching
    /// for a stable screen does not work here, because for the first moments
    /// after the press the open menu is perfectly stable.
    public static func waitForMenuToClose(appName: String?, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            refresh(appName: appName)
            let pid = appName.flatMap { Perception.findApp(named: $0)?.processIdentifier } ?? latestPID
            guard let pid, let state = states[pid],
                  state.lines.contains(where: { $0.fingerprint.hasPrefix("section|menu|") }),
                  Date() < deadline
            else { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    /// Wait until two consecutive walks of the window read the same.
    public static func settle(appName: String?) {
        _ = changes(appName: appName, usedIndex: true, since: nil)
    }

    /// What the whole sequence changed, measured once the screen has settled.
    public static func endSequence(appName: String) -> String? {
        defer { sequenceStart = nil }
        let pid = Perception.findApp(named: appName)?.processIdentifier
        let start = sequenceStart.flatMap { $0.pid == pid ? $0.state : nil }
        return changes(appName: appName, usedIndex: true, since: start)
    }

    /// Wait for the screen to settle and describe how it differs from
    /// `since`, or from the last state the agent was shown when that is nil.
    private static func changes(appName: String?, usedIndex: Bool, since: AppState?) -> String? {
        let pid: pid_t? = if let appName {
            Perception.findApp(named: appName)?.processIdentifier
        } else if usedIndex {
            latestPID
        } else {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
        guard let pid, let baseline = states[pid],
              let app = NSRunningApplication(processIdentifier: pid),
              AppPolicy.denialReason(for: app) == nil
        else { return nil }

        // Settled = two consecutive walks render the same lines.
        let deadline = Date().addingTimeInterval(settleLimitSeconds)
        guard var current = capture(app, inheriting: baseline, lineBudget: defaultMaxLines) else { return nil }
        var settled = false
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            guard let next = capture(app, inheriting: current.state, lineBudget: defaultMaxLines) else { break }
            let same = next.state.lines.count == current.state.lines.count
                && zip(next.state.lines, current.state.lines).allSatisfy { $0.text == $1.text }
            current = next
            if same { settled = true; break }
        }
        states[pid] = current.state
        latestPID = pid

        let reference = since ?? baseline
        if reference.windowTitle != current.state.windowTitle {
            return "window is now \"\(clip(current.state.windowTitle, nameLimit))\"; call pc_snapshot for its contents"
        }
        let diff = diffLines(old: reference.lines, new: current.state.lines)
        if diff.changes.isEmpty {
            return settled ? "no visible change" : "no visible change yet (still updating)"
        }
        var shown = diff.changes.prefix(maxInlineChangeLines).joined(separator: "\n")
        if diff.changes.count > maxInlineChangeLines {
            shown += "\n(\(diff.changes.count - maxInlineChangeLines) more changes; call pc_snapshot)"
        }
        if !settled { shown += "\n(still updating)" }
        return shown
    }

    // MARK: - Capture

    private struct Capture {
        var state: AppState
        var notes: [String]
    }

    /// Walk the focused window of `app`. Numbers already assigned in
    /// `previous` are reused so elements keep their index.
    private static func capture(_ app: NSRunningApplication, inheriting previous: AppState?, lineBudget: Int) -> Capture? {
        guard let window = window(of: app) else { return nil }

        var state = AppState(
            appName: app.localizedName ?? "App",
            windowTitle: stringAttribute(kAXTitleAttribute, of: window) ?? ""
        )
        if let previous {
            state.numbers = previous.numbers
            state.nextNumber = previous.nextNumber
            state.known = previous.known
            state.lastFrame = previous.lastFrame
        }
        var walk = Walk(
            windowFrame: read(window)?.frame,
            deadline: Date().addingTimeInterval(deadlineSeconds),
            lineBudget: lineBudget
        )
        let started = Date()
        visit(window, depth: 0, indent: 0, enclosingName: nil, walk: &walk, state: &state)
        assignNumbers(walk: walk, state: &state)
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        Log.debug("Snapshot of \(state.appName): \(walk.visited) nodes, \(state.lines.count) lines, \(elapsed)ms")

        var notes: [String] = []
        if walk.hitDeadline { notes.append("stopped at the \(Int(deadlineSeconds))s deadline, tree is partial") }
        if walk.hitNodeBudget { notes.append("stopped after \(maxNodes) nodes, tree is partial") }
        if walk.hitLineBudget { notes.append("line limit reached, raise max_lines for more") }
        if walk.skippedOffscreen > 0 { notes.append("offscreen content omitted, scroll to reveal it") }
        return Capture(state: state, notes: notes)
    }

    /// The window a snapshot describes: focused, else main, else the first one.
    private static func window(of app: NSRunningApplication) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        return elementAttribute(kAXFocusedWindowAttribute, of: appElement)
            ?? elementAttribute(kAXMainWindowAttribute, of: appElement)
            ?? (arrayAttribute(kAXWindowsAttribute, of: appElement)?.first)
    }

    /// Browsers whose page content has already been requested.
    private static var webContentRequested: Set<pid_t> = []

    /// If the window holds a web area that the walk saw nothing inside, ask
    /// for it and walk again once the page's tree has arrived. Reading the
    /// area's URL is what triggers Chromium to build it. Done once per app.
    private static func wakeWebContent(
        of app: NSRunningApplication, current: Capture, inheriting previous: AppState?, lineBudget: Int
    ) -> Capture? {
        let pid = app.processIdentifier
        guard !webContentRequested.contains(pid) else { return nil }
        webContentRequested.insert(pid)

        func hasPageContent(_ capture: Capture) -> Bool {
            guard let start = capture.state.lines.firstIndex(where: { $0.fingerprint.hasPrefix("section|web|") })
            else { return false }
            return start + 1 < capture.state.lines.count
        }
        guard !hasPageContent(current) else { return nil }
        // Same window the walk used. The focused-window attribute alone can be
        // empty for an app that is not in front.
        func findWebArea() -> Element? {
            window(of: app).flatMap { Perception.findWebArea(in: Element($0)) }
        }
        // Chromium switches page accessibility on when a client reads the role of
        // its application element. Walking the window does not do that, so ask
        // here; the web area then appears a moment later.
        _ = stringAttribute(kAXRoleAttribute, of: AXUIElementCreateApplication(pid))
        var found = findWebArea()
        if found == nil, embedsChromium(app) {
            // Not there yet. Looking once and giving up loses this race on a busy
            // machine and leaves a snapshot with a toolbar and no page.
            requestFullWebState(for: app)
            for _ in 0..<20 where found == nil {
                Thread.sleep(forTimeInterval: 0.1)
                found = findWebArea()
            }
            if found == nil {
                webContentRequested.remove(pid)   // look again on the next snapshot
                Log.info("\(app.localizedName ?? "Browser") has not exposed a page yet")
                var partial = current
                partial.notes.append("the page is not available yet, only the browser's own controls; take another snapshot")
                return partial
            }
        }
        guard let webArea = found else { return nil }
        _ = webArea.url()
        Log.info("Requested page content from \(app.localizedName ?? "browser")")
        requestFullWebState(for: app)

        var latest: Capture?
        for _ in 0..<8 {
            Thread.sleep(forTimeInterval: 0.25)
            guard let retried = capture(app, inheriting: previous, lineBudget: lineBudget) else { continue }
            latest = retried
            if hasPageContent(retried) { break }
        }
        // The fuller mode takes a while to reach the page, and until it does a
        // checkbox does not say whether it is ticked. Wait for that only when
        // the page has such a control; a page without one is returned at once.
        if enhancedApps.contains(pid) {
            func stateMissing(_ capture: Capture?) -> Bool {
                capture?.state.lines.contains { $0.text.contains(unreportedState) } ?? false
            }
            for _ in 0..<10 where stateMissing(latest) {
                Thread.sleep(forTimeInterval: 0.25)
                if let again = capture(app, inheriting: previous, lineBudget: lineBudget) { latest = again }
            }
        }
        return latest
    }

    /// Chromium-based apps (Chrome, Brave, Edge, Electron, CEF) ship their engine
    /// as "<Name> Framework.framework" inside the app bundle.
    private static func embedsChromium(_ app: NSRunningApplication) -> Bool {
        guard let bundle = app.bundleURL else { return false }
        let frameworks = bundle.appendingPathComponent("Contents/Frameworks").path
        let names = (try? FileManager.default.contentsOfDirectory(atPath: frameworks)) ?? []
        return names.contains { $0.hasSuffix(" Framework.framework") }
    }

    /// Browsers switched to their fuller accessibility mode, to be switched back.
    private static var enhancedApps: Set<pid_t> = []

    private static let enhancedModeEnabled: Bool = {
        let value = ProcessInfo.processInfo.environment["YOUXPC_ENHANCED_AX"]?.lowercased()
        return !["off", "0", "false", "no"].contains(value ?? "")
    }()

    /// Chromium reports whether a page checkbox is ticked only in its fuller
    /// accessibility mode, the one screen readers switch on by setting
    /// AXEnhancedUserInterface. Without it the value is empty and an agent
    /// cannot tell a ticked box from an unticked one. The setter reports an
    /// error even when it takes effect, so the result is not checked. The
    /// mode can change how some window managers treat the app, so it is
    /// switched back off when the server stops. YOUXPC_ENHANCED_AX=off skips it.
    private static func requestFullWebState(for app: NSRunningApplication) {
        guard enhancedModeEnabled else { return }
        let pid = app.processIdentifier
        let element = AXUIElementCreateApplication(pid)
        var current: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXEnhancedUserInterface" as CFString, &current)
        if (current as? Bool) == true { return }   // someone else's setting; leave it alone on exit
        AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        enhancedApps.insert(pid)
    }

    /// Undo what this server changed in other apps. Called on shutdown.
    public static func restoreApps() {
        for pid in enhancedApps {
            AXUIElementSetAttributeValue(
                AXUIElementCreateApplication(pid), "AXEnhancedUserInterface" as CFString, kCFBooleanFalse
            )
        }
        enhancedApps.removeAll()
    }

    /// Apps already asked to expose their full accessibility tree.
    private static var accessibilityRequested: Set<pid_t> = []

    /// Ask an Electron or Chromium app to build its accessibility tree.
    /// AXManualAccessibility is the switch Electron documents for this. It is
    /// a no-op error on apps that do not know it. Returns true when the app
    /// accepted it, in which case the tree is worth walking again.
    private static func requestFullAccessibility(for app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        guard !accessibilityRequested.contains(pid) else { return false }
        accessibilityRequested.insert(pid)
        let appElement = AXUIElementCreateApplication(pid)
        let accepted = AXUIElementSetAttributeValue(
            appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue
        ) == .success
        guard accepted else { return false }
        Log.info("Requested full accessibility tree from \(app.localizedName ?? "app")")
        Thread.sleep(forTimeInterval: 0.5)
        return true
    }

    // MARK: - Lookup by name

    /// Find an element by name in the latest snapshot of an app, taking a
    /// snapshot first if there is none. An exact name wins over a name that
    /// merely contains the query; ties go to the lowest number. This is what
    /// `query:` arguments resolve through, so a click by name hits the same
    /// element the agent saw in its snapshot.
    public static func find(query: String, role: String?, appName: String?) -> Entry? {
        let app: NSRunningApplication? = if let appName {
            Perception.findApp(named: appName)
        } else if let latestPID {
            NSRunningApplication(processIdentifier: latestPID)
        } else {
            NSWorkspace.shared.frontmostApplication
        }
        guard let app else { return nil }
        let pid = app.processIdentifier
        if states[pid] == nil {
            _ = take(appName: appName ?? app.localizedName, forceFull: true, maxLines: nil)
        }
        guard let state = states[pid] else { return nil }

        let wanted = query.lowercased()
        let wantedRole = role.map { $0.hasPrefix("AX") ? $0 : "AX" + $0 }?.lowercased()
        let candidates = state.entries.values
            .filter { wantedRole == nil || $0.role.lowercased() == wantedRole }
            .sorted { $0.index < $1.index }
        // Last resort: the query is a role word as the snapshot prints it ("textarea",
        // "text field") and exactly one element has that role. Unnamed fields are
        // listed with nothing but their role, so that word is all a caller can quote.
        let wantedWord = wanted.replacingOccurrences(of: " ", with: "")
        let ofThatRole = candidates.filter { shortRole($0.role) == wantedWord }
        let match = candidates.first { $0.name.lowercased() == wanted }
            ?? candidates.first { $0.name.lowercased().hasPrefix(wanted) }
            ?? candidates.first { $0.name.lowercased().contains(wanted) }
            ?? (ofThatRole.count == 1 ? ofThatRole.first : nil)
        guard let match, stringAttribute(kAXRoleAttribute, of: match.element) == match.role else { return nil }
        return match
    }

    /// The element's name as a snapshot taken now would list it.
    public static func currentName(of element: AXUIElement) -> String? {
        guard let node = read(element) else { return nil }
        let name = clip(oneLine(node.title ?? node.description ?? firstText(in: node.children, depth: 3) ?? ""), nameLimit)
        return name.isEmpty ? nil : name
    }

    // MARK: - Names shared by several elements

    /// When more than one element on screen carries exactly this name, a
    /// request by name cannot say which is meant. Refuse, and list each one
    /// with its id and the row or section it sits in.
    public static func ambiguity(named query: String, role: String?, appName: String?) -> ToolResult? {
        let pid: pid_t? = appName.flatMap { Perception.findApp(named: $0)?.processIdentifier } ?? latestPID
        guard let pid, let state = states[pid] else { return nil }
        let wanted = query.lowercased()
        let wantedRole = role.map { $0.hasPrefix("AX") ? $0 : "AX" + $0 }?.lowercased()
        let matches = state.entries.values
            .filter { $0.name.lowercased() == wanted && (wantedRole == nil || $0.role.lowercased() == wantedRole) }
            .filter { stringAttribute(kAXRoleAttribute, of: $0.element) == $0.role }   // still on screen
            .sorted { $0.index < $1.index }
        guard matches.count > 1 else { return nil }

        let listed = matches.prefix(8).map { entry -> String in
            let place = enclosingLine(ofElement: entry.index, in: state)
            return "e\(entry.index)" + (place.map { " in \($0)" } ?? "")
        }
        let more = matches.count > listed.count ? "; and \(matches.count - listed.count) more" : ""
        return ToolResult(
            success: false,
            error: "\(matches.count) items are named \"\(clip(query, nameLimit))\". Nothing was done.",
            suggestion: "Use the id of the one you mean: " + listed.joined(separator: "; ") + more + "."
        )
    }

    /// The heading of the table row an element was listed in, if it sits in one.
    /// Action results repeat it, so "Approve" pressed in the wrong row reads as
    /// such before the agent moves on.
    public static func row(ofElement number: Int, appName: String?) -> String? {
        let pid: pid_t? = appName.flatMap { Perception.findApp(named: $0)?.processIdentifier } ?? latestPID
        guard let pid, let state = states[pid],
              let line = enclosingLine(ofElement: number, in: state), line.hasPrefix("row \"")
        else { return nil }
        let heading = line.dropFirst("row \"".count)
        return String(heading.hasSuffix("\"") ? heading.dropLast() : heading)
    }

    /// The heading line an element is listed under (its row, or its section).
    private static func enclosingLine(ofElement number: Int, in state: AppState) -> String? {
        func indent(_ text: String) -> Int { text.prefix { $0 == " " }.count }
        let marker = "[e\(number)] "
        guard let position = state.lines.firstIndex(where: { $0.text.trimmingCharacters(in: .whitespaces).hasPrefix(marker) })
        else { return nil }
        let own = indent(state.lines[position].text)
        for line in state.lines[..<position].reversed() where indent(line.text) < own {
            return clip(line.text.trimmingCharacters(in: .whitespaces), 48)
        }
        return nil
    }

    // MARK: - Bare numbers

    /// A model that sends 7 instead of e7 may mean the id or the label. When
    /// both readings exist and point at different elements, refuse and spell
    /// out the two options instead of guessing.
    public static func ambiguity(bareNumber number: Int, appName: String?) -> ToolResult? {
        let pid: pid_t? = if let appName {
            Perception.findApp(named: appName)?.processIdentifier
        } else {
            latestPID
        }
        guard let pid, let state = states[pid] else { return nil }
        let label = String(number)
        guard let labelled = state.entries.values.first(where: { $0.name == label }),
              labelled.index != number
        else { return nil }
        let byID = state.entries[number].map { "e\(number) is the \(shortRole($0.role)) \"\($0.name)\"" }
            ?? "there is no e\(number)"
        return ToolResult(
            success: false,
            error: "\(number) is ambiguous: \(byID), and the \(shortRole(labelled.role)) labelled \"\(label)\" is e\(labelled.index)",
            suggestion: "Pass the id with its letter, for example e\(labelled.index)"
        )
    }

    // MARK: - Lookup for action tools

    /// Result of resolving an `index` argument.
    public enum Resolution {
        case found(Entry, pid: pid_t)
        case failed(ToolResult)
    }

    /// Resolve a number from the latest snapshot of `appName` (or of the most
    /// recently snapshotted app) and confirm the element still exists.
    public static func resolve(index: Int, appName: String?) -> Resolution {
        let pid: pid_t? = if let appName {
            Perception.findApp(named: appName)?.processIdentifier
        } else {
            latestPID
        }
        guard let pid, let state = states[pid] else {
            return .failed(ToolResult(
                success: false,
                error: "No snapshot to resolve e\(index) against",
                suggestion: "Call pc_snapshot first, then use the numbers it returns"
            ))
        }
        guard let entry = state.entries[index] else {
            // The usual cause when a label matches: the label was used as the id.
            if let labelled = state.entries.values.first(where: { $0.name == String(index) }) {
                return .failed(ToolResult(
                    success: false,
                    error: "Nothing has the id e\(index). Nothing was done.",
                    suggestion: "The \(shortRole(labelled.role)) labelled \"\(index)\" has the id e\(labelled.index). Use that id, or its name."
                ))
            }
            return .failed(ToolResult(
                success: false,
                error: "e\(index) is not in the latest snapshot of \(state.appName)",
                suggestion: "Call pc_snapshot again; the UI has probably changed"
            ))
        }
        // A dead element fails this read; a recycled one reports another role.
        // Apps often rebuild an element that looks the same (a menu that was
        // redrawn, a list that refreshed). A fresh walk gives a replacement in
        // the same place, with the same role and name, the same id.
        if stringAttribute(kAXRoleAttribute, of: entry.element) != entry.role,
           let app = NSRunningApplication(processIdentifier: pid),
           let fresh = capture(app, inheriting: state, lineBudget: defaultMaxLines)
        {
            states[pid] = fresh.state
            if let replacement = fresh.state.entries[index], replacement.role == entry.role,
               replacement.name == entry.name,
               stringAttribute(kAXRoleAttribute, of: replacement.element) == replacement.role
            {
                return .found(replacement, pid: pid)
            }
        }
        guard stringAttribute(kAXRoleAttribute, of: entry.element) == entry.role else {
            return .failed(ToolResult(
                success: false,
                error: "[e\(index)] \(shortRole(entry.role)) \"\(entry.name)\" no longer exists",
                suggestion: "Call pc_snapshot again to get current numbers"
            ))
        }
        return .found(entry, pid: pid)
    }

    // MARK: - Walk

    private struct Walk {
        let windowFrame: CGRect?
        let deadline: Date
        let lineBudget: Int
        var visited = 0
        var skippedOffscreen = 0
        var hitDeadline = false
        var hitNodeBudget = false
        var hitLineBudget = false
        /// Occurrence counter per role+name, to tell identical elements apart.
        var seen: [String: Int] = [:]
        /// Elements already walked. Some trees expose one element under two
        /// parents (a table's cells under its rows and again under its columns).
        var walked: Set<AXUIElement> = []
        /// A row is headed by its first text; that text is then not repeated below it.
        var rowHeading: String?
        /// Heading of the row being walked, if any. Part of an element's fingerprint.
        var currentRow: String?
        /// Interactive elements in document order, waiting for their ids.
        var pending: [Pending] = []

        var exhausted: Bool { hitDeadline || hitNodeBudget || hitLineBudget }
    }

    private struct Pending {
        let line: Int
        let element: AXUIElement
        let role: String
        let name: String
        let frame: CGRect?
        let fingerprint: String
        /// The only element with this role and name in a named row.
        let anchored: Bool
        let prefix: String
        let detail: String
    }

    private struct Node {
        var role = ""
        var title: String?
        var description: String?
        var value: String?
        var enabled = true
        var focused = false
        var selected = false
        var subrole: String?
        var frame: CGRect?
        var children: [AXUIElement] = []
    }

    private static func visit(
        _ element: AXUIElement,
        depth: Int,
        indent: Int,
        enclosingName: String?,
        walk: inout Walk,
        state: inout AppState
    ) {
        guard !walk.exhausted, depth < maxDepth else { return }
        if walk.visited >= maxNodes { walk.hitNodeBudget = true; return }
        // Checked on every node: when an app stops answering, each call can block for the
        // whole messaging timeout, so a sparser check would overrun the deadline by minutes.
        if Date() > walk.deadline { walk.hitDeadline = true; return }
        walk.visited += 1
        guard walk.walked.insert(element).inserted else { return }

        guard let node = read(element) else { return }
        // A table's columns hold the same cells as its rows. Listing both doubles
        // every control and gives the second copy a different id.
        if node.role == "AXColumn" { return }

        // Skip anything fully outside the window, with its whole subtree.
        // Zero-sized layout containers are kept: their children can be visible.
        if let frame = node.frame, let window = walk.windowFrame,
           frame.width > 1, frame.height > 1, !frame.intersects(window)
        {
            walk.skippedOffscreen += 1
            return
        }

        let childIndent = indent
        var childEnclosing = enclosingName

        if let subrole = node.subrole, windowControlSubroles.contains(subrole) {
            return
        }
        if interactiveRoles.contains(node.role) {
            var name = node.title ?? node.description ?? ""
            if name.isEmpty { name = firstText(in: node.children, depth: 3) ?? "" }
            name = clip(oneLine(name), nameLimit)
            // Text boxes are often titled after their own content. Using that
            // as the name would renumber the box every time its text changed.
            if textEntryRoles.contains(node.role), let value = node.value,
               !name.isEmpty, value.lowercased().hasPrefix(name.lowercased().replacingOccurrences(of: "…", with: ""))
            {
                name = ""
            }
            // A dropdown in a web page carries a second, collapsed copy of its
            // options as menu items with no name. They cannot be told apart or
            // usefully pressed; the named copy appears when the dropdown opens.
            if !(node.role == "AXMenuItem" && name.isEmpty) {
                emitInteractive(element, node: node, name: name, indent: indent, walk: &walk, state: &state)
            }
            childEnclosing = name
        } else if node.role == "AXHeading" {
            // A heading's AXValue is its level, not its text. The text is the
            // title or, more often on the web, a child static text.
            let text = oneLine(node.title ?? node.description ?? firstText(in: node.children, depth: 3) ?? "")
            if !text.isEmpty {
                let shown = clip(text, textLimit)
                append(pad(indent) + "# \"\(shown)\"", key: "heading|" + shown, walk: &walk, state: &state)
                childEnclosing = text
            }
        } else if node.role == "AXStaticText" {
            let text = oneLine(node.value ?? node.title ?? node.description ?? "")
            if text == walk.rowHeading {
                walk.rowHeading = nil   // already shown on the row's own line
            } else if !text.isEmpty, !isRepeat(text, of: enclosingName) {
                let shown = clip(text, textLimit)
                append(pad(indent) + "\"\(shown)\"", key: "text|" + shown, walk: &walk, state: &state)
            }
        } else if node.role == "AXRow" {
            // One heading line per row, named after the row's first text, with the
            // rest of the row indented under it. Without this, six rows that each
            // hold an "Approve" button are a flat run of identical lines.
            let heading = oneLine(node.title ?? node.description ?? firstText(in: node.children, depth: 4) ?? "")
            let shown = clip(heading, textLimit)
            let linesBefore = state.lines.count
            append(pad(indent) + "row" + (shown.isEmpty ? "" : " \"\(shown)\""), key: "row|" + shown, walk: &walk, state: &state)
            walk.rowHeading = heading.isEmpty ? nil : heading
            let outerRow = walk.currentRow
            walk.currentRow = heading.isEmpty ? nil : heading
            for child in node.children {
                if walk.exhausted { break }
                visit(child, depth: depth + 1, indent: indent + 1, enclosingName: enclosingName, walk: &walk, state: &state)
            }
            walk.rowHeading = nil
            walk.currentRow = outerRow
            // A row with nothing but its heading text reads better as plain text.
            if state.lines.count == linesBefore + 1, !walk.exhausted {
                state.lines[linesBefore].text = shown.isEmpty ? "" : pad(indent) + "\"\(shown)\""
                if shown.isEmpty { state.lines.removeLast() }
            }
            return
        } else if let label = sectionRoles[node.role] {
            let title = clip(oneLine(node.title ?? node.description ?? ""), nameLimit)
            let line = pad(indent) + label + (title.isEmpty ? "" : " \"\(title)\"")
            let linesBefore = state.lines.count
            append(line, key: "section|" + label + "|" + title, walk: &walk, state: &state)
            for child in node.children {
                if walk.exhausted { break }
                visit(child, depth: depth + 1, indent: indent + 1, enclosingName: childEnclosing, walk: &walk, state: &state)
            }
            // A heading with nothing under it is noise. The web area is kept: an
            // empty one is how a page that has not been built yet is recognised.
            if state.lines.count == linesBefore + 1, node.role != "AXWebArea", !walk.exhausted {
                state.lines.removeLast()
                walk.seen["section|" + label + "|" + title, default: 1] -= 1
            }
            return
        }

        for child in node.children {
            if walk.exhausted { break }
            visit(child, depth: depth + 1, indent: childIndent, enclosingName: childEnclosing, walk: &walk, state: &state)
        }
    }

    private static func emitInteractive(
        _ element: AXUIElement,
        node: Node,
        name: String,
        indent: Int,
        walk: inout Walk,
        state: inout AppState
    ) {
        // Inside a named row the fingerprint includes the row, so "the Delete
        // button of row draft-c1" stays the same thing when other rows come and go.
        let base = node.role + "|" + name + (walk.currentRow.map { "|row:" + $0 } ?? "")
        let occurrence = walk.seen[base, default: 0]
        walk.seen[base] = occurrence + 1

        var detail = shortRole(node.role)
        if !name.isEmpty { detail += " \"\(name)\"" }
        if node.role == "AXSecureTextField" {
            // Never echo a password field's contents.
            if let value = node.value, !value.isEmpty { detail += " = (hidden)" }
        } else if valueRoles.contains(node.role), let value = node.value {
            let shown = clip(oneLine(value), valueLimit)
            if !shown.isEmpty, shown != name { detail += " = \"\(shown)\"" }
        } else if node.role == "AXCheckBox" || node.role == "AXSwitch" || node.role == "AXToggle" {
            // Say all three cases. Some browsers report no value at all for a
            // page checkbox; printing nothing there reads as "unchecked" and
            // an agent then clicks it again and undoes its own work.
            switch node.value {
            case "1": detail += " (checked)"
            case "0": detail += " (unchecked)"
            case "2": detail += " (mixed)"
            default: detail += " " + unreportedState
            }
        }
        // A radio button reports its choice as a value, not as a selection.
        if node.selected || (node.role == "AXRadioButton" && node.value == "1") { detail += " (selected)" }
        if node.focused { detail += " (focused)" }
        if !node.enabled { detail += " (disabled)" }

        guard walk.lineBudget > state.lines.count else { walk.hitLineBudget = true; return }
        // The id is filled in by assignNumbers once the whole window has been walked.
        walk.pending.append(Pending(
            line: state.lines.count, element: element, role: node.role, name: name, frame: node.frame,
            fingerprint: base + "|" + String(occurrence), anchored: walk.currentRow != nil && occurrence == 0,
            prefix: pad(indent), detail: detail
        ))
        state.lines.append(("", ""))
    }

    /// Give every interactive element found by a walk its id.
    ///
    /// An id belongs to an element, not to a position. The rule used before
    /// (role + name + how many of those came earlier) let an id change hands:
    /// with six "Approve" buttons, removing the first row moved every later
    /// button up one id, and the id an agent had read for one row then pressed
    /// the button of another, with nothing in the change report to say so.
    ///
    /// 1. An element that has had an id in this session keeps it, whether or
    ///    not it was on screen in the snapshot before this one.
    /// 2. An element not seen before takes the id last used for the same role
    ///    and name when that is safe: either it is the only such element in a
    ///    named row (so the row identifies it), or the id's element was last
    ///    seen in the same place. That keeps ids steady when an app rebuilds
    ///    its elements or hands out a new handle for the same control.
    /// 3. Otherwise the element is new and gets a new id. An id whose element
    ///    is gone is not handed to something else, so using it fails with a
    ///    clear message instead of acting on a neighbour.
    private static func assignNumbers(walk: Walk, state: inout AppState) {
        var assigned: [Int?] = Array(repeating: nil, count: walk.pending.count)
        var claimed: Set<Int> = []
        for (position, item) in walk.pending.enumerated() {
            if let own = state.known[item.element], claimed.insert(own).inserted { assigned[position] = own }
        }
        // A new id is never a number that is also a label on screen. Next to a
        // key labelled 5, an id e5 belonging to some other key gets pressed by
        // mistake; with no e5 at all the same mistake fails and can be corrected.
        let numericLabels = Set(walk.pending.compactMap { Int($0.name) })
        for (position, item) in walk.pending.enumerated() where assigned[position] == nil {
            if let earlier = state.numbers[item.fingerprint], !claimed.contains(earlier),
               item.anchored || sameFrame(state.lastFrame[earlier], item.frame)
            {
                assigned[position] = earlier
                claimed.insert(earlier)
            } else {
                while numericLabels.contains(state.nextNumber) { state.nextNumber += 1 }
                assigned[position] = state.nextNumber
                claimed.insert(state.nextNumber)
                state.nextNumber += 1
            }
        }
        // Bound the memory of elements seen: keep what is on screen now.
        if state.known.count > maxKnownElements {
            state.known.removeAll(keepingCapacity: true)
            state.lastFrame.removeAll(keepingCapacity: true)
        }
        for (item, number) in zip(walk.pending, assigned) {
            guard let number else { continue }
            state.numbers[item.fingerprint] = number
            state.known[item.element] = number
            if let frame = item.frame { state.lastFrame[number] = frame }
            state.lines[item.line] = ("e|\(number)", item.prefix + "[e\(number)] " + item.detail)
            state.entries[number] = Entry(index: number, element: item.element, role: item.role, name: item.name, frame: item.frame)
        }
    }

    private static func sameFrame(_ first: CGRect?, _ second: CGRect?) -> Bool {
        guard let first, let second else { return false }
        return abs(first.minX - second.minX) < 1.5 && abs(first.minY - second.minY) < 1.5
            && abs(first.width - second.width) < 1.5 && abs(first.height - second.height) < 1.5
    }

    /// Append an unnumbered line (text or section heading).
    private static func append(_ line: String, key: String, walk: inout Walk, state: inout AppState) {
        guard walk.lineBudget > state.lines.count else { walk.hitLineBudget = true; return }
        let occurrence = walk.seen[key, default: 0]
        walk.seen[key] = occurrence + 1
        state.lines.append((key + "|" + String(occurrence), line))
    }

    /// First static text under `elements`, for controls that carry no name of their own.
    private static func firstText(in elements: [AXUIElement], depth: Int) -> String? {
        guard depth > 0 else { return nil }
        for element in elements.prefix(12) {
            guard let node = read(element) else { continue }
            if node.role == "AXStaticText" || node.role == "AXImage" {
                let text = node.value ?? node.title ?? node.description ?? ""
                if !text.isEmpty { return text }
            }
            if let nested = firstText(in: node.children, depth: depth - 1) { return nested }
        }
        return nil
    }

    // MARK: - Diff

    private static func diffLines(
        old: [(fingerprint: String, text: String)],
        new: [(fingerprint: String, text: String)]
    ) -> (changes: [String], unchanged: Int) {
        let oldByKey = Dictionary(old.map { ($0.fingerprint, $0.text) }, uniquingKeysWith: { first, _ in first })
        let newKeys = Set(new.map(\.fingerprint))
        var changes: [String] = []
        var unchanged = 0

        for line in new {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            if let before = oldByKey[line.fingerprint] {
                if before.trimmingCharacters(in: .whitespaces) == text {
                    unchanged += 1
                } else {
                    changes.append("~ " + text)
                }
            } else {
                changes.append("+ " + text)
            }
        }
        for line in old where !newKeys.contains(line.fingerprint) {
            changes.append("- " + line.text.trimmingCharacters(in: .whitespaces))
        }
        return (changes, unchanged)
    }

    // MARK: - Batched AX read

    /// Read every attribute a snapshot needs in a single round trip to the app.
    private static func read(_ element: AXUIElement) -> Node? {
        var raw: CFArray?
        let status = AXUIElementCopyMultipleAttributeValues(
            element, attributeNames as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &raw
        )
        guard status == .success, let values = raw as? [Any], values.count == attributeNames.count else {
            return nil
        }

        var node = Node()
        node.role = values[0] as? String ?? ""
        node.title = nonEmpty(values[1] as? String)
        node.description = nonEmpty(values[2] as? String)
        if let string = values[3] as? String {
            node.value = nonEmpty(string)
        } else if let number = values[3] as? NSNumber {
            node.value = number.stringValue
        }
        node.enabled = values[4] as? Bool ?? true
        node.focused = values[5] as? Bool ?? false
        if let origin = point(values[6]), let size = size(values[7]) {
            node.frame = CGRect(origin: origin, size: size)
        }
        if let children = values[8] as? [AnyObject] {
            node.children = children.compactMap { child in
                CFGetTypeID(child) == AXUIElementGetTypeID() ? (child as! AXUIElement) : nil
            }
        }
        node.selected = values[9] as? Bool ?? false
        node.subrole = values[10] as? String
        return node
    }

    private static func point(_ value: Any) -> CGPoint? {
        let object = value as AnyObject
        guard CFGetTypeID(object) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        // Type checked against AXValueGetTypeID above.
        return AXValueGetValue(object as! AXValue, .cgPoint, &point) ? point : nil
    }

    private static func size(_ value: Any) -> CGSize? {
        let object = value as AnyObject
        guard CFGetTypeID(object) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        // Type checked against AXValueGetTypeID above.
        return AXValueGetValue(object as! AXValue, .cgSize, &size) ? size : nil
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

    private static func arrayAttribute(_ name: String, of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let items = value as? [AnyObject]
        else { return nil }
        return items.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }

    // MARK: - Text helpers

    static func shortRole(_ role: String) -> String {
        (role.hasPrefix("AX") ? String(role.dropFirst(2)) : role).lowercased()
    }

    private static func pad(_ indent: Int) -> String {
        String(repeating: "  ", count: indent)
    }

    private static func suffix(_ notes: [String]) -> String {
        notes.isEmpty ? "" : "\n(" + notes.joined(separator: "; ") + ")"
    }

    private static func nonEmpty(_ string: String?) -> String? {
        guard let string, !string.isEmpty else { return nil }
        return string
    }

    private static func oneLine(_ string: String) -> String {
        string.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }

    private static func clip(_ string: String, _ limit: Int) -> String {
        string.count > limit ? String(string.prefix(limit)) + "…" : string
    }

    /// True when `text` only repeats the label of the control it sits inside.
    private static func isRepeat(_ text: String, of enclosing: String?) -> Bool {
        guard let enclosing, !enclosing.isEmpty else { return false }
        return enclosing == text || enclosing.hasPrefix(text) || text.hasPrefix(enclosing)
    }
}

// AppPolicy.swift - Which apps the agent may see and operate
//
// Accessibility access is all-or-nothing at the OS level, so the narrowing has
// to happen here. Policy is keyed on bundle identifiers, never display names
// (names are matched by substring elsewhere and are trivially spoofed).
//
// Default: everything is allowed except
//   - the app hosting this server, so the agent cannot click through its own
//     permission prompts or settings,
//   - system security surfaces (permission dialogs, System Settings, login),
//   - password managers and Keychain,
//   - terminal emulators, which would turn UI access into shell access.
//
// Configuration (environment, typically set in the MCP server entry):
//   YOUXPC_ALLOW_APPS  comma-separated bundle IDs. When set, ONLY these apps are
//                     allowed, and they are allowed even if denied by default.
//   YOUXPC_DENY_APPS   comma-separated bundle IDs added to the default deny list.
//   YOUXPC_APP_POLICY=off  disables all checks.
//
// Enforced in MCPDispatch (every tool call) and RecipeEngine (every step).

import AppKit
import ApplicationServices
import Foundation

/// Decides whether a tool call may touch a given application.
public enum AppPolicy {

    public static let isEnabled: Bool = {
        let value = ProcessInfo.processInfo.environment["YOUXPC_APP_POLICY"]?.lowercased()
        return !["off", "0", "false", "no"].contains(value ?? "")
    }()

    /// Bundle-ID families denied unless explicitly allowed. An entry matches
    /// itself and anything below it ("com.1password" covers "com.1password.1password").
    private static let defaultDeny: [(family: String, reason: String)] = [
        ("com.apple.SecurityAgent", "a system security prompt"),
        ("com.apple.UserNotificationCenter", "a system permission prompt"),
        ("com.apple.accessibility.universalAccessAuthWarn", "a system permission prompt"),
        ("com.apple.loginwindow", "the login window"),
        ("com.apple.systempreferences", "System Settings"),
        ("com.apple.keychainaccess", "Keychain Access"),
        ("com.apple.Passwords", "a password manager"),
        ("com.1password", "a password manager"),
        ("com.agilebits", "a password manager"),
        ("com.bitwarden", "a password manager"),
        ("com.lastpass", "a password manager"),
        ("com.dashlane", "a password manager"),
        ("org.keepassxc", "a password manager"),
        ("me.proton.pass", "a password manager"),
        ("com.apple.Terminal", "a terminal"),
        ("com.googlecode.iterm2", "a terminal"),
        ("dev.warp", "a terminal"),
        ("com.mitchellh.ghostty", "a terminal"),
        ("net.kovidgoyal.kitty", "a terminal"),
        ("co.zeit.hyper", "a terminal"),
        ("com.github.wez.wezterm", "a terminal"),
        ("org.alacritty", "a terminal"),
        ("io.alacritty", "a terminal"),
    ]

    private static let allowList: [String]? = list(from: "YOUXPC_ALLOW_APPS")
    private static let extraDeny: [String] = list(from: "YOUXPC_DENY_APPS") ?? []

    /// Bundle IDs of the apps that launched this process (e.g. the agent's
    /// desktop app). Resolved once by walking parent processes.
    private static let hostBundleIDs: Set<String> = {
        var ids: Set<String> = []
        var pid = getppid()
        for _ in 0..<12 where pid > 1 {
            if let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier {
                ids.insert(id.lowercased())
            }
            guard let parent = parentPID(of: pid), parent != pid else { break }
            pid = parent
        }
        return ids
    }()

    // MARK: - Checks

    /// Reason this app is off limits, or nil when it may be used.
    public static func denialReason(for app: NSRunningApplication) -> String? {
        guard isEnabled else { return nil }
        guard let bundleID = app.bundleIdentifier?.lowercased() else {
            // No bundle ID: cannot be allow-listed, and is not a known sensitive app.
            return allowList == nil ? nil : "it has no bundle identifier and an allowlist is active"
        }
        if let allowList {
            return allowList.contains { matches(bundleID, family: $0) } ? nil : "it is not in YOUXPC_ALLOW_APPS"
        }
        if hostBundleIDs.contains(bundleID) {
            return "it is the app hosting this agent"
        }
        if let hit = defaultDeny.first(where: { matches(bundleID, family: $0.family) }) {
            return "it is \(hit.reason)"
        }
        if extraDeny.contains(where: { matches(bundleID, family: $0) }) {
            return "it is listed in YOUXPC_DENY_APPS"
        }
        return nil
    }

    /// Check an app named in a tool call. A nil name means the frontmost app.
    /// Returns a failed ToolResult when blocked, nil when allowed or not running
    /// (a missing app is reported by the tool itself).
    public static func denial(appName: String?) -> ToolResult? {
        guard isEnabled else { return nil }
        let app: NSRunningApplication? = if let appName {
            Perception.findApp(named: appName)
        } else {
            NSWorkspace.shared.frontmostApplication
        }
        guard let app, let reason = denialReason(for: app) else { return nil }
        return blocked(app, reason: reason)
    }

    /// Check whichever app owns the UI at a screen point.
    public static func denial(at point: CGPoint) -> ToolResult? {
        guard isEnabled else { return nil }
        var element: AXUIElement?
        var pid: pid_t = 0
        guard AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element
        ) == .success,
            let element,
            AXUIElementGetPid(element, &pid) == .success,
            let app = NSRunningApplication(processIdentifier: pid),
            let reason = denialReason(for: app)
        else { return nil }
        return blocked(app, reason: reason)
    }

    /// Gate for one MCP tool call. Looks at the `app` argument (frontmost app
    /// when the tool is app-scoped and none was given) and at any coordinates.
    public static func check(tool: String, args: [String: Any]) -> ToolResult? {
        guard isEnabled else { return nil }
        let appName = args["app"] as? String

        // An `index` points into a snapshot, and taking that snapshot already
        // passed this check for its app. The frontmost app is irrelevant then.
        let usesSnapshot = appName == nil && args["index"] != nil

        if appName != nil || (frontmostScopedTools.contains(tool) && !usesSnapshot) {
            if let denied = denial(appName: appName) { return denied }
        }
        // Coordinates can land on a different app than the named or frontmost one.
        if appName == nil, !usesSnapshot {
            for (xKey, yKey) in [("x", "y"), ("from_x", "from_y"), ("to_x", "to_y")] {
                if let x = number(args[xKey]), let y = number(args[yKey]),
                   let denied = denial(at: CGPoint(x: x, y: y))
                {
                    return denied
                }
            }
        }
        return nil
    }

    /// Tools that act on the frontmost app when no `app` is passed.
    private static let frontmostScopedTools: Set<String> = [
        "pc_context", "pc_snapshot", "pc_find", "pc_read", "pc_inspect", "pc_screenshot",
        "pc_annotate", "pc_ground", "pc_parse_screen",
        "pc_click", "pc_type", "pc_press", "pc_hotkey", "pc_scroll",
        "pc_hover", "pc_long_press", "pc_drag", "pc_wait",
    ]

    // MARK: - Helpers

    private static func blocked(_ app: NSRunningApplication, reason: String) -> ToolResult {
        let name = app.localizedName ?? "app"
        let bundleID = app.bundleIdentifier ?? "unknown"
        return ToolResult(
            success: false,
            error: "'\(name)' (\(bundleID)) is blocked by the YouxPC app policy because \(reason).",
            suggestion: "Do not look for another way into this app. Only the user can allow it, "
                + "by adding its bundle ID to YOUXPC_ALLOW_APPS in the MCP server configuration."
        )
    }

    private static func matches(_ bundleID: String, family: String) -> Bool {
        let family = family.lowercased()
        return bundleID == family || bundleID.hasPrefix(family + ".")
    }

    private static func list(from variable: String) -> [String]? {
        guard let raw = ProcessInfo.processInfo.environment[variable] else { return nil }
        let items = raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        return items.isEmpty ? nil : items
    }

    private static func number(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        return nil
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}

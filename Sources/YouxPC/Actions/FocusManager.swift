// FocusManager.swift - Focus orchestration for YouxPC v2
//
// Handles: pc_focus, pc_window, focus save/restore, modifier clearing.
// Uses AXorcist's Element.activateApplication(), focusWindow(), etc.

import AppKit
import AXorcist
import Foundation

/// Manages application and window focus, modifier key cleanup, and focus restoration.
public enum FocusManager {

    /// Focus an app, optionally a specific window. Retries activation once,
    /// then polls for up to 1 second to verify focus took effect.
    public static func focus(appName: String, windowTitle: String? = nil) -> ToolResult {
        guard let app = Perception.runningApps().first(where: {
            $0.localizedName?.localizedCaseInsensitiveContains(appName) == true
        }) else {
            return ToolResult(
                success: false,
                error: "Application '\(appName)' not found",
                suggestion: "Use pc_state to see all running apps"
            )
        }

        // Try activation with retry (two attempts).
        for attempt in 1...2 {
            let activated = bringToFront(app)
            if !activated && attempt == 2 {
                return ToolResult(
                    success: false,
                    error: "Failed to activate '\(appName)'",
                    suggestion: "The app may be unresponsive. Try pc_state to check its status."
                )
            }

            // Brief pause to let the activation propagate.
            Thread.sleep(forTimeInterval: 0.2)

            // If window title specified, find and raise that window.
            if let windowTitle {
                if let appElement = Element.application(for: app.processIdentifier),
                   let windows = appElement.windows()
                {
                    if let targetWindow = windows.first(where: {
                        $0.title()?.localizedCaseInsensitiveContains(windowTitle) == true
                    }) {
                        _ = targetWindow.focusWindow()
                    }
                }
            }

            // Poll for up to 1 second (10 checks x 100ms) to verify focus.
            for _ in 0..<10 {
                Thread.sleep(forTimeInterval: 0.1)
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                    return ToolResult(
                        success: true,
                        data: [
                            "app": app.localizedName ?? appName,
                            "focused": true,
                        ]
                    )
                }
            }
            // First attempt timed out, retry activation.
        }

        // Both attempts completed but couldn't verify within the polling window.
        return ToolResult(
            success: true,
            data: [
                "app": app.localizedName ?? appName,
                "focused": false,
                "note": "App was activated but focus verification timed out. It may still be focused.",
            ]
        )
    }

    /// Save the current frontmost app for later restoration.
    public static func saveFrontmostApp() -> NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }

    /// Restore focus to a previously saved app.
    public static func restoreFocus(to app: NSRunningApplication?) {
        guard let app else { return }
        _ = bringToFront(app)
    }

    /// Make `app` frontmost and confirm it stayed that way.
    ///
    /// `NSRunningApplication.activate()` is only a request on recent macOS and
    /// may be ignored when the caller is not the active app, which a background
    /// MCP server never is; the app's AXFrontmost attribute is the fallback.
    /// Both are synchronous requests. Nothing asynchronous is used here: a
    /// late-arriving activation is exactly how keystrokes end up in the wrong
    /// app. The result is true only if the app is frontmost and still is a
    /// moment later.
    @discardableResult
    public static func bringToFront(_ app: NSRunningApplication) -> Bool {
        func isFront() -> Bool {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
        }
        func becameFront(within seconds: TimeInterval) -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                if isFront() { return true }
                Thread.sleep(forTimeInterval: 0.03)
            }
            return isFront()
        }

        if !isFront() {
            // Activation can take over a second to land when the caller is a
            // background process; giving up early reports a failure that is
            // then contradicted by the app arriving in front.
            app.activate()
            if !becameFront(within: 1.2) {
                let element = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                _ = becameFront(within: 1.5)
            }
        }
        // Hold: another activation may be in flight and about to take over.
        Thread.sleep(forTimeInterval: 0.12)
        if !isFront() {
            Log.warn("Could not bring '\(app.localizedName ?? "app")' to the front")
            return false
        }
        return true
    }

    /// Execute an operation with automatic focus save/restore.
    public static func withFocusRestore<T>(_ operation: () throws -> T) rethrows -> T {
        let savedApp = saveFrontmostApp()
        defer { restoreFocus(to: savedApp) }
        return try operation()
    }

    /// Clear all modifier key flags to prevent stuck keys after hotkeys.
    /// AXorcist's performHotkey can leave Cmd/Shift/Option stuck.
    public static func clearModifierFlags() {
        if let event = CGEvent(source: nil) {
            event.type = .flagsChanged
            event.flags = CGEventFlags(rawValue: 0)
            event.post(tap: .cghidEventTap)
        }
    }
}

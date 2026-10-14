// PressGuard.swift - Controls the user has said the agent must never press.
//
//   YOUXPC_NEVER_PRESS=Send,Delete,Pay now      (comma-separated, any case)
//
// A control is refused when its name contains an entry as whole words: "Send"
// matches "Send" and "Send message", not "Sender" or "Resend". Checked for
// clicks and long-presses on a named control, for clicks at a point that
// lands on one, and for Return or Space while one has keyboard focus.
//
// This stops the common accident. It is not a boundary: a form can still be
// submitted with Return from a text field, and a control with no accessible
// name cannot be matched.

import Foundation

public enum PressGuard {

    private static let entries: [[String]] = parse(ProcessInfo.processInfo.environment["YOUXPC_NEVER_PRESS"])

    public static var isActive: Bool { !entries.isEmpty }

    /// Roles a click only focuses, so a matching label on them is not a press.
    private static let exemptRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXComboBox", "AXStaticText", "AXHeading", "AXWebArea", "AXWindow",
    ]

    static func parse(_ raw: String?) -> [[String]] {
        (raw ?? "").split(separator: ",").map { words(String($0)) }.filter { !$0.isEmpty }
    }

    static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
    }

    /// The entry `name` matches, if any.
    static func match(_ name: String, in entries: [[String]]) -> String? {
        let nameWords = words(name)
        for entry in entries where entry.count <= nameWords.count {
            for start in 0...(nameWords.count - entry.count)
            where Array(nameWords[start..<(start + entry.count)]) == entry {
                return entry.joined(separator: " ")
            }
        }
        return nil
    }

    /// A refusal when `name` is on the list, nil when the press may go ahead.
    public static func refusal(name: String?, role: String?) -> ToolResult? {
        guard isActive, let name, !exemptRoles.contains(role ?? ""),
              let entry = match(name, in: entries)
        else { return nil }
        return ToolResult(
            success: false,
            error: "'\(name)' is on the user's never-press list (matches \"\(entry)\"). Nothing was pressed.",
            suggestion: "Stop here and ask the user to do this step. Only the user can change YOUXPC_NEVER_PRESS."
        )
    }
}

// ActionSequence.swift - pc_do: several actions in one call
//
// A model turn costs seconds; an accessibility press costs a fraction of one.
// In the benchmark about nine tenths of a run was the model deciding, one
// tool call at a time, so the way to make a task faster and cheaper is to let
// one decision carry several actions:
//
//   pc_do steps:[{"click":"4"},{"click":"7"},{"click":"Multiply"},
//                {"click":"1"},{"click":"9"},{"click":"Equals"}]
//
//   pc_do steps:[{"type":"Ada","into":"e14"},{"type":"ada@example.test","into":"e15"},
//                {"click":"Submit"}]
//
// Rules that keep it predictable:
//
// - Steps run in order and stop at the first one that fails. The answer says
//   which step failed and that the rest were not run.
// - A target is an id when written with its e (e7). Anything else is the
//   item's name, looked up on the screen as it is at that step, so a step can
//   name something an earlier step made appear. The step waits up to a second
//   and a half for that name to show up.
// - Every step goes through the same code as the single tools: app policy,
//   never-press list, typing refused on non-text targets, one receipt each.
// - The answer ends with what the whole sequence changed, once the screen
//   has settled.

import AppKit
import Foundation

public enum ActionSequence {

    public static let toolName = "pc_do"

    private static let maxSteps = 30
    private static let maxWaitSeconds = 5.0
    /// How long to wait for a menu to close after a choice is made in it.
    private static let menuCloseSeconds = 1.5
    /// How long a step waits for the thing it names to appear.
    private static let nameWaitSeconds = 1.5

    // MARK: - Definition

    public static let definition: [String: Any] = [
        "name": toolName,
        "description": "Do several actions in one call, in order. Use it whenever you already know the next few "
            + "steps (pressing a series of buttons, filling a form and submitting it). Stops at the first step that "
            + "fails. Answers with each step's outcome and what changed on screen.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "steps": [
                    "type": "array",
                    "description": "Each step is an object with one action: click, type, key, scroll or wait.",
                    "items": [
                        "type": "object",
                        "properties": [
                            "click": [
                                "type": "string",
                                "description": "Item to click: its id (e7) or its name (\"Save\"). For keys and items labelled with a digit or one character, use the name (\"7\", \"+\"), not the id.",
                            ],
                            "type": ["type": "string", "description": "Text to put in a field."],
                            "into": [
                                "type": "string",
                                "description": "With type: the field's id or name; its content is replaced. Leave out to type at the keyboard focus.",
                            ],
                            "key": ["type": "string", "description": "Key or shortcut: return, tab, escape, down, cmd+a."],
                            "scroll": ["type": "string", "description": "up or down."],
                            "wait": ["type": "number", "description": "Seconds to pause, at most 5. Rarely needed."],
                        ] as [String: Any],
                    ] as [String: Any],
                ] as [String: Any],
                "app": ["type": "string", "description": "App name. Leave out to continue in the app last looked at."],
            ] as [String: Any],
            "required": ["steps"],
        ] as [String: Any],
    ]

    // MARK: - Steps

    enum Step: Equatable {
        case click(String)
        case type(text: String, into: String?)
        case key(String)
        case scroll(String)
        case wait(Double)

        var label: String {
            switch self {
            case let .click(target): "click \(target)"
            case let .type(_, into): into.map { "type into \($0)" } ?? "type"
            case let .key(combo): "key \(combo)"
            case let .scroll(direction): "scroll \(direction)"
            case let .wait(seconds): "wait \(seconds)s"
            }
        }
    }

    enum ParseError: Error, Equatable {
        case notAList
        case empty
        case tooMany(Int)
        case unreadable(Int)
    }

    /// Read the `steps` argument. Targets may arrive as strings or numbers.
    static func parse(_ raw: Any?) -> Result<[Step], ParseError> {
        guard let list = raw as? [Any] else { return .failure(.notAList) }
        guard !list.isEmpty else { return .failure(.empty) }
        guard list.count <= maxSteps else { return .failure(.tooMany(list.count)) }
        var steps: [Step] = []
        for (offset, item) in list.enumerated() {
            guard let fields = item as? [String: Any], let step = step(from: fields) else {
                return .failure(.unreadable(offset + 1))
            }
            steps.append(step)
        }
        return .success(steps)
    }

    private static func step(from fields: [String: Any]) -> Step? {
        if let text = fields["type"] as? String {
            return .type(text: text, into: string(fields["into"]))
        }
        if let target = string(fields["click"]) { return .click(target) }
        if let combo = string(fields["key"]) { return .key(combo) }
        if let direction = string(fields["scroll"]) { return .scroll(direction.lowercased()) }
        if let seconds = fields["wait"] as? Double { return .wait(seconds) }
        if let seconds = fields["wait"] as? Int { return .wait(Double(seconds)) }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? Int { return String(number) }
        return nil
    }

    /// An id is written with its e: e7, [e7]. Everything else is a name, so
    /// "7" is the key labelled 7 and not the element numbered 7.
    static func target(_ raw: String) -> (index: Int?, name: String?) {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        if trimmed.range(of: "^[eE][0-9]+$", options: .regularExpression) != nil {
            return (Int(trimmed.dropFirst()), nil)
        }
        return (nil, raw)
    }

    // MARK: - Running

    struct Outcome {
        var lines: [String] = []
        var failed = false
    }

    /// Run the steps against `app`. Does not report screen changes; the caller does.
    static func run(_ steps: [Step], app: String?) -> Outcome {
        var outcome = Outcome()
        var stale = false   // an action has run since the screen was last read
        for (offset, step) in steps.enumerated() {
            let started = DispatchTime.now()
            // A name has to be looked up on the screen as it is now, and what an
            // earlier step set in motion may not be there yet: wait for it.
            if stale, let name = namedTarget(step) {
                Snapshot.waitFor(name: name, appName: app, timeout: nameWaitSeconds)
                stale = false
            } else if stale, goesToKeyboardFocus(step) {
                // A key lands wherever focus is when it arrives. If the step before
                // opened a menu or moved focus, that has to have happened first:
                // "open the dropdown, press p, press return" sent the keys before
                // the menu existed, chose nothing, and still reported three successes.
                Snapshot.settle(appName: app)
                stale = false
            }
            // The last step keeps its full pause so the final report sees its effect.
            // The pause after a press is cut short only when the next step names
            // or points at its own target. A key goes wherever focus is, so what
            // this step sets in motion (a menu opening) must be given its full
            // time; "stable for a moment" cannot tell done from not yet started.
            let next = offset + 1 < steps.count ? steps[offset + 1] : nil
            Actions.betweenSequenceSteps = next.map { !goesToKeyboardFocus($0) } ?? false
            Actions.pressedMenuItem = false
            let (tool, args, result) = perform(step, app: app)
            Actions.betweenSequenceSteps = false
            // Choosing from a menu is not finished when the press returns. Wait
            // for the menu to go before the next step touches anything.
            if result.success, offset < steps.count - 1, Actions.pressedMenuItem || confirmsMenuChoice(step) {
                Snapshot.waitForMenuToClose(appName: app, timeout: menuCloseSeconds)
            }
            let elapsed = Int((DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000)
            if let tool {
                var logged = args
                logged["sequence_step"] = offset + 1
                Receipts.record(
                    tool: tool, args: logged,
                    response: MCPDispatch.formatResult(result, toolName: tool), milliseconds: elapsed
                )
                stale = true
            }
            let number = "\(offset + 1). "
            if result.success {
                outcome.lines.append(number + describe(step, result) + ": ok")
            } else {
                var line = number + step.label + ": FAILED. " + sentence(result.error ?? "The action did not work")
                // Suggestions written for single tools name tools this call cannot use mid-sequence.
                if let suggestion = result.suggestion, !suggestion.contains("pc_find"), !suggestion.contains("pc_context") {
                    line += " " + sentence(suggestion)
                } else if usesName(step) {
                    line += " Use the exact name or the id shown in the snapshot."
                }
                outcome.lines.append(line)
                let left = steps.count - offset - 1
                if left > 0 {
                    outcome.lines.append("Stopped. The remaining \(left) step\(left == 1 ? " was" : "s were") not run.")
                }
                outcome.failed = true
                break
            }
        }
        return outcome
    }

    private static func namedTarget(_ step: Step) -> String? {
        switch step {
        case let .click(raw): target(raw).name
        case let .type(_, into): into.flatMap { target($0).name }
        default: nil
        }
    }

    private static func usesName(_ step: Step) -> Bool { namedTarget(step) != nil }

    /// Keys that pick the highlighted item of an open menu, or dismiss it.
    private static func confirmsMenuChoice(_ step: Step) -> Bool {
        guard case let .key(combo) = step else { return false }
        return ["return", "enter", "space", "escape", "esc", "tab"].contains(combo.lowercased())
    }

    private static func goesToKeyboardFocus(_ step: Step) -> Bool {
        switch step {
        case .key: true
        case let .type(_, into): into == nil
        default: false
        }
    }

    /// Returns the single tool this step corresponds to (nil for a pause), the
    /// arguments as that tool would have received them, and the result.
    private static func perform(_ step: Step, app: String?) -> (String?, [String: Any], ToolResult) {
        var args: [String: Any] = [:]
        if let app { args["app"] = app }
        switch step {
        case let .click(raw):
            let (index, name) = target(raw)
            if let index { args["index"] = "e\(index)" } else { args["query"] = name }
            let result = FocusManager.withFocusRestore {
                Actions.click(
                    query: name, role: nil, domId: nil, appName: app, x: nil, y: nil, button: nil, count: nil, index: index
                )
            }
            return ("pc_click", args, withIdHint(result, raw: raw, named: name != nil))

        case let .type(text, into):
            args["text"] = text
            let (index, name) = into.map(target) ?? (nil, nil)
            if let index { args["index"] = "e\(index)" } else if let name { args["into"] = name }
            let result = FocusManager.withFocusRestore {
                Actions.typeText(text: text, into: name, domId: nil, appName: app, clear: into != nil, index: index)
            }
            return ("pc_type", args, result)

        case let .key(combo):
            // "+" separates modifiers from the key, and is also a key: "+", "shift++".
            var parts = combo.lowercased().split(separator: "+", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if combo.hasSuffix("+") { parts.append("+") }
            guard let key = parts.last, !key.isEmpty else {
                return (nil, args, ToolResult(success: false, error: "'\(combo)' is not a key."))
            }
            if parts.count > 1 {
                args["keys"] = parts
                return ("pc_hotkey", args, Actions.hotkey(keys: parts, appName: app))
            }
            args["key"] = key
            return ("pc_press", args, Actions.pressKey(key: key, modifiers: nil, appName: app))

        case let .scroll(direction):
            args["direction"] = direction
            return ("pc_scroll", args, Actions.scroll(direction: direction, amount: nil, appName: app, x: nil, y: nil))

        case let .wait(seconds):
            Thread.sleep(forTimeInterval: max(0, min(seconds, maxWaitSeconds)))
            return (nil, args, ToolResult(success: true))
        }
    }

    /// A bare number that matched nothing was probably meant as an id.
    private static func withIdHint(_ result: ToolResult, raw: String, named: Bool) -> ToolResult {
        guard !result.success, named, Int(raw) != nil else { return result }
        return ToolResult(
            success: false, error: result.error,
            suggestion: "Nothing on screen is named \"\(raw)\". If you meant the id, write it as e\(raw)."
        )
    }

    /// A click by id also says what was clicked; a click by name already does.
    private static func describe(_ step: Step, _ result: ToolResult) -> String {
        guard case let .click(raw) = step, target(raw).index != nil,
              let element = result.data?["element"] as? String, !element.isEmpty
        else { return step.label }
        var shown = "\(step.label) \"\(element.replacingOccurrences(of: "\n", with: " "))\""
        if let row = result.data?["row"] as? String { shown += " in row \"\(row)\"" }
        if let earlier = result.data?["listed_as"] as? String { shown += " (listed as \"\(earlier)\" before)" }
        return shown
    }

    private static func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.hasSuffix(".") || trimmed.hasSuffix("?") ? trimmed : trimmed + "."
    }

    static func message(for error: ParseError) -> String {
        switch error {
        case .notAList:
            "steps must be a list, for example steps:[{\"click\":\"e7\"},{\"type\":\"hello\",\"into\":\"e3\"}]."
        case .empty:
            "steps is empty. Give at least one step."
        case let .tooMany(count):
            "\(count) steps is too many for one call; the limit is \(maxSteps). Send the first part, read the result, then continue."
        case let .unreadable(position):
            "Step \(position) has no action. Each step needs one of: click, type, key, scroll, wait."
        }
    }

    // MARK: - Default profile entry point

    /// pc_do for the default and full profiles: step outcomes, then the net change.
    static func handle(_ args: [String: Any]) -> [String: Any] {
        let steps: [Step]
        switch parse(args["steps"]) {
        case let .failure(error): return text(message(for: error), isError: true)
        case let .success(parsed): steps = parsed
        }
        let app = (args["app"] as? String) ?? Snapshot.latestAppName
        guard let app else {
            return text("Call pc_snapshot with the app name first, or pass app.", isError: true)
        }
        if let denied = AppPolicy.check(tool: "pc_click", args: ["app": app]) {
            return MCPDispatch.formatResult(denied, toolName: toolName)
        }
        Snapshot.beginSequence(appName: app)
        let outcome = run(steps, app: app)
        var lines = outcome.lines
        if let changes = Snapshot.endSequence(appName: app) {
            lines.append("Changes:")
            lines.append(changes)
        }
        return text(lines.joined(separator: "\n"), isError: outcome.failed)
    }

    private static func text(_ string: String, isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": string] as [String: Any]], "isError": isError]
    }
}

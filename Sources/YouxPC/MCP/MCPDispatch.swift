// MCPDispatch.swift - Route MCP tool calls to module functions
//
// Maps tool names to handler functions. Wraps each call in a timeout.
// Formats responses as MCP content arrays.

import Foundation

/// Routes MCP tool calls to the appropriate module function.
public enum MCPDispatch {

    /// Handle a tools/call request. Returns MCP-formatted result.
    /// Tools run synchronously on the main thread and are not interrupted;
    /// what bounds them is the global AX messaging timeout (MCPServer.init)
    /// and the node budget and deadline inside each tree walk.
    public static func handle(_ params: [String: Any]) -> [String: Any] {
        guard let toolName = params["name"] as? String else {
            return errorContent("Missing tool name")
        }

        let args = params["arguments"] as? [String: Any] ?? [:]
        let startTime = DispatchTime.now()
        Log.info("Tool call: \(toolName)")

        // Screenshot and annotate return MCP image content directly (not text-wrapped JSON)
        let response: [String: Any]
        if SimpleProfile.isEnabled, SimpleProfile.toolNames.contains(toolName) {
            let policyArgs = SimpleProfile.policyArguments(toolName, args)
            if policyArgs["app"] != nil, let denied = AppPolicy.check(tool: "pc_snapshot", args: policyArgs) {
                response = formatResult(denied, toolName: toolName)
            } else {
                response = SimpleProfile.handle(tool: toolName, args: args)
            }
        } else if SimpleProfile.isBareNumber(args["index"]), let number = int(args, "index"),
                  let unclear = Snapshot.ambiguity(bareNumber: number, appName: str(args, "app"))
        {
            response = formatResult(unclear, toolName: toolName)
        } else if let denied = AppPolicy.check(tool: toolName, args: args) {
            Log.warn("Tool \(toolName) blocked by app policy")
            response = formatResult(denied, toolName: toolName)
        } else if MCPTools.learningToolNames.contains(toolName) && !MCPTools.learningEnabled {
            response = formatResult(
                ToolResult(
                    success: false,
                    error: "Learning mode is disabled. It records the user's keyboard and mouse input system-wide.",
                    suggestion: "Only the user can enable it, by setting YOUXPC_LEARNING=on in the MCP server configuration."
                ),
                toolName: toolName
            )
        } else if toolName == "pc_snapshot" {
            // Plain text, not JSON: the format is the token saving.
            let output = Snapshot.take(
                appName: str(args, "app"),
                forceFull: bool(args, "full") ?? false,
                maxLines: int(args, "max_lines")
            )
            response = [
                "content": [["type": "text", "text": output.text] as [String: Any]],
                "isError": output.isError,
            ]
        } else if toolName == ActionSequence.toolName {
            response = ActionSequence.handle(args)
        } else if toolName == "pc_screenshot" {
            response = handleScreenshot(args)
        } else if toolName == "pc_annotate" {
            response = handleAnnotate(args)
        } else {
            var result = dispatch(tool: toolName, args: args)
            // Tell the agent what its action changed, saving it a follow-up call.
            if result.success, actionTools.contains(toolName),
               let changes = Snapshot.changesAfterAction(
                   appName: str(args, "app"), usedIndex: args["index"] != nil
               )
            {
                var data = result.data ?? [:]
                data["changes"] = changes
                result = ToolResult(
                    success: true, data: data, suggestion: result.suggestion, context: result.context
                )
            }
            response = formatResult(result, toolName: toolName)
        }

        // Log timing for every tool call (helps diagnose slow tools)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
        Receipts.record(tool: toolName, args: args, response: response, milliseconds: Int(elapsed))
        if elapsed > 5000 {
            Log.warn("Tool \(toolName) took \(Int(elapsed))ms (slow)")
        } else {
            Log.info("Tool \(toolName) completed in \(Int(elapsed))ms")
        }

        return response
    }

    /// Tools whose results report the UI changes they caused.
    private static let actionTools: Set<String> = [
        "pc_click", "pc_type", "pc_press", "pc_hotkey", "pc_scroll",
        "pc_long_press", "pc_drag",
    ]

    /// Screenshot handler returns MCP image content type for inline display.
    private static func handleScreenshot(_ args: [String: Any]) -> [String: Any] {
        let result = Perception.screenshot(
            appName: str(args, "app"),
            fullResolution: bool(args, "full_resolution") ?? false
        )

        guard result.success,
              let data = result.data,
              let base64 = data["image"] as? String
        else {
            return formatResult(result, toolName: "pc_screenshot")
        }

        // Return as MCP image + text caption (v1 pattern: both content types)
        let mimeType = data["mime_type"] as? String ?? "image/png"
        let width = data["width"] as? Int ?? 0
        let height = data["height"] as? Int ?? 0
        let windowTitle = data["window_title"] as? String ?? ""
        var caption = "Screenshot: \(width)x\(height)"
        if !windowTitle.isEmpty { caption += " - \(windowTitle)" }

        return [
            "content": [
                [
                    "type": "image",
                    "data": base64,
                    "mimeType": mimeType,
                ] as [String: Any],
                [
                    "type": "text",
                    "text": caption,
                ] as [String: Any],
            ] as [[String: Any]],
            "isError": false,
        ]
    }

    /// Annotate handler returns MCP image + text index for labeled screenshots.
    private static func handleAnnotate(_ args: [String: Any]) -> [String: Any] {
        let rolesArray = args["roles"] as? [String]
        let result = Annotate.annotate(
            appName: str(args, "app"),
            roles: rolesArray,
            maxLabels: int(args, "max_labels")
        )

        guard result.success,
              let data = result.data,
              let base64 = data["annotated_image"] as? String,
              let index = data["index"] as? String
        else {
            return formatResult(result, toolName: "pc_annotate")
        }

        let mimeType = data["mime_type"] as? String ?? "image/png"
        let width = data["width"] as? Int ?? 0
        let height = data["height"] as? Int ?? 0
        let elementCount = data["element_count"] as? Int ?? 0
        let windowTitle = data["window_title"] as? String ?? ""

        var caption = "Annotated screenshot: \(width)x\(height), \(elementCount) labeled elements"
        if !windowTitle.isEmpty { caption += " — \(windowTitle)" }

        return [
            "content": [
                [
                    "type": "image",
                    "data": base64,
                    "mimeType": mimeType,
                ] as [String: Any],
                [
                    "type": "text",
                    "text": caption + "\n\n" + index,
                ] as [String: Any],
            ] as [[String: Any]],
            "isError": false,
        ]
    }

    // MARK: - Dispatch

    private static func dispatch(tool: String, args: [String: Any]) -> ToolResult {
        switch tool {

        case "pc_terminal":
            return TerminalSessions.handle(args)

        // Perception
        case "pc_context":
            return Perception.getContext(appName: str(args, "app"))

        case "pc_state":
            return Perception.getState(appName: str(args, "app"))

        case "pc_find":
            return Perception.findElements(
                query: str(args, "query"),
                role: str(args, "role"),
                domId: str(args, "dom_id"),
                domClass: str(args, "dom_class"),
                identifier: str(args, "identifier"),
                appName: str(args, "app"),
                depth: int(args, "depth")
            )

        case "pc_read":
            return Perception.readContent(
                appName: str(args, "app"),
                query: str(args, "query"),
                depth: int(args, "depth")
            )

        case "pc_inspect":
            guard let query = str(args, "query") else {
                return ToolResult(success: false, error: "Missing required parameter: query")
            }
            return Perception.inspect(
                query: query,
                role: str(args, "role"),
                domId: str(args, "dom_id"),
                appName: str(args, "app")
            )

        case "pc_element_at":
            guard let x = double(args, "x"), let y = double(args, "y") else {
                return ToolResult(success: false, error: "Missing required parameters: x, y")
            }
            return Perception.elementAt(x: x, y: y)

        case "pc_screenshot":
            return Perception.screenshot(
                appName: str(args, "app"),
                fullResolution: bool(args, "full_resolution") ?? false
            )

        // Actions
        case "pc_click":
            return FocusManager.withFocusRestore {
                Actions.click(
                    query: str(args, "query"),
                    role: str(args, "role"),
                    domId: str(args, "dom_id"),
                    appName: str(args, "app"),
                    x: double(args, "x"),
                    y: double(args, "y"),
                    button: str(args, "button"),
                    count: int(args, "count"),
                    index: int(args, "index")
                )
            }

        case "pc_type":
            guard let text = str(args, "text") else {
                return ToolResult(success: false, error: "Missing required parameter: text")
            }
            return FocusManager.withFocusRestore {
                Actions.typeText(
                    text: text,
                    into: str(args, "into"),
                    domId: str(args, "dom_id"),
                    appName: str(args, "app"),
                    clear: bool(args, "clear") ?? false,
                    index: int(args, "index")
                )
            }

        // Press, hotkey, scroll, hover, long_press, drag are synthetic input tools
        // that send events to the FRONTMOST app. They need the target app to STAY
        // focused after the tool returns — the agent will call pc_focus to
        // restore when ready. Do NOT wrap these in withFocusRestore, which would
        // steal focus back before the app processes the event (e.g. Cmd+L needs
        // Chrome to stay focused while it selects the address bar text).
        case "pc_press":
            guard let key = str(args, "key") else {
                return ToolResult(success: false, error: "Missing required parameter: key")
            }
            let modifiers = (args["modifiers"] as? [String])
            return Actions.pressKey(key: key, modifiers: modifiers, appName: str(args, "app"))

        case "pc_hotkey":
            guard let keys = args["keys"] as? [String] else {
                return ToolResult(success: false, error: "Missing required parameter: keys (array of strings)")
            }
            return Actions.hotkey(keys: keys, appName: str(args, "app"))

        case "pc_scroll":
            guard let direction = str(args, "direction") else {
                return ToolResult(success: false, error: "Missing required parameter: direction")
            }
            return Actions.scroll(
                direction: direction,
                amount: int(args, "amount"),
                appName: str(args, "app"),
                x: double(args, "x"),
                y: double(args, "y")
            )

        case "pc_hover":
            return Actions.hover(
                query: str(args, "query"),
                role: str(args, "role"),
                domId: str(args, "dom_id"),
                appName: str(args, "app"),
                x: double(args, "x"),
                y: double(args, "y"),
                index: int(args, "index")
            )

        case "pc_long_press":
            return Actions.longPress(
                query: str(args, "query"),
                role: str(args, "role"),
                domId: str(args, "dom_id"),
                appName: str(args, "app"),
                x: double(args, "x"),
                y: double(args, "y"),
                duration: double(args, "duration"),
                button: str(args, "button"),
                index: int(args, "index")
            )

        case "pc_drag":
            guard let toX = double(args, "to_x"),
                  let toY = double(args, "to_y")
            else {
                return ToolResult(success: false, error: "Missing required parameters: to_x, to_y")
            }
            return Actions.drag(
                query: str(args, "query"),
                role: str(args, "role"),
                domId: str(args, "dom_id"),
                appName: str(args, "app"),
                fromX: double(args, "from_x"),
                fromY: double(args, "from_y"),
                toX: toX,
                toY: toY,
                duration: double(args, "duration"),
                holdDuration: double(args, "hold_duration")
            )

        case "pc_focus":
            guard let app = str(args, "app") else {
                return ToolResult(success: false, error: "Missing required parameter: app")
            }
            return FocusManager.focus(appName: app, windowTitle: str(args, "window"))

        case "pc_window":
            guard let action = str(args, "action"),
                  let app = str(args, "app")
            else {
                return ToolResult(success: false, error: "Missing required parameters: action, app")
            }
            return Actions.manageWindow(
                action: action,
                appName: app,
                windowTitle: str(args, "window"),
                x: double(args, "x"),
                y: double(args, "y"),
                width: double(args, "width"),
                height: double(args, "height")
            )

        // Wait
        case "pc_wait":
            guard let condition = str(args, "condition") else {
                return ToolResult(success: false, error: "Missing required parameter: condition")
            }
            return WaitManager.waitFor(
                condition: condition,
                value: str(args, "value"),
                appName: str(args, "app"),
                timeout: double(args, "timeout") ?? 10,
                interval: double(args, "interval") ?? 0.5
            )

        // Recipes
        case "pc_recipes":
            let recipes = RecipeStore.listRecipes()
            let summaries: [[String: Any]] = recipes.map { recipe in
                var summary: [String: Any] = [
                    "name": recipe.name,
                    "description": recipe.description,
                ]
                if let app = recipe.app { summary["app"] = app }
                if let params = recipe.params {
                    summary["params"] = params.map { key, param in
                        ["name": key, "type": param.type, "description": param.description,
                         "required": param.required ?? false] as [String: Any]
                    }
                }
                return summary
            }
            return ToolResult(success: true, data: ["recipes": summaries, "count": summaries.count])

        case "pc_run":
            guard let recipeName = str(args, "recipe") else {
                return ToolResult(success: false, error: "Missing required parameter: recipe")
            }
            guard let recipe = RecipeStore.loadRecipe(named: recipeName) else {
                return ToolResult(
                    success: false,
                    error: "Recipe '\(recipeName)' not found",
                    suggestion: "Use pc_recipes to list available recipes"
                )
            }
            // Parse params from the MCP arguments
            let recipeParams: [String: String]
            if let paramsObj = args["params"] as? [String: Any] {
                recipeParams = paramsObj.reduce(into: [:]) { result, pair in
                    result[pair.key] = "\(pair.value)"
                }
            } else {
                recipeParams = [:]
            }
            return RecipeEngine.run(recipe: recipe, params: recipeParams)

        case "pc_recipe_show":
            guard let name = str(args, "name") else {
                return ToolResult(success: false, error: "Missing required parameter: name")
            }
            guard let recipe = RecipeStore.loadRecipe(named: name) else {
                return ToolResult(
                    success: false,
                    error: "Recipe '\(name)' not found",
                    suggestion: "Use pc_recipes to list available recipes"
                )
            }
            if let data = try? JSONEncoder().encode(recipe),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                return ToolResult(success: true, data: dict)
            }
            return ToolResult(success: false, error: "Failed to serialize recipe")

        case "pc_recipe_save":
            guard let jsonStr = str(args, "recipe_json") else {
                return ToolResult(success: false, error: "Missing required parameter: recipe_json")
            }
            do {
                let name = try RecipeStore.saveRecipeJSON(jsonStr)
                return ToolResult(success: true, data: ["saved": name])
            } catch {
                return ToolResult(success: false, error: "Failed to save recipe: \(error)")
            }

        case "pc_recipe_delete":
            guard let name = str(args, "name") else {
                return ToolResult(success: false, error: "Missing required parameter: name")
            }
            let deleted = RecipeStore.deleteRecipe(named: name)
            return ToolResult(
                success: deleted,
                data: deleted ? ["deleted": name] : nil,
                error: deleted ? nil : "Recipe '\(name)' not found"
            )

        // Vision
        case "pc_parse_screen":
            return VisionPerception.parseScreen(
                appName: str(args, "app"),
                fullResolution: bool(args, "full_resolution") ?? false
            )

        case "pc_ground":
            guard let description = str(args, "description") else {
                return ToolResult(success: false, error: "Missing required parameter: description")
            }
            let cropBox: [Double]?
            if let arr = args["crop_box"] as? [Any] {
                cropBox = arr.compactMap { val -> Double? in
                    if let d = val as? Double { return d }
                    if let i = val as? Int { return Double(i) }
                    return nil
                }
            } else {
                cropBox = nil
            }
            return VisionPerception.groundElement(
                description: description,
                appName: str(args, "app"),
                cropBox: cropBox
            )

        // Learning
        case "pc_learn_start":
            return LearningDispatch.learnStart(args: args)

        case "pc_learn_stop":
            return LearningDispatch.learnStop(args: args)

        case "pc_learn_status":
            return LearningDispatch.learnStatus(args: args)

        default:
            return ToolResult(success: false, error: "Unknown tool: \(tool)")
        }
    }

    // MARK: - Response Formatting

    /// Format a ToolResult as MCP content array.
    static func formatResult(_ result: ToolResult, toolName: String) -> [String: Any] {
        let dict = result.toDict()

        // Serialize to JSON string for MCP text content
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
           let jsonStr = String(data: data, encoding: .utf8)
        {
            return [
                "content": [
                    ["type": "text", "text": jsonStr],
                ],
                "isError": !result.success,
            ]
        }

        return errorContent("Failed to serialize response for \(toolName)")
    }

    static func errorContent(_ message: String) -> [String: Any] {
        [
            "content": [
                ["type": "text", "text": "{\"success\":false,\"error\":\"\(message)\"}"],
            ],
            "isError": true,
        ]
    }

    // MARK: - Parameter Helpers

    private static func str(_ args: [String: Any], _ key: String) -> String? {
        args[key] as? String
    }

    /// Numbers arrive as 7, 7.0, "7" or "[7]" depending on the model.
    private static func int(_ args: [String: Any], _ key: String) -> Int? {
        SimpleProfile.number(args[key])
    }

    private static func double(_ args: [String: Any], _ key: String) -> Double? {
        if let d = args[key] as? Double { return d }
        if let i = args[key] as? Int { return Double(i) }
        return nil
    }

    private static func bool(_ args: [String: Any], _ key: String) -> Bool? {
        args[key] as? Bool
    }
}

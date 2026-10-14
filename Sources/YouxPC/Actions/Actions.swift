// Actions.swift - All action functions for YouxPC v2
//
// Maps to MCP tools: pc_click, pc_type, pc_press, pc_hotkey,
// pc_scroll, pc_window
//
// Architecture: Uses AXorcist's COMMAND SYSTEM (runCommand with Locators)
// for AX-native operations, with synthetic fallback for Chrome/web apps.
//
// The Action Loop (every action follows this):
// 1. PRE-FLIGHT: find element via AXorcist, check actionable
// 2. EXECUTE: AX-native first, synthetic fallback if no state change
// 3. POST-VERIFY: brief pause, read post-action context
// 4. CLEANUP: clear modifier flags, restore focus

import AppKit
import AXorcist
import Foundation

/// Actions module: operating apps for the agent.
public enum Actions {

    // MARK: - pc_click

    /// Click an element. AX-native first via AXorcist's PerformAction command,
    /// synthetic fallback with position-based click.
    public static func click(
        query: String?,
        role: String?,
        domId: String?,
        appName: String?,
        x: Double?,
        y: Double?,
        button: String?,
        count: Int?,
        index: Int? = nil
    ) -> ToolResult {
        let indexed = indexedTarget(index, appName: appName, query: query, role: role)
        if let failure = indexed.failure { return failure }
        let appName = indexed.appName
        // Echo the name the control has now. A control can change its name
        // between the snapshot and the press (Calculator's "All Clear" becomes
        // "Clear" once a digit is entered, and does something different).
        let before = indexed.listedName.flatMap { $0.isEmpty ? nil : $0 }
        let listed = indexed.element.flatMap { Snapshot.currentName(of: $0.underlyingElement) } ?? before
        let renamedFrom = (before != nil && listed != before) ? before : nil

        let mouseButton: MouseButton = switch button {
        case "right": .right
        case "middle": .middle
        default: .left
        }
        let clickCount = max(1, count ?? 1)

        // Coordinate-based click (no element lookup)
        if indexed.element == nil, let x, let y {
            let point = CGPoint(x: x, y: y)
            if let refusal = neverPress(at: point, appName: appName) { return refusal }
            VirtualCursor.shared.glide(to: point)

            // Background path: if a pressable control sits at this point, ask it
            // to press itself. No mouse event, no focus change, pointer untouched.
            if mouseButton == .left && clickCount == 1 {
                let pid = appName.flatMap { Perception.findApp(named: $0)?.processIdentifier }
                if let target = PointerDriver.pressTarget(at: point, pid: pid),
                   PointerDriver.perform("AXPress", on: target.element)
                {
                    VirtualCursor.shared.pulse()
                    pauseAfterPress(300_000) // same settle time as the element-based AX press
                    return ToolResult(
                        success: true,
                        data: [
                            "method": "ax-at-point", "pointer": "virtual",
                            "element": target.name, "role": target.role,
                            "x": x, "y": y,
                        ]
                    )
                }
            }

            if let appName, let failure = focusForInput(appName) {
                return failure
            }
            do {
                try PointerDriver.click(at: point, button: mouseButton, count: clickCount)
                VirtualCursor.shared.pulse()
                Thread.sleep(forTimeInterval: 0.15)
                return ToolResult(
                    success: true,
                    data: ["method": "coordinate", "pointer": PointerDriver.borrowedLabel, "x": x, "y": y]
                )
            } catch {
                return ToolResult(success: false, error: "Click at (\(Int(x)), \(Int(y))) failed: \(error)")
            }
        }

        // Element-based click needs an index, a query or a domId
        guard indexed.element != nil || query != nil || domId != nil else {
            return ToolResult(
                success: false,
                error: "One of index, query/dom_id or x/y coordinates is required",
                suggestion: "Use pc_snapshot for numbered elements, or pc_find to search by name"
            )
        }

        // Build locator for AXorcist
        let locator = LocatorBuilder.build(query: query, role: role, domId: domId)

        // Find the element up front so the virtual cursor can travel to it and so
        // the AX press can target the exact element we resolved.
        let element = indexed.element ?? findElement(locator: locator, appName: appName)
        if let refusal = neverPress(element, query: query) { return refusal }
        if let frame = element?.frame() {
            VirtualCursor.shared.glide(to: CGPoint(x: frame.midX, y: frame.midY))
        }

        // Strategy 1a: AX-native press on the resolved element. Works with the
        // app in the background and never moves the user's pointer.
        if mouseButton == .left && clickCount == 1, let element,
           PointerDriver.supports("AXPress", on: element.underlyingElement),
           PointerDriver.perform("AXPress", on: element.underlyingElement)
        {
            VirtualCursor.shared.pulse()
            // A menu item's press returns before the menu has closed and the
            // choice has been applied. Acting again inside that window (focusing
            // a field, say) dismisses the menu and the choice is lost.
            let closesMenu = element.role() == "AXMenuItem"
            pressedMenuItem = closesMenu
            pauseAfterPress(300_000, always: closesMenu) // 300ms for background app to react (v1's timing)
            Log.info("AX-native press succeeded for '\(query ?? domId ?? "")'")
            return ToolResult(
                success: true,
                data: renamed([
                    "method": "ax-native", "pointer": "virtual",
                    "element": listed ?? element.computedName() ?? query ?? domId ?? "",
                ], from: renamedFrom)
            )
        }

        // Strategy 1c: web controls. Chromium does not offer AXPress on page
        // buttons and links (and silently ignores it if sent), but they can be
        // focused through accessibility and then activated with Space or
        // Return posted to the browser's process. No pointer, no focus change,
        // and the browser can stay in the background.
        if mouseButton == .left && clickCount == 1, let element,
           let activated = PointerDriver.activateByKey(element.underlyingElement)
        {
            VirtualCursor.shared.pulse()
            pauseAfterPress(200_000)
            return ToolResult(
                success: true,
                data: renamed([
                    "method": "ax-focus-" + activated, "pointer": "virtual",
                    "element": listed ?? element.computedName() ?? query ?? domId ?? "",
                ], from: renamedFrom)
            )
        }

        // Strategy 1d: a text field. Clicking one is asking for the keyboard to
        // go there, which accessibility can do directly.
        if mouseButton == .left && clickCount == 1, let element,
           PointerDriver.focusTextField(element.underlyingElement)
        {
            VirtualCursor.shared.pulse()
            return ToolResult(
                success: true,
                data: renamed([
                    "method": "ax-focus", "pointer": "virtual",
                    "element": listed ?? element.computedName() ?? query ?? domId ?? "",
                ], from: renamedFrom)
            )
        }

        // Strategy 1b: AX-native via AXorcist's PerformAction command, which
        // runs its own search and can reach elements ours did not resolve.
        if mouseButton == .left && clickCount == 1 && indexed.element == nil {
            let actionCmd = PerformActionCommand(
                appIdentifier: appName,
                locator: locator,
                action: "AXPress",
                maxDepthForSearch: Limits.semanticDepthBudget
            )
            let response = AXorcist.shared.runCommand(
                AXCommandEnvelope(commandID: "click", command: .performAction(actionCmd))
            )

            switch response {
            case .success:
                VirtualCursor.shared.pulse()
                pauseAfterPress(300_000) // 300ms for background app to react (v1's timing)
                Log.info("AX-native press succeeded for '\(query ?? domId ?? "")'")
                return ToolResult(
                    success: true,
                    data: [
                        "method": "ax-native", "pointer": "virtual",
                        "element": query ?? domId ?? "",
                    ]
                )
            case let .error(message, code, _):
                // Log the actual error so we know WHY AX-native failed
                Log.info("AX-native press failed for '\(query ?? domId ?? "")': [\(code)] \(message) - trying synthetic")
            }
        }

        // Strategy 2: synthetic click at the element's position (resolved above)

        // Strategy 2.5a: CDP fallback — try Chrome DevTools Protocol for web apps.
        // Much faster than VLM (~50ms vs 3s), but requires Chrome debug port.
        if element == nil, let query {
            if CDPBridge.isAvailable(),
               let cdpElements = CDPBridge.findElements(query: query),
               let firstMatch = cdpElements.first
            {
                let viewportX = firstMatch["centerX"] as? Int ?? 0
                let viewportY = firstMatch["centerY"] as? Int ?? 0

                // Get Chrome window origin for coordinate conversion
                let windowOrigin: (x: Double, y: Double)
                if let appName,
                   let app = Perception.findApp(named: appName),
                   let appElement = Element.application(for: app.processIdentifier),
                   let window = appElement.focusedWindow(),
                   let pos = window.position()
                {
                    windowOrigin = (Double(pos.x), Double(pos.y))
                } else {
                    windowOrigin = (0, 0)
                }

                let screenCoords = CDPBridge.viewportToScreen(
                    viewportX: Double(viewportX),
                    viewportY: Double(viewportY),
                    windowX: windowOrigin.x,
                    windowY: windowOrigin.y
                )

                if let appName, let failure = focusForInput(appName) {
                    return failure
                }

                do {
                    let cdpPoint = CGPoint(x: screenCoords.x, y: screenCoords.y)
                    VirtualCursor.shared.glide(to: cdpPoint)
                    try PointerDriver.click(at: cdpPoint, button: mouseButton, count: clickCount)
                    VirtualCursor.shared.pulse()
                    Thread.sleep(forTimeInterval: 0.15)
                    Log.info("CDP click: '\(query)' at (\(Int(screenCoords.x)), \(Int(screenCoords.y)))")
                    return ToolResult(
                        success: true,
                        data: [
                            "method": "cdp-grounded", "pointer": PointerDriver.borrowedLabel,
                            "element": query,
                            "x": screenCoords.x,
                            "y": screenCoords.y,
                            "match_type": firstMatch["matchType"] as? String ?? "unknown",
                        ]
                    )
                } catch {
                    Log.warn("CDP click failed: \(error)")
                }
            }
        }

        // Strategy 2.5b: Vision fallback — if AX AND CDP can't find it, try VLM grounding.
        // This handles web apps (Chrome AXGroup elements) and dynamic content.
        if element == nil, let query {
            if let visionResult = VisionPerception.visionFallbackClick(
                query: query,
                appName: appName
            ) {
                // VLM found the element — click at the grounded coordinates
                let vx = visionResult.data?["x"] as? Double ?? 0
                let vy = visionResult.data?["y"] as? Double ?? 0

                if let appName, let failure = focusForInput(appName) {
                    return failure
                }

                do {
                    let visionPoint = CGPoint(x: vx, y: vy)
                    VirtualCursor.shared.glide(to: visionPoint)
                    try PointerDriver.click(at: visionPoint, button: mouseButton, count: clickCount)
                    VirtualCursor.shared.pulse()
                    Thread.sleep(forTimeInterval: 0.15)
                    return ToolResult(
                        success: true,
                        data: [
                            "method": "vlm-grounded", "pointer": PointerDriver.borrowedLabel,
                            "element": query,
                            "x": vx,
                            "y": vy,
                            "confidence": visionResult.data?["confidence"] as? Double ?? 0,
                            "inference_ms": visionResult.data?["inference_ms"] as? Int ?? 0,
                        ]
                    )
                } catch {
                    return ToolResult(
                        success: false,
                        error: "VLM-grounded click at (\(Int(vx)), \(Int(vy))) failed: \(error)"
                    )
                }
            }
        }

        guard let element else {
            return ToolResult(
                success: false,
                error: "Element '\(query ?? domId ?? "")' not found in \(appName ?? "frontmost app")",
                suggestion: "Use pc_find to see what elements are available, or pc_ground for visual search"
            )
        }

        // Pre-flight: check actionable
        if !element.isActionable() {
            return ToolResult(
                success: false,
                error: "Element '\(element.computedName() ?? query ?? "")' is not actionable",
                suggestion: "Element may be disabled, hidden, or off-screen. Use pc_inspect to check."
            )
        }

        // Focus the app for synthetic input
        if let appName, let failure = focusForInput(appName) {
            return failure
        }

        guard let frame = element.frame() else {
            return ToolResult(
                success: false,
                error: "Element '\(element.computedName() ?? query ?? "")' has no frame",
                suggestion: "Element may be off-screen. Use pc_inspect to check."
            )
        }

        do {
            try PointerDriver.click(
                at: CGPoint(x: frame.midX, y: frame.midY),
                button: mouseButton,
                count: clickCount
            )
            VirtualCursor.shared.pulse()
            Thread.sleep(forTimeInterval: 0.15)
            return ToolResult(
                success: true,
                data: [
                    "method": "synthetic", "pointer": PointerDriver.borrowedLabel,
                    "element": element.computedName() ?? query ?? "",
                ]
            )
        } catch {
            return ToolResult(
                success: false,
                error: "Click failed: \(error)",
                suggestion: "Try pc_inspect on the element, or use x/y coordinates"
            )
        }
    }

    // MARK: - pc_type

    /// True if the string contains any non-ASCII character (e.g. Chinese, emoji).
    /// Synthetic key events (AXorcist typeText) use key codes and produce wrong
    /// output for such characters; we use clipboard paste instead.
    private static func containsNonASCII(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value > 0x7F }
    }

    /// Type text by pasting from clipboard. Used for non-ASCII text so IME/Unicode
    /// is preserved instead of wrong key-code output (e.g. "aaaaa" for Chinese).
    static func typeViaPaste(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        // Keep every item and type the user had (images and files, not just text).
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        // Ask clipboard managers not to record this entry (nspasteboard.org convention).
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        guard pasteboard.writeObjects([item]) else {
            throw NSError(domain: "Actions", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to set pasteboard"])
        }
        defer {
            // Paste is asynchronous in the target app. Restoring too early makes
            // it paste the user's old clipboard instead of our text.
            Thread.sleep(forTimeInterval: 0.3)
            pasteboard.clearContents()
            let restored: [NSPasteboardItem] = saved.map { entries in
                let item = NSPasteboardItem()
                for (type, data) in entries { item.setData(data, forType: type) }
                return item
            }
            if !restored.isEmpty { pasteboard.writeObjects(restored) }
        }
        try Element.performHotkey(keys: ["cmd", "v"])
        FocusManager.clearModifierFlags()
    }

    /// Type text into a field. Uses AXorcist's SetFocusedValue command for
    /// AX-native typing (focus + setValue), with synthetic typeText fallback.
    public static func typeText(
        text: String,
        into: String?,
        domId: String?,
        appName: String?,
        clear: Bool,
        index: Int? = nil
    ) -> ToolResult {
        let indexed = indexedTarget(index, appName: appName, query: into)
        if let failure = indexed.failure { return failure }
        let appName = indexed.appName
        let indexLabel = indexed.element == nil ? nil : (index.map { "[e\($0)]" } ?? into)

        // If target field specified, find it and type into it
        if let fieldName = into ?? domId ?? indexLabel {
            // For 'into' parameter, use field-specific search that prefers
            // editable/interactive roles (AXComboBox, AXTextField, AXTextArea)
            // over random elements that happen to contain the text.
            // This prevents into:"To" from matching "Skip to content" instead
            // of the actual "To recipients" field.
            let element: Element?
            if let resolved = indexed.element {
                element = resolved
            } else if let domId {
                let locator = LocatorBuilder.build(domId: domId)
                element = findElement(locator: locator, appName: appName)
            } else if let into {
                element = findEditableField(named: into, appName: appName)
            } else {
                element = nil
            }

            guard let element else {
                return ToolResult(
                    success: false,
                    error: "Field '\(fieldName)' not found",
                    suggestion: "Pass the field's id from pc_snapshot as index (for example index:\"e3\"), or its exact name as into"
                )
            }

            // Typing needs something that holds text. Without this check the
            // fallback below clicks the target to focus it, so "type into
            // [23]" aimed at a button presses that button instead.
            let targetRole = element.role() ?? ""
            if !editableRoles.contains(targetRole), !element.isAttributeSettable(named: "AXValue") {
                return ToolResult(
                    success: false,
                    error: "'\(fieldName)' is a \(Snapshot.shortRole(targetRole)), not a text field, so nothing was typed",
                    suggestion: "Choose a text field, click this element instead, or type without a target to send keys to the app"
                )
            }

            // Strategy 1: AX-native setValue
            // Try setting value directly via AX API (works for native fields)
            if element.isAttributeSettable(named: "AXValue") {
                // Focus the element first
                _ = element.setValue(true, forAttribute: "AXFocused")
                Thread.sleep(forTimeInterval: 0.1)

                if clear {
                    _ = element.setValue("", forAttribute: "AXValue")
                    Thread.sleep(forTimeInterval: 0.05)
                }

                let setOk = element.setValue(text, forAttribute: "AXValue")
                if setOk {
                    usleep(150_000) // 150ms (v1's timing)

                    // Verify: read AXValue DIRECTLY via raw API on the SAME element.
                    // v1's proven pattern: raw AXUIElementCopyAttributeValue, not
                    // computedName/title fallbacks which return wrong data from
                    // stale handles or overlay elements.
                    var readBackRef: CFTypeRef?
                    let readBackOk = AXUIElementCopyAttributeValue(
                        element.underlyingElement,
                        "AXValue" as CFString,
                        &readBackRef
                    )
                    let readback: String?
                    if readBackOk == .success, let ref = readBackRef {
                        if let str = ref as? String, !str.isEmpty {
                            readback = str
                        } else if CFGetTypeID(ref) == CFStringGetTypeID() {
                            readback = (ref as! CFString) as String
                        } else {
                            readback = nil
                        }
                    } else {
                        readback = nil
                    }

                    // Check if first 10 chars match (v1's threshold)
                    let textPrefix = String(text.prefix(10))
                    if let readback, readback.contains(textPrefix) {
                        return ToolResult(
                            success: true,
                            data: [
                                "method": "ax-native-setValue",
                                "field": fieldName,
                                "typed": text,
                                "readback": String(readback.prefix(200)),
                            ]
                        )
                    }
                    Log.info("setValue for '\(fieldName)' readback doesn't match - falling back to click-then-type")
                }
            }

            // Strategy 1.5: focus the field through accessibility and send the
            // keys to its process. The app stays in the background and the
            // user's pointer is not used. Verified by reading the field back.
            var fieldPID: pid_t = 0
            let hasPID = AXUIElementGetPid(element.underlyingElement, &fieldPID) == .success && fieldPID > 0
            if TargetedKeyboard.isEnabled, hasPID {
                let before = readbackFromElement(element)
                if element.setValue(true, forAttribute: "AXFocused") {
                    Thread.sleep(forTimeInterval: 0.1)
                    if clear {
                        // Select the whole field through accessibility; the
                        // typed text then replaces the selection.
                        var range = CFRange(location: 0, length: before.count + 4096)
                        if let all = AXValueCreate(.cfRange, &range) {
                            AXUIElementSetAttributeValue(
                                element.underlyingElement, kAXSelectedTextRangeAttribute as CFString, all
                            )
                        }
                    }
                    TargetedKeyboard.type(text, to: fieldPID)
                    Thread.sleep(forTimeInterval: 0.2)
                    let readback = readbackFromElement(element)
                    if readback.contains(String(text.prefix(10))) {
                        return ToolResult(
                            success: true,
                            data: [
                                "method": "ax-focus-then-keys", "pointer": "virtual",
                                "field": fieldName, "typed": text,
                                "verified": true, "readback": readback,
                            ]
                        )
                    }
                    if readback != before {
                        // Something landed but not what we sent. Retyping would double it.
                        return ToolResult(
                            success: true,
                            data: [
                                "method": "ax-focus-then-keys", "pointer": "virtual",
                                "field": fieldName, "typed": text,
                                "verified": false, "readback": readback,
                            ],
                            suggestion: "The field changed but does not show the typed text. Check it before continuing."
                        )
                    }
                    Log.info("Background typing into '\(fieldName)' had no effect - bringing the app forward")
                }
            }

            // Strategy 2: bring the app forward, click the field, then type.
            // Needed for apps that ignore keys while they are in the background.
            if let appName, let failure = focusForInput(appName) {
                return failure
            }

            // Click the element to put cursor in the field
            if element.isActionable(), let frame = element.frame() {
                do {
                    let center = CGPoint(x: frame.midX, y: frame.midY)
                    VirtualCursor.shared.glide(to: center)
                    try PointerDriver.click(at: center, button: .left, count: 1)
                    VirtualCursor.shared.pulse()
                    Thread.sleep(forTimeInterval: 0.15)
                } catch {
                    // Click failed, try AX focus as fallback
                    _ = element.setValue(true, forAttribute: "AXFocused")
                    Thread.sleep(forTimeInterval: 0.1)
                }
            } else {
                _ = element.setValue(true, forAttribute: "AXFocused")
                Thread.sleep(forTimeInterval: 0.1)
            }

            do {
                try sendText(text, clear: clear, to: hasPID ? fieldPID : nil)
                Thread.sleep(forTimeInterval: 0.15)

                // Read back from the same element we found earlier
                let readback = readbackFromElement(element)
                let textPrefix = String(text.prefix(10))
                let verified = readback.contains(textPrefix)
                return ToolResult(
                    success: true,
                    data: [
                        "method": containsNonASCII(text) ? "click-then-paste" : "click-then-type",
                        "field": fieldName,
                        "typed": text,
                        "verified": verified,
                        "readback": readback,
                    ]
                )
            } catch {
                return ToolResult(success: false, error: "Type into '\(fieldName)' failed: \(error)")
            }
        }

        // No target field - type at current focus
        // Clearing uses Cmd+A, which only works through the frontmost app.
        if let appName, let failure = focusForInput(appName, keysOnly: !clear) {
            return failure
        }

        do {
            try sendText(text, clear: clear, to: targetPID(appName))
            Thread.sleep(forTimeInterval: 0.1)
            return ToolResult(
                success: true,
                data: [
                    "method": containsNonASCII(text) ? "synthetic-paste" : "synthetic-at-focus",
                    "typed": text,
                ]
            )
        } catch {
            return ToolResult(success: false, error: "Type failed: \(error)")
        }
    }

    // MARK: - pc_press

    /// Press a single key with optional modifiers.
    public static func pressKey(
        key: String,
        modifiers: [String]?,
        appName: String?
    ) -> ToolResult {
        if PressGuard.isActive, ["return", "enter", "space"].contains(key.lowercased()),
           let pid = targetPID(appName), let control = PointerDriver.focusedControl(pid: pid),
           let refusal = PressGuard.refusal(name: control.name, role: control.role)
        {
            return refusal
        }
        let pressKeys = (modifiers ?? []) + [key]
        let pressTargeted = TargetedKeyboard.isEnabled
            && (TargetedKeyboard.canSend(pressKeys) || (key.count == 1 && (modifiers?.isEmpty ?? true)))
        if let appName, let failure = focusForInput(appName, keysOnly: pressTargeted) {
            return failure
        }

        if pressTargeted, let pid = targetPID(appName) {
            let keys = pressKeys
            if TargetedKeyboard.canSend(keys) {
                TargetedKeyboard.chord(keys, to: pid)
                return ToolResult(success: true, data: ["key": key])
            }
            if key.count == 1, modifiers?.isEmpty ?? true {
                TargetedKeyboard.type(key, to: pid)
                return ToolResult(success: true, data: ["key": key])
            }
        }

        do {
            if let modifiers, !modifiers.isEmpty {
                // Key with modifiers = hotkey
                try Element.performHotkey(keys: modifiers + [key])
                FocusManager.clearModifierFlags()
                usleep(10_000) // 10ms for modifier clear to propagate
            } else if let specialKey = mapSpecialKey(key) {
                try Element.typeKey(specialKey)
            } else if key.count == 1 {
                try Element.typeText(key)
            } else {
                return ToolResult(
                    success: false,
                    error: "Unknown key: '\(key)'",
                    suggestion: "Valid: return, tab, escape, space, delete, up, down, left, right, f1-f12"
                )
            }
            return ToolResult(success: true, data: ["key": key])
        } catch {
            return ToolResult(success: false, error: "Key press failed: \(error)")
        }
    }

    // MARK: - pc_hotkey

    /// Press a key combination. Clears modifier flags after to prevent stuck keys.
    public static func hotkey(
        keys: [String],
        appName: String?
    ) -> ToolResult {
        guard !keys.isEmpty else {
            return ToolResult(success: false, error: "Keys array cannot be empty")
        }

        let hotkeyTargeted = TargetedKeyboard.isEnabled && TargetedKeyboard.canSend(keys)
        if let appName, let failure = focusForInput(appName, keysOnly: hotkeyTargeted) {
            return failure
        }

        if hotkeyTargeted, let pid = targetPID(appName) {
            TargetedKeyboard.chord(keys, to: pid)
            usleep(200_000) // 200ms for app to process the hotkey result
            return ToolResult(success: true, data: ["keys": keys])
        }

        do {
            try Element.performHotkey(keys: keys)
            // Clear modifier flags IMMEDIATELY after the key events.
            // v1's proven order: clear first, delay after.
            // If we delay before clearing, the system thinks Cmd is held for 200ms
            // which makes Chrome enter shortcut-hint mode (the "flicker") and
            // disrupts text selection in the address bar.
            FocusManager.clearModifierFlags()
            usleep(10_000) // 10ms for clear event to propagate
            usleep(200_000) // 200ms for app to process the hotkey result
            return ToolResult(success: true, data: ["keys": keys])
        } catch {
            FocusManager.clearModifierFlags()
            return ToolResult(success: false, error: "Hotkey \(keys.joined(separator: "+")) failed: \(error)")
        }
    }

    // MARK: - pc_scroll

    /// Scroll in a direction. Uses AXorcist's element-based scroll when app is
    /// specified (auto-handles multi-monitor via AX coordinates). Falls back to
    /// InputDriver.scroll with explicit coordinates when x,y are provided.
    public static func scroll(
        direction: String,
        amount: Int?,
        appName: String?,
        x: Double?,
        y: Double?
    ) -> ToolResult {
        let scrollAmount = amount ?? 3

        guard let scrollDir = mapScrollDirection(direction) else {
            return ToolResult(success: false, error: "Invalid direction: '\(direction)'")
        }

        // If explicit coordinates provided, use InputDriver directly
        if let x, let y {
            if let appName, let failure = focusForInput(appName) {
                return failure
            }
            do {
                try Element.scrollAt(
                    CGPoint(x: x, y: y),
                    direction: scrollDir,
                    amount: scrollAmount
                )
                return ToolResult(success: true, data: ["direction": direction, "amount": scrollAmount])
            } catch {
                return ToolResult(success: false, error: "Scroll failed: \(error)")
            }
        }

        // If app specified, use element-based scroll on the focused window.
        // AXorcist's element.scroll() calculates coordinates from the element's
        // frame, which auto-handles multi-monitor setups.
        if let appName {
            guard let appElement = Perception.appElement(for: appName) else {
                return ToolResult(success: false, error: "Application '\(appName)' not found")
            }
            guard let window = appElement.focusedWindow() ?? appElement.mainWindow() else {
                return ToolResult(success: false, error: "No window found for '\(appName)'")
            }

            // Find a scrollable area within the window (AXWebArea for browsers,
            // AXScrollArea for native apps, or the window itself)
            let scrollTarget = findScrollable(in: window) ?? window

            do {
                try scrollTarget.scroll(direction: scrollDir, amount: scrollAmount)
                return ToolResult(success: true, data: ["direction": direction, "amount": scrollAmount])
            } catch {
                // Fallback: try scrolling at the window's center
                if let frame = window.frame() {
                    let center = CGPoint(x: frame.midX, y: frame.midY)
                    do {
                        try Element.scrollAt(center, direction: scrollDir, amount: scrollAmount)
                        return ToolResult(success: true, data: ["direction": direction, "amount": scrollAmount])
                    } catch {
                        return ToolResult(success: false, error: "Scroll failed: \(error)")
                    }
                }
                return ToolResult(success: false, error: "Scroll failed: \(error)")
            }
        }

        // No app, no coordinates - scroll at current mouse position
        do {
            let lines = Double(scrollAmount)
            let deltaY: Double = (direction == "up" ? lines * 10 : -lines * 10)
            try InputDriver.scroll(deltaY: deltaY, at: nil)
            return ToolResult(success: true, data: ["direction": direction, "amount": scrollAmount])
        } catch {
            return ToolResult(success: false, error: "Scroll failed: \(error)")
        }
    }

    /// Find a scrollable element within a window (AXScrollArea or AXWebArea).
    private static func findScrollable(in element: Element, depth: Int = 0) -> Element? {
        guard depth < 5 else { return nil }
        let role = element.role() ?? ""
        if role == "AXScrollArea" || role == "AXWebArea" { return element }
        guard let children = element.children() else { return nil }
        for child in children {
            if let found = findScrollable(in: child, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    private static func mapScrollDirection(_ direction: String) -> ScrollDirection? {
        switch direction.lowercased() {
        case "up": .up
        case "down": .down
        case "left": .left
        case "right": .right
        default: nil
        }
    }

    // MARK: - pc_hover

    /// Move cursor to an element or coordinates without clicking.
    /// Triggers hover effects: tooltips, CSS :hover, menu navigation.
    public static func hover(
        query: String?,
        role: String?,
        domId: String?,
        appName: String?,
        x: Double?,
        y: Double?,
        index: Int? = nil
    ) -> ToolResult {
        let indexed = indexedTarget(index, appName: appName, query: query, role: role)
        if let failure = indexed.failure { return failure }
        let appName = indexed.appName

        // Coordinate-based hover
        if indexed.element == nil, let x, let y {
            if let appName, let failure = focusForInput(appName) {
                return failure
            }
            do {
                // Hover effects follow the real pointer, so it has to move and stay.
                VirtualCursor.shared.glide(to: CGPoint(x: x, y: y))
                try InputDriver.move(to: CGPoint(x: x, y: y))
                return ToolResult(success: true, data: ["method": "coordinate", "pointer": "system", "x": x, "y": y])
            } catch {
                return ToolResult(success: false, error: "Hover at (\(Int(x)), \(Int(y))) failed: \(error)")
            }
        }

        // Element-based hover needs an index, a query or a domId
        guard indexed.element != nil || query != nil || domId != nil else {
            return ToolResult(
                success: false,
                error: "One of index, query/dom_id or x/y coordinates is required",
                suggestion: "Use pc_snapshot for numbered elements, or pc_find to search by name"
            )
        }

        let locator = LocatorBuilder.build(query: query, role: role, domId: domId)
        let element = indexed.element ?? findElement(locator: locator, appName: appName)

        guard let element else {
            return ToolResult(
                success: false,
                error: "Element '\(query ?? domId ?? "")' not found in \(appName ?? "frontmost app")",
                suggestion: "Use pc_find to see what elements are available"
            )
        }

        guard let frame = element.frame() else {
            return ToolResult(
                success: false,
                error: "Element '\(element.computedName() ?? query ?? "")' has no frame",
                suggestion: "Element may be off-screen. Use pc_inspect to check."
            )
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)

        if let appName, let failure = focusForInput(appName) {
            return failure
        }

        do {
            VirtualCursor.shared.glide(to: center)
            try InputDriver.move(to: center)
            return ToolResult(
                success: true,
                data: [
                    "method": "element", "pointer": "system",
                    "element": element.computedName() ?? query ?? "",
                    "x": center.x, "y": center.y,
                ]
            )
        } catch {
            return ToolResult(success: false, error: "Hover failed: \(error)")
        }
    }

    // MARK: - pc_long_press

    /// Press and hold at an element or coordinates for a duration.
    /// Triggers long-press menus, Force Touch previews, drag initiation.
    public static func longPress(
        query: String?,
        role: String?,
        domId: String?,
        appName: String?,
        x: Double?,
        y: Double?,
        duration: Double?,
        button: String?,
        index: Int? = nil
    ) -> ToolResult {
        let indexed = indexedTarget(index, appName: appName, query: query, role: role)
        if let failure = indexed.failure { return failure }
        let appName = indexed.appName

        let holdDuration = min(duration ?? 1.0, 10.0)
        let mouseButton: MouseButton = (button == "right") ? .right : .left

        // Resolve target point
        let targetPoint: CGPoint

        if let element = indexed.element {
            guard let frame = element.frame() else {
                return ToolResult(
                    success: false,
                    error: "Element [\(index ?? 0)] has no frame",
                    suggestion: "Call pc_snapshot again; the element may have gone off-screen"
                )
            }
            targetPoint = CGPoint(x: frame.midX, y: frame.midY)
        } else if let x, let y {
            targetPoint = CGPoint(x: x, y: y)
        } else if query != nil || domId != nil {
            let locator = LocatorBuilder.build(query: query, role: role, domId: domId)
            guard let element = findElement(locator: locator, appName: appName) else {
                return ToolResult(
                    success: false,
                    error: "Element '\(query ?? domId ?? "")' not found in \(appName ?? "frontmost app")",
                    suggestion: "Use pc_find to see what elements are available"
                )
            }
            guard let frame = element.frame() else {
                return ToolResult(
                    success: false,
                    error: "Element '\(element.computedName() ?? query ?? "")' has no frame",
                    suggestion: "Element may be off-screen. Use pc_inspect to check."
                )
            }
            targetPoint = CGPoint(x: frame.midX, y: frame.midY)
        } else {
            return ToolResult(
                success: false,
                error: "Either query/dom_id or x/y coordinates required",
                suggestion: "Use pc_find to locate elements, or pc_element_at for coordinates"
            )
        }

        if let refusal = neverPress(indexed.element, query: query) ?? neverPress(at: targetPoint, appName: appName) {
            return refusal
        }
        if let appName, let failure = focusForInput(appName) {
            return failure
        }

        do {
            VirtualCursor.shared.glide(to: targetPoint)
            VirtualCursor.shared.pulse()
            try PointerDriver.pressHold(at: targetPoint, button: mouseButton, duration: holdDuration)
            Thread.sleep(forTimeInterval: 0.15)
            return ToolResult(
                success: true,
                data: [
                    "method": (query != nil || domId != nil) ? "element" : "coordinate",
                    "pointer": PointerDriver.borrowedLabel,
                    "x": targetPoint.x, "y": targetPoint.y,
                    "duration": holdDuration, "button": button ?? "left",
                ]
            )
        } catch {
            return ToolResult(
                success: false,
                error: "Long press at (\(Int(targetPoint.x)), \(Int(targetPoint.y))) failed: \(error)"
            )
        }
    }

    // MARK: - pc_drag

    /// Drag from one point to another. Posts mouseDown, holds briefly for grab
    /// registration, interpolates drag steps, then posts mouseUp.
    public static func drag(
        query: String?,
        role: String?,
        domId: String?,
        appName: String?,
        fromX: Double?,
        fromY: Double?,
        toX: Double,
        toY: Double,
        duration: Double?,
        holdDuration: Double?
    ) -> ToolResult {
        // Resolve start point
        let startPoint: CGPoint

        if let fromX, let fromY {
            startPoint = CGPoint(x: fromX, y: fromY)
        } else if query != nil || domId != nil {
            let locator = LocatorBuilder.build(query: query, role: role, domId: domId)
            guard let element = findElement(locator: locator, appName: appName) else {
                return ToolResult(
                    success: false,
                    error: "Drag source '\(query ?? domId ?? "")' not found in \(appName ?? "frontmost app")",
                    suggestion: "Use pc_find to locate the element, or provide from_x/from_y coordinates"
                )
            }
            guard let frame = element.frame() else {
                return ToolResult(
                    success: false,
                    error: "Drag source '\(query ?? domId ?? "")' has no frame",
                    suggestion: "Use pc_inspect to check the element, or provide from_x/from_y coordinates"
                )
            }
            startPoint = CGPoint(x: frame.midX, y: frame.midY)
        } else {
            return ToolResult(
                success: false,
                error: "Drag source required: provide query/dom_id or from_x/from_y",
                suggestion: "Use pc_find to locate elements, or pc_element_at for coordinates"
            )
        }

        let endPoint = CGPoint(x: toX, y: toY)

        // Focus the app for synthetic input
        if let appName, let failure = focusForInput(appName) {
            return failure
        }

        // Compute drag parameters
        let clampedDuration = min(10.0, max(0.1, duration ?? 0.5))
        let steps = max(10, Int(clampedDuration * 60))
        let interStepDelay = clampedDuration / Double(steps)
        let clampedHold = min(5.0, max(0.0, holdDuration ?? 0.1))

        // Inlined rather than calling InputDriver.drag() because:
        // 1. We need hold-before-drag (InputDriver doesn't support it)
        // 2. InputDriver.drag() hardcodes .leftMouseDragged for all button types

        VirtualCursor.shared.glide(to: startPoint)
        let userPointer = PointerDriver.userPointerLocation()

        // 1. Mouse down at start
        guard let downEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: startPoint,
            mouseButton: .left
        ) else {
            return ToolResult(success: false, error: "Failed to create mouse down event")
        }
        downEvent.post(tap: .cghidEventTap)

        // 2. Hold for grab registration
        if clampedHold > 0 {
            Thread.sleep(forTimeInterval: clampedHold)
        }

        // 3. Drag steps (linear interpolation)
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let pos = CGPoint(
                x: startPoint.x + (endPoint.x - startPoint.x) * t,
                y: startPoint.y + (endPoint.y - startPoint.y) * t
            )
            if let dragEvent = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: pos,
                mouseButton: .left
            ) {
                dragEvent.post(tap: .cghidEventTap)
            }
            VirtualCursor.shared.track(pos)
            if interStepDelay > 0 {
                Thread.sleep(forTimeInterval: interStepDelay)
            }
        }

        // 4. Mouse up at end
        guard let upEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: endPoint,
            mouseButton: .left
        ) else {
            Log.error("Drag: mouseUp event creation failed — mouse may be stuck in pressed state")
            return ToolResult(
                success: false,
                data: [
                    "from": ["x": Int(startPoint.x), "y": Int(startPoint.y)],
                    "to": ["x": Int(endPoint.x), "y": Int(endPoint.y)],
                    "warning": "mouseUp_failed",
                ],
                error: "Drag completed but mouseUp failed — mouse may be stuck. Click anywhere to recover."
            )
        }
        upEvent.post(tap: .cghidEventTap)

        // 5. Settle time, then give the user their pointer back
        Thread.sleep(forTimeInterval: 0.15)
        PointerDriver.returnPointer(to: userPointer)

        Log.info("Drag from (\(Int(startPoint.x)),\(Int(startPoint.y))) to (\(Int(endPoint.x)),\(Int(endPoint.y))) - \(steps) steps in \(clampedDuration)s")

        return ToolResult(
            success: true,
            data: [
                "method": query != nil || domId != nil ? "element-to-coordinate" : "coordinate",
                "pointer": PointerDriver.borrowedLabel,
                "from": ["x": Int(startPoint.x), "y": Int(startPoint.y)],
                "to": ["x": Int(endPoint.x), "y": Int(endPoint.y)],
                "steps": steps, "duration": clampedDuration,
            ]
        )
    }

    // MARK: - pc_window

    /// Window management operations.
    public static func manageWindow(
        action: String,
        appName: String,
        windowTitle: String?,
        x: Double?, y: Double?,
        width: Double?, height: Double?
    ) -> ToolResult {
        guard let appElement = Perception.appElement(for: appName) else {
            return ToolResult(success: false, error: "Application '\(appName)' not found")
        }

        if action == "list" {
            guard let windows = appElement.windows() else {
                return ToolResult(success: true, data: ["windows": [] as [Any], "count": 0])
            }
            let infos: [[String: Any]] = windows.compactMap { win in
                var info: [String: Any] = [:]
                if let title = win.title() { info["title"] = title }
                if let pos = win.position() { info["position"] = ["x": Int(pos.x), "y": Int(pos.y)] }
                if let size = win.size() { info["size"] = ["width": Int(size.width), "height": Int(size.height)] }
                if let minimized = win.isMinimized() { info["minimized"] = minimized }
                if let fullscreen = win.isFullScreen() { info["fullscreen"] = fullscreen }
                return info.isEmpty ? nil : info
            }
            return ToolResult(success: true, data: ["windows": infos, "count": infos.count])
        }

        let window: Element? = if let windowTitle {
            appElement.windows()?.first { $0.title()?.localizedCaseInsensitiveContains(windowTitle) == true }
        } else {
            appElement.focusedWindow() ?? appElement.mainWindow()
        }

        guard let window else {
            return ToolResult(
                success: false,
                error: "Window not found in '\(appName)'",
                suggestion: "Use pc_window with action:'list' to see windows"
            )
        }

        switch action.lowercased() {
        case "minimize":
            _ = window.minimizeWindow()
            return ToolResult(success: true, data: ["action": "minimize"])
        case "maximize":
            _ = window.maximizeWindow()
            return ToolResult(success: true, data: ["action": "maximize"])
        case "close":
            _ = window.closeWindow()
            return ToolResult(success: true, data: ["action": "close"])
        case "restore":
            _ = window.showWindow()
            return ToolResult(success: true, data: ["action": "restore"])
        case "move":
            guard let x, let y else {
                return ToolResult(success: false, error: "move requires x and y parameters")
            }
            _ = window.moveWindow(to: CGPoint(x: x, y: y))
            return ToolResult(success: true, data: ["action": "move", "x": x, "y": y])
        case "resize":
            guard let width, let height else {
                return ToolResult(success: false, error: "resize requires width and height parameters")
            }
            _ = window.resizeWindow(to: CGSize(width: width, height: height))
            return ToolResult(success: true, data: ["action": "resize", "width": width, "height": height])
        default:
            return ToolResult(success: false, error: "Unknown action: '\(action)'")
        }
    }

    // MARK: - Keyboard delivery

    /// The process that should receive keys: the named app, or the frontmost one.
    /// Refusal when the resolved element, or the name it was asked for, is on the
    /// user's never-press list (PressGuard).
    private static func neverPress(_ element: Element?, query: String?) -> ToolResult? {
        guard PressGuard.isActive else { return nil }
        if let element {
            return PressGuard.refusal(name: element.computedName(), role: element.role())
        }
        return PressGuard.refusal(name: query, role: nil)
    }

    /// Same check for a click at a point: any pressable control there counts.
    private static func neverPress(at point: CGPoint, appName: String?) -> ToolResult? {
        guard PressGuard.isActive else { return nil }
        let pid = appName.flatMap { Perception.findApp(named: $0)?.processIdentifier }
        for control in PointerDriver.controls(at: point, pid: pid) {
            if let refusal = PressGuard.refusal(name: control.name, role: control.role) { return refusal }
        }
        return nil
    }

    private static func renamed(_ data: [String: Any], from earlier: String?) -> [String: Any] {
        guard let earlier else { return data }
        var data = data
        data["listed_as"] = earlier
        data["note"] = "This control was listed as \"\(earlier)\" in your last snapshot and has a different name now."
        return data
    }

    /// Set while a pc_do sequence is between steps. The pause after an
    /// accessibility press exists so that the change report that follows sees
    /// the result; between steps nothing is reported, and the next step's own
    /// accessibility call waits for the app anyway.
    public static var betweenSequenceSteps = false

    /// True when the last accessibility press was on a menu item. pc_do reads
    /// it to let the menu finish closing before the next step.
    public static var pressedMenuItem = false

    private static func pauseAfterPress(_ microseconds: UInt32, always: Bool = false) {
        usleep(betweenSequenceSteps && !always ? min(microseconds, 30_000) : microseconds)
    }

    private static func targetPID(_ appName: String?) -> pid_t? {
        if let appName { return Perception.findApp(named: appName)?.processIdentifier }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    /// Type `text`, optionally clearing the field first. The text is posted
    /// to `pid` so it cannot reach any other app. Only when targeted delivery
    /// is switched off, or the process is unknown, does it go to whatever is
    /// frontmost. Clearing always uses the frontmost app (Cmd+A is a menu
    /// shortcut), so callers that clear must have confirmed focus first.
    private static func sendText(_ text: String, clear: Bool, to pid: pid_t?) throws {
        if clear {
            // A menu shortcut: it has to go through the frontmost app, which
            // the caller has confirmed is the target.
            try Element.performHotkey(keys: ["cmd", "a"])
            Thread.sleep(forTimeInterval: 0.05)
            try Element.typeKey(.delete)
            Thread.sleep(forTimeInterval: 0.05)
            FocusManager.clearModifierFlags()
        }
        if TargetedKeyboard.isEnabled, let pid {
            TargetedKeyboard.type(text, to: pid)
            return
        }
        if containsNonASCII(text) {
            try typeViaPaste(text)
        } else {
            try Element.typeText(text, delay: 0.01)
        }
    }

    // MARK: - Focus guard

    /// Bring `appName` to the front for synthetic input, or return the failure
    /// to report. Synthetic mouse and key events go to whatever is frontmost
    /// when they arrive, so if the target cannot be confirmed there, nothing
    /// may be sent: the alternative is typing into some other app.
    ///
    /// Keys are posted to the target process and cannot go astray, so for
    /// keyboard-only input (`keysOnly`) coming to the front is best effort:
    /// it helps apps that ignore background keys, and failing is not fatal.
    private static func focusForInput(_ appName: String, keysOnly: Bool = false) -> ToolResult? {
        guard let app = Perception.findApp(named: appName) else {
            return ToolResult(
                success: false,
                error: "Application '\(appName)' not found",
                suggestion: "Use pc_state to see all running apps"
            )
        }
        let isFront = FocusManager.bringToFront(app)
        if keysOnly, TargetedKeyboard.isEnabled { return nil }
        guard isFront else {
            return ToolResult(
                success: false,
                error: "Could not bring '\(appName)' to the front, so no input was sent",
                suggestion: "Input would have gone to a different app. Retry, or target an element by index "
                    + "so it can be operated through accessibility without focus."
            )
        }
        return nil
    }

    // MARK: - Snapshot index resolution

    /// Outcome of looking up an optional `index` argument.
    private struct IndexedTarget {
        var element: Element?
        var appName: String?
        var failure: ToolResult?
        /// The element's name as the snapshot listed it. Results echo this one:
        /// an app's internal title can differ ("AllClear" for a key shown as
        /// "Clear"), and an echo that contradicts the screen hides mistakes.
        var listedName: String?
    }

    /// Resolve a pc_snapshot number to its element. With no index this is a
    /// pass-through. The snapshot's own app fills in a missing `app` argument.
    private static func indexedTarget(
        _ index: Int?, appName: String?, query: String? = nil, role: String? = nil
    ) -> IndexedTarget {
        guard let index else {
            // No number given: a name is looked up in the snapshot first, so
            // the agent acts on the element it saw there.
            if let query, let unclear = Snapshot.ambiguity(named: query, role: role, appName: appName) {
                return IndexedTarget(element: nil, appName: appName, failure: unclear)
            }
            if let query, let entry = Snapshot.find(query: query, role: role, appName: appName) {
                return IndexedTarget(element: Element(entry.element), appName: appName, failure: nil, listedName: entry.name)
            }
            return IndexedTarget(element: nil, appName: appName, failure: nil)
        }
        switch Snapshot.resolve(index: index, appName: appName) {
        case let .failed(result):
            return IndexedTarget(element: nil, appName: appName, failure: result)
        case let .found(entry, pid):
            let owner = appName ?? NSRunningApplication(processIdentifier: pid)?.localizedName
            return IndexedTarget(element: Element(entry.element), appName: owner, failure: nil, listedName: entry.name)
        }
    }

    // MARK: - Element Finding (shared helper)

    /// Find an element using content-root-first strategy with semantic depth.
    /// Searches AXWebArea first (in-page elements), then full app tree.
    private static func findElement(locator: Locator, appName: String?) -> Element? {
        guard let appElement = resolveAppElement(appName: appName) else { return nil }

        // Content-root-first: search AXWebArea, then full tree
        if let window = appElement.focusedWindow(),
           let webArea = Perception.findWebArea(in: window)
        {
            if let found = searchWithSemanticDepth(locator: locator, root: webArea) {
                return found
            }
        }

        // Full app tree fallback
        return searchWithSemanticDepth(locator: locator, root: appElement)
    }

    /// Search with semantic depth tunneling using AXorcist's Element.searchElements.
    /// Falls back to manual semantic-depth walk if AXorcist doesn't find it.
    private static func searchWithSemanticDepth(locator: Locator, root: Element) -> Element? {
        // Try AXorcist's built-in search first
        if let query = locator.computedNameContains {
            var options = ElementSearchOptions()
            options.maxDepth = Limits.semanticDepthBudget
            if let roleCriteria = locator.criteria.first(where: { $0.attribute == "AXRole" }) {
                options.includeRoles = [roleCriteria.value]
            }
            if let found = root.findElement(matching: query, options: options) {
                return found
            }
        }

        // DOM ID search (bypasses depth limits)
        if let domIdCriteria = locator.criteria.first(where: { $0.attribute == "AXDOMIdentifier" }) {
            return findByDOMId(domIdCriteria.value, in: root, maxDepth: 50)
        }

        return nil
    }

    /// Resolve app name to Element.
    private static func resolveAppElement(appName: String?) -> Element? {
        if let appName {
            return Perception.appElement(for: appName)
        }
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        return Element.application(for: frontApp.processIdentifier)
    }

    // MARK: - Field Finding for pc_type into

    /// Editable/input roles that the 'into' parameter should match against.
    /// When someone says into:"To", they mean a field labeled "To", not
    /// a link that says "Skip to content".
    private static let editableRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField",
        "AXSecureTextField",
    ]

    /// Find an editable field by name. Searches ALL matching elements and
    /// scores them, preferring editable roles and exact/prefix matches.
    /// This is the v1 SmartResolver pattern adapted for v2.
    private static func findEditableField(named query: String, appName: String?) -> Element? {
        guard let appElement = resolveAppElement(appName: appName) else { return nil }

        let queryLower = query.lowercased()

        // Search from content root first (web area), then full tree
        let searchRoot: Element
        if let window = appElement.focusedWindow(),
           let webArea = Perception.findWebArea(in: window)
        {
            searchRoot = webArea
        } else if let window = appElement.focusedWindow() {
            searchRoot = window
        } else {
            searchRoot = appElement
        }

        // Collect ALL matching elements with scores.
        // Uses semantic depth (empty layout containers cost 0) so we reach
        // Gmail compose fields at DOM depth 30+ within budget of 25.
        var candidates: [(element: Element, score: Int)] = []
        scoreFieldCandidates(
            element: searchRoot,
            queryLower: queryLower,
            candidates: &candidates,
            semanticDepth: 0,
            maxSemanticDepth: Limits.semanticDepthBudget
        )

        // Return the highest-scoring candidate
        return candidates.max(by: { $0.score < $1.score })?.element
    }

    /// Layout roles that cost zero semantic depth (tunneled through).
    /// Same set used by pc_read's semantic depth tunneling.
    private static let layoutRoles: Set<String> = [
        "AXGroup", "AXGenericElement", "AXSection", "AXDiv",
        "AXList", "AXLandmarkMain", "AXLandmarkNavigation",
        "AXLandmarkBanner", "AXLandmarkContentInfo",
    ]

    /// Walk the tree scoring elements as field candidates.
    /// Uses SEMANTIC depth (empty layout containers cost 0) so we can
    /// reach Gmail compose fields at DOM depth 30+ within budget of 25.
    private static func scoreFieldCandidates(
        element: Element,
        queryLower: String,
        candidates: inout [(element: Element, score: Int)],
        semanticDepth: Int,
        maxSemanticDepth: Int
    ) {
        guard semanticDepth <= maxSemanticDepth, candidates.count < 100 else { return }

        let role = element.role() ?? ""
        let titleLower = (element.title() ?? "").lowercased()
        let descLower = (element.descriptionText() ?? "").lowercased()
        let nameLower = (element.computedName() ?? "").lowercased()

        // Semantic depth: empty layout containers cost 0
        let hasContent = !titleLower.isEmpty || !descLower.isEmpty || !nameLower.isEmpty
        let isTunnel = layoutRoles.contains(role) && !hasContent
        let childSemanticDepth = isTunnel ? semanticDepth : semanticDepth + 1

        // Score: does this element's name match the query?
        var score = 0

        // Exact match on any name property
        if titleLower == queryLower || descLower == queryLower || nameLower == queryLower {
            score = 100
        }
        // Starts with query
        else if titleLower.hasPrefix(queryLower) || descLower.hasPrefix(queryLower) || nameLower.hasPrefix(queryLower) {
            score = 80
        }
        // Contains query
        else if titleLower.contains(queryLower) || descLower.contains(queryLower) || nameLower.contains(queryLower) {
            score = 60
        }

        if score > 0 {
            // Bonus for editable/interactive roles (the whole point of 'into')
            // High bonus (+50) ensures editable fields always beat links/buttons
            if editableRoles.contains(role) {
                score += 50
            }

            // Bonus for being on-screen (visible) - helps when multiple
            // compose windows exist (old draft vs current compose)
            if let pos = element.position(), let size = element.size() {
                let onScreen = NSScreen.screens.contains { screen in
                    screen.frame.intersects(CGRect(origin: pos, size: size))
                }
                if onScreen && size.width > 1 && size.height > 1 {
                    score += 20
                }
            }

            // Only include if score is reasonable
            if score >= 50 {
                candidates.append((element: element, score: score))
            }
        }

        // Recurse into children with semantic depth
        guard let children = element.children() else { return }
        for child in children {
            scoreFieldCandidates(
                element: child, queryLower: queryLower,
                candidates: &candidates,
                semanticDepth: childSemanticDepth,
                maxSemanticDepth: maxSemanticDepth
            )
        }
    }

    // MARK: - Readback Verification

    /// Read the current value of an element for verification.
    private static func readbackFromElement(_ element: Element) -> String {
        // Try raw AXValue (Chrome compatible)
        if let value = Perception.readValue(from: element), !value.isEmpty {
            return value.count > 200 ? String(value.prefix(200)) + "..." : value
        }
        // Try title (some fields expose typed text as title)
        if let title = element.title(), !title.isEmpty {
            return title.count > 200 ? String(title.prefix(200)) + "..." : title
        }
        // Try computedName
        if let name = element.computedName(), !name.isEmpty {
            return name.count > 200 ? String(name.prefix(200)) + "..." : name
        }
        return "(verification unavailable for this field type)"
    }

    // MARK: - DOM ID Search

    private static func findByDOMId(_ domId: String, in root: Element, maxDepth: Int) -> Element? {
        findByDOMIdWalk(element: root, domId: domId, depth: 0, maxDepth: maxDepth)
    }

    private static func findByDOMIdWalk(element: Element, domId: String, depth: Int, maxDepth: Int) -> Element? {
        guard depth < maxDepth else { return nil }
        if let elDomId = element.rawAttributeValue(named: "AXDOMIdentifier") as? String, elDomId == domId {
            return element
        }
        guard let children = element.children() else { return nil }
        for child in children {
            if let found = findByDOMIdWalk(element: child, domId: domId, depth: depth + 1, maxDepth: maxDepth) {
                return found
            }
        }
        return nil
    }

    // MARK: - Special Key Mapping

    static func mapSpecialKey(_ key: String) -> SpecialKey? {
        switch key.lowercased() {
        case "return", "enter": .return
        case "tab": .tab
        case "escape", "esc": .escape
        case "space": .space
        case "delete", "backspace": .delete
        case "up": .up
        case "down": .down
        case "left": .left
        case "right": .right
        case "home": .home
        case "end": .end
        case "pageup": .pageUp
        case "pagedown": .pageDown
        case "f1": .f1;  case "f2": .f2;  case "f3": .f3
        case "f4": .f4;  case "f5": .f5;  case "f6": .f6
        case "f7": .f7;  case "f8": .f8;  case "f9": .f9
        case "f10": .f10; case "f11": .f11; case "f12": .f12
        default: nil
        }
    }
}

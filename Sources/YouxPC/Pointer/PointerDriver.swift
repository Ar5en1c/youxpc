// PointerDriver.swift - Single owner of pointer input delivery
//
// Two ways to "click", in order of preference:
//
// 1. Accessibility action. Ask the control to press itself (AXPress). No mouse
//    event exists at all, so the user's pointer does not move, the target app
//    does not need to be frontmost, and its window may even be covered.
//    Coordinate clicks get this path too, via an AX hit-test at the point.
//
// 2. Borrowed system pointer. For targets with no pressable AX element (canvas,
//    games, custom-drawn UI) real mouse events are the only option. We post
//    them through the HID tap, then put the user's pointer back where it was.
//
// Web pages are the exception to (1): Chromium does not expose AXPress on page
// buttons and links. Those are focused through accessibility and activated
// with Space or Return posted to the browser's process (activateByKey), which
// also needs no pointer and works with the browser in the background.
//
// CGEvent.postToPid is deliberately not used for mouse input: measured against
// Chrome it leaves the system pointer alone but the click never registers,
// with or without the window-under-pointer fields, active or not.
//
// YOUXPC_POINTER_RETURN=off keeps the pointer at the click location (the
// pre-2.3 behavior), which some hover-driven UIs need.

import AppKit
import ApplicationServices
import AXorcist
import Foundation

/// Delivers pointer input for the Actions module.
public enum PointerDriver {

    /// Whether the user's pointer is returned after a borrowed click.
    public static let returnsPointer: Bool = {
        let value = ProcessInfo.processInfo.environment["YOUXPC_POINTER_RETURN"]?.lowercased()
        return !["off", "0", "false", "no"].contains(value ?? "")
    }()

    /// Roles whose AXPress is equivalent to a left click on them.
    private static let pressableRoles: Set<String> = [
        "AXButton", "AXPopUpButton", "AXMenuButton", "AXLink", "AXCheckBox",
        "AXRadioButton", "AXMenuItem", "AXMenuBarItem", "AXDisclosureTriangle",
        "AXTab", "AXSwitch", "AXToggle",
    ]

    /// How far up the tree to look for a pressable ancestor of the hit element
    /// (e.g. the AXStaticText inside an AXLink, the AXImage inside an AXButton).
    private static let maxAncestorClimb = 3

    // MARK: - Accessibility path

    /// A pressable element found at a screen point.
    public struct PressTarget {
        public let element: AXUIElement
        public let role: String
        public let name: String
    }

    /// Whether `element` advertises `action`.
    public static func supports(_ action: String, on element: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let list = names as? [String]
        else { return false }
        return list.contains(action)
    }

    /// Perform an accessibility action. True only when the app accepted it.
    @discardableResult
    public static func perform(_ action: String, on element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    /// Hit-test `point` and return the nearest pressable element containing it.
    /// With a pid the test is scoped to that app, so it works even when the
    /// app's window is behind another one. Without one it is system-wide.
    public static func pressTarget(at point: CGPoint, pid: pid_t?) -> PressTarget? {
        let root = pid.map { AXUIElementCreateApplication($0) } ?? AXUIElementCreateSystemWide()
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(root, Float(point.x), Float(point.y), &hit) == .success,
              var current = hit
        else { return nil }

        for _ in 0...maxAncestorClimb {
            let role = stringAttribute(kAXRoleAttribute, of: current) ?? ""
            if pressableRoles.contains(role),
               supports(kAXPressAction, on: current),
               frame(of: current)?.contains(point) ?? false,
               boolAttribute(kAXEnabledAttribute, of: current) ?? true
            {
                let name = stringAttribute(kAXTitleAttribute, of: current)
                    ?? stringAttribute(kAXDescriptionAttribute, of: current)
                    ?? role
                return PressTarget(element: current, role: role, name: name)
            }
            guard let parent = elementAttribute(kAXParentAttribute, of: current) else { break }
            current = parent
        }
        return nil
    }

    /// Role and name of each pressable control at `point`: the hit element and
    /// the ancestors a click there would reach. Used by the never-press list.
    public static func controls(at point: CGPoint, pid: pid_t?) -> [(role: String, name: String)] {
        let root = pid.map { AXUIElementCreateApplication($0) } ?? AXUIElementCreateSystemWide()
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(root, Float(point.x), Float(point.y), &hit) == .success,
              var current = hit
        else { return [] }
        var found: [(role: String, name: String)] = []
        for _ in 0...maxAncestorClimb {
            if let control = namedControl(current) { found.append(control) }
            guard let parent = elementAttribute(kAXParentAttribute, of: current) else { break }
            current = parent
        }
        return found
    }

    /// Role and name of the control holding keyboard focus in `pid`, if it is pressable.
    public static func focusedControl(pid: pid_t) -> (role: String, name: String)? {
        elementAttribute(kAXFocusedUIElementAttribute, of: AXUIElementCreateApplication(pid)).flatMap(namedControl)
    }

    private static func namedControl(_ element: AXUIElement) -> (role: String, name: String)? {
        guard let role = stringAttribute(kAXRoleAttribute, of: element), pressableRoles.contains(role),
              let name = stringAttribute(kAXTitleAttribute, of: element)
                ?? stringAttribute(kAXDescriptionAttribute, of: element)
        else { return nil }
        return (role, name)
    }

    // MARK: - Keyboard activation of web controls

    /// Web controls a focused Space or Return activates, and which key to use.
    private static let keyActivation: [String: String] = [
        "AXButton": "space", "AXCheckBox": "space", "AXRadioButton": "space",
        "AXPopUpButton": "space", "AXMenuButton": "space", "AXSwitch": "space",
        "AXToggle": "space", "AXTab": "return", "AXLink": "return",
    ]

    /// Activate a control inside a web page without the pointer: focus it
    /// through accessibility, confirm the focus took, then post its activation
    /// key to the owning process. Returns the key used, or nil when this path
    /// does not apply (not a web control, not focusable) so the caller can
    /// fall back to a real click.
    public static func activateByKey(_ element: AXUIElement) -> String? {
        guard TargetedKeyboard.isEnabled,
              let role = stringAttribute(kAXRoleAttribute, of: element),
              let key = keyActivation[role],
              boolAttribute(kAXEnabledAttribute, of: element) ?? true,
              isInsideWebArea(element)
        else { return nil }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXFocusedAttribute as CFString, &settable) == .success,
              settable.boolValue
        else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0,
              AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
        else { return nil }
        // The key goes to whatever holds focus, so the focus must be confirmed.
        for _ in 0..<10 where boolAttribute(kAXFocusedAttribute, of: element) != true {
            usleep(30_000)
        }
        guard boolAttribute(kAXFocusedAttribute, of: element) == true else { return nil }
        return TargetedKeyboard.chord([key], to: pid) ? key : nil
    }

    /// Roles whose click means "put the keyboard here".
    private static let textEntryRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXSearchField", "AXComboBox", "AXSecureTextField",
    ]

    /// Clicking a text field is a request for keyboard focus, and focus can be
    /// given through accessibility: no pointer, and the app can stay in the
    /// background. True only when the field reports that it has the focus.
    public static func focusTextField(_ element: AXUIElement) -> Bool {
        guard let role = stringAttribute(kAXRoleAttribute, of: element), textEntryRoles.contains(role),
              boolAttribute(kAXEnabledAttribute, of: element) ?? true
        else { return false }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXFocusedAttribute as CFString, &settable) == .success,
              settable.boolValue,
              AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
        else { return false }
        for _ in 0..<10 where boolAttribute(kAXFocusedAttribute, of: element) != true {
            usleep(30_000)
        }
        return boolAttribute(kAXFocusedAttribute, of: element) == true
    }

    private static func isInsideWebArea(_ element: AXUIElement) -> Bool {
        var current = element
        for _ in 0..<60 {
            guard let parent = elementAttribute(kAXParentAttribute, of: current) else { return false }
            if stringAttribute(kAXRoleAttribute, of: parent) == "AXWebArea" { return true }
            current = parent
        }
        return false
    }

    // MARK: - Borrowed system pointer

    /// Click with real mouse events, then return the user's pointer.
    public static func click(at point: CGPoint, button: MouseButton, count: Int) throws {
        try borrowingPointer {
            try InputDriver.click(at: point, button: button, count: count)
        }
    }

    /// Press and hold with real mouse events, then return the user's pointer.
    public static func pressHold(at point: CGPoint, button: MouseButton, duration: TimeInterval) throws {
        try borrowingPointer {
            try InputDriver.pressHold(at: point, button: button, duration: duration)
        }
    }

    /// Run `body`, which posts real mouse events, and afterwards warp the
    /// pointer back to where the user left it. The warp generates no events,
    /// so the target app never sees the pointer leave.
    public static func borrowingPointer<T>(_ body: () throws -> T) rethrows -> T {
        let saved = userPointerLocation()
        defer { returnPointer(to: saved) }
        return try body()
    }

    /// Where the user's pointer is now, or nil when pointer return is disabled.
    /// Pair with `returnPointer(to:)` around inline event sequences.
    public static func userPointerLocation() -> CGPoint? {
        returnsPointer ? CGEvent(source: nil)?.location : nil
    }

    /// Warp the user's pointer back to a location from `userPointerLocation()`.
    public static func returnPointer(to saved: CGPoint?) {
        guard let saved else { return }
        // Let the posted events drain into the target before moving.
        usleep(40_000)
        CGWarpMouseCursorPosition(saved)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    /// Label for tool results: which pointer the action used.
    public static var borrowedLabel: String {
        returnsPointer ? "system-returned" : "system"
    }

    // MARK: - Raw AX helpers

    private static func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let string = value as? String, !string.isEmpty
        else { return nil }
        return string
    }

    private static func boolAttribute(_ name: String, of element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    private static func elementAttribute(_ name: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        // Type checked against AXUIElementGetTypeID above.
        return (value as! AXUIElement)
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef,
              CFGetTypeID(positionRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        // Types checked against AXValueGetTypeID above.
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }
}

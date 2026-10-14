// TargetedKeyboard.swift - Keyboard input addressed to one process
//
// Ordinary synthetic key events go to whichever app is frontmost at the moment
// they are delivered. If focus is not where the caller believes it is, the
// text lands in another app. That is not hypothetical: during development a
// focus race sent a terminal test's keystrokes into the agent's own chat box.
//
// Events posted with CGEvent.postToPid go to the named process and nowhere
// else, whatever is frontmost. Every keystroke YouxPC sends goes this way.
// A background app also accepts them (verified on TextEdit and Terminal), so
// typing into a known element does not need the app in front.
//
// YOUXPC_KEYBOARD=global restores the old frontmost-app delivery for apps
// that turn out to ignore targeted events.

import CoreGraphics
import Foundation

/// Sends key events to a specific process.
public enum TargetedKeyboard {

    /// Virtual key codes for named keys (ANSI layout).
    private static let namedKeys: [String: CGKeyCode] = [
        "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51,
        "backspace": 51, "escape": 53, "esc": 53, "left": 123, "right": 124,
        "down": 125, "up": 126, "home": 115, "end": 119, "pageup": 116,
        "pagedown": 121,
    ]

    private static let letterKeys: [Character: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8,
        "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45,
        "m": 46,
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28,
        "9": 25, "0": 29, "-": 27, "=": 24, "[": 33, "]": 30, ";": 41, "'": 39,
        ",": 43, ".": 47, "/": 44, "\\": 42, "`": 50,
    ]

    private static let functionKeys: [String: CGKeyCode] = [
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]

    private static let modifierFlags: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand, "shift": .maskShift,
        "ctrl": .maskControl, "control": .maskControl,
        "alt": .maskAlternate, "option": .maskAlternate, "opt": .maskAlternate,
    ]

    /// False when YOUXPC_KEYBOARD=global asks for frontmost-app delivery.
    public static let isEnabled: Bool = {
        ProcessInfo.processInfo.environment["YOUXPC_KEYBOARD"]?.lowercased() != "global"
    }()

    private static func keyCode(for name: String) -> CGKeyCode? {
        let lowered = name.lowercased()
        if let code = namedKeys[lowered] ?? functionKeys[lowered] { return code }
        return lowered.count == 1 ? lowered.first.flatMap { letterKeys[$0] } : nil
    }

    /// Whether `keys` (modifiers followed by one key) can be sent as a chord.
    ///
    /// Command and Option chords are excluded: they are menu shortcuts, and
    /// apps did not act on them when posted to their process (Cmd+A sent to
    /// TextEdit selected nothing, even with TextEdit frontmost). Those still
    /// go through the frontmost-app path. Plain keys, Shift and Ctrl chords
    /// are ordinary key input and do arrive.
    public static func canSend(_ keys: [String]) -> Bool {
        guard let last = keys.last, keyCode(for: last) != nil else { return false }
        return keys.dropLast().allSatisfy { ["shift", "ctrl", "control"].contains($0.lowercased()) }
    }

    /// Press a chord such as ["cmd", "a"] or a single key such as ["return"] in `pid`.
    @discardableResult
    public static func chord(_ keys: [String], to pid: pid_t) -> Bool {
        guard let last = keys.last, let code = keyCode(for: last) else { return false }
        var flags: CGEventFlags = []
        for name in keys.dropLast() {
            guard let flag = modifierFlags[name.lowercased()] else { return false }
            flags.insert(flag)
        }
        return post(code, flags: flags, to: pid)
    }

    /// Whether `name` is a key this driver can press without modifiers.
    public static func isNamedKey(_ name: String) -> Bool {
        namedKeys[name.lowercased()] != nil
    }

    /// Type text into `pid`. Each character is carried as a Unicode string on
    /// the event, so no keyboard-layout mapping is involved.
    @discardableResult
    public static func type(_ text: String, to pid: pid_t, delayMicroseconds: useconds_t = 3000) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        for character in text {
            let units = Array(String(character).utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { return false }
            // Explicitly empty: do not inherit modifiers the user is holding.
            down.flags = []
            up.flags = []
            down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            down.postToPid(pid)
            up.postToPid(pid)
            usleep(delayMicroseconds)
        }
        return true
    }

    /// Press a named key (return, tab, arrows, ...) in `pid`.
    @discardableResult
    public static func press(_ name: String, shift: Bool = false, to pid: pid_t) -> Bool {
        guard let code = namedKeys[name.lowercased()] else { return false }
        return post(code, flags: shift ? .maskShift : [], to: pid)
    }

    /// Press Ctrl+letter in `pid`.
    @discardableResult
    public static func pressControl(_ letter: Character, to pid: pid_t) -> Bool {
        guard let code = letterKeys[Character(letter.lowercased())] else { return false }
        return post(code, flags: .maskControl, to: pid)
    }

    private static func post(_ code: CGKeyCode, flags: CGEventFlags, to pid: pid_t) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        else { return false }
        down.flags = flags
        up.flags = flags
        down.postToPid(pid)
        usleep(8000)
        up.postToPid(pid)
        usleep(8000)
        return true
    }
}

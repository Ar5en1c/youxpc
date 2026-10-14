import Testing
@testable import YouxPC

@Suite("Never-press list matching")
struct PressGuardTests {

    @Test("Entries are split on commas and compared without case")
    func parses() {
        #expect(PressGuard.parse("Send, Delete ,Pay now") == [["send"], ["delete"], ["pay", "now"]])
        #expect(PressGuard.parse(nil).isEmpty)
        #expect(PressGuard.parse(" , ,").isEmpty)
    }

    @Test("A name matches when it contains the entry as whole words")
    func matchesWholeWords() {
        let entries = PressGuard.parse("Send,Pay now")
        #expect(PressGuard.match("Send", in: entries) == "send")
        #expect(PressGuard.match("SEND MESSAGE", in: entries) == "send")
        #expect(PressGuard.match("Send (⌘↩)", in: entries) == "send")
        #expect(PressGuard.match("Review and pay now", in: entries) == "pay now")
    }

    @Test("Longer words and split phrases do not match")
    func ignoresPartialWords() {
        let entries = PressGuard.parse("Send,Pay now")
        #expect(PressGuard.match("Sender", in: entries) == nil)
        #expect(PressGuard.match("Resend code", in: entries) == nil)
        #expect(PressGuard.match("Pay later, not now", in: entries) == nil)
        #expect(PressGuard.match("", in: entries) == nil)
    }
}

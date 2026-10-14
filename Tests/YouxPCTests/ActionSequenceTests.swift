import Testing
@testable import YouxPC

@Suite("pc_do step parsing")
struct ActionSequenceTests {

    @Test("Each kind of step is read")
    func parsesSteps() throws {
        let raw: [Any] = [
            ["click": "e7"], ["type": "Ada", "into": "Name"], ["type": "x"],
            ["key": "cmd+a"], ["scroll": "Down"], ["wait": 1], ["click": 7],
        ]
        let steps = try ActionSequence.parse(raw).get()
        #expect(steps == [
            .click("e7"), .type(text: "Ada", into: "Name"), .type(text: "x", into: nil),
            .key("cmd+a"), .scroll("down"), .wait(1), .click("7"),
        ])
    }

    @Test("Malformed input is named, not guessed at")
    func rejectsBadInput() {
        #expect(ActionSequence.parse("click e7") == .failure(.notAList))
        #expect(ActionSequence.parse([Any]()) == .failure(.empty))
        #expect(ActionSequence.parse([["click": "e1"], ["press": "e2"]]) == .failure(.unreadable(2)))
        #expect(ActionSequence.parse(Array(repeating: ["click": "e1"], count: 31)) == .failure(.tooMany(31)))
    }

    @Test("Only a target written with its e is an id")
    func tellsIdsFromNames() {
        #expect(ActionSequence.target("e7").index == 7)
        #expect(ActionSequence.target("[e12]").index == 12)
        #expect(ActionSequence.target("7").index == nil)
        #expect(ActionSequence.target("7").name == "7")
        #expect(ActionSequence.target("Equals").name == "Equals")
        #expect(ActionSequence.target("e-mail").name == "e-mail")
    }
}

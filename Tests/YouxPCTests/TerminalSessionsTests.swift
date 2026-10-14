import Testing
@testable import YouxPC

@Suite("Terminal command parsing")
struct TerminalSessionsTests {

    @Test("Words and quoted groups become arguments")
    func tokenizes() throws {
        #expect(try TerminalSessions.tokenize("npm test") == ["npm", "test"])
        #expect(try TerminalSessions.tokenize("  opencode   run  ") == ["opencode", "run"])
        #expect(try TerminalSessions.tokenize("opencode run \"fix the bug\"") == ["opencode", "run", "fix the bug"])
        #expect(try TerminalSessions.tokenize("echo 'a b' c") == ["echo", "a b", "c"])
        #expect(try TerminalSessions.tokenize("tool \"\"") == ["tool", ""])
    }

    @Test("Shell operators stay inside the argument they were typed in")
    func operatorsAreNotSpecial() throws {
        // "bc;" is not "bc", so an approved "bc" does not match this line.
        #expect(try TerminalSessions.tokenize("bc; rm -rf x") == ["bc;", "rm", "-rf", "x"])
        #expect(try TerminalSessions.tokenize("ls && whoami") == ["ls", "&&", "whoami"])
        #expect(try TerminalSessions.tokenize("echo $(id)") == ["echo", "$(id)"])
    }

    @Test("Unbalanced quotes and control characters are rejected")
    func rejectsMalformed() {
        #expect(throws: TerminalSessions.ParseError.self) { try TerminalSessions.tokenize("echo \"open") }
        #expect(throws: TerminalSessions.ParseError.self) { try TerminalSessions.tokenize("ls\nrm x") }
        #expect(throws: TerminalSessions.ParseError.self) { try TerminalSessions.tokenize("ls\u{1B}[A") }
    }

    @Test("Quoting makes every character literal for the shell")
    func quotes() {
        #expect(TerminalSessions.shellQuote("plain") == "'plain'")
        #expect(TerminalSessions.shellQuote("$(id); rm") == "'$(id); rm'")
        #expect(TerminalSessions.shellQuote("it's") == "'it'\"'\"'s'")
    }
}

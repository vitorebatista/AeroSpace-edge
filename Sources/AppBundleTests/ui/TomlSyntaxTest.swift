@testable import AppBundle
import Testing

@MainActor
@Suite(.serializedGlobally)
struct TomlSyntaxTest {
    @Test func testColoursTheParts() {
        assertSpans(
            spans("[mode.main.binding]\nalt-h = 'focus left' # go west\n"),
            [
                ("[mode.main.binding]", .tableHeader),
                ("alt-h", .key),
                ("'focus left'", .string),
                ("# go west", .comment),
            ],
        )
    }

    @Test func testHashInsideAStringIsNotAComment() {
        assertSpans(
            spans("cmd = 'echo #1'\n"),
            [("cmd", .key), ("'echo #1'", .string)],
        )
    }

    @Test func testNumbersAndBooleans() {
        assertSpans(
            spans("inner.horizontal = 10\nstart-at-login = true\n"),
            [
                ("inner.horizontal", .key),
                ("10", .number),
                ("start-at-login", .key),
                ("true", .boolean),
            ],
        )
    }

    @Test func testArrayIsNotATableHeader() {
        assertSpans(
            spans("workspaces = ['1', '2']\n"),
            [("workspaces", .key), ("'1'", .string), ("'2'", .string)],
        )
    }

    @Test func testMultiLineStringSwallowsTheLinesItSpans() {
        assertSpans(
            spans("run = \"\"\"\n# not a comment\n\"\"\"\n"),
            [("run", .key), ("\"\"\"", .string), ("# not a comment", .string), ("\"\"\"", .string)],
        )
    }

    @Test func testUnterminatedStringStopsAtTheEndOfTheLine() {
        assertSpans(
            spans("cmd = 'oops\nnext = 1\n"),
            [("cmd", .key), ("'oops", .string), ("next", .key), ("1", .number)],
        )
    }

    @Test func testRangesSurviveNonAsciiText() {
        let text = "cmd = 'é🙂' # tail"
        let comment = tomlTokens(text).last!
        assertEquals((text as NSString).substring(with: comment.range), "# tail")
    }

    /// The coloured substrings, in order — the thing the editor actually shows.
    private func spans(_ text: String) -> [(String, TomlToken.Kind)] {
        let ns = text as NSString
        return tomlTokens(text).map { (ns.substring(with: $0.range), $0.kind) }
    }

    private func assertSpans(
        _ actual: [(String, TomlToken.Kind)],
        _ expected: [(String, TomlToken.Kind)],
        sourceLocation: SourceLocation = #_sourceLocation,
    ) {
        #expect(
            actual.count == expected.count && zip(actual, expected).allSatisfy { $0 == $1 },
            "\(actual)\n!=\n\(expected)",
            sourceLocation: sourceLocation,
        )
    }
}

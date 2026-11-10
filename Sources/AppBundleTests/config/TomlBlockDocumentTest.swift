@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct TomlBlockDocumentTest {
    @Test func testRoundTripDefaultConfig() {
        for name in ["default-config.toml", "i3-like-config-example.toml"] {
            let text = try! String(
                contentsOf: projectRoot.appending(component: "docs/config-examples/\(name)"),
                encoding: .utf8,
            )
            assertEquals(TomlBlockDocument(text).render(), text)
        }
    }

    @Test func testRoundTripTrickyValues() {
        let text = """
            # leading comment
            start-at-login = true

            after-startup-command = [
                'exec-and-forget echo "a # not-a-comment"',
                'exec-and-forget echo [not-a-header]',
            ]

            [gaps]
            inner.horizontal = 10 # trailing comment

            [[on-window-detected]]
            if.app-id = 'com.apple.finder'
            run = ['layout floating']

            """
        assertEquals(TomlBlockDocument(text).render(), text)
    }

    @Test func testCommentContainingAMultilineDelimiterDoesNotHideFollowingBlocks() {
        // TOML comments may contain any text, including the three-quote sequence that
        // starts a multiline string. The document splitter must stop at the comment
        // marker before considering delimiters, or it treats every following line as a
        // continuation and cannot safely edit a later key.
        var doc = TomlBlockDocument("# Example: \"\"\" is a multiline string delimiter\nstart-at-login = false\n\n[gaps]\ninner.vertical = 2\n")
        doc.set(key: "start-at-login", tomlValue: "true")
        assertEquals(
            doc.render(),
            "# Example: \"\"\" is a multiline string delimiter\nstart-at-login = true\n\n[gaps]\ninner.vertical = 2\n",
        )
    }

    @Test func testBlockSplitting() {
        let doc = TomlBlockDocument(
            """
            a = 1
            # comment about the table
            [gaps]
            inner.vertical = 2
            """,
        )
        assertEquals(doc.blocks.count, 3)
        assertEquals(doc.blocks[0], .keyValue(key: "a", text: "a = 1\n"))
        assertEquals(doc.blocks[1], .trivia(text: "# comment about the table\n"))
        assertEquals(
            doc.blocks[2],
            .table(name: "gaps", text: "[gaps]\ninner.vertical = 2"),
        )
    }

    @Test func testTrailingCommentsInATableBecomeTrivia() {
        // A comment run at the end of a table body is split out, so that replacing the
        // table does not swallow a comment that visually belongs to what follows.
        let doc = TomlBlockDocument(
            """
            [gaps]
            inner.vertical = 2

            # about the next thing
            [exec]
            inherit-env-vars = true
            """,
        )
        assertEquals(doc.blocks.count, 3)
        assertEquals(doc.blocks[0], .table(name: "gaps", text: "[gaps]\ninner.vertical = 2\n"))
        assertEquals(doc.blocks[1], .trivia(text: "\n# about the next thing\n"))
        assertEquals(doc.blocks[2], .table(name: "exec", text: "[exec]\ninherit-env-vars = true"))
    }

    @Test func testArrayOfTablesName() {
        let doc = TomlBlockDocument("[[on-window-detected]]\nrun = ['layout floating']\n")
        assertEquals(doc.blocks.count, 1)
        assertEquals(doc.blocks[0].name, "on-window-detected")
    }

    @Test func testEmptyInput() {
        assertEquals(TomlBlockDocument("").render(), "")
        assertEquals(TomlBlockDocument("").blocks.count, 0)
    }

    @Test func testSetExistingKeyPreservesEverythingElse() {
        var doc = TomlBlockDocument(
            """
            # top comment
            start-at-login = false
            accordion-padding = 30 # why 30

            [gaps]
            inner.vertical = 2
            """,
        )
        doc.set(key: "start-at-login", tomlValue: "true")
        assertEquals(
            doc.render(),
            """
            # top comment
            start-at-login = true
            accordion-padding = 30 # why 30

            [gaps]
            inner.vertical = 2
            """,
        )
    }

    @Test func testSetPreservesTrailingCommentOnTheSameLine() {
        var doc = TomlBlockDocument("accordion-padding = 30 # why 30\n")
        doc.set(key: "accordion-padding", tomlValue: "45")
        assertEquals(doc.render(), "accordion-padding = 45 # why 30\n")
    }

    @Test func testSetAbsentKeyIsInsertedBeforeTheFirstTableHeader() {
        var doc = TomlBlockDocument(
            """
            start-at-login = true

            [gaps]
            inner.vertical = 2
            """,
        )
        doc.set(key: "accordion-padding", tomlValue: "45")
        assertEquals(
            doc.render(),
            """
            start-at-login = true
            accordion-padding = 45

            [gaps]
            inner.vertical = 2
            """,
        )
    }

    @Test func testSetAbsentKeyInAFileWithNoTables() {
        var doc = TomlBlockDocument("start-at-login = true\n")
        doc.set(key: "accordion-padding", tomlValue: "45")
        assertEquals(doc.render(), "start-at-login = true\naccordion-padding = 45\n")
    }

    @Test func testSetAbsentKeyInAnEmptyDocument() {
        var doc = TomlBlockDocument("")
        doc.set(key: "start-at-login", tomlValue: "true")
        assertEquals(doc.render(), "start-at-login = true\n")
    }

    @Test func testSetMultiLineValueIsReplacedWholesale() {
        var doc = TomlBlockDocument(
            """
            persistent-workspaces = [
                '1',
                '2',
            ]
            start-at-login = true
            """,
        )
        doc.set(key: "persistent-workspaces", tomlValue: "['1', '2', '3']")
        assertEquals(
            doc.render(),
            """
            persistent-workspaces = ['1', '2', '3']
            start-at-login = true
            """,
        )
    }

    @Test func testRemoveKey() {
        var doc = TomlBlockDocument("a = 1\nb = 2\n")
        doc.remove(key: "a")
        assertEquals(doc.render(), "b = 2\n")
        doc.remove(key: "nonexistent") // no-op
        assertEquals(doc.render(), "b = 2\n")
    }

    @Test func testUnknownKeysAndTablesSurviveASet() {
        let text = """
            some-future-option = 'hello'
            start-at-login = false

            [some.future.table]
            x = 1
            """
        var doc = TomlBlockDocument(text)
        doc.set(key: "start-at-login", tomlValue: "true")
        assertEquals(doc.render(), text.replacingOccurrences(of: "start-at-login = false", with: "start-at-login = true"))
    }

    @Test func testValueSerialisers() {
        assertEquals(TomlValue.of(true), "true")
        assertEquals(TomlValue.of(42), "42")
        assertEquals(TomlValue.of("plain"), "'plain'")
        assertEquals(TomlValue.of("it's"), "\"it's\"")
        assertEquals(TomlValue.of("say \"hi\""), "'say \"hi\"'")
        assertEquals(TomlValue.array([TomlValue.of("1"), TomlValue.of("2")]), "['1', '2']")
        assertEquals(TomlValue.array([]), "[]")
    }

    @Test func testValueSerialiserEscapesControlCharactersInsteadOfEmittingARawLiteral() {
        // A raw newline inside a single-quoted literal string is invalid TOML (literal
        // strings are single-line) — this must fall back to an escaped basic string.
        assertEquals(TomlValue.of("line1\nline2"), "\"line1\\nline2\"")
        // Same, but also containing a quote that would have forced the basic-string
        // path anyway — the newline still needs its own escape, not a raw embedded one.
        assertEquals(TomlValue.of("it's\nbroken"), "\"it's\\nbroken\"")
        assertEquals(TomlValue.of("a\tb"), "\"a\\tb\"")
    }

    private static let tablesFixture = """
        start-at-login = true

        [gaps]
        inner.vertical = 2

        [mode.main.binding]
        alt-h = 'focus left'

        [mode.service.binding]
        esc = 'mode main'

        [exec]
        inherit-env-vars = true

        """

    @Test func testTextForTablesMatching() {
        let doc = TomlBlockDocument(Self.tablesFixture)
        assertEquals(
            doc.text(forTablesMatching: { $0.hasPrefix("mode.") }),
            """
            [mode.main.binding]
            alt-h = 'focus left'

            [mode.service.binding]
            esc = 'mode main'

            """,
        )
        assertEquals(doc.text(forTablesMatching: { $0 == "nope" }), "")
    }

    @Test func testReplaceTableKeepsPosition() {
        var doc = TomlBlockDocument(Self.tablesFixture)
        doc.replaceTable(named: "gaps", with: "[gaps]\ninner.vertical = 9\n")
        assertEquals(
            doc.render(),
            Self.tablesFixture.replacingOccurrences(of: "inner.vertical = 2", with: "inner.vertical = 9"),
        )
    }

    @Test func testReplaceTableWithNilDeletesIt() {
        var doc = TomlBlockDocument("a = 1\n\n[gaps]\ninner.vertical = 2\n\n[exec]\nx = 1\n")
        doc.replaceTable(named: "gaps", with: nil)
        assertEquals(doc.render(), "a = 1\n\n[exec]\nx = 1\n")
    }

    @Test func testReplaceTableWithNilKeepsARealCommentThatFollowsIt() {
        // The dangling-trivia cleanup after a delete must only ever remove a *blank*
        // trivia block. A trivia block carrying a real comment (not blank-only) is left
        // in place untouched, so the comment isn't silently swallowed.
        var doc = TomlBlockDocument("a = 1\n\n[gaps]\ninner.vertical = 2\n# still relevant\n[exec]\nx = 1\n")
        doc.replaceTable(named: "gaps", with: nil)
        assertEquals(doc.render(), "a = 1\n\n# still relevant\n[exec]\nx = 1\n")
    }

    @Test func testReplaceTableAlsoDropsTopLevelDottedKeys() {
        // `gaps.inner.vertical = 5` at top level is the same setting spelled differently;
        // regenerating `[gaps]` must not leave a duplicate definition behind.
        var doc = TomlBlockDocument("gaps.inner.vertical = 5\nstart-at-login = true\n")
        doc.replaceTable(named: "gaps", with: "[gaps]\ninner.vertical = 9\n")
        assertEquals(doc.render(), "start-at-login = true\n[gaps]\ninner.vertical = 9\n")
    }

    @Test func testReplaceAbsentTableAppends() {
        var doc = TomlBlockDocument("a = 1\n")
        doc.replaceTable(named: "gaps", with: "[gaps]\ninner.vertical = 9\n")
        assertEquals(doc.render(), "a = 1\n[gaps]\ninner.vertical = 9\n")
    }

    @Test func testReplaceTablesMatchingSplicesAtFirstMatch() {
        var doc = TomlBlockDocument(Self.tablesFixture)
        doc.replaceTables(matching: { $0.hasPrefix("mode.") }, with: "[mode.main.binding]\nalt-j = 'focus down'\n")
        assertEquals(
            doc.render(),
            """
            start-at-login = true

            [gaps]
            inner.vertical = 2

            [mode.main.binding]
            alt-j = 'focus down'

            [exec]
            inherit-env-vars = true

            """,
        )
    }

    @Test func testReplaceTablesMatchingWhenNoneMatchAppends() {
        var doc = TomlBlockDocument("a = 1\n")
        doc.replaceTables(matching: { $0.hasPrefix("mode.") }, with: "[mode.main.binding]\nalt-j = 'focus down'\n")
        assertEquals(doc.render(), "a = 1\n[mode.main.binding]\nalt-j = 'focus down'\n")
    }

    @Test func testCrlfDocumentSplitsIntoLines() {
        // Swift treats "\r\n" as a SINGLE Character, so `char == "\n"` never fires on a CRLF
        // document: without an explicit CRLF case in `linesWithTerminators()` the whole file
        // came back as one block, and `set` then dropped everything after the first key as
        // if it were a continuation line — silently, and producing valid TOML that `save()`'s
        // validation pass had no reason to reject.
        let text = "a = 1\r\n\r\n[gaps]\r\ninner.vertical = 2\r\n"
        let doc = TomlBlockDocument(text)
        assertEquals(doc.render(), text)
        assertEquals(doc.blocks.count, 3)
        assertEquals(doc.blocks[0], .keyValue(key: "a", text: "a = 1\r\n"))
        assertEquals(doc.blocks[1], .trivia(text: "\r\n"))
        assertEquals(doc.blocks[2], .table(name: "gaps", text: "[gaps]\r\ninner.vertical = 2\r\n"))
    }

    @Test func testSetKeepsTheLineEndingTheFileAlreadyUsed() {
        // A rewritten key keeps its own CRLF rather than becoming the one LF line in the
        // middle of the user's file — and the keys after it are still there.
        var crlf = TomlBlockDocument("a = 1\r\nb = 2\r\n")
        crlf.set(key: "a", tomlValue: "9")
        assertEquals(crlf.render(), "a = 9\r\nb = 2\r\n")

        // A trailing comment survives too, on its own CRLF line.
        var withComment = TomlBlockDocument("a = 1 # keep me\r\nb = 2\r\n")
        withComment.set(key: "a", tomlValue: "9")
        assertEquals(withComment.render(), "a = 9 # keep me\r\nb = 2\r\n")

        // And a last line with no terminator at all still gets none.
        var unterminated = TomlBlockDocument("a = 1")
        unterminated.set(key: "a", tomlValue: "9")
        assertEquals(unterminated.render(), "a = 9")
    }

    @Test func testSetAbsentKeyInACrlfDocumentDoesNotGlueLines() {
        // Pinning a known limitation, not an aspiration: a key that is *rewritten* keeps the
        // file's own terminator, but a brand-new line (here, and in a regenerated table body)
        // is still emitted with LF. That leaves one mixed ending in a CRLF file — cosmetic,
        // and every parser accepts it; giving the generated table bodies the file's terminator
        // would mean threading it through every builder in `ConfigTomlWriter`.
        var doc = TomlBlockDocument("a = 1\r\n[gaps]\r\ninner.vertical = 2\r\n")
        doc.set(key: "b", tomlValue: "2")
        assertEquals(doc.render(), "a = 1\r\nb = 2\n[gaps]\r\ninner.vertical = 2\r\n")
    }

    @Test func testReplaceTablesMatchingLeavesAnUnmatchedTableInBetweenUntouched() {
        // Two matching tables separated by a *non-matching* table (not just trivia):
        // the span to splice must stop at each match, not swallow the unmatched table
        // (and its comment) sitting between them.
        var doc = TomlBlockDocument("[mode.a]\nx = 1\n\n[other]\n# keep me\ny = 2\n\n[mode.b]\nz = 3\n")
        doc.replaceTables(matching: { $0.hasPrefix("mode.") }, with: "[mode.c]\nw = 9\n")
        assertEquals(doc.render(), "[mode.c]\nw = 9\n\n[other]\n# keep me\ny = 2\n\n")
    }
}

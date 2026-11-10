@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct LayoutCmdArgsTest {
    @Test func testParseSticky() {
        let cmd = parseCommand("layout sticky").singleCmdOrNil as! LayoutCommand
        assertEquals(cmd.args.toggleBetween.val, [.sticky])
    }

    @Test func testParseStickyAmongOthers() {
        let cmd = parseCommand("layout sticky floating").singleCmdOrNil as! LayoutCommand
        assertEquals(cmd.args.toggleBetween.val, [.sticky, .floating])
    }

    @Test func testParseUnknownLayout() {
        switch parseCommand("layout bogus") {
            case .cmd, .help: Issue.record(Comment(rawValue: "Expected failure"))
            case .failure: break
        }
    }
}

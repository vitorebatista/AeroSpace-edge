@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct ListMonitorsTest {
    @Test func testParseListMonitorsCommand() {
        testParseSingleCommandSucc("list-monitors", ListMonitorsCmdArgs(rawArgs: []))
        testParseSingleCommandSucc("list-monitors --focused", ListMonitorsCmdArgs(rawArgs: []).with(\.focused, true))
        testParseSingleCommandSucc("list-monitors --count", ListMonitorsCmdArgs(rawArgs: []).with(\.outputOnlyCount, true))
        assertEquals(parseCommand("list-monitors --format %{monitor-id} --count").errorOrNil, "ERROR: Conflicting flags: --count, --format")
        assertEquals(parseCommand("list-monitors --format '%{all}'").errorOrNil, "'%{all}' format option requires --json flag")
        assertNil(parseCommand("list-monitors --format '%{all}' --json").errorOrNil)
        assertEquals(parseCommand("list-monitors --format '%{all} %{monitor-id}'").errorOrNil, "'%{all}' format option must be used alone and cannot be combined with other variables")
        assertEquals(parseCommand("list-monitors --format '%{monitor-name} %{all}'").errorOrNil, "'%{all}' format option must be used alone and cannot be combined with other variables")
        assertNil(parseCommand("list-monitors --format ' %{all} ' --json").errorOrNil)
    }
}

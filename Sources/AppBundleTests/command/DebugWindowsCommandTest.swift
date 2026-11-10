@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct DebugWindowsCommandTest {
    init() { setUpWorkspacesForTests() }

    @Test func testParse() {
        testParseSingleCommandSucc("debug-windows", DebugWindowsCmdArgs(rawArgs: []))
        testParseSingleCommandSucc(
            "debug-windows --window-id 42",
            DebugWindowsCmdArgs(rawArgs: []).with(\.windowId, 42),
        )
        testParseSingleCommandSucc(
            "debug-windows --app-bundle-id com.example.app",
            DebugWindowsCmdArgs(rawArgs: []).with(\.appBundleId, "com.example.app"),
        )
    }
}

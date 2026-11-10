@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct ListAppsTest {
    @Test func testParse() {
        assertNotNil(parseCommand("list-apps --macos-native-hidden").cmdOrDie)
        assertNotNil(parseCommand("list-apps --macos-native-hidden no").cmdOrDie)
        assertNotNil(parseCommand("list-apps --format %{app-bundle-id}").cmdOrDie)
        assertNotNil(parseCommand("list-apps --count").cmdOrDie)
        assertEquals(parseCommand("list-apps --format %{app-bundle-id} --count").errorOrNil, "ERROR: Conflicting flags: --count, --format")
        assertEquals(parseCommand("list-apps --format '%{all}'").errorOrNil, "'%{all}' format option requires --json flag")
        assertNil(parseCommand("list-apps --format '%{all}' --json").errorOrNil)
        assertEquals(parseCommand("list-apps --format '%{all} %{app-name}'").errorOrNil, "'%{all}' format option must be used alone and cannot be combined with other variables")
        assertEquals(parseCommand("list-apps --format '%{app-bundle-id} %{all}'").errorOrNil, "'%{all}' format option must be used alone and cannot be combined with other variables")
        assertNil(parseCommand("list-apps --format ' %{all} ' --json").errorOrNil)
    }
}

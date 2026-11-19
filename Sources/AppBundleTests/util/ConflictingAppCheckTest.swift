@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct ConflictingAppCheckTest {
    private let ownPid: Int32 = 100
    private let otherPid: Int32 = 200

    @Test func testDetectsUpstreamAeroSpaceBuilds() {
        assertTrue(isConflictingApp(appId: "bobko.aerospace", pid: otherPid, ownPid: ownPid))
        assertTrue(isConflictingApp(appId: "bobko.aerospace.debug", pid: otherPid, ownPid: ownPid))
    }

    /// Blocking on ourselves would make the app refuse to ever start.
    @Test func testOwnProcessIsNeverAConflict() {
        assertFalse(isConflictingApp(appId: aeroSpaceAppId, pid: ownPid, ownPid: ownPid))
    }

    /// A dev build left running next to the installed app: same app id, different process. Both
    /// manage the same windows, and a click made the stale one drag focus back to its own workspace.
    @Test func testSecondCopyOfThisAppIsAConflict() {
        assertTrue(isConflictingApp(appId: aeroSpaceAppId, pid: otherPid, ownPid: ownPid))
    }

    @Test func testUnrelatedAppsAreIgnored() {
        for appId in ["com.apple.finder", "com.koekeishiya.yabai", "com.if.Amethyst"] {
            assertFalse(isConflictingApp(appId: appId, pid: otherPid, ownPid: ownPid))
        }
    }
}

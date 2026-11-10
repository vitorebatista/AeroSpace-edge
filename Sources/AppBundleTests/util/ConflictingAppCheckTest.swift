@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct ConflictingAppCheckTest {
    @Test func testDetectsUpstreamAeroSpaceBuilds() {
        assertEquals(conflictingAppIds(among: ["bobko.aerospace"]), ["bobko.aerospace"])
        assertEquals(conflictingAppIds(among: ["bobko.aerospace.debug"]), ["bobko.aerospace.debug"])
    }

    /// Blocking on ourselves would make the app refuse to ever start.
    @Test func testOwnAppIdIsNeverAConflict() {
        assertEquals(conflictingAppIds(among: [aeroSpaceAppId]), [])
        assertEquals(conflictingAppIds(among: [stableAeroSpaceAppId]).contains(aeroSpaceAppId), false)
    }

    @Test func testUnrelatedAppsAreIgnored() {
        assertEquals(conflictingAppIds(among: ["com.apple.finder", "com.koekeishiya.yabai", "com.if.Amethyst"]), [])
    }

    @Test func testPicksConflictsOutOfAFullRunningAppList() {
        let running = ["com.apple.finder", "bobko.aerospace", aeroSpaceAppId, "com.googlecode.iterm2"]
        assertEquals(conflictingAppIds(among: running), ["bobko.aerospace"])
    }
}

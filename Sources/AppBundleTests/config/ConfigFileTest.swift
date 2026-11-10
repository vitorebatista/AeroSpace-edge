@testable import AppBundle
import Common
import Foundation
import Testing

@MainActor
@Suite(.serializedGlobally)
struct ConfigFileTest {
    /// AeroSpace-edge must look at its own config before falling back to an upstream AeroSpace config,
    /// and the two must live in separate tiers so that having both isn't an "ambiguous config" error.
    @Test func testOwnConfigIsPreferredOverUpstreamConfig() {
        let home = URL(filePath: "/Users/test/")
        let xdg = URL(filePath: "/Users/test/.config/")
        let tiers = configCandidateTiers(home: home, xdgConfigHome: xdg).map { $0.map(\.path) }

        assertEquals(tiers.count, 2)
        assertEquals(tiers[0], ["/Users/test/.aerospace-edge.toml", "/Users/test/.config/aerospace-edge/aerospace-edge.toml"])
        assertEquals(tiers[1], ["/Users/test/.aerospace.toml", "/Users/test/.config/aerospace/aerospace.toml"])
    }
}

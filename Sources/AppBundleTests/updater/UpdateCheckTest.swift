@testable import AppBundle
import Common
import Foundation
import Testing

@MainActor
@Suite(.serializedGlobally)
struct UpdateCheckTest {
    // MARK: - Version ordering

    /// The bug a string comparison would introduce: "1.9" > "1.10" lexicographically, so every 1.10+ user
    /// would be told to "update" back to 1.9, forever.
    @Test func testDoubleDigitMinorSortsAfterSingleDigit() {
        assertTrue(AppVersion("1.9")! < AppVersion("1.10")!)
        assertEquals(AppVersion("1.10")! < AppVersion("1.9")!, false)
    }

    @Test func testMissingComponentsAreZero() {
        assertEquals(AppVersion("1.11")! < AppVersion("1.11.0")!, false)
        assertEquals(AppVersion("1.11.0")! < AppVersion("1.11")!, false)
        assertTrue(AppVersion("1.11")! < AppVersion("1.11.1")!)
    }

    @Test func testLeadingVIsAccepted() {
        assertEquals(AppVersion("v1.11")!.description, "1.11")
    }

    /// Debug builds report 0.0.0-SNAPSHOT. Rather than guessing, the checker declines to compare.
    @Test func testUnparsableVersionsAreRejected() {
        assertNil(AppVersion("0.0.0-SNAPSHOT"))
        assertNil(AppVersion("0.20.3-Beta-fork.9"))
        assertNil(AppVersion(""))
        assertNil(AppVersion("1.x"))
    }

    // MARK: - Release parsing

    private func releasesJson(_ body: String) -> Data { body.data(using: .utf8)! }

    /// Every AeroSpace-edge release is a prerelease, so prereleases must be eligible — treating them the
    /// way GitHub's /releases/latest does would mean never finding an update at all.
    @Test func testPrereleasesAreEligible() {
        let json = releasesJson("""
            [{"tag_name":"v1.11","draft":false,"prerelease":true,"body":"notes",
              "assets":[{"name":"AeroSpace-edge-v1.11.zip","browser_download_url":"https://github.com/vitorebatista/AeroSpace-edge/releases/download/v1.11/AeroSpace-edge-v1.11.zip"}]}]
            """)
        let release = newestRelease(inReleasesJson: json)
        assertEquals(release?.tag, "v1.11")
        assertEquals(release?.version.description, "1.11")
    }

    @Test func testPicksHighestVersionNotFirstListed() {
        let json = releasesJson("""
            [{"tag_name":"v1.9","draft":false,"body":"","assets":[{"name":"a.zip","browser_download_url":"https://github.com/x/y/releases/download/v1.9/a.zip"}]},
             {"tag_name":"v1.11","draft":false,"body":"","assets":[{"name":"b.zip","browser_download_url":"https://github.com/x/y/releases/download/v1.11/b.zip"}]},
             {"tag_name":"v1.10","draft":false,"body":"","assets":[{"name":"c.zip","browser_download_url":"https://github.com/x/y/releases/download/v1.10/c.zip"}]}]
            """)
        assertEquals(newestRelease(inReleasesJson: json)?.version.description, "1.11")
    }

    @Test func testDraftsAreIgnored() {
        let json = releasesJson("""
            [{"tag_name":"v1.12","draft":true,"body":"","assets":[{"name":"a.zip","browser_download_url":"https://github.com/x/y/releases/download/v1.12/a.zip"}]},
             {"tag_name":"v1.11","draft":false,"body":"","assets":[{"name":"b.zip","browser_download_url":"https://github.com/x/y/releases/download/v1.11/b.zip"}]}]
            """)
        assertEquals(newestRelease(inReleasesJson: json)?.version.description, "1.11")
    }

    /// A release with no installable asset (notes-only, or assets still uploading) must not be offered.
    @Test func testReleaseWithoutZipIsSkipped() {
        let json = releasesJson("""
            [{"tag_name":"v1.12","draft":false,"body":"","assets":[]},
             {"tag_name":"v1.11","draft":false,"body":"","assets":[{"name":"b.zip","browser_download_url":"https://github.com/x/y/releases/download/v1.11/b.zip"}]}]
            """)
        assertEquals(newestRelease(inReleasesJson: json)?.version.description, "1.11")
    }

    /// The app replaces its own bundle with this download, so an asset URL pointing off GitHub is dropped
    /// rather than followed.
    @Test func testAssetOnForeignHostIsRejected() {
        let json = releasesJson("""
            [{"tag_name":"v1.12","draft":false,"body":"","assets":[{"name":"evil.zip","browser_download_url":"https://evil.example.com/evil.zip"}]}]
            """)
        assertNil(newestRelease(inReleasesJson: json))
    }

    @Test func testMalformedJsonIsHandled() {
        assertNil(newestRelease(inReleasesJson: releasesJson("not json")))
        assertNil(newestRelease(inReleasesJson: releasesJson("{}")))
        assertNil(newestRelease(inReleasesJson: releasesJson("[]")))
    }

    // MARK: - Download allowlist

    @Test func testUpdateUrlAllowlist() {
        assertTrue(isAllowedUpdateUrl(URL(string: "https://github.com/vitorebatista/AeroSpace-edge/releases/download/v1.11/a.zip")!))
        assertTrue(isAllowedUpdateUrl(URL(string: "https://objects.githubusercontent.com/foo")!))
        assertEquals(isAllowedUpdateUrl(URL(string: "http://github.com/a.zip")!), false) // plain http
        assertEquals(isAllowedUpdateUrl(URL(string: "https://evil.example.com/a.zip")!), false)
        assertEquals(isAllowedUpdateUrl(URL(string: "https://github.com.evil.example.com/a.zip")!), false)
        assertEquals(isAllowedUpdateUrl(URL(string: "file:///tmp/a.zip")!), false)
    }
}

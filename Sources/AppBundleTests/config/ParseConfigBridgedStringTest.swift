@testable import AppBundle
import Common
import Foundation
import Testing

@MainActor
@Suite(.serializedGlobally)
struct ParseConfigBridgedStringTest {
    /// Regression: TOMLDecoder unpacks scalars through
    /// `source.utf8.withContiguousStorageIfAvailable { ... }!`, which returns nil for a String
    /// that isn't natively stored — so parsing text handed back by AppKit/SwiftUI (the Settings
    /// panes) trapped with SIGTRAP instead of returning parse errors.
    @Test func testParsesNonContiguousString() {
        // An all-ASCII NSString bridges eagerly into native storage; a UTF-16-backed one bridges
        // lazily and stays non-contiguous, which is the representation that used to crash.
        let bridged = NSString(string: "# ünïcödé\nstart-at-login = true\n") as String
        // Sanity check that this really is the pathological representation the crash needed.
        assertNil(unsafe bridged.utf8.withContiguousStorageIfAvailable { _ in () })

        let (config, errors) = parseConfigTuple(bridged)
        assertEquals(errors, [])
        assertEquals(config.startAtLogin, true)
    }
}

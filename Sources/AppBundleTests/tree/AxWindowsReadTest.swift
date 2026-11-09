@testable import AppBundle
import ApplicationServices
import Common
import XCTest

// The native-tab replacement check (https://github.com/nikitabobko/AeroSpace/issues/2225) prunes a tracked
// window when it's missing from the app's AXWindows. An app that didn't respond in time
// (kAXErrorCannotComplete) answers nothing at all, which must not read as "every window is missing".
// https://github.com/nikitabobko/AeroSpace/issues/1615
final class AxWindowsReadTest: XCTestCase {
    func testTimedOutReadNeverReportsATabAsMissing() {
        assertEquals(isMissingFromLiveAxWindows(42, in: .timedOut), false)
    }

    func testSuccessfulReadReportsMissingTab() {
        let ax = AXUIElementCreateApplication(getpid())
        let other: WindowIdAndAxUiElement = (windowId: 7, ax: ax)
        let tab: WindowIdAndAxUiElement = (windowId: 42, ax: ax)
        assertEquals(isMissingFromLiveAxWindows(42, in: .windows([])), true)
        assertEquals(isMissingFromLiveAxWindows(42, in: .windows([other])), true)
        assertEquals(isMissingFromLiveAxWindows(42, in: .windows([other, tab])), false)
    }

    func testTimedOutReadRegistersNoWindows() {
        assertEquals(AxWindowsRead.timedOut.isTimedOut, true)
        assertEquals(AxWindowsRead.timedOut.windowsOrEmpty.count, 0)
        assertEquals(AxWindowsRead.windows([]).isTimedOut, false)
    }
}

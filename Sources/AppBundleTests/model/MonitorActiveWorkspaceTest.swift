@testable import AppBundle
import AppKit
import Common
import Testing

private struct DetachedMonitor: MonitorInfo {
    let monitorAppKitNsScreenScreensId = 42
    let name = "Detached"
    let rect: Rect
    var visibleRect: Rect { rect }
    var width: CGFloat { rect.width }
    var height: CGFloat { rect.height }
    let isMain = false
}

@MainActor
@Suite(.serializedGlobally)
struct MonitorActiveWorkspaceTest {
    init() { setUpWorkspacesForTests() }

    /// Regression (fork 01e97d8b): a monitor that `NSScreen.screens` no longer reports (display
    /// reconfiguration — closing/opening the lid with external monitors attached) used to
    /// send `activeWorkspace` (upstream: `visibleWorkspace` -> `toMonitorOrRearrangeMonitors`) into unbounded recursion
    /// and blow the stack.
    @Test func testActiveWorkspaceOfDetachedMonitorTerminates() {
        // The monitor list is the single test monitor at (0, 0) under test, so this one can never be found.
        let detached = DetachedMonitor(rect: Rect(topLeftX: 9000, topLeftY: 9000, width: 1920, height: 1080))
        assertNotNil(detached.visibleWorkspace) // Hangs/crashes if the recursion comes back
    }
}

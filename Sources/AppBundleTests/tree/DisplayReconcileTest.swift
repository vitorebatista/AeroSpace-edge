@testable import AppBundle
import Common
import Foundation
import Testing

/// The focused workspace must stay visible after monitors are added, removed or moved
@MainActor
@Suite(.serializedGlobally)
struct DisplayReconcileTest {
    init() { setUpWorkspacesForTests() }

    // Leave no test monitors or focus behind for other test suites (XCTest's tearDown before the swift-testing migration)
    private func tearDown() {
        setTestMonitors(nil) // gcMonitors() ignores an empty monitor list, so reset to the single test monitor
        gcMonitors()
        resetFocusForTests()
    }

    @Test func testFocusedForceAssignedWorkspaceStaysVisibleWhenMonitorDisconnects() {
        defer { tearDown() }
        seedOpenThreeMonitors(forceAssignNumerics: true)
        assertTrue(Workspace.get(byName: "2").focusWorkspace())
        applyClosedTwoMonitors()
        gcMonitors()

        assertEquals(globalFocus.workspace.name, "2")
        assertEquals(closedRight().visibleWorkspace.name, "2")
        assertFalse(Workspace.get(byName: "R").isVisible)
        assertReconcileInvariants()
        gcMonitors()
        assertEquals(closedRight().visibleWorkspace.name, "2")
        assertFalse(Workspace.get(byName: "R").isVisible)
        assertReconcileInvariants()
    }

    @Test func testFocusedWorkspaceThatStaysVisibleIsNotMoved() {
        defer { tearDown() }
        seedOpenThreeMonitors(forceAssignNumerics: false)
        assertTrue(Workspace.get(byName: "2").focusWorkspace())
        applyClosedTwoMonitors()
        gcMonitors()

        assertEquals(globalFocus.workspace.name, "2")
        assertEquals(closedLeft().visibleWorkspace.name, "2")
        assertEquals(closedRight().visibleWorkspace.name, "R")
        assertReconcileInvariants()
    }

    @Test func testFocusedWorkspaceWinsWhenTwoWorkspacesMapToOneMonitor() {
        defer { tearDown() }
        seedOpenThreeMonitors(forceAssignNumerics: false)
        assertTrue(Workspace.get(byName: "1").focusWorkspace())
        applyClosedTwoMonitors()
        gcMonitors()

        assertEquals(globalFocus.workspace.name, "1")
        assertEquals(closedLeft().visibleWorkspace.name, "1")
        assertFalse(Workspace.get(byName: "2").isVisible)
        assertEquals(closedRight().visibleWorkspace.name, "R")
        assertTrue(Workspace.get(byName: "R").isVisible)
        assertReconcileInvariants()
    }

    @Test func testFocusInitializationAfterAllMonitorsDisconnect() {
        defer { tearDown() }
        seedOpenThreeMonitors(forceAssignNumerics: true)
        // gcMonitors() ignores an empty monitor list (upstream would crash on zero screens), so "all monitors
        // disconnected" is not observable any more; start from the reset focus directly
        resetFocusForTests()
        assertNil(initializedFocusWorkspaceName)
        setTestMonitors([closedLeft()])
        gcMonitors()
        assertNil(initializedFocusWorkspaceName) // Rearranging must not initialize the focus

        // Initializing the focus rearranges the monitors once and doesn't recurse
        setTestMonitors([closedLeft()])
        let workspace = globalFocus.workspace
        assertNotNil(initializedFocusWorkspaceName)
        assertTrue(workspace.isVisible)
        assertEquals(closedLeft().visibleWorkspace.name, workspace.name)
        assertReconcileInvariants()
    }

    @Test func testFocusedWorkspaceStaysVisibleWhenMonitorsMove() {
        defer { tearDown() }
        config.persistentWorkspaces = ["1", "R"]
        setTestMonitors([closedLeft(), closedRight()])
        gcMonitors()
        check(closedLeft().setVisibleWorkspace(Workspace.get(byName: "1")))
        check(closedRight().setVisibleWorkspace(Workspace.get(byName: "R")))
        assertTrue(Workspace.get(byName: "1").focusWorkspace())

        let shiftedLeft = testMonitor(
            name: "Left",
            id: 1,
            topLeftX: 10,
            topLeftY: 10,
            width: 1920,
            height: 1080,
            isMain: true,
        )
        let shiftedRight = testMonitor(
            name: "Right",
            id: 2,
            topLeftX: 1930,
            topLeftY: 10,
            width: 1920,
            height: 1080,
            isMain: false,
        )
        setTestMonitors([shiftedLeft, shiftedRight])
        gcMonitors()
        assertEquals(closedLeft().visibleWorkspace.name, "1")

        assertEquals(shiftedLeft.visibleWorkspace.name, "1")
        assertTrue(Workspace.get(byName: "1").isVisible)
        assertEquals(shiftedRight.visibleWorkspace.name, "R")
        assertReconcileInvariants()
    }

    // Fork: the focused workspace is persisted the moment focus changes (fork #71). Reconciliation only re-shows the
    // focused workspace; it never changes focus, so the persisted name must neither be rewritten nor fall out of view
    @Test func testReconcileDoesNotRewritePersistedFocusedWorkspace() {
        defer { tearDown() }
        UserDefaults.standard.removeObject(forKey: focusedWorkspaceDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: focusedWorkspaceDefaultsKey) }
        seedOpenThreeMonitors(forceAssignNumerics: true)
        assertTrue(Workspace.get(byName: "2").focusWorkspace())
        assertEquals(storedFocusedWorkspace(), "2")
        storeFocusedWorkspace("stale-marker")

        applyClosedTwoMonitors()
        gcMonitors()

        assertEquals(storedFocusedWorkspace(), "stale-marker")
        assertEquals(globalFocus.workspace.name, "2")
        assertTrue(Workspace.get(byName: "2").isVisible)
        assertReconcileInvariants()
    }

    // An empty monitor list (a transient state during display reconfiguration) is ignored: nothing is rearranged,
    // the focus and the visible workspaces stay as they were
    @Test func testEmptyMonitorListIsIgnored() {
        defer { tearDown() }
        seedOpenThreeMonitors(forceAssignNumerics: true)
        assertTrue(Workspace.get(byName: "2").focusWorkspace())
        let visibleBefore = visibleSnapshot()
        setTestMonitors([])
        gcMonitors()
        assertEquals(globalFocus.workspace.name, "2")
        assertTrue(Workspace.get(byName: "2").isVisible)
        assertEquals(visibleSnapshot(), visibleBefore)
    }
}

private struct TestMonitor: MonitorInfo {
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let rect: Rect
    let visibleRect: Rect
    let isMain: Bool
    var width: CGFloat { rect.width }
    var height: CGFloat { rect.height }
}

@MainActor
private func setTestMonitors(_ monitors: [MonitorInfo]?) {
    unsafe monitorsForTests = monitors
}

@MainActor
private func testMonitor(
    name: String,
    id: Int,
    topLeftX: CGFloat,
    topLeftY: CGFloat,
    width: CGFloat,
    height: CGFloat,
    isMain: Bool,
) -> MonitorInfo {
    let rect = Rect(topLeftX: topLeftX, topLeftY: topLeftY, width: width, height: height)
    return TestMonitor(
        monitorAppKitNsScreenScreensId: id,
        name: name,
        rect: rect,
        visibleRect: rect,
        isMain: isMain,
    )
}

@MainActor
private func openLeft() -> MonitorInfo {
    testMonitor(name: "Left", id: 1, topLeftX: -1920, topLeftY: -1080, width: 1920, height: 1080, isMain: false)
}

@MainActor
private func openLaptop() -> MonitorInfo {
    testMonitor(name: "Laptop", id: 2, topLeftX: 0, topLeftY: 0, width: 1728, height: 1117, isMain: true)
}

@MainActor
private func openRight() -> MonitorInfo {
    testMonitor(name: "Right", id: 3, topLeftX: 1728, topLeftY: -1080, width: 1920, height: 1080, isMain: false)
}

@MainActor
private func closedLeft() -> MonitorInfo {
    testMonitor(name: "Left", id: 1, topLeftX: 0, topLeftY: 0, width: 1920, height: 1080, isMain: true)
}

@MainActor
private func closedRight() -> MonitorInfo {
    testMonitor(name: "Right", id: 2, topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080, isMain: false)
}

@MainActor
private func seedOpenThreeMonitors(forceAssignNumerics: Bool) {
    config.persistentWorkspaces = ["1", "2", "R"]
    if forceAssignNumerics {
        config.workspaceToMonitorForceAssignment = [
            "1": [.sequenceNumber(1)],
            "2": [.sequenceNumber(2)],
        ]
    }
    setTestMonitors([openLeft(), openLaptop(), openRight()])
    gcMonitors()
    check(openLeft().setVisibleWorkspace(Workspace.get(byName: "1")))
    check(openLaptop().setVisibleWorkspace(Workspace.get(byName: "2")))
    check(openRight().setVisibleWorkspace(Workspace.get(byName: "R")))
}

@MainActor
private func applyClosedTwoMonitors() {
    setTestMonitors([closedLeft(), closedRight()])
}

@MainActor
private func visibleSnapshot() -> [String] {
    Workspace.all
        .filter(\.isVisible)
        .map { "\($0.name)@\($0.workspaceMonitorInfo.rect.topLeftX),\($0.workspaceMonitorInfo.rect.topLeftY)" }
        .sorted()
}

@MainActor
private func assertReconcileInvariants() {
    let visibles = Workspace.all.filter(\.isVisible)
    let origins = visibles.map { "\($0.workspaceMonitorInfo.rect.topLeftX),\($0.workspaceMonitorInfo.rect.topLeftY)" }
    assertEquals(Set(origins).count, origins.count)
    assertEquals(visibles.count, globalSortedMonitorInfos.count)
    for monitor in globalSortedMonitorInfos {
        assertEquals(visibles.count(where: { $0.workspaceMonitorInfo.rect.topLeftCorner == monitor.rect.topLeftCorner }), 1)
    }
}

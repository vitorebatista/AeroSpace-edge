@testable import AppBundle
import Common
import Foundation
import Testing

@MainActor
@Suite(.serializedGlobally)
struct PersistedLayoutTest {
    init() { setUpWorkspacesForTests() }

    /// The whole point of persisting to disk, so this has to actually round-trip.
    @Test func testFrozenWorldSurvivesJson() throws {
        let ws = Workspace.get(byName: "round-trip")
        TestWindow.new(id: 1, parent: ws.rootTilingContainer)
        TestWindow.new(id: 2, parent: ws.rootTilingContainer)
        let world = frozen(ws)

        let decoded = try JSONDecoder().decode(FrozenWorld.self, from: JSONEncoder().encode(world))
        assertEquals(decoded.windowIds, [1, 2])
        // Upstream's FrozenWorld is per monitor and freezes every workspace of the monitor
        let decodedWorkspace = decoded.monitors.flatMap(\.workspaces).first { $0.name == "round-trip" }
        assertEquals(decodedWorkspace?.rootTilingNode.children.count, 2)
    }

    /// The two-Brave-windows case: after a restart the windows are live under *new* ids, so the
    /// restore has to place them by the app + title match rather than by id, and they must land on
    /// the separate workspaces they were on — not both on whichever one is active.
    @Test func testRestorePlacesRematchedWindowsOnTheirOwnWorkspaces() async throws {
        let ws1 = Workspace.get(byName: "one")
        let ws2 = Workspace.get(byName: "two")
        TestWindow.new(id: 1, parent: ws1.rootTilingContainer)
        TestWindow.new(id: 2, parent: ws2.rootTilingContainer)
        let world = try JSONDecoder().decode(
            FrozenWorld.self, from: JSONEncoder().encode(frozen(ws1, ws2)))

        // Restart: the old windows are gone and the same two apps came back under fresh ids, both
        // dumped into one workspace the way an unrestored startup leaves them.
        for window in [Window.get(byId: 1), Window.get(byId: 2)] { window?.unbindFromParent() }
        let scratch = Workspace.get(byName: "scratch")
        let new1 = TestWindow.new(id: 101, parent: scratch.rootTilingContainer)
        let new2 = TestWindow.new(id: 102, parent: scratch.rootTilingContainer)

        let rematched: [OpaqueWindowId: Window] = [1: new1, 2: new2]
        try await applyFrozenWorld(world) { rematched[$0.id] }

        assertEquals(new1.nodeWorkspace?.name, "one")
        assertEquals(new2.nodeWorkspace?.name, "two")
    }

    private func frozen(_ workspaces: Workspace...) -> FrozenWorld {
        FrozenWorld(
            monitors: Monitor.all.map(FrozenMonitor.init),
            windowIds: workspaces.flatMap { collectAllWindowIdsRecursive($0) }.toSet(),
        )
    }
}

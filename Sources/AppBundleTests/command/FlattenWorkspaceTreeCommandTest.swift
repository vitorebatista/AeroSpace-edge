@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct FlattenWorkspaceTreeCommandTest {
    init() { setUpWorkspacesForTests() }

    @Test func testSimple() async {
        let workspace = Workspace.get(byName: name).apply {
            $0.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0)
                TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                    TestWindow.new(id: 2, parent: $0)
                }
            }
            TestWindow.new(id: 3, parent: $0.floatingWindowsContainer) // floating
        }
        assertEquals(workspace.focusWorkspace(), true)

        await parseCommand("flatten-workspace-tree").cmdOrDie.run(.defaultEnv, .emptyStdin)
        // normalizeContainers() is called inside the command (fork: upstream PR #1953), so no need to call it here.
        assertEquals(workspace.layoutDescription, .workspace([.h_tiles([.window(1), .window(2)]), .floatingWindowsContainer([.window(3)])]))
    }

    @Test func testDeeplyNested() async {
        // Verify flatten fully normalizes a deeply nested tree (no residual containers).
        let workspace = Workspace.get(byName: name).apply {
            $0.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0)
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    TestWindow.new(id: 2, parent: $0)
                    TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                        TestWindow.new(id: 3, parent: $0)
                        TestWindow.new(id: 4, parent: $0)
                    }
                }
            }
        }
        assertEquals(workspace.focusWorkspace(), true)

        // Before flatten: root → [window(1), v_tiles → [window(2), h_tiles → [window(3), window(4)]]]
        await FlattenWorkspaceTreeCommand(args: FlattenWorkspaceTreeCmdArgs(rawArgs: [])).run(.defaultEnv, .emptyStdin)
        // After flatten: all windows are direct children of root, no residual containers.
        assertEquals(workspace.layoutDescription, .workspace([.h_tiles([.window(1), .window(2), .window(3), .window(4)])]))
    }
}

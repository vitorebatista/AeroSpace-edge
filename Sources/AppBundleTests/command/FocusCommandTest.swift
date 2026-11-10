@testable import AppBundle
import Common
import Testing

// todo write tests
//
// test 1
//     horizontal
//         window1
//         vertical
//             vertical
//                 window2 <-- focused
//             vertical
//                 window5
//                 horizontal
//                     window3
//                     window4
// pre-condition: focus_wrapping force_workspace
// action: focus up
// expected: mru(window3, window4) is focused

@MainActor
@Suite(.serializedGlobally)
struct FocusCommandTest {
    init() { setUpWorkspacesForTests() }

    @Test func testParse() {
        #expect(parseCommand("focus --boundaries left").errorOrNil?.contains("Possible values") == true)
        var expected = FocusCmdArgs(rawArgs: [], cardinalOrDfsDirection: .direction(.left))
        expected.rawBoundaries = .workspace
        testParseSingleCommandSucc("focus --boundaries workspace left", expected)

        assertEquals(
            parseCommand("focus --boundaries workspace --boundaries workspace left").errorOrNil,
            "ERROR: Duplicated flag '--boundaries'",
        )
        assertEquals(
            parseCommand("focus --window-id 42 --ignore-floating").errorOrNil,
            "--window-id is incompatible with other options",
        )
        assertEquals(
            parseCommand("focus --boundaries all-monitors-outer-frame dfs-next").errorOrNil,
            "(dfs-next|dfs-prev) only supports --boundaries workspace",
        )

        assertEquals(
            parseCommand("focus --window-id 42 --wrap-around").errorOrNil,
            "--window-id is incompatible with other options",
        )
        assertEquals(
            parseCommand("focus left --boundaries-action wrap-around-the-workspace --wrap-around").errorOrNil,
            "ERROR: Conflicting flags: --boundaries-action, --wrap-around",
        )
        assertEquals(
            parseCommand("focus dfs-next --fail-if-fullscreen").errorOrNil,
            "--fail-if-fullscreen/--fail-if-macos-native-fullscreen require using (left|down|up|right) argument",
        )
        assertEquals(
            parseCommand("focus --fail-if-macos-native-fullscreen --window-id 42").errorOrNil,
            "--window-id is incompatible with other options",
        )
        assertNil(parseCommand("focus --fail-if-fullscreen --fail-if-macos-native-fullscreen left").errorOrNil)
    }

    @Test func testFailIfFullscreen() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            let window = TestWindow.new(id: 1, parent: $0)
            assertEquals(window.focusWindow(), true)
            window.isFullscreen = true
            TestWindow.new(id: 2, parent: $0)
        }

        let result = await parseCommand("focus --fail-if-fullscreen right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(globalFocus.windowOrNil?.windowId, 1)
    }

    @Test func testFailIfMacosNativeFullscreen() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            let window = TestWindow.new(id: 1, parent: $0)
            assertEquals(window.focusWindow(), true)
            window.isMacosFullscreenForTest = true

            TestWindow.new(id: 2, parent: $0)
        }

        let result = await parseCommand("focus --fail-if-macos-native-fullscreen right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(globalFocus.windowOrNil?.windowId, 1)
    }

    @Test func testFailIfFullscreenAllowsRegularWindows() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        let result = await parseCommand("focus --fail-if-fullscreen --fail-if-macos-native-fullscreen right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(globalFocus.windowOrNil?.windowId, 2)
    }

    @Test func testFocus() {
        assertEquals(globalFocus.windowOrNil, nil)
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            TestWindow.new(id: 3, parent: $0)
        }
        assertEquals(globalFocus.windowOrNil?.windowId, 2)
    }

    @Test func testFocusOverFloatingWindows() async {
        assertEquals(globalFocus.windowOrNil, nil)
        Workspace.get(byName: name).floatingWindowsContainer.apply {
            TestWindow.new(id: 1, parent: $0, rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100))
            assertEquals(TestWindow.new(id: 2, parent: $0, rect: Rect(topLeftX: 10, topLeftY: 10, width: 100, height: 100)).focusWindow(), true)
            TestWindow.new(id: 3, parent: $0, rect: Rect(topLeftX: 20, topLeftY: 20, width: 100, height: 100))
        }

        assertEquals(globalFocus.windowOrNil?.windowId, 2)
        await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 3)
    }

    @Test func testFocusAlongTheContainerOrientation() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(globalFocus.windowOrNil?.windowId, 1)
        await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 2)
    }

    @Test func testFocusAcrossTheContainerOrientation() async {
        Workspace.get(byName: name).apply {
            TestWindow.new(id: 1, parent: $0.rootTilingContainer)
            TestWindow.new(id: 2, parent: $0.rootTilingContainer)
            assertEquals($0.focusWorkspace(), true)
        }

        assertEquals(globalFocus.windowOrNil?.windowId, 2)
        await parseCommand("focus up").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 2)
        await parseCommand("focus down").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 2)
    }

    @Test func testFocusNoWrapping() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(globalFocus.windowOrNil?.windowId, 1)
        await parseCommand("focus left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 1)
    }

    @Test func testFocusWrapping() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(globalFocus.windowOrNil?.windowId, 1)
        await parseCommand("focus --boundaries workspace --boundaries-action wrap-around-the-workspace left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 2)
    }

    @Test func testFocusFindMruLeaf() async {
        let workspace = Workspace.get(byName: name)
        var startWindow: Window!
        var window2: Window!
        var window3: Window!
        var unrelatedWindow: Window!
        workspace.rootTilingContainer.apply {
            startWindow = TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                    window2 = TestWindow.new(id: 2, parent: $0)
                    unrelatedWindow = TestWindow.new(id: 5, parent: $0)
                }
                window3 = TestWindow.new(id: 3, parent: $0)
            }
        }

        assertEquals(workspace.mostRecentWindowRecursive?.windowId, 3) // The latest bound
        _ = startWindow.focusWindow()
        await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 3)

        window2.markAsMostRecentChild()
        _ = startWindow.focusWindow()
        await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 2)

        window3.markAsMostRecentChild()
        unrelatedWindow.markAsMostRecentChild()
        _ = startWindow.focusWindow()
        await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 2)
    }

    @Test func testFocusOutsideOfTheContainer() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            }
        }

        await parseCommand("focus left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 1)
    }

    @Test func testFocusOutsideOfTheContainer2() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            }
        }

        await parseCommand("focus left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 1)
    }

    @Test func testFocusDfsRelative() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                    TestWindow.new(id: 2, parent: $0)
                    TestWindow.new(id: 3, parent: $0)
                }
            }
            TestWindow.new(id: 4, parent: $0)
        }

        assertEquals(globalFocus.windowOrNil?.windowId, 1)

        await parseCommand("focus dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 2)
        await parseCommand("focus dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 3)
        await parseCommand("focus dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 4)

        await parseCommand("focus dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 3)
        await parseCommand("focus dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 2)
        await parseCommand("focus dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 1)
    }

    @Test func testFocusSkipsTombstones() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0).lifeStatus = .dead
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 3, parent: $0).lifeStatus = .invisible
                $0.lifeStatus = .deadOrInvisible
            }
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 4, parent: $0).lifeStatus = .invisible
                TestWindow.new(id: 5, parent: $0)
                TestWindow.new(id: 6, parent: $0).lifeStatus = .dead
            }
            TestWindow.new(id: 7, parent: $0)
        }

        assertEquals(globalFocus.windowOrNil?.windowId, 1)

        // Directional
        await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 5)
        await parseCommand("focus down").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 5)
        await parseCommand("focus up").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 5)
        await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 7)
        await parseCommand("focus left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 5)
        await parseCommand("focus left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 1)
        await parseCommand("focus --boundaries-action wrap-around-the-workspace left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 7)
        await parseCommand("focus --boundaries-action wrap-around-the-workspace right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 1)

        // DFS relative
        await parseCommand("focus dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 5)
        await parseCommand("focus dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 7)
        await parseCommand("focus --boundaries-action wrap-around-the-workspace dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 1)
        await parseCommand("focus --boundaries-action wrap-around-the-workspace dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 7)
        await parseCommand("focus dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 5)

        // DFS index
        await parseCommand("focus --dfs-index 0").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 1)
        await parseCommand("focus --dfs-index 1").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 5)
        await parseCommand("focus --dfs-index 2").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 7)
        assertEquals(await parseCommand("focus --dfs-index 3").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 2)
        assertEquals(globalFocus.windowOrNil?.windowId, 7)

        // --window-id still focuses tombstones
        await parseCommand("focus --window-id 2").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 2)
    }

    @Test func testFocusDfsRelativeWrapping() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(globalFocus.windowOrNil?.windowId, 1)

        assertEquals(await parseCommand("focus --boundaries-action stop dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
        assertEquals(globalFocus.windowOrNil?.windowId, 1)

        assertEquals(await parseCommand("focus --boundaries-action fail dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 2)
        assertEquals(globalFocus.windowOrNil?.windowId, 1)

        assertEquals(await parseCommand("focus --boundaries-action wrap-around-the-workspace dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
        assertEquals(globalFocus.windowOrNil?.windowId, 2)

        assertEquals(await parseCommand("focus --boundaries-action stop dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
        assertEquals(globalFocus.windowOrNil?.windowId, 2)

        assertEquals(await parseCommand("focus --boundaries-action fail dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 2)
        assertEquals(globalFocus.windowOrNil?.windowId, 2)

        assertEquals(await parseCommand("focus --boundaries-action wrap-around-the-workspace dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
        assertEquals(globalFocus.windowOrNil?.windowId, 1)
    }

    // https://github.com/nikitabobko/AeroSpace/issues/1311
    // 'a' is suspended in the first getCenter of makeFloatingWindowsSeenAsTiling, 'b' unbinds the same floating window
    // meanwhile. Before the fix, 'a' died with "is already unbound" once it was resumed
    @Test func testConcurrentFocusOverFloatingWindows() async throws {
        let workspace = Workspace.get(byName: name)
        assertEquals(workspace.focusWorkspace(), true)
        let monitorRect = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
        // The tiling window covers the whole monitor, so that the second getCenter of the loop is reachable too
        let tiling = TestWindow.new(id: 1, parent: workspace.rootTilingContainer, rect: monitorRect)
        tiling.lastAppliedLayoutVirtualRect = monitorRect
        let floating1 = TestWindow.new(id: 2, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 100, topLeftY: 100, width: 200, height: 200))
        let floating2 = TestWindow.new(id: 3, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 900, topLeftY: 500, width: 200, height: 200))
        assertEquals(tiling.focusWindow(), true)
        assertEquals(workspace.floatingWindows.map(\.windowId), [2, 3])

        let aSuspended = AwaitableOneTimeBroadcastLatch()
        let aResume = AwaitableOneTimeBroadcastLatch()
        floating1.onNextGetAxRectForTest = {
            await aSuspended.signalToAll()
            try await aResume.await(.nonCancellable)
        }
        let a = Task.startUnstructured { @MainActor in _ = await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin) }
        try await aSuspended.await(.nonCancellable)
        assertTrue(floating1.isBound) // 'a' hasn't unbound it yet

        // floating1's hook is already consumed, so 'b' unbinds floating1 and suspends on floating2
        let bSuspended = AwaitableOneTimeBroadcastLatch()
        let bResume = AwaitableOneTimeBroadcastLatch()
        floating2.onNextGetAxRectForTest = {
            await bSuspended.signalToAll()
            try await bResume.await(.nonCancellable)
        }
        let b = Task.startUnstructured { @MainActor in _ = await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin) }
        try await bSuspended.await(.nonCancellable)
        // makeFloatingWindowsSeenAsTiling doesn't mutate the tree until its last await, so 'b' hasn't touched floating1
        assertTrue(floating1.parent === workspace.floatingWindowsContainer)
        assertTrue(floating2.isBound)

        await aResume.signalToAll()
        await a.value
        await bResume.signalToAll()
        await b.value

        // Every floating window is bound back, none is lost, duplicated, or left in the tiling tree
        assertTrue(floating1.parent === workspace.floatingWindowsContainer)
        assertTrue(floating2.parent === workspace.floatingWindowsContainer)
        assertEquals(workspace.floatingWindows.map(\.windowId.rawId).sorted(), [2, 3])
        assertEquals(workspace.rootTilingContainer.allLeafWindowsRecursive.map(\.windowId), [1])
        assertTrue(tiling.parent === workspace.rootTilingContainer)
    }

    // https://github.com/nikitabobko/AeroSpace/issues/1311
    // The same race, but 'a' is suspended in the second getCenter of the loop (the AX read of the tiling window it is
    // about to be inserted next to). That's why both suspension points must re-validate the window
    @Test func testConcurrentFocusOverFloatingWindows2() async throws {
        let workspace = Workspace.get(byName: name)
        assertEquals(workspace.focusWorkspace(), true)
        let monitorRect = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
        let tiling = TestWindow.new(id: 1, parent: workspace.rootTilingContainer, rect: monitorRect)
        tiling.lastAppliedLayoutVirtualRect = monitorRect
        let floating1 = TestWindow.new(id: 2, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 100, topLeftY: 100, width: 200, height: 200))
        let floating2 = TestWindow.new(id: 3, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 900, topLeftY: 500, width: 200, height: 200))
        assertEquals(tiling.focusWindow(), true)

        let aSuspended = AwaitableOneTimeBroadcastLatch()
        let aResume = AwaitableOneTimeBroadcastLatch()
        tiling.onNextGetAxRectForTest = {
            await aSuspended.signalToAll()
            try await aResume.await(.nonCancellable)
        }
        let a = Task.startUnstructured { @MainActor in _ = await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin) }
        try await aSuspended.await(.nonCancellable)
        assertTrue(floating1.isBound)

        let bSuspended = AwaitableOneTimeBroadcastLatch()
        let bResume = AwaitableOneTimeBroadcastLatch()
        floating2.onNextGetAxRectForTest = {
            await bSuspended.signalToAll()
            try await bResume.await(.nonCancellable)
        }
        let b = Task.startUnstructured { @MainActor in _ = await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin) }
        try await bSuspended.await(.nonCancellable)
        // makeFloatingWindowsSeenAsTiling doesn't mutate the tree until its last await, so 'b' hasn't touched floating1
        assertTrue(floating1.parent === workspace.floatingWindowsContainer)

        await aResume.signalToAll()
        await a.value
        await bResume.signalToAll()
        await b.value

        assertTrue(floating1.parent === workspace.floatingWindowsContainer)
        assertTrue(floating2.parent === workspace.floatingWindowsContainer)
        assertEquals(workspace.floatingWindows.map(\.windowId.rawId).sorted(), [2, 3])
        assertEquals(workspace.rootTilingContainer.allLeafWindowsRecursive.map(\.windowId), [1])
    }

    // https://github.com/nikitabobko/AeroSpace/issues/1311
    // The workspace from the report, where all the windows are floating. No tiling window is found under the floating
    // window center, so the loop takes the branch that never reaches the second getCenter, and the first check is the
    // only thing that stands between 'a' and the already unbound window
    @Test func testConcurrentFocusOverFloatingWindows3() async throws {
        let workspace = Workspace.get(byName: name)
        assertEquals(workspace.focusWorkspace(), true)
        let floating1 = TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 100, topLeftY: 100, width: 200, height: 200))
        let floating2 = TestWindow.new(id: 2, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 900, topLeftY: 500, width: 200, height: 200))
        assertEquals(floating1.focusWindow(), true)
        assertEquals(workspace.rootTilingContainer.allLeafWindowsRecursive.map(\.windowId), [])

        let aSuspended = AwaitableOneTimeBroadcastLatch()
        let aResume = AwaitableOneTimeBroadcastLatch()
        floating1.onNextGetAxRectForTest = {
            await aSuspended.signalToAll()
            try await aResume.await(.nonCancellable)
        }
        let a = Task.startUnstructured { @MainActor in _ = await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin) }
        try await aSuspended.await(.nonCancellable)
        assertTrue(floating1.isBound)

        let bSuspended = AwaitableOneTimeBroadcastLatch()
        let bResume = AwaitableOneTimeBroadcastLatch()
        floating2.onNextGetAxRectForTest = {
            await bSuspended.signalToAll()
            try await bResume.await(.nonCancellable)
        }
        let b = Task.startUnstructured { @MainActor in _ = await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin) }
        try await bSuspended.await(.nonCancellable)
        // makeFloatingWindowsSeenAsTiling doesn't mutate the tree until its last await, so 'b' hasn't touched floating1
        assertTrue(floating1.parent === workspace.floatingWindowsContainer)

        await aResume.signalToAll()
        await a.value
        await bResume.signalToAll()
        await b.value

        assertTrue(floating1.parent === workspace.floatingWindowsContainer)
        assertTrue(floating2.parent === workspace.floatingWindowsContainer)
        assertEquals(workspace.floatingWindows.map(\.windowId.rawId).sorted(), [1, 2])
        assertEquals(workspace.rootTilingContainer.allLeafWindowsRecursive.map(\.windowId), [])
    }

    /// `focus --window-id` resolves through MacWindow.allWindowsMap, so unlike
    /// the directional and dfs targets it does not depend on floating windows
    /// being temporarily bound into the tiling tree. Pins the observable
    /// behaviour: focus lands on the requested window, floating windows stay
    /// floating, and the workspace mru points at whatever was focused last.
    @Test func testFocusWindowIdOverFloatingWindows() async {
        assertEquals(globalFocus.windowOrNil, nil)
        let workspace = Workspace.get(byName: name)
        TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertEquals(TestWindow.new(id: 2, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100)).focusWindow(), true)
        TestWindow.new(id: 3, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 20, topLeftY: 20, width: 100, height: 100))
        assertEquals(globalFocus.windowOrNil?.windowId, 2)

        // floating -> floating
        await parseCommand("focus --window-id 3").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 3)
        assertEquals(workspace.floatingWindows.map(\.windowId.rawId).sorted(), [2, 3])
        assertEquals(workspace.mostRecentWindowRecursive?.windowId, 3)

        // floating -> tiling
        await parseCommand("focus --window-id 1").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(globalFocus.windowOrNil?.windowId, 1)
        assertEquals(workspace.floatingWindows.map(\.windowId.rawId).sorted(), [2, 3])
        assertEquals(workspace.mostRecentWindowRecursive?.windowId, 1)
        // The floating windows keep their order. restoreFloatingWindows would have rebound them with INDEX_BIND_LAST
        assertEquals(workspace.floatingWindows.map(\.windowId), [2, 3])
    }

    @Test func testFocusDfsRelativeOverFloatingWindows() async {
        let workspace = Workspace.get(byName: name)
        TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100))
        TestWindow.new(id: 2, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 10, topLeftY: 10, width: 100, height: 100))
        TestWindow.new(id: 3, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 20, topLeftY: 20, width: 100, height: 100))
        assertEquals(TestWindow.new(id: 4, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 30, topLeftY: 30, width: 100, height: 100)).focusWindow(), true)

        assertEquals(globalFocus.windowOrNil?.windowId, 4)
        for expectedWindowId in [1, 2, 3, 4, 1] as [OpaqueWindowId] {
            await parseCommand("focus --wrap-around dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(globalFocus.windowOrNil?.windowId, expectedWindowId)
        }
        assertEquals(workspace.floatingWindows.count, 4)
        assertEquals(workspace.rootTilingContainer.allLeafWindowsRecursive.count, 0)

        for expectedWindowId in [4, 3, 2, 1] as [OpaqueWindowId] {
            await parseCommand("focus --wrap-around dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(globalFocus.windowOrNil?.windowId, expectedWindowId)
        }
        assertEquals(workspace.floatingWindows.count, 4)
        assertEquals(workspace.rootTilingContainer.allLeafWindowsRecursive.count, 0)
    }

    @Test func testFocusDfsRelativeOverFloatingWindowsWithEqualCenters() async {
        let workspace = Workspace.get(byName: name)
        TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100))
        TestWindow.new(id: 2, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100))
        TestWindow.new(id: 3, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 10, topLeftY: 10, width: 100, height: 100))
        assertEquals(TestWindow.new(id: 4, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 20, topLeftY: 20, width: 100, height: 100)).focusWindow(), true)

        assertEquals(globalFocus.windowOrNil?.windowId, 4)
        for expectedWindowId in [1, 2, 3, 4, 1] as [OpaqueWindowId] {
            await parseCommand("focus --wrap-around dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(globalFocus.windowOrNil?.windowId, expectedWindowId)
        }
        assertEquals(workspace.floatingWindows.count, 4)
        assertEquals(workspace.rootTilingContainer.allLeafWindowsRecursive.count, 0)
    }

    @Test func testFocusDfsRelativeOverTilingAndFloatingWindows() async {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }
        TestWindow.new(id: 3, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 10, topLeftY: 10, width: 100, height: 100))
        TestWindow.new(id: 4, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 20, topLeftY: 20, width: 100, height: 100))

        assertEquals(globalFocus.windowOrNil?.windowId, 1)
        for expectedWindowId in [2, 3, 4, 1] as [OpaqueWindowId] {
            await parseCommand("focus --wrap-around dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(globalFocus.windowOrNil?.windowId, expectedWindowId)
        }
        assertEquals(workspace.floatingWindows.count, 2)
        assertEquals(workspace.rootTilingContainer.allLeafWindowsRecursive.count, 2)
    }

    @Test func testFocusDfsRelativeFailsWhenFocusedWindowIsOutsideTilingTree() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
        }
        assertEquals(
            TestWindow.new(id: 2, parent: Workspace.get(byName: name).macOsNativeFullscreenWindowsContainer).focusWindow(),
            true,
        )

        let result = await parseCommand("focus dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, ["Can't find the focused window in the tiling tree of workspace '\(name)'"])
    }
}

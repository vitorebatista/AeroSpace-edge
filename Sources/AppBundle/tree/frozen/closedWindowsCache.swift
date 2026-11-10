import AppKit
import Common

/// First line of defence against lock screen
///
/// When you lock the screen, all accessibility API becomes unobservable (all attributes become empty, window id
/// becomes nil, etc.) which tricks AeroSpace into thinking that all windows were closed.
/// That's why every time a window dies AeroSpace caches the "entire world" (unless window is already presented in the cache)
/// so that once the screen is unlocked, AeroSpace could restore windows to where they were
@MainActor private var closedWindowsCache = FrozenWorld(monitors: [], windowIds: [])

struct FrozenMonitor: Sendable, Codable {
    let visibleWorkspace: String
    let topLeftCorner: CGPoint
    let workspaces: [FrozenWorkspace]

    @MainActor init(_ monitor: Monitor) {
        self.topLeftCorner = monitor.info.rect.topLeftCorner
        self.workspaces = monitor.getWorkspacesContainerOrCreate().children.map { FrozenWorkspace($0 as! Workspace) }
        self.visibleWorkspace = monitor.getWorkspacesContainerOrCreate().getVisibleWorkspaceOrCreate(parent: monitor).name
    }
}

struct FrozenWorkspace: Sendable, Codable {
    let name: String
    let rootTilingNode: FrozenContainer
    let floatingWindows: [FrozenWindow]
    let macosUnconventionalWindows: [FrozenWindow]

    @MainActor init(_ workspace: Workspace) {
        name = workspace.name
        rootTilingNode = FrozenContainer(workspace.rootTilingContainer)
        floatingWindows = workspace.floatingWindows.map(FrozenWindow.init)
        macosUnconventionalWindows =
            workspace.macOsNativeHiddenAppsWindowsContainer.children.map { FrozenWindow($0 as! Window) } +
            workspace.macOsNativeFullscreenWindowsContainer.children.map { FrozenWindow($0 as! Window) }
    }
}

@MainActor func cacheClosedWindowIfNeeded() {
    let allWs = Workspace.all
    let allWindowIds = allWs.flatMap { collectAllWindowIdsRecursive($0) }.toSet()
    if allWindowIds.isSubset(of: closedWindowsCache.windowIds) {
        return // already cached
    }
    closedWindowsCache = FrozenWorld(
        monitors: Monitor.all.map(FrozenMonitor.init),
        windowIds: allWindowIds,
    )
}

@MainActor func restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: Window) async throws -> Bool {
    if !closedWindowsCache.windowIds.contains(newlyDetectedWindow.windowId) {
        return false
    }
    try await applyFrozenWorld(closedWindowsCache) { MacWindow.get(byId: $0.id) }
    return true
}

/// Rebuilds the live tree to match `world`, using `resolve` to turn each frozen window back into a
/// live one. The lock-screen path resolves by window id; ``restorePersistedLayout`` resolves through
/// a precomputed map so it can also fall back to matching on app + title. (fork #71)
@MainActor func applyFrozenWorld(_ world: FrozenWorld, resolve: (FrozenWindow) -> Window?) async throws {
    let monitors = globalUnsortedMonitorInfos
    let topLeftCornerToMonitorInfo = monitors.grouped { $0.rect.topLeftCorner }

    for monitor in world.monitors {
        for frozenWorkspace in monitor.workspaces {
            let workspace = Workspace.get(byName: frozenWorkspace.name)
            _ = topLeftCornerToMonitorInfo[monitor.topLeftCorner]?
                .singleOrNil()?
                .bindWorkspace(workspace)
            for frozenWindow in frozenWorkspace.floatingWindows {
                resolve(frozenWindow)?.bindAsFloatingWindow(to: workspace)
            }
            for frozenWindow in frozenWorkspace.macosUnconventionalWindows { // Will get fixed by normalizations
                resolve(frozenWindow)?.bindAsFloatingWindow(to: workspace)
            }
            let prevRoot = workspace.rootTilingContainer // Save prevRoot into a variable to avoid it being garbage collected earlier than needed
            let potentialOrphans = prevRoot.allLeafWindowsRecursive
            prevRoot.unbindFromParent()
            restoreTreeRecursive(frozenContainer: frozenWorkspace.rootTilingNode, parent: workspace, index: INDEX_BIND_LAST, resolve: resolve)
            for window in (potentialOrphans - workspace.rootTilingContainer.allLeafWindowsRecursive) {
                try await window.relayoutWindow(on: workspace, .cancellable, forceTile: true)
            }
        }

        _ = topLeftCornerToMonitorInfo[monitor.topLeftCorner]?
            .singleOrNil()?
            .setVisibleWorkspace(Workspace.get(byName: monitor.visibleWorkspace))
    }
}

@discardableResult
@MainActor
private func restoreTreeRecursive(frozenContainer: FrozenContainer, parent: NonLeafTreeNodeObject, index: Int, resolve: (FrozenWindow) -> Window?) -> Bool {
    let container = TilingContainer(
        parent: parent,
        adaptiveWeight: frozenContainer.weight,
        frozenContainer.orientation,
        frozenContainer.layout,
        index: index,
    )

    for (index, child) in frozenContainer.children.enumerated() {
        switch child {
            case .window(let w):
                // Stop the loop if can't find the window, because otherwise all the subsequent windows will have incorrect index
                guard let window = resolve(w) else { return false }
                window.bind(to: container, adaptiveWeight: w.weight, index: index)
            case .container(let c):
                // There is no reason to continue
                if !restoreTreeRecursive(frozenContainer: c, parent: container, index: index, resolve: resolve) { return false }
        }
    }
    return true
}

// Consider the following case:
// 1. Close window
// 2. The previous step lead to caching the whole world
// 3. Change something in the layout
// 4. Lock the screen
// 5. The cache won't be updated because all alive windows are already cached
// 6. Unlock the screen
// 7. The wrong cache is used
//
// That's why we have to reset the cache every time layout changes. The layout can only be changed by running commands
// and with mouse manipulations
@MainActor func resetClosedWindowsCache() {
    closedWindowsCache = FrozenWorld(monitors: [], windowIds: [])
    // The same signal - "the layout just changed" - is what the on-disk snapshot wants. (fork #71)
    scheduleLayoutPersist()
}

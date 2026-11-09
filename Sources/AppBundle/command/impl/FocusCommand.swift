import AppKit
import Common

struct FocusCommand: Command {
    let args: FocusCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        // todo bug: floating windows break mru
        // Only targets whose semantics depend on the tree need floating windows
        // temporarily bound into it: `.direction` navigates spatially, and the
        // dfs targets walk rootTilingContainer. `.windowId` resolves through
        // MacWindow.allWindowsMap and ignores the tree, so the preamble is pure
        // overhead there -- one synchronous ax call per floating window.
        var floatingAsTiling = args.floatingAsTiling
        if case .windowId = args.target { floatingAsTiling = false }
        let floatingWindows = floatingAsTiling ? try await makeFloatingWindowsSeenAsTiling(workspace: target.workspace) : []
        defer {
            if floatingAsTiling {
                restoreFloatingWindows(floatingWindows: floatingWindows, workspace: target.workspace)
            }
        }

        switch args.target {
            case .direction(let direction):
                let window = target.windowOrNil
                if let (parent, ownIndex) = window?.closestParent(hasChildrenInDirection: direction, withLayout: nil) {
                    guard let windowToFocus = parent.children[ownIndex + direction.focusOffset]
                        .findLeafWindowRecursive(snappedTo: direction.opposite) else { return .fail }
                    return .from(bool: windowToFocus.focusWindow())
                } else {
                    return hitWorkspaceBoundaries(target, io, args, direction)
                }
            case .windowId(let windowId):
                if let windowToFocus = Window.get(byId: windowId) {
                    return .from(bool: windowToFocus.focusWindow())
                } else {
                    return .fail(io.err("Can't find window with ID \(windowId)"))
                }
            case .dfsIndex(let dfsIndex):
                if let windowToFocus = target.workspace.rootTilingContainer.allLeafWindowsRecursive.getOrNil(atIndex: Int(dfsIndex)) {
                    return .from(bool: windowToFocus.focusWindow())
                } else {
                    return .fail(io.err("Can't find window with DFS index \(dfsIndex)"))
                }
            case .dfsRelative(let nextPrev):
                let windows = target.workspace.rootTilingContainer.allLeafWindowsRecursive
                guard let currentIndex = windows.firstIndex(where: { $0 == target.windowOrNil }) else {
                    return .fail(io.err("Can't find the focused window in the tiling tree of workspace '\(target.workspace.name)'"))
                }
                var targetIndex = switch nextPrev {
                    case .dfsNext: currentIndex + 1
                    case .dfsPrev: currentIndex - 1
                }
                if !(0 ..< windows.count).contains(targetIndex) {
                    switch args.boundariesAction {
                        case .stop: return .succ
                        case .fail: return .fail
                        case .wrapAroundTheWorkspace: targetIndex = (targetIndex + windows.count) % windows.count
                        case .wrapAroundAllMonitors: return dieT("Must be discarded by args parser")
                    }
                }
                return .from(bool: windows[targetIndex].focusWindow())
        }
    }
}

@MainActor private func hitWorkspaceBoundaries(
    _ target: LiveFocus,
    _ io: CmdIo,
    _ args: FocusCmdArgs,
    _ direction: CardinalDirection,
) -> BinaryExitCode {
    switch args.boundaries {
        case .workspace:
            return switch args.boundariesAction {
                case .stop: .succ
                case .fail: .fail
                case .wrapAroundTheWorkspace: wrapAroundTheWorkspace(target, io, direction)
                case .wrapAroundAllMonitors: dieT("Must be discarded by args parser")
            }
        case .allMonitorsOuterFrame:
            let currentMonitor = target.workspace.workspaceMonitor
            guard let (monitors, index) = currentMonitor.findRelativeMonitor(inDirection: direction) else {
                return .fail(io.err("Should never happen. Can't find the current monitor"))
            }

            if let targetMonitor = monitors.getOrNil(atIndex: index) {
                return .from(bool: targetMonitor.activeWorkspace.focusWorkspace())
            } else {
                guard let wrapped = monitors.get(wrappingIndex: index) else { return .fail }
                return hitAllMonitorsOuterFrameBoundaries(target, io, args, direction, wrapped)
            }
    }
}

@MainActor private func hitAllMonitorsOuterFrameBoundaries(
    _ target: LiveFocus,
    _ io: CmdIo,
    _ args: FocusCmdArgs,
    _ direction: CardinalDirection,
    _ wrappedMonitor: Monitor,
) -> BinaryExitCode {
    switch args.boundariesAction {
        case .stop:
            return .succ
        case .fail:
            return .fail
        case .wrapAroundTheWorkspace:
            return wrapAroundTheWorkspace(target, io, direction)
        case .wrapAroundAllMonitors:
            wrappedMonitor.activeWorkspace.findLeafWindowRecursive(snappedTo: direction.opposite)?.markAsMostRecentChild()
            return .from(bool: wrappedMonitor.activeWorkspace.focusWorkspace())
    }
}

@MainActor private func wrapAroundTheWorkspace(_ target: LiveFocus, _ io: CmdIo, _ direction: CardinalDirection) -> BinaryExitCode {
    guard let windowToFocus = target.workspace.findLeafWindowRecursive(snappedTo: direction.opposite) else {
        return .fail(io.err(noWindowIsFocused))
    }
    return .from(bool: windowToFocus.focusWindow())
}

@MainActor private func makeFloatingWindowsSeenAsTiling(workspace: Workspace) async throws -> [FloatingWindowData] {
    let mruBefore = workspace.mostRecentWindowRecursive
    defer {
        mruBefore?.markAsMostRecentChild()
    }
    var _floatingWindows: [FloatingWindowData] = []
    for window in workspace.floatingWindows {
        let center = try await window.getCenter() // todo bug: we shouldn't access ax api here. What if the window was moved but it wasn't committed to ax yet?
        guard let center else { continue }
        // getCenter is a suspension point. Another focus command could have unbound the window in the meantime
        // https://github.com/nikitabobko/AeroSpace/issues/1311
        guard window.parent === workspace else { continue }

        let tilingParent: TilingContainer
        let index: Int
        if let target = center.coerce(in: workspace.workspaceMonitor.visibleRectPaddedByOuterGaps)?
            .findIn(tree: workspace.rootTilingContainer, virtual: true)
        {
            guard let targetCenter = try await target.getCenter() else { continue }
            // getCenter is a suspension point. Another focus command could have unbound the window in the meantime
            // https://github.com/nikitabobko/AeroSpace/issues/1311
            guard window.parent === workspace else { continue }
            guard let _tilingParent = target.parent as? TilingContainer else { continue }
            tilingParent = _tilingParent
            index = switch tilingParent.layout {
                case .tiles:
                    center.getProjection(tilingParent.orientation) >= targetCenter.getProjection(tilingParent.orientation)
                        ? target.ownIndex.orDie() + 1
                        : target.ownIndex.orDie()
                case .accordion:
                    center.getProjection(tilingParent.orientation) >= targetCenter.getProjection(tilingParent.orientation)
                        ? tilingParent.children.count
                        : 0
            }
        } else {
            index = 0
            tilingParent = workspace.rootTilingContainer
        }

        _floatingWindows.append(FloatingWindowData(
            window: window,
            center: center,
            parent: tilingParent,
            index: index,
        ))
    }
    // Equal projections are possible (e.g. native macOS tiled windows). The order of such windows must not
    // depend on the previous tree state, otherwise `focus dfs-next` toggles between them instead of cycling
    let floatingWindows: [FloatingWindowData] = _floatingWindows
        .sorted {
            let lhsProjection = $0.center.getProjection($0.parent.orientation)
            let rhsProjection = $1.center.getProjection($1.parent.orientation)
            if lhsProjection != rhsProjection { return lhsProjection < rhsProjection }
            return $0.window.windowId < $1.window.windowId
        }
        .reversed()

    // Mutations must happen only after the last `await`, otherwise the tree could be observed
    // in an intermediate state by concurrent tasks (commands and model refreshes share MainActor)
    var boundFloatingWindows: [FloatingWindowData] = []
    for var floating in floatingWindows { // Make floating windows be seen as tiling
        // The window could be closed, re-detected, moved to another workspace, or temporarily made tiling by a
        // concurrent focus command during the reads above. Only windows that are still floating are taken
        guard floating.window.parent === workspace else { continue }
        // `parent` and `index` could become stale during the reads above (e.g. due to containers normalization)
        if floating.parent.nodeWorkspace != workspace {
            floating.parent = workspace.rootTilingContainer
            floating.index = 0
        }
        floating.index = min(max(floating.index, 0), floating.parent.children.count)
        // `bind` also unbinds the window from the workspace. The old binding data is used to restore
        // the original adaptive weight in `restoreFloatingWindows`
        floating.adaptiveWeight = floating.window.bind(to: floating.parent, adaptiveWeight: 1, index: floating.index)?.adaptiveWeight ?? WEIGHT_DOESNT_MATTER
        boundFloatingWindows.append(floating)
    }
    return boundFloatingWindows
}

@MainActor private func restoreFloatingWindows(floatingWindows: [FloatingWindowData], workspace: Workspace) {
    let mruBefore = workspace.mostRecentWindowRecursive
    defer {
        mruBefore?.markAsMostRecentChild()
    }
    for floating in floatingWindows {
        floating.window.bind(to: workspace, adaptiveWeight: floating.adaptiveWeight, index: INDEX_BIND_LAST)
    }
}

private struct FloatingWindowData {
    let window: Window
    let center: CGPoint

    var parent: TilingContainer
    var adaptiveWeight: CGFloat = WEIGHT_DOESNT_MATTER
    var index: Int
}

extension TreeNode {
    @MainActor
    func findLeafWindowRecursive(snappedTo direction: CardinalDirection) -> Window? {
        switch nodeCases {
            case .workspace(let workspace):
                return workspace.rootTilingContainer.findLeafWindowRecursive(snappedTo: direction)
            case .window(let window):
                return window
            case .tilingContainer(let container):
                if direction.orientation == container.orientation {
                    return (direction.isPositive ? container.children.last : container.children.first)?
                        .findLeafWindowRecursive(snappedTo: direction)
                } else {
                    return mostRecentChild?.findLeafWindowRecursive(snappedTo: direction)
                }
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
                die("Impossible")
        }
    }
}

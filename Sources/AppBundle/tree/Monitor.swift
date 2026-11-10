import AppKit
import Common

@MainActor private var pointToMonitor: [CGPoint: Monitor] = [:]

final class Monitor: TreeNode, NonLeafTreeNodeObject {
    fileprivate var _info: MonitorInfo
    var info: MonitorInfo { _info }

    @MainActor fileprivate init(_ info: MonitorInfo) {
        self._info = info
        super.init(parent: NilTreeNode.instance, adaptiveWeight: 0, index: 0)
    }

    override func getWeight(_ targetOrientation: Orientation) -> CGFloat {
        info.visibleRectPaddedByOuterGaps.getDimension(targetOrientation)
    }

    override func setWeight(_ targetOrientation: Orientation, _ newValue: CGFloat) {
        die("It's not possible to change weight of Monitor")
    }

    @MainActor static var all: [Monitor] { Array(pointToMonitor.values) }
}

@MainActor private func rearrangeMonitors() {
    let newMonitorInfos = globalUnsortedMonitorInfos
    // While all displays are momentarily off during display reconfiguration (e.g. opening the lid with external
    // monitors attached), `NSScreen.screens` is empty. There is nowhere to move the workspaces to, so keep the
    // current monitors until the next refresh sees a settled screen list. (fork 01e97d8b)
    if newMonitorInfos.isEmpty { return }
    // Remember where the focused workspace belongs before the monitors are rearranged (fork #89, upstream PR #2358)
    let focusedWorkspace = initializedFocusWorkspaceName.flatMap { Workspace.existing(byName: $0) }
    let focusedWorkspacePoint: CGPoint? = focusedWorkspace.flatMap {
        $0.forceAssignedMonitorInfo?.rect.topLeftCorner ?? $0.nodeMonitorInfo?.rect.topLeftCorner
    }
    defer {
        // The nearest-monitor mapping can leave the focused workspace invisible (e.g. when a monitor disconnects)
        if let focusedWorkspace, let focusedWorkspacePoint, !focusedWorkspace.isVisible,
           let target = pointToMonitor.values.minBy({ ($0.info.rect.topLeftCorner - focusedWorkspacePoint).vectorLength })
        {
            _ = target.getWorkspacesContainerOrCreate().setVisibleWorkspace(focusedWorkspace)
        }
    }
    var newMonitorPoints = newMonitorInfos.grouped(by: { $0.rect.topLeftCorner }).mapValues { $0.singleOrNil().orDie() }

    var oldPointToMonitor = pointToMonitor
    pointToMonitor = [:]

    var newPointToClosestOldPoint = [CGPoint: CGPoint]()
    var oldPointToClosestNewPoint = [CGPoint: CGPoint]()

    for point in newMonitorPoints.keys {
        newPointToClosestOldPoint[point] = oldPointToMonitor.keys.minBy { ($0 - point).vectorLength }
    }

    for point in oldPointToMonitor.keys {
        oldPointToClosestNewPoint[point] = newMonitorPoints.keys.minBy { ($0 - point).vectorLength }
    }

    for (newPoint, closestOldPoint) in newPointToClosestOldPoint {
        if oldPointToClosestNewPoint[closestOldPoint] == newPoint { // Closest points of each other
            pointToMonitor[newPoint] = oldPointToMonitor.removeValue(forKey: closestOldPoint)
            pointToMonitor[newPoint].orDie()._info = newMonitorPoints.removeValue(forKey: newPoint).orDie()
        }
    }

    var monitors = oldPointToMonitor.values.sortedBy { $0.info.rect.topLeftCorner.vectorLength } // [Monitor]
    let monitorInfos = newMonitorPoints.values.sortedBy { $0.rect.topLeftCorner.vectorLength } // [MonitorInfo]

    let mainMonitor = pointToMonitor[CGPoint(x: 0, y: 0)] ?? pointToMonitor.first?.value
    while monitors.count > monitorInfos.count, let mainMonitor {
        let monitor = monitors.removeLast()
        for child in monitor.children {
            switch child.nodeCases {
                case .floatingWindowsContainer,
                     .macosFullscreenWindowsContainer,
                     .macosHiddenAppsWindowsContainer,
                     .macosMinimizedWindowsContainer,
                     .macosPopupWindowsContainer,
                     .monitor,
                     .tilingContainer,
                     .window,
                     .workspace: illegalChildParentRelation(child: child, parent: monitor)
                case .workspacesContainer(let it):
                    for workspace in it.children {
                        workspace.bind(to: mainMonitor.getWorkspacesContainerOrCreate(), adaptiveWeight: 1, index: INDEX_BIND_LAST)
                    }
            }
        }
    }

    for j in monitors.indices {
        monitors[j]._info = monitorInfos.getOrNil(atIndex: j).orDie()
        pointToMonitor[monitors[j].info.rect.topLeftCorner] = monitors[j]
    }

    var i = monitors.count
    while let monitorInfo = monitorInfos.getOrNil(atIndex: i) {
        let monitor = Monitor(monitorInfo)
        monitors.append(monitor)
        pointToMonitor[monitor.info.rect.topLeftCorner] = monitor
        i += 1
    }
}

extension MonitorInfo {
    @MainActor var visibleWorkspace: Workspace { // todo revisit this API
        let monitor = toMonitorOrRearrangeMonitors()
        return monitor.getWorkspacesContainerOrCreate().getVisibleWorkspaceOrCreate(parent: monitor)
    }

    @MainActor func toMonitorOrRearrangeMonitors() -> Monitor {
        if let existing = pointToMonitor[rect.topLeftCorner] {
            return existing
        }
        rearrangeMonitors() // If monitor configuration changed
        if let existing = pointToMonitor[rect.topLeftCorner] {
            return existing
        }
        // `rearrangeMonitors` only knows the monitors that `NSScreen.screens` reports *right now*. If `self` isn't
        // one of them, retrying can never succeed, and recursing spun until the stack blew (EXC_BAD_ACCESS on the
        // stack guard). That happens for real during display reconfiguration: opening the lid with external monitors
        // attached hands callers a `MonitorInfo` snapshot that `NSScreen.screens` has already invalidated.
        // Fall back to the closest known monitor instead. The next refresh re-runs with a settled screen list.
        // (fork 01e97d8b; upstream issue #506)
        let point = rect.topLeftCorner
        if let closest = pointToMonitor.values.minBy({ ($0.info.rect.topLeftCorner - point).vectorLength }) {
            return closest
        }
        // No monitors known at all (all displays off before the first rearrangement): adopt this snapshot
        let monitor = Monitor(self)
        pointToMonitor[point] = monitor
        return monitor
    }

    @MainActor func setVisibleWorkspace(_ workspace: Workspace) -> Bool { // todo revisit this API (new name: setVisibleWorkspace)
        let container = toMonitorOrRearrangeMonitors().getWorkspacesContainerOrCreate()
        return container.setVisibleWorkspace(workspace)
    }

    @MainActor func bindWorkspace(_ workspace: Workspace) -> Bool {
        return toMonitorOrRearrangeMonitors().getWorkspacesContainerOrCreate().bindWorkspace(workspace)
    }
}

@MainActor func gcMonitors() {
    if pointToMonitor.count != globalUnsortedMonitorInfos.count {
        rearrangeMonitors()
    }
}

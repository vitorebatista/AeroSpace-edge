import AppKit
import Common

@MainActor private var workspaceNameToWorkspace: [String: Workspace] = [:]

final class Workspace: TreeNode, NonLeafTreeNodeObject, Hashable, Comparable {
    let name: String
    nonisolated private let nameLogicalSegments: StringLogicalSegments
    /// Per-workspace overrides for normalization flags. Empty by default; absent
    /// kinds fall through to the global config value. Lives as long as the
    /// workspace itself: `garbageCollectUnusedWorkspaces` destroys the override
    /// together with the workspace. Not persisted across restarts.
    var normalizationOverride: [NormalizationKind: Bool] = [:]

    @MainActor private init(_ name: String) {
        self.name = name
        self.nameLogicalSegments = name.toLogicalSegments()
        let container = mainMonitorInfo.toMonitorOrRearrangeMonitors().getWorkspacesContainerOrCreate()
        super.init(parent: container, adaptiveWeight: 0, index: 0)
        check(forceAssignedMonitorInfo?.toMonitorOrRearrangeMonitors().getWorkspacesContainerOrCreate().bindWorkspace(self) != false)
    }

    @MainActor static var all: [Workspace] {
        workspaceNameToWorkspace.values.sorted()
    }

    @MainActor static func get(byName name: String) -> Workspace {
        if let existing = workspaceNameToWorkspace[name] {
            return existing
        } else {
            let workspace = Workspace(name)
            workspaceNameToWorkspace[name] = workspace
            return workspace
        }
    }

    nonisolated static func < (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.nameLogicalSegments < rhs.nameLogicalSegments
    }

    override func getWeight(_ targetOrientation: Orientation) -> CGFloat {
        workspaceMonitorInfo.visibleRectPaddedByOuterGaps.getDimension(targetOrientation)
    }

    override func setWeight(_ targetOrientation: Orientation, _ newValue: CGFloat) {
        die("It's not possible to change weight of Workspace")
    }

    @MainActor
    var description: String {
        let description = [
            ("name", name),
            ("isVisible", String(isVisible)),
            ("isEffectivelyEmpty", String(isEffectivelyEmpty)),
            ("doKeepAlive", String(config.persistentWorkspaces.contains(name))),
        ].map { "\($0.0): \(String(describing: $0.1).singleQuoted)" }.joined(separator: ", ")
        return "Workspace(\(description))"
    }

    /// True when garbageCollectUnusedWorkspaces would destroy this workspace.
    @MainActor
    var isDoomedToGarbageCollection: Bool {
        !config.persistentWorkspaces.contains(name)
            && isEffectivelyEmpty
            && !isVisible
            && name != globalFocus.workspace.name
    }

    @MainActor static func forceAssignWorkspaces() {
        for wsName in config.workspaceToMonitorForceAssignment.keys {
            let ws = Workspace.get(byName: wsName)
            check(ws.forceAssignedMonitorInfo?.bindWorkspace(ws) != false)
        }
    }

    /// Looks a workspace up without creating it (creating one binds it to a monitor, which can rearrange monitors)
    @MainActor static func existing(byName name: String) -> Workspace? {
        workspaceNameToWorkspace[name]
    }

    @MainActor static func garbageCollectUnusedWorkspaces() {
        for name in config.persistentWorkspaces {
            _ = get(byName: name) // Make sure that all persistent workspaces are "cached"
        }
        let garbage = workspaceNameToWorkspace.values.filter { $0.isDoomedToGarbageCollection }
        for workspace in garbage {
            workspaceNameToWorkspace.removeValue(forKey: workspace.name)
            workspace.unbindFromParent()
        }
    }

    nonisolated static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        check((lhs === rhs) == (lhs.name == rhs.name), "lhs: \(lhs) rhs: \(rhs)")
        return lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

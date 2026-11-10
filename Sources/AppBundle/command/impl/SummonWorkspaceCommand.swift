import AppKit
import Common

struct SummonWorkspaceCommand: Command {
    let args: SummonWorkspaceCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        let workspace = Workspace.get(byName: args.target.val.raw)
        let focusedMonitor = globalFocus.workspace.workspaceMonitorInfo

        if focusedMonitor.visibleWorkspace == workspace {
            return switch args.failIfNoop {
                case true: .fail
                case false:
                    .succ(io.err("Workspace '\(workspace.name)' is already visible on the focused monitor. Tip: use --fail-if-noop to exit with non-zero code"))
            }
        }

        if !workspace.isVisible {
            // Then we just need to summon the workspace to the focused monitor.
            if focusedMonitor.setVisibleWorkspace(workspace) {
                return .from(bool: workspace.focusWorkspace())
            } else {
                return .fail(io.err("Can't move workspace '\(workspace.name)' to monitor '\(focusedMonitor.name)'. workspace-to-monitor-force-assignment doesn't allow it"))
            }
        } else {
            // The workspace is already visible on another monitor.
            let otherMonitor = workspace.workspaceMonitorInfo
            let currentWorkspace = focusedMonitor.visibleWorkspace

            switch args.whenVisible {
                case .swap:
                    if otherMonitor.setVisibleWorkspace(currentWorkspace) && focusedMonitor.setVisibleWorkspace(workspace) {
                        return .from(bool: workspace.focusWorkspace())
                    } else {
                        return .fail(io.err("Can't swap workspaces due to monitor force assignment restrictions"))
                    }
                case .focus:
                    return .from(bool: workspace.focusWorkspace())
            }
        }
    }
}

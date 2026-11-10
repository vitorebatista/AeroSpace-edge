import AppKit
import Common

struct ListWindowsCommand: Command {
    let args: ListWindowsCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        let focus = globalFocus
        var windows: [Window] = []

        if args.filteringFlags.focused {
            switch focus.windowOrNil {
                case let window?: windows = [window]
                case nil: return .fail(io.err(noWindowIsFocused))
            }
        } else {
            var workspaces: Set<Workspace> = args.filteringFlags.workspaces.isEmpty
                ? Workspace.all.toSet()
                : args.filteringFlags.workspaces
                    .flatMap { filter in
                        switch filter {
                            case .focused: [focus.workspace]
                            case .visible: Workspace.all.filter(\.isVisible)
                            case .name(let name): [Workspace.get(byName: name.raw)]
                        }
                    }
                    .toSet()
            if !args.filteringFlags.monitors.isEmpty {
                let monitors: Set<CGPoint> = args.filteringFlags.monitors.resolveMonitors(io)
                if monitors.isEmpty { return .fail }
                workspaces = workspaces.filter { monitors.contains($0.workspaceMonitorInfo.rect.topLeftCorner) }
            }
            windows = workspaces.flatMap(\.allInhabitedLeafWindowsRecursive)
            if let pid = args.filteringFlags.pidFilter {
                windows = windows.filter { $0.app.pid == pid }
            }
            if let appId = args.filteringFlags.appIdFilter {
                windows = windows.filter { $0.app.rawAppBundleId == appId }
            }
        }

        if args.outputOnlyCount {
            return .succ(io.out("\(windows.count)"))
        } else {
            var _list: [WindowWithPrefetchedTitle] = [] // todo cleanup
            for window in windows {
                guard let window = try? await WindowWithPrefetchedTitle.resolveWindow(window, for: args.format, .nonCancellable) else { return .fail(io.err(bugPrompt())) }
                _list.append(window)
            }
            _list = _list.filter { $0.window.isBound }
            _list = _list.sorted { Self.sortLess($0, $1, by: args.sort) }

            let list = _list.map { AeroObj.window($0) }
            if args.json {
                return switch list.formatToJson(args.format, ignoreRightPaddingVar: args._format.isEmpty) {
                    case .success(let json): .succ(io.out(json))
                    case .failure(let msg): .fail(io.err(msg))
                }
            } else {
                return switch list.format(args.format) {
                    case .success(let lines): .succ(io.out(lines))
                    case .failure(let msg): .fail(io.err(msg.map(\.description).joinErrors()))
                }
            }
        }
    }

    @MainActor
    static func sortLess(_ lhs: WindowWithPrefetchedTitle, _ rhs: WindowWithPrefetchedTitle, by sort: [SortOption]) -> Bool {
        for criterion in sort {
            switch criterion {
                case .recent:
                    // Sort by lastFocusedAt descending (most recent first)
                    if lhs.window.lastFocusedAt > rhs.window.lastFocusedAt { return true }
                    if lhs.window.lastFocusedAt < rhs.window.lastFocusedAt { return false }
                case .appName:
                    let lhsName = lhs.window.app.name ?? ""
                    let rhsName = rhs.window.app.name ?? ""
                    if lhsName < rhsName { return true }
                    if lhsName > rhsName { return false }
                case .windowTitle:
                    let lhsTitle = lhs.title ?? ""
                    let rhsTitle = rhs.title ?? ""
                    if lhsTitle < rhsTitle { return true }
                    if lhsTitle > rhsTitle { return false }
            }
        }
        return false
    }
}

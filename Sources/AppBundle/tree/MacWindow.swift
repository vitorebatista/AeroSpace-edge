import AppKit
import Common

final class MacWindow: Window {
    let macApp: MacApp
    private var prevUnhiddenProportionalPositionInsideWorkspaceRect: CGPoint?
    var isSticky: Bool = false // fork: `layout sticky` (floating windows that follow the visible workspace of their monitor)

    @MainActor private init(
        _ id: OpaqueWindowId,
        _ actor: MacApp,
        lastFloatingSize: CGSize?,
        parent: NonLeafTreeNodeObject,
        adaptiveWeight: CGFloat,
        index: Int,
    ) {
        self.macApp = actor
        super.init(id: id, actor, lastFloatingSize: lastFloatingSize, parent: parent, adaptiveWeight: adaptiveWeight, index: index)
    }

    @MainActor static var allWindowsMap: [OpaqueWindowId: MacWindow] = [:]
    @MainActor static var allWindows: [MacWindow] { Array(allWindowsMap.values) }

    /// The AX reads `getOrRegister` needs before it can bind a not-yet-known window into the tree.
    /// They touch nothing but the window itself, which is what lets `prefetchAxSnapshots` issue them
    /// for many windows concurrently ahead of the serial registration loop. (fork 62e757a1)
    struct AxSnapshot: Sendable {
        let rect: Rect?
        let windowType: AxUiElementWindowType
    }

    /// Read the per-window AX data for every window in `mapping` that isn't registered yet. One task
    /// per window, but the parallelism that matters is across apps: each MacApp serves its reads from
    /// its own AX thread, so the round-trips of different apps overlap instead of being serialized by
    /// the caller's `await`. (fork 62e757a1)
    @MainActor
    static func prefetchAxSnapshots(_ mapping: [MacApp: [OpaqueWindowId: WindowLifeStatus]]) async throws -> [OpaqueWindowId: AxSnapshot] {
        try await withThrowingTaskGroup(of: (OpaqueWindowId, AxSnapshot).self, returning: [OpaqueWindowId: AxSnapshot].self) { group in
            for (app, windowIds) in mapping {
                for windowId in windowIds.keys where allWindowsMap[windowId] == nil {
                    try checkCancellation()
                    group.addTask { @Sendable @MainActor in
                        let rect = try await app.getAxRect(windowId, .cancellable)
                        let windowLevel = try await app.getWindowLevel(windowId, .cancellable)
                        let windowType = try await app.getAxUiElementWindowType(windowId, windowLevel, .cancellable)
                        return (windowId, AxSnapshot(rect: rect, windowType: windowType))
                    }
                }
            }
            var result: [OpaqueWindowId: AxSnapshot] = [:]
            for try await (windowId, snapshot) in group {
                result[windowId] = snapshot
            }
            return result
        }
    }

    @MainActor
    @discardableResult
    static func getOrRegister(windowId: OpaqueWindowId, macApp: MacApp, snapshot: AxSnapshot? = nil) async throws -> MacWindow {
        if let existing = allWindowsMap[windowId] { return existing }
        let rect: Rect? = if let snapshot {
            snapshot.rect
        } else {
            try await macApp.getAxRect(windowId, .cancellable)
        }
        let data = try await unbindAndGetBindingDataForNewWindow(
            windowId,
            macApp,
            isStartup
                ? (rect?.center.monitorApproximation ?? mainMonitorInfo).visibleWorkspace
                : globalFocus.workspace,
            window: nil,
            .cancellable,
            windowType: snapshot?.windowType,
        )

        // atomic synchronous section
        if let existing = allWindowsMap[windowId] { return existing }
        let window = MacWindow(windowId, macApp, lastFloatingSize: rect?.size, parent: data.parent, adaptiveWeight: data.adaptiveWeight, index: data.index)
        window.isAwaitingOnWindowDetected = true
        allWindowsMap[windowId] = window

        try await debugWindowsIfRecording(window, .cancellable)
        defer { window.isAwaitingOnWindowDetected = false }
        if try await !restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: window) {
            await runOnWindowDetected(ifConventional: window)
        }
        window.preventNewWindowFlickerIfNeeded()
        return window
    }

    // Move a freshly detected tiling window offscreen the instant it's registered, *before* macOS paints
    // it at its native spawn position (usually screen center). The subsequent layoutWorkspaces() in the same
    // refresh session unhides it straight into its final tiled slot, so the user never sees the center flash.
    // Opt-in via `new-window-prevent-flicker` because moving windows via the AX API is app-dependent.
    @MainActor
    func preventNewWindowFlickerIfNeeded() {
        guard config.newWindowPreventFlicker else { return }
        guard !isStartup else { return } // On startup everything is laid out at once; no per-window flash to hide
        guard let nodeMonitorInfo, let workspace = nodeWorkspace, workspace.isVisible else { return }
        // Only tiling windows flash at a wrong spot; floating windows keep their native position on purpose.
        guard parent is TilingContainer else { return }
        if isHiddenInCorner { return }
        // Stash a sentinel so layoutWorkspaces()'s unhideFromCorner() treats this as a hidden tiling window
        // (the value itself is unused for tiling windows - they're repositioned by layoutRecursive).
        prevUnhiddenProportionalPositionInsideWorkspaceRect = .zero
        // Single non-blocking AX move to the bottom-right corner, mirroring hideInCorner's offscreen target.
        let s = lastFloatingSize ?? .zero
        let corner = nodeMonitorInfo.visibleRect.bottomRightCorner + CGPoint(x: 1, y: 1) - CGPoint(x: s.width, y: 0)
        setAxFrame(corner, nil)
    }

    // var description: String {
    //     let description = [
    //         ("title", title),
    //         ("role", axWindow.get(Ax.roleAttr)),
    //         ("subrole", axWindow.get(Ax.subroleAttr)),
    //         ("identifier", axWindow.get(Ax.identifierAttr)),
    //         ("modal", axWindow.get(Ax.modalAttr).map { String($0) } ?? ""),
    //         ("windowId", String(windowId)),
    //     ].map { "\($0.0): '\(String(describing: $0.1))'" }.joined(separator: ", ")
    //     return "Window(\(description))"
    // }

    func isWindowHeuristic(_ windowLevel: MacOsWindowLevel?, _ cm: CancellationMode) async throws -> Bool { // todo cache
        try await macApp.isWindowHeuristic(windowId, windowLevel, cm)
    }

    func isDialogHeuristic(_ windowLevel: MacOsWindowLevel?, _ cm: CancellationMode) async throws -> Bool { // todo cache
        try await macApp.isDialogHeuristic(windowId, windowLevel, cm)
    }

    func dumpAxInfo(_ cm: CancellationMode) async throws -> [String: Json] {
        try await macApp.dumpWindowAxInfo(windowId: windowId, cm)
    }

    @MainActor func getWindowLevel(_ cm: CancellationMode) async throws -> MacOsWindowLevel? {
        try await macApp.getWindowLevel(windowId, cm)
    }

    func setNativeFullscreen(_ value: Bool) {
        macApp.setNativeFullscreen(windowId, value)
    }

    func setNativeMinimized(_ value: Bool) {
        macApp.setNativeMinimized(windowId, value)
    }

    // skipClosedWindowsCache is an optimization when it's definitely not necessary to cache closed window.
    //                        If you are unsure, it's better to pass `false`
    @MainActor
    func garbageCollect(skipClosedWindowsCache: Bool) {
        if MacWindow.allWindowsMap.removeValue(forKey: windowId) == nil {
            return
        }
        if !skipClosedWindowsCache { cacheClosedWindowIfNeeded() }
        let parent = unbindFromParent().parent
        let deadWindowWorkspace = parent.nodeWorkspace
        broadcastEvent(.windowClosed(windowId: windowId, workspace: deadWindowWorkspace?.name))
        let focus = globalFocus
        if let deadWindowWorkspace, deadWindowWorkspace == focus.workspace ||
            deadWindowWorkspace == prevFocusedWorkspace && prevFocusedWorkspaceDate.distance(to: .now) < 1
        {
            protectFocusAfterWindowClose(workspaceName: deadWindowWorkspace.name)
            switch parent.cases {
                case .tilingContainer, .floatingWindowsContainer, .macosHiddenAppsWindowsContainer, .macosFullscreenWindowsContainer:
                    let deadWindowFocus = deadWindowWorkspace.toLiveFocus()
                    _ = setFocus(to: deadWindowFocus)
                    // Guard against "Apple Reminders popup" bug: https://github.com/nikitabobko/AeroSpace/issues/201
                    if focus.windowOrNil?.app.pid != app.pid {
                        // Force focus to fix macOS annoyance with focused apps without windows.
                        //   https://github.com/nikitabobko/AeroSpace/issues/65
                        deadWindowFocus.windowOrNil?.nativeFocus()
                    }
                case .macosPopupWindowsContainer, // Don't switch back on popup destruction
                     .workspace, // Workspace is invalid parent for windows
                     .monitor, // Monitor is invalid parent for windows
                     .workspacesContainer, // WorkspacesContainer is invalid parent for windows
                     .macosMinimizedWindowsContainer: // Don't switch back on minimized windows destruction
                    break
            }
        }
    }

    override func getTitle(_ cm: CancellationMode) async throws -> String { try await macApp.getAxTitle(windowId, cm) ?? "" }

    override func isMacosFullscreen(_ cm: CancellationMode) async throws -> Bool { try await macApp.isMacosNativeFullscreen(windowId, cm) == true }
    override func isMacosMinimized(_ cm: CancellationMode) async throws -> Bool { try await macApp.isMacosNativeMinimized(windowId, cm) == true }
    override func getMacosWindowNativeState(_ cm: CancellationMode) async throws -> MacosWindowNativeState {
        try await macApp.getMacosWindowNativeState(windowId, cm) ?? .normal
    }

    @MainActor override func nativeFocus() {
        macApp.nativeFocus(windowId)
    }

    override func closeAxWindow() {
        garbageCollect(skipClosedWindowsCache: true)
        macApp.closeAndUnregisterAxWindow(windowId)
    }

    /// Save the current window position so it can be restored later by unhideFromCorner. (fork fd172393)
    /// Returns false when current AX/screen state is unsafe, so caller must not move the window to a hide corner.
    @MainActor
    @discardableResult
    func saveFloatingPositionIfNeeded() async throws -> Bool {
        guard !isHiddenInCorner else { return true }
        guard !screenSleepWakeInProgress else { return false }
        guard let workspace = nodeWorkspace, let parent else { return false }
        // Tiling windows are put back by layoutRecursive, and unhideFromCorner throws their saved
        // position away unread. Skip the blocking AX rect round-trip and store only the sentinel that
        // marks the window as hidden - the same trick preventNewWindowFlickerIfNeeded uses. That's one
        // saved round-trip per tiled window on every non-visible workspace, at startup and on every
        // workspace switch. (fork 62e757a1)
        if case .tiling = getChildParentRelation(child: self, parent: parent) {
            prevUnhiddenProportionalPositionInsideWorkspaceRect = .zero
            return true
        }
        let workspaceRect = workspace.workspaceMonitorInfo.rect
        let visibleRect = workspace.workspaceMonitorInfo.visibleRect
        guard let windowRect = try await getAxRect(.cancellable) else { return false }
        // Check again after the suspension point above. Another hideInCorner/unhideFromCorner
        // cycle may have already saved the correct position while this AX read was awaiting.
        guard !screenSleepWakeInProgress else { return false }
        guard !isHiddenInCorner else { return true }
        guard let snapshot = floatingPositionSnapshot(
            windowRect: windowRect,
            workspaceRect: workspaceRect,
            visibleRect: visibleRect,
        ) else { return false }
        prevUnhiddenProportionalPositionInsideWorkspaceRect = snapshot
        // Refresh lastFloatingSize from the live AX rect (already fetched above). Otherwise
        // unhideFromCorner clamps the restored position against a stale size written only at
        // detection / 'layout floating', nudging user-resized floating windows off the
        // right/bottom edges. Guarded by isFloating so a corner-parked tiled window can't pollute
        // the size that 'layout floating' restores. (upstream 649301b2)
        if isFloating {
            lastFloatingSize = windowRect.size
        }
        return true
    }

    private func floatingPositionSnapshot(windowRect: Rect, workspaceRect: Rect, visibleRect: Rect) -> CGPoint? {
        if workspaceRect.width <= 0 || workspaceRect.height <= 0 { return nil }

        let topLeftCorner = windowRect.topLeftCorner
        let absolutePoint = topLeftCorner - workspaceRect.topLeftCorner
        let snapshot = CGPoint(x: absolutePoint.x / workspaceRect.width, y: absolutePoint.y / workspaceRect.height)

        // Reject positions that look like AeroSpace hide corners.
        // Hide corners place window's top-left at visible monitor bottom edge, sometimes outside X bounds.
        // This protects against saving wrong positions after macOS wake from sleep.
        let tolerance: CGFloat = 5
        let isNearBottomEdge = topLeftCorner.y >= visibleRect.maxY - tolerance
        let isNearRightHideCorner = topLeftCorner.x >= visibleRect.maxX - tolerance
        let isNearLeftHideCorner = topLeftCorner.x + windowRect.width <= visibleRect.minX + tolerance
        let looksLikeHideCorner = isNearBottomEdge && (isNearLeftHideCorner || isNearRightHideCorner)
        return looksLikeHideCorner ? nil : snapshot
    }

    // todo it's part of the window layout and should be moved to layoutRecursive.swift
    @MainActor
    func hideInCorner(_ corner: OptimalHideCorner) async throws {
        guard !screenSleepWakeInProgress else { return }
        guard let nodeMonitorInfo else { return }
        // Don't move a floating window to a hide corner unless we know how to restore it.
        guard try await saveFloatingPositionIfNeeded() else { return }
        guard !screenSleepWakeInProgress else { return }
        let p: CGPoint
        switch corner {
            case .bottomLeftCorner:
                guard let s = try await getAxSize(.cancellable) else { fallthrough }
                // Zoom will jump off if you do one pixel offset https://github.com/nikitabobko/AeroSpace/issues/527
                // todo this ad hoc won't be necessary once I implement optimization suggested by Zalim
                let onePixelOffset = macApp.appId == .zoom ? .zero : CGPoint(x: 1, y: -1)
                p = nodeMonitorInfo.visibleRect.bottomLeftCorner + onePixelOffset + CGPoint(x: -s.width, y: 0)
            case .bottomRightCorner:
                // Zoom will jump off if you do one pixel offset https://github.com/nikitabobko/AeroSpace/issues/527
                // todo this ad hoc won't be necessary once I implement optimization suggested by Zalim
                let onePixelOffset = macApp.appId == .zoom ? .zero : CGPoint(x: 1, y: 1)
                p = nodeMonitorInfo.visibleRect.bottomRightCorner - onePixelOffset
        }
        // The window is being moved away from whatever layoutRecursive last applied to it, so that record is now
        // stale. Without invalidating it, layoutRecursive's redundant-write skip would wrongly think the window
        // is still at its correct tiled position on the next relayout (since the computed target rect is
        // unchanged) and skip re-applying it, leaving tiling windows stuck hidden in the corner. (fork #90)
        lastAppliedLayoutPhysicalRect = nil
        setAxFrame(p, nil)
    }

    @MainActor
    func unhideFromCorner() {
        guard let prevUnhiddenProportionalPositionInsideWorkspaceRect else { return }
        guard let nodeWorkspace else { return } // hiding only makes sense for workspace windows
        guard let parent else { return }

        switch getChildParentRelation(child: self, parent: parent) {
            // Just a small optimization to avoid unnecessary AX calls for non floating windows
            // Tiling windows should be unhidden with layoutRecursive anyway
            case .floatingWindow:
                let workspaceRect = nodeWorkspace.workspaceMonitorInfo.rect
                var newX = workspaceRect.topLeftX + workspaceRect.width * prevUnhiddenProportionalPositionInsideWorkspaceRect.x
                var newY = workspaceRect.topLeftY + workspaceRect.height * prevUnhiddenProportionalPositionInsideWorkspaceRect.y
                // todo we probably should replace lastFloatingSize with proper floating window sizing
                // https://github.com/nikitabobko/AeroSpace/issues/1519
                let windowWidth = lastFloatingSize?.width ?? 0
                let windowHeight = lastFloatingSize?.height ?? 0
                newX = newX.coerce(in: workspaceRect.minX ... max(workspaceRect.minX, workspaceRect.maxX - windowWidth))
                newY = newY.coerce(in: workspaceRect.minY ... max(workspaceRect.minY, workspaceRect.maxY - windowHeight))

                setAxFrame(CGPoint(x: newX, y: newY), nil)
                self.prevUnhiddenProportionalPositionInsideWorkspaceRect = nil
            case .tiling, .rootTilingContainer:
                // Tiling windows are positioned by layoutRecursive, safe to clear.
                self.prevUnhiddenProportionalPositionInsideWorkspaceRect = nil
            case .macosNativeFullscreenWindow, .macosNativeHiddenAppWindow, .macosNativeMinimizedWindow,
                 .macosPopupWindow, .shimContainerRelation:
                // Preserve saved position - window is in a temporary macOS state and will
                // need the position when it returns to floating. (fork fd172393)
                break
        }
    }

    override var isHiddenInCorner: Bool {
        prevUnhiddenProportionalPositionInsideWorkspaceRect != nil
    }

    override func getAxSize(_ cm: CancellationMode) async throws -> CGSize? {
        try await macApp.getAxSize(windowId, cm)
    }

    override func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) {
        macApp.setAxFrame(windowId, topLeft, size)
    }

    override func getAxRect(_ cm: CancellationMode) async throws -> Rect? {
        try await macApp.getAxRect(windowId, cm)
    }
}

extension Window {
    @MainActor
    func relayoutWindow(on workspace: Workspace, _ cm: CancellationMode, forceTile: Bool = false) async throws {
        let data = forceTile
            ? unbindAndGetBindingDataForNewTilingWindow(workspace, window: self)
            : try await unbindAndGetBindingDataForNewWindow(self.asMacWindow().windowId, self.asMacWindow().macApp, workspace, window: self, cm)
        bind(to: data.parent, adaptiveWeight: data.adaptiveWeight, index: data.index)
    }
}

// The function is private because it's unsafe. It leaves the window in unbound state
@MainActor
private func unbindAndGetBindingDataForNewWindow(
    _ windowId: OpaqueWindowId,
    _ macApp: MacApp,
    _ workspace: Workspace,
    window: Window?,
    _ cm: CancellationMode,
    windowType: AxUiElementWindowType? = nil,
) async throws -> BindingData {
    let resolvedWindowType: AxUiElementWindowType = if let windowType {
        windowType // Already read by MacWindow.prefetchAxSnapshots
    } else {
        try await macApp.getAxUiElementWindowType(windowId, macApp.getWindowLevel(windowId, cm), cm)
    }
    return switch resolvedWindowType {
        case .popup: BindingData(parent: macosPopupWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        case .dialog: BindingData(parent: workspace.floatingWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        case .window: unbindAndGetBindingDataForNewTilingWindow(workspace, window: window)
    }
}

// The function is private because it's unsafe. It leaves the window in unbound state
@MainActor
private func unbindAndGetBindingDataForNewTilingWindow(_ workspace: Workspace, window: Window?) -> BindingData {
    window?.unbindFromParent() // It's important to unbind to get correct data from below
    if let (tilingParent, index) = workspace.mostRecentWindowRecursive?.nearestAliveTilingParent() {
        return BindingData(parent: tilingParent, adaptiveWeight: WEIGHT_AUTO, index: index + 1)
    } else {
        return BindingData(
            parent: workspace.rootTilingContainer,
            adaptiveWeight: WEIGHT_AUTO,
            index: INDEX_BIND_LAST,
        )
    }
}

@MainActor
func runOnWindowDetected(ifConventional window: Window) async {
    switch window.windowParentCases {
        case .tilingContainer, .floatingWindowsContainer, .macosMinimizedWindowsContainer,
             .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer:
            let layout = global_layoutForNextDetectedWindow
            global_layoutForNextDetectedWindow = nil
            defer {
                if let layout {
                    await LayoutCommand(args: LayoutCmdArgs(rawArgs: [], toggleBetween: [layout]))
                        .run(.defaultEnv.withWindowId(window.windowId), .emptyStdin)
                }
            }
            if let layout {
                await LayoutCommand(args: LayoutCmdArgs(rawArgs: [], toggleBetween: [layout]))
                    .run(.defaultEnv.withWindowId(window.windowId), .emptyStdin)
            }
            _ = await onWindowDetected(.defaultEnv, CmdIoImpl.emptyStdinIgnoringOut, window)
        case .macosPopupWindowsContainer, nil:
            break
    }
}

@MainActor
func onWindowDetected(_ env: CmdEnv, _ io: CmdIo, _ window: Window) async -> Int32ExitCode {
    broadcastEvent(.windowDetected(
        windowId: window.windowId,
        workspace: window.nodeWorkspace?.name,
        appBundleId: window.app.rawAppBundleId,
        appName: window.app.name,
    ))
    var lastExitCode = Int32ExitCode.succ
    for callback in config.onWindowDetected where await callback.matches(window) {
        lastExitCode = await callback.run.run(env.withWindowId(window.windowId), io)
        if !callback.checkFurtherCallbacks {
            return lastExitCode
        }
    }
    return lastExitCode
}

extension WindowDetectedCallback {
    @MainActor
    func matches(_ window: Window) async -> Bool {
        switch self.matcher {
            case .legacy(let matcher):
                if let startupMatcher = matcher.duringAeroSpaceStartup, startupMatcher != isStartup {
                    return false
                }
                if let regex = matcher.windowTitleRegexSubstring, (try? await window.getTitle(.nonCancellable))?.contains(caseInsensitiveRegex: regex) != true {
                    return false
                }
                if let appIds = matcher.appIds, !appIds.contains(window.app.rawAppBundleId ?? "") {
                    return false
                }
                if let regex = matcher.appIdRegexSubstring, !(window.app.rawAppBundleId ?? "").contains(caseInsensitiveRegex: regex) {
                    return false
                }
                if let regex = matcher.appNameRegexSubstring, !(window.app.name ?? "").contains(caseInsensitiveRegex: regex) {
                    return false
                }
                if let workspace = matcher.workspace, workspace != window.nodeWorkspace?.name {
                    return false
                }
                return true
            case .command(let command):
                return await command.run(.defaultEnv.withWindowId(window.windowId), .emptyStdin).exitCode.rawValue == 0
        }
    }
}

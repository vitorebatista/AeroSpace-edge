import AppKit
import Common

// Potential alternative implementation
// https://github.com/swiftlang/swift-evolution/blob/main/proposals/0392-custom-actor-executors.md
// (only available since macOS 14)
final class MacApp: AbstractApp {
    /*conforms*/ let pid: Int32
    /*conforms*/ let rawAppBundleId: String?
    let appId: KnownBundleId?
    let nsApp: NSRunningApplication
    private let axApp: ThreadGuardedValue<AXUIElement>
    private let appAxSubscriptions: ThreadGuardedValue<[AxSubscription]> // keep subscriptions in memory
    private let windows: ThreadGuardedValue<[UInt32: AxWindow]> = .init([:])
    private var windowsCount = 0
    var lastNativeFocusedWindowId: UInt32? = nil
    private var thread: Thread?
    private var setFrameJobs: [UInt32: RunLoopJob] = [:]
    @MainActor private static var focusJob: RunLoopJob? = nil

    /*conforms*/ var name: String? { nsApp.localizedName }
    /*conforms*/ var execPath: String? { nsApp.executableURL?.path }
    /*conforms*/ var bundlePath: String? { nsApp.bundleURL?.path }

    // todo think if it's possible to integrate this global mutable state to https://github.com/nikitabobko/AeroSpace/issues/1215
    //      and make deinitialization automatic in deinit
    @MainActor static var allAppsMap: [pid_t: MacApp] = [:]
    @MainActor private static var wipPids: [pid_t: AwaitableOneTimeBroadcastLatch] = [:]
    @MainActor static var failedRegistrationRetryAfter: [pid_t: Date] = [:]
    static let failedRegistrationRetryDelay: TimeInterval = 5

    /// Decides whether a failed-registration retry for `pid` should be throttled (skipped).
    /// If a throttle deadline is set and still in the future, returns `true` (skip).
    /// If the deadline has passed, it is cleared and `false` is returned (proceed).
    /// `now` is injectable to keep this pure and testable.
    @MainActor static func shouldThrottleFailedRegistration(_ pid: pid_t, now: Date = Date()) -> Bool {
        if let retryAfter = failedRegistrationRetryAfter[pid] {
            if retryAfter > now { return true }
            failedRegistrationRetryAfter[pid] = nil
        }
        return false
    }

    /// Records a failed registration for `pid`, throttling retries until `now + failedRegistrationRetryDelay`.
    @MainActor static func recordFailedRegistration(_ pid: pid_t, now: Date = Date()) {
        failedRegistrationRetryAfter[pid] = now.addingTimeInterval(failedRegistrationRetryDelay)
    }

    /// Clears any throttle state for `pid` (called on successful registration and on destroy).
    @MainActor static func clearFailedRegistration(_ pid: pid_t) {
        failedRegistrationRetryAfter[pid] = nil
    }

    private init(_ nsApp: NSRunningApplication, _ pid: pid_t, _ axApp: AXUIElement, _ axSubscriptions: [AxSubscription], _ thread: Thread) {
        self.nsApp = nsApp
        self.axApp = .init(axApp)
        self.pid = pid
        self.rawAppBundleId = nsApp.bundleIdentifier
        self.appId = nsApp.bundleIdentifier.flatMap { KnownBundleId.init(rawValue: $0) }
        assert(!axSubscriptions.isEmpty)
        self.appAxSubscriptions = .init(axSubscriptions)
        self.thread = thread
    }

    @MainActor
    @discardableResult
    static func getOrRegister(_ nsApp: NSRunningApplication) async throws -> MacApp? {
        // Don't perceive any of the lock screen windows as real windows
        // Otherwise, false positive ax notifications might trigger that lead to gcWindows
        if nsApp.bundleIdentifier == lockScreenAppBundleId { return nil }
        guard let pid = resolveRealPid(nsApp) else { return nil }
        // AX requests crash if you send them to yourself
        if pid == myPid { return nil }

        while true {
            if let existing = allAppsMap[pid] { return existing }
            if shouldThrottleFailedRegistration(pid) { return nil }
            try checkCancellation()
            if let wip = wipPids[pid] {
                try await wip.await()
                continue
            }
            let wip = AwaitableOneTimeBroadcastLatch()
            wipPids[pid] = wip

            let thread = Thread {
                $axTaskLocalAppThreadToken.withValue(AxAppThreadToken(pid: pid, idForDebug: nsApp.idForDebug)) {
                    let axApp = AXUIElementCreateApplication(pid)
                    // Every AX read is a synchronous IPC round-trip into the target app. Without an
                    // explicit timeout, one wedged app (Electron mid-freeze, a JetBrains IDE indexing)
                    // stalls the whole refresh and the WM appears hung. Cap the wait instead: a slow
                    // app loses one refresh cycle, everything else keeps tiling.
                    // Tuning knob: too low and genuinely slow apps (e.g. Godot) get their windows
                    // dropped from a refresh; too high and a hang is user-visible.
                    AXUIElementSetMessagingTimeout(axApp, axMessagingTimeoutSeconds)
                    let handlers: HandlerToNotifKeyMapping = unsafe [
                        (refreshObs, [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification]),
                    ]
                    let job = RunLoopJob()
                    let subscriptions = (try? unsafe AxSubscription.bulkSubscribe(pid, axApp, job, handlers)) ?? []
                    let isGood = !subscriptions.isEmpty
                    let app = isGood ? MacApp(nsApp, pid, axApp, subscriptions, Thread.current) : nil

                    let appAxSubscriptionsThreadGuarded = app?.appAxSubscriptions
                    let windowsThreadGuarded = app?.windows
                    let axAppThreadGuarded = app?.axApp

                    Task { @MainActor in
                        if let app {
                            allAppsMap[pid] = app
                            clearFailedRegistration(pid)
                        } else {
                            recordFailedRegistration(pid)
                        }
                        // Clear wipPids before signaling the latch: otherwise a woken awaiter can see the
                        // still-present (now-signaled) latch, re-await it (returns instantly), loop, and spin
                        // on @MainActor until this task gets scheduled to clear the entry.
                        wipPids[pid] = nil
                        await wip.signalToAll()
                    }
                    if isGood {
                        CFRunLoopRun()

                        // Destroy AX objects in reverse order of their creation, on the AX thread, after the
                        // run loop has fully stopped. Destroying them in a separate close-time job raced with
                        // the asynchronous CFRunLoopStop and could hit 'Value is already destroyed'.
                        appAxSubscriptionsThreadGuarded?.destroy()
                        windowsThreadGuarded?.destroy()
                        axAppThreadGuarded?.destroy()
                    }
                }
            }
            thread.name = "AxAppThread \(nsApp.idForDebug)"
            thread.start()
        }
    }

    func closeAndUnregisterAxWindow(_ windowId: UInt32) {
        if serverArgs.isReadOnly { return }
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        _ = withWindowAsync(windowId) { [windows] window, job in
            guard let closeButton = window.get(Ax.closeButtonAttr) else { return }
            if AXUIElementPerformAction(closeButton.cast, kAXPressAction as CFString) == .success {
                guard windows.threadGuardedOrNil != nil else { return }
                windows.threadGuarded.removeValue(forKey: windowId)
            }
        }
    }

    func getAxSize(_ windowId: UInt32) async throws -> CGSize? {
        try await withWindow(windowId) { window, job in
            window.get(Ax.sizeAttr)
        }
    }

    // todo merge together with detectNewWindows
    func getFocusedWindow() async throws -> Window? {
        // Read on this (the caller's) actor, before hopping to the dedicated AX thread below,
        // mirroring how lastNativeFocusedWindowId is written in updateFocusCache.
        let previousFocusedWindowId = lastNativeFocusedWindowId
        let focused = try await thread?.runInLoop { [pid, axApp, windows, previousFocusedWindowId] (job) -> (UInt32, UInt32?)? in
            guard let axApp = axApp.threadGuardedOrNil else { return nil }
            guard windows.threadGuardedOrNil != nil else { return nil }
            guard let axFocusedWindow = axApp.get(Ax.focusedWindowAttr),
                  let focusedWindow = try windows.threadGuarded.getOrRegisterAxWindow(
                      windowId: axFocusedWindow.windowId,
                      axFocusedWindow.ax.cast,
                      pid,
                      job,
                  )
            else {
                return nil
            }
            guard let previousFocusedWindowId,
                  previousFocusedWindowId != focusedWindow.windowId,
                  !isLeftMouseButtonDown, // Mirrors the new-window-detection safeguard for tab-drag-out gestures below
                  windows.threadGuarded[previousFocusedWindowId] != nil
            else {
                return (focusedWindow.windowId, nil)
            }
            // Apps that fold native tabs into one titlebar (Finder, Ghostty, Fork) keep the old
            // tab's AX object alive after switching away from it, but drop it from AXWindows.
            // Scoped to the just-focused-a-moment-ago window only, since that one is guaranteed
            // to have been on the active Space - a blanket AXWindows/tracked-set intersection
            // would not be (see windowsAttr's doc comment).
            guard isMissingFromLiveAxWindows(previousFocusedWindowId, in: readAxWindows(axApp)) else {
                return (focusedWindow.windowId, nil)
            }
            windows.threadGuarded.removeValue(forKey: previousFocusedWindowId)
            return (focusedWindow.windowId, previousFocusedWindowId)
        }
        // `thread` is Optional, so `focused` is a double optional and the `?? nil` flattens it —
        // it is not redundant. swiftlint's autocorrect also drops the space, producing `focusedelse`.
        // swiftlint:disable:next redundant_nil_coalescing
        guard let (windowId, staleWindowId) = focused ?? nil else { return nil }
        if let staleWindowId {
            setFrameJobs.removeValue(forKey: staleWindowId)?.cancel()
        }
        return try await MacWindow.getOrRegister(windowId: windowId, macApp: self, replacingNativeTabWindowId: staleWindowId)
    }

    @MainActor func nativeFocus(_ windowId: UInt32) {
        if serverArgs.isReadOnly { return }
        MacApp.focusJob?.cancel()
        // Performance optimization. If possible avoid doing AX requests
        // (important for apps which are slow at responding even such basic AX requests. E.g. Godot)
        // Beware of the macOS bug: https://github.com/nikitabobko/AeroSpace/issues/101
        if (!NSScreen.screensHaveSeparateSpaces || monitors.count == 1) &&
            (lastNativeFocusedWindowId == windowId || windowsCount == 1)
        {
            nativeActivate(nsApp)
        } else {
            MacApp.focusJob = withWindowAsync(windowId) { [nsApp] window, job in
                // Raise firstly to make sure that by the time we activate the app, the window would be already on top
                try performNativeFocus(
                    job: job,
                    setMain: { window.set(Ax.isMainAttr, true) },
                    raise: { AXUIElementPerformAction(window, kAXRaiseAction as CFString) },
                    activate: { nativeActivate(nsApp) },
                )
            }
        }
    }

    func setAxFrame(_ windowId: UInt32, _ topLeft: CGPoint?, _ size: CGSize?) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = withWindowAsync(windowId) { [axApp] window, job in
            guard let axApp = axApp.threadGuardedOrNil else { return }
            try disableAnimations(app: axApp, job) {
                try setFrame(window, topLeft, size, job)
            }
            // Nudge the window size by 1px and back after AXEnhancedUserInterface is
            // restored.  Some toolkits (e.g. GTK3's Quartz backend) don't redraw after
            // AX-driven frame changes made while AXEnhancedUserInterface is disabled,
            // leaving windows visually stale.  A no-op re-set of the same size is
            // optimized away by macOS, so a real geometry change is needed to trigger
            // the resize notification that prompts the app to redraw.
            try job.checkCancellation()
            if let size {
                window.set(Ax.sizeAttr, CGSize(width: size.width + 1, height: size.height))
                window.set(Ax.sizeAttr, size)
            }
        }
    }

    func setAxFrameForTermination(_ windowId: UInt32, _ topLeft: CGPoint?, _ size: CGSize?) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        let semaphore = DispatchSemaphore(value: 0)
        let job = withWindowAsync(windowId) { [axApp] window, job in
            if let axApp = axApp.threadGuardedOrNil {
                try? disableAnimations(app: axApp, job) {
                    try setFrame(window, topLeft, size, job)
                }
                // Nudge the window size by 1px and back after AXEnhancedUserInterface is
                // restored.  Some toolkits (e.g. GTK3's Quartz backend) don't redraw after
                // AX-driven frame changes made while AXEnhancedUserInterface is disabled,
                // leaving windows visually stale.  A no-op re-set of the same size is
                // optimized away by macOS, so a real geometry change is needed to trigger
                // the resize notification that prompts the app to redraw.
                if !job.isCancelled, let size {
                    window.set(Ax.sizeAttr, CGSize(width: size.width + 1, height: size.height))
                    window.set(Ax.sizeAttr, size)
                }
            }
            semaphore.signal()
        }
        switch job.isCancelled {
            case true: return
            case false: semaphore.wait()
        }
    }

    func getAxWindowsCount() async throws -> Int? {
        try await thread?.runInLoop { [axApp] job in
            axApp.threadGuardedOrNil?.get(Ax.windowsAttr)?.count
        }
    }

    func getAxRect(_ windowId: UInt32) async throws -> Rect? {
        try await withWindow(windowId) { window, job in try AppBundle.getAxRect(window: window, job: job) }
    }

    func getAxRectForTermination(_ windowId: UInt32) -> Rect? {
        let future = CompletableFuture<Rect?>()
        let job = withWindowAsync(windowId) { window, job in
            future.complete(try AppBundle.getAxRect(window: window, job: job))
        }
        return switch job.isCancelled {
            case true: nil
            case false: future.blockingGet()
        }
    }

    func isWindowHeuristic(_ windowId: UInt32, _ windowLevel: MacOsWindowLevel?) async throws -> Bool {
        return try await withWindow(windowId) { [nsApp, axApp, appId] window, job in
            guard let axApp = axApp.threadGuardedOrNil else { return nil }
            return window.isWindowHeuristic(axApp: axApp, appId, nsApp.activationPolicy, windowLevel)
        } == true
    }

    func getAxUiElementWindowType(_ windowId: UInt32, _ windowLevel: MacOsWindowLevel?) async throws -> AxUiElementWindowType {
        return try await withWindow(windowId) { [nsApp, axApp, appId] window, job in
            guard let axApp = axApp.threadGuardedOrNil else { return nil }
            return window.getWindowType(axApp: axApp, appId, nsApp.activationPolicy, windowLevel)
        } ?? .window
    }

    func isDialogHeuristic(_ windowId: UInt32, _ windowLevel: MacOsWindowLevel?) async throws -> Bool {
        try await withWindow(windowId) { [appId] window, job in
            window.isDialogHeuristic(appId, windowLevel)
        } == true
    }

    func setNativeFullscreen(_ windowId: UInt32, _ value: Bool) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = withWindowAsync(windowId) { window, job in
            window.set(Ax.isFullscreenAttr, value)
        }
    }

    func setNativeMinimized(_ windowId: UInt32, _ value: Bool) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = withWindowAsync(windowId) { window, job in
            window.set(Ax.minimizedAttr, value)
        }
    }

    func dumpWindowAxInfo(windowId: UInt32) async throws -> [String: Json] {
        try await withWindow(windowId) { window, job in
            dumpAxRecursive(window, .window)
        } ?? [:]
    }

    /// Unlike 'dumpWindowAxInfo', it also dumps AX windows that are not treated as windows from AeroSpace perspective.
    /// The only intended use case is 'debug-windows' command. https://github.com/nikitabobko/AeroSpace/issues/1235
    func dumpAllWindowsAxInfo(_ windowLevels: [UInt32: MacOsWindowLevel]) async throws -> [(windowId: UInt32?, dump: [String: Json])] {
        try await thread?.runInLoop { [nsApp, axApp, windows, appId] job in
            guard let app = axApp.threadGuardedOrNil else { return [] }
            var result: [(windowId: UInt32?, dump: [String: Json])] = []
            var enumeratedIds: Set<UInt32> = []
            func newDump(_ windowId: UInt32?, _ ax: AXUIElement) -> [String: Json] {
                var dump = dumpAxRecursive(ax, .window)
                let windowLevel = windowId.flatMap { windowLevels[$0] }
                let windowType = ax.getWindowType(axApp: app, appId, nsApp.activationPolicy, windowLevel)
                dump["Aero.AxUiElementWindowType"] = .string(windowType.rawValue)
                dump["Aero.AxUiElementWindowType_isDialogHeuristic"] = .bool(ax.isDialogHeuristic(appId, windowLevel))
                return dump
            }
            for (windowId, ax) in app.get(Ax.windowsRawAttr) ?? [] {
                try job.checkCancellation()
                var dump = newDump(windowId, ax)
                if windowId == nil {
                    dump["Aero.debug.windowIdFailed"] = .string("_AXUIElementGetWindow failed or returned kCGNullWindowID. AeroSpace ignores such AX windows")
                }
                if let windowId { enumeratedIds.insert(windowId) }
                result.append((windowId, dump))
            }
            // Registered AX windows that are not enumerated in kAXWindowsAttribute (e.g. windows on inactive macOS Spaces)
            for (windowId, axWindow) in (windows.threadGuardedOrNil ?? [:]) where !enumeratedIds.contains(windowId) {
                try job.checkCancellation()
                var dump = newDump(windowId, axWindow.ax)
                dump["Aero.debug.absentInAxWindowsAttr"] = .bool(true)
                result.append((windowId, dump))
            }
            return result
        } ?? []
    }

    func dumpAppAxInfo() async throws -> [String: Json] {
        try await thread?.runInLoop { [axApp] job in
            guard let axApp = axApp.threadGuardedOrNil else { return nil }
            return dumpAxRecursive(axApp, .app)
        } ?? [:]
    }

    func getAxTitle(_ windowId: UInt32) async throws -> String? {
        try await withWindow(windowId) { window, job in
            window.get(Ax.titleAttr)
        }
    }

    func isMacosNativeFullscreen(_ windowId: UInt32) async throws -> Bool? {
        try await withWindow(windowId) { window, job in
            window.get(Ax.isFullscreenAttr)
        }
    }

    func isMacosNativeMinimized(_ windowId: UInt32) async throws -> Bool? {
        try await withWindow(windowId) { window, job in
            window.get(Ax.minimizedAttr)
        }
    }

    @MainActor
    static func refreshAllAndGetAliveWindowIds(frontmostAppBundleId: String?) async throws -> (mapping: [MacApp: [UInt32]], incomplete: Bool) {
        for (_, app) in MacApp.allAppsMap { // gc dead apps
            try checkCancellation()
            if app.nsApp.isTerminated {
                await app.destroy()
            }
        }
        return try await withThrowingTaskGroup(of: (pid_t, [UInt32], Bool).self, returning: ([MacApp: [UInt32]], Bool).self) { group in
            func refreshTheApp(_ nsApp: NSRunningApplication) {
                group.addTask { @Sendable @MainActor in
                    guard let app = try await MacApp.getOrRegister(nsApp) else { return (nsApp.processIdentifier, [], false) }
                    let (windowIds, incomplete) = try await app.refreshAndGetAliveWindowIds(frontmostAppBundleId: frontmostAppBundleId)
                    // app.pid, not nsApp.processIdentifier: they differ for apps reported with pid -1 (see resolveRealPid)
                    return (app.pid, windowIds, incomplete)
                }
            }
            // Register new apps
            for nsApp in NSWorkspace.shared.runningApplications {
                try checkCancellation()
                if nsApp.activationPolicy == .regular {
                    refreshTheApp(nsApp)
                }
            }
            for (_, app) in MacApp.allAppsMap {
                try checkCancellation()
                // "About this Mac" window, TouchID, and a lot of other utility windows
                // We don't monitor them actively as we do for regular apps, but if a window of one of those utility
                // apps got focused it will end up in allAppsMap
                if app.nsApp.activationPolicy != .regular {
                    refreshTheApp(app.nsApp)
                }
            }
            var result: [MacApp: [UInt32]] = [:]
            var anyIncomplete = false
            for try await (pid, windowIds, incomplete) in group {
                if let app = MacApp.allAppsMap[pid] {
                    result[app] = windowIds
                }
                anyIncomplete = anyIncomplete || incomplete
            }
            return (result, anyIncomplete)
        }
    }

    /// `incomplete` is true when the app didn't respond to the window enumeration request in time
    /// (e.g. the app is busy, or the system is under load during boot). The returned window ids are
    /// still valid, but new windows of the app may be missing - the caller should schedule a retry.
    /// https://github.com/nikitabobko/AeroSpace/issues/1615
    private func refreshAndGetAliveWindowIds(frontmostAppBundleId: String?) async throws -> (windowIds: [UInt32], incomplete: Bool) {
        if nsApp.isTerminated {
            await destroy()
            return ([], false)
        }
        guard let thread else { return ([], false) }
        // Read on this actor before hopping to the dedicated AX thread, same as in getFocusedWindow.
        let staleTabCandidateId = lastNativeFocusedWindowId
        let (alive, dead, incomplete) = try await thread.runInLoop { [pid, windows, axApp, staleTabCandidateId] (job) -> ([UInt32], [UInt32], Bool) in
            guard var alive: [UInt32: AxWindow] = windows.threadGuardedOrNil else { return ([], [], false) }
            guard let axApp = axApp.threadGuardedOrNil else { return ([], [], false) }
            var dead = [UInt32: AxWindow]()
            // The app didn't respond to the enumeration request in time. It doesn't mean the app has
            // no windows - keep the known set, and let the caller schedule a retry
            let liveWindows = readAxWindows(axApp)
            var incomplete = liveWindows.isTimedOut
            // Same native-tab-replacement candidate as getFocusedWindow, caught here too so this
            // periodic refresh (which can run before the focus-change notification that normally
            // retires it) doesn't flicker the layout by reporting the stale tab as alive.
            if !isLeftMouseButtonDown,
               let staleTabCandidateId,
               alive[staleTabCandidateId] != nil,
               axApp.get(Ax.focusedWindowAttr)?.windowId != staleTabCandidateId,
               isMissingFromLiveAxWindows(staleTabCandidateId, in: liveWindows), // Never true on a timeout
               let stale = alive.removeValue(forKey: staleTabCandidateId)
            {
                dead[staleTabCandidateId] = stale
            }
            // Second line of defence against lock screen. See the first line of defence: closedWindowsCache
            // Second and third lines of defence are technically needed only to avoid potential flickering
            if frontmostAppBundleId != lockScreenAppBundleId {
                (alive, dead) = try alive.partition {
                    try job.checkCancellation()
                    switch $0.value.ax.windowLiveness() {
                        case .alive: return true
                        case .dead: return false
                        case .unknown:
                            // The app didn't respond in time. Unknown is not dead: reaping windows of a
                            // merely busy app makes them vanish from the tree and reappear later.
                            incomplete = true
                            return true
                    }
                }
            }

            for (id, window) in liveWindows.windowsOrEmpty {
                try job.checkCancellation()
                try alive.getOrRegisterAxWindow(windowId: id, window, pid, job)
            }

            windows.threadGuarded = alive
            return (Array(alive.keys), Array(dead.keys), incomplete)
        }
        windowsCount = alive.count
        for windowId in dead {
            setFrameJobs.removeValue(forKey: windowId)?.cancel()
        }
        return (alive, incomplete)
    }

    private func destroy() async {
        _ = await Task { @MainActor [pid] in
            _ = MacApp.allAppsMap.removeValue(forKey: pid)
            MacApp.clearFailedRegistration(pid)
        }.result
        for (_, job) in setFrameJobs {
            job.cancel()
        }
        setFrameJobs = [:]
        // Only stop the run loop here. The AX objects are destroyed on the AX thread right after
        // CFRunLoopRun() returns (see getOrRegister), so they can't be freed while the run loop is
        // still dispatching (which caused the 'Value is already destroyed' crash).
        thread?.runInLoopAsync { job in CFRunLoopStop(CFRunLoopGetCurrent()) }
        thread = nil // Disallow all future job submissions
    }

    private func withWindow<T>(_ windowId: UInt32, _ body: @Sendable @escaping (AXUIElement, RunLoopJob) throws -> T?) async throws -> T? {
        try await thread?.runInLoop { [windows] job in
            guard let window = windows.threadGuardedOrNil?[windowId] else { return nil }
            return try body(window.ax, job)
        }
    }

    private func withWindowAsync(_ windowId: UInt32, _ body: @Sendable @escaping (AXUIElement, RunLoopJob) throws -> ()) -> RunLoopJob {
        thread?.runInLoopAsync { [windows] job in
            guard let window = windows.threadGuardedOrNil?[windowId] else { return }
            try? body(window.ax, job)
        } ?? .cancelled
    }
}

func performNativeFocus(
    job: RunLoopJob,
    setMain: () -> Void,
    raise: () -> Void,
    activate: () -> Void,
) throws {
    try job.checkCancellation()
    setMain()
    // AX calls can block while another focus request cancels this job.
    try job.checkCancellation()
    raise()
    try job.checkCancellation()
    activate()
}

private final class AxWindow {
    let windowId: UInt32
    let ax: AXUIElement
    // periphery:ignore
    private let axSubscriptions: [AxSubscription] // keep subscriptions in memory

    private init(windowId: UInt32, _ ax: AXUIElement, _ axSubscriptions: [AxSubscription]) {
        self.windowId = windowId
        self.ax = ax
        assert(!axSubscriptions.isEmpty)
        self.axSubscriptions = axSubscriptions
    }

    static func new(windowId: UInt32, _ ax: AXUIElement, _ pid: pid_t, _ job: RunLoopJob) throws -> AxWindow? {
        let handlers: HandlerToNotifKeyMapping = unsafe [
            (refreshObs, [kAXUIElementDestroyedNotification, kAXWindowDeminiaturizedNotification, kAXWindowMiniaturizedNotification]),
            (movedObs, [kAXMovedNotification]),
            (resizedObs, [kAXResizedNotification]),
        ]
        let subscriptions = try unsafe AxSubscription.bulkSubscribe(pid, ax, job, handlers)
        return !subscriptions.isEmpty ? AxWindow(windowId: windowId, ax, subscriptions) : nil
    }
}

extension [UInt32: AxWindow] {
    @discardableResult
    fileprivate mutating func getOrRegisterAxWindow(windowId id: UInt32, _ axWindow: AXUIElement, _ pid: pid_t, _ job: RunLoopJob) throws -> AxWindow? {
        if let existing = self[id] { return existing }
        // Delay new window detection if mouse is down
        // It helps with apps that allow dragging their tabs out to create new windows
        // https://github.com/nikitabobko/AeroSpace/issues/1001
        if isLeftMouseButtonDown { return nil }

        if let window = try AxWindow.new(windowId: id, axWindow, pid, job) {
            self[id] = window
            return window
        } else {
            return nil
        }
    }
}

/// The app's AXWindows list, or `.timedOut` when the app didn't respond in time (kAXErrorCannotComplete).
/// A timeout says nothing about which windows exist. https://github.com/nikitabobko/AeroSpace/issues/1615
enum AxWindowsRead {
    case windows([WindowIdAndAxUiElement])
    case timedOut

    var isTimedOut: Bool {
        if case .timedOut = self { true } else { false }
    }

    /// Every other read failure keeps the old `get(...) ?? []` behavior
    var windowsOrEmpty: [WindowIdAndAxUiElement] {
        switch self {
            case .windows(let windows): windows
            case .timedOut: []
        }
    }
}

private func readAxWindows(_ axApp: AXUIElement) -> AxWindowsRead {
    let (windows, error) = axApp.getOrError(Ax.windowsAttr)
    return error == .cannotComplete ? .timedOut : .windows(windows ?? [])
}

/// True if `windowId` is missing from the app's live AXWindows list, i.e. a native-tab
/// window it belonged to was replaced by a sibling tab (see getFocusedWindow).
/// Never true when the read timed out: an unresponsive app's empty answer must not prune a tab
func isMissingFromLiveAxWindows(_ windowId: UInt32, in liveWindows: AxWindowsRead) -> Bool {
    switch liveWindows {
        case .windows(let windows): !windows.contains { $0.windowId == windowId }
        case .timedOut: false
    }
}

private func getAxRect(window: AXUIElement, job: RunLoopJob) throws -> Rect? {
    guard let topLeftCorner = window.get(Ax.topLeftCornerAttr) else { return nil }
    try job.checkCancellation()
    guard let size = window.get(Ax.sizeAttr) else { return nil }
    return Rect(topLeftX: topLeftCorner.x, topLeftY: topLeftCorner.y, width: size.width, height: size.height)
}

private func setFrame(_ window: AXUIElement, _ topLeft: CGPoint?, _ size: CGSize?, _ job: RunLoopJob) throws {
    // Set size and then the position. The order is important https://github.com/nikitabobko/AeroSpace/issues/143
    //                                                        https://github.com/nikitabobko/AeroSpace/issues/335
    if let size { window.set(Ax.sizeAttr, size) }
    try job.checkCancellation()
    if let topLeft { window.set(Ax.topLeftCornerAttr, topLeft) } else { return }
    try job.checkCancellation()
    if let size { window.set(Ax.sizeAttr, size) }
}

// Some undocumented magic
// References: https://github.com/koekeishiya/yabai/commit/3fe4c77b001e1a4f613c26f01ea68c0f09327f3a
//             https://github.com/rxhanson/Rectangle/pull/285
private func disableAnimations<T>(app: AXUIElement, _ job: RunLoopJob, _ body: () throws -> T) throws -> T {
    let wasEnabled = app.get(Ax.enhancedUserInterfaceAttr) == true
    if wasEnabled {
        app.set(Ax.enhancedUserInterfaceAttr, false)
    }
    defer {
        if wasEnabled {
            app.set(Ax.enhancedUserInterfaceAttr, true)
        }
    }
    try job.checkCancellation()
    return try body()
}

// Some apps are started via a launcher process that exits after it starts the real process.
// E.g. Xcode 27 "Device Hub" (com.apple.dt.Devices) is started via DevicesTrampoline.
// For such apps, NSRunningApplication.processIdentifier is -1, and the real process isn't in
// NSWorkspace.runningApplications at all. Even NSRunningApplication(processIdentifier: realPid) returns
// an object with processIdentifier == -1. The workaround is to find the real pid by the owner pid of the windows
@MainActor
private func resolveRealPid(_ nsApp: NSRunningApplication) -> pid_t? {
    if nsApp.processIdentifier > 0 { return nsApp.processIdentifier }
    guard let bundleId = nsApp.bundleIdentifier else { return nil }
    // .optionAll because the windows of the app might be minimized or hidden
    guard let cfArray = CGWindowListCopyWindowInfo(.optionAll, CGWindowID(0)) as? [CFDictionary] else { return nil }
    var visitedPids: Set<pid_t> = []
    for elem in cfArray {
        let dict = elem as NSDictionary
        guard let _pid = dict[kCGWindowOwnerPID] else { continue }
        let pid = ((_pid as! CFNumber) as NSNumber).int32Value
        if pid <= 0 || !visitedPids.insert(pid).inserted { continue }
        if NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == bundleId {
            return pid
        }
    }
    return nil
}

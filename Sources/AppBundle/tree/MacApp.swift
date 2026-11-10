import AppKit
import Common
import os

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
    var lastFocusedNativeWindowOpaqueId: OpaqueWindowId? = nil
    private var thread: Thread?
    private var setFrameJobs: [OpaqueWindowId: RunLoopJob] = [:]
    /// Windows whose last frame write may have ended before the GTK redraw nudge (see setAxFrame), e.g. because
    /// the job was cancelled in between. They never take the "frame already applied" shortcut. (fork #90)
    private let redrawNudgePending = OSAllocatedUnfairLock<Set<OpaqueWindowId>>(initialState: [])
    // Never pruned: while the screen is locked, AX reports windows as gone, and closedWindowsCache matches
    // the windows re-detected after unlock by their OpaqueWindowId
    // todo: start prunning after we get rid of closedWindowsCache
    private var windowIdMapping = BiDictionary<OpaqueWindowId, UInt32>()
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

    /// Decides whether a failed-registration retry for `pid` should be throttled (skipped). (fork #19, upstream PR #2085)
    /// Upstream 269dc71b turned the registration retry loop into a single attempt, which fixes the tight CPU-spiking
    /// loop. But an app whose AX subscription keeps failing would still spawn a new AX thread and re-subscribe on
    /// every refresh session, so failed attempts are still throttled on top of that.
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

    private init(
        _ nsApp: NSRunningApplication,
        _ pid: pid_t,
        _ axApp: AXUIElement,
        _ axSubscriptions: [AxSubscription],
        _ thread: Thread,
    ) {
        self.nsApp = nsApp
        self.axApp = .init(axApp)
        self.pid = pid // Not nsApp.processIdentifier: it's -1 for some apps (see resolveRealPid)
        self.rawAppBundleId = nsApp.bundleIdentifier
        self.appId = nsApp.bundleIdentifier.flatMap { KnownBundleId.init(rawValue: $0) }
        assert(!axSubscriptions.isEmpty)
        self.appAxSubscriptions = .init(axSubscriptions)
        self.thread = thread
    }

    @MainActor @discardableResult static func getOrRegister(_ nsApp: NSRunningApplication) async throws -> MacApp? {
        // Don't perceive any of the lock screen windows as real windows
        // Otherwise, false positive ax notifications might trigger that lead to gcWindows
        if nsApp.bundleIdentifier == lockScreenAppBundleId { return nil }
        guard let pid = resolveRealPid(nsApp) else { return nil }
        // AX requests crash if you send them to yourself
        if pid == myPid { return nil }

        if let existing = allAppsMap[pid] { return existing }
        if shouldThrottleFailedRegistration(pid) { return nil }
        try checkCancellation()
        if let wip = wipPids[pid] {
            try await wip.await(.cancellable)
            return allAppsMap[pid]
        }
        let wip = AwaitableOneTimeBroadcastLatch()
        wipPids[pid] = wip

        let thread = Thread {
            $axTaskLocalAppThreadToken.withValue(AxAppThreadToken(pid: pid, idForDebug: nsApp.idForDebug)) {
                let axApp = AXUIElementCreateApplication(pid)
                // Every AX read is a synchronous IPC round-trip into the target app. Without an
                // explicit timeout, one wedged app (Electron mid-freeze, a JetBrains IDE indexing)
                // stalls the whole refresh and the WM appears hung. Cap the wait instead: a slow
                // app loses one refresh cycle, everything else keeps tiling. (fork 15d63519)
                // Tuning knob: too low and genuinely slow apps (e.g. Godot) get their windows
                // dropped from a refresh; too high and a hang is user-visible.
                AXUIElementSetMessagingTimeout(axApp, axMessagingTimeoutSeconds)
                let handlers: HandlerToNotifKeyMapping = unsafe [
                    (refreshObs, [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification]),
                ]
                let job = RunLoopJob(.cancellable)
                let subscriptions = (try? unsafe AxSubscription.bulkSubscribe(pid, axApp, job, handlers)) ?? []
                let isGood = !subscriptions.isEmpty
                let app = isGood ? MacApp(nsApp, pid, axApp, subscriptions, Thread.current) : nil

                let appAxSubscriptionsThreadGuarded = app?.appAxSubscriptions
                let windowsThreadGuarded = app?.windows
                let axAppThreadGuarded = app?.axApp

                Task.startUnstructured { @MainActor in
                    allAppsMap[pid] = app
                    if app != nil {
                        clearFailedRegistration(pid)
                    } else {
                        recordFailedRegistration(pid)
                    }
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

        try await wip.await(.cancellable)
        return allAppsMap[pid]
    }

    func nativeWindowId(of windowId: OpaqueWindowId) -> UInt32? { windowIdMapping.forward[windowId] }

    func opaqueWindowId(of nativeWindowId: UInt32) -> OpaqueWindowId? { windowIdMapping.backward[nativeWindowId] }

    @MainActor private func getOrRegisterOpaqueWindowId(_ nativeWindowId: UInt32) -> OpaqueWindowId {
        if let existing = windowIdMapping.backward[nativeWindowId] { return existing }
        let windowId = OpaqueWindowId.nextUniqId()
        windowIdMapping.put(windowId, nativeWindowId)
        return windowId
    }

    func closeAndUnregisterAxWindow(_ windowId: OpaqueWindowId) {
        if serverArgs.isReadOnly { return }
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        guard let nativeWindowId = windowIdMapping.forward[windowId] else { return }
        _ = withWindowAsync(windowId, .cancellable) { [windows] window, job in
            guard let closeButton = window.get(Ax.closeButtonAttr) else { return }
            if AXUIElementPerformAction(closeButton.cast, kAXPressAction as CFString) == .success {
                guard windows.threadGuardedOrNil != nil else { return }
                windows.threadGuarded.removeValue(forKey: nativeWindowId)
            }
        }
    }

    func getAxSize(_ windowId: OpaqueWindowId, _ cm: CancellationMode) async throws -> CGSize? {
        try await withWindow(windowId, cm) { window, job in
            window.get(Ax.sizeAttr)
        }
    }

    // todo merge together with detectNewWindows
    func getFocusedWindow(_ cm: CancellationMode) async throws -> Window? {
        let nativeWindowId = try await thread?.runInLoop(cm) { [pid, axApp, windows] job -> UInt32? in
            guard let axApp = axApp.threadGuardedOrNil, windows.threadGuardedOrNil != nil else { return nil }
            return try axApp.get(Ax.focusedWindowAttr)
                .flatMap { try windows.threadGuarded.getOrRegisterAxWindow(windowId: $0.windowId, $0.ax.cast, pid, job) }?
                .windowId
        }
        guard let nativeWindowId else { return nil }
        return try await MacWindow.getOrRegister(windowId: getOrRegisterOpaqueWindowId(nativeWindowId), macApp: self)
    }

    @MainActor func nativeFocus(_ windowId: OpaqueWindowId) {
        if serverArgs.isReadOnly { return }
        MacApp.focusJob?.cancel()
        // Performance optimization. If possible avoid doing AX requests
        // (important for apps which are slow at responding even such basic AX requests. E.g. Godot)
        // Beware of the macOS bug: https://github.com/nikitabobko/AeroSpace/issues/101
        if (!NSScreen.screensHaveSeparateSpaces || globalUnsortedMonitorInfos.count == 1) &&
            (lastFocusedNativeWindowOpaqueId == windowId || windowsCount == 1)
        {
            nativeActivate(nsApp)
        } else {
            MacApp.focusJob = withWindowAsync(windowId, .cancellable) { [nsApp] window, job in
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

    func setAxFrame(_ windowId: OpaqueWindowId, _ topLeft: CGPoint?, _ size: CGSize?) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = withWindowAsync(windowId, .cancellable) { [axApp, redrawNudgePending] window, job in
            guard let axApp = axApp.threadGuardedOrNil else { return }
            // Writes are expensive and trigger kAXMoved/kAXResized, which schedule yet another refresh. (fork #90)
            // Skipping also skips the redraw nudge below: nothing moved, so there's nothing to redraw. Unless the
            // previous write was interrupted before its nudge, in which case the frame matches but the app may be stale
            if !redrawNudgePending.withLock({ $0.contains(windowId) }),
               isFrameAlreadyApplied(topLeft, size, currentTopLeft: { window.get(Ax.topLeftCornerAttr) }, currentSize: { window.get(Ax.sizeAttr) })
            {
                return
            }
            redrawNudgePending.withLock { _ = $0.insert(windowId) }
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
            redrawNudgePending.withLock { _ = $0.remove(windowId) }
        }
    }

    func setAxFrameForTermination(_ windowId: OpaqueWindowId, _ topLeft: CGPoint?, _ size: CGSize?) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        let semaphore = DispatchSemaphore(value: 0)
        let job = withWindowAsync(windowId, .nonCancellable) { [axApp] window, job in
            if let axApp = axApp.threadGuardedOrNil {
                try? disableAnimations(app: axApp, job) {
                    try setFrame(window, topLeft, size, job)
                }
                // GTK redraw nudge, see setAxFrame (fork cdc4d48b)
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

    func getAxWindowsCount(_ cm: CancellationMode) async throws -> Int? {
        try await thread?.runInLoop(cm) { [axApp] job in
            axApp.threadGuardedOrNil?.get(Ax.windowsAttr)?.count
        }
    }

    func getAxRect(_ windowId: OpaqueWindowId, _ cm: CancellationMode) async throws -> Rect? {
        try await withWindow(windowId, cm) { window, job in
            try AppBundle::getAxRect(window: window, job: job)
        }
    }

    func getAxRectForTermination(_ windowId: OpaqueWindowId) -> Rect? {
        let future = CompletableFuture<Rect?>()
        let job = withWindowAsync(windowId, .nonCancellable) { window, job in
            future.complete(try AppBundle::getAxRect(window: window, job: job))
        }
        return switch job.isCancelled {
            case true: nil
            case false: future.blockingGet()
        }
    }

    func isWindowHeuristic(_ windowId: OpaqueWindowId, _ windowLevel: MacOsWindowLevel?, _ cm: CancellationMode) async throws -> Bool {
        return try await withWindow(windowId, cm) { [nsApp, axApp, appId] window, job in
            guard let axApp = axApp.threadGuardedOrNil else { return nil }
            return window.isWindowHeuristic(axApp: axApp, appId, nsApp.activationPolicy, windowLevel)
        } == true
    }

    func getAxUiElementWindowType(_ windowId: OpaqueWindowId, _ windowLevel: MacOsWindowLevel?, _ cm: CancellationMode) async throws -> AxUiElementWindowType {
        return try await withWindow(windowId, cm) { [nsApp, axApp, appId] window, job in
            guard let axApp = axApp.threadGuardedOrNil else { return nil }
            return window.getWindowType(axApp: axApp, appId, nsApp.activationPolicy, windowLevel)
        } ?? .window
    }

    func isDialogHeuristic(_ windowId: OpaqueWindowId, _ windowLevel: MacOsWindowLevel?, _ cm: CancellationMode) async throws -> Bool {
        try await withWindow(windowId, cm) { [appId] window, job in
            window.isDialogHeuristic(appId, windowLevel)
        } == true
    }

    func setNativeFullscreen(_ windowId: OpaqueWindowId, _ value: Bool) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = withWindowAsync(windowId, .cancellable) { window, job in
            window.set(Ax.isFullscreenAttr, value)
        }
    }

    func setNativeMinimized(_ windowId: OpaqueWindowId, _ value: Bool) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = withWindowAsync(windowId, .cancellable) { window, job in
            window.set(Ax.minimizedAttr, value)
        }
    }

    func dumpWindowAxInfo(windowId: OpaqueWindowId, _ cm: CancellationMode) async throws -> [String: Json] {
        try await withWindow(windowId, cm) { window, job in
            dumpAxRecursive(window, .window)
        } ?? [:]
    }

    /// Unlike 'dumpWindowAxInfo', it also dumps AX windows that are not treated as windows from AeroSpace perspective.
    /// The only intended use case is 'debug-windows --app-bundle-id' command. https://github.com/nikitabobko/AeroSpace/issues/1235
    /// (fork fcb0260b). Window ids are native (WindowServer) ids
    func dumpAllWindowsAxInfo(_ windowLevels: [UInt32: MacOsWindowLevel], _ cm: CancellationMode) async throws -> [(windowId: UInt32?, dump: [String: Json])] {
        try await thread?.runInLoop(cm) { [nsApp, axApp, windows, appId] job in
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

    func dumpAppAxInfo(_ cm: CancellationMode) async throws -> [String: Json] {
        try await thread?.runInLoop(cm) { [axApp] job in
            guard let axApp = axApp.threadGuardedOrNil else { return nil }
            return dumpAxRecursive(axApp, .app)
        } ?? [:]
    }

    func getAxTitle(_ windowId: OpaqueWindowId, _ cm: CancellationMode) async throws -> String? {
        try await withWindow(windowId, cm) { window, job in
            window.get(Ax.titleAttr)
        }
    }

    func isMacosNativeFullscreen(_ windowId: OpaqueWindowId, _ cm: CancellationMode) async throws -> Bool? {
        try await withWindow(windowId, cm) { window, job in
            window.get(Ax.isFullscreenAttr)
        }
    }

    func isMacosNativeMinimized(_ windowId: OpaqueWindowId, _ cm: CancellationMode) async throws -> Bool? {
        try await withWindow(windowId, cm) { window, job in
            window.get(Ax.minimizedAttr)
        }
    }

    func getMacosWindowNativeState(_ windowId: OpaqueWindowId, _ cm: CancellationMode) async throws -> MacosWindowNativeState? {
        try await withWindow(windowId, cm) { window, job in
            if window.get(Ax.isFullscreenAttr) == true { return .nativeFullscreen }
            try job.checkCancellation()
            if window.get(Ax.minimizedAttr) == true { return .nativeMinimized }
            return .normal
        }
    }

    @MainActor func getWindowLevel(_ windowId: OpaqueWindowId, _ cm: CancellationMode) async throws -> MacOsWindowLevel? {
        guard let nativeWindowId = windowIdMapping.forward[windowId] else { return nil }
        return try await AppBundle::getWindowLevel(forNativeId: nativeWindowId, cm)
    }

    /// `incomplete` is true when some app didn't respond to the window enumeration request in time. (fork #87)
    @MainActor static func refreshAllAndGetAliveWindowIds(
        frontmostAppBundleId: String?,
    ) async throws -> (mapping: [MacApp: [OpaqueWindowId: WindowLifeStatus]], incomplete: Bool) {
        for app in MacApp.allAppsMap.values { // gc dead apps
            try checkCancellation()
            if app.nsApp.isTerminated {
                await app.destroy()
            }
        }
        return try await withThrowingTaskGroup(
            of: (MainActorRef<MacApp>?, [OpaqueWindowId: WindowLifeStatus], Bool).self,
            returning: ([MacApp: [OpaqueWindowId: WindowLifeStatus]], Bool).self,
        ) { group in
            // Registration happens inside the task, so one slow-to-register app doesn't serialize the rest
            @MainActor func refreshTheApp(_ nsApp: NSRunningApplication) {
                group.addTask { @Sendable @MainActor in
                    guard let app = try await MacApp.getOrRegister(nsApp) else { return (nil, [:], false) }
                    let (windowIds, incomplete) = try await app.refreshAndGetAliveWindowIds(frontmostAppBundleId: frontmostAppBundleId)
                    return (MainActorRef.init(app), windowIds, incomplete)
                }
            }
            // Register new apps
            for nsApp in NSWorkspace.shared.runningApplications {
                try checkCancellation()
                if nsApp.activationPolicy == .regular {
                    refreshTheApp(nsApp)
                }
            }
            for app in MacApp.allAppsMap.values {
                try checkCancellation()
                // "About this Mac" window, TouchID, and a lot of other utility windows
                // We don't monitor them actively as we do for regular apps, but if a window of one of those utility
                // apps got focused it will end up in allAppsMap
                if app.nsApp.activationPolicy != .regular {
                    refreshTheApp(app.nsApp)
                }
            }
            var result: [MacApp: [OpaqueWindowId: WindowLifeStatus]] = [:]
            var anyIncomplete = false
            for try await (macAppRef, windowIds, incomplete) in group {
                if let macAppRef {
                    result[macAppRef.value] = windowIds
                }
                anyIncomplete = anyIncomplete || incomplete
            }
            return (result, anyIncomplete)
        }
    }

    /// `incomplete` is true when the app didn't respond to the window enumeration request in time
    /// (e.g. the app is busy, or the system is under load during boot). The returned window ids are
    /// still valid, but new windows of the app may be missing - the caller should schedule a retry.
    /// https://github.com/nikitabobko/AeroSpace/issues/1615 (fork #87)
    @MainActor private func refreshAndGetAliveWindowIds(
        frontmostAppBundleId: String?,
    ) async throws -> (windowIds: [OpaqueWindowId: WindowLifeStatus], incomplete: Bool) {
        if nsApp.isTerminated {
            await destroy()
            return ([:], false)
        }
        guard let thread else { return ([:], false) }
        let (axResult, timedOut, incomplete) = try await thread
            .runInLoop(.cancellable) { [pid, windows, axApp, bgTabsScheduledForPrune] (job) -> ([UInt32: WindowLifeStatus], Bool, Bool) in
                guard let known = windows.threadGuardedOrNil, let axApp = axApp.threadGuardedOrNil else { return ([:], false, false) }
                var aliveOrInvisible: [UInt32: AxWindow] = known.filter { !bgTabsScheduledForPrune.contains($0.key) }
                var aliveWindowIds: Set<UInt32> = []
                // The app didn't respond to the enumeration request in time. It doesn't mean the app has
                // no windows - keep the known set, and let the caller schedule a retry
                let liveWindows = readAxWindows(axApp)
                var incomplete = liveWindows.isTimedOut
                // Second line of defence against lock screen. See the first line of defence: closedWindowsCache
                // Second and third lines of defence are technically needed only to avoid potential flickering
                if frontmostAppBundleId != lockScreenAppBundleId {
                    aliveOrInvisible = try aliveOrInvisible.filter {
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
                    try aliveOrInvisible.getOrRegisterAxWindow(windowId: id, window, pid, job)
                    aliveWindowIds.insert(id)
                }

                windows.threadGuarded = aliveOrInvisible
                return (
                    aliveOrInvisible.keys.associate(with: { it in aliveWindowIds.contains(it) ? .alive : .invisible }),
                    liveWindows.isTimedOut,
                    incomplete,
                )
            }
        var aliveOrInvisible = axResult
        bgTabsScheduledForPrune = []
        windowsCount = aliveOrInvisible.count

        if timedOut {
            // AXWindows timed out, so the alive/invisible split above carries no information: every window looks
            // invisible. Keep the statuses of the last refresh instead of tombstoning the windows of a busy app
            for id in aliveOrInvisible.keys {
                aliveOrInvisible[id] = lifeStatusesOfLastRefresh[id] ?? .alive
            }
        } else {
            nonidempotentNativeTabSwapHeuristic(&aliveOrInvisible)
        }

        var aliveOrInvisibleMap: [OpaqueWindowId: WindowLifeStatus] = [:]
        for (id, lifeStatus) in aliveOrInvisible {
            aliveOrInvisibleMap[getOrRegisterOpaqueWindowId(id)] = lifeStatus
        }
        for windowId in setFrameJobs.keys {
            if !aliveOrInvisibleMap.keys.contains(windowId) {
                setFrameJobs.removeValue(forKey: windowId)?.cancel()
            }
        }
        return (aliveOrInvisibleMap, incomplete)
    }

    private var bgTabsScheduledForPrune: Set<UInt32> = []
    private var lifeStatusesOfLastRefresh: [UInt32: WindowLifeStatus] = [:]
    @MainActor private func nonidempotentNativeTabSwapHeuristic(_ aliveOrInvisible: inout [UInt32: WindowLifeStatus]) {
        let noLongerAlive = lifeStatusesOfLastRefresh.filter { (id, lifeStatus) in lifeStatus == .alive && aliveOrInvisible[id] != .alive }
        let becameAlive = aliveOrInvisible.filter { (id, lifeStatus) in lifeStatus == .alive && lifeStatusesOfLastRefresh[id] != .alive }
        lifeStatusesOfLastRefresh = aliveOrInvisible
        if let backgroundTabId = noLongerAlive.singleOrNil()?.key,
           let frontmostTabId = becameAlive.singleOrNil()?.key
        {
            let tabGroupWindowId = getOrRegisterOpaqueWindowId(backgroundTabId)
            windowIdMapping.put(tabGroupWindowId, frontmostTabId)
            // The tree slot now points at a different native window. layoutRecursive skips frame writes whose target
            // rect didn't change since the last pass (fork 65546512), which would leave the new tab wherever macOS
            // put it. Forget the last applied rect so the next layout writes the frame
            MacWindow.allWindowsMap[tabGroupWindowId]?.lastAppliedLayoutPhysicalRect = nil
            aliveOrInvisible[backgroundTabId] = nil
            bgTabsScheduledForPrune.insert(backgroundTabId)
        }
    }

    private func destroy() async {
        _ = await Task.startUnstructured { @MainActor [pid] in
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
        thread?.runInLoopAsync(job: RunLoopJob(.nonCancellable)) { job in CFRunLoopStop(CFRunLoopGetCurrent()) }
        thread = nil // Disallow all future job submissions
    }

    private func withWindow<T>(
        _ windowId: OpaqueWindowId,
        _ cm: CancellationMode,
        _ body: @Sendable @escaping (AXUIElement, RunLoopJob) throws -> T?,
    ) async throws -> T? {
        guard let nativeWindowId = windowIdMapping.forward[windowId] else { return nil }
        return try await thread?.runInLoop(cm) { [windows] job -> T? in
            guard let window = windows.threadGuardedOrNil?[nativeWindowId] else { return nil }
            return try body(window.ax, job)
        }
    }

    private func withWindowAsync(_ windowId: OpaqueWindowId, _ cm: CancellationMode, _ body: @Sendable @escaping (AXUIElement, RunLoopJob) throws -> ()) -> RunLoopJob {
        guard let nativeWindowId = windowIdMapping.forward[windowId] else { return .cancelled }
        return thread?.runInLoopAsync(job: RunLoopJob(cm)) { [windows] job in
            guard let window = windows.threadGuardedOrNil?[nativeWindowId] else { return }
            try? body(window.ax, job)
        } ?? .cancelled
    }
}

/// Each AX call can block while another focus request cancels this job, so cancellation is re-checked between the
/// calls (fork #85)
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
    @discardableResult fileprivate mutating func getOrRegisterAxWindow(
        windowId id: UInt32,
        _ axWindow: AXUIElement,
        _ pid: pid_t,
        _ job: RunLoopJob,
    ) throws -> AxWindow? {
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
/// A timeout says nothing about which windows exist. https://github.com/nikitabobko/AeroSpace/issues/1615 (fork #87)
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

/// True if `windowId` is missing from the app's live AXWindows list.
/// Never true when the read timed out: an unresponsive app's empty answer must not prune a window
/// (Only covered by tests since the resync: the fork's own native-tab replacement that used it was superseded by
/// upstream's nonidempotentNativeTabSwapHeuristic)
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

/// Whether the window already has the target frame, so the AX write (and the redraw nudge) can be skipped. (fork #90)
/// AX frames are integral, while layout may produce fractional values, hence the 1px tolerance.
/// Comparing against the live frame (not a cache of the last applied one) stays correct when the app or the user
/// moves the window. The current frame is read lazily: a nil target component is not read at all
func isFrameAlreadyApplied(
    _ topLeft: CGPoint?,
    _ size: CGSize?,
    currentTopLeft: () -> CGPoint?,
    currentSize: () -> CGSize?,
) -> Bool {
    func isClose(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 1 }
    if let topLeft {
        guard let cur = currentTopLeft(), isClose(cur.x, topLeft.x), isClose(cur.y, topLeft.y) else { return false }
    }
    if let size {
        guard let cur = currentSize(), isClose(cur.width, size.width), isClose(cur.height, size.height) else { return false }
    }
    return true
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

// Some apps are started via a launcher process that exits after it starts the real process. (fork #83, upstream PR #2316)
// E.g. Xcode 27 "Device Hub" (com.apple.dt.Devices) is started via DevicesTrampoline.
// For such apps, NSRunningApplication.processIdentifier is -1, and the real process isn't in
// NSWorkspace.runningApplications at all. Even NSRunningApplication(processIdentifier: realPid) returns
// an object with processIdentifier == -1. The workaround is to find the real pid by the owner pid of the windows
@MainActor
private func resolveRealPid(_ nsApp: NSRunningApplication) -> pid_t? {
    if nsApp.processIdentifier > 0 { return nsApp.processIdentifier }
    guard let bundleId = nsApp.bundleIdentifier else { return nil }
    // .optionAll because the windows of the app might be minimized or hidden
    guard let cfArray = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [CFDictionary] else { return nil }
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

final class MainActorRef<T>: Sendable {
    @MainActor var value: T
    @MainActor public init(_ value: T) { self.value = value }
}

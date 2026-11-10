import AppKit
import Common

@MainActor var screenSleepWakeInProgress = false
@MainActor private var screenSleepWakeTask: Task<Void, Never>? = nil
private let screenSleepWakeSettleDelay: Duration = .milliseconds(1000)

@MainActor private var screenParamsTask: Task<Void, Never>? = nil
/// Display reconfiguration (hotplug, resolution change, rearrange) emits a burst of
/// `didChangeScreenParametersNotification`. Coalesce them so the tree is laid out once,
/// against the final monitor arrangement, rather than once per intermediate state.
private let screenParamsSettleDelay: Duration = .milliseconds(500)

enum GlobalObserver {
    private static func onNotif(_ notification: Notification) {
        // Third line of defence against lock screen window. See: closedWindowsCache
        // Second and third lines of defence are technically needed only to avoid potential flickering
        if (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == lockScreenAppBundleId {
            return
        }
        let notifName = notification.name.rawValue
        let activatedAppPid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
        Task.startUnstructured { @MainActor in
            if !TrayMenuModel.shared.isEnabled { return }
            if notifName == NSWorkspace.didActivateApplicationNotification.rawValue {
                if let activatedAppPid {
                    noteNativeAppActivation(appPid: activatedAppPid)
                }
                scheduleCancellableCompleteRefreshSession(.globalObserver(notifName), optimisticallyPreLayoutWorkspaces: true)
            } else {
                scheduleCancellableCompleteRefreshSession(.globalObserver(notifName))
            }
        }
    }

    private static func onHideApp(_ notification: Notification) {
        let notifName = notification.name.rawValue
        Task.startUnstructured { @MainActor in
            guard let token: RunSessionGuard = .isServerEnabled else { return }
            try await runLightSession(.globalObserver(notifName), token) {
                if config.automaticallyUnhideMacosHiddenApps {
                    if let w = prevFocus?.windowOrNil,
                       w.macAppUnsafe.nsApp.isHidden,
                       // "Hide others" (cmd-alt-h) -> don't force focus
                       // "Hide app" (cmd-h) -> force focus
                       MacApp.allAppsMap.values.count(where: { $0.nsApp.isHidden }) == 1
                    {
                        // Force focus
                        _ = w.focusWindow()
                        w.nativeFocus()
                    }
                    for app in MacApp.allAppsMap.values {
                        app.nsApp.unhide()
                    }
                }
            }
        }
    }

    private static func onScreenSleepWake(_ notification: Notification) {
        let notifName = notification.name.rawValue
        let isSleepNotification = notification.name == NSWorkspace.screensDidSleepNotification
        Task.startUnstructured { @MainActor in
            if !TrayMenuModel.shared.isEnabled { return }
            screenSleepWakeInProgress = true
            cancelCancellableCompleteRefreshSession()
            screenSleepWakeTask?.cancel()
            if isSleepNotification { return }
            screenSleepWakeTask = Task.startUnstructured { @MainActor in
                try? await Task.sleep(for: screenSleepWakeSettleDelay)
                if Task.isCancelled { return }
                screenSleepWakeInProgress = false
                scheduleCancellableCompleteRefreshSession(.globalObserver(notifName))
            }
        }
    }

    /// `monitors` is derived from `NSScreen.screens` on demand, so nothing recomputes the layout
    /// when a display is plugged in, unplugged, rearranged, or changes resolution. Without this,
    /// the tree keeps the stale monitor arrangement until some unrelated event triggers a refresh.
    private static func onScreenParamsChanged(_ notification: Notification) {
        let notifName = notification.name.rawValue
        Task.startUnstructured { @MainActor in
            if !TrayMenuModel.shared.isEnabled { return }
            screenParamsTask?.cancel()
            screenParamsTask = Task.startUnstructured { @MainActor in
                try? await Task.sleep(for: screenParamsSettleDelay)
                if Task.isCancelled { return }
                // A display change while the screens are asleep is settled by the wake handler
                if screenSleepWakeInProgress { return }
                scheduleCancellableCompleteRefreshSession(.globalObserver(notifName))
            }
        }
    }

    @MainActor
    static func initObserver() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.didHideApplicationNotification, object: nil, queue: .main, using: onHideApp)
        nc.addObserver(forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main,
            using: onScreenSleepWake,
        )
        nc.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main,
            using: onScreenSleepWake,
        )

        // Unlike the notifications above, this one is posted on the default center, not NSWorkspace's
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main,
            using: onScreenParamsChanged,
        )

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            guard let token: RunSessionGuard = .isServerEnabled else { return }
            // todo reduce number of refreshSession in the callback
            //  resetManipulatedWithMouseIfPossible might call its own refreshSession
            //  The end of the callback calls refreshSession
            Task.startUnstructured { @MainActor in
                // A click can intentionally activate another app, including one
                // on a different workspace. It supersedes keyboard/CLI workspace
                // protection and should be reconciled normally.
                cancelFocusProtectionAfterWorkspaceSwitch()
                noteUserClick() // marks the upcoming app activation as user-initiated

                try await resetManipulatedWithMouseIfPossible()
                let mouseLocation = mouseLocation
                let clickedMonitor = mouseLocation.monitorApproximation
                switch true {
                    // Detect clicks on desktop of different monitors
                    case clickedMonitor.visibleRect.contains(mouseLocation) && clickedMonitor.visibleWorkspace != globalFocus.workspace:
                        _ = try await runLightSession(.globalObserverLeftMouseUp, token) {
                            clickedMonitor.visibleWorkspace.focusWorkspace()
                        }
                    // Detect close button clicks for unfocused windows. Yes, kAXUIElementDestroyedNotification is that unreliable
                    //  And trigger new window detection that could be delayed due to mouseDown event
                    default:
                        scheduleCancellableCompleteRefreshSession(.globalObserverLeftMouseUp)
                }
            }
        }
    }
}

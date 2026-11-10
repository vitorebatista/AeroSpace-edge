@testable import AppBundle
import Testing

@MainActor
@Suite(.serializedGlobally)
struct FocusCacheTest {
    private let now = ContinuousClock().now

    @Test func testCloseProtectionSuppressesCrossWorkspaceFocus() {
        var protection = NativeFocusRaceProtection()
        protection.recordWindowClose(workspaceName: "a", now: now)

        #expect(protection.shouldSuppressAfterClose(
            currentWorkspaceName: "a",
            nativeWorkspaceName: "b",
            now: now,
        ))
    }

    @Test func testCloseProtectionOnlySuppressesFocusLeavingTheClosedWorkspace() {
        var protection = NativeFocusRaceProtection()
        protection.recordWindowClose(workspaceName: "a", now: now)

        #expect(!(protection.shouldSuppressAfterClose(
            currentWorkspaceName: "a",
            nativeWorkspaceName: "a",
            now: now,
        )))
        #expect(!(protection.shouldSuppressAfterClose(
            currentWorkspaceName: "b",
            nativeWorkspaceName: "c",
            now: now,
        )))
    }

    @Test func testCloseProtectionExpires() {
        var protection = NativeFocusRaceProtection()
        protection.recordWindowClose(workspaceName: "a", now: now)

        #expect(!(protection.shouldSuppressAfterClose(
            currentWorkspaceName: "a",
            nativeWorkspaceName: "b",
            now: now.advanced(by: NativeFocusRaceProtection.closeProtectionDuration),
        )))
    }

    @Test func testAppActivationDelaysCrossWorkspaceFocus() {
        var protection = NativeFocusRaceProtection()
        protection.recordAppActivation(appPid: 42, now: now)

        #expect(protection.appActivationDelay(
                appPid: 42,
                currentWorkspaceName: "a",
                nativeWorkspaceName: "b",
                now: now,
            ) == NativeFocusRaceProtection.appActivationGraceDuration)
        #expect(protection.appActivationDelay(
            appPid: 42,
            currentWorkspaceName: "a",
            nativeWorkspaceName: "a",
            now: now,
        ) == nil)
        #expect(protection.appActivationDelay(
            appPid: 7,
            currentWorkspaceName: "a",
            nativeWorkspaceName: "b",
            now: now,
        ) == nil)
    }

    @Test func testSameWorkspaceFocusClearsActivationDelay() {
        var protection = NativeFocusRaceProtection()
        protection.recordAppActivation(appPid: 42, now: now)
        protection.clearAppActivation(appPid: 42)

        #expect(protection.appActivationDelay(
            appPid: 42,
            currentWorkspaceName: "a",
            nativeWorkspaceName: "b",
            now: now,
        ) == nil)
    }

    @Test func testWorkspaceSwitchSuppressesDelayedCrossWorkspaceFocus() {
        var protection = NativeFocusRaceProtection()
        protection.recordWorkspaceSwitch(workspaceName: "b", now: now)

        #expect(protection.shouldSuppressAfterWorkspaceSwitch(
            currentWorkspaceName: "b",
            nativeWorkspaceName: "a",
            now: now,
        ))
    }

    @Test func testWorkspaceSwitchOnlyProtectsItsTarget() {
        var protection = NativeFocusRaceProtection()
        protection.recordWorkspaceSwitch(workspaceName: "b", now: now)

        #expect(!(protection.shouldSuppressAfterWorkspaceSwitch(
            currentWorkspaceName: "b",
            nativeWorkspaceName: "b",
            now: now,
        )))
        #expect(!(protection.shouldSuppressAfterWorkspaceSwitch(
            currentWorkspaceName: "c",
            nativeWorkspaceName: "a",
            now: now,
        )))
    }

    @Test func testWorkspaceSwitchProtectionExpires() {
        var protection = NativeFocusRaceProtection()
        protection.recordWorkspaceSwitch(workspaceName: "b", now: now)

        #expect(!(protection.shouldSuppressAfterWorkspaceSwitch(
            currentWorkspaceName: "b",
            nativeWorkspaceName: "a",
            now: now.advanced(by: NativeFocusRaceProtection.workspaceSwitchProtectionDuration),
        )))
    }

    @Test func testWorkspaceSwitchProtectionCanBeCancelledForMouseIntent() {
        var protection = NativeFocusRaceProtection()
        protection.recordWorkspaceSwitch(workspaceName: "b", now: now)
        protection.clearWorkspaceSwitch()

        #expect(!(protection.shouldSuppressAfterWorkspaceSwitch(
            currentWorkspaceName: "b",
            nativeWorkspaceName: "a",
            now: now,
        )))
    }

    @Test func testAppSelfActivationIsSuppressedWithoutRecentUserClick() {
        let protection = NativeFocusRaceProtection()

        #expect(protection.shouldSuppressAppSelfActivation(
            currentWorkspaceName: "1",
            nativeWorkspaceName: "W",
            now: now,
        ))
    }

    @Test func testAppSelfActivationIsAllowedAfterRecentUserClick() {
        var protection = NativeFocusRaceProtection()
        protection.recordUserClick(now: now)

        #expect(!(protection.shouldSuppressAppSelfActivation(
            currentWorkspaceName: "1",
            nativeWorkspaceName: "W",
            now: now.advanced(by: .milliseconds(500)),
        )))
    }

    @Test func testAppSelfActivationClickIntentExpires() {
        var protection = NativeFocusRaceProtection()
        protection.recordUserClick(now: now)

        #expect(protection.shouldSuppressAppSelfActivation(
            currentWorkspaceName: "1",
            nativeWorkspaceName: "W",
            now: now.advanced(by: NativeFocusRaceProtection.userClickIntentDuration),
        ))
    }

    @Test func testAppSelfActivationOnSameWorkspaceIsNeverSuppressed() {
        let protection = NativeFocusRaceProtection()

        #expect(!(protection.shouldSuppressAppSelfActivation(
            currentWorkspaceName: "1",
            nativeWorkspaceName: "1",
            now: now,
        )))
    }
}

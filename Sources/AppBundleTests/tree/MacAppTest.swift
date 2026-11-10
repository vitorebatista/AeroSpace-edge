@testable import AppBundle
import Foundation
import Testing

/// Tests for the failed-app-registration retry throttle in `MacApp`.
///
/// The full `MacApp.getOrRegister` flow can't be exercised in a unit test because it spins up a
/// real AX thread against a live `NSRunningApplication`. The throttle decision/state-machine is
/// extracted into pure, `now`-injectable helpers (`shouldThrottleFailedRegistration`,
/// `recordFailedRegistration`, `clearFailedRegistration`) so it can be verified directly.
@MainActor
@Suite(.serializedGlobally)
struct MacAppTest {
    private let pid: pid_t = 424_242

    // The pid is unique to this suite, so resetting before every test is enough (no tearDown in swift-testing structs)
    init() {
        MacApp.clearFailedRegistration(pid)
    }

    @Test func testNoThrottleWhenNoFailureRecorded() {
        // A pid that never failed registration is never throttled.
        #expect(!(MacApp.shouldThrottleFailedRegistration(pid, now: Date())))
    }

    @Test func testFailedRegistrationThrottlesImmediateRetry() {
        let now = Date()
        // First attempt fails -> throttle state is set.
        MacApp.recordFailedRegistration(pid, now: now)
        // A second immediate attempt is skipped (throttled).
        #expect(MacApp.shouldThrottleFailedRegistration(pid, now: now))
        // Still throttled just before the delay elapses.
        let justBefore = now.addingTimeInterval(MacApp.failedRegistrationRetryDelay - 0.001)
        #expect(MacApp.shouldThrottleFailedRegistration(pid, now: justBefore))
    }

    @Test func testThrottleExpiresAfterDelayAndClearsState() {
        let now = Date()
        MacApp.recordFailedRegistration(pid, now: now)
        // Once the delay has elapsed, the retry is allowed again...
        let after = now.addingTimeInterval(MacApp.failedRegistrationRetryDelay + 0.001)
        #expect(!(MacApp.shouldThrottleFailedRegistration(pid, now: after)))
        // ...and the expired throttle state is cleared as a side effect, so subsequent
        // attempts (even back at `now`) are no longer throttled.
        #expect(!(MacApp.shouldThrottleFailedRegistration(pid, now: now)))
    }

    @Test func testClearFailedRegistrationResetsThrottle() {
        let now = Date()
        MacApp.recordFailedRegistration(pid, now: now)
        #expect(MacApp.shouldThrottleFailedRegistration(pid, now: now))
        // Clearing (mirrors successful registration / destroy) lifts the throttle immediately.
        MacApp.clearFailedRegistration(pid)
        #expect(!(MacApp.shouldThrottleFailedRegistration(pid, now: now)))
    }
}

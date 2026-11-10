@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct NativeFocusTest {
    @Test func testPreCancelledJobRunsNoActions() {
        let job = RunLoopJob(.cancellable)
        job.cancel()
        var actions: [String] = []

        assertCancellation {
            try performNativeFocus(
                job: job,
                setMain: { actions.append("setMain") },
                raise: { actions.append("raise") },
                activate: { actions.append("activate") },
            )
        }

        assertEquals(actions, [])
    }

    @Test func testCancellationDuringSetMainSkipsRaiseAndActivate() {
        let job = RunLoopJob(.cancellable)
        var actions: [String] = []

        assertCancellation {
            try performNativeFocus(
                job: job,
                setMain: {
                    actions.append("setMain")
                    job.cancel()
                },
                raise: { actions.append("raise") },
                activate: { actions.append("activate") },
            )
        }

        assertEquals(actions, ["setMain"])
    }

    @Test func testCancellationDuringRaiseSkipsActivate() {
        let job = RunLoopJob(.cancellable)
        var actions: [String] = []

        assertCancellation {
            try performNativeFocus(
                job: job,
                setMain: { actions.append("setMain") },
                raise: {
                    actions.append("raise")
                    job.cancel()
                },
                activate: { actions.append("activate") },
            )
        }

        assertEquals(actions, ["setMain", "raise"])
    }

    @Test func testUncancelledJobRunsActionsOnceInOrder() throws {
        let job = RunLoopJob(.cancellable)
        var actions: [String] = []

        try performNativeFocus(
            job: job,
            setMain: { actions.append("setMain") },
            raise: { actions.append("raise") },
            activate: { actions.append("activate") },
        )

        assertEquals(actions, ["setMain", "raise", "activate"])
    }

    @Test func testSupersededJobStopsAndNewJobCompletes() throws {
        let firstJob = RunLoopJob(.cancellable)
        let secondJob = RunLoopJob(.cancellable)
        var actions: [String] = []

        assertCancellation {
            try performNativeFocus(
                job: firstJob,
                setMain: {
                    actions.append("first.setMain")
                    firstJob.cancel()
                },
                raise: { actions.append("first.raise") },
                activate: { actions.append("first.activate") },
            )
        }

        try performNativeFocus(
            job: secondJob,
            setMain: { actions.append("second.setMain") },
            raise: { actions.append("second.raise") },
            activate: { actions.append("second.activate") },
        )

        assertEquals(actions, ["first.setMain", "second.setMain", "second.raise", "second.activate"])
    }

    private func assertCancellation(
        sourceLocation: SourceLocation = #_sourceLocation,
        _ body: () throws -> Void,
    ) {
        do {
            try body()
            failExpectedActual("CancellationError", "no error thrown", sourceLocation: sourceLocation)
        } catch is CancellationError {
            // expected
        } catch {
            failExpectedActual("CancellationError", error, sourceLocation: sourceLocation)
        }
    }
}

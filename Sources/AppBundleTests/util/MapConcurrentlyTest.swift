@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct MapConcurrentlyTest {
    // Later elements finish first, the result must still follow the input order
    @Test func testPreservesOrder() async throws {
        let result = try await [30, 20, 10, 0].mapConcurrently { (ms: Int) in
            try await Task.sleep(for: .milliseconds(ms))
            return ms * 2
        }
        assertEquals(result, [60, 40, 20, 0])
    }

    @Test func testEmpty() async throws {
        assertEquals(try await [Int]().mapConcurrently { $0 }, [])
    }

    @Test func testRethrows() async {
        struct Boom: Error {}
        do {
            _ = try await [1, 2, 3].mapConcurrently { (x: Int) -> Int in
                if x == 2 { throw Boom() }
                return x
            }
            Issue.record(Comment(rawValue: "Expected an error"))
        } catch is Boom {
            // expected
        } catch {
            Issue.record(Comment(rawValue: "Unexpected error \(error)"))
        }
    }
}

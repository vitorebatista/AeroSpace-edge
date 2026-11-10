@testable import AppBundle
import Testing

@MainActor
@Suite(.serializedGlobally)
struct MenuBarItemPositionTest {
    @Test func testZeroAndNegativeLeaveThePositionToMacOs() {
        assertEquals(statusItemPositionToPersist(0), nil)
        assertEquals(statusItemPositionToPersist(-1), nil)
    }

    @Test func testAPositiveValueIsPersisted() {
        assertEquals(statusItemPositionToPersist(400), 400)
    }

    @Test func testAValueThatWouldHideTheItemIsFlagged() {
        #expect(menuBarPositionWarning(2000, screenWidth: 1512) != nil)
        #expect(menuBarPositionWarning(1313, screenWidth: 1512) != nil)
    }

    @Test func testAUsableValueIsNotFlagged() {
        assertEquals(menuBarPositionWarning(400, screenWidth: 1512), nil)
        assertEquals(menuBarPositionWarning(1312, screenWidth: 1512), nil)
        // 0 means "let macOS decide", and an unknown screen can't be judged.
        assertEquals(menuBarPositionWarning(0, screenWidth: 1512), nil)
        assertEquals(menuBarPositionWarning(2000, screenWidth: nil), nil)
    }
}

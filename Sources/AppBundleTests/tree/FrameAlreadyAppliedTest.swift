@testable import AppBundle
import Common
import XCTest

final class FrameAlreadyAppliedTest: XCTestCase {
    func testMatchingFrameIsAlreadyApplied() {
        assertTrue(isFrameAlreadyApplied(
            CGPoint(x: 10, y: 20),
            CGSize(width: 300, height: 200),
            currentTopLeft: { CGPoint(x: 10, y: 20) },
            currentSize: { CGSize(width: 300, height: 200) },
        ))
    }

    // AX frames are integral, layout may produce fractional values
    func testSubPixelDifferenceIsAlreadyApplied() {
        assertTrue(isFrameAlreadyApplied(
            CGPoint(x: 10.4, y: 19.6),
            CGSize(width: 300.5, height: 199.5),
            currentTopLeft: { CGPoint(x: 10, y: 20) },
            currentSize: { CGSize(width: 300, height: 200) },
        ))
    }

    func testDifferentPositionOrSizeIsNotApplied() {
        assertEquals(isFrameAlreadyApplied(
            CGPoint(x: 11, y: 20),
            CGSize(width: 300, height: 200),
            currentTopLeft: { CGPoint(x: 10, y: 20) },
            currentSize: { CGSize(width: 300, height: 200) },
        ), false)
        assertEquals(isFrameAlreadyApplied(
            CGPoint(x: 10, y: 20),
            CGSize(width: 301, height: 200),
            currentTopLeft: { CGPoint(x: 10, y: 20) },
            currentSize: { CGSize(width: 300, height: 200) },
        ), false)
    }

    // A failed AX read must never be mistaken for "already there"
    func testUnreadableFrameIsNotApplied() {
        assertEquals(isFrameAlreadyApplied(
            CGPoint(x: 10, y: 20),
            nil,
            currentTopLeft: { nil },
            currentSize: { CGSize(width: 300, height: 200) },
        ), false)
    }

    // Hiding in a corner moves without resizing: the size is neither compared nor read
    func testNilComponentIsNotRead() {
        assertTrue(isFrameAlreadyApplied(
            CGPoint(x: 10, y: 20),
            nil,
            currentTopLeft: { CGPoint(x: 10, y: 20) },
            currentSize: { XCTFail("size must not be read"); return nil },
        ))
    }
}

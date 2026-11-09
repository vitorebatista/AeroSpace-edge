@testable import AppBundle
import AppKit

final class TestWindow: Window, CustomStringConvertible {
    private var _rect: Rect?
    // In production, getAxRect is a real suspension point (the read is dispatched to the app AX thread), but the mock
    // returns right away. The hook is reset after the first invocation
    @MainActor var onNextGetAxRectForTest: (@MainActor () async throws -> ())?

    @MainActor
    private init(_ id: UInt32, _ parent: NonLeafTreeNodeObject, _ adaptiveWeight: CGFloat, _ rect: Rect?) {
        _rect = rect
        super.init(id: id, TestApp.shared, lastFloatingSize: nil, parent: parent, adaptiveWeight: adaptiveWeight, index: INDEX_BIND_LAST)
    }

    @discardableResult
    @MainActor
    static func new(id: UInt32, parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat = 1, rect: Rect? = nil) -> TestWindow {
        let wi = TestWindow(id, parent, adaptiveWeight, rect)
        TestApp.shared._windows.append(wi)
        return wi
    }

    nonisolated var description: String { "TestWindow(\(windowId))" }

    @MainActor
    override func nativeFocus() {
        appForTests = TestApp.shared
        TestApp.shared.focusedWindow = self
    }

    override func closeAxWindow() {
        unbindFromParent()
    }

    override var title: String {
        get async { // redundant async. todo create bug report to Swift
            description
        }
    }

    @MainActor override func getAxRect() async throws -> Rect? { // todo change to not Optional
        if let hook = onNextGetAxRectForTest {
            onNextGetAxRectForTest = nil
            try await hook()
        }
        return _rect
    }

    @MainActor override func getAxSize() async throws -> CGSize? { _rect?.size }

    override func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) {
        let cur = _rect ?? Rect(topLeftX: 0, topLeftY: 0, width: 0, height: 0)
        _rect = Rect(
            topLeftX: topLeft?.x ?? cur.topLeftX,
            topLeftY: topLeft?.y ?? cur.topLeftY,
            width: size?.width ?? cur.width,
            height: size?.height ?? cur.height,
        )
    }
}

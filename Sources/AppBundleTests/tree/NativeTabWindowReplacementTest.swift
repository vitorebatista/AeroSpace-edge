@testable import AppBundle
import Testing

@MainActor
@Suite(.serializedGlobally)
struct NativeTabWindowReplacementTest {
    init() { setUpWorkspacesForTests() }

    @Test func testReplacementPreservesNestedTreeSlotAndWeight() throws {
        let root = Workspace.get(byName: name).rootTilingContainer
        let container = TilingContainer.newHTiles(parent: root, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        TestWindow.new(id: 1, parent: container)
        let oldWindow = TestWindow.new(id: 2, parent: container, adaptiveWeight: 3)
        TestWindow.new(id: 3, parent: container)

        let replacement = takeNativeTabReplacementBinding(from: oldWindow)
        let bindingData = try #require(replacement).bindingData
        let newWindow = TestWindow.new(id: 4, parent: root)
        newWindow.bind(
            to: bindingData.parent,
            adaptiveWeight: bindingData.adaptiveWeight,
            index: bindingData.index,
        )

        assertEquals(container.layoutDescription, .h_tiles([.window(1), .window(4), .window(3)]))
        assertEquals(newWindow.getWeight(.h), 3)
    }

    @Test func testNoReplacementWhenStaleWindowIsNil() {
        let replacement = takeNativeTabReplacementBinding(from: nil)
        #expect(replacement == nil)
    }

    @Test func testNoReplacementWhenStaleWindowIsAlreadyUnbound() {
        let root = Workspace.get(byName: name).rootTilingContainer
        let window = TestWindow.new(id: 1, parent: root)
        window.unbindFromParent()

        let replacement = takeNativeTabReplacementBinding(from: window)

        #expect(replacement == nil)
    }

    @Test func testReplacementUnbindsExactlyTheGivenWindow() {
        let root = Workspace.get(byName: name).rootTilingContainer
        let untouched = TestWindow.new(id: 1, parent: root)
        let staleWindow = TestWindow.new(id: 2, parent: root)

        let replacement = takeNativeTabReplacementBinding(from: staleWindow)

        #expect(replacement != nil)
        #expect(untouched.isBound)
        #expect(!staleWindow.isBound)
    }
}

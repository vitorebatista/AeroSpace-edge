@testable import AppBundle
import Testing

@MainActor
@Suite(.serializedGlobally)
struct MenuBarTest {
    @Test func testPrimaryMenuContainsOnlyEnableSettingsAndQuit() {
        assertEquals(menuBarPrimaryActions, [.toggleEnabled, .settings, .quit])
    }

    @Test func testApplicationToolsHaveASettingsSidebarDestination() {
        #expect(SettingsCategory.allCases.contains(.application))
    }

    private func ws(
        _ name: String,
        isFocused: Bool = false,
        isEffectivelyEmpty: Bool = true,
        isVisible: Bool = false,
    ) -> WorkspaceViewModel {
        WorkspaceViewModel(
            name: name,
            suffix: "",
            isFocused: isFocused,
            isEffectivelyEmpty: isEffectivelyEmpty,
            isVisible: isVisible,
            hasFullscreenWindows: false,
        )
    }

    private func names(_ workspaces: [WorkspaceViewModel]) -> [String] { workspaces.map(\.name) }

    @Test func testMixed_persistentFirstInConfigOrderThenRestAlphabetical() {
        // Input order is intentionally shuffled to prove the comparator (not input order) drives output.
        let input = [ws("delta"), ws("2"), ws("alpha"), ws("1"), ws("charlie")]
        let result = sortWorkspacesForMenuBar(input, persistentWorkspaces: ["2", "1"])
        // Persistent first in config order ("2" before "1"), then the rest alphabetically.
        assertEquals(names(result), ["2", "1", "alpha", "charlie", "delta"])
    }

    @Test func testAllPersistent_keepConfigOrder() {
        let input = [ws("a"), ws("b"), ws("c")]
        let result = sortWorkspacesForMenuBar(input, persistentWorkspaces: ["c", "a", "b"])
        assertEquals(names(result), ["c", "a", "b"])
    }

    @Test func testNonePersistent_alphabetical() {
        let input = [ws("charlie"), ws("alpha"), ws("bravo")]
        let result = sortWorkspacesForMenuBar(input, persistentWorkspaces: [])
        assertEquals(names(result), ["alpha", "bravo", "charlie"])
    }

    @Test func testPersistentNameNotPresentInWorkspaces_isIgnored() {
        // A persistent name with no matching workspace doesn't appear and doesn't disturb ordering.
        let input = [ws("b"), ws("a")]
        let result = sortWorkspacesForMenuBar(input, persistentWorkspaces: ["z", "a"])
        // "a" is persistent (present), "b" is not -> "a" first, then "b".
        assertEquals(names(result), ["a", "b"])
    }

    @Test func testEmptyInput() {
        let result = sortWorkspacesForMenuBar([], persistentWorkspaces: ["1", "2"])
        assertEquals(names(result), [])
    }

    // MARK: - In-use / available split

    @Test func testWorkspacesWithWindowsAreInUse() {
        let (inUse, available) = partitionWorkspacesForMenuBar([
            ws("1", isEffectivelyEmpty: false),
            ws("2"),
            ws("3", isEffectivelyEmpty: false),
        ])
        assertEquals(names(inUse), ["1", "3"])
        assertEquals(names(available), ["2"])
    }

    /// A workspace you're looking at stays at the top level even with nothing on it — otherwise it would
    /// vanish into the submenu the moment its last window closed.
    @Test func testVisibleOrFocusedEmptyWorkspaceStaysInUse() {
        let (inUse, available) = partitionWorkspacesForMenuBar([
            ws("1", isVisible: true),
            ws("2", isFocused: true),
            ws("3"),
        ])
        assertEquals(names(inUse), ["1", "2"])
        assertEquals(names(available), ["3"])
    }

    @Test func testAllEmptyAndUnusedMeansEverythingIsAvailable() {
        let (inUse, available) = partitionWorkspacesForMenuBar([ws("1"), ws("2")])
        assertEquals(names(inUse), [])
        assertEquals(names(available), ["1", "2"])
    }

    /// The caller sorts before partitioning, so the split must not reshuffle either group.
    @Test func testRelativeOrderIsPreservedWithinEachGroup() {
        let (inUse, available) = partitionWorkspacesForMenuBar([
            ws("b", isEffectivelyEmpty: false),
            ws("z"),
            ws("a", isEffectivelyEmpty: false),
            ws("c"),
        ])
        assertEquals(names(inUse), ["b", "a"])
        assertEquals(names(available), ["z", "c"])
    }

    @Test func testEmptyInputIsHandled() {
        let (inUse, available) = partitionWorkspacesForMenuBar([])
        assertEquals(names(inUse), [])
        assertEquals(names(available), [])
    }
}

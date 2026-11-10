@testable import AppBundle
import Common
import Testing

/// Covers the pure row-commit logic behind the settings window's key-value list editors
/// (key mapping, env-var overrides, per-monitor gaps). These functions are the fix for a
/// real defect: the original design derived rows straight from a sorted dictionary and
/// wrote back through a `.filter { !$0.key.isEmpty }` setter, which made "Add" inert (an
/// appended empty-keyed row was filtered out immediately) and dropped any row while its
/// key was still half-typed. `dictionaryFromKeyValueRows` / `parsePerMonitorGapRows` are
/// only ever called to decide what to *write* — the on-screen `rows` array in
/// `SyncedKeyValueRows` is never rebuilt from their output, only from an external change
/// — so exercising them here pins the "incomplete rows are skipped, not deleted" contract
/// without needing a view.
@MainActor
@Suite(.serializedGlobally)
struct KeyValueRowsLogicTest {
    // MARK: - dictionaryFromKeyValueRows

    @Test func testEmptyKeyedRowIsSkipped() {
        // This is exactly what "Add" produces before the user types a key: the row must
        // not appear in the written dictionary, but the caller keeps it in `rows`.
        let rows = [KeyValueRow(key: "", value: "")]
        assertEquals(dictionaryFromKeyValueRows(rows), [:])
    }

    @Test func testHalfTypedKeyIsKeptOnceNonEmpty() {
        let rows = [KeyValueRow(key: "MY_VAR", value: "")]
        assertEquals(dictionaryFromKeyValueRows(rows), ["MY_VAR": ""])
    }

    @Test func testDuplicateKeysLastRowWins() {
        let rows = [
            KeyValueRow(key: "A", value: "first"),
            KeyValueRow(key: "A", value: "second"),
        ]
        assertEquals(dictionaryFromKeyValueRows(rows), ["A": "second"])
    }

    @Test func testMixOfCompleteAndIncompleteRows() {
        let rows = [
            KeyValueRow(key: "A", value: "1"),
            KeyValueRow(key: "", value: "orphaned value"),
            KeyValueRow(key: "B", value: "2"),
        ]
        assertEquals(dictionaryFromKeyValueRows(rows), ["A": "1", "B": "2"])
    }

    // MARK: - parsePerMonitorGapRows

    @Test func testUnparseableMonitorRowIsSkippedNotDropped() {
        // "0" isn't a valid 1-based sequence number and an unbalanced "[" isn't a valid
        // regex — either must not blow up the whole list, just be absent from what gets
        // written until the user finishes typing something valid.
        let rows = [
            KeyValueRow(key: "0", value: "10"),
            KeyValueRow(key: "[", value: "15"),
            KeyValueRow(key: "main", value: "20"),
        ]
        assertEquals(parsePerMonitorGapRows(rows), [PerMonitorValue(description: .main, value: 20)])
    }

    @Test func testUnparseableIntValueIsSkipped() {
        let rows = [KeyValueRow(key: "main", value: "not a number")]
        assertEquals(parsePerMonitorGapRows(rows), [])
    }

    @Test func testOrderIsPreserved() {
        // Order matters: `DynamicConfigValue.getValue` uses first-match-wins.
        let rows = [
            KeyValueRow(key: "secondary", value: "5"),
            KeyValueRow(key: "main", value: "10"),
        ]
        assertEquals(parsePerMonitorGapRows(rows), [
            PerMonitorValue(description: .secondary, value: 5),
            PerMonitorValue(description: .main, value: 10),
        ])
    }

    @Test func testDuplicateMonitorDescriptionsAreBothKept() {
        // Unlike a dictionary, the per-monitor list is not deduplicated by key — the
        // first rule to match a monitor wins, so preserving both rows (not collapsing
        // them) is required for that semantics to be editable at all.
        let rows = [
            KeyValueRow(key: "main", value: "10"),
            KeyValueRow(key: "main", value: "20"),
        ]
        assertEquals(parsePerMonitorGapRows(rows), [
            PerMonitorValue(description: .main, value: 10),
            PerMonitorValue(description: .main, value: 20),
        ])
    }

    // MARK: - togglePerMonitorGaps

    /// Covers a real defect found in review: toggling "Per monitor" off then back on used
    /// to silently discard every rule but one (off collapsed straight to `.constant`, on
    /// rebuilt only a single synthetic `main` rule from the fallback). These pin the fix —
    /// off hands the rules back as `rememberedRules` instead of dropping them, and on
    /// restores them verbatim when there's something to restore.

    @Test func testTurningOffRemembersRulesAndWritesAConstant() {
        let current = DynamicConfigValue.perMonitor(
            [PerMonitorValue(description: .main, value: 20), PerMonitorValue(description: .secondary, value: 10)],
            default: 5,
        )
        let result = togglePerMonitorGaps(isPerMonitor: false, current: current, rememberedRules: [])
        assertEquals(result.value, .constant(5))
        assertEquals(result.rememberedRules, [
            PerMonitorValue(description: .main, value: 20),
            PerMonitorValue(description: .secondary, value: 10),
        ])
    }

    @Test func testTurningBackOnRestoresRememberedRulesInsteadOfASyntheticOne() {
        let remembered = [PerMonitorValue(description: .main, value: 20), PerMonitorValue(description: .secondary, value: 10)]
        let result = togglePerMonitorGaps(isPerMonitor: true, current: .constant(5), rememberedRules: remembered)
        assertEquals(result.value, .perMonitor(remembered, default: 5))
        // The full round trip from the review's example: main=20, secondary=10, default=5
        // survives off→on intact, not collapsed to main=5, default=5.
        assertEquals(result.value, .perMonitor(
            [PerMonitorValue(description: .main, value: 20), PerMonitorValue(description: .secondary, value: 10)],
            default: 5,
        ))
    }

    @Test func testTurningOnWithNothingRememberedBuildsASingleSyntheticMainRule() {
        // First-ever enable, or after the state that used to lose everything: falls back
        // to one rule seeded from the current constant, same as the original behavior.
        let result = togglePerMonitorGaps(isPerMonitor: true, current: .constant(7), rememberedRules: [])
        assertEquals(result.value, .perMonitor([PerMonitorValue(description: .main, value: 7)], default: 7))
    }

    @Test func testMismatchedToggleStateIsANoOp() {
        // Turning "on" a field that's already per-monitor, or "off" one that's already
        // constant, can't happen from the checkbox itself but must not corrupt state.
        let perMonitor = DynamicConfigValue.perMonitor([PerMonitorValue(description: .main, value: 1)], default: 1)
        let onAlreadyOn = togglePerMonitorGaps(isPerMonitor: true, current: perMonitor, rememberedRules: [])
        assertEquals(onAlreadyOn.value, perMonitor)
        assertEquals(onAlreadyOn.rememberedRules, [])

        let offAlreadyOff = togglePerMonitorGaps(isPerMonitor: false, current: .constant(3), rememberedRules: [])
        assertEquals(offAlreadyOff.value, .constant(3))
        assertEquals(offAlreadyOff.rememberedRules, [])
    }
}

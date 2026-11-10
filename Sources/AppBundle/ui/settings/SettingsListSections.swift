import Common
import OrderedCollections
import SwiftUI

// MARK: - Shared row editor

/// One editable row in a `KeyValueRowsEditor`. Identity is independent of the text, so a
/// row that is empty or momentarily identical to another keeps its own place in the list
/// instead of being merged or dropped — see `SyncedKeyValueRows`.
struct KeyValueRow: Identifiable, Equatable {
    let id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}

/// A plain add/remove/edit list of key-value text rows.
///
/// This view knows nothing about how `rows` maps onto a config value — that mapping, and
/// the "never lose a half-typed row" contract, lives in `SyncedKeyValueRows`, its only
/// caller. Keeping this view dumb is what makes it reusable across the key-mapping,
/// env-var, and per-monitor-gap editors without dragging their individual parsing rules
/// in here.
@MainActor
struct KeyValueRowsEditor: View {
    let keyPlaceholder: String
    let valuePlaceholder: String
    @Binding var rows: [KeyValueRow]
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach($rows) { $row in
                HStack {
                    TextField(keyPlaceholder, text: $row.key)
                        .onChange(of: row.key) { _ in onEdit() }
                    Text("=").foregroundStyle(.secondary)
                    TextField(valuePlaceholder, text: $row.value)
                        .onChange(of: row.value) { _ in onEdit() }
                    Button(role: .destructive) {
                        rows.removeAll { $0.id == row.id }
                        onEdit()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button("Add") { rows.append(KeyValueRow(key: "", value: "")); onEdit() }
                .buttonStyle(.borderless)
        }
    }
}

/// Bridges a `KeyValueRowsEditor`'s local row state to a draft field that can change out
/// from under it — Revert, or a reload after Save — while the pane stays open.
///
/// The rows are edited completely locally (`rows == nil` until first touched, after
/// which it is the sole source of what's on screen) and are never rebuilt from the draft
/// just because a keystroke changed it, so a half-typed or empty-keyed row never
/// vanishes and an "Add" always produces a visible new row. On every edit, `write` is
/// called with `valueFor(rows)` — skipping whatever `valueFor` can't make sense of
/// without deleting it from `rows`. Because the draft is always set to exactly that
/// value, comparing the draft's current value against `valueFor(rows)` distinguishes
/// "we just wrote this ourselves" (no-op) from "something external changed it," which is
/// exactly what happens on Revert or a post-Save reload while this view is still on
/// screen — in that case `rowsFor(newValue)` reseeds the rows for real.
@MainActor
struct SyncedKeyValueRows<Value: Equatable>: View {
    let keyPlaceholder: String
    let valuePlaceholder: String
    let read: () -> Value
    let write: (Value) -> Void
    let rowsFor: (Value) -> [KeyValueRow]
    let valueFor: ([KeyValueRow]) -> Value
    let onEdit: () -> Void

    @State private var rows: [KeyValueRow]?

    var body: some View {
        KeyValueRowsEditor(
            keyPlaceholder: keyPlaceholder,
            valuePlaceholder: valuePlaceholder,
            rows: Binding(
                get: { rows ?? rowsFor(read()) },
                set: { newRows in
                    rows = newRows
                    let newValue = valueFor(newRows)
                    if newValue != read() { write(newValue) }
                },
            ),
            onEdit: onEdit,
        )
        .onChange(of: read()) { newValue in
            if let rows, newValue == valueFor(rows) { return } // our own write, echoed back
            rows = rowsFor(newValue)
        }
    }
}

/// Turns key-value text rows into the dictionary the draft stores, skipping any row
/// whose key is empty. Pure and separate from the view on purpose: it decides what gets
/// *written*, and never touches `rows` itself, so it can't be the reason a row the user
/// is still typing disappears from the screen (only `SyncedKeyValueRows.write` writes
/// back into a `@State`, and only ever with rows the caller already has). Duplicate keys
/// keep the last row's value, matching how a real TOML table would parse.
func dictionaryFromKeyValueRows(_ rows: [KeyValueRow]) -> [String: String] {
    Dictionary(rows.filter { !$0.key.isEmpty }.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
}

/// Parses per-monitor gap rows into rules, in order, skipping any row whose monitor text
/// or gap value doesn't currently parse (e.g. mid-typing) without touching `rows`.
func parsePerMonitorGapRows(_ rows: [KeyValueRow]) -> [PerMonitorValue<Int>] {
    rows.compactMap { row in
        guard let description = parseMonitorDescription(row.key).getIgnoringErrorsOrNil(), let int = Int(row.value) else { return nil }
        return PerMonitorValue(description: description, value: int)
    }
}

/// The text spelling of a monitor description, matching what the config file accepts.
@MainActor
func monitorDescriptionText(_ description: MonitorDescription) -> String {
    switch description {
        case .main: "main"
        case .secondary: "secondary"
        case .sequenceNumber(let number): String(number)
        case .pattern(let regex): regex.origin
    }
}

/// Decides the next value for the "Per monitor" checkbox, and what to remember about the
/// per-monitor rules afterward.
///
/// Turning per-monitor off never discards `current`'s rules — the file only ever stores a
/// `.constant` once it's off, but the rules are handed back as `rememberedRules` for the
/// caller to hold (in `@State`, since the row editor itself gets torn down while hidden).
/// Turning it back on restores those verbatim, rather than rebuilding a single synthetic
/// `main` rule from the fallback — the fix for a real defect where a toggle off→on round
/// trip silently dropped every rule but one.
func togglePerMonitorGaps(
    isPerMonitor: Bool,
    current: DynamicConfigValue<Int>,
    rememberedRules: [PerMonitorValue<Int>],
) -> (value: DynamicConfigValue<Int>, rememberedRules: [PerMonitorValue<Int>]) {
    switch (isPerMonitor, current) {
        case (true, .constant(let int)):
            let rules = rememberedRules.isEmpty ? [PerMonitorValue(description: .main, value: int)] : rememberedRules
            return (.perMonitor(rules, default: int), rememberedRules)
        case (false, .perMonitor(let rules, let fallback)):
            return (.constant(fallback), rules)
        default:
            return (current, rememberedRules)
    }
}

// MARK: - Gaps

@MainActor
struct GapsSection: View {
    @Binding var draft: ConfigTomlWriter.ConfigDraft
    /// Forwarded to each `GapRow` so it can tell a Revert (or the reload after a
    /// successful Save) apart from its own edits — see `GapRow.lastKnownRules`.
    let loadGeneration: Int
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup("Inner gaps", footer: "Space between tiled windows.") {
                GapRow(label: "Horizontal", draft: $draft, path: \.inner.horizontal, loadGeneration: loadGeneration, onEdit: onEdit)
                GapRow(label: "Vertical", draft: $draft, path: \.inner.vertical, loadGeneration: loadGeneration, onEdit: onEdit)
            }
            SettingsGroup("Outer gaps", footer: "Space between the tiling area and the screen edges.") {
                GapRow(label: "Left", draft: $draft, path: \.outer.left, loadGeneration: loadGeneration, onEdit: onEdit)
                GapRow(label: "Right", draft: $draft, path: \.outer.right, loadGeneration: loadGeneration, onEdit: onEdit)
                GapRow(label: "Top", draft: $draft, path: \.outer.top, loadGeneration: loadGeneration, onEdit: onEdit)
                GapRow(label: "Bottom", draft: $draft, path: \.outer.bottom, loadGeneration: loadGeneration, onEdit: onEdit)
            }
        }
    }
}

/// One gap value: a number, plus optional per-monitor overrides. A per-monitor gap is a
/// list of monitor patterns with a fallback, so the row grows into a small list when "Per
/// monitor" is enabled.
///
/// A real `View` (not a `@ViewBuilder` function) so each of the six gap fields gets its
/// own `@State`, independent of the other five — needed for `lastKnownRules` below.
@MainActor
private struct GapRow: View {
    let label: String
    @Binding var draft: ConfigTomlWriter.ConfigDraft
    let path: WritableKeyPath<Gaps, DynamicConfigValue<Int>>
    let loadGeneration: Int
    let onEdit: () -> Void

    /// Remembered across a "Per monitor" toggle off→on round trip — see
    /// `togglePerMonitorGaps`. Lives here, not in the per-monitor row editor below,
    /// because that editor is unmounted (and its own state destroyed) the moment the
    /// toggle goes off.
    ///
    /// This is exactly the kind of state `SyncedKeyValueRows` guards against going stale
    /// via its own `.onChange(of: read())` — but there, "did we write this ourselves"
    /// can be answered by comparing the source's value to what our own commit would
    /// produce. Here it can't: turning per-monitor off always writes the *same*
    /// `.constant(fallback)` a Revert could also reload, so no value comparison can
    /// tell "I just wrote this" apart from "the document came back looking the same by
    /// coincidence" (see `SettingsModel.loadGeneration`'s doc comment for the concrete
    /// scenario this defends against). `loadGeneration` sidesteps the ambiguity by
    /// making the reload itself the signal, independent of whether the reloaded value
    /// happens to match.
    @State private var lastKnownRules: [PerMonitorValue<Int>] = []

    var body: some View {
        let value = draft.gaps[keyPath: path]
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SettingHelpLabel(title: label, topic: gapTopic)
                    .frame(width: 110, alignment: .leading)
                switch value {
                    case .constant(let int):
                        Stepper("\(int)", value: Binding(
                            get: { int },
                            set: { draft.gaps[keyPath: path] = .constant($0); onEdit() },
                        ), in: 0 ... 400, step: 2)
                    case .perMonitor(_, let fallback):
                        Stepper("default \(fallback)", value: Binding(
                            get: { fallback },
                            set: {
                                guard case .perMonitor(let rules, _) = draft.gaps[keyPath: path] else { return }
                                draft.gaps[keyPath: path] = .perMonitor(rules, default: $0)
                                onEdit()
                            },
                        ), in: 0 ... 400, step: 2)
                }
                Toggle(isOn: Binding(
                    get: { if case .perMonitor = value { true } else { false } },
                    set: { isPerMonitor in
                        let result = togglePerMonitorGaps(
                            isPerMonitor: isPerMonitor,
                            current: draft.gaps[keyPath: path],
                            rememberedRules: lastKnownRules,
                        )
                        draft.gaps[keyPath: path] = result.value
                        lastKnownRules = result.rememberedRules
                        onEdit()
                    },
                )) {
                    SettingHelpLabel(title: "Per monitor", topic: .perMonitorGaps)
                }
                .toggleStyle(.checkbox)
            }
            if case .perMonitor = value {
                SyncedKeyValueRows(
                    keyPlaceholder: "main / secondary / 2 / regex",
                    valuePlaceholder: "gap",
                    read: {
                        if case .perMonitor(let rules, _) = draft.gaps[keyPath: path] { rules } else { [] }
                    },
                    write: { newRules in
                        guard case .perMonitor(_, let fallback) = draft.gaps[keyPath: path] else { return }
                        draft.gaps[keyPath: path] = .perMonitor(newRules, default: fallback)
                    },
                    rowsFor: { rules in
                        rules.map { KeyValueRow(key: monitorDescriptionText($0.description), value: String($0.value)) }
                    },
                    valueFor: parsePerMonitorGapRows,
                    onEdit: onEdit,
                )
                .padding(.leading, 118)
            }
        }
        .onChange(of: loadGeneration) { _ in
            // The document was reloaded (Revert, or the reload after a successful Save) —
            // whatever this field's memory referred to may no longer exist, even if the
            // reloaded value happens to read the same. Drop it rather than risk
            // resurrecting rules the user just discarded.
            lastKnownRules = []
        }
    }

    private var gapTopic: SettingHelpTopic {
        path == \Gaps.inner.horizontal || path == \Gaps.inner.vertical ? .innerGaps : .outerGaps
    }
}

// MARK: - Workspaces & Monitors

@MainActor
struct WorkspacesSection: View {
    @Binding var draft: ConfigTomlWriter.ConfigDraft
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup("Persistent workspaces", footer: "These always exist, in this order, even when empty.") {
                SettingHelpLabel(title: "Workspace list", topic: .persistentWorkspaces)
                PersistentWorkspacesEditor(draft: $draft, onEdit: onEdit)
            }
            SettingsGroup(
                "Force a workspace onto a monitor",
                footer: "A monitor is 'main', 'secondary', a 1-based number, or a regex matched against the monitor name. Separate several with a comma to give a priority order.",
            ) {
                SettingHelpLabel(title: "Workspace and monitor priority", topic: .workspaceMonitorAssignment)
                SyncedKeyValueRows(
                    keyPlaceholder: "workspace",
                    valuePlaceholder: "main, secondary, 2, regex",
                    read: { draft.workspaceToMonitorForceAssignment },
                    write: { draft.workspaceToMonitorForceAssignment = $0 },
                    rowsFor: { dict in
                        dict.sorted { $0.key < $1.key }
                            .map { KeyValueRow(key: $0.key, value: $0.value.map(monitorDescriptionText).joined(separator: ", ")) }
                    },
                    valueFor: { rows in
                        var result: [String: [MonitorDescription]] = [:]
                        for row in rows where !row.key.isEmpty {
                            let parsed = row.value
                                .split(separator: ",")
                                .compactMap { parseMonitorDescription($0.trimmingCharacters(in: .whitespaces)).getIgnoringErrorsOrNil() }
                            // Skip, don't drop: a half-typed monitor parses to nothing, and
                            // committing that empty list would assign the workspace to no
                            // monitor at all rather than leaving it as it was.
                            if !parsed.isEmpty { result[row.key] = parsed }
                        }
                        return result
                    },
                    onEdit: onEdit,
                )
            }
        }
    }
}

/// The persistent-workspaces list: an ordered, reorderable set of names.
///
/// Edited under the same rule as `SyncedKeyValueRows` — local row state (with its own
/// identity per row, independent of the name text) that a half-typed or momentarily
/// duplicate name survives. `OrderedSet` collapses duplicates, but that collapse only
/// happens in `valueFor`, at commit time; the on-screen `rows` array is a plain array
/// that never dedupes, so two rows that briefly hold the same text stay two rows.
@MainActor
private struct PersistentWorkspacesEditor: View {
    @Binding var draft: ConfigTomlWriter.ConfigDraft
    let onEdit: () -> Void

    private struct Row: Identifiable, Equatable {
        let id: UUID
        var name: String
        init(id: UUID = UUID(), name: String) { self.id = id; self.name = name }
    }

    @State private var rows: [Row]?

    var body: some View {
        let currentRows = rows ?? Self.rowsFor(draft.persistentWorkspaces)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(currentRows.enumerated()), id: \.element.id) { index, row in
                HStack {
                    TextField("name", text: Binding(
                        get: { row.name },
                        set: { newName in
                            var updated = currentRows
                            updated[index].name = newName
                            commit(updated)
                        },
                    ))
                    Button { commit(moved(currentRows, index, by: -1)) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.borderless).disabled(index == 0)
                    Button { commit(moved(currentRows, index, by: 1)) } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.borderless).disabled(index == currentRows.count - 1)
                    Button(role: .destructive) {
                        var updated = currentRows
                        updated.remove(at: index)
                        commit(updated)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button("Add") { commit(currentRows + [Row(name: "")]) }
                .buttonStyle(.borderless)
        }
        .onChange(of: draft.persistentWorkspaces) { newValue in
            if let rows, newValue == Self.valueFor(rows) { return } // our own write, echoed back
            rows = Self.rowsFor(newValue)
        }
    }

    private func commit(_ newRows: [Row]) {
        rows = newRows
        let newValue = Self.valueFor(newRows)
        if newValue != draft.persistentWorkspaces { draft.persistentWorkspaces = newValue }
        onEdit()
    }

    private func moved(_ rows: [Row], _ index: Int, by offset: Int) -> [Row] {
        var rows = rows
        let target = index + offset
        guard rows.indices.contains(target) else { return rows }
        rows.swapAt(index, target)
        return rows
    }

    private static func rowsFor(_ names: OrderedSet<String>) -> [Row] { names.map { Row(name: $0) } }
    /// Empty rows are dropped, the same way `dictionaryFromKeyValueRows` drops an
    /// empty key: a freshly-added row the user hasn't named yet is still on screen (it
    /// lives in `rows`), but committing it would write `persistent-workspaces = ['']`,
    /// which `parsePersistentWorkspaces` has no name validation to reject.
    private static func valueFor(_ rows: [Row]) -> OrderedSet<String> {
        OrderedSet(rows.map(\.name).filter { !$0.isEmpty })
    }
}

// MARK: - Key Mapping

@MainActor
struct KeyMappingSection: View {
    @Binding var draft: ConfigTomlWriter.ConfigDraft
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup("Preset", footer: "The keyboard layout your key notations are written for.") {
                Picker(selection: tracked($draft.keyMappingPreset, onEdit)) {
                    ForEach(KeyMapping.Preset.allCases, id: \.rawValue) { preset in
                        Text(preset.rawValue.capitalized).tag(preset)
                    }
                } label: {
                    SettingHelpLabel(title: "Preset", topic: .keyMappingPreset)
                }
                .pickerStyle(.radioGroup)
            }
            SettingsGroup(
                "Notation overrides",
                footer: "Left: your own notation — no spaces, no dashes. Right: a key code AeroSpace knows, such as 'quote' or 'semicolon'.",
            ) {
                SettingHelpLabel(title: "Custom notation mapping", topic: .keyNotationOverrides)
                SyncedKeyValueRows(
                    keyPlaceholder: "notation",
                    valuePlaceholder: "key code",
                    read: { draft.keyNotationToKeyCode },
                    write: { draft.keyNotationToKeyCode = $0 },
                    rowsFor: { dict in dict.sorted { $0.key < $1.key }.map { KeyValueRow(key: $0.key, value: $0.value) } },
                    valueFor: dictionaryFromKeyValueRows,
                    onEdit: onEdit,
                )
            }
        }
    }
}

// MARK: - Exec

@MainActor
struct ExecSection: View {
    @Binding var draft: ConfigTomlWriter.ConfigDraft
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup("Environment", footer: "Applies to every 'exec-and-forget' command.") {
                Toggle(isOn: tracked($draft.inheritEnvVars, onEdit)) {
                    SettingHelpLabel(title: "Inherit environment variables from the launching process", topic: .inheritEnvVars)
                }
            }
            SettingsGroup(
                "Overrides",
                footer: "Use $VAR to interpolate the inherited value. 'PWD' can't be changed and will be rejected on save.",
            ) {
                SettingHelpLabel(title: "Environment variable overrides", topic: .envVarOverrides)
                SyncedKeyValueRows(
                    keyPlaceholder: "NAME",
                    valuePlaceholder: "value",
                    read: { draft.envVars },
                    write: { draft.envVars = $0 },
                    rowsFor: { dict in dict.sorted { $0.key < $1.key }.map { KeyValueRow(key: $0.key, value: $0.value) } },
                    valueFor: dictionaryFromKeyValueRows,
                    onEdit: onEdit,
                )
            }
        }
    }
}

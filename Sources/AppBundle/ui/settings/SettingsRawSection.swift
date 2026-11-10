import Common
import SwiftUI

/// A raw TOML editor for one family of config keys — keybindings, window rules, or
/// callbacks. These are an AeroSpace command DSL rather than a fixed set of values, so
/// they are edited as text; the parser is the validator.
///
/// The parse check only ever covers *this pane's own text* (plus an optional
/// `preamble`, see below), never the whole config — so it is advisory, not
/// authoritative. `SettingsModel.save()`'s temp-file validation against the real,
/// complete document is what actually decides whether a save is accepted; the pane just
/// tries to surface an obvious mistake before that point.
@MainActor
struct SettingsRawSection: View {
    let title: String
    let help: String
    let docsHint: String
    @Binding var text: String
    /// TOML prepended before parsing (only for parsing — never shown in the editor and
    /// never written to the file). Supplies config state the pane's own text fragment
    /// doesn't carry on its own; see `keybindingsPreamble`. Defaults to none for panes
    /// whose text is fully self-contained.
    let preamble: String
    let onEdit: () -> Void

    /// Parse feedback for `preamble + text`, recomputed only on edit (via `.onChange`
    /// below) rather than on every view update, which a computed property read from
    /// `body` would do.
    @State private var parseStatus: Result<Void, String>

    init(title: String, help: String, docsHint: String, text: Binding<String>, preamble: String = "", onEdit: @escaping () -> Void) {
        self.title = title
        self.help = help
        self.docsHint = docsHint
        self._text = text
        self.preamble = preamble
        self.onEdit = onEdit
        self._parseStatus = State(initialValue: parseRawSectionFragment(preamble: preamble, text: text.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroup(title, footer: help) {
                Text(docsHint).font(.caption).foregroundStyle(.secondary)
            }
            TomlTextEditor(text: Binding(get: { text }, set: { text = $0; onEdit() }))
                .frame(minHeight: 300)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(.separatorColor)))
            switch parseStatus {
                case .success:
                    Label("This section parses on its own", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                case .failure(let message):
                    ScrollView {
                        Text(message).font(.caption.monospaced()).foregroundStyle(.red).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 100)
            }
            // The check above only ever sees this pane's own text (plus `preamble`), so
            // it can't catch a mistake that only shows up once this section is combined
            // with the rest of the file. Say so plainly rather than let "parses" read as
            // a final answer.
            Text("Checked as its own fragment — Save validates the whole config file.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .onChange(of: text) { _ in revalidate() }
        .onChange(of: preamble) { _ in revalidate() }
    }

    private func revalidate() { parseStatus = parseRawSectionFragment(preamble: preamble, text: text) }
}

/// Parses `preamble + text` with the real config parser and reports whether it's clean.
/// Pulled out of the view so it's plain, testable logic: given the same two strings, it
/// always reports the same thing.
@MainActor
func parseRawSectionFragment(preamble: String, text: String) -> Result<Void, String> {
    let errors = parseConfig(preamble + text).errorMessages // warnings don't make a fragment invalid
    return errors.isEmpty ? .success(()) : .failure(errors.joined(separator: "\n\n"))
}

/// The `[key-mapping]` table implied by the draft, synthesized so the Keybindings pane's
/// parse check resolves key notations the same way the real config does.
/// `document.text(forTablesMatching:)` only ever hands the pane the `[mode.*]` tables —
/// `[key-mapping]` lives in a separate section of the form — so without this preamble,
/// two things could go wrong when parsing the pane's text alone:
///
/// - `notationOverrides` (`[key-mapping.key-notation-to-key-code]`) is where this
///   actually bites: it lets a user name a custom notation (e.g. `zz`) for a binding.
///   Without the override table present, that notation isn't in *any* preset's map, so
///   `alt-zz = '...'` — perfectly valid in the real file — reports a false "Can't parse
///   the key" error here.
/// - `preset` is included too, for defense in depth, even though today's three preset
///   tables (`keysMap.swift`) happen to share the exact same set of notation strings and
///   only differ in which physical key each one resolves to — so on its own, a plain
///   dvorak/colemak notation never actually fails to parse for lack of this. It costs
///   nothing to include and stays correct if that ever changes.
///
/// Window rules and callbacks don't need an equivalent: their `run` / callback values go
/// through `parseCommandOrCommands` → `parseCommand`, which parses each command as a
/// self-contained CLI-style argument list with no dependency on key mapping, modes, or
/// any other table (mode/workspace names referenced by a command, e.g. `mode main` or
/// `move-node-to-workspace foo`, are resolved at run time, not at parse time).
@MainActor
func keybindingsPreamble(preset: KeyMapping.Preset, notationOverrides: [String: String]) -> String {
    var body = "[key-mapping]\npreset = \(TomlValue.of(preset.rawValue))\n"
    if !notationOverrides.isEmpty {
        body += "\n[key-mapping.key-notation-to-key-code]\n"
        for (notation, code) in notationOverrides.sorted(by: { $0.key < $1.key }) {
            // Key notation only forbids whitespace and `-`, so a valid custom notation
            // can still contain TOML-significant characters such as a dot or quote. Use
            // the same key serializer as the writer or the pane feedback can reject a
            // binding that the eventual saved config accepts.
            body += "\(TomlValue.key(notation)) = \(TomlValue.of(code))\n"
        }
    }
    return body
}

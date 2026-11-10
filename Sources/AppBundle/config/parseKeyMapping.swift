import Common
import HotKey

private let keyMappingParser: [String: any ParserProtocol<KeyMapping>] = [
    "preset": Parser(\.preset, parsePreset),
    "key-notation-to-key-code": Parser(\.rawKeyNotationToKeyCode, parseKeyNotationToKeyCode),
]

struct KeyMapping: Withable, Equatable, Sendable {
    enum Preset: String, CaseIterable, Sendable {
        case qwerty, dvorak, colemak
    }

    init(
        preset: Preset = .qwerty,
        rawKeyNotationToKeyCode: [String: Key] = [:],
    ) {
        self.preset = preset
        self.rawKeyNotationToKeyCode = rawKeyNotationToKeyCode
    }

    fileprivate var preset: Preset = .qwerty
    fileprivate var rawKeyNotationToKeyCode: [String: Key] = [:]

    func resolve() -> [String: Key] {
        getKeysPreset(preset) + rawKeyNotationToKeyCode
    }
}

/// The settings window uses `Preset` as a SwiftUI `Picker` tag, which requires
/// `Hashable`. Declared next to the type rather than in the UI layer.
extension KeyMapping.Preset: Hashable {}

func parseKeyMapping(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> KeyMapping {
    parseNonEmptyTable(raw, KeyMapping(), keyMappingParser, backtrace, &c)
}

private func parsePreset(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<KeyMapping.Preset> {
    parseString(raw, backtrace).flatMap { parseEnum($0, KeyMapping.Preset.self).toParsedConfig(backtrace) }
}

private func parseKeyNotationToKeyCode(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> [String: Key] {
    var result: [String: Key] = [:]
    guard let table = raw.asDictOrNil else {
        c.errors.append(expectedActualTypeDiagnostic(expected: .table, actual: raw.tomlType, backtrace))
        return result
    }
    for (key, value): (String, OrderedJson) in table {
        if isValidKeyNotation(key) {
            let backtrace = backtrace + .key(key)
            if let value = parseString(value, backtrace).getOrNil(appendErrorTo: &c.errors) {
                switch keyNotationToKeyCode[value] {
                    case let value?: result[key] = value
                    case nil: c.errors.append(.init(backtrace, "\(value.singleQuoted) is invalid key code"))
                }
            }
        } else {
            c.errors.append(.init(backtrace, "\(key.singleQuoted) is invalid key notation"))
        }
    }
    return result
}

private func isValidKeyNotation(_ str: String) -> Bool {
    str.rangeOfCharacter(from: .whitespacesAndNewlines) == nil && !str.contains("-")
}

extension KeyMapping {
    /// Read-only accessors for the settings window. `preset` and the raw notation map are
    /// `fileprivate` so that nothing else can bypass `resolve()`.
    var presetForSettings: Preset { preset }

    /// The raw overrides as key-code *names*, which is how they are written in the config
    /// file. `rawKeyNotationToKeyCode` holds resolved `Key` values, so this inverts
    /// `keyNotationToKeyCode` to recover the name.
    var rawNotationNamesForSettings: [String: String] {
        var nameByKey: [Key: String] = [:]
        for (name, key) in keyNotationToKeyCode where nameByKey[key] == nil { nameByKey[key] = name }
        return rawKeyNotationToKeyCode.compactMapValues { nameByKey[$0] }
    }
}

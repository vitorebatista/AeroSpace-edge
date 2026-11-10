import Common
import OrderedCollections

/// Maps the settings window's draft state onto a `TomlBlockDocument`.
///
/// This is the single place that knows the TOML spelling of every option, so adding an
/// option to the window means touching this file and `SettingsSections.swift` and
/// nothing else.
enum ConfigTomlWriter {
    /// The editable settings state.
    ///
    /// This is not `Config` because two parts of `Config` are not round-trippable:
    /// `execConfig` is the *expanded* environment (writing it back would bake the whole
    /// inherited process environment into the user's file), and the callbacks are
    /// `[any Command]`. Those live here as raw file-shaped values instead.
    struct ConfigDraft: Withable, Equatable {
        var startAtLogin: Bool
        var autoReloadConfig: Bool
        var automaticallyUnhideMacosHiddenApps: Bool
        var enableNormalizationFlattenContainers: Bool
        var enableNormalizationOppositeOrientationForNestedContainers: Bool
        var enableNormalizationBinaryTree: Bool
        var defaultRootContainerLayout: Layout
        var defaultRootContainerOrientation: DefaultContainerOrientation
        var accordionPadding: Int
        var focusFollowsAppActivation: FocusFollowsAppActivation
        var newWindowPreventFlicker: Bool
        var focusedWindowBorder: Bool
        var focusedWindowBorderColor: String
        var focusedWindowBorderWidth: Int
        var focusedWindowBorderOpacity: Int
        var focusedWindowBorderRadius: Int
        var focusedWindowBorderInset: Int
        var configVersion: Int
        var persistentWorkspaces: OrderedSet<String>
        var gaps: Gaps
        var workspaceToMonitorForceAssignment: [String: [MonitorDescription]]
        var keyMappingPreset: KeyMapping.Preset
        var keyNotationToKeyCode: [String: String] // notation -> key-code NAME, as written in the file
        var inheritEnvVars: Bool
        var envVars: [String: String]
        var rawKeybindings: String
        var rawWindowRules: String
        var rawCallbacks: String

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.startAtLogin == rhs.startAtLogin &&
                lhs.autoReloadConfig == rhs.autoReloadConfig &&
                lhs.automaticallyUnhideMacosHiddenApps == rhs.automaticallyUnhideMacosHiddenApps &&
                lhs.enableNormalizationFlattenContainers == rhs.enableNormalizationFlattenContainers &&
                lhs.enableNormalizationOppositeOrientationForNestedContainers == rhs.enableNormalizationOppositeOrientationForNestedContainers &&
                lhs.enableNormalizationBinaryTree == rhs.enableNormalizationBinaryTree &&
                lhs.defaultRootContainerLayout.rawValue == rhs.defaultRootContainerLayout.rawValue &&
                lhs.defaultRootContainerOrientation.rawValue == rhs.defaultRootContainerOrientation.rawValue &&
                lhs.accordionPadding == rhs.accordionPadding &&
                lhs.focusFollowsAppActivation.rawValue == rhs.focusFollowsAppActivation.rawValue &&
                lhs.newWindowPreventFlicker == rhs.newWindowPreventFlicker &&
                lhs.focusedWindowBorder == rhs.focusedWindowBorder &&
                lhs.focusedWindowBorderColor == rhs.focusedWindowBorderColor &&
                lhs.focusedWindowBorderWidth == rhs.focusedWindowBorderWidth &&
                lhs.focusedWindowBorderOpacity == rhs.focusedWindowBorderOpacity &&
                lhs.focusedWindowBorderRadius == rhs.focusedWindowBorderRadius &&
                lhs.focusedWindowBorderInset == rhs.focusedWindowBorderInset &&
                lhs.configVersion == rhs.configVersion &&
                lhs.persistentWorkspaces == rhs.persistentWorkspaces &&
                lhs.gaps == rhs.gaps &&
                lhs.workspaceToMonitorForceAssignment == rhs.workspaceToMonitorForceAssignment &&
                lhs.keyMappingPreset.rawValue == rhs.keyMappingPreset.rawValue &&
                lhs.keyNotationToKeyCode == rhs.keyNotationToKeyCode &&
                lhs.inheritEnvVars == rhs.inheritEnvVars &&
                lhs.envVars == rhs.envVars &&
                lhs.rawKeybindings == rhs.rawKeybindings &&
                lhs.rawWindowRules == rhs.rawWindowRules &&
                lhs.rawCallbacks == rhs.rawCallbacks
        }
    }

    // MARK: - Table ownership

    static func isKeybindingTable(_ name: String) -> Bool { name == "mode" || name.hasPrefix("mode.") }
    static func isWindowRuleTable(_ name: String) -> Bool { name == "on-window-detected" }

    /// The top-level keys the Callbacks pane owns.
    static let callbackKeys = [
        "after-startup-command",
        "on-focus-changed",
        "on-mode-changed",
        "on-focused-monitor-changed",
        "exec-on-workspace-change",
    ]

    /// The nested tables the form models completely and therefore regenerates wholesale —
    /// but only when one of the fields feeding them actually changed, see `apply`. Kept as
    /// a list so the set the docs promise is greppable from one place.
    static let regeneratedTables = ["gaps", "key-mapping", "exec", "workspace-to-monitor-force-assignment"]

    // MARK: - Reading a draft out of a parsed config + the document

    @MainActor static func draft(from config: Config, rawExec: RawExecConfig, document: TomlBlockDocument) -> ConfigDraft {
        ConfigDraft(
            startAtLogin: config.startAtLogin,
            autoReloadConfig: config.autoReloadConfig,
            automaticallyUnhideMacosHiddenApps: config.automaticallyUnhideMacosHiddenApps,
            enableNormalizationFlattenContainers: config.enableNormalizationFlattenContainers,
            enableNormalizationOppositeOrientationForNestedContainers: config.enableNormalizationOppositeOrientationForNestedContainers,
            enableNormalizationBinaryTree: config.enableNormalizationBinaryTree,
            defaultRootContainerLayout: config.defaultRootContainerLayout,
            defaultRootContainerOrientation: config.defaultRootContainerOrientation,
            accordionPadding: config.accordionPadding,
            focusFollowsAppActivation: config.focusFollowsAppActivation,
            newWindowPreventFlicker: config.newWindowPreventFlicker,
            focusedWindowBorder: config.focusedWindowBorder,
            focusedWindowBorderColor: config.focusedWindowBorderColor,
            focusedWindowBorderWidth: config.focusedWindowBorderWidth,
            focusedWindowBorderOpacity: config.focusedWindowBorderOpacity,
            focusedWindowBorderRadius: config.focusedWindowBorderRadius,
            focusedWindowBorderInset: config.focusedWindowBorderInset,
            configVersion: config.configVersion.rawValue,
            persistentWorkspaces: config.persistentWorkspaces,
            gaps: config.gaps,
            workspaceToMonitorForceAssignment: config.workspaceToMonitorForceAssignment,
            keyMappingPreset: config.keyMapping.presetForSettings,
            keyNotationToKeyCode: config.keyMapping.rawNotationNamesForSettings,
            inheritEnvVars: rawExec.inheritEnvVariables,
            envVars: rawExec.overriddenVars,
            rawKeybindings: document.text(forTablesMatching: isKeybindingTable),
            rawWindowRules: document.text(forTablesMatching: isWindowRuleTable),
            // Newline-terminate each piece defensively: a `text(forKeyValue:)` block
            // normally already ends in "\n", but a file whose last line lacks a trailing
            // newline would otherwise glue two callback keys onto one line when joined.
            rawCallbacks: callbackKeys.compactMap { document.text(forKeyValue: $0) }
                .map { $0.endsWithNewline ? $0 : $0 + "\n" }.joined(),
        )
    }

    // MARK: - Writing a draft into the document

    /// Writes `draft` into `document`, touching only what the user actually changed.
    ///
    /// `original` is the draft as it was loaded from this same document. Every region —
    /// scalar, regenerated table family, raw pane, callback block — is written only when
    /// its own contributing fields differ from `original`, and is otherwise left completely
    /// alone rather than removed and re-inserted. That is what makes an untouched region
    /// byte-identical after a save: re-emitting even an unchanged value would still reflow
    /// its spacing, collapse a multi-line array onto one line, relocate a table, or delete a
    /// table whose values happen to equal the defaults (which the stock config's `[gaps]`
    /// and `[key-mapping]` both do).
    @MainActor static func apply(_ draft: ConfigDraft, original: ConfigDraft, to document: inout TomlBlockDocument) {
        let defaults = ConfigDraft.defaults

        // Top-level scalars. A scalar the user did not touch is never rewritten; one that
        // was is written unless it equals the default AND is absent from the file, so the
        // window never bloats a minimal config.
        func setScalar<Value: Equatable>(
            _ key: String,
            _ keyPath: KeyPath<ConfigDraft, Value>,
            _ serialize: (Value) -> String,
        ) {
            let value = draft[keyPath: keyPath]
            if value == original[keyPath: keyPath] { return }
            if value == defaults[keyPath: keyPath], document.text(forKeyValue: key) == nil { return }
            document.set(key: key, tomlValue: serialize(value))
        }

        setScalar("start-at-login", \.startAtLogin) { TomlValue.of($0) }
        setScalar("auto-reload-config", \.autoReloadConfig) { TomlValue.of($0) }
        setScalar("automatically-unhide-macos-hidden-apps", \.automaticallyUnhideMacosHiddenApps) { TomlValue.of($0) }
        setScalar("enable-normalization-flatten-containers", \.enableNormalizationFlattenContainers) { TomlValue.of($0) }
        setScalar("enable-normalization-opposite-orientation-for-nested-containers", \.enableNormalizationOppositeOrientationForNestedContainers) { TomlValue.of($0) }
        setScalar("enable-normalization-binary-tree", \.enableNormalizationBinaryTree) { TomlValue.of($0) }
        setScalar("default-root-container-layout", \.defaultRootContainerLayout) { TomlValue.of($0.rawValue) }
        setScalar("default-root-container-orientation", \.defaultRootContainerOrientation) { TomlValue.of($0.rawValue) }
        setScalar("accordion-padding", \.accordionPadding) { TomlValue.of($0) }
        setScalar("focus-follows-app-activation", \.focusFollowsAppActivation) { TomlValue.of($0.rawValue) }
        setScalar("new-window-prevent-flicker", \.newWindowPreventFlicker) { TomlValue.of($0) }
        setScalar("focused-window-border", \.focusedWindowBorder) { TomlValue.of($0) }
        setScalar("focused-window-border-color", \.focusedWindowBorderColor) { TomlValue.of($0) }
        setScalar("focused-window-border-width", \.focusedWindowBorderWidth) { TomlValue.of($0) }
        setScalar("focused-window-border-opacity", \.focusedWindowBorderOpacity) { TomlValue.of($0) }
        setScalar("focused-window-border-radius", \.focusedWindowBorderRadius) { TomlValue.of($0) }
        setScalar("focused-window-border-inset", \.focusedWindowBorderInset) { TomlValue.of($0) }
        setScalar("config-version", \.configVersion) { TomlValue.of($0) }
        // `persistent-workspaces` is a config-version-2-only key: the parser treats it as
        // a semantic error in a config-version <= 1 file (and derives `persistentWorkspaces`
        // itself from the file's bindings there instead). Only ever write it when the
        // draft is actually on version 2, or the key is already — and therefore validly —
        // present; there is no legitimate v1 file containing this key.
        if draft.configVersion >= 2 || document.text(forKeyValue: "persistent-workspaces") != nil {
            setScalar("persistent-workspaces", \.persistentWorkspaces) { names in
                TomlValue.array(names.map { TomlValue.of($0) })
            }
        }

        // Nested tables the form models completely: regenerated wholesale, but only when
        // one of their own values changed. A `nil` body deletes the table, on the grounds
        // that its values now equal the parser's fallbacks and it carries no information —
        // which is exactly why `changed` has to gate this. An untouched `[gaps]` of all
        // zeroes IS all-defaults, and regenerating it unconditionally would delete the
        // stock config's table and orphan the comment block introducing it.
        //
        // Still driven off `regeneratedTables`, so that list stays the single source of
        // truth for which tables the form owns outright.
        let regenerated: [String: (changed: Bool, body: String?)] = [
            "gaps": (
                draft.gaps != original.gaps,
                gapsTable(draft.gaps, defaults: defaults.gaps),
            ),
            "key-mapping": (
                draft.keyMappingPreset != original.keyMappingPreset || draft.keyNotationToKeyCode != original.keyNotationToKeyCode,
                keyMappingTable(draft, defaults: defaults),
            ),
            "exec": (
                draft.inheritEnvVars != original.inheritEnvVars || draft.envVars != original.envVars,
                execTable(draft, defaults: defaults),
            ),
            "workspace-to-monitor-force-assignment": (
                draft.workspaceToMonitorForceAssignment != original.workspaceToMonitorForceAssignment,
                workspaceAssignmentTable(draft.workspaceToMonitorForceAssignment),
            ),
        ]
        for name in regeneratedTables {
            guard let table = regenerated[name], table.changed else { continue }
            document.replaceTable(named: name, with: table.body)
        }

        // Raw panes. Each spliced block is tagged with a name its own predicate matches
        // ("mode" / "on-window-detected"), so calling `apply` again on the same document
        // finds and replaces it instead of appending a duplicate.
        if draft.rawKeybindings != original.rawKeybindings {
            document.replaceTables(matching: isKeybindingTable, with: draft.rawKeybindings, name: "mode")
        }
        if draft.rawWindowRules != original.rawWindowRules {
            document.replaceTables(matching: isWindowRuleTable, with: draft.rawWindowRules, name: "on-window-detected")
        }
        // The callbacks pane, by contrast, splices in as untagged trivia (see
        // `setRawTopLevel`) and `remove(key:)` cannot find it to remove before
        // re-inserting — so unlike the two panes above, this one relies on `apply` being
        // called at most once per `TomlBlockDocument` instance. That holds today: Task 5's
        // save flow always applies to a fresh copy of the on-disk document.
        //
        // It also gathers keys the file may spell in several separate places into one
        // block at one position, so an unchanged pane must not run at all: on the stock
        // config that alone would pull three callbacks out from under the three comment
        // blocks that explain them.
        if draft.rawCallbacks != original.rawCallbacks {
            for key in callbackKeys { document.remove(key: key) }
            document.setRawTopLevel(text: draft.rawCallbacks)
        }
    }

    // MARK: - Table bodies

    private static func gapsTable(_ gaps: Gaps, defaults: Gaps) -> String? {
        if gaps == defaults { return nil }
        var body = "[gaps]\n"
        body += "inner.horizontal = \(dynamicInt(gaps.inner.horizontal))\n"
        body += "inner.vertical = \(dynamicInt(gaps.inner.vertical))\n"
        body += "outer.left = \(dynamicInt(gaps.outer.left))\n"
        body += "outer.bottom = \(dynamicInt(gaps.outer.bottom))\n"
        body += "outer.top = \(dynamicInt(gaps.outer.top))\n"
        body += "outer.right = \(dynamicInt(gaps.outer.right))\n"
        return body
    }

    /// `5` for a constant, or `[{ monitor.main = 20 }, 8]` for a per-monitor value —
    /// the shape `parseDynamicValue` expects: monitor patterns first, plain default last.
    private static func dynamicInt(_ value: DynamicConfigValue<Int>) -> String {
        switch value {
            case .constant(let int): return TomlValue.of(int)
            case .perMonitor(let rules, let fallback):
                let items = rules.map { rule in
                    "{ monitor.\(monitorDescriptionToml(rule.description)) = \(TomlValue.of(rule.value)) }"
                }
                return TomlValue.array(items + [TomlValue.of(fallback)])
        }
    }

    /// A monitor description as it is spelled on the left of a per-monitor entry, where a
    /// pattern needs quoting but `main` / `secondary` / a number do not.
    private static func monitorDescriptionToml(_ description: MonitorDescription) -> String {
        switch description {
            case .main: "main"
            case .secondary: "secondary"
            case .sequenceNumber(let number): String(number)
            case .pattern(let regex): TomlValue.of(regex.origin)
        }
    }

    /// A monitor description as a standalone value (right-hand side), where every form is
    /// a string except a sequence number, which stays an int.
    private static func monitorDescriptionValue(_ description: MonitorDescription) -> String {
        switch description {
            case .main: TomlValue.of("main")
            case .secondary: TomlValue.of("secondary")
            case .sequenceNumber(let number): TomlValue.of(number)
            case .pattern(let regex): TomlValue.of(regex.origin)
        }
    }

    private static func keyMappingTable(_ draft: ConfigDraft, defaults: ConfigDraft) -> String? {
        if draft.keyMappingPreset == defaults.keyMappingPreset, draft.keyNotationToKeyCode.isEmpty { return nil }
        var body = "[key-mapping]\n"
        body += "preset = \(TomlValue.of(draft.keyMappingPreset.rawValue))\n"
        if !draft.keyNotationToKeyCode.isEmpty {
            body += "\n[key-mapping.key-notation-to-key-code]\n"
            for (notation, code) in draft.keyNotationToKeyCode.sorted(by: { $0.key < $1.key }) {
                // `TomlValue.key`, not a bare interpolation: a notation containing a dot
                // would otherwise be emitted as a dotted key and read back as a sub-table.
                body += "\(TomlValue.key(notation)) = \(TomlValue.of(code))\n"
            }
        }
        return body
    }

    private static func execTable(_ draft: ConfigDraft, defaults: ConfigDraft) -> String? {
        if draft.inheritEnvVars == defaults.inheritEnvVars, draft.envVars.isEmpty { return nil }
        var body = "[exec]\n"
        body += "inherit-env-vars = \(TomlValue.of(draft.inheritEnvVars))\n"
        if !draft.envVars.isEmpty {
            body += "\n[exec.env-vars]\n"
            for (name, value) in draft.envVars.sorted(by: { $0.key < $1.key }) {
                // `TomlValue.key`, not a bare interpolation: an env-var name is arbitrary
                // text, and a space or a dot in it would otherwise produce invalid TOML or
                // an unintended sub-table.
                body += "\(TomlValue.key(name)) = \(TomlValue.of(value))\n"
            }
        }
        return body
    }

    private static func workspaceAssignmentTable(_ assignment: [String: [MonitorDescription]]) -> String? {
        if assignment.isEmpty { return nil }
        var body = "[workspace-to-monitor-force-assignment]\n"
        for (workspace, monitors) in assignment.sorted(by: { $0.key < $1.key }) {
            let value = monitors.count == 1
                ? monitorDescriptionValue(monitors[0])
                : TomlValue.array(monitors.map(monitorDescriptionValue))
            body += "\(TomlValue.of(workspace)) = \(value)\n"
        }
        return body
    }
}

extension ConfigTomlWriter.ConfigDraft {
    /// The values the parser falls back to when a key is absent — i.e. `Config()`'s
    /// defaults, which is what `setOrOmit` compares against to keep a config minimal.
    @MainActor static var defaults: Self {
        ConfigTomlWriter.draft(from: Config(), rawExec: RawExecConfig(), document: TomlBlockDocument(""))
    }
}

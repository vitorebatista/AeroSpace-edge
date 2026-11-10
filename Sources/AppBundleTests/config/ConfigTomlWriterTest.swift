@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct ConfigTomlWriterTest {
    /// Applies a draft to an empty document, re-parses the result with the real parser,
    /// and returns the parsed config. Fails the test if the output does not parse.
    ///
    /// The pre-edit draft is built from `Config()`, not `defaultConfig`, so that it agrees
    /// with the empty document it is applied to — `SettingsModel` always derives the draft
    /// from the very config it parsed out of the document, and the writer now compares
    /// against that draft to decide what to touch. Seeding it from `defaultConfig` (which
    /// sets `config-version = 2` and a full `persistent-workspaces` list) would claim the
    /// empty document already contained values it does not.
    private func roundTrip(_ mutate: (inout ConfigTomlWriter.ConfigDraft) -> Void) -> Config {
        let original = ConfigTomlWriter.draft(from: Config(), rawExec: RawExecConfig(), document: TomlBlockDocument(""))
        var draft = original
        mutate(&draft)
        var document = TomlBlockDocument("")
        ConfigTomlWriter.apply(draft, original: original, to: &document)
        let text = document.render()
        let (parsed, errors) = parseConfigTuple(text)
        assertEquals(errors, [], additionalMsg: "generated config did not parse:\n\(text)")
        return parsed
    }

    @Test func testScalarsRoundTrip() {
        let parsed = roundTrip { draft in
            draft.startAtLogin = true
            draft.autoReloadConfig = true
            draft.automaticallyUnhideMacosHiddenApps = true
            draft.enableNormalizationFlattenContainers = false
            draft.enableNormalizationOppositeOrientationForNestedContainers = false
            draft.enableNormalizationBinaryTree = true
            draft.defaultRootContainerLayout = .accordion
            draft.defaultRootContainerOrientation = .vertical
            draft.accordionPadding = 45
            draft.focusFollowsAppActivation = .smart
            draft.newWindowPreventFlicker = true
            draft.configVersion = 2
        }
        assertEquals(parsed.startAtLogin, true)
        assertEquals(parsed.autoReloadConfig, true)
        assertEquals(parsed.automaticallyUnhideMacosHiddenApps, true)
        assertEquals(parsed.enableNormalizationFlattenContainers, false)
        assertEquals(parsed.enableNormalizationOppositeOrientationForNestedContainers, false)
        assertEquals(parsed.enableNormalizationBinaryTree, true)
        assertEquals(parsed.defaultRootContainerLayout, .accordion)
        assertEquals(parsed.defaultRootContainerOrientation, .vertical)
        assertEquals(parsed.accordionPadding, 45)
        assertEquals(parsed.focusFollowsAppActivation, .smart)
        assertEquals(parsed.newWindowPreventFlicker, true)
        assertEquals(parsed.configVersion, 2)
    }

    @Test func testWindowBorderRoundTrips() {
        let parsed = roundTrip { draft in
            draft.focusedWindowBorder = true
            draft.focusedWindowBorderColor = "0xff123456"
            draft.focusedWindowBorderWidth = 6
            draft.focusedWindowBorderOpacity = 80
            draft.focusedWindowBorderRadius = 12
            draft.focusedWindowBorderInset = 2
        }
        assertEquals(parsed.focusedWindowBorder, true)
        assertEquals(parsed.focusedWindowBorderColor, "0xff123456")
        assertEquals(parsed.focusedWindowBorderWidth, 6)
        assertEquals(parsed.focusedWindowBorderOpacity, 80)
        assertEquals(parsed.focusedWindowBorderRadius, 12)
        assertEquals(parsed.focusedWindowBorderInset, 2)
    }

    @Test func testPersistentWorkspacesRoundTrips() {
        // `config-version = 2` is not incidental: the key is rejected outright below that,
        // so this is the only combination a user can actually save.
        let parsed = roundTrip { draft in
            draft.configVersion = 2
            draft.persistentWorkspaces = ["1", "web", "it's"]
        }
        assertEquals(Array(parsed.persistentWorkspaces), ["1", "web", "it's"])
    }

    @Test func testPersistentWorkspacesIsGatedOnConfigVersion() {
        // Negative branch: a genuine config-version <= 1 file — the realistic case, where
        // the key is simply absent and config-version defaults to 1 — with a workspace
        // binding, so the parser itself derives a non-empty `persistentWorkspaces`
        // (parseConfig.swift's config-version <= 1 branch) exactly the way `SettingsModel`
        // will see it at runtime. Without the gate, `apply` would write
        // `persistent-workspaces = [...]` into this v1 file, and the parser rejects that
        // key outright ("This config option is only available since 'config-version = 2'").
        let text = "[mode.main.binding]\nalt-1 = 'workspace 1'\n"
        var document = TomlBlockDocument(text)
        let (config, errors) = parseConfigTuple(text)
        assertEquals(errors, [])
        assertEquals(config.configVersion, 1)
        assertEquals(Array(config.persistentWorkspaces), ["1"])

        let original = ConfigTomlWriter.draft(from: config, rawExec: RawExecConfig(), document: document)
        var draft = original
        draft.startAtLogin = true // an unrelated edit, the way a real save would make one
        ConfigTomlWriter.apply(draft, original: original, to: &document)

        let rendered = document.render()
        assertEquals(rendered.contains("persistent-workspaces"), false, additionalMsg: rendered)
        let (_, reErrors) = parseConfigTuple(rendered)
        assertEquals(reErrors, [], additionalMsg: rendered)

        // The gate's other half: a v1 file that already spells out `persistent-workspaces`
        // (already invalid on its own, since the parser rejects that combination) stays
        // writable rather than being silently dropped by the settings window.
        var alreadyPresentDocument = TomlBlockDocument("persistent-workspaces = ['1']\n")
        let alreadyPresentOriginal = ConfigTomlWriter.draft(from: Config(), rawExec: RawExecConfig(), document: alreadyPresentDocument)
        var alreadyPresentDraft = alreadyPresentOriginal
        alreadyPresentDraft.configVersion = 1
        alreadyPresentDraft.persistentWorkspaces = ["1", "2"]
        ConfigTomlWriter.apply(alreadyPresentDraft, original: alreadyPresentOriginal, to: &alreadyPresentDocument)
        assertEquals(alreadyPresentDocument.render(), "persistent-workspaces = ['1', '2']\n")
    }

    @Test func testConstantGapsRoundTrip() {
        let parsed = roundTrip { draft in
            draft.gaps = Gaps(inner: .init(vertical: 5, horizontal: 6), outer: .init(left: 1, bottom: 2, top: 3, right: 4))
        }
        assertEquals(parsed.gaps.inner.vertical, .constant(5))
        assertEquals(parsed.gaps.outer.top, .constant(3))
    }

    @Test func testPerMonitorGapsRoundTrip() {
        let pattern = MonitorDescription.pattern("Dell.*")!
        let parsed = roundTrip { draft in
            draft.gaps = Gaps(
                inner: .init(vertical: .constant(5), horizontal: .constant(6)),
                outer: .init(
                    left: .perMonitor([PerMonitorValue(description: .main, value: 20)], default: 8),
                    bottom: .constant(2), top: .constant(3),
                    right: .perMonitor([PerMonitorValue(description: pattern, value: 12)], default: 4),
                ),
            )
        }
        assertEquals(parsed.gaps.outer.left, .perMonitor([PerMonitorValue(description: .main, value: 20)], default: 8))
        // A monitor *pattern* on the left of a per-monitor entry needs quoting, unlike
        // `main` / `secondary` / a sequence number.
        assertEquals(parsed.gaps.outer.right, .perMonitor([PerMonitorValue(description: pattern, value: 12)], default: 4))
    }

    @Test func testKeyMappingRoundTrips() {
        let parsed = roundTrip { draft in
            draft.keyMappingPreset = .dvorak
            draft.keyNotationToKeyCode = ["q": "quote"]
        }
        // An override wins over the preset (KeyMapping.resolve() is
        // getKeysPreset(preset) + rawKeyNotationToKeyCode).
        assertEquals(parsed.keyMapping.resolve()["q"], keyNotationToKeyCode["quote"])
        // The preset itself round-trips too — 's' differs between qwerty and dvorak.
        assertEquals(parsed.keyMapping.resolve()["s"], getKeysPreset(.dvorak)["s"])
    }

    @Test func testExecRoundTrips() {
        let parsed = roundTrip { draft in
            draft.inheritEnvVars = false
            draft.envVars = ["MY_VAR": "hello"]
        }
        assertEquals(parsed.execConfig.envVariables["MY_VAR"], "hello")
        assertEquals(parsed.execConfig.envVariables["AEROSPACE_INHERITED_TEST_ENV"], nil)
    }

    @Test func testWorkspaceToMonitorAssignmentRoundTrips() {
        let pattern = MonitorDescription.pattern("Dell.*")!
        let parsed = roundTrip { draft in
            draft.workspaceToMonitorForceAssignment = [
                "1": [.main],
                "2": [.secondary, .sequenceNumber(3)],
                "3": [pattern],
            ]
        }
        assertEquals(parsed.workspaceToMonitorForceAssignment["1"], [.main])
        assertEquals(parsed.workspaceToMonitorForceAssignment["2"], [.secondary, .sequenceNumber(3)])
        assertEquals(parsed.workspaceToMonitorForceAssignment["3"], [pattern])
    }

    @Test func testRawPanesAreSpliced() {
        let parsed = roundTrip { draft in
            draft.rawKeybindings = "[mode.main.binding]\nalt-h = 'focus left'\n"
            draft.rawWindowRules = "[[on-window-detected]]\nif.app-id = 'com.apple.finder'\nrun = ['layout floating']\n"
            draft.rawCallbacks = "on-focus-changed = ['move-mouse window-lazy-center']\n"
        }
        assertEquals(parsed.modes[mainModeId]?.bindings.isEmpty, false)
        assertEquals(parsed.onWindowDetected.count, 1)
        assertEquals(parsed.onFocusChanged.count, 1)
    }

    @Test func testDefaultsAreNotWrittenWhenAbsentFromTheFile() {
        // A user's file that sets nothing must stay minimal after an unrelated edit.
        //
        // Deviation from the brief, reconfirmed after the round-1 review (see the fix
        // report): built from `Config()`, not `defaultConfig`. `defaultConfig` (the parsed
        // docs/config-examples/default-config.toml) explicitly sets BOTH `config-version =
        // 2` AND a full `persistent-workspaces` list, beyond `Config()`'s bare defaults.
        // Critical 2's fix (gating `persistent-workspaces` on config-version >= 2) only
        // silences the second of those — `config-version` itself still differs from
        // `ConfigDraft.defaults` (built from `Config()`) regardless, so `setOrOmit` still
        // writes `config-version = 2` unconditionally even with Critical 2 fixed. This is
        // independent of Critical 2: `configVersion`'s `isDefault` check never involves the
        // version gate at all. Verified empirically: reverting to `defaultConfig` here,
        // with Critical 2's fix in place, still fails with exactly `config-version = 2`
        // appended (persistent-workspaces no longer appears). See the fix report for the
        // full trace. `Config()` is the only source consistent with this test's own intent
        // ("stays minimal") and with how the type is used for real (Task 5 always builds
        // the draft from the Config parsed from the SAME document).
        var document = TomlBlockDocument("start-at-login = false\n")
        let original = ConfigTomlWriter.draft(from: Config(), rawExec: RawExecConfig(), document: document)
        var draft = original
        draft.startAtLogin = true
        ConfigTomlWriter.apply(draft, original: original, to: &document)
        assertEquals(document.render(), "start-at-login = true\n")
    }

    @Test func testRevertingAnOptionToItsDefaultStillPersistsWhenAlreadyPresent() {
        // The `isDefault && already present` branch of `setOrOmit`: turning a toggle back
        // to its default value must still overwrite the existing line, not leave the old
        // value or silently drop the key.
        //
        // Built from `Config()`, not `defaultConfig` — same reasoning as
        // `testDefaultsAreNotWrittenWhenAbsentFromTheFile` above: `defaultConfig` sets
        // `config-version` / `persistent-workspaces` beyond `Config()`'s bare defaults,
        // which would leak into this near-empty document's exact-equality assertion too.
        let text = "start-at-login = true\n"
        var document = TomlBlockDocument(text)
        // Built from the config parsed out of THIS document, the way `SettingsModel.load()`
        // does: the writer only touches a key whose value differs from the one it loaded,
        // so an `original` that disagreed with the document would skip the branch entirely.
        let (config, errors) = parseConfigTuple(text)
        assertEquals(errors, [])
        let original = ConfigTomlWriter.draft(from: config, rawExec: RawExecConfig(), document: document)
        var draft = original
        draft.startAtLogin = false
        ConfigTomlWriter.apply(draft, original: original, to: &document)
        assertEquals(document.render(), "start-at-login = false\n")
    }

    @Test func testRegeneratingATableRemovesItsExistingSubTables() {
        // `[exec]` and `[exec.env-vars]` are separate top-level blocks (each `[header]`
        // line splits into its own block). Regenerating `[exec]` must remove the stale
        // `[exec.env-vars]` too, or the freshly-generated `[exec]` body (which re-emits
        // its own `[exec.env-vars]`) duplicates the table and the result fails to parse.
        var document = TomlBlockDocument("[exec]\ninherit-env-vars = false\n\n[exec.env-vars]\nFOO = 'bar'\n")
        let original = ConfigTomlWriter.draft(from: defaultConfig, rawExec: RawExecConfig(), document: document)
        var draft = original
        draft.inheritEnvVars = false
        draft.envVars = ["FOO": "bar", "BAZ": "qux"]
        ConfigTomlWriter.apply(draft, original: original, to: &document)
        let text = document.render()
        assertEquals(text.components(separatedBy: "[exec.env-vars]").count - 1, 1, additionalMsg: text)
        let (parsed, errors) = parseConfigTuple(text)
        assertEquals(errors, [], additionalMsg: text)
        assertEquals(parsed.execConfig.envVariables["FOO"], "bar")
        assertEquals(parsed.execConfig.envVariables["BAZ"], "qux")
    }

    @Test func testCommentsOutsideRegeneratedTablesSurvive() {
        var document = TomlBlockDocument("# my note\nstart-at-login = false\n\n[mode.main.binding]\nalt-h = 'focus left'\n")
        let original = ConfigTomlWriter.draft(from: defaultConfig, rawExec: RawExecConfig(), document: document)
        var draft = original
        draft.startAtLogin = true
        ConfigTomlWriter.apply(draft, original: original, to: &document)
        assertEquals(document.render().contains("# my note"), true)
        assertEquals(document.render().contains("alt-h = 'focus left'"), true)
    }

    @Test func testAppliedToDefaultConfigStillParses() {
        let text = try! String(
            contentsOf: projectRoot.appending(component: "docs/config-examples/default-config.toml"),
            encoding: .utf8,
        )
        var document = TomlBlockDocument(text)
        let (config, errors) = parseConfigTuple(text)
        assertEquals(errors, [])
        let original = ConfigTomlWriter.draft(from: config, rawExec: RawExecConfig(), document: document)
        var draft = original
        draft.accordionPadding = 99
        draft.gaps = draft.gaps.with(\.inner.vertical, .constant(7))
        ConfigTomlWriter.apply(draft, original: original, to: &document)
        let (reparsed, reErrors) = parseConfigTuple(document.render())
        assertEquals(reErrors, [], additionalMsg: document.render())
        assertEquals(reparsed.accordionPadding, 99)
        assertEquals(reparsed.gaps.inner.vertical, .constant(7))
        // The bindings the default config ships with must survive an unrelated edit.
        assertEquals(reparsed.modes[mainModeId]?.bindings.count, config.modes[mainModeId]?.bindings.count)
    }

    /// Reads `docs/config-examples/default-config.toml` — the file the settings window
    /// itself seeds a brand-new config from, and the closest thing to "a real user's file"
    /// this suite has.
    private func defaultConfigText() -> String {
        try! String(
            contentsOf: projectRoot.appending(component: "docs/config-examples/default-config.toml"),
            encoding: .utf8,
        )
    }

    @Test func testApplyingAnUnchangedDraftIsByteIdentical() {
        // The whole feature's promise, on the whole stock config: opening the window and
        // saving without touching anything must give back exactly the bytes that went in —
        // no reflowed multi-line `persistent-workspaces`, no re-indented `[gaps]`, no
        // `[key-mapping]` deleted for holding the default preset, no callbacks pulled out
        // from under the comments that explain them.
        let text = defaultConfigText()
        var document = TomlBlockDocument(text)
        let (config, errors) = parseConfigTuple(text)
        assertEquals(errors, [])
        let draft = ConfigTomlWriter.draft(
            from: config,
            rawExec: SettingsModel.rawExecConfig(from: text),
            document: document,
        )
        ConfigTomlWriter.apply(draft, original: draft, to: &document)
        assertEquals(document.render(), text)
    }

    @Test func testAnUnrelatedEditLeavesEveryOtherRegionAlone() {
        // The realistic save: one toggle flipped, everything else untouched. Only the
        // `start-at-login` line may differ — in particular the four regenerated tables must
        // stay exactly where and how they were, even though `[gaps]` (all zeroes) and
        // `[key-mapping]` (preset 'qwerty') both hold nothing but default values.
        let text = defaultConfigText()
        var document = TomlBlockDocument(text)
        let (config, errors) = parseConfigTuple(text)
        assertEquals(errors, [])
        let original = ConfigTomlWriter.draft(
            from: config,
            rawExec: SettingsModel.rawExecConfig(from: text),
            document: document,
        )
        var draft = original
        draft.startAtLogin = true
        ConfigTomlWriter.apply(draft, original: original, to: &document)

        let rendered = document.render()
        assertEquals(rendered, text.replacingOccurrences(of: "start-at-login = false", with: "start-at-login = true"))
        for table in ConfigTomlWriter.regeneratedTables {
            assertEquals(rendered.contains("[\(table)]"), text.contains("[\(table)]"), additionalMsg: table)
        }
        let (reparsed, reErrors) = parseConfigTuple(rendered)
        assertEquals(reErrors, [], additionalMsg: rendered)
        assertEquals(reparsed.startAtLogin, true)
    }

    @Test func testTablesHoldingOnlyDefaultsSurviveAnUnrelatedEdit() {
        // The narrow form of the above, spelled out: `replaceTable(named:with: nil)` deletes
        // a family whose values equal the defaults, so an untouched one must never reach it.
        let text = "[key-mapping]\npreset = 'qwerty'\n\n[gaps]\ninner.horizontal = 0\n"
        var document = TomlBlockDocument(text)
        let (config, errors) = parseConfigTuple(text)
        assertEquals(errors, [])
        let original = ConfigTomlWriter.draft(from: config, rawExec: RawExecConfig(), document: document)
        var draft = original
        draft.startAtLogin = true
        ConfigTomlWriter.apply(draft, original: original, to: &document)
        assertEquals(document.render(), "start-at-login = true\n" + text)
    }

    @Test func testNotationAndEnvVarNamesAreQuotedOnlyWhenTheyHaveToBe() {
        // A bare key can't carry a dot (it would nest a sub-table) or a space (invalid
        // TOML); an ordinary name must still be spelled bare, the way a human would.
        var document = TomlBlockDocument("")
        let original = ConfigTomlWriter.draft(from: Config(), rawExec: RawExecConfig(), document: document)
        var draft = original
        draft.keyNotationToKeyCode = ["a.b": "quote", "q": "quote"]
        draft.envVars = ["MY VAR": "hello", "MY_VAR": "hello"]
        ConfigTomlWriter.apply(draft, original: original, to: &document)
        let rendered = document.render()
        for expected in ["'a.b' = 'quote'", "q = 'quote'", "'MY VAR' = 'hello'", "MY_VAR = 'hello'"] {
            assertEquals(rendered.contains(expected), true, additionalMsg: "\(expected) missing from:\n\(rendered)")
        }
    }

    @Test func testEditingExecPreservesAnInterpolatedValueAndAQuotedVariableName() {
        // `Config.execConfig` holds an expanded environment, not the text that was in the
        // file. The Settings window has to use RawExecConfig for the draft, otherwise a
        // save after changing only `inherit-env-vars` would bake the process's PATH into
        // the config or lose a TOML-significant variable name.
        let text = """
            [exec]
            inherit-env-vars = false

            [exec.env-vars]
            'MY.PATH' = '/tools:${PATH}'
            """
        var document = TomlBlockDocument(text)
        let (config, errors) = parseConfigTuple(text)
        assertEquals(errors, [])
        let original = ConfigTomlWriter.draft(
            from: config,
            rawExec: SettingsModel.rawExecConfig(from: text),
            document: document,
        )
        assertEquals(original.envVars, ["MY.PATH": "/tools:${PATH}"])

        var draft = original
        draft.inheritEnvVars = true
        ConfigTomlWriter.apply(draft, original: original, to: &document)

        let rendered = document.render()
        assertEquals(rendered.contains("'MY.PATH' = '/tools:${PATH}'"), true, additionalMsg: rendered)
        assertEquals(SettingsModel.rawExecConfig(from: rendered).overriddenVars, ["MY.PATH": "/tools:${PATH}"])
    }

    @Test func testEditingCallbacksKeepsUnrelatedTopLevelText() {
        // The Callbacks pane removes and reinserts only its owned callback keys. Its edit
        // must not discard a future top-level option or its surrounding comment.
        let text = """
            # Keep this future option exactly where it is.
            future-option = 'keep me'
            on-focus-changed = 'focus left'

            [mode.main.binding]
            alt-h = 'focus left'
            """
        var document = TomlBlockDocument(text)
        let original = ConfigTomlWriter.draft(from: Config(), rawExec: RawExecConfig(), document: document)
        var draft = original
        draft.rawCallbacks = "on-focus-changed = 'focus right'\n"
        ConfigTomlWriter.apply(draft, original: original, to: &document)

        let rendered = document.render()
        assertEquals(rendered.contains("# Keep this future option exactly where it is.\nfuture-option = 'keep me'"), true, additionalMsg: rendered)
        assertEquals(rendered.contains("on-focus-changed = 'focus right'"), true, additionalMsg: rendered)
        assertEquals(rendered.contains("[mode.main.binding]\nalt-h = 'focus left'"), true, additionalMsg: rendered)
    }
}

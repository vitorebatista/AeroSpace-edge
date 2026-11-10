@testable import AppBundle
import Common
import Foundation
import Testing

@MainActor
@Suite(.serializedGlobally)
struct ConfigMigratorTest {
    private typealias Draft = ConfigTomlWriter.ConfigDraft

    @Test func testMigrateComprehensiveV1FixturePreservesEveryDraftFieldAndSourceBlock() throws {
        try assertFixtureMigration(named: "config-v1-comprehensive")
    }

    @Test func testMigrateComprehensiveV1FixturePreservesWorkspaceAndStartupWindowMatchers() throws {
        let sourceText = try String(
            contentsOf: projectRoot.appending(component: "Sources/AppBundleTests/config/fixtures/config-v1-comprehensive.toml"),
            encoding: .utf8,
        )
        let source = parseConfig(sourceText)
        #expect(source.errors == [])
        guard source.errors.isEmpty else { return }

        let candidate = migrate(sourceText)
        let migrated = parseConfig(candidate.text)
        #expect(migrated.errors == [])
        guard migrated.errors.isEmpty else { return }

        let sourceMatchers = source.config.onWindowDetected.compactMap(\.matcher.legacyOrNil)
        let migratedMatchers = migrated.config.onWindowDetected.compactMap(\.matcher.legacyOrNil)
        #expect(sourceMatchers.contains { $0.workspace == "fixture-workspace" })
        #expect(sourceMatchers.contains { $0.duringAeroSpaceStartup == true })
        #expect(migratedMatchers.contains { $0.workspace == "fixture-workspace" })
        #expect(migratedMatchers.contains { $0.duringAeroSpaceStartup == true })
    }

    @Test func testMigrateCurrentShapeV1FixturePreservesEveryDraftFieldAndSourceBlock() throws {
        try assertFixtureMigration(named: "config-v1-current-shape")
    }

    @Test(
        "Set AEROSPACE_MIGRATION_DRY_RUN to inspect a local config",
        .enabled(if: ProcessInfo.processInfo.environment["AEROSPACE_MIGRATION_DRY_RUN"] != nil),
    )
    func testDryRunMigrationFromEnvironmentWithoutWriting() throws {
        guard let path = ProcessInfo.processInfo.environment["AEROSPACE_MIGRATION_DRY_RUN"] else { return }

        let sourceText = try String(contentsOfFile: path, encoding: .utf8)
        let source = parseConfig(sourceText)
        #expect(source.errors == [])
        guard source.errors.isEmpty else { return }
        guard source.config.configVersion == ._1 else {
            print("Migration dry run diff: skipped; source is already config-version \(source.config.configVersion)")
            return // AEROSPACE_MIGRATION_DRY_RUN must point to an effective config-version 1 file
        }

        let candidate = migrate(sourceText)
        let migrated = parseConfig(candidate.text)
        #expect(migrated.errors == [])

        let sourceKeysAndTables = TomlBlockDocument(sourceText).blocks.compactMap(\.name)
        let candidateKeysAndTables = TomlBlockDocument(candidate.text).blocks.compactMap(\.name)
        print("Migration dry run source keys/tables: \(sourceKeysAndTables.joined(separator: ", "))")
        print("Migration dry run candidate keys/tables: \(candidateKeysAndTables.joined(separator: ", "))")
        print("Migration dry run workspaces: \(candidate.persistentWorkspaces.joined(separator: ", "))")
        print("Migration dry run diff: config-version and persistent-workspaces; bytes \(sourceText.utf8.count) -> \(candidate.text.utf8.count)")

        #expect(try String(contentsOfFile: path, encoding: .utf8) == sourceText)
    }

    @Test func testMigrateAddsVersionAndPersistentWorkspacesToAnImplicitV1Config() {
        let candidate = migrate(
            """
            [mode.main.binding]
            alt-1 = 'workspace 1'
            """,
        )

        assertEquals(candidate.fromVersion, 1)
        assertEquals(candidate.toVersion, 2)
        assertEquals(candidate.persistentWorkspaces, ["1"])
        assertEquals(
            candidate.text,
            """
            config-version = 2
            persistent-workspaces = ['1']
            [mode.main.binding]
            alt-1 = 'workspace 1'
            """,
        )
    }

    @Test func testMigrateRewritesAnExplicitV1VersionInPlace() {
        let candidate = migrate(
            """
            # Keep this comment
            config-version = 1 # old format
            start-at-login = true

            [mode.main.binding]
            alt-w = 'workspace web'
            """,
        )

        assertEquals(
            candidate.text,
            """
            # Keep this comment
            config-version = 2 # old format
            start-at-login = true
            persistent-workspaces = ['web']

            [mode.main.binding]
            alt-w = 'workspace web'
            """,
        )
    }

    @Test func testMigrateRejectsUnsupportedPaths() {
        assertEquals(
            ConfigMigrator.migrate(text: "", from: 2, to: 1),
            .failure(.unsupportedPath(from: 2, to: 1)),
        )
    }

    @Test func testMigrateRejectsAnInvalidSource() {
        assertEquals(
            ConfigMigrator.migrate(text: "config-version = 0\n", from: 1, to: 2),
            .failure(.invalidSource(["[ERROR] config-version: config-version must be in [1, 2] range"])),
        )
    }

    @Test func testMigrateEmitsBindingThenAssignmentWorkspacesInSourceOrder() {
        let candidate = migrate(
            """
            [key-mapping]
            preset = 'qwerty'

            [key-mapping.key-notation-to-key-code]
            zz = 'a'

            [mode.main.binding]
            alt-zz = ['workspace three', 'move-node-to-workspace two']
            alt-1 = 'workspace one'

            [mode.second.binding]
            alt-2 = 'move-node-to-workspace four'

            [workspace-to-monitor-force-assignment]
            five = 'main'
            two = 'secondary'
            """,
        )

        assertEquals(candidate.persistentWorkspaces, ["three", "two", "one", "four", "five"])
        #expect(candidate.text.contains("persistent-workspaces = ['three', 'two', 'one', 'four', 'five']"))
    }

    @Test func testMigrateKeepsSourceSemanticContextWhenParsingSplitBindings() {
        let candidate = migrate(
            """
            enable-normalization-flatten-containers = false

            [mode.main.binding]
            alt-s = 'split horizontal'
            alt-1 = 'workspace 1'
            """,
        )

        assertEquals(candidate.persistentWorkspaces, ["1"])
        #expect(candidate.text.contains("enable-normalization-flatten-containers = false"))
    }

    @Test func testMigrateUsesCustomKeyMappingWrittenAsDottedKeys() {
        let candidate = migrate(
            """
            key-mapping.key-notation-to-key-code.zz = 'a'

            [mode.main.binding]
            alt-zz = 'workspace one'
            """,
        )

        assertEquals(candidate.persistentWorkspaces, ["one"])
    }

    @Test func testMigrateParsesMultilineTomlBindingStrings() {
        let candidate = migrate(
            #"""
            [mode.main.binding]
            alt-1 = """
            workspace one
            """
            """#,
        )

        assertEquals(candidate.persistentWorkspaces, ["one"])
    }

    @Test func testMigrateCollectsAssignmentsWithoutModeBindings() {
        let candidate = migrate(
            """
            [workspace-to-monitor-force-assignment]
            one = 'main'
            two = 'secondary'
            """,
        )

        assertEquals(candidate.persistentWorkspaces, ["one", "two"])
    }

    @Test func testMigrateOnlyRewritesVersionAndPersistentWorkspaceLines() {
        let candidate = migrate(
            """
            config-version = 1
            # This block must stay byte-for-byte identical.
            [mode.main.binding]
            alt-1 = [
                'workspace 1', # keep
                'move-node-to-workspace 2',
            ]
            """,
        )

        assertEquals(
            candidate.text,
            """
            config-version = 2
            persistent-workspaces = ['1', '2']
            # This block must stay byte-for-byte identical.
            [mode.main.binding]
            alt-1 = [
                'workspace 1', # keep
                'move-node-to-workspace 2',
            ]
            """,
        )
    }

    private func migrate(_ text: String) -> ConfigMigrationCandidate {
        switch ConfigMigrator.migrate(text: text, from: 1, to: 2) {
            case .success(let candidate): return candidate
            case .failure(let error):
                Issue.record(Comment(rawValue: "Migration failed: \(error)"))
                fatalError("Migration failed")
        }
    }

    private func assertFixtureMigration(named name: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let sourceText = try String(
            contentsOf: projectRoot.appending(component: "Sources/AppBundleTests/config/fixtures/\(name).toml"),
            encoding: .utf8,
        )
        let source = parseConfig(sourceText)
        #expect(source.errors == [], "Invalid fixture \(name)", sourceLocation: sourceLocation)
        guard source.errors.isEmpty else { return }

        let candidate = migrate(sourceText)
        let migrated = parseConfig(candidate.text)
        #expect(migrated.errors == [], "Invalid migrated fixture \(name)", sourceLocation: sourceLocation)
        guard migrated.errors.isEmpty else { return }

        assertEveryDraftField(
            source: draft(from: source.config, text: sourceText),
            migrated: draft(from: migrated.config, text: candidate.text),
            sourceLocation: sourceLocation,
        )
        assertEveryNonMigrationBlockIsByteIdentical(
            sourceText: sourceText,
            candidateText: candidate.text,
            sourceLocation: sourceLocation,
        )
    }

    private func draft(from config: Config, text: String) -> Draft {
        ConfigTomlWriter.draft(
            from: config,
            rawExec: SettingsModel.rawExecConfig(from: text),
            document: TomlBlockDocument(text),
        )
    }

    private func assertEveryDraftField(
        source: Draft,
        migrated: Draft,
        sourceLocation: SourceLocation,
    ) {
        let fields: [(name: String, matches: (Draft, Draft) -> Bool)] = [
            ("startAtLogin", { $0.startAtLogin == $1.startAtLogin }),
            ("autoReloadConfig", { $0.autoReloadConfig == $1.autoReloadConfig }),
            ("automaticallyUnhideMacosHiddenApps", { $0.automaticallyUnhideMacosHiddenApps == $1.automaticallyUnhideMacosHiddenApps }),
            ("enableNormalizationFlattenContainers", { $0.enableNormalizationFlattenContainers == $1.enableNormalizationFlattenContainers }),
            ("enableNormalizationOppositeOrientationForNestedContainers", { $0.enableNormalizationOppositeOrientationForNestedContainers == $1.enableNormalizationOppositeOrientationForNestedContainers }),
            ("enableNormalizationBinaryTree", { $0.enableNormalizationBinaryTree == $1.enableNormalizationBinaryTree }),
            ("defaultRootContainerLayout", { $0.defaultRootContainerLayout.rawValue == $1.defaultRootContainerLayout.rawValue }),
            ("defaultRootContainerOrientation", { $0.defaultRootContainerOrientation.rawValue == $1.defaultRootContainerOrientation.rawValue }),
            ("accordionPadding", { $0.accordionPadding == $1.accordionPadding }),
            ("focusFollowsAppActivation", { $0.focusFollowsAppActivation.rawValue == $1.focusFollowsAppActivation.rawValue }),
            ("newWindowPreventFlicker", { $0.newWindowPreventFlicker == $1.newWindowPreventFlicker }),
            ("focusedWindowBorder", { $0.focusedWindowBorder == $1.focusedWindowBorder }),
            ("focusedWindowBorderColor", { $0.focusedWindowBorderColor == $1.focusedWindowBorderColor }),
            ("focusedWindowBorderWidth", { $0.focusedWindowBorderWidth == $1.focusedWindowBorderWidth }),
            ("focusedWindowBorderOpacity", { $0.focusedWindowBorderOpacity == $1.focusedWindowBorderOpacity }),
            ("focusedWindowBorderRadius", { $0.focusedWindowBorderRadius == $1.focusedWindowBorderRadius }),
            ("focusedWindowBorderInset", { $0.focusedWindowBorderInset == $1.focusedWindowBorderInset }),
            ("configVersion", { $0.configVersion == 1 && $1.configVersion == 2 }),
            ("persistentWorkspaces membership", { Set($0.persistentWorkspaces) == Set($1.persistentWorkspaces) }),
            ("gaps", { $0.gaps == $1.gaps }),
            ("workspaceToMonitorForceAssignment", { $0.workspaceToMonitorForceAssignment == $1.workspaceToMonitorForceAssignment }),
            ("keyMappingPreset", { $0.keyMappingPreset.rawValue == $1.keyMappingPreset.rawValue }),
            ("keyNotationToKeyCode", { $0.keyNotationToKeyCode == $1.keyNotationToKeyCode }),
            ("inheritEnvVars", { $0.inheritEnvVars == $1.inheritEnvVars }),
            ("envVars", { $0.envVars == $1.envVars }),
            ("rawKeybindings", { $0.rawKeybindings == $1.rawKeybindings }),
            ("rawWindowRules", { $0.rawWindowRules == $1.rawWindowRules }),
            ("rawCallbacks", { $0.rawCallbacks == $1.rawCallbacks }),
        ]

        for field in fields {
            #expect(field.matches(source, migrated), "Draft field changed: \(field.name)", sourceLocation: sourceLocation)
        }
    }

    private func assertEveryNonMigrationBlockIsByteIdentical(
        sourceText: String,
        candidateText: String,
        sourceLocation: SourceLocation,
    ) {
        let migrationOwnedKeys = Set(["config-version", "persistent-workspaces"])
        let sourceBlocks = TomlBlockDocument(sourceText).blocks.filter { !migrationOwnedKeys.contains($0.name ?? "") }
        let candidateBlocks = TomlBlockDocument(candidateText).blocks.filter { !migrationOwnedKeys.contains($0.name ?? "") }
        #expect(candidateBlocks == sourceBlocks, "A non-migration TOML block changed or moved", sourceLocation: sourceLocation)
    }
}

extension WindowDetectedCallbackMatcher {
    fileprivate var legacyOrNil: LegacyWindowDetectedCallbackMatcher? {
        if case .legacy(let matcher) = self { matcher } else { nil }
    }
}

@testable import AppBundle
import AppKit
import Testing

@MainActor
@Suite(.serializedGlobally)
struct SettingsHelpTest {
    /// The controls that are deliberately not config options: app preferences and immediate
    /// actions. Everything else must name the TOML key it writes.
    private static let appPreferenceTopics: Set<SettingHelpTopic> = [
        .menuBarStyle, .menuBarItemPosition, .openConfig, .reloadConfig, .crashReports, .versionInfo,
    ]

    @Test func testAppPreferencesAreExactlyTheTopicsWithoutTomlKeys() {
        let withoutKeys = Set(SettingHelpTopic.allCases.filter { $0.content.tomlKeys.isEmpty })
        assertEquals(withoutKeys.sorted { $0.rawValue < $1.rawValue }, Self.appPreferenceTopics.sorted { $0.rawValue < $1.rawValue })
    }

    @Test func testEveryTopicProvidesUsefulUserFacingHelp() {
        for topic in SettingHelpTopic.allCases {
            let content = topic.content
            #expect(!(content.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty), "Missing summary for \(topic)")
            #expect(!(content.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty), "Missing details for \(topic)")
            #expect(content.tomlKeys.allSatisfy { !$0.isEmpty }, "Empty TOML key for \(topic)")
            #expect(!content.tomlKeys.isEmpty || Self.appPreferenceTopics.contains(topic), "Missing TOML key for \(topic) — add it, or list the topic as an app preference")
        }
    }

    /// Anything the user has to type a *structure* into, rather than pick or toggle, has to show
    /// what that structure looks like.
    @Test func testFreeFormControlsShowExamples() {
        let topics: [SettingHelpTopic] = [
            .keyNotationOverrides,
            .envVarOverrides,
            .persistentWorkspaces,
            .workspaceMonitorAssignment,
            .perMonitorGaps,
            .borderColor,
        ]
        for topic in topics {
            #expect(!topic.content.examples.isEmpty, "Missing examples for \(topic)")
            #expect(topic.content.examples.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }, "Empty example for \(topic)")
        }
    }

    @Test func testTheTooltipCarriesTheExamples() {
        let content = SettingHelpTopic.envVarOverrides.content
        #expect(content.tooltip.contains(content.summary))
        for example in content.examples {
            #expect(content.tooltip.contains(example), "Tooltip drops example: \(example)")
        }
        // A plain switch has nothing to show, and its tooltip stays the bare summary.
        assertEquals(SettingHelpTopic.startAtLogin.content.tooltip, SettingHelpTopic.startAtLogin.content.summary)
    }

    /// The link in each destination has to land on a page that exists — the docs are a separate
    /// tree, so a renamed page would otherwise 404 silently.
    @MainActor
    @Test func testEveryDestinationLinksToAPageThatExists() {
        for category in SettingsCategory.allCases {
            let page = category.docsUrl.lastPathComponent
            let file = projectRoot.appending(component: "docs-md/settings/\(page).md")
            #expect(FileManager.default.fileExists(atPath: file.path), "\(category) links to a missing docs page: \(file.path)")
        }
    }

    @Test func testCompoundControlsNameEveryTomlKeyTheyChange() {
        assertEquals(SettingHelpTopic.innerGaps.content.tomlKeys, ["gaps.inner.horizontal", "gaps.inner.vertical"])
        assertEquals(SettingHelpTopic.outerGaps.content.tomlKeys, [
            "gaps.outer.left", "gaps.outer.right", "gaps.outer.top", "gaps.outer.bottom",
        ])
        assertEquals(SettingHelpTopic.focusedWindowBorder.content.tomlKeys, [
            "focused-window-border",
            "focused-window-border-color",
            "focused-window-border-width",
            "focused-window-border-opacity",
            "focused-window-border-radius",
            "focused-window-border-inset",
        ])
    }

    @Test func testSpatialOptionsHaveAVisualExplanation() {
        let topics: [SettingHelpTopic] = [
            .defaultLayout,
            .defaultOrientation,
            .flattenContainers,
            .oppositeOrientation,
            .binaryTree,
            .accordionPadding,
            .innerGaps,
            .outerGaps,
            .perMonitorGaps,
            .focusActivation,
            .focusedWindowBorder,
            .workspaceMonitorAssignment,
        ]
        for topic in topics {
            #expect(topic.content.visual != nil, "Missing visual explanation for \(topic)")
        }
    }

    @Test func testConfigVersionHelpExplainsMigrationAndRecoveryBeforeSaving() {
        let details = SettingsMigrationCopy.pending

        for expected in [
            "Version 1",
            "Version 2",
            "materializes",
            "persistent-workspaces",
            "backup-v1-YYYYMMDD-HHmmss",
            "No files change until Save",
        ] {
            #expect(details.contains(expected), "Missing migration guidance: \(expected)")
        }
    }

    @Test func testConfigVersionHelpDescribesMigrationConditionallyWhenNoneIsPending() {
        let details = SettingsMigrationCopy.configVersionHelp(migrationPending: false)
        let pendingDetails = SettingsMigrationCopy.configVersionHelp(migrationPending: true)

        #expect(SettingHelpTopic.configVersion.content.details == details)
        #expect(pendingDetails == SettingsMigrationCopy.pending)
        #expect(details != pendingDetails)
        #expect(!(details.contains("This is a migration")))
        #expect(!(details.contains("No files change until Save")))
        #expect(details.contains("If you change a loaded Version 1 config to Version 2"))
    }
}

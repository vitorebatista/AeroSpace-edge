import AppKit
import Common
import SwiftUI

public let settingsWindowId = "\(aeroSpaceAppName).settings"

@MainActor
public func getSettingsWindow(model: SettingsModel, viewModel: TrayMenuModel) -> some Scene {
    // SwiftUI.Window because AeroSpace already has a class called Window
    SwiftUI.Window("\(aeroSpaceAppName) Settings", id: settingsWindowId) {
        SettingsView(model: model, viewModel: viewModel)
            .onAppear {
                // Without this an accessory-mode app's window can't receive keyboard input
                NSApp.setActivationPolicy(.accessory)
                model.load()
            }
    }
    .windowResizability(.contentMinSize)
}

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "General"
    case layout = "Layout"
    case gaps = "Gaps"
    case focus = "Focus"
    case windowBorder = "Window Border"
    case workspaces = "Workspaces & Monitors"
    case keyMapping = "Key Mapping"
    case exec = "Exec"
    case keybindings = "Keybindings"
    case windowRules = "Window Rules"
    case callbacks = "Callbacks"
    case menuBar = "Menu Bar"
    case application = "Application"

    var id: String { rawValue }

    /// The page in the Settings section of the site that documents this destination. The section
    /// is written to mirror the sidebar one-to-one, so the mapping is just the file name.
    var docsUrl: URL {
        let page = switch self {
            case .general: "general"
            case .layout: "layout"
            case .gaps: "gaps"
            case .focus: "focus"
            case .windowBorder: "window-border"
            case .workspaces: "workspaces"
            case .keyMapping: "key-mapping"
            case .exec: "exec"
            case .keybindings: "keybindings"
            case .windowRules: "window-rules"
            case .callbacks: "callbacks"
            case .menuBar: "menu-bar"
            case .application: "application"
        }
        return URL(string: "https://vitorebatista.github.io/AeroSpace-edge/settings/\(page)/")!
    }

    var systemImage: String {
        switch self {
            case .general: "gearshape"
            case .layout: "square.grid.2x2"
            case .gaps: "rectangle.split.3x1"
            case .focus: "scope"
            case .windowBorder: "rectangle.dashed"
            case .workspaces: "display.2"
            case .keyMapping: "keyboard"
            case .exec: "terminal"
            case .keybindings: "command"
            case .windowRules: "macwindow.badge.plus"
            case .callbacks: "arrow.triangle.branch"
            case .menuBar: "menubar.rectangle"
            case .application: "gearshape.2"
        }
    }
}

@MainActor
struct SettingsView: View {
    @StateObject private var model: SettingsModel
    @ObservedObject var viewModel: TrayMenuModel
    @State private var selection: SettingsCategory = .general
    @State private var showOverwriteAlert = false
    @State private var showMigrationAlert = false

    init(model: SettingsModel, viewModel: TrayMenuModel) {
        self._model = .init(wrappedValue: model)
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            switch model.mode {
                case .readOnly(let reason):
                    ScrollView { Text(reason).font(.body.monospaced()).padding() }
                case .rawOnly(let parseError):
                    rawOnlyBody(parseError: parseError)
                case .form:
                    NavigationSplitView {
                        List(SettingsCategory.allCases, selection: $selection) { category in
                            NavigationLink(value: category) {
                                Label(category.rawValue, systemImage: category.systemImage)
                            }
                        }
                        .navigationSplitViewColumnWidth(min: 190, ideal: 210)
                    } detail: {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                docsLink(for: selection)
                                section(for: selection)
                            }
                            .padding()
                        }
                    }
                    .disabled(model.isSaving)
            }
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    @ViewBuilder
    private func rawOnlyBody(parseError: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("This config doesn't parse, so only raw editing is available.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(parseError).font(.caption.monospaced()).textSelection(.enabled)
            TomlTextEditor(text: Binding(get: { model.wholeFileText }, set: { guard !model.isSaving else { return }; model.wholeFileText = $0; markDirty() }))
                .disabled(model.isSaving)
        }
        .padding()
    }

    /// The draft binding every section edits through.
    ///
    /// Writes are dropped while a save is in flight: `save()` suspends across the config
    /// reload with this window still live, and finishes with a `load()` that reseeds the
    /// draft from disk — so an edit landing in that gap would be silently thrown away.
    /// Freezing the form (and both footer buttons) for the duration makes that impossible
    /// rather than invisible.
    private var draft: Binding<ConfigTomlWriter.ConfigDraft> {
        Binding(get: { model.draft }, set: { if !model.isSaving { model.draft = $0 } })
    }

    /// Every destination links to its own page. The popovers explain one control at a time; the
    /// page is where the whole destination, its TOML keys and the surrounding behavior live.
    private func docsLink(for category: SettingsCategory) -> some View {
        HStack {
            Spacer()
            Link(destination: category.docsUrl) {
                Label("\(category.rawValue) documentation", systemImage: "book")
                    .font(.caption)
            }
            .help("Open the \(category.rawValue) documentation page in your browser")
        }
    }

    @ViewBuilder
    private func section(for category: SettingsCategory) -> some View {
        switch category {
            case .general: GeneralSection(draft: draft, migrationPending: model.requiresVersionMigration, onEdit: markDirty)
            case .layout: LayoutSection(draft: draft, onEdit: markDirty)
            case .focus: FocusSection(draft: draft, onEdit: markDirty)
            case .windowBorder: WindowBorderSection(draft: draft, onEdit: markDirty)
            case .gaps: GapsSection(draft: draft, loadGeneration: model.loadGeneration, onEdit: markDirty)
            case .workspaces: WorkspacesSection(draft: draft, onEdit: markDirty)
            case .keyMapping: KeyMappingSection(draft: draft, onEdit: markDirty)
            case .exec: ExecSection(draft: draft, onEdit: markDirty)
            case .keybindings:
                SettingsRawSection(
                    title: "Keybindings",
                    help: "Binding modes and their key bindings, as TOML. Each binding maps a key combination to one or more AeroSpace commands.",
                    docsHint: """
                        Tables: [mode.<name>.binding]. Example:
                        [mode.main.binding]
                        alt-h = 'focus left'
                        alt-shift-1 = 'move-node-to-workspace 1'
                        alt-r = ['mode resize']          # a list runs commands in order
                        'alt-custom.key' = 'focus left'  # quote a key with TOML punctuation
                        """,
                    text: draft.rawKeybindings,
                    preamble: keybindingsPreamble(preset: model.draft.keyMappingPreset, notationOverrides: model.draft.keyNotationToKeyCode),
                    onEdit: markDirty,
                )
            case .windowRules:
                SettingsRawSection(
                    title: "Window rules",
                    help: "Rules run when a window is first detected. Matchers: app-id, app-id-regex-substring, app-name-regex-substring, window-title-regex-substring, workspace, during-aerospace-startup.",
                    docsHint: """
                        Tables: [[on-window-detected]] with an 'if' matcher and a mandatory 'run'. Example:
                        [[on-window-detected]]
                        if.app-id = 'com.apple.systempreferences'
                        if.window-title-regex-substring = 'Settings'
                        run = ['layout floating']
                        """,
                    text: draft.rawWindowRules,
                    onEdit: markDirty,
                )
            case .callbacks:
                SettingsRawSection(
                    title: "Callbacks",
                    help: "Commands AeroSpace runs on lifecycle events.",
                    docsHint: """
                        Keys: \(ConfigTomlWriter.callbackKeys.joined(separator: ", ")). Example:
                        after-startup-command = 'exec-and-forget sketchybar'
                        on-focus-changed = ['move-mouse window-lazy-center']
                        """,
                    text: draft.rawCallbacks,
                    onEdit: markDirty,
                )
            case .menuBar:
                MenuBarSection(viewModel: viewModel)
            case .application:
                ApplicationSection()
        }
    }

    private func markDirty() {
        guard !model.isSaving else { return }
        model.isDirty = true
        model.status = nil
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .error(let message) = model.status {
                ScrollView {
                    Text(displayableErrorMessage(message))
                        .font(.caption.monospaced()).foregroundStyle(.red).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            } else if case .migrated(let backupUrl) = model.status {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Migrated to config version 2. Backup: \(backupUrl.path)")
                            .textSelection(.enabled)
                    }
                    .font(.caption)
                    .foregroundStyle(.green)
                    Button("Reveal Backup") {
                        NSWorkspace.shared.activateFileViewerSelecting([backupUrl])
                    }
                    .font(.caption)
                    .accessibilityHint("Reveals the migration backup in Finder")
                }
            }
            HStack {
                Button("Check for Updates…") { Task.startUnstructured { await runCheckForUpdatesFlow() } }
                    .disabled(model.isSaving)
                if model.willCreateConfig {
                    Text("Saving will create ~/\(configDotfileName)").font(.caption).foregroundStyle(.secondary)
                } else if case .saved = model.status {
                    Label("Saved and reloaded", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                }
                Spacer()
                Button("Revert") { model.revert() }.disabled(!model.isDirty || model.isSaving)
                Button("Save") { requestSave() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.isDirty || model.isSaving)
            }
        }
        .padding()
        .alert("The config file changed on disk", isPresented: $showOverwriteAlert) {
            Button("Overwrite") { confirmMigrationThenSave() }
            Button("Discard my changes") { model.load() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Someone or something edited the config after this window opened. Overwriting will lose those edits.")
        }
        .alert(SettingsMigrationCopy.confirmationTitle, isPresented: $showMigrationAlert) {
            Button("Migrate and Save") { beginSave() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(SettingsMigrationCopy.confirmationMessage)
        }
    }

    private func requestSave() {
        guard !model.isSaving else { return }
        if model.externallyModified {
            showOverwriteAlert = true
        } else {
            confirmMigrationThenSave()
        }
    }

    private func confirmMigrationThenSave() {
        if model.requiresVersionMigration {
            showMigrationAlert = true
        } else {
            beginSave()
        }
    }

    private func beginSave() {
        Task.startUnstructured { await model.save() }
    }

    /// `SettingsModel.save()` validates against a temp file and its error message embeds
    /// that temp file's path (e.g. `/var/folders/.../aerospace-settings-<uuid>.toml`), which
    /// is meaningless to the user. Substitute the real config path instead.
    private func displayableErrorMessage(_ message: String) -> String {
        guard let realPath = model.targetUrl?.path else { return message }
        var result = message
        // Replace every occurrence of the temp validation path with the real config path.
        // The marker "aerospace-settings-" is unique to the temp file name minted in
        // `SettingsModel.save()`; walk outward from it to the surrounding path boundaries.
        //
        // The search resumes past what was just substituted rather than restarting from
        // the beginning: `realPath` is the user's own config path and could itself contain
        // the marker, and re-finding it every pass would spin here forever — on the
        // MainActor, i.e. a hung app.
        var searchFrom = result.startIndex
        while let markerRange = result.range(of: "aerospace-settings-", range: searchFrom ..< result.endIndex) {
            var start = markerRange.lowerBound
            while start > result.startIndex {
                let prev = result.index(before: start)
                if result[prev].isWhitespace || result[prev] == "\"" || result[prev] == "'" { break }
                start = prev
            }
            guard let tomlRange = result.range(of: ".toml", range: markerRange.upperBound ..< result.endIndex) else { break }
            // Mutating invalidates every index into `result`, so carry the resume point
            // across as an offset and recompute it afterwards.
            let resumeOffset = result.distance(from: result.startIndex, to: start) + realPath.count
            result.replaceSubrange(start ..< tomlRange.upperBound, with: realPath)
            searchFrom = result.index(result.startIndex, offsetBy: resumeOffset, limitedBy: result.endIndex) ?? result.endIndex
        }
        return result
    }
}

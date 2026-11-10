import Common
import Foundation
import SwiftUI

enum MenuBarPrimaryAction: String, Identifiable {
    case toggleEnabled
    case settings
    case quit

    var id: String { rawValue }
}

let menuBarPrimaryActions: [MenuBarPrimaryAction] = [.toggleEnabled, .settings, .quit]

@MainActor
public func menuBar(viewModel: TrayMenuModel, openSettings: @escaping () -> Void) -> some Scene { // todo should it be converted to "SwiftUI struct"?
    MenuBarExtra {
        // No version line here: it lives in Settings → Application → Version, where it's copyable.
        if viewModel.axPermissionStatus == .granted {
            if let token: RunSessionGuard = .isServerEnabled, viewModel.lastReloadConfigContainedWarnings {
                Button {
                    Task.startUnstructured {
                        try await runLightSession(.menuBarButton, token) {
                            let args: ReloadConfigCmdArgs = ReloadConfigCmdArgs(rawArgs: []).with(\.warningsAsErrors, true)
                            _ = await reloadConfig_nonCancellable(args: args)
                        }
                    }
                } label: {
                    Label("Config contains warnings...", systemImage: "exclamationmark.triangle.fill")
                }
                Divider()
            }
            if let token: RunSessionGuard = .isServerEnabled {
                // Persistent workspaces first (in config order), then the rest alphabetically.
                let sorted = sortWorkspacesForMenuBar(viewModel.workspaces, persistentWorkspaces: config.persistentWorkspaces)
                let (inUse, available) = partitionWorkspacesForMenuBar(sorted)

                Text("Workspaces:")
                ForEach(inUse, id: \.name) { workspace in
                    workspaceButton(workspace, token: token)
                }
                // Empty workspaces go behind a submenu: with 10 configured workspaces and 2 in use, the
                // other 8 are just distance between the pointer and everything below them.
                if !available.isEmpty {
                    Menu {
                        ForEach(available, id: \.name) { workspace in
                            workspaceButton(workspace, token: token)
                        }
                    } label: {
                        Text("New")
                    }
                }
                Divider()
            }
            ForEach(menuBarPrimaryActions) { action in
                primaryMenuButton(action, viewModel: viewModel, openSettings: openSettings)
            }
        } else {
            Button("\(aeroSpaceAppName) requires accessibility permission to move windows") {
                viewModel.axPermissionStatus = .waitingWithPrompt
            }
            primaryMenuButton(.quit, viewModel: viewModel, openSettings: openSettings)
        }
    } label: {
        switch (viewModel.axPermissionStatus, viewModel.isEnabled) {
            case (.granted, true):
                MenuBarLabel().environmentObject(viewModel)
            case (.granted, false):
                Image(systemName: "pause.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case (_, _):
                Image(systemName: "exclamationmark.triangle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
        }
    }
}

@MainActor @ViewBuilder
private func primaryMenuButton(
    _ action: MenuBarPrimaryAction,
    viewModel: TrayMenuModel,
    openSettings: @escaping () -> Void,
) -> some View {
    switch action {
        case .toggleEnabled:
            Button(viewModel.isEnabled ? "Disable" : "Enable") {
                Task.startUnstructured {
                    try await runLightSession(.menuBarButton, .forceRun) {
                        _ = await EnableCommand(args: EnableCmdArgs(rawArgs: [], targetState: .toggle))
                            .run(.defaultEnv, .emptyStdin)
                    }
                }
            }.keyboardShortcut("E", modifiers: .command)
        case .settings:
            settingsWindowButton(openSettings: openSettings)
        case .quit:
            Button("Quit \(aeroSpaceAppName)") {
                Task.startUnstructured {
                    terminationHandler?.beforeTermination()
                    terminateApp()
                }
            }.keyboardShortcut("Q", modifiers: .command)
    }
}

@MainActor @ViewBuilder
func workspaceButton(_ workspace: WorkspaceViewModel, token: RunSessionGuard) -> some View {
    Button {
        Task.startUnstructured {
            try await runLightSession(.menuBarButton, token) { _ = Workspace.get(byName: workspace.name).focusWorkspace() }
        }
    } label: {
        Toggle(isOn: .constant(workspace.isFocused)) {
            Text(workspace.name + workspace.suffix).font(.system(.body, design: .monospaced))
        }
    }
}

/// Splits workspaces into the ones the menu shows directly and the ones hidden behind "New".
///
/// "In use" is deliberately wider than "has windows": a workspace that's on screen, or focused, belongs
/// at the top level even while empty — it's where the user already is, and having it disappear into a
/// submenu the moment its last window closes would be disorienting.
/// Relative order within each group is preserved, so the caller's sort still decides ordering.
func partitionWorkspacesForMenuBar(
    _ workspaces: [WorkspaceViewModel],
) -> (inUse: [WorkspaceViewModel], available: [WorkspaceViewModel]) {
    var inUse: [WorkspaceViewModel] = []
    var available: [WorkspaceViewModel] = []
    for workspace in workspaces {
        switch !workspace.isEffectivelyEmpty || workspace.isVisible || workspace.isFocused {
            case true: inUse.append(workspace)
            case false: available.append(workspace)
        }
    }
    return (inUse, available)
}

@MainActor @ViewBuilder
func openConfigButton(showShortcutGroup: Bool = false) -> some View {
    let editor = getTextEditorToOpenConfig()
    let button = Button("Open config in '\(editor.lastPathComponent)'") {
        let fallbackConfig: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: configDotfileName)
        switch findCustomConfigUrl() {
            case .file(let url):
                url.open(with: editor)
            case .noCustomConfigExists:
                _ = try? FileManager.default.copyItem(atPath: defaultConfigUrl.path, toPath: fallbackConfig.path)
                fallbackConfig.open(with: editor)
            case .ambiguousConfigError:
                fallbackConfig.open(with: editor)
        }
    }.keyboardShortcut(",", modifiers: .command)
    switch showShortcutGroup {
        case true: shortcutGroup(label: Text("⌘ ,"), content: button)
        case false: button
    }
}

@MainActor @ViewBuilder
func settingsWindowButton(openSettings: @escaping () -> Void) -> some View {
    Button("Settings…") {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == settingsWindowId }) {
            // Already open: just bring it forward. Do NOT reload here — `SettingsModel.load()`
            // resets `isDirty` and overwrites `draft` from disk, which would silently discard
            // an unsaved edit in a window the user only backgrounded, not closed.
            window.makeKeyAndOrderFront(nil)
        } else {
            // Not open (first click ever, or the user closed it): `SettingsView.onAppear`
            // calls `model.load()` once the new window's content view is created, so there's
            // nothing to load here.
            openSettings()
        }
    }
}

@MainActor @ViewBuilder
func reloadConfigButton(showShortcutGroup: Bool = false, warningsAsErrors: Bool = false) -> some View {
    if let token: RunSessionGuard = .isServerEnabled {
        let button = Button("Reload config") {
            Task.startUnstructured {
                try await runLightSession(.menuBarButton, token) {
                    let args: ReloadConfigCmdArgs = ReloadConfigCmdArgs(rawArgs: []).with(\.warningsAsErrors, warningsAsErrors)
                    _ = await reloadConfig_nonCancellable(args: args)
                }
            }
        }.keyboardShortcut("R", modifiers: .command)
        switch showShortcutGroup {
            case true: shortcutGroup(label: Text("⌘ R"), content: button)
            case false: button
        }
    }
}

func shortcutGroup(label: some View, content: some View) -> some View {
    GroupBox {
        VStack(alignment: .trailing, spacing: 6) {
            label
                .foregroundStyle(Color.secondary)
            content
        }
    }
}

/// Orders workspaces for the menu bar: persistent workspaces first (in `persistentWorkspaces`
/// config order), followed by all remaining workspaces sorted alphabetically by name.
/// Pure function extracted from the menu bar view so the ordering is unit-testable.
func sortWorkspacesForMenuBar(_ workspaces: [WorkspaceViewModel], persistentWorkspaces: some Sequence<String>) -> [WorkspaceViewModel] {
    // Build a lookup of persistent workspace name -> position in the config order.
    let persistentOrderIndex: [String: Int] =
        Dictionary(uniqueKeysWithValues: persistentWorkspaces.enumerated().map { ($0.element, $0.offset) })

    return workspaces.sorted { a, b in
        let ia = persistentOrderIndex[a.name]
        let ib = persistentOrderIndex[b.name]

        if let ia, let ib {
            return ia < ib                // both are in persistent list
        } else if ia != nil {
            return true                   // only a is in persistent list
        } else if ib != nil {
            return false                  // only b is in persistent list
        } else {
            return a.name < b.name        // neither is in persistent list
        }
    }
}

func getTextEditorToOpenConfig() -> URL {
    NSWorkspace.shared.urlForApplication(toOpen: findCustomConfigUrl().urlOrNil ?? defaultConfigUrl)?
        .takeIf { $0.lastPathComponent != "Xcode.app" } // Blacklist Xcode. It is too heavy to open plain text files
        ?? URL(filePath: "/System/Applications/TextEdit.app")
}

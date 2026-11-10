import Common
import Foundation
import SwiftUI
import TOMLDecoder

enum SettingsMode: Equatable {
    /// The config parsed; the full form is available.
    case form
    /// The config did not parse, so there is no `Config` to bind a form to. One raw editor
    /// over the whole file, with the parser's message.
    case rawOnly(parseError: String)
    /// Several config files exist and it is not our place to guess which one to write.
    case readOnly(reason: String)
}

enum SettingsStatus: Equatable {
    case error(String)
    case migrated(backupUrl: URL)
    case saved
}

private struct SettingsReloadError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct SettingsCandidateWriteError: LocalizedError {
    let underlying: any Error
    let targetMayHaveChanged: Bool

    var errorDescription: String? { underlying.localizedDescription }
}

@MainActor
public final class SettingsModel: ObservableObject {
    // `public` because `AeroSpaceApp` (a separate SPM target) holds `.shared` as a
    // `@StateObject` to keep it alive for the settings window's lifetime.
    public static let shared = SettingsModel()

    @Published var draft: ConfigTomlWriter.ConfigDraft = ConfigTomlWriter.ConfigDraft.defaults
    @Published var mode: SettingsMode = .form
    @Published var isDirty = false
    /// `true` while `save()` is in flight. The save suspends across the config reload with
    /// the window still interactive, so the UI freezes its bindings and both footer buttons
    /// for the duration — see `save()`.
    @Published private(set) var isSaving = false
    @Published var status: SettingsStatus?
    @Published var wholeFileText = ""
    /// Bumped every time `load()` reseeds `draft` from disk (Revert, or the reload at the
    /// end of a successful `save()`). Sections that keep their own local "what was here
    /// before" memory across a value round trip — see `GapRow.lastKnownRules` — watch this
    /// to know when that memory refers to a document that no longer exists, since the
    /// value it was shadowing can come back looking identical (e.g. `.constant(5)` both
    /// before and after a revert) with no other signal that it changed out from under them.
    @Published private(set) var loadGeneration = 0

    /// The file we read and will write, as the config lookup spelled it. Kept unresolved
    /// because it is what the user recognises in a message; `writeUrl` is what we touch.
    private(set) var targetUrl: URL?
    /// `true` when no custom config exists yet, so saving creates `~/<configDotfileName>`.
    private(set) var willCreateConfig = false
    private var document = TomlBlockDocument("")
    /// `draft` as `load()` read it, before the user touched anything. `apply` compares
    /// against it so a region the user never went near is left byte-for-byte alone.
    private var loadedDraft: ConfigTomlWriter.ConfigDraft = ConfigTomlWriter.ConfigDraft.defaults
    private var loadedModificationDate: Date?
    private let configFileProvider: () -> ConfigFile
    private let bundledDefaultConfigUrl: URL
    private let fileManager: FileManager
    private let backupCreator: (URL, Int) throws -> ConfigMigrationBackup
    private let atomicWriter: (Data, URL, Int?) throws -> Void
    private let reloadAfterSave: () async throws -> Void

    init(
        configFile: @escaping () -> ConfigFile = { findCustomConfigUrl() },
        bundledDefaultConfigUrl: URL = defaultConfigUrl,
        fileManager: FileManager = .default,
        backupCreator: @escaping (URL, Int) throws -> ConfigMigrationBackup = {
            try ConfigMigrationBackup.create(forResolvedTarget: $0, fromVersion: $1)
        },
        atomicWriter: ((Data, URL, Int?) throws -> Void)? = nil,
        reloadAfterSave: @escaping () async throws -> Void = {
            try await SettingsModel.reloadCurrentConfig()
        },
    ) {
        configFileProvider = configFile
        self.bundledDefaultConfigUrl = bundledDefaultConfigUrl
        self.fileManager = fileManager
        self.backupCreator = backupCreator
        self.atomicWriter = atomicWriter ?? {
            try Self.writeCandidateAtomically($0, to: $1, permissions: $2, fileManager: fileManager)
        }
        self.reloadAfterSave = reloadAfterSave
    }

    /// The path writes actually land on. `write(to:atomically:)` renames a fresh temp file
    /// over the path, which replaces a *symlink* with a regular file instead of writing
    /// through it — a config symlinked into a dotfiles repo would be silently detached and
    /// the real file left holding the old contents. Resolving first also keeps the
    /// modification-date check and the write looking at the same file.
    private var writeUrl: URL? { targetUrl?.resolvingSymlinksInPath() }

    var requiresVersionMigration: Bool {
        guard case .form = mode else { return false }
        return loadedDraft.configVersion == 1 && draft.configVersion == 2
    }

    /// `true` if the file changed on disk since `load()`. Checked before overwriting.
    var externallyModified: Bool {
        guard let writeUrl, let loadedModificationDate else { return false }
        guard let current = modificationDate(of: writeUrl) else { return false }
        return current != loadedModificationDate
    }

    private func modificationDate(of url: URL) -> Date? {
        try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    func load() {
        status = nil
        isDirty = false
        loadGeneration += 1

        switch configFileProvider() {
            case .ambiguousConfigError(let candidates):
                mode = .readOnly(reason: """
                    Several AeroSpace configs exist, so the settings window will not guess which one to write:

                    \(candidates.map(\.path).joined(separator: "\n"))

                    Remove or rename all but one, then reopen Settings.
                    """)
                targetUrl = nil
                return
            case .file(let url):
                targetUrl = url
                willCreateConfig = false
            case .noCustomConfigExists:
                // Read the bundled default, but write to the user's own dotfile.
                targetUrl = fileManager.homeDirectoryForCurrentUser.appending(path: configDotfileName)
                willCreateConfig = true
        }

        let sourceUrl = willCreateConfig ? bundledDefaultConfigUrl : targetUrl.orDie()
        let text = (try? String(contentsOf: sourceUrl, encoding: .utf8)) ?? ""
        document = TomlBlockDocument(text)
        wholeFileText = text
        // Read through the resolved path, the same one `save()` writes, so the two agree
        // when the config is a symlink (`attributesOfItem` does not follow one).
        loadedModificationDate = willCreateConfig ? nil : writeUrl.flatMap(modificationDate(of:))

        // Only errors drop the form: upstream warnings (e.g. an outdated config-version) don't stop AeroSpace
        // loading the config, so they don't stop the Settings window editing it either.
        let parsed = parseConfig(text)
        let config = parsed.config
        let errors = parsed.errorMessages
        if errors.isEmpty {
            // `parseConfig` expands `[exec]` into the full environment, which is not
            // writable back. Recover the file's own `[exec]` values instead.
            draft = ConfigTomlWriter.draft(from: config, rawExec: Self.rawExecConfig(from: text), document: document)
            loadedDraft = draft
            mode = .form
        } else {
            mode = .rawOnly(parseError: errors.joined(separator: "\n\n"))
        }
    }

    func revert() { load() }

    /// Renders the draft, validates it with the real parser against a temp file, and only
    /// then writes the user's config and reloads. A bad edit can never leave the user with
    /// a config AeroSpace refuses to load.
    ///
    /// `isSaving` is set for the whole of this, because it suspends (the reload awaits
    /// `activateMode`) with the MainActor free and the window live: without it a keystroke
    /// landing in that gap would be silently overwritten by the closing `load()`, and a
    /// second click on Save would start an overlapping save.
    func save() async {
        guard let targetUrl, let writeUrl, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        status = nil

        let migrationRequired = requiresVersionMigration
        let migration: ConfigMigrationCandidate?
        let candidate: String
        switch mode {
            case .form:
                if migrationRequired {
                    let migrationResult = ConfigMigrator.migrate(
                        text: document.render(),
                        from: loadedDraft.configVersion,
                        to: draft.configVersion,
                    )
                    let migrated: ConfigMigrationCandidate
                    switch migrationResult {
                        case .failure(let error):
                            status = .error("Can't migrate the config: \(error)")
                            return
                        case .success(let value):
                            migrated = value
                    }
                    migration = migrated

                    let migratedDocument = TomlBlockDocument(migrated.text)
                    let migratedParse = parseConfig(migrated.text)
                    let migratedConfig = migratedParse.config
                    let errors = migratedParse.errorMessages
                    guard errors.isEmpty else {
                        status = .error(errors.joined(separator: "\n\n"))
                        return
                    }
                    let migratedBaseline = ConfigTomlWriter.draft(
                        from: migratedConfig,
                        rawExec: Self.rawExecConfig(from: migrated.text),
                        document: migratedDocument,
                    )
                    var editedDraft = draft
                    if draft.persistentWorkspaces == loadedDraft.persistentWorkspaces {
                        editedDraft.persistentWorkspaces = .init(migrated.persistentWorkspaces)
                    }
                    var working = migratedDocument
                    ConfigTomlWriter.apply(editedDraft, original: migratedBaseline, to: &working)
                    candidate = working.render()
                } else {
                    migration = nil
                    var working = document
                    ConfigTomlWriter.apply(draft, original: loadedDraft, to: &working)
                    candidate = working.render()
                }
            case .rawOnly:
                migration = nil
                candidate = wholeFileText
            case .readOnly:
                return
        }

        let tempUrl = fileManager.temporaryDirectory
            .appending(path: "aerospace-settings-\(UUID().uuidString).toml")
        defer { try? fileManager.removeItem(at: tempUrl) }
        do {
            try candidate.write(to: tempUrl, atomically: true, encoding: .utf8)
        } catch {
            status = .error("Can't write a temporary file for validation: \(error.localizedDescription)")
            return
        }

        // Errors block the save; warnings don't (the reload below accepts them too, and the menu bar shows them)
        switch readConfig(forceConfigUrl: tempUrl).asResult {
            case .failure(let message):
                status = .error(message)
                return
            case .success:
                break
        }

        let backup: ConfigMigrationBackup?
        if let migration {
            do {
                backup = try backupCreator(writeUrl, migration.fromVersion)
            } catch {
                status = .error("Can't back up \(targetUrl.path): \(error.localizedDescription)")
                return
            }
        } else {
            backup = nil
        }

        let targetExisted = fileManager.fileExists(atPath: writeUrl.path)
        let originalData: Data?
        let originalPermissions: Int?
        do {
            if let backup {
                originalData = nil
                originalPermissions = try Self.permissions(of: backup.url, fileManager: fileManager)
            } else if targetExisted {
                originalData = try Data(contentsOf: writeUrl)
                originalPermissions = try Self.permissions(of: writeUrl, fileManager: fileManager)
            } else {
                originalData = nil
                originalPermissions = nil
            }
        } catch {
            status = .error("Can't read \(targetUrl.path) before saving: \(error.localizedDescription)")
            return
        }

        do {
            try atomicWriter(Data(candidate.utf8), writeUrl, originalPermissions)
        } catch {
            if let writeError = error as? SettingsCandidateWriteError, !writeError.targetMayHaveChanged {
                status = .error("Can't write \(targetUrl.path): \(writeError.localizedDescription)")
                return
            }
            do {
                try restoreOriginalTarget(
                    at: writeUrl,
                    targetExisted: targetExisted,
                    originalData: originalData,
                    originalPermissions: originalPermissions,
                    backup: backup,
                )
                status = .error("Can't write \(targetUrl.path): \(error.localizedDescription)")
            } catch let restorationError {
                status = .error(
                    "Can't write \(targetUrl.path): \(error.localizedDescription). " +
                        "Restoring the original also failed: \(restorationError.localizedDescription)",
                )
            }
            return
        }

        do {
            try await reloadAfterSave()
        } catch {
            let backupMessage = backup.map { " Backup: \($0.url.path)." } ?? ""
            load() // The disk write succeeded; retries must use its v2 document as baseline.
            status = .error("Saved, but reloading the config failed:\(backupMessage) \(error.localizedDescription)")
            return
        }

        load() // re-read from disk so the form and the document match the file exactly
        status = backup.map { .migrated(backupUrl: $0.url) } ?? .saved
    }

    private func restoreOriginalTarget(
        at writeUrl: URL,
        targetExisted: Bool,
        originalData: Data?,
        originalPermissions: Int?,
        backup: ConfigMigrationBackup?,
    ) throws {
        guard targetExisted else {
            if fileManager.fileExists(atPath: writeUrl.path) {
                try fileManager.removeItem(at: writeUrl)
            }
            return
        }

        let data = try backup.map { try Data(contentsOf: $0.url) } ?? originalData.orDie()
        try Self.writeCandidateAtomically(
            data,
            to: writeUrl,
            permissions: originalPermissions,
            fileManager: fileManager,
        )
    }

    static func writeCandidateAtomically(
        _ data: Data,
        to target: URL,
        permissions: Int?,
        fileManager: FileManager = .default,
        applyPermissions: ((Int, URL) throws -> Void)? = nil,
    ) throws {
        let stagingUrl = target.deletingLastPathComponent()
            .appending(path: ".\(target.lastPathComponent).aerospace-settings-\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: stagingUrl) }

        do {
            try data.write(to: stagingUrl, options: .withoutOverwriting)
            if let permissions {
                if let applyPermissions {
                    try applyPermissions(permissions, stagingUrl)
                } else {
                    try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: stagingUrl.path)
                }
            }
        } catch {
            throw SettingsCandidateWriteError(underlying: error, targetMayHaveChanged: false)
        }

        do {
            if fileManager.fileExists(atPath: target.path) {
                _ = try fileManager.replaceItemAt(
                    target,
                    withItemAt: stagingUrl,
                    backupItemName: nil,
                    options: .usingNewMetadataOnly,
                )
            } else {
                try fileManager.moveItem(at: stagingUrl, to: target)
            }
        } catch {
            throw SettingsCandidateWriteError(underlying: error, targetMayHaveChanged: true)
        }
    }

    private static func permissions(of url: URL, fileManager: FileManager) throws -> Int? {
        let value = try fileManager.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        return value?.intValue
    }

    private static func reloadCurrentConfig() async throws {
        // Mirror `reloadConfigButton`: a reload swaps the config in, and the windows only
        // pick up the new gaps/normalization once a refresh session relays them out.
        if let token: RunSessionGuard = .isServerEnabled {
            try await runLightSession(.menuBarButton, token) { try await reloadConfigOrThrow() }
        } else {
            try await reloadConfigOrThrow()
        }
    }

    /// Warnings don't fail the reload (`isOk` only counts errors unless `--warnings-as-errors` is passed)
    private static func reloadConfigOrThrow() async throws {
        let result = await reloadConfig_nonCancellable()
        if !result.isOk {
            throw SettingsReloadError(message: result.stdout)
        }
    }

    /// Recovers `inherit-env-vars` and the override map exactly as written in the file,
    /// which `Config` cannot give back: `Config.execConfig` holds the *expanded*
    /// environment, and `parseEnvVariables` has already interpolated every `$VAR`.
    ///
    /// This deliberately re-deserialises the config text with `TOMLDecoder` — the same
    /// deserialiser `parseConfig` runs — rather than reading values out of the block
    /// document. The block document carries source text verbatim and does not interpret
    /// it, so recovering values from it means hand-lexing TOML, and every gap in that lexer
    /// (a trailing comment, a partially quoted value, `exec.inherit-env-vars` written as a
    /// dotted key with no `[exec]` header) silently produces a *valid* wrong value that
    /// `save()`'s validation pass cannot catch. Going through the real deserialiser removes
    /// the whole class. It is un-interpolated because interpolation happens later, in
    /// `parseEnvVariables`, which is exactly what we need to write back.
    nonisolated static func rawExecConfig(from configText: String) -> RawExecConfig {
        var result = RawExecConfig()
        guard let root = try? [String: Any](TOMLTable(source: configText)),
              let exec = root["exec"] as? [String: Any]
        else {
            return result
        }
        if let inheritEnvVars = exec["inherit-env-vars"] as? Bool { result.inheritEnvVariables = inheritEnvVars }
        // Non-string values are left out on purpose: the real parser rejects them, and
        // `save()`'s validation pass will report that against the user's own text.
        for (name, value) in exec["env-vars"] as? [String: Any] ?? [:] {
            if let value = value as? String { result.overriddenVars[name] = value }
        }
        return result
    }
}

@testable import AppBundle
import Common
import Foundation
import Testing

@MainActor
@Suite(.serializedGlobally)
struct SettingsModelTest {
    private enum ExpectedFailure: Error {
        case backup
        case permissions
        case write
        case reload
    }

    @Test func testInheritEnvVarsWithATrailingComment() {
        let raw = SettingsModel.rawExecConfig(from: "[exec]\ninherit-env-vars = true  # keep my PATH\n")
        assertEquals(raw.inheritEnvVariables, true)
    }

    @Test func testEnvVarWithATrailingComment() {
        let raw = SettingsModel.rawExecConfig(from: """
            [exec.env-vars]
            PATH = '/opt/homebrew/bin' # my path
            """)
        assertEquals(raw.overriddenVars["PATH"], "/opt/homebrew/bin")
    }

    @Test func testDottedKeyFormIsSeen() {
        // No `[exec]` header at all. Missing this used to leave the draft on the default
        // `true`, after which the writer deleted the dotted key and wrote nothing back.
        let raw = SettingsModel.rawExecConfig(from: "exec.inherit-env-vars = false\n")
        assertEquals(raw.inheritEnvVariables, false)
    }

    @Test func testDottedEnvVarKeyIsSeen() {
        let raw = SettingsModel.rawExecConfig(from: "exec.env-vars.FOO = 'bar'\n")
        assertEquals(raw.overriddenVars["FOO"], "bar")
    }

    @Test func testQuotedEnvVarKeyIsSeenAsOneName() {
        // A dot in a quoted TOML key is part of the environment variable's name, not a
        // nested table. This is the spelling ConfigTomlWriter emits for UI input such as
        // "MY.PATH", so recovering it correctly is required before the user edits [exec].
        let raw = SettingsModel.rawExecConfig(from: "[exec.env-vars]\n'MY.PATH' = 'bin'\n")
        assertEquals(raw.overriddenVars, ["MY.PATH": "bin"])
    }

    @Test func testValuesAreNotInterpolated() {
        // `$VAR` has to come back exactly as written: this value is destined to be written
        // straight back into the user's file, not to be executed.
        let raw = SettingsModel.rawExecConfig(from: "[exec.env-vars]\nPATH = '/my/bin:${PATH}'\n")
        assertEquals(raw.overriddenVars["PATH"], "/my/bin:${PATH}")
    }

    @Test func testEscapesInABasicStringAreResolved() {
        let raw = SettingsModel.rawExecConfig(from: #"""
        [exec.env-vars]
        QUOTED = "a\"b"
        """#)
        assertEquals(raw.overriddenVars["QUOTED"], #"a"b"#)
    }

    @Test func testDefaultsWhenThereIsNoExecTable() {
        let raw = SettingsModel.rawExecConfig(from: "start-at-login = true\n")
        assertEquals(raw.inheritEnvVariables, true)
        assertEquals(raw.overriddenVars, [:])
    }

    @Test func testUnparseableConfigFallsBackToDefaults() {
        let raw = SettingsModel.rawExecConfig(from: "this is not toml [[[\n")
        assertEquals(raw.inheritEnvVariables, true)
        assertEquals(raw.overriddenVars, [:])
    }

    @Test func testRequiresVersionMigrationOnlyForLoadedV1DraftV2() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "config.toml")
        try Data(v1Config.utf8).write(to: target)
        let model = makeModel(target: target)

        model.load()
        #expect(!model.requiresVersionMigration)

        model.draft.configVersion = 2
        #expect(model.requiresVersionMigration)

        model.draft.configVersion = 1
        #expect(!model.requiresVersionMigration)
    }

    @Test func testMigrationBacksUpOriginalAndAppliesDraftEditsToMigratedBaseline() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "config.toml")
        let original = Data(v1Config.utf8)
        try original.write(to: target)
        let model = makeModel(target: target)
        model.load()
        model.draft.configVersion = 2
        model.draft.startAtLogin = true

        await model.save()

        guard case .migrated(let backupUrl) = model.status else {
            Issue.record(Comment(rawValue: "Expected migrated status, got \(String(describing: model.status))"))
            return
        }
        #expect(backupUrl == backupUrl.absoluteURL)
        #expect(backupUrl.deletingLastPathComponent() == directory)
        #expect(try Data(contentsOf: backupUrl) == original)
        let written = try String(contentsOf: target, encoding: .utf8)
        #expect(written.contains("config-version = 2"))
        #expect(written.contains("persistent-workspaces = ['two', 'one', 'assigned']"))
        #expect(written.contains("start-at-login = true"))
        #expect(written.contains("# untouched marker"))
    }

    @Test func testMigrationKeepsUserEditedPersistentWorkspaceOrder() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "config.toml")
        try Data(v1Config.utf8).write(to: target)
        let model = makeModel(target: target)
        model.load()
        model.draft.configVersion = 2
        model.draft.persistentWorkspaces = ["custom", "two"]

        await model.save()

        let written = try String(contentsOf: target, encoding: .utf8)
        #expect(written.contains("persistent-workspaces = ['custom', 'two']"))
    }

    @Test func testInvalidMigrationCandidateCreatesNoBackupAndDoesNotChangeTarget() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "config.toml")
        let original = Data(v1Config.utf8)
        try original.write(to: target)
        let originalDirectoryEntries = try directoryEntries(in: directory)
        let model = makeModel(target: target)
        model.load()
        model.draft.configVersion = 2
        model.draft.rawKeybindings = "[mode.main.binding]\nalt-a = 'not-a-command'\n"

        await model.save()

        assertIsError(model.status)
        #expect(try Data(contentsOf: target) == original)
        #expect(try directoryEntries(in: directory) == originalDirectoryEntries)
    }

    @Test func testBackupCreatorFailureBeforeWritingLeavesTargetAndDirectoryUnchanged() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "config.toml")
        let original = Data(v1Config.utf8)
        try original.write(to: target)
        let originalDirectoryEntries = try directoryEntries(in: directory)
        let model = makeModel(
            target: target,
            backupCreator: { _, _ in throw ExpectedFailure.backup },
            atomicWriter: { data, url, _ in try data.write(to: url, options: .atomic) },
        )
        model.load()
        model.draft.configVersion = 2

        await model.save()

        assertIsError(model.status)
        #expect(try Data(contentsOf: target) == original)
        #expect(try directoryEntries(in: directory) == originalDirectoryEntries)
    }

    @Test func testWriteFailureAfterBackupRestoresExactOriginalBytes() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "config.toml")
        let original = Data(v1Config.replacingOccurrences(of: "\n", with: "\r\n").utf8)
        try original.write(to: target)
        let model = makeModel(
            target: target,
            atomicWriter: { _, url, _ in
                try Data("corrupted".utf8).write(to: url, options: .atomic)
                throw ExpectedFailure.write
            },
        )
        model.load()
        model.draft.configVersion = 2

        await model.save()

        assertIsError(model.status)
        #expect(try Data(contentsOf: target) == original)
        let backups = try backupUrls(in: directory)
        #expect(backups.count == 1)
        let firstBackup = try #require(backups.first)
        #expect(try Data(contentsOf: firstBackup) == original)
    }

    @Test func testSavingUnrelatedV1EditCreatesNoBackup() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "config.toml")
        try Data(v1Config.utf8).write(to: target)
        let model = makeModel(target: target)
        model.load()
        model.draft.startAtLogin = true

        await model.save()

        #expect(model.status == .saved)
        #expect(try backupUrls(in: directory) == [])
        let written = try String(contentsOf: target, encoding: .utf8)
        #expect(!(written.contains("config-version = 2")))
        #expect(written.contains("start-at-login = true"))
    }

    @Test func testMigrationThroughSymlinkPreservesLinkTargetPermissionsAndBackupPlacement() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let targetDirectory = directory.appending(path: "dotfiles", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        let target = targetDirectory.appending(path: "aerospace.toml")
        let original = Data(v1Config.utf8)
        try original.write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: target.path)
        let symlink = directory.appending(path: ".aerospace.toml")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
        let model = makeModel(target: symlink)
        model.load()
        model.draft.configVersion = 2

        await model.save()

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: symlink.path) == target.path)
        #expect(try Data(contentsOf: target) != original)
        #expect(try permissions(of: target) == 0o640)
        let backups = try backupUrls(in: targetDirectory)
        #expect(backups.count == 1)
        let firstBackup = try #require(backups.first)
        #expect(try Data(contentsOf: firstBackup) == original)
        #expect(try backupUrls(in: directory) == [])
        guard case .migrated(let backupUrl) = model.status else {
            Issue.record(Comment(rawValue: "Expected migrated status, got \(String(describing: model.status))"))
            return
        }
        #expect(backupUrl.resolvingSymlinksInPath() == backups.first?.resolvingSymlinksInPath())
    }

    @Test func testReloadFailureSynchronizesMigratedBaselineBeforeRetry() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "config.toml")
        let original = Data(v1Config.utf8)
        try original.write(to: target)
        var reloadAttempts = 0
        let model = makeModel(target: target, reloadAfterSave: {
            reloadAttempts += 1
            if reloadAttempts == 1 { throw ExpectedFailure.reload }
        })
        model.load()
        model.draft.configVersion = 2

        await model.save()

        let message = assertIsError(model.status)
        let backup = try #require(try backupUrls(in: directory).first)
        #expect(message.contains(backup.resolvingSymlinksInPath().path))
        #expect(try Data(contentsOf: target) != original)
        #expect(try Data(contentsOf: backup) == original)
        #expect(!model.requiresVersionMigration)

        await model.save()

        #expect(model.status == .saved)
        #expect(reloadAttempts == 2)
        #expect(try backupUrls(in: directory) == [backup])
    }

    @Test func testCandidatePermissionFailureLeavesOriginalBytesAndModeUntouched() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "config.toml")
        let original = Data(v1Config.utf8)
        try original.write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: target.path)

        #expect(throws: (any Error).self) {
            try SettingsModel.writeCandidateAtomically(
                Data("candidate".utf8),
                to: target,
                permissions: 0o640,
                applyPermissions: { _, _ in throw ExpectedFailure.permissions },
            )
        }

        #expect(try Data(contentsOf: target) == original)
        #expect(try permissions(of: target) == 0o640)
    }

    @Test func testCandidateWriteFailureLeavesOriginalBytesAndModeUntouched() throws {
        let directory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let target = directory.appending(path: "config.toml")
        let original = Data(v1Config.utf8)
        try original.write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: target.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)

        #expect(throws: (any Error).self) {
            try SettingsModel.writeCandidateAtomically(
                Data("candidate".utf8),
                to: target,
                permissions: 0o640,
            )
        }

        #expect(try Data(contentsOf: target) == original)
        #expect(try permissions(of: target) == 0o640)
    }

    private var v1Config: String {
        """
        # untouched marker
        [mode.main.binding]
        alt-2 = 'workspace two'
        alt-1 = 'move-node-to-workspace one'

        [workspace-to-monitor-force-assignment]
        assigned = 'main'
        """
    }

    private func makeModel(
        target: URL,
        backupCreator: @escaping (URL, Int) throws -> ConfigMigrationBackup = {
            try ConfigMigrationBackup.create(forResolvedTarget: $0, fromVersion: $1)
        },
        atomicWriter: ((Data, URL, Int?) throws -> Void)? = nil,
        reloadAfterSave: @escaping () async throws -> Void = {},
    ) -> SettingsModel {
        SettingsModel(
            configFile: { .file(target) },
            backupCreator: backupCreator,
            atomicWriter: atomicWriter,
            reloadAfterSave: reloadAfterSave,
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SettingsModelTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func directoryEntries(in directory: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
    }

    private func backupUrls(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains(".backup-v") }
    }

    @discardableResult
    private func assertIsError(
        _ status: SettingsStatus?,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) -> String {
        guard case .error(let message) = status else {
            Issue.record(Comment(rawValue: "Expected error status, got \(String(describing: status))"), sourceLocation: sourceLocation)
            return ""
        }
        return message
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? NSNumber).intValue
    }
}

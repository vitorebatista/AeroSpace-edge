@testable import AppBundle
import Foundation
import Testing

@MainActor
@Suite(.serializedGlobally)
final class ConfigMigrationBackupTest {
    private let fileManager = FileManager.default
    private let temporaryDirectory: URL

    init() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "ConfigMigrationBackupTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    @Test func testBackupPreservesTheExactSourceBytes() throws {
        let target = temporaryDirectory.appending(path: "config.toml")
        let source = Data([0x00, 0x0A, 0x80, 0xFF])
        try source.write(to: target)

        let backup = try ConfigMigrationBackup.create(
            forResolvedTarget: target,
            fromVersion: 1,
            now: fixedDate,
        )

        #expect(try Data(contentsOf: backup.url) == source)
    }

    @Test func testBackupNameContainsSourceVersionAndTimestamp() throws {
        let target = temporaryDirectory.appending(path: ".aerospace.toml")
        try Data("source".utf8).write(to: target)

        let backup = try ConfigMigrationBackup.create(
            forResolvedTarget: target,
            fromVersion: 1,
            now: fixedDate,
        )

        #expect(backup.url.lastPathComponent == ".aerospace.toml.backup-v1-20260829-203000")
        #expect(backup.url.standardizedFileURL == backup.url.absoluteURL)
    }

    @Test func testBackupUsesNumericSuffixesWithoutOverwritingCollisions() throws {
        let target = temporaryDirectory.appending(path: "config.toml")
        try Data("source".utf8).write(to: target)
        let firstCollision = temporaryDirectory.appending(path: "config.toml.backup-v1-20260829-203000")
        let secondCollision = temporaryDirectory.appending(path: "config.toml.backup-v1-20260829-203000-2")
        try Data("keep first".utf8).write(to: firstCollision)
        try Data("keep second".utf8).write(to: secondCollision)

        let backup = try ConfigMigrationBackup.create(
            forResolvedTarget: target,
            fromVersion: 1,
            now: fixedDate,
        )

        #expect(backup.url.lastPathComponent == "config.toml.backup-v1-20260829-203000-3")
        #expect(try Data(contentsOf: firstCollision) == Data("keep first".utf8))
        #expect(try Data(contentsOf: secondCollision) == Data("keep second".utf8))
    }

    @Test func testBackupForResolvedSymlinkTargetIsCreatedBesideTheTarget() throws {
        let targetDirectory = temporaryDirectory.appending(path: "dotfiles", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        let target = targetDirectory.appending(path: "aerospace.toml")
        try Data("source".utf8).write(to: target)
        let symlink = temporaryDirectory.appending(path: ".aerospace.toml")
        try fileManager.createSymbolicLink(at: symlink, withDestinationURL: target)

        let backup = try ConfigMigrationBackup.create(
            forResolvedTarget: symlink.resolvingSymlinksInPath(),
            fromVersion: 1,
            now: fixedDate,
        )

        #expect(backup.url.deletingLastPathComponent() == targetDirectory)
        #expect(try Data(contentsOf: backup.url) == Data("source".utf8))
        #expect(try fileManager.destinationOfSymbolicLink(atPath: symlink.path) == target.path)
    }

    @Test func testBackupPreservesSourcePermissions() throws {
        let target = temporaryDirectory.appending(path: "config.toml")
        try Data("source".utf8).write(to: target)
        try fileManager.setAttributes([.posixPermissions: 0o640], ofItemAtPath: target.path)

        let backup = try ConfigMigrationBackup.create(
            forResolvedTarget: target,
            fromVersion: 1,
            now: fixedDate,
        )

        #expect(try permissions(of: backup.url) == 0o640)
    }

    private var fixedDate: Date {
        Date(timeIntervalSince1970: 1_788_035_400) // 2026-08-29 20:30:00 UTC
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? NSNumber).intValue
    }
}

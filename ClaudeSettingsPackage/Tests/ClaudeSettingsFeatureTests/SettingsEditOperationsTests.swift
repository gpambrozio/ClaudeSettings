import Foundation
import Testing
@testable import ClaudeSettingsFeature

/// Tests for settings edit operations (update, delete, copy, move)
@MainActor
struct SettingsEditOperationsTests {
    // MARK: - Test Environment Setup

    /// Create a temporary directory for test files
    func createTestDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeSettingsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    /// Clean up test directory
    func cleanupTestDirectory(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    /// Create a test settings file
    func createTestSettingsFile(
        at url: URL,
        content: [String: SettingValue]
    ) async throws {
        let fileSystemManager = FileSystemManager()
        let parser = SettingsParser(fileSystemManager: fileSystemManager)

        let settingsFile = SettingsFile(
            type: .globalSettings,
            path: url,
            content: content,
            isValid: true,
            validationErrors: [],
            lastModified: Date(),
            isReadOnly: false
        )

        try await parser.writeSettingsFile(settingsFile)
    }

    // MARK: - Update Setting Tests

    @Test("Update simple string setting")
    func testUpdateStringSetting() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        // Create .claude directory
        let claudeDir = testDir.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        // Create settings file
        let settingsPath = claudeDir.appendingPathComponent("settings.json")
        let initialContent: [String: SettingValue] = [
            "editor.theme": .string("light"),
        ]
        try await createTestSettingsFile(at: settingsPath, content: initialContent)

        // Create project and view model
        let project = ClaudeProject(
            name: "Test Project",
            path: testDir,
            claudeDirectory: claudeDir,
            hasLocalSettings: false,
            hasSharedSettings: true,
            hasClaudeMd: false,
            hasLocalClaudeMd: false
        )

        let viewModel = SettingsViewModel(project: project)
        viewModel.loadSettings()

        // Wait for settings to load
        try await Task.sleep(for: .milliseconds(100))

        // Update setting
        try await viewModel.updateSetting(
            key: "editor.theme",
            value: .string("dark"),
            in: .projectSettings
        )

        // Wait for update to complete
        try await Task.sleep(for: .milliseconds(100))

        // Verify the setting was updated
        let updatedItem = viewModel.settingItems.first { $0.key == "editor.theme" }
        #expect(updatedItem != nil)
        if case let .string(value) = updatedItem?.value {
            #expect(value == "dark")
        } else {
            Issue.record("Setting value should be a string")
        }
    }

    @Test("Update nested setting")
    func testUpdateNestedSetting() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let claudeDir = testDir.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        let settingsPath = claudeDir.appendingPathComponent("settings.json")
        let initialContent: [String: SettingValue] = [
            "editor": .object([
                "fontSize": .int(12),
                "fontFamily": .string("Courier"),
            ]),
        ]
        try await createTestSettingsFile(at: settingsPath, content: initialContent)

        let project = ClaudeProject(
            name: "Test Project",
            path: testDir,
            claudeDirectory: claudeDir,
            hasLocalSettings: false,
            hasSharedSettings: true,
            hasClaudeMd: false,
            hasLocalClaudeMd: false
        )

        let viewModel = SettingsViewModel(project: project)
        viewModel.loadSettings()

        try await Task.sleep(for: .milliseconds(100))

        // Update nested setting
        try await viewModel.updateSetting(
            key: "editor.fontSize",
            value: .int(16),
            in: .projectSettings
        )

        try await Task.sleep(for: .milliseconds(100))

        // Verify
        let updatedItem = viewModel.settingItems.first { $0.key == "editor.fontSize" }
        #expect(updatedItem != nil)
        if case let .int(value) = updatedItem?.value {
            #expect(value == 16)
        } else {
            Issue.record("Setting value should be an int")
        }
    }

    @Test("Update creates backup")
    func testUpdateCreatesBackup() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let claudeDir = testDir.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        let settingsPath = claudeDir.appendingPathComponent("settings.json")
        let initialContent: [String: SettingValue] = [
            "test.setting": .string("original"),
        ]
        try await createTestSettingsFile(at: settingsPath, content: initialContent)

        let project = ClaudeProject(
            name: "Test Project",
            path: testDir,
            claudeDirectory: claudeDir,
            hasLocalSettings: false,
            hasSharedSettings: true,
            hasClaudeMd: false,
            hasLocalClaudeMd: false
        )

        let viewModel = SettingsViewModel(project: project)
        viewModel.loadSettings()

        try await Task.sleep(for: .milliseconds(100))

        // Update setting
        try await viewModel.updateSetting(
            key: "test.setting",
            value: .string("updated"),
            in: .projectSettings
        )

        try await Task.sleep(for: .milliseconds(100))

        // Check for backup directory
        let backupDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClaudeSettings/Backups")

        let backupExists = FileManager.default.fileExists(atPath: backupDir.path)
        #expect(backupExists, "Backup directory should be created")

        if backupExists {
            // Check that at least one backup file was created
            let backupFiles = try FileManager.default.contentsOfDirectory(
                at: backupDir,
                includingPropertiesForKeys: nil
            )
            #expect(!backupFiles.isEmpty, "At least one backup should exist")
        }
    }

    // MARK: - Delete Setting Tests

    @Test("Delete simple setting")
    func testDeleteSetting() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let claudeDir = testDir.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        let settingsPath = claudeDir.appendingPathComponent("settings.json")
        let initialContent: [String: SettingValue] = [
            "setting1": .string("value1"),
            "setting2": .string("value2"),
        ]
        try await createTestSettingsFile(at: settingsPath, content: initialContent)

        let project = ClaudeProject(
            name: "Test Project",
            path: testDir,
            claudeDirectory: claudeDir,
            hasLocalSettings: false,
            hasSharedSettings: true,
            hasClaudeMd: false,
            hasLocalClaudeMd: false
        )

        let viewModel = SettingsViewModel(project: project)
        viewModel.loadSettings()

        try await Task.sleep(for: .milliseconds(100))

        // Delete setting
        try await viewModel.deleteSetting(key: "setting1", from: .projectSettings)

        try await Task.sleep(for: .milliseconds(100))

        // Verify deletion
        let deletedItem = viewModel.settingItems.first { $0.key == "setting1" }
        #expect(deletedItem == nil, "Setting should be deleted")

        let remainingItem = viewModel.settingItems.first { $0.key == "setting2" }
        #expect(remainingItem != nil, "Other setting should remain")
    }

    @Test("Delete nested setting cleans up empty parent")
    func testDeleteNestedSettingCleansUpParent() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let claudeDir = testDir.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        let settingsPath = claudeDir.appendingPathComponent("settings.json")
        let initialContent: [String: SettingValue] = [
            "editor": .object([
                "fontSize": .int(12),
            ]),
        ]
        try await createTestSettingsFile(at: settingsPath, content: initialContent)

        let project = ClaudeProject(
            name: "Test Project",
            path: testDir,
            claudeDirectory: claudeDir,
            hasLocalSettings: false,
            hasSharedSettings: true,
            hasClaudeMd: false,
            hasLocalClaudeMd: false
        )

        let viewModel = SettingsViewModel(project: project)
        viewModel.loadSettings()

        try await Task.sleep(for: .milliseconds(100))

        // Delete the only nested setting
        try await viewModel.deleteSetting(key: "editor.fontSize", from: .projectSettings)

        try await Task.sleep(for: .milliseconds(100))

        // Verify both the nested setting and parent are gone
        let deletedItem = viewModel.settingItems.first { $0.key == "editor.fontSize" }
        #expect(deletedItem == nil, "Nested setting should be deleted")

        // Check the file to ensure empty parent was cleaned up
        let fileManager = FileSystemManager()
        let data = try await fileManager.readFile(at: settingsPath)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["editor"] == nil, "Empty parent object should be removed")
    }

    // MARK: - Copy Setting Tests

    @Test("Copy setting to existing file")
    func testCopySettingToExistingFile() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let claudeDir = testDir.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        // Create source file
        let globalSettingsPath = claudeDir.appendingPathComponent("settings.json")
        let globalContent: [String: SettingValue] = [
            "test.setting": .string("value from global"),
        ]
        try await createTestSettingsFile(at: globalSettingsPath, content: globalContent)

        // Create target file
        let localSettingsPath = claudeDir.appendingPathComponent("settings.local.json")
        let localContent: [String: SettingValue] = [
            "other.setting": .string("other value"),
        ]

        let fileSystemManager = FileSystemManager()
        let parser = SettingsParser(fileSystemManager: fileSystemManager)
        let localFile = SettingsFile(
            type: .projectLocal,
            path: localSettingsPath,
            content: localContent,
            isValid: true,
            validationErrors: [],
            lastModified: Date(),
            isReadOnly: false
        )
        try await parser.writeSettingsFile(localFile)

        let project = ClaudeProject(
            name: "Test Project",
            path: testDir,
            claudeDirectory: claudeDir,
            hasLocalSettings: true,
            hasSharedSettings: true,
            hasClaudeMd: false,
            hasLocalClaudeMd: false
        )

        let viewModel = SettingsViewModel(project: project)
        viewModel.loadSettings()

        try await Task.sleep(for: .milliseconds(100))

        // Copy setting
        try await viewModel.copySetting(
            key: "test.setting",
            from: .projectSettings,
            to: .projectLocal
        )

        try await Task.sleep(for: .milliseconds(100))

        // Verify the setting exists in both files
        let contributions = viewModel.settingItems
            .first { $0.key == "test.setting" }?
            .contributions

        #expect(contributions != nil)
        #expect(contributions?.count == 2, "Setting should exist in both files")

        let hasProjectSettings = contributions?.contains { $0.source == .projectSettings } ?? false
        let hasProjectLocal = contributions?.contains { $0.source == .projectLocal } ?? false

        #expect(hasProjectSettings, "Should exist in project settings")
        #expect(hasProjectLocal, "Should exist in project local")
    }

    @Test("Copy setting creates new file if target doesn't exist")
    func testCopySettingCreatesNewFile() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let claudeDir = testDir.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        // Create only source file
        let settingsPath = claudeDir.appendingPathComponent("settings.json")
        let content: [String: SettingValue] = [
            "test.setting": .string("test value"),
        ]
        try await createTestSettingsFile(at: settingsPath, content: content)

        let project = ClaudeProject(
            name: "Test Project",
            path: testDir,
            claudeDirectory: claudeDir,
            hasLocalSettings: false,
            hasSharedSettings: true,
            hasClaudeMd: false,
            hasLocalClaudeMd: false
        )

        let viewModel = SettingsViewModel(project: project)
        viewModel.loadSettings()

        try await Task.sleep(for: .milliseconds(100))

        // Copy to non-existent local file
        try await viewModel.copySetting(
            key: "test.setting",
            from: .projectSettings,
            to: .projectLocal
        )

        try await Task.sleep(for: .milliseconds(200))

        // Verify the local file was created
        let localPath = claudeDir.appendingPathComponent("settings.local.json")
        let localFileExists = FileManager.default.fileExists(atPath: localPath.path)
        #expect(localFileExists, "Local settings file should be created")
    }

    // MARK: - Move Setting Tests

    @Test("Move setting between files")
    func testMoveSetting() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let claudeDir = testDir.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        // Create source file
        let settingsPath = claudeDir.appendingPathComponent("settings.json")
        let content: [String: SettingValue] = [
            "test.setting": .string("test value"),
            "other.setting": .string("other value"),
        ]
        try await createTestSettingsFile(at: settingsPath, content: content)

        let project = ClaudeProject(
            name: "Test Project",
            path: testDir,
            claudeDirectory: claudeDir,
            hasLocalSettings: false,
            hasSharedSettings: true,
            hasClaudeMd: false,
            hasLocalClaudeMd: false
        )

        let viewModel = SettingsViewModel(project: project)
        viewModel.loadSettings()

        try await Task.sleep(for: .milliseconds(100))

        // Move setting to local file
        try await viewModel.moveSetting(
            key: "test.setting",
            from: .projectSettings,
            to: .projectLocal
        )

        try await Task.sleep(for: .milliseconds(200))

        // Verify the setting was moved
        let item = viewModel.settingItems.first { $0.key == "test.setting" }
        #expect(item != nil)

        // Should only exist in project local now
        #expect(item?.contributions.count == 1, "Should only exist in one file")
        #expect(item?.contributions.first?.source == .projectLocal, "Should be in project local")

        // Verify it's gone from source file
        let sourceHasSetting = item?.contributions.contains { $0.source == .projectSettings } ?? false
        #expect(!sourceHasSetting, "Should be removed from source file")
    }

    @Test("Move setting fails when source and target are same")
    func testMoveSettingToSameFileFails() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let claudeDir = testDir.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        let settingsPath = claudeDir.appendingPathComponent("settings.json")
        let content: [String: SettingValue] = [
            "test.setting": .string("test value"),
        ]
        try await createTestSettingsFile(at: settingsPath, content: content)

        let project = ClaudeProject(
            name: "Test Project",
            path: testDir,
            claudeDirectory: claudeDir,
            hasLocalSettings: false,
            hasSharedSettings: true,
            hasClaudeMd: false,
            hasLocalClaudeMd: false
        )

        let viewModel = SettingsViewModel(project: project)
        viewModel.loadSettings()

        try await Task.sleep(for: .milliseconds(100))

        // Try to move to same file - should throw error
        await #expect(throws: Error.self) {
            try await viewModel.moveSetting(
                key: "test.setting",
                from: .projectSettings,
                to: .projectSettings
            )
        }
    }

    // MARK: - Error Handling Tests

    @Test("Update read-only file fails")
    func testUpdateReadOnlyFileFails() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        // Note: This test assumes enterprise managed files are read-only
        // In a real scenario, we'd need to set up proper read-only files

        let viewModel = SettingsViewModel(project: nil)

        // Try to update a read-only enterprise managed setting
        // Should fail with fileIsReadOnly error
        await #expect(throws: Error.self) {
            try await viewModel.updateSetting(
                key: "test.setting",
                value: .string("new value"),
                in: .enterpriseManaged
            )
        }
    }

    @Test("Delete from non-existent file fails")
    func testDeleteFromNonExistentFileFails() async throws {
        let testDir = try createTestDirectory()
        defer { try? cleanupTestDirectory(testDir) }

        let claudeDir = testDir.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        let project = ClaudeProject(
            name: "Test Project",
            path: testDir,
            claudeDirectory: claudeDir,
            hasLocalSettings: false,
            hasSharedSettings: false,
            hasClaudeMd: false,
            hasLocalClaudeMd: false
        )

        let viewModel = SettingsViewModel(project: project)
        viewModel.loadSettings()

        try await Task.sleep(for: .milliseconds(100))

        // Try to delete from non-existent file
        await #expect(throws: Error.self) {
            try await viewModel.deleteSetting(
                key: "test.setting",
                from: .projectSettings
            )
        }
    }
}

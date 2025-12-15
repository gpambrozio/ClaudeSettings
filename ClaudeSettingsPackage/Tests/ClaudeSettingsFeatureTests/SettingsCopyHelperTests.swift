import Foundation
import Testing
@testable import ClaudeSettingsFeature

// MARK: - Test Helpers

/// Parse JSON data into a dictionary (helper to avoid Sendable issues)
private func parseJSON(_ data: Data?) -> [String: Any]? {
    guard let data else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

/// Tests for SettingsCopyHelper drag-and-drop copy functionality
@Suite("SettingsCopyHelper Tests")
@MainActor
struct SettingsCopyHelperTests {
    // MARK: - Test Environment

    struct TestEnvironment {
        let mockFileSystem: MockFileSystemManager
        let pathProvider: MockPathProvider
        let homeDirectory: URL

        init() {
            self.homeDirectory = URL(fileURLWithPath: "/mock/home")
            self.mockFileSystem = MockFileSystemManager()
            self.pathProvider = MockPathProvider(homeDirectory: homeDirectory)
        }

        var globalSettingsPath: URL {
            homeDirectory.appendingPathComponent(".claude/settings.json")
        }

        var globalLocalPath: URL {
            homeDirectory.appendingPathComponent(".claude/settings.local.json")
        }

        func projectPath(_ name: String) -> URL {
            URL(fileURLWithPath: "/mock/projects/\(name)")
        }

        func projectSettingsPath(for project: URL) -> URL {
            project.appendingPathComponent(".claude/settings.json")
        }

        func projectLocalPath(for project: URL) -> URL {
            project.appendingPathComponent(".claude/settings.local.json")
        }

        func createProject(name: String, hasSharedSettings: Bool = false, hasLocalSettings: Bool = false) -> ClaudeProject {
            let path = projectPath(name)
            return ClaudeProject(
                name: name,
                path: path,
                claudeDirectory: path.appendingPathComponent(".claude"),
                hasLocalSettings: hasLocalSettings,
                hasSharedSettings: hasSharedSettings
            )
        }
    }

    // MARK: - copySetting to Project Tests

    @Test("copySetting copies single setting to project settings")
    func copySettingToProjectSettings() async throws {
        // Given: A project with existing settings
        let env = TestEnvironment()
        let projectPath = env.projectPath("TestProject")
        let settingsPath = env.projectSettingsPath(for: projectPath)

        try await env.mockFileSystem.addJSONFile(
            at: settingsPath,
            content: ["existingSetting": "existingValue"]
        )

        let project = env.createProject(name: "TestProject", hasSharedSettings: true)
        let draggable = DraggableSetting(
            key: "newSetting",
            value: .string("newValue"),
            sourceFileType: .globalSettings
        )

        // When: Copying the setting to project settings
        try await SettingsCopyHelper.copySetting(
            setting: draggable,
            to: project,
            fileType: .projectSettings,
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider
        )

        // Then: Both settings should exist in the file
        let content = parseJSON(await env.mockFileSystem.getFileData(at: settingsPath))
        #expect(content?["existingSetting"] as? String == "existingValue", "Existing setting preserved")
        #expect(content?["newSetting"] as? String == "newValue", "New setting added")
    }

    @Test("copySetting copies single setting to project local")
    func copySettingToProjectLocal() async throws {
        // Given: A project with existing local settings
        let env = TestEnvironment()
        let projectPath = env.projectPath("TestProject")
        let localPath = env.projectLocalPath(for: projectPath)

        try await env.mockFileSystem.addJSONFile(
            at: localPath,
            content: ["localSetting": "localValue"]
        )

        let project = env.createProject(name: "TestProject", hasLocalSettings: true)
        let draggable = DraggableSetting(
            key: "copiedSetting",
            value: .int(42),
            sourceFileType: .globalSettings
        )

        // When: Copying the setting to project local
        try await SettingsCopyHelper.copySetting(
            setting: draggable,
            to: project,
            fileType: .projectLocal,
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider
        )

        // Then: Both settings should exist
        let content = parseJSON(await env.mockFileSystem.getFileData(at: localPath))
        #expect(content?["localSetting"] as? String == "localValue", "Existing setting preserved")
        #expect(content?["copiedSetting"] as? Int == 42, "New setting added")
    }

    @Test("copySetting copies multiple settings at once")
    func copyMultipleSettingsToProject() async throws {
        // Given: A project with existing settings
        let env = TestEnvironment()
        let projectPath = env.projectPath("TestProject")
        let settingsPath = env.projectSettingsPath(for: projectPath)

        try await env.mockFileSystem.addJSONFile(
            at: settingsPath,
            content: ["existing": "value"]
        )

        let project = env.createProject(name: "TestProject", hasSharedSettings: true)
        let draggable = DraggableSetting(settings: [
            DraggableSetting.SettingEntry(key: "setting1", value: .string("value1"), sourceFileType: .globalSettings),
            DraggableSetting.SettingEntry(key: "setting2", value: .bool(true), sourceFileType: .globalSettings),
            DraggableSetting.SettingEntry(key: "setting3", value: .int(123), sourceFileType: .globalLocal),
        ])

        // When: Copying multiple settings
        try await SettingsCopyHelper.copySetting(
            setting: draggable,
            to: project,
            fileType: .projectSettings,
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider
        )

        // Then: All settings should be present
        let content = parseJSON(await env.mockFileSystem.getFileData(at: settingsPath))
        #expect(content?["existing"] as? String == "value", "Existing setting preserved")
        #expect(content?["setting1"] as? String == "value1", "First setting added")
        #expect(content?["setting2"] as? Bool == true, "Second setting added")
        #expect(content?["setting3"] as? Int == 123, "Third setting added")
    }

    @Test("copySetting rejects global file types")
    func copySettingRejectsGlobalFileTypes() async throws {
        // Given: A project and a setting to copy
        let env = TestEnvironment()
        let project = env.createProject(name: "TestProject")
        let draggable = DraggableSetting(
            key: "setting",
            value: .string("value"),
            sourceFileType: .projectSettings
        )

        // When/Then: Attempting to copy to globalSettings should throw
        await #expect(throws: SettingsError.self) {
            try await SettingsCopyHelper.copySetting(
                setting: draggable,
                to: project,
                fileType: .globalSettings,
                fileSystemManager: env.mockFileSystem,
                pathProvider: env.pathProvider
            )
        }

        // When/Then: Attempting to copy to globalLocal should throw
        await #expect(throws: SettingsError.self) {
            try await SettingsCopyHelper.copySetting(
                setting: draggable,
                to: project,
                fileType: .globalLocal,
                fileSystemManager: env.mockFileSystem,
                pathProvider: env.pathProvider
            )
        }
    }

    // MARK: - copySettingToGlobal Tests

    @Test("copySettingToGlobal copies setting to global settings")
    func copySettingToGlobalSettings() async throws {
        // Given: Existing global settings
        let env = TestEnvironment()

        try await env.mockFileSystem.addJSONFile(
            at: env.globalSettingsPath,
            content: ["existingGlobal": "value"]
        )

        let draggable = DraggableSetting(
            key: "newGlobalSetting",
            value: .string("globalValue"),
            sourceFileType: .projectSettings
        )

        // When: Copying to global settings
        try await SettingsCopyHelper.copySettingToGlobal(
            setting: draggable,
            fileType: .globalSettings,
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider
        )

        // Then: Both settings should exist
        let content = parseJSON(await env.mockFileSystem.getFileData(at: env.globalSettingsPath))
        #expect(content?["existingGlobal"] as? String == "value", "Existing setting preserved")
        #expect(content?["newGlobalSetting"] as? String == "globalValue", "New setting added")
    }

    @Test("copySettingToGlobal copies setting to global local")
    func copySettingToGlobalLocal() async throws {
        // Given: Existing global local settings
        let env = TestEnvironment()

        try await env.mockFileSystem.addJSONFile(
            at: env.globalLocalPath,
            content: ["existingLocal": 99]
        )

        let draggable = DraggableSetting(
            key: "newLocalSetting",
            value: .bool(false),
            sourceFileType: .projectLocal
        )

        // When: Copying to global local
        try await SettingsCopyHelper.copySettingToGlobal(
            setting: draggable,
            fileType: .globalLocal,
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider
        )

        // Then: Both settings should exist
        let content = parseJSON(await env.mockFileSystem.getFileData(at: env.globalLocalPath))
        #expect(content?["existingLocal"] as? Int == 99, "Existing setting preserved")
        #expect(content?["newLocalSetting"] as? Bool == false, "New setting added")
    }

    @Test("copySettingToGlobal copies multiple settings")
    func copyMultipleSettingsToGlobal() async throws {
        // Given: Empty global settings
        let env = TestEnvironment()

        try await env.mockFileSystem.addJSONFile(
            at: env.globalSettingsPath,
            content: [:]
        )

        let draggable = DraggableSetting(settings: [
            DraggableSetting.SettingEntry(key: "batch1", value: .string("a"), sourceFileType: .projectSettings),
            DraggableSetting.SettingEntry(key: "batch2", value: .string("b"), sourceFileType: .projectSettings),
        ])

        // When: Copying multiple settings to global
        try await SettingsCopyHelper.copySettingToGlobal(
            setting: draggable,
            fileType: .globalSettings,
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider
        )

        // Then: All settings should be present
        let content = parseJSON(await env.mockFileSystem.getFileData(at: env.globalSettingsPath))
        #expect(content?["batch1"] as? String == "a", "First batch setting added")
        #expect(content?["batch2"] as? String == "b", "Second batch setting added")
    }

    @Test("copySettingToGlobal rejects project file types")
    func copySettingToGlobalRejectsProjectFileTypes() async throws {
        // Given: A setting to copy
        let env = TestEnvironment()
        let draggable = DraggableSetting(
            key: "setting",
            value: .string("value"),
            sourceFileType: .globalSettings
        )

        // When/Then: Attempting to copy to projectSettings should throw
        await #expect(throws: SettingsError.self) {
            try await SettingsCopyHelper.copySettingToGlobal(
                setting: draggable,
                fileType: .projectSettings,
                fileSystemManager: env.mockFileSystem,
                pathProvider: env.pathProvider
            )
        }

        // When/Then: Attempting to copy to projectLocal should throw
        await #expect(throws: SettingsError.self) {
            try await SettingsCopyHelper.copySettingToGlobal(
                setting: draggable,
                fileType: .projectLocal,
                fileSystemManager: env.mockFileSystem,
                pathProvider: env.pathProvider
            )
        }
    }

    // MARK: - File Creation Tests

    @Test("copySetting creates settings file if it doesn't exist")
    func copySettingCreatesFileIfMissing() async throws {
        // Given: A project without a settings file
        let env = TestEnvironment()
        let projectPath = env.projectPath("NewProject")
        let settingsPath = env.projectSettingsPath(for: projectPath)

        // Create only the .claude directory, not the settings file
        await env.mockFileSystem.addDirectory(at: projectPath.appendingPathComponent(".claude"))

        let project = env.createProject(name: "NewProject", hasSharedSettings: false)
        let draggable = DraggableSetting(
            key: "firstSetting",
            value: .string("firstValue"),
            sourceFileType: .globalSettings
        )

        // When: Copying a setting
        try await SettingsCopyHelper.copySetting(
            setting: draggable,
            to: project,
            fileType: .projectSettings,
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider
        )

        // Then: File should be created with the setting
        let exists = await env.mockFileSystem.exists(at: settingsPath)
        #expect(exists, "Settings file should be created")

        let content = parseJSON(await env.mockFileSystem.getFileData(at: settingsPath))
        #expect(content?["firstSetting"] as? String == "firstValue", "Setting should be in new file")
    }

    @Test("copySetting creates .claude directory if it doesn't exist")
    func copySettingCreatesClaudeDirectoryIfMissing() async throws {
        // Given: A project without a .claude directory
        let env = TestEnvironment()
        let projectPath = env.projectPath("BrandNewProject")
        let claudeDir = projectPath.appendingPathComponent(".claude")
        let settingsPath = env.projectSettingsPath(for: projectPath)

        // Only create the project directory, not .claude
        await env.mockFileSystem.addDirectory(at: projectPath)

        let project = env.createProject(name: "BrandNewProject")
        let draggable = DraggableSetting(
            key: "setting",
            value: .string("value"),
            sourceFileType: .globalSettings
        )

        // When: Copying a setting
        try await SettingsCopyHelper.copySetting(
            setting: draggable,
            to: project,
            fileType: .projectSettings,
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider
        )

        // Then: .claude directory and settings file should be created
        let dirExists = await env.mockFileSystem.exists(at: claudeDir)
        let fileExists = await env.mockFileSystem.exists(at: settingsPath)

        #expect(dirExists, ".claude directory should be created")
        #expect(fileExists, "Settings file should be created")
    }

    @Test("copySettingToGlobal creates file if it doesn't exist")
    func copySettingToGlobalCreatesFileIfMissing() async throws {
        // Given: No global settings file exists
        let env = TestEnvironment()

        // Create only the .claude directory
        await env.mockFileSystem.addDirectory(at: env.homeDirectory.appendingPathComponent(".claude"))

        let draggable = DraggableSetting(
            key: "newGlobalSetting",
            value: .int(100),
            sourceFileType: .projectSettings
        )

        // When: Copying to global settings
        try await SettingsCopyHelper.copySettingToGlobal(
            setting: draggable,
            fileType: .globalSettings,
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider
        )

        // Then: File should be created
        let exists = await env.mockFileSystem.exists(at: env.globalSettingsPath)
        #expect(exists, "Global settings file should be created")

        let content = parseJSON(await env.mockFileSystem.getFileData(at: env.globalSettingsPath))
        #expect(content?["newGlobalSetting"] as? Int == 100, "Setting should be in new file")
    }

    // MARK: - Nested Settings Tests

    @Test("copySetting handles nested settings correctly")
    func copySettingHandlesNestedSettings() async throws {
        // Given: A project with existing nested settings
        let env = TestEnvironment()
        let projectPath = env.projectPath("TestProject")
        let settingsPath = env.projectSettingsPath(for: projectPath)

        try await env.mockFileSystem.addJSONFile(
            at: settingsPath,
            content: [
                "editor": [
                    "theme": "dark",
                    "fontSize": 14,
                ],
            ]
        )

        let project = env.createProject(name: "TestProject", hasSharedSettings: true)
        let draggable = DraggableSetting(
            key: "editor.tabSize",
            value: .int(4),
            sourceFileType: .globalSettings
        )

        // When: Copying a nested setting
        try await SettingsCopyHelper.copySetting(
            setting: draggable,
            to: project,
            fileType: .projectSettings,
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider
        )

        // Then: The nested setting should be merged correctly
        let content = parseJSON(await env.mockFileSystem.getFileData(at: settingsPath))
        let editor = content?["editor"] as? [String: Any]

        #expect(editor?["theme"] as? String == "dark", "Existing nested setting preserved")
        #expect(editor?["fontSize"] as? Int == 14, "Existing nested setting preserved")
        #expect(editor?["tabSize"] as? Int == 4, "New nested setting added")
    }

    @Test("copySetting handles deeply nested settings")
    func copySettingHandlesDeeplyNestedSettings() async throws {
        // Given: A project with no existing settings
        let env = TestEnvironment()
        let projectPath = env.projectPath("TestProject")
        let settingsPath = env.projectSettingsPath(for: projectPath)

        await env.mockFileSystem.addDirectory(at: projectPath.appendingPathComponent(".claude"))

        let project = env.createProject(name: "TestProject")
        let draggable = DraggableSetting(
            key: "hooks.PreToolUse.command",
            value: .string("echo 'hello'"),
            sourceFileType: .globalSettings
        )

        // When: Copying a deeply nested setting
        try await SettingsCopyHelper.copySetting(
            setting: draggable,
            to: project,
            fileType: .projectSettings,
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider
        )

        // Then: The nested structure should be created
        let content = parseJSON(await env.mockFileSystem.getFileData(at: settingsPath))
        let hooks = content?["hooks"] as? [String: Any]
        let preToolUse = hooks?["PreToolUse"] as? [String: Any]

        #expect(preToolUse?["command"] as? String == "echo 'hello'", "Deeply nested setting should be created")
    }

    // MARK: - Override Behavior Tests

    @Test("copySetting overrides existing setting with same key")
    func copySettingOverridesExistingSetting() async throws {
        // Given: A project with an existing setting
        let env = TestEnvironment()
        let projectPath = env.projectPath("TestProject")
        let settingsPath = env.projectSettingsPath(for: projectPath)

        try await env.mockFileSystem.addJSONFile(
            at: settingsPath,
            content: ["theme": "light"]
        )

        let project = env.createProject(name: "TestProject", hasSharedSettings: true)
        let draggable = DraggableSetting(
            key: "theme",
            value: .string("dark"),
            sourceFileType: .globalSettings
        )

        // When: Copying a setting with the same key
        try await SettingsCopyHelper.copySetting(
            setting: draggable,
            to: project,
            fileType: .projectSettings,
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider
        )

        // Then: The setting should be overridden
        let content = parseJSON(await env.mockFileSystem.getFileData(at: settingsPath))
        #expect(content?["theme"] as? String == "dark", "Setting should be overridden")
    }

    // MARK: - Complex Value Types Tests

    @Test("copySetting handles array values")
    func copySettingHandlesArrayValues() async throws {
        // Given: A project
        let env = TestEnvironment()
        let projectPath = env.projectPath("TestProject")
        let settingsPath = env.projectSettingsPath(for: projectPath)

        await env.mockFileSystem.addDirectory(at: projectPath.appendingPathComponent(".claude"))

        let project = env.createProject(name: "TestProject")
        let draggable = DraggableSetting(
            key: "allowedTools",
            value: .array([.string("Read"), .string("Write"), .string("Bash")]),
            sourceFileType: .globalSettings
        )

        // When: Copying an array setting
        try await SettingsCopyHelper.copySetting(
            setting: draggable,
            to: project,
            fileType: .projectSettings,
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider
        )

        // Then: The array should be preserved
        let content = parseJSON(await env.mockFileSystem.getFileData(at: settingsPath))
        let tools = content?["allowedTools"] as? [String]

        #expect(tools?.count == 3, "Array should have 3 elements")
        #expect(tools?.contains("Read") == true, "Array should contain Read")
        #expect(tools?.contains("Write") == true, "Array should contain Write")
        #expect(tools?.contains("Bash") == true, "Array should contain Bash")
    }

    @Test("copySetting handles object values")
    func copySettingHandlesObjectValues() async throws {
        // Given: A project
        let env = TestEnvironment()
        let projectPath = env.projectPath("TestProject")
        let settingsPath = env.projectSettingsPath(for: projectPath)

        await env.mockFileSystem.addDirectory(at: projectPath.appendingPathComponent(".claude"))

        let project = env.createProject(name: "TestProject")
        let draggable = DraggableSetting(
            key: "mcpServers",
            value: .object([
                "server1": .object([
                    "command": .string("npx"),
                    "args": .array([.string("-y"), .string("@server/mcp")]),
                ]),
            ]),
            sourceFileType: .globalSettings
        )

        // When: Copying an object setting
        try await SettingsCopyHelper.copySetting(
            setting: draggable,
            to: project,
            fileType: .projectSettings,
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider
        )

        // Then: The object structure should be preserved
        let content = parseJSON(await env.mockFileSystem.getFileData(at: settingsPath))
        let servers = content?["mcpServers"] as? [String: Any]
        let server1 = servers?["server1"] as? [String: Any]

        #expect(server1?["command"] as? String == "npx", "Object command preserved")
        #expect((server1?["args"] as? [String])?.count == 2, "Object args preserved")
    }

    // MARK: - Error Handling Tests

    @Test("copySetting propagates file system write errors")
    func copySettingPropagatesWriteErrors() async throws {
        // Given: A project and an error set to occur on write
        let env = TestEnvironment()
        let projectPath = env.projectPath("TestProject")
        let settingsPath = env.projectSettingsPath(for: projectPath)

        await env.mockFileSystem.addDirectory(at: projectPath.appendingPathComponent(".claude"))

        let project = env.createProject(name: "TestProject")
        let draggable = DraggableSetting(
            key: "setting",
            value: .string("value"),
            sourceFileType: .globalSettings
        )

        // Inject a write error
        await env.mockFileSystem.setErrorOnWrite(
            FileSystemError.writeFailed(
                url: settingsPath,
                underlyingError: NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Disk full"])
            )
        )

        // When/Then: Should propagate the error
        await #expect(throws: Error.self) {
            try await SettingsCopyHelper.copySetting(
                setting: draggable,
                to: project,
                fileType: .projectSettings,
                fileSystemManager: env.mockFileSystem,
                pathProvider: env.pathProvider
            )
        }
    }

    @Test("copySettingToGlobal propagates file system write errors")
    func copySettingToGlobalPropagatesWriteErrors() async throws {
        // Given: An error set to occur on write
        let env = TestEnvironment()

        await env.mockFileSystem.addDirectory(at: env.homeDirectory.appendingPathComponent(".claude"))

        let draggable = DraggableSetting(
            key: "setting",
            value: .string("value"),
            sourceFileType: .projectSettings
        )

        // Inject a write error
        await env.mockFileSystem.setErrorOnWrite(
            FileSystemError.writeFailed(
                url: env.globalSettingsPath,
                underlyingError: NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
            )
        )

        // When/Then: Should propagate the error
        await #expect(throws: Error.self) {
            try await SettingsCopyHelper.copySettingToGlobal(
                setting: draggable,
                fileType: .globalSettings,
                fileSystemManager: env.mockFileSystem,
                pathProvider: env.pathProvider
            )
        }
    }

    // MARK: - Backup Verification Tests

    @Test("copySetting creates backup before modifying existing file")
    func copySettingCreatesBackup() async throws {
        // Given: A project with existing settings
        let env = TestEnvironment()
        let projectPath = env.projectPath("TestProject")
        let settingsPath = env.projectSettingsPath(for: projectPath)

        try await env.mockFileSystem.addJSONFile(
            at: settingsPath,
            content: ["existingSetting": "value"]
        )

        let project = env.createProject(name: "TestProject", hasSharedSettings: true)
        let draggable = DraggableSetting(
            key: "newSetting",
            value: .string("newValue"),
            sourceFileType: .globalSettings
        )

        // When: Copying a setting
        try await SettingsCopyHelper.copySetting(
            setting: draggable,
            to: project,
            fileType: .projectSettings,
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider
        )

        // Then: A backup should have been created
        let backupCalls = await env.mockFileSystem.backupCalls
        #expect(backupCalls.count >= 1, "At least one backup should be created")

        // Find the backup call for our settings file
        let settingsBackup = backupCalls.first { $0.url == settingsPath }
        #expect(settingsBackup != nil, "Backup should be for the settings file")
    }
}

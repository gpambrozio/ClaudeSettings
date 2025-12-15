import Foundation
import Testing
@testable import ClaudeSettingsFeature

// MARK: - Test Helpers

/// Parse JSON data into a dictionary (avoids Sendable issues with actor boundaries)
private func parseJSON(_ data: Data?) -> [String: Any]? {
    guard let data else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

/// Tests demonstrating how to use MockFileSystemManager for comprehensive testing
/// without touching real files
@Suite("Mock File System Integration Tests")
struct MockFileSystemTests {
    // MARK: - Test Fixtures

    /// Create a test environment with mock file system and path provider
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

        func projectSettingsPath(for project: URL) -> URL {
            project.appendingPathComponent(".claude/settings.json")
        }

        func projectLocalPath(for project: URL) -> URL {
            project.appendingPathComponent(".claude/settings.local.json")
        }
    }

    // MARK: - MockFileSystemManager Tests

    @Test("MockFileSystemManager can read and write files")
    func mockFileSystemBasicOperations() async throws {
        let mockFS = MockFileSystemManager()
        let testURL = URL(fileURLWithPath: "/test/file.json")

        // Initially, file doesn't exist
        let existsBefore = await mockFS.exists(at: testURL)
        #expect(existsBefore == false)

        // Write a file
        let content = #"{"key": "value"}"#.data(using: .utf8)!
        try await mockFS.writeFile(data: content, to: testURL)

        // File should now exist
        let existsAfter = await mockFS.exists(at: testURL)
        #expect(existsAfter == true)

        // Read the file
        let readData = try await mockFS.readFile(at: testURL)
        #expect(readData == content)
    }

    @Test("MockFileSystemManager tracks operations for verification")
    func mockFileSystemTracksOperations() async throws {
        let mockFS = MockFileSystemManager()
        let url = URL(fileURLWithPath: "/test/file.txt")

        // Add a file
        await mockFS.addFile(at: url, content: "test content")

        // Read it
        _ = try await mockFS.readFile(at: url)

        // Verify tracking
        let readCalls = await mockFS.readFileCalls
        #expect(readCalls.count == 1)
        #expect(readCalls[0] == url)
    }

    @Test("MockFileSystemManager supports read-only files")
    func mockFileSystemReadOnlyFiles() async throws {
        let mockFS = MockFileSystemManager()
        let url = URL(fileURLWithPath: "/test/readonly.json")

        await mockFS.addFile(at: url, content: "content")
        await mockFS.setReadOnly(at: url)

        // Should be able to read
        _ = try await mockFS.readFile(at: url)

        // Should not be able to write
        await #expect(throws: FileSystemError.self) {
            try await mockFS.writeFile(data: "new content".data(using: .utf8)!, to: url)
        }
    }

    @Test("MockFileSystemManager can inject errors")
    func mockFileSystemErrorInjection() async throws {
        let mockFS = MockFileSystemManager()
        let url = URL(fileURLWithPath: "/test/file.json")

        await mockFS.addFile(at: url, content: "content")

        // Inject an error
        let testError = FileSystemError.readFailed(url: url, underlyingError: NSError(domain: "Test", code: 42))
        await mockFS.setErrorOnRead(testError)

        // Read should now throw
        await #expect(throws: Error.self) {
            try await mockFS.readFile(at: url)
        }
    }

    // MARK: - SettingsParser with Mock File System Tests

    @Test("SettingsParser works with MockFileSystemManager")
    func settingsParserWithMockFileSystem() async throws {
        let mockFS = MockFileSystemManager()
        let parser = SettingsParser(fileSystemManager: mockFS)

        // Set up a mock settings file
        let settingsPath = URL(fileURLWithPath: "/mock/.claude/settings.json")
        let settingsContent: [String: Any] = [
            "theme": "dark",
            "fontSize": 14,
            "hooks": [
                "onToolCall": "echo 'called'",
            ],
        ]
        try await mockFS.addJSONFile(at: settingsPath, content: settingsContent)

        // Parse the settings
        let settings = try await parser.parseSettingsFile(at: settingsPath, type: .globalSettings)

        // Verify parsing
        #expect(settings.isValid)
        #expect(settings.content["theme"] == .string("dark"))
        #expect(settings.content["fontSize"] == .int(14))

        if case let .object(hooks) = settings.content["hooks"] {
            #expect(hooks["onToolCall"] == .string("echo 'called'"))
        } else {
            Issue.record("hooks should be an object")
        }
    }

    @Test("SettingsParser can write settings to MockFileSystemManager")
    func settingsParserWriteWithMockFileSystem() async throws {
        let mockFS = MockFileSystemManager()
        let parser = SettingsParser(fileSystemManager: mockFS)

        // Create a settings file to write
        let settingsPath = URL(fileURLWithPath: "/mock/.claude/settings.json")
        var settings = SettingsFile(
            type: .globalSettings,
            path: settingsPath,
            content: [
                "newSetting": .string("value"),
                "number": .int(42),
            ],
            isValid: true,
            validationErrors: [],
            lastModified: Date(),
            isReadOnly: false
        )

        // Write the settings
        try await parser.writeSettingsFile(&settings)

        // Verify the file was written
        let exists = await mockFS.exists(at: settingsPath)
        #expect(exists)

        // Verify content
        let jsonContent = parseJSON(await mockFS.getFileData(at: settingsPath))
        #expect(jsonContent?["newSetting"] as? String == "value")
        #expect(jsonContent?["number"] as? Int == 42)
    }

    // MARK: - SettingsViewModel Integration Tests

    @Test("SettingsViewModel loads settings from MockFileSystemManager")
    @MainActor
    func settingsViewModelLoadWithMockFileSystem() async throws {
        let env = TestEnvironment()

        // Set up mock settings files
        try await env.mockFileSystem.addJSONFile(
            at: env.globalSettingsPath,
            content: [
                "globalSetting": "value1",
                "sharedSetting": "fromGlobal",
            ]
        )

        try await env.mockFileSystem.addJSONFile(
            at: env.globalLocalPath,
            content: [
                "localSetting": "value2",
                "sharedSetting": "fromLocal", // Overrides global
            ]
        )

        // Create SettingsParser with mock file system
        let parser = SettingsParser(fileSystemManager: env.mockFileSystem)

        // Create SettingsViewModel with mocks (no file monitoring for tests)
        let viewModel = SettingsViewModel(
            project: nil,
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider,
            settingsParser: parser,
            fileMonitor: SettingsFileMonitor(fileWatcher: nil)
        )

        // Load settings
        await viewModel.loadSettings()

        // Verify settings were loaded
        #expect(viewModel.settingsFiles.count == 2)
        #expect(viewModel.settingItems.count == 3) // globalSetting, localSetting, sharedSetting

        // Verify precedence: localSetting overrides globalSetting
        let sharedItem = viewModel.settingItems.first { $0.key == "sharedSetting" }
        #expect(sharedItem?.value == .string("fromLocal"))
        #expect(sharedItem?.contributions.count == 2)
    }

    @Test("SettingsViewModel saves edits to MockFileSystemManager")
    @MainActor
    func settingsViewModelSaveWithMockFileSystem() async throws {
        let env = TestEnvironment()

        // Set up initial settings
        try await env.mockFileSystem.addJSONFile(
            at: env.globalSettingsPath,
            content: ["theme": "dark"]
        )

        let parser = SettingsParser(fileSystemManager: env.mockFileSystem)
        let viewModel = SettingsViewModel(
            project: nil,
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider,
            settingsParser: parser,
            fileMonitor: SettingsFileMonitor(fileWatcher: nil)
        )

        // Load settings
        await viewModel.loadSettings()

        // Start editing and make changes
        viewModel.startEditing()
        viewModel.pendingEdits["theme"] = PendingEdit(
            key: "theme",
            value: .string("light"),
            targetFileType: .globalSettings,
            originalFileType: .globalSettings
        )

        // Save edits
        try await viewModel.saveAllEdits()

        // Verify file was updated
        let jsonContent = parseJSON(await env.mockFileSystem.getFileData(at: env.globalSettingsPath))
        #expect(jsonContent?["theme"] as? String == "light")
    }

    @Test("SettingsViewModel moves settings between files")
    @MainActor
    func settingsViewModelMoveSettingWithMockFileSystem() async throws {
        let env = TestEnvironment()

        // Set up settings in global file
        try await env.mockFileSystem.addJSONFile(
            at: env.globalSettingsPath,
            content: [
                "settingToMove": "value",
                "settingToKeep": "stays",
            ]
        )

        // Create empty local file
        try await env.mockFileSystem.addJSONFile(
            at: env.globalLocalPath,
            content: [:]
        )

        let parser = SettingsParser(fileSystemManager: env.mockFileSystem)
        let viewModel = SettingsViewModel(
            project: nil,
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider,
            settingsParser: parser,
            fileMonitor: SettingsFileMonitor(fileWatcher: nil)
        )

        // Load settings
        await viewModel.loadSettings()

        // Move setting from global to local
        viewModel.startEditing()
        viewModel.pendingEdits["settingToMove"] = PendingEdit(
            key: "settingToMove",
            value: .string("value"),
            targetFileType: .globalLocal,
            originalFileType: .globalSettings
        )

        // Save edits
        try await viewModel.saveAllEdits()

        // Verify setting was moved
        let globalContent = parseJSON(await env.mockFileSystem.getFileData(at: env.globalSettingsPath))
        let localContent = parseJSON(await env.mockFileSystem.getFileData(at: env.globalLocalPath))

        #expect(globalContent?["settingToMove"] == nil, "Setting should be removed from global")
        #expect(globalContent?["settingToKeep"] as? String == "stays", "Other settings should remain")
        #expect(localContent?["settingToMove"] as? String == "value", "Setting should be in local")
    }

    @Test("SettingsViewModel handles project settings")
    @MainActor
    func settingsViewModelProjectSettingsWithMockFileSystem() async throws {
        let env = TestEnvironment()
        let projectPath = URL(fileURLWithPath: "/mock/projects/MyProject")

        // Set up global and project settings
        try await env.mockFileSystem.addJSONFile(
            at: env.globalSettingsPath,
            content: ["globalSetting": "global"]
        )

        try await env.mockFileSystem.addJSONFile(
            at: env.projectSettingsPath(for: projectPath),
            content: [
                "projectSetting": "project",
                "globalSetting": "overridden", // Overrides global
            ]
        )

        // Create a project
        let project = ClaudeProject(
            name: "MyProject",
            path: projectPath,
            claudeDirectory: projectPath.appendingPathComponent(".claude"),
            hasSharedSettings: true
        )

        let parser = SettingsParser(fileSystemManager: env.mockFileSystem)
        let viewModel = SettingsViewModel(
            project: project,
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider,
            settingsParser: parser,
            fileMonitor: SettingsFileMonitor(fileWatcher: nil)
        )

        // Load settings
        await viewModel.loadSettings()

        // Verify both global and project settings were loaded
        #expect(viewModel.settingsFiles.count == 2)

        // Verify project setting overrides global
        let globalSettingItem = viewModel.settingItems.first { $0.key == "globalSetting" }
        #expect(globalSettingItem?.value == .string("overridden"))
        #expect(globalSettingItem?.overriddenBy == .projectSettings)
    }

    // MARK: - ProjectScanner Tests

    @Test("ProjectScanner discovers projects from MockFileSystemManager")
    func projectScannerWithMockFileSystem() async throws {
        let env = TestEnvironment()

        // Set up claude config file
        let claudeConfig: [String: Any] = [
            "projects": [
                "/mock/projects/Project1": [:],
                "/mock/projects/Project2": [:],
                env.homeDirectory.path: [:], // Should be skipped (home directory)
            ],
        ]
        try await env.mockFileSystem.addJSONFile(at: env.pathProvider.claudeConfigPath, content: claudeConfig)

        // Set up project directories
        let project1Path = URL(fileURLWithPath: "/mock/projects/Project1")
        let project2Path = URL(fileURLWithPath: "/mock/projects/Project2")

        await env.mockFileSystem.addDirectory(at: project1Path)
        await env.mockFileSystem.addDirectory(at: project1Path.appendingPathComponent(".claude"))
        try await env.mockFileSystem.addJSONFile(
            at: project1Path.appendingPathComponent(".claude/settings.json"),
            content: ["setting": "value"]
        )

        await env.mockFileSystem.addDirectory(at: project2Path)
        await env.mockFileSystem.addDirectory(at: project2Path.appendingPathComponent(".claude"))
        try await env.mockFileSystem.addJSONFile(
            at: project2Path.appendingPathComponent(".claude/settings.local.json"),
            content: ["localSetting": "value"]
        )

        // Scan for projects
        let scanner = ProjectScanner(
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider
        )

        let projects = try await scanner.scanProjects()

        // Should find 2 projects (home directory excluded)
        #expect(projects.count == 2)

        // Verify project details
        let project1 = projects.first { $0.path == project1Path }
        #expect(project1?.hasSharedSettings == true)
        #expect(project1?.hasLocalSettings == false)

        let project2 = projects.first { $0.path == project2Path }
        #expect(project2?.hasSharedSettings == false)
        #expect(project2?.hasLocalSettings == true)
    }

    // MARK: - Error Handling Tests

    @Test("SettingsViewModel handles missing files gracefully")
    @MainActor
    func settingsViewModelHandlesMissingFiles() async throws {
        let env = TestEnvironment()

        // Don't create any settings files - they should all be missing

        let parser = SettingsParser(fileSystemManager: env.mockFileSystem)
        let viewModel = SettingsViewModel(
            project: nil,
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider,
            settingsParser: parser,
            fileMonitor: SettingsFileMonitor(fileWatcher: nil)
        )

        // Load settings - should not crash
        await viewModel.loadSettings()

        // Should have no settings files
        #expect(viewModel.settingsFiles.isEmpty)
        #expect(viewModel.settingItems.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("SettingsViewModel handles read-only files")
    @MainActor
    func settingsViewModelHandlesReadOnlyFiles() async throws {
        let env = TestEnvironment()

        // Create a read-only settings file
        try await env.mockFileSystem.addJSONFile(
            at: env.globalSettingsPath,
            content: ["theme": "dark"]
        )
        await env.mockFileSystem.setReadOnly(at: env.globalSettingsPath)

        let parser = SettingsParser(fileSystemManager: env.mockFileSystem)
        let viewModel = SettingsViewModel(
            project: nil,
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider,
            settingsParser: parser,
            fileMonitor: SettingsFileMonitor(fileWatcher: nil)
        )

        // Load settings
        await viewModel.loadSettings()

        // Verify file is marked as read-only
        let settingsFile = viewModel.settingsFiles.first { $0.type == .globalSettings }
        #expect(settingsFile?.isReadOnly == true)
    }

    @Test("SettingsViewModel validates backup creation")
    @MainActor
    func settingsViewModelCreatesBackups() async throws {
        let env = TestEnvironment()

        // Set up settings file
        try await env.mockFileSystem.addJSONFile(
            at: env.globalSettingsPath,
            content: ["theme": "dark"]
        )

        let parser = SettingsParser(fileSystemManager: env.mockFileSystem)
        let viewModel = SettingsViewModel(
            project: nil,
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider,
            settingsParser: parser,
            fileMonitor: SettingsFileMonitor(fileWatcher: nil)
        )

        // Load and edit settings
        await viewModel.loadSettings()
        viewModel.startEditing()
        viewModel.pendingEdits["theme"] = PendingEdit(
            key: "theme",
            value: .string("light"),
            targetFileType: .globalSettings,
            originalFileType: .globalSettings
        )

        // Save edits
        try await viewModel.saveAllEdits()

        // Verify backup was created
        let backupCalls = await env.mockFileSystem.backupCalls
        #expect(backupCalls.count == 1)
        #expect(backupCalls[0].url == env.globalSettingsPath)
        #expect(backupCalls[0].backupDirectory == env.pathProvider.backupDirectory)
    }

    // MARK: - Complex Scenario Tests

    @Test("Full workflow: load, edit, move, save, verify")
    @MainActor
    func fullWorkflowTest() async throws {
        let env = TestEnvironment()

        // Set up initial state with settings in multiple files
        try await env.mockFileSystem.addJSONFile(
            at: env.globalSettingsPath,
            content: [
                "globalSetting": "originalValue",
                "settingToEdit": "editMe",
                "settingToMove": "moveMe",
            ]
        )

        try await env.mockFileSystem.addJSONFile(
            at: env.globalLocalPath,
            content: [
                "localSetting": "localValue",
            ]
        )

        let parser = SettingsParser(fileSystemManager: env.mockFileSystem)
        let viewModel = SettingsViewModel(
            project: nil,
            fileSystemManager: env.mockFileSystem,
            pathProvider: env.pathProvider,
            settingsParser: parser,
            fileMonitor: SettingsFileMonitor(fileWatcher: nil)
        )

        // Load settings
        await viewModel.loadSettings()
        #expect(viewModel.settingItems.count == 4)

        // Start editing
        viewModel.startEditing()

        // Edit a setting in place
        viewModel.pendingEdits["settingToEdit"] = PendingEdit(
            key: "settingToEdit",
            value: .string("edited"),
            targetFileType: .globalSettings,
            originalFileType: .globalSettings
        )

        // Move a setting from global to local
        viewModel.pendingEdits["settingToMove"] = PendingEdit(
            key: "settingToMove",
            value: .string("moveMe"),
            targetFileType: .globalLocal,
            originalFileType: .globalSettings
        )

        // Save all edits
        try await viewModel.saveAllEdits()

        // Verify final state
        let globalContent = parseJSON(await env.mockFileSystem.getFileData(at: env.globalSettingsPath))
        let localContent = parseJSON(await env.mockFileSystem.getFileData(at: env.globalLocalPath))

        // Global file
        #expect(globalContent?["globalSetting"] as? String == "originalValue", "Unchanged setting preserved")
        #expect(globalContent?["settingToEdit"] as? String == "edited", "Setting was edited")
        #expect(globalContent?["settingToMove"] == nil, "Moved setting removed from global")

        // Local file
        #expect(localContent?["localSetting"] as? String == "localValue", "Existing local setting preserved")
        #expect(localContent?["settingToMove"] as? String == "moveMe", "Setting was moved to local")

        // Verify editing mode ended
        #expect(viewModel.isEditingMode == false)
        #expect(viewModel.pendingEdits.isEmpty)
    }
}

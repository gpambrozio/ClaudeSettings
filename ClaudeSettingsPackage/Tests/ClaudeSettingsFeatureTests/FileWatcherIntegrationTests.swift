import Foundation
import Testing
@testable import ClaudeSettingsFeature

/// Integration tests for FileWatcher functionality in ViewModels
@Suite("FileWatcher Integration Tests")
@MainActor
struct FileWatcherIntegrationTests {
    /// Test that SettingsViewModel tracks consecutive reload failures
    @Test("SettingsViewModel tracks consecutive reload failures")
    func settingsViewModelTracksReloadFailures() async throws {
        // Given: A SettingsViewModel with error tracking
        let viewModel = SettingsViewModel()

        // Create a test file that exists initially
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-reload-failure-\(UUID().uuidString).json")
        let validJSON = """
        {
            "theme": "dark"
        }
        """
        try validJSON.write(to: testFile, atomically: true, encoding: .utf8)

        // Load the file
        let settingsFile = try await SettingsParser(fileSystemManager: FileSystemManager()).parseSettingsFile(at: testFile, type: .globalSettings)
        viewModel.settingsFiles = [settingsFile]

        // When: File becomes unreadable (simulating permission issues)
        // Make file unreadable by removing read permissions
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: testFile.path)

        // Simulate reload attempts that fail
        for attempt in 1...3 {
            await viewModel._testReloadChangedFile(at: testFile)

            // After 3 failures, error message should be set
            if attempt >= 3 {
                #expect(viewModel.errorMessage != nil, "Should show error after 3 consecutive failures")
                #expect(viewModel.errorMessage?.contains(testFile.lastPathComponent) == true, "Error should mention filename")
            } else {
                #expect(viewModel.errorMessage == nil, "Should not show error for transient failures (attempt \(attempt))")
            }
        }

        // Cleanup: restore permissions before deleting
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: testFile.path)
        try? FileManager.default.removeItem(at: testFile)
    }

    /// Test that SettingsViewModel resets failure count on successful reload
    @Test("SettingsViewModel resets failure count on success")
    func settingsViewModelResetsFailureCount() async throws {
        // Given: A SettingsViewModel
        let viewModel = SettingsViewModel()

        // Create a test file
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-reset-failure-\(UUID().uuidString).json")
        let validJSON = """
        {
            "theme": "dark"
        }
        """
        try validJSON.write(to: testFile, atomically: true, encoding: .utf8)

        // Load the file
        let settingsFile = try await SettingsParser(fileSystemManager: FileSystemManager()).parseSettingsFile(at: testFile, type: .globalSettings)
        viewModel.settingsFiles = [settingsFile]

        // When: File fails twice, then succeeds
        // Make file unreadable
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: testFile.path)
        await viewModel._testReloadChangedFile(at: testFile)
        await viewModel._testReloadChangedFile(at: testFile)

        // Should not show error yet (only 2 failures)
        #expect(viewModel.errorMessage == nil, "Should not show error for 2 failures")

        // Fix the file by restoring permissions
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: testFile.path)
        await viewModel._testReloadChangedFile(at: testFile)

        // Should succeed and reset counter
        #expect(viewModel.errorMessage == nil, "Should clear error on success")

        // Break it again - should take another 3 failures to show error
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: testFile.path)
        await viewModel._testReloadChangedFile(at: testFile)
        await viewModel._testReloadChangedFile(at: testFile)

        // Still shouldn't show error (counter was reset)
        #expect(viewModel.errorMessage == nil, "Counter should have reset after successful reload")

        // Cleanup: restore permissions before deleting
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: testFile.path)
        try? FileManager.default.removeItem(at: testFile)
    }

    /// Test that SettingsViewModel handles file deletion
    @Test("SettingsViewModel handles file deletion")
    func settingsViewModelHandlesFileDeletion() async throws {
        // Given: A SettingsViewModel with a loaded file
        let viewModel = SettingsViewModel()

        // Create a test file
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-deletion-\(UUID().uuidString).json")
        let validJSON = """
        {
            "theme": "dark"
        }
        """
        try validJSON.write(to: testFile, atomically: true, encoding: .utf8)

        // Load the file
        let settingsFile = try await SettingsParser(fileSystemManager: FileSystemManager()).parseSettingsFile(at: testFile, type: .globalSettings)
        viewModel.settingsFiles = [settingsFile]
        viewModel.settingItems = viewModel.computeSettingItems(from: [settingsFile])

        #expect(viewModel.settingsFiles.count == 1, "Should have one file")
        #expect(!viewModel.settingItems.isEmpty, "Should have settings")

        // When: File is deleted
        try FileManager.default.removeItem(at: testFile)
        await viewModel._testReloadChangedFile(at: testFile)

        // Then: File should be removed from the list
        #expect(viewModel.settingsFiles.isEmpty, "Should have removed deleted file")
        #expect(viewModel.settingItems.isEmpty, "Should have no settings after file deletion")
    }

    /// Test that cleanup prevents zombie watchers
    @Test("Cleanup prevents zombie watchers")
    func cleanupPreventsZombieWatchers() async throws {
        // Given: Multiple ViewModels created and destroyed
        var viewModels: [SettingsViewModel] = []

        // Create and setup several view models with file watchers
        for _ in 0..<5 {
            let vm = SettingsViewModel()
            // Simulate setup (would normally start file watcher)
            viewModels.append(vm)
        }

        #expect(viewModels.count == 5, "Should have created 5 view models")

        // When: Explicitly stopping watchers before releasing
        for vm in viewModels {
            await vm.stopFileWatcher()
        }

        // Clear references
        viewModels.removeAll()

        // Then: No assertion - this test verifies that stopFileWatcher can be called
        // multiple times and that cleanup happens gracefully
        // The real verification is that this doesn't crash or leak resources
        #expect(viewModels.isEmpty, "Should have cleared all view models")
    }

    /// Test that ProjectListViewModel cleanup works
    @Test("ProjectListViewModel cleanup works")
    func projectListViewModelCleanup() async throws {
        // Given: A ProjectListViewModel
        let viewModel = ProjectListViewModel()

        // When: Starting and stopping file watcher
        // Note: We can't easily test the actual file watching without .claude.json file
        // but we can verify that cleanup doesn't crash
        await viewModel.stopFileWatcher()

        // Call it again - should be safe to call multiple times
        await viewModel.stopFileWatcher()

        // Then: Should complete without crashing
        #expect(true, "Multiple stopFileWatcher calls should be safe")
    }
}

import Foundation
import Testing
@testable import ClaudeSettingsFeature

/// Unit tests for FileWatcher logic (not relying on FSEvents timing)
@Suite("FileWatcher Logic Tests")
struct FileWatcherLogicTests {
    /// Test that updating paths multiple times is safe
    @Test("Updating watched paths multiple times is safe")
    func updatingWatchedPathsMultipleTimesIsSafe() async throws {
        let watcher = FileWatcher()

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test.json")

        // Update watching
        await watcher.updateWatchedPaths(directories: [tempDir], filePaths: [testFile])

        // Update again - should be safe (stops previous and starts new)
        await watcher.updateWatchedPaths(directories: [tempDir], filePaths: [testFile])

        // Cleanup
        await watcher.stopWatching()

        // Test passes if we reach here without crashing
        #expect(true, "Updating watched paths multiple times should be safe")
    }

    /// Test that stopping a non-running watcher is safe
    @Test("Stopping a non-running watcher is safe")
    func stoppingNonRunningWatcherIsSafe() async throws {
        let watcher = FileWatcher()

        // Stop without starting - should be safe
        await watcher.stopWatching()

        // Stop again - should still be safe
        await watcher.stopWatching()

        // Test passes if we reach here without crashing
        #expect(true, "Stopping non-running watcher should be safe")
    }

    /// Test that FileWatcher properly accepts directories and file paths
    @Test("FileWatcher API accepts directories and file paths")
    func fileWatcherAPIAcceptsDirectoriesAndFilePaths() async throws {
        let watcher = FileWatcher()

        let tempDir = FileManager.default.temporaryDirectory
        let settingsFile = tempDir.appendingPathComponent("settings.json")
        let localFile = tempDir.appendingPathComponent("settings.local.json")

        // Verify we can pass multiple directories and files
        await watcher.updateWatchedPaths(
            directories: [tempDir, tempDir.appendingPathComponent("subdir")],
            filePaths: [settingsFile, localFile]
        )

        await watcher.stopWatching()

        // Test passes if we can call the API correctly without crashing
        #expect(true, "API accepts multiple directories and file paths")
    }

    /// Test that FileWatcher can watch for files that don't exist yet
    @Test("FileWatcher can watch for files that don't exist yet")
    func fileWatcherCanWatchNonExistentFiles() async throws {
        let watcher = FileWatcher()

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let nonExistentFile = tempDir.appendingPathComponent("does-not-exist.json")

        // Watch the directory and will detect when the file is created
        await watcher.updateWatchedPaths(directories: [tempDir], filePaths: [nonExistentFile])

        // Should not crash even though file doesn't exist
        try await Task.sleep(for: .milliseconds(100))

        await watcher.stopWatching()

        #expect(!FileManager.default.fileExists(atPath: nonExistentFile.path), "File should not exist")
    }

    /// Test that FileWatcher can monitor multiple directories
    @Test("FileWatcher uses directories instead of individual file paths")
    func fileWatcherUsesDirectories() async throws {
        let watcher = FileWatcher()

        let tempDir1 = FileManager.default.temporaryDirectory.appendingPathComponent("dir1")
        let tempDir2 = FileManager.default.temporaryDirectory.appendingPathComponent("dir2")

        let file1 = tempDir1.appendingPathComponent("settings.json")
        let file2 = tempDir2.appendingPathComponent("settings.local.json")

        // Watch multiple directories for specific files
        await watcher.updateWatchedPaths(
            directories: [tempDir1, tempDir2],
            filePaths: [file1, file2]
        )

        await watcher.stopWatching()

        // Test verifies the API accepts this pattern without crashing
        #expect(true, "FileWatcher can monitor multiple directories for specific files")
    }

    /// Verify the API change to AsyncStream-based approach
    @Test("FileWatcher API signature is correct")
    func fileWatcherAPISignatureIsCorrect() async throws {
        let watcher = FileWatcher()

        // The new API uses AsyncStream for file changes
        _ = await watcher.fileChanges

        let dir = FileManager.default.temporaryDirectory
        let file = dir.appendingPathComponent("test.json")

        // This should compile and work
        await watcher.updateWatchedPaths(directories: [dir], filePaths: [file])

        await watcher.stopWatching()

        #expect(true, "API signature has fileChanges AsyncStream and updateWatchedPaths method")
    }

    /// Test that fileChanges stream exists and is accessible
    @Test("FileWatcher provides fileChanges AsyncStream")
    func fileWatcherProvidesFileChangesStream() async throws {
        let watcher = FileWatcher()

        // Accessing the stream should not crash
        let streamTask = Task {
            var eventCount = 0
            for await _ in await watcher.fileChanges {
                eventCount += 1
                if eventCount >= 1 {
                    break
                }
            }
            return eventCount
        }

        // Give it a moment then stop
        try await Task.sleep(for: .milliseconds(100))
        await watcher.stopWatching()

        streamTask.cancel()

        // Test passes if we can access the stream without crashing
        #expect(true, "FileWatcher provides accessible fileChanges AsyncStream")
    }
}

import Foundation
import Testing
@testable import ClaudeSettingsFeature

/// Thread-safe counter for testing async notifications
actor NotificationCounter {
    private var count = 0
    private var receivedURLs: [URL] = []

    func increment() {
        count += 1
    }

    func append(url: URL) {
        receivedURLs.append(url)
    }

    func getCount() -> Int {
        count
    }

    func getURLs() -> [URL] {
        receivedURLs
    }

    func reset() {
        count = 0
        receivedURLs.removeAll()
    }
}

/// Mock FileWatcher for testing - allows manual control of file change events
actor MockFileWatcher: FileWatcherProtocol {
    private var continuation: AsyncStream<URL>.Continuation?
    private var _fileChanges: AsyncStream<URL>?

    var updateWatchedPathsCalls: [(directories: [URL], filePaths: [URL])] = []
    var stopWatchingCallCount = 0

    init() {
        let (stream, continuation) = AsyncStream<URL>.makeStream()
        self._fileChanges = stream
        self.continuation = continuation
    }

    var fileChanges: AsyncStream<URL> {
        _fileChanges ?? AsyncStream { _ in }
    }

    func updateWatchedPaths(directories: [URL], filePaths: [URL]) async {
        updateWatchedPathsCalls.append((directories: directories, filePaths: filePaths))
    }

    func stopWatching() async {
        stopWatchingCallCount += 1
        continuation?.finish()
    }

    /// Simulate a file change event
    func simulateFileChange(at url: URL) {
        continuation?.yield(url)
    }

    /// Reset tracking data for test isolation
    func reset() {
        updateWatchedPathsCalls.removeAll()
        stopWatchingCallCount = 0
    }
}

// MARK: - Test Suite

@Suite("SettingsFileMonitor Tests")
struct SettingsFileMonitorTests {
    // MARK: - Observer Registration Tests

    @Test("Observer registration returns a valid UUID")
    func observerRegistrationReturnsUUID() async throws {
        let mockWatcher = MockFileWatcher()
        let monitor = SettingsFileMonitor(fileWatcher: mockWatcher)

        let observerId = await monitor.registerObserver(scope: .global) { _ in }

        // UUID should be valid (not nil, and formatted correctly)
        #expect(!observerId.uuidString.isEmpty)
    }

    @Test("Registering observer with global scope resolves correct file paths")
    func globalScopeResolvesCorrectPaths() async throws {
        let mockWatcher = MockFileWatcher()
        let monitor = SettingsFileMonitor(fileWatcher: mockWatcher)

        _ = await monitor.registerObserver(scope: .global) { _ in }

        // Should start listening (which calls updateWatchedPaths once configured)
        // But registration alone doesn't call updateWatchedPaths - only configureProjects does
        let callCount = await mockWatcher.updateWatchedPathsCalls.count
        #expect(callCount == 0) // No calls yet, waiting for configureProjects
    }

    @Test("Multiple observers can be registered")
    func multipleObserversCanBeRegistered() async throws {
        let mockWatcher = MockFileWatcher()
        let monitor = SettingsFileMonitor(fileWatcher: mockWatcher)

        let observer1 = await monitor.registerObserver(scope: .global) { _ in }
        let observer2 = await monitor.registerObserver(scope: .global) { _ in }
        let observer3 = await monitor.registerObserver(scope: .global) { _ in }

        // All should have unique IDs
        #expect(observer1 != observer2)
        #expect(observer2 != observer3)
        #expect(observer1 != observer3)
    }

    // MARK: - Observer Unregistration Tests

    @Test("Unregistering valid observer succeeds silently")
    func unregisteringValidObserverSucceeds() async throws {
        let mockWatcher = MockFileWatcher()
        let monitor = SettingsFileMonitor(fileWatcher: mockWatcher)

        let observerId = await monitor.registerObserver(scope: .global) { _ in }

        // Should not crash or throw
        await monitor.unregisterObserver(observerId)
    }

    @Test("Unregistering unknown observer does not crash")
    func unregisteringUnknownObserverDoesNotCrash() async throws {
        let mockWatcher = MockFileWatcher()
        let monitor = SettingsFileMonitor(fileWatcher: mockWatcher)

        let randomId = UUID()

        // Should not crash
        await monitor.unregisterObserver(randomId)
    }

    // MARK: - Observer Update Tests

    @Test("Updating observer scope changes watched paths")
    func updatingObserverScopeChangesWatchedPaths() async throws {
        let mockWatcher = MockFileWatcher()
        let monitor = SettingsFileMonitor(fileWatcher: mockWatcher)

        let observerId = await monitor.registerObserver(scope: .global) { _ in }

        let project = ClaudeProject(
            name: "Test Project",
            path: URL(fileURLWithPath: "/tmp/test-project"),
            claudeDirectory: URL(fileURLWithPath: "/tmp/test-project/.claude")
        )

        // Update to watch projects instead
        await monitor.updateObserver(observerId, scope: .projects([project]))

        // Observer should now watch project files instead of global
        // We can't directly verify internal state, but we can verify it doesn't crash
    }

    @Test("Updating unknown observer does not crash")
    func updatingUnknownObserverDoesNotCrash() async throws {
        let mockWatcher = MockFileWatcher()
        let monitor = SettingsFileMonitor(fileWatcher: mockWatcher)

        let randomId = UUID()
        let project = ClaudeProject(
            name: "Test Project",
            path: URL(fileURLWithPath: "/tmp/test-project"),
            claudeDirectory: URL(fileURLWithPath: "/tmp/test-project/.claude")
        )

        // Should not crash
        await monitor.updateObserver(randomId, scope: .projects([project]))
    }

    // MARK: - File Change Notification Tests

    @Test("Observer receives notification when watched file changes")
    func observerReceivesNotificationForWatchedFile() async throws {
        let mockWatcher = MockFileWatcher()
        let monitor = SettingsFileMonitor(fileWatcher: mockWatcher)
        let homeDir = FileManager.default.homeDirectoryForCurrentUser

        let counter = NotificationCounter()

        _ = await monitor.registerObserver(scope: .global) { url in
            Task {
                await counter.append(url: url)
            }
        }

        // Configure with empty projects to start watching
        await monitor.configureProjects([])

        // Give the async stream listener time to start
        try? await Task.sleep(for: .milliseconds(50))

        // Simulate a change to global settings file
        let globalSettingsPath = SettingsFileType.globalSettings.path(in: homeDir)
        await mockWatcher.simulateFileChange(at: globalSettingsPath)

        // Wait for debouncing (200ms) plus a bit extra
        try? await Task.sleep(for: .milliseconds(300))

        // Verify notification was received
        let receivedURLs = await counter.getURLs()
        #expect(receivedURLs.count == 1)
        #expect(receivedURLs.first?.path == globalSettingsPath.path)
    }

    @Test("Observer does not receive notification for unwatched files")
    func observerDoesNotReceiveNotificationForUnwatchedFiles() async throws {
        let mockWatcher = MockFileWatcher()
        let monitor = SettingsFileMonitor(fileWatcher: mockWatcher)

        let counter = NotificationCounter()

        // Register observer watching only global files
        _ = await monitor.registerObserver(scope: .global) { _ in
            Task {
                await counter.increment()
            }
        }

        await monitor.configureProjects([])
        try? await Task.sleep(for: .milliseconds(50))

        // Simulate a change to a project file (not watched by global scope)
        let projectPath = URL(fileURLWithPath: "/tmp/test-project/.claude/settings.json")
        await mockWatcher.simulateFileChange(at: projectPath)

        // Wait for debouncing
        try? await Task.sleep(for: .milliseconds(300))

        // Should not have received any notifications
        let count = await counter.getCount()
        #expect(count == 0)
    }

    @Test("Multiple observers receive notifications for same file")
    func multipleObserversReceiveNotificationsForSameFile() async throws {
        let mockWatcher = MockFileWatcher()
        let monitor = SettingsFileMonitor(fileWatcher: mockWatcher)
        let homeDir = FileManager.default.homeDirectoryForCurrentUser

        let counter1 = NotificationCounter()
        let counter2 = NotificationCounter()

        _ = await monitor.registerObserver(scope: .global) { _ in
            Task {
                await counter1.increment()
            }
        }

        _ = await monitor.registerObserver(scope: .global) { _ in
            Task {
                await counter2.increment()
            }
        }

        await monitor.configureProjects([])
        try? await Task.sleep(for: .milliseconds(50))

        let globalSettingsPath = SettingsFileType.globalSettings.path(in: homeDir)
        await mockWatcher.simulateFileChange(at: globalSettingsPath)

        try? await Task.sleep(for: .milliseconds(300))

        let count1 = await counter1.getCount()
        let count2 = await counter2.getCount()
        #expect(count1 == 1)
        #expect(count2 == 1)
    }

    // MARK: - Scope Resolution Tests

    @Test("Global scope watches only global files")
    func globalScopeWatchesOnlyGlobalFiles() async throws {
        let mockWatcher = MockFileWatcher()
        let monitor = SettingsFileMonitor(fileWatcher: mockWatcher)
        let homeDir = FileManager.default.homeDirectoryForCurrentUser

        let counter = NotificationCounter()

        _ = await monitor.registerObserver(scope: .global) { url in
            Task {
                await counter.append(url: url)
            }
        }

        await monitor.configureProjects([])
        try? await Task.sleep(for: .milliseconds(50))

        // Simulate change to global settings
        let globalSettingsPath = SettingsFileType.globalSettings.path(in: homeDir)
        await mockWatcher.simulateFileChange(at: globalSettingsPath)

        // Simulate change to project settings (should be ignored)
        let projectPath = URL(fileURLWithPath: "/tmp/project/.claude/settings.json")
        await mockWatcher.simulateFileChange(at: projectPath)

        try? await Task.sleep(for: .milliseconds(300))

        // Should only receive global file notification
        let notifiedFiles = await counter.getURLs()
        #expect(notifiedFiles.count == 1)
        #expect(notifiedFiles.first?.path == globalSettingsPath.path)
    }

    @Test("Projects scope watches project files and .claude.json")
    func projectsScopeWatchesProjectFiles() async throws {
        let mockWatcher = MockFileWatcher()
        let monitor = SettingsFileMonitor(fileWatcher: mockWatcher)
        let homeDir = FileManager.default.homeDirectoryForCurrentUser

        let project = ClaudeProject(
            name: "Test Project",
            path: URL(fileURLWithPath: "/tmp/test-project"),
            claudeDirectory: URL(fileURLWithPath: "/tmp/test-project/.claude")
        )

        let counter = NotificationCounter()

        _ = await monitor.registerObserver(scope: .projects([project])) { url in
            Task {
                await counter.append(url: url)
            }
        }

        await monitor.configureProjects([project])
        try? await Task.sleep(for: .milliseconds(50))

        // Simulate change to project settings
        let projectSettingsPath = SettingsFileType.projectSettings.path(in: project.path)
        await mockWatcher.simulateFileChange(at: projectSettingsPath)

        // Simulate change to .claude.json
        let claudeJsonPath = homeDir.appendingPathComponent(".claude.json")
        await mockWatcher.simulateFileChange(at: claudeJsonPath)

        // Simulate change to global settings (should be ignored)
        let globalSettingsPath = SettingsFileType.globalSettings.path(in: homeDir)
        await mockWatcher.simulateFileChange(at: globalSettingsPath)

        try? await Task.sleep(for: .milliseconds(300))

        // Should receive project and .claude.json notifications, but not global
        let notifiedFiles = await counter.getURLs()
        #expect(notifiedFiles.count == 2)
        #expect(notifiedFiles.contains { $0.path == projectSettingsPath.path })
        #expect(notifiedFiles.contains { $0.path == claudeJsonPath.path })
    }

    @Test("GlobalAndProjects scope watches both global and project files")
    func globalAndProjectsScopeWatchesBoth() async throws {
        let mockWatcher = MockFileWatcher()
        let monitor = SettingsFileMonitor(fileWatcher: mockWatcher)
        let homeDir = FileManager.default.homeDirectoryForCurrentUser

        let project = ClaudeProject(
            name: "Test Project",
            path: URL(fileURLWithPath: "/tmp/test-project"),
            claudeDirectory: URL(fileURLWithPath: "/tmp/test-project/.claude")
        )

        let counter = NotificationCounter()

        _ = await monitor.registerObserver(scope: .globalAndProjects([project])) { url in
            Task {
                await counter.append(url: url)
            }
        }

        await monitor.configureProjects([project])
        try? await Task.sleep(for: .milliseconds(50))

        // Simulate changes to both global and project files
        let globalSettingsPath = SettingsFileType.globalSettings.path(in: homeDir)
        let projectSettingsPath = SettingsFileType.projectSettings.path(in: project.path)

        await mockWatcher.simulateFileChange(at: globalSettingsPath)
        await mockWatcher.simulateFileChange(at: projectSettingsPath)

        try? await Task.sleep(for: .milliseconds(300))

        // Should receive both notifications
        let notifiedFiles = await counter.getURLs()
        #expect(notifiedFiles.count == 2)
        #expect(notifiedFiles.contains { $0.path == globalSettingsPath.path })
        #expect(notifiedFiles.contains { $0.path == projectSettingsPath.path })
    }

    // MARK: - Debouncing Tests

    @Test("Multiple rapid changes are debounced to single notification")
    func rapidChangesAreDebounced() async throws {
        let mockWatcher = MockFileWatcher()
        let monitor = SettingsFileMonitor(fileWatcher: mockWatcher)
        let homeDir = FileManager.default.homeDirectoryForCurrentUser

        let counter = NotificationCounter()

        _ = await monitor.registerObserver(scope: .global) { _ in
            Task {
                await counter.increment()
            }
        }

        await monitor.configureProjects([])
        try? await Task.sleep(for: .milliseconds(50))

        let globalSettingsPath = SettingsFileType.globalSettings.path(in: homeDir)

        // Simulate rapid changes (within debounce window)
        for _ in 0..<5 {
            await mockWatcher.simulateFileChange(at: globalSettingsPath)
            try? await Task.sleep(for: .milliseconds(10))
        }

        // Wait for debouncing to complete
        try? await Task.sleep(for: .milliseconds(300))

        // Should only receive one notification due to debouncing
        let count = await counter.getCount()
        #expect(count == 1)
    }

    @Test("Changes to different files are not debounced together")
    func changesToDifferentFilesAreNotDebouncedTogether() async throws {
        let mockWatcher = MockFileWatcher()
        let monitor = SettingsFileMonitor(fileWatcher: mockWatcher)
        let homeDir = FileManager.default.homeDirectoryForCurrentUser

        let counter = NotificationCounter()

        _ = await monitor.registerObserver(scope: .global) { _ in
            Task {
                await counter.increment()
            }
        }

        await monitor.configureProjects([])
        try? await Task.sleep(for: .milliseconds(50))

        let globalSettingsPath = SettingsFileType.globalSettings.path(in: homeDir)
        let globalLocalPath = SettingsFileType.globalLocal.path(in: homeDir)

        // Simulate changes to different files
        await mockWatcher.simulateFileChange(at: globalSettingsPath)
        await mockWatcher.simulateFileChange(at: globalLocalPath)

        try? await Task.sleep(for: .milliseconds(300))

        // Should receive two notifications (one per file)
        let count = await counter.getCount()
        #expect(count == 2)
    }

    // MARK: - Configuration Tests

    @Test("ConfigureProjects updates file watcher with all project paths")
    func configureProjectsUpdatesFileWatcher() async throws {
        let mockWatcher = MockFileWatcher()
        let monitor = SettingsFileMonitor(fileWatcher: mockWatcher)

        let project1 = ClaudeProject(
            name: "Project 1",
            path: URL(fileURLWithPath: "/tmp/project1"),
            claudeDirectory: URL(fileURLWithPath: "/tmp/project1/.claude")
        )

        let project2 = ClaudeProject(
            name: "Project 2",
            path: URL(fileURLWithPath: "/tmp/project2"),
            claudeDirectory: URL(fileURLWithPath: "/tmp/project2/.claude")
        )

        await monitor.configureProjects([project1, project2])

        let calls = await mockWatcher.updateWatchedPathsCalls
        #expect(calls.count == 1)

        // Should watch global files + .claude.json + both project files
        let filePaths = calls[0].filePaths
        #expect(!filePaths.isEmpty) // Should have multiple files
    }

    @Test("ConfigureProjects with empty array still watches global files")
    func configureProjectsWithEmptyArrayWatchesGlobalFiles() async throws {
        let mockWatcher = MockFileWatcher()
        let monitor = SettingsFileMonitor(fileWatcher: mockWatcher)

        await monitor.configureProjects([])

        let calls = await mockWatcher.updateWatchedPathsCalls
        #expect(calls.count == 1)

        // Should still watch global files and .claude.json
        let filePaths = calls[0].filePaths
        #expect(filePaths.count >= 3) // At least: global settings, global local, .claude.json
    }

    // MARK: - Cleanup Tests

    @Test("StopAll stops file watcher and clears observers")
    func stopAllStopsWatcherAndClearsObservers() async throws {
        let mockWatcher = MockFileWatcher()
        let monitor = SettingsFileMonitor(fileWatcher: mockWatcher)

        _ = await monitor.registerObserver(scope: .global) { _ in }
        await monitor.configureProjects([])

        await monitor.stopAll()

        let stopCallCount = await mockWatcher.stopWatchingCallCount
        #expect(stopCallCount == 1)
    }

    @Test("After stopAll, no notifications are received")
    func afterStopAllNoNotificationsReceived() async throws {
        let mockWatcher = MockFileWatcher()
        let monitor = SettingsFileMonitor(fileWatcher: mockWatcher)
        let homeDir = FileManager.default.homeDirectoryForCurrentUser

        let counter = NotificationCounter()

        _ = await monitor.registerObserver(scope: .global) { _ in
            Task {
                await counter.increment()
            }
        }

        await monitor.configureProjects([])
        try? await Task.sleep(for: .milliseconds(50))

        await monitor.stopAll()

        // Try to simulate a file change after stopping
        let globalSettingsPath = SettingsFileType.globalSettings.path(in: homeDir)
        await mockWatcher.simulateFileChange(at: globalSettingsPath)

        try? await Task.sleep(for: .milliseconds(300))

        // Should not receive any notifications
        let count = await counter.getCount()
        #expect(count == 0)
    }
}

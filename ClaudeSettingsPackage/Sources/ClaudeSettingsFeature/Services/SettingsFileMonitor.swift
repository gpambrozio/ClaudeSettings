import Foundation
import Logging

/// What settings files to monitor
public enum SettingsScope {
    /// Global settings only (~/.claude/)
    case global
    /// Specific projects
    case projects([ClaudeProject])
    /// Global + specific projects
    case globalAndProjects([ClaudeProject])
}

/// Centralized file monitoring service for settings files
/// Manages a single FileWatcher instance and notifies registered observers of file changes
public actor SettingsFileMonitor {
    /// Shared instance for app-wide file monitoring
    public static let shared = SettingsFileMonitor()

    private let logger = Logger(label: "com.claudesettings.filemonitor")

    /// Observer information with pre-computed paths
    private struct Observer {
        let id: UUID
        let scope: SettingsScope
        let watchedPaths: Set<URL> // Pre-computed paths for this scope
        let callback: @Sendable (URL) -> Void
    }

    private var observers: [UUID: Observer] = [:]
    private let fileWatcher: FileWatcherProtocol
    private var debouncers: [String: Debouncer] = [:]
    private var streamListenerTask: Task<Void, Never>?
    private var isConfigured = false

    public init(fileWatcher: FileWatcherProtocol? = nil) {
        self.fileWatcher = fileWatcher ?? FileWatcher()
    }

    /// Configure the monitor with all projects to watch
    /// This should be called once at app startup with all discovered projects
    /// - Parameter projects: All Claude projects to monitor
    public func configureProjects(_ projects: [ClaudeProject]) async {
        logger.info("Configuring file monitor with \(projects.count) projects")

        // Calculate all unique paths to watch from all possible scopes
        var allFilePaths = Set<URL>()
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser

        // Always include global settings
        for fileType: SettingsFileType in [.globalSettings, .globalLocal] {
            allFilePaths.insert(fileType.path(in: homeDirectory))
        }

        // Include .claude.json for project discovery
        allFilePaths.insert(homeDirectory.appendingPathComponent(".claude.json"))

        // Include all project settings
        for project in projects {
            for fileType: SettingsFileType in [.projectSettings, .projectLocal] {
                allFilePaths.insert(fileType.path(in: project.path))
            }
        }

        // Collect unique directories
        var directories = Set<URL>()
        for filePath in allFilePaths {
            directories.insert(filePath.deletingLastPathComponent())
        }

        logger.info("Configuring file watcher for \(directories.count) directories watching \(allFilePaths.count) files")

        // Update the file watcher with all paths
        await fileWatcher.updateWatchedPaths(directories: Array(directories), filePaths: Array(allFilePaths))

        // Start listening to the file changes stream if not already started
        if streamListenerTask == nil {
            startListeningToFileChanges()
        }

        isConfigured = true
    }

    /// Start listening to file changes from the watcher
    private func startListeningToFileChanges() {
        streamListenerTask = Task {
            for await changedURL in await fileWatcher.fileChanges {
                await handleFileChange(at: changedURL)
            }
        }
        logger.debug("Started listening to file changes stream")
    }

    /// Register an observer to watch settings files
    /// - Parameters:
    ///   - scope: What settings files to watch
    ///   - callback: Called when any of the watched files change
    /// - Returns: Observer ID to use for updates or unregistration
    @discardableResult
    public func registerObserver(
        scope: SettingsScope,
        callback: @escaping @Sendable (URL) -> Void
    ) async -> UUID {
        let observerId = UUID()
        let watchedPaths = resolveFilePaths(for: scope)
        let observer = Observer(
            id: observerId,
            scope: scope,
            watchedPaths: watchedPaths,
            callback: callback
        )
        observers[observerId] = observer

        logger.info("Registered observer \(observerId) watching \(watchedPaths.count) files")

        // If not yet configured, start listening (will watch only what's needed)
        if !isConfigured && streamListenerTask == nil {
            startListeningToFileChanges()
        }

        return observerId
    }

    /// Update the scope an observer is watching
    /// - Parameters:
    ///   - observerId: The observer ID returned from registerObserver
    ///   - scope: The new scope to watch
    public func updateObserver(_ observerId: UUID, scope: SettingsScope) async {
        guard let existingObserver = observers[observerId] else {
            logger.warning("Attempted to update unknown observer: \(observerId)")
            return
        }

        let watchedPaths = resolveFilePaths(for: scope)
        observers[observerId] = Observer(
            id: observerId,
            scope: scope,
            watchedPaths: watchedPaths,
            callback: existingObserver.callback
        )

        logger.info("Updated observer \(observerId) to watch \(watchedPaths.count) files")
        // No need to update FileWatcher - it's already watching all necessary paths
    }

    /// Resolve file paths for a given scope
    private func resolveFilePaths(for scope: SettingsScope) -> Set<URL> {
        var filePaths = Set<URL>()
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser

        switch scope {
        case .global:
            // Global settings files
            for fileType: SettingsFileType in [.globalSettings, .globalLocal] {
                filePaths.insert(fileType.path(in: homeDirectory))
            }

        case .projects(let projects):
            // .claude.json for project discovery
            filePaths.insert(homeDirectory.appendingPathComponent(".claude.json"))

            // Project settings files
            for project in projects {
                for fileType: SettingsFileType in [.projectSettings, .projectLocal] {
                    filePaths.insert(fileType.path(in: project.path))
                }
            }

        case .globalAndProjects(let projects):
            // Global settings
            for fileType: SettingsFileType in [.globalSettings, .globalLocal] {
                filePaths.insert(fileType.path(in: homeDirectory))
            }

            // Project settings
            for project in projects {
                for fileType: SettingsFileType in [.projectSettings, .projectLocal] {
                    filePaths.insert(fileType.path(in: project.path))
                }
            }
        }

        return filePaths
    }

    /// Unregister an observer
    /// - Parameter observerId: The observer ID to unregister
    public func unregisterObserver(_ observerId: UUID) async {
        guard observers.removeValue(forKey: observerId) != nil else {
            logger.warning("Attempted to unregister unknown observer: \(observerId)")
            return
        }

        logger.info("Unregistered observer \(observerId)")
        // No need to update FileWatcher - it continues watching all configured paths
    }

    /// Handle file change events with debouncing
    private func handleFileChange(at url: URL) async {
        let path = url.path

        // Get or create debouncer for this file path
        if debouncers[path] == nil {
            debouncers[path] = Debouncer()
        }

        guard let debouncer = debouncers[path] else { return }

        // Debounce: wait 200ms before notifying observers
        await debouncer.debounce(milliseconds: 200) {
            await self.notifyObservers(of: url)
        }
    }

    /// Notify all observers watching a specific file
    private func notifyObservers(of url: URL) async {
        logger.debug("Notifying observers of change: \(url.path)")

        // Find all observers watching this file using pre-computed paths
        for observer in observers.values {
            if observer.watchedPaths.contains(url) {
                observer.callback(url)
            }
        }
    }

    /// Stop all file watching (cleanup)
    public func stopAll() async {
        logger.info("Stopping all file monitoring")
        streamListenerTask?.cancel()
        streamListenerTask = nil
        await fileWatcher.stopWatching()
        observers.removeAll()
        debouncers.removeAll()
        isConfigured = false
    }
}

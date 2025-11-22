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
    private let fileSystemManager: FileSystemManager

    /// Observer information
    private struct Observer {
        let id: UUID
        let scope: SettingsScope
        let callback: @Sendable (URL) -> Void
    }

    private var observers: [UUID: Observer] = [:]
    private var fileWatcher: FileWatcher?
    private var debouncers: [String: Debouncer] = [:]

    public init(fileSystemManager: FileSystemManager = FileSystemManager()) {
        self.fileSystemManager = fileSystemManager
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
        let observer = Observer(id: observerId, scope: scope, callback: callback)
        observers[observerId] = observer

        let filePaths = resolveFilePaths(for: scope)
        logger.info("Registered observer \(observerId) watching \(filePaths.count) files")

        // Update the file watcher with the new aggregated paths
        await updateFileWatcher()

        return observerId
    }

    /// Update the scope an observer is watching
    /// - Parameters:
    ///   - observerId: The observer ID returned from registerObserver
    ///   - scope: The new scope to watch
    public func updateObserver(_ observerId: UUID, scope: SettingsScope) async {
        guard observers[observerId] != nil else {
            logger.warning("Attempted to update unknown observer: \(observerId)")
            return
        }

        let callback = observers[observerId]!.callback
        observers[observerId] = Observer(id: observerId, scope: scope, callback: callback)

        let filePaths = resolveFilePaths(for: scope)
        logger.info("Updated observer \(observerId) to watch \(filePaths.count) files")

        // Update the file watcher with the new aggregated paths
        await updateFileWatcher()
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

        // Update the file watcher (might stop if no more observers)
        await updateFileWatcher()
    }

    /// Update the FileWatcher to watch all files from all observers
    private func updateFileWatcher() async {
        // Stop existing watcher
        await fileWatcher?.stopWatching()
        fileWatcher = nil

        // If no observers, we're done
        guard !observers.isEmpty else {
            logger.debug("No observers, file watcher stopped")
            return
        }

        // Aggregate all file paths from all observers
        var allFilePaths = Set<URL>()
        for observer in observers.values {
            let filePaths = resolveFilePaths(for: observer.scope)
            allFilePaths.formUnion(filePaths)
        }

        guard !allFilePaths.isEmpty else {
            logger.debug("No files to watch")
            return
        }

        // Collect unique directories
        var directories = Set<URL>()
        for filePath in allFilePaths {
            directories.insert(filePath.deletingLastPathComponent())
        }

        logger.info("Setting up file watcher for \(directories.count) directories watching \(allFilePaths.count) files")

        // Create new watcher
        fileWatcher = FileWatcher { [weak self] changedURL in
            Task {
                await self?.handleFileChange(at: changedURL)
            }
        }

        await fileWatcher?.startWatching(directories: Array(directories), filePaths: Array(allFilePaths))
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

        // Find all observers watching this file
        for observer in observers.values {
            let filePaths = resolveFilePaths(for: observer.scope)
            if filePaths.contains(url) {
                observer.callback(url)
            }
        }
    }

    /// Stop all file watching (cleanup)
    public func stopAll() async {
        logger.info("Stopping all file monitoring")
        await fileWatcher?.stopWatching()
        fileWatcher = nil
        observers.removeAll()
        debouncers.removeAll()
    }
}

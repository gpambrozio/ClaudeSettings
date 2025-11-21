import Foundation
import Logging
import SwiftUI

/// ViewModel for managing the list of Claude projects
@MainActor
@Observable
final public class ProjectListViewModel {
    private let fileSystemManager: FileSystemManager
    private let logger = Logger(label: "com.claudesettings.projectlist")

    public var projects: [ClaudeProject] = []
    public var isLoading = false
    public var errorMessage: String?

    private let projectScanner: ProjectScanner
    private var fileWatcher: FileWatcher?
    private let debouncer = Debouncer()

    public init(fileSystemManager: FileSystemManager = FileSystemManager()) {
        self.fileSystemManager = fileSystemManager
        self.projectScanner = ProjectScanner(fileSystemManager: fileSystemManager)
    }

    /// Scan for all Claude projects
    public func scanProjects() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let foundProjects = try await projectScanner.scanProjects()
                projects = foundProjects.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
                logger.info("Loaded \(projects.count) projects")

                // Set up file watching for the Claude config file
                await setupFileWatcher()
            } catch {
                logger.error("Failed to scan projects: \(error)")
                errorMessage = "Failed to scan projects: \(error.localizedDescription)"
            }

            isLoading = false
        }
    }

    /// Reload projects
    public func refresh() {
        scanProjects()
    }

    /// Set up file watcher to monitor ~/.claude.json for changes
    private func setupFileWatcher() async {
        // Stop any existing watcher first
        await stopFileWatcher()

        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let configPath = homeDirectory.appendingPathComponent(".claude.json")

        logger.info("Setting up file watcher for .claude.json")

        // FileWatcher's callback is @Sendable but not MainActor-isolated
        // We need to explicitly hop to MainActor since this ViewModel is MainActor-isolated
        fileWatcher = FileWatcher { [weak self] _ in
            // Only watching one file (.claude.json), so URL parameter is always that file
            Task { @MainActor in
                await self?.handleConfigFileChange()
            }
        }

        // Watch the home directory for changes to .claude.json
        // This way we can detect creation and deletion of the file
        await fileWatcher?.startWatching(directories: [homeDirectory], filePaths: [configPath])
    }

    /// Stop file watching
    public func stopFileWatcher() async {
        await debouncer.cancel()
        await fileWatcher?.stopWatching()
        fileWatcher = nil
    }

    /// Handle changes to .claude.json with debouncing
    private func handleConfigFileChange() async {
        // Debounce: wait 200ms before reloading
        await debouncer.debounce(milliseconds: 200) {
            self.logger.info(".claude.json changed externally, refreshing project list")
            self.refresh()
        }
    }
}

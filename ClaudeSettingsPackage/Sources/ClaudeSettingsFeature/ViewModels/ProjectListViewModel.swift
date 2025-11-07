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
    private var debounceTask: Task<Void, Never>?

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

        // Only watch if the config file exists
        guard await fileSystemManager.exists(at: configPath) else {
            logger.debug("No .claude.json file to watch")
            return
        }

        logger.info("Setting up file watcher for .claude.json")

        fileWatcher = FileWatcher { [weak self] _ in
            Task { @MainActor in
                await self?.handleConfigFileChange()
            }
        }

        await fileWatcher?.startWatching(paths: [configPath])
    }

    /// Stop file watching
    public func stopFileWatcher() async {
        debounceTask?.cancel()
        debounceTask = nil
        await fileWatcher?.stopWatching()
        fileWatcher = nil
    }

    /// Handle changes to .claude.json with debouncing
    private func handleConfigFileChange() async {
        // Cancel any pending reload
        debounceTask?.cancel()

        // Debounce: wait 200ms before reloading
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))

            guard !Task.isCancelled else { return }

            logger.info(".claude.json changed externally, refreshing project list")
            refresh()
        }
    }
}

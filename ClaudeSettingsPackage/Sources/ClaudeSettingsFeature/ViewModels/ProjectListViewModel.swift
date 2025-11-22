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

    /// Set up file watcher to monitor ~/.claude.json and all project settings files
    private func setupFileWatcher() async {
        // Stop any existing watcher first
        await stopFileWatcher()

        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let configPath = homeDirectory.appendingPathComponent(".claude.json")

        // Build list of all directories and files to watch
        var directories: Set<URL> = [homeDirectory]
        var filePaths: [URL] = [configPath]

        // Watch each project's .claude directory for settings file changes
        for project in projects {
            let projectClaudeDir = project.claudeDirectory
            directories.insert(projectClaudeDir)

            // Add all possible settings files for this project
            for fileType: SettingsFileType in [.projectSettings, .projectLocal] {
                let settingsPath = fileType.path(in: project.path)
                filePaths.append(settingsPath)
            }
        }

        logger.info("Setting up file watcher for .claude.json and \(projects.count) projects")

        // FileWatcher's callback is @Sendable but not MainActor-isolated
        // We need to explicitly hop to MainActor since this ViewModel is MainActor-isolated
        fileWatcher = FileWatcher { [weak self] changedURL in
            Task { @MainActor in
                await self?.handleFileChange(at: changedURL)
            }
        }

        // Watch directories for any changes to tracked files
        await fileWatcher?.startWatching(directories: Array(directories), filePaths: filePaths)
    }

    /// Stop file watching
    public func stopFileWatcher() async {
        await debouncer.cancel()
        await fileWatcher?.stopWatching()
        fileWatcher = nil
    }

    /// Handle changes to .claude.json or project settings files with debouncing
    private func handleFileChange(at url: URL) async {
        // Debounce: wait 200ms before reloading to handle rapid successive changes
        await debouncer.debounce(milliseconds: 200) {
            self.logger.info("Settings file changed at \(url.path), refreshing project list")
            self.refresh()
        }
    }
}

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
    private let fileMonitor: SettingsFileMonitor
    private var observerId: UUID?
    private var scanTask: Task<Void, Never>?

    public init(
        fileSystemManager: FileSystemManager = FileSystemManager(),
        fileMonitor: SettingsFileMonitor = .shared
    ) {
        self.fileSystemManager = fileSystemManager
        self.projectScanner = ProjectScanner(fileSystemManager: fileSystemManager)
        self.fileMonitor = fileMonitor
    }

    /// Scan for all Claude projects
    public func scanProjects() {
        // Cancel any existing scan task to prevent concurrent scans
        scanTask?.cancel()

        isLoading = true
        errorMessage = nil

        scanTask = Task {
            do {
                let foundProjects = try await projectScanner.scanProjects()

                // Check if task was cancelled
                guard !Task.isCancelled else {
                    logger.info("Project scan was cancelled")
                    return
                }

                projects = foundProjects.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
                logger.info("Loaded \(projects.count) projects")

                // Configure the centralized file monitor with all projects
                await fileMonitor.configureProjects(foundProjects)

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

    /// Set up file monitoring for ~/.claude.json and all project settings files
    private func setupFileWatcher() async {
        logger.info("Registering file monitoring for .claude.json and \(projects.count) projects")

        // The monitor handles all path enumeration internally
        let scope: SettingsScope = .projects(projects)

        // Register with the centralized file monitor
        // The callback will be called on a background thread, so we need to hop to MainActor
        if let existingObserverId = observerId {
            // Update existing observer
            await fileMonitor.updateObserver(existingObserverId, scope: scope)
        } else {
            // Register new observer
            observerId = await fileMonitor.registerObserver(scope: scope) { [weak self] changedURL in
                Task { @MainActor in
                    self?.handleFileChange(at: changedURL)
                }
            }
        }
    }

    /// Stop file watching
    public func stopFileWatcher() async {
        if let observerId {
            await fileMonitor.unregisterObserver(observerId)
            self.observerId = nil
        }
    }

    /// Handle changes to .claude.json or project settings files
    /// Note: Debouncing is handled by SettingsFileMonitor
    private func handleFileChange(at url: URL) {
        logger.info("Settings file changed at \(url.path), refreshing project list")
        refresh()
    }
}

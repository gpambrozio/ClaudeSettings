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
}

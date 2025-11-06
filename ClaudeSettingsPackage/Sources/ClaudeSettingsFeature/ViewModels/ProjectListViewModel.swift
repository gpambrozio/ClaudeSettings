import Foundation
import Logging
import SwiftUI

/// ViewModel for managing the list of Claude projects
@MainActor
@Observable
final public class ProjectListViewModel {
    private let fileSystemManager = FileSystemManager()
    private let logger = Logger(label: "com.claudesettings.projectlist")

    public var projects: [ClaudeProject] = []
    public var isLoading = false
    public var errorMessage: String?

    private var projectScanner: ProjectScanner?

    public init() {
        self.projectScanner = ProjectScanner(fileSystemManager: fileSystemManager)
    }

    /// Scan for all Claude projects
    public func scanProjects() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                guard let scanner = projectScanner else {
                    throw ProjectListError.scannerNotInitialized
                }

                let foundProjects = try await scanner.scanProjects()
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

/// Errors that can occur in ProjectListViewModel
enum ProjectListError: LocalizedError {
    case scannerNotInitialized

    var errorDescription: String? {
        switch self {
        case .scannerNotInitialized:
            return "Project scanner not initialized"
        }
    }
}

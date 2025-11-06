import Foundation
import Logging
import SwiftUI

/// ViewModel for managing settings of a specific project
@MainActor
@Observable
final public class SettingsViewModel {
    private let fileSystemManager = FileSystemManager()
    private let logger = Logger(label: "com.claudesettings.settings")

    public var settingsFiles: [SettingsFile] = []
    public var mergedSettings: [String: AnyCodable] = [:]
    public var isLoading = false
    public var errorMessage: String?

    private var settingsParser: SettingsParser?
    private let project: ClaudeProject?

    public init(project: ClaudeProject? = nil) {
        self.project = project
        self.settingsParser = SettingsParser(fileSystemManager: fileSystemManager)
    }

    /// Load all settings files for the current project
    public func loadSettings() {
        guard let project else {
            logger.warning("No project set, loading global settings only")
            loadGlobalSettings()
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                guard let parser = settingsParser else {
                    throw SettingsViewModelError.parserNotInitialized
                }

                var files: [SettingsFile] = []

                // Load project settings
                let projectSettingsPath = project.claudeDirectory.appendingPathComponent("settings.json")
                if await fileSystemManager.exists(at: projectSettingsPath) {
                    let file = try await parser.parseSettingsFile(
                        at: projectSettingsPath,
                        type: .projectSettings
                    )
                    files.append(file)
                }

                let projectLocalPath = project.claudeDirectory.appendingPathComponent("settings.local.json")
                if await fileSystemManager.exists(at: projectLocalPath) {
                    let file = try await parser.parseSettingsFile(
                        at: projectLocalPath,
                        type: .projectLocal
                    )
                    files.append(file)
                }

                settingsFiles = files
                mergedSettings = await parser.mergeSettings(files)
                logger.info("Loaded \(files.count) settings files")
            } catch {
                logger.error("Failed to load settings: \(error)")
                errorMessage = "Failed to load settings: \(error.localizedDescription)"
            }

            isLoading = false
        }
    }

    /// Load only global settings
    private func loadGlobalSettings() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                guard let parser = settingsParser else {
                    throw SettingsViewModelError.parserNotInitialized
                }

                var files: [SettingsFile] = []

                let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
                let globalSettingsPath = homeDirectory.appendingPathComponent(".claude/settings.json")

                if await fileSystemManager.exists(at: globalSettingsPath) {
                    let file = try await parser.parseSettingsFile(
                        at: globalSettingsPath,
                        type: .globalSettings
                    )
                    files.append(file)
                }

                let globalLocalPath = homeDirectory.appendingPathComponent(".claude/settings.local.json")
                if await fileSystemManager.exists(at: globalLocalPath) {
                    let file = try await parser.parseSettingsFile(
                        at: globalLocalPath,
                        type: .globalLocal
                    )
                    files.append(file)
                }

                settingsFiles = files
                mergedSettings = await parser.mergeSettings(files)
                logger.info("Loaded \(files.count) global settings files")
            } catch {
                logger.error("Failed to load global settings: \(error)")
                errorMessage = "Failed to load settings: \(error.localizedDescription)"
            }

            isLoading = false
        }
    }
}

/// Errors that can occur in SettingsViewModel
enum SettingsViewModelError: LocalizedError {
    case parserNotInitialized

    var errorDescription: String? {
        switch self {
        case .parserNotInitialized:
            return "Settings parser not initialized"
        }
    }
}

import Foundation
import Logging
import SwiftUI

/// ViewModel for managing settings of a specific project
@MainActor
@Observable
final public class SettingsViewModel {
    private let fileSystemManager: FileSystemManager
    private let logger = Logger(label: "com.claudesettings.settings")

    public var settingsFiles: [SettingsFile] = []
    public var settingItems: [SettingItem] = []
    public var validationErrors: [ValidationError] = []
    public var isLoading = false
    public var errorMessage: String?

    private let settingsParser: SettingsParser
    private let project: ClaudeProject?

    public init(project: ClaudeProject? = nil, fileSystemManager: FileSystemManager = FileSystemManager()) {
        self.project = project
        self.fileSystemManager = fileSystemManager
        self.settingsParser = SettingsParser(fileSystemManager: fileSystemManager)
    }

    /// Load all settings files for the current project
    public func loadSettings() {
        loadSettingsFiles(includeProject: project != nil, projectPath: project?.path)
    }

    /// Load settings files with optional project scope
    private func loadSettingsFiles(includeProject: Bool, projectPath: URL?) {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                var files: [SettingsFile] = []
                let homeDirectory = FileManager.default.homeDirectoryForCurrentUser

                // Load enterprise managed settings first (highest precedence, cannot be overridden)
                for enterprisePath in SettingsFileType.enterpriseManagedPaths(homeDirectory: homeDirectory) where await fileSystemManager.exists(at: enterprisePath) {
                    let file = try await settingsParser.parseSettingsFile(
                        at: enterprisePath,
                        type: .enterpriseManaged
                    )
                    files.append(file)
                    logger.info("Loaded enterprise managed settings from: \(enterprisePath.path)")
                    break // Only load the first found enterprise settings
                }

                // Load global settings (they form the base layer)
                let globalSettingsPath = SettingsFileType.globalSettings.path(in: homeDirectory)
                if await fileSystemManager.exists(at: globalSettingsPath) {
                    let file = try await settingsParser.parseSettingsFile(
                        at: globalSettingsPath,
                        type: .globalSettings
                    )
                    files.append(file)
                }

                let globalLocalPath = SettingsFileType.globalLocal.path(in: homeDirectory)
                if await fileSystemManager.exists(at: globalLocalPath) {
                    let file = try await settingsParser.parseSettingsFile(
                        at: globalLocalPath,
                        type: .globalLocal
                    )
                    files.append(file)
                }

                // Load project settings if requested
                if includeProject, let projectPath {
                    let projectSettingsPath = SettingsFileType.projectSettings.path(in: projectPath)
                    if await fileSystemManager.exists(at: projectSettingsPath) {
                        let file = try await settingsParser.parseSettingsFile(
                            at: projectSettingsPath,
                            type: .projectSettings
                        )
                        files.append(file)
                    }

                    let projectLocalPath = SettingsFileType.projectLocal.path(in: projectPath)
                    if await fileSystemManager.exists(at: projectLocalPath) {
                        let file = try await settingsParser.parseSettingsFile(
                            at: projectLocalPath,
                            type: .projectLocal
                        )
                        files.append(file)
                    }
                }

                settingsFiles = files
                settingItems = computeSettingItems(from: files)
                validationErrors = files.flatMap(\.validationErrors)

                let scope = includeProject ? "settings" : "global settings"
                logger.info("Loaded \(files.count) \(scope) files with \(settingItems.count) settings and \(validationErrors.count) validation errors")
            } catch {
                logger.error("Failed to load settings: \(error)")
                errorMessage = userFriendlyErrorMessage(for: error)
            }

            isLoading = false
        }
    }

    /// Convert technical errors into user-friendly messages
    private func userFriendlyErrorMessage(for error: Error) -> String {
        switch error {
        case let fsError as FileSystemError:
            switch fsError {
            case .readFailed:
                return "Unable to read settings file. Please check if the file exists and you have permission to access it."
            case .writeFailed:
                return "Unable to save settings. Please check if you have write permission for this location."
            case .directoryCreationFailed:
                return "Unable to create settings directory. Please check folder permissions."
            case .directoryListFailed:
                return "Unable to access settings directory. Please check folder permissions."
            case .deleteFailed:
                return "Unable to delete settings file. Please check file permissions."
            case .copyFailed:
                return "Unable to copy settings file. Please check file permissions."
            case .attributeNotFound,
                 .attributeReadFailed:
                return "Unable to read file information. The file may be corrupted or inaccessible."
            }
        case let urlError as URLError:
            return "Network or file access error: \(urlError.localizedDescription)"
        case is DecodingError:
            return "Settings file contains invalid data format. Please check the JSON syntax."
        default:
            // Log technical details but show generic message to user
            return "Unable to load settings. Please check that your configuration files are valid and accessible."
        }
    }

    /// Compute setting items with source tracking
    func computeSettingItems(from files: [SettingsFile]) -> [SettingItem] {
        // Build a dictionary mapping keys to their source files (sorted by precedence)
        var keyToSources: [String: [(SettingsFileType, SettingValue)]] = [:]

        for file in files {
            let flattenedKeys = flattenDictionary(file.content)
            for (key, value) in flattenedKeys {
                if keyToSources[key] == nil {
                    keyToSources[key] = []
                }
                keyToSources[key]?.append((file.type, value))
            }
        }

        // Sort each key's sources by precedence and create SettingItems
        var items: [SettingItem] = []

        for (key, sources) in keyToSources {
            let sortedSources = sources.sorted { $0.0.precedence < $1.0.precedence }

            guard
                let lowestSource = sortedSources.first,
                let activeSource = sortedSources.last else { continue }

            let valueType = activeSource.1.valueType

            // For arrays, settings are additive across sources
            // For other types, higher precedence overrides lower precedence
            // Track contributions for all settings to show in inspector
            let (overriddenBy, contributions): (SettingsFileType?, [SourceContribution])
            if valueType == .array && sortedSources.count > 1 {
                // Arrays are additive - track all contributing sources with their individual values
                overriddenBy = nil
                contributions = sortedSources.map { SourceContribution(source: $0.0, value: $0.1) }
            } else if sortedSources.count > 1 {
                // Non-arrays are replaced - track both base and override for display
                overriddenBy = activeSource.0
                contributions = sortedSources.map { SourceContribution(source: $0.0, value: $0.1) }
            } else {
                // Single source
                overriddenBy = nil
                contributions = sortedSources.map { SourceContribution(source: $0.0, value: $0.1) }
            }

            let item = SettingItem(
                key: key,
                value: activeSource.1,
                valueType: valueType,
                source: lowestSource.0,
                overriddenBy: overriddenBy,
                contributions: contributions,
                isDeprecated: false, // TODO: Implement deprecation checking
                documentation: nil // TODO: Add documentation lookup
            )

            items.append(item)
        }

        return items.sorted { $0.key < $1.key }
    }

    /// Flatten a nested dictionary to dot-notation keys
    private func flattenDictionary(_ dict: [String: SettingValue], prefix: String = "") -> [String: SettingValue] {
        var result: [String: SettingValue] = [:]

        for (key, value) in dict {
            let fullKey = prefix.isEmpty ? key : "\(prefix).\(key)"

            if case let .object(nestedDict) = value {
                let flattened = flattenDictionary(nestedDict, prefix: fullKey)
                result.merge(flattened) { _, new in new }
            } else {
                result[fullKey] = value
            }
        }

        return result
    }
}

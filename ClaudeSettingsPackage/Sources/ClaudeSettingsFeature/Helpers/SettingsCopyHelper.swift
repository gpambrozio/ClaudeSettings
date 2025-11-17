import Foundation
import Logging

/// Helper for copying settings to project files via drag and drop
public enum SettingsCopyHelper {
    private static let logger = Logger(label: "com.claudesettings.copy")

    /// Copy one or more settings to a project's settings file
    /// - Parameters:
    ///   - setting: The setting(s) to copy (can be single or collection)
    ///   - project: The target project
    ///   - fileType: The file type (projectSettings or projectLocal)
    @MainActor
    public static func copySetting(
        setting: DraggableSetting,
        to project: ClaudeProject,
        fileType: SettingsFileType
    ) async throws {
        // Verify this is a project file type
        guard fileType == .projectSettings || fileType == .projectLocal else {
            throw SettingsError.invalidFileType("Can only copy to project settings or project local files")
        }

        let settingCount = setting.settings.count
        let settingLabel = settingCount == 1 ? "setting '\(setting.key)'" : "\(settingCount) settings"
        logger.info("Copying \(settingLabel) to \(project.name) (\(fileType.displayName))")

        // Create a temporary SettingsViewModel for the target project
        // This reuses all existing file handling, validation, backup, and rollback logic
        let viewModel = SettingsViewModel(project: project)
        await viewModel.loadSettingsAsync()

        // Convert entries to (key, value) tuples for batch update
        let updates = setting.settings.map { ($0.key, $0.value) }

        // Use the unified batch update method which handles:
        // - Creating a single backup before all updates
        // - Creating the file if it doesn't exist
        // - Creating .claude directory if needed
        // - Proper nested value handling
        // - File watching and validation
        // - Rollback on failure
        try await viewModel.batchUpdateSettings(updates, in: fileType)

        logger.info("Successfully copied \(settingLabel) to \(fileType.displayName)")
    }
}

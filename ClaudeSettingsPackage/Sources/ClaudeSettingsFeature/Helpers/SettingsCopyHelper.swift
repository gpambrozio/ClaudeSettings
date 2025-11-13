import Foundation
import Logging

/// Helper for copying settings to project files via drag and drop
public enum SettingsCopyHelper {
    private static let logger = Logger(label: "com.claudesettings.copy")

    /// Copy a setting to a project's settings file
    /// - Parameters:
    ///   - setting: The setting to copy
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

        logger.info("Copying setting '\(setting.key)' to \(project.name) (\(fileType.displayName))")

        // Create a temporary SettingsViewModel for the target project
        // This reuses all existing file handling, validation, and backup logic
        let viewModel = SettingsViewModel(project: project)
        viewModel.loadSettings()

        // Use the existing updateSetting method which handles:
        // - Creating the file if it doesn't exist
        // - Creating .claude directory if needed
        // - Creating backups before modification
        // - Proper nested value handling
        // - File watching and validation
        try await viewModel.updateSetting(key: setting.key, value: setting.value, in: fileType)

        logger.info("Successfully copied setting '\(setting.key)' to \(fileType.displayName)")
    }
}

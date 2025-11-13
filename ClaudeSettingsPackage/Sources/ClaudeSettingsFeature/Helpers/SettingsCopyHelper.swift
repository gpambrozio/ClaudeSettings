import Foundation
import Logging

/// Helper for copying settings to project files
public enum SettingsCopyHelper {
    private static let logger = Logger(label: "com.claudesettings.copy")

    /// Copy a setting to a project's settings file
    /// - Parameters:
    ///   - setting: The setting to copy
    ///   - project: The target project
    ///   - fileType: The file type (projectSettings or projectLocal)
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

        let fileSystemManager = FileSystemManager()
        let settingsParser = SettingsParser(fileSystemManager: fileSystemManager)

        // Determine the file path
        let filePath = fileType.path(in: project.path)

        // Load existing file or create new one
        var settingsFile: SettingsFile

        if await fileSystemManager.exists(at: filePath) {
            // Load existing file
            settingsFile = try await settingsParser.parseSettingsFile(at: filePath, type: fileType)

            // Create backup before modifying
            _ = try await fileSystemManager.createBackup(of: filePath)
            logger.debug("Created backup of existing file")
        } else {
            // Create new file structure
            settingsFile = SettingsFile(
                type: fileType,
                path: filePath,
                content: [:],
                isValid: true,
                validationErrors: [],
                lastModified: Date(),
                isReadOnly: false
            )

            // Ensure .claude directory exists
            let claudeDir = project.claudeDirectory
            if !await fileSystemManager.exists(at: claudeDir) {
                try await fileSystemManager.createDirectory(at: claudeDir)
                logger.info("Created .claude directory at \(claudeDir.path)")
            }
        }

        // Add the setting to the content
        var updatedContent = settingsFile.content
        try setNestedValue(&updatedContent, for: setting.key, value: setting.value)
        settingsFile.content = updatedContent

        // Write the file
        try await settingsParser.writeSettingsFile(&settingsFile)

        logger.info("Successfully copied setting '\(setting.key)' to \(fileType.displayName)")
    }

    /// Set a nested value in a dictionary using dot notation
    private static func setNestedValue(
        _ dict: inout [String: SettingValue],
        for key: String,
        value: SettingValue
    ) throws {
        let components = key.split(separator: ".")

        guard !components.isEmpty else {
            throw SettingsError.invalidKey("Empty key")
        }

        if components.count == 1 {
            dict[String(components[0])] = value
        } else {
            let firstKey = String(components[0])
            let remainingKey = components.dropFirst().joined(separator: ".")

            // Get or create the nested dictionary
            var nested: [String: SettingValue]
            if let existingValue = dict[firstKey] {
                // Validate that the existing value is an object
                if case let .object(existing) = existingValue {
                    nested = existing
                } else {
                    // Type mismatch - we need to traverse through this, but it's not an object
                    throw SettingsError.typeMismatch(
                        key: key,
                        expected: "object",
                        found: existingValue.typeName
                    )
                }
            } else {
                // No existing value, create new object
                nested = [:]
            }

            // Recursively set the value
            try setNestedValue(&nested, for: remainingKey, value: value)
            dict[firstKey] = .object(nested)
        }
    }
}


import Foundation
import Logging

/// Parses and validates Claude Code settings files
public actor SettingsParser {
    private let fileSystemManager: FileSystemManager
    private let logger = Logger(label: "com.claudesettings.parser")

    public init(fileSystemManager: FileSystemManager) {
        self.fileSystemManager = fileSystemManager
    }

    /// Parse a JSON settings file
    public func parseSettingsFile(at url: URL, type: SettingsFileType) async throws -> SettingsFile {
        logger.debug("Parsing settings file at: \(url.path)")

        let data = try await fileSystemManager.readFile(at: url)
        let modificationDate = try await fileSystemManager.modificationDate(of: url)
        let isReadOnly = !(await fileSystemManager.isWritable(at: url))

        var validationErrors: [ValidationError] = []
        var content: [String: AnyCodable] = [:]
        var isValid = true

        // Try to parse JSON
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            if let dict = jsonObject as? [String: Any] {
                content = dict.mapValues { AnyCodable($0) }
                logger.debug("Successfully parsed JSON with \(content.count) keys")
            } else {
                validationErrors.append(ValidationError(
                    type: .syntax,
                    message: "Settings file must be a JSON object",
                    suggestion: "Ensure the file contains a JSON object at the root level"
                ))
                isValid = false
            }
        } catch {
            logger.error("JSON parsing failed: \(error)")
            validationErrors.append(ValidationError(
                type: .syntax,
                message: "Invalid JSON syntax: \(error.localizedDescription)",
                suggestion: "Check for missing commas, quotes, or brackets"
            ))
            isValid = false
        }

        // Validate known settings
        if isValid {
            validationErrors.append(contentsOf: validateKnownSettings(content))
        }

        return SettingsFile(
            type: type,
            path: url,
            content: content,
            isValid: isValid,
            validationErrors: validationErrors,
            lastModified: modificationDate,
            isReadOnly: isReadOnly
        )
    }

    /// Write a settings file
    public func writeSettingsFile(_ settingsFile: SettingsFile) async throws {
        logger.debug("Writing settings file to: \(settingsFile.path.path)")

        // Convert content back to native types
        let nativeContent = settingsFile.content.mapValues(\.value)

        // Serialize to JSON with pretty printing
        let jsonData = try JSONSerialization.data(
            withJSONObject: nativeContent,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )

        try await fileSystemManager.writeFile(data: jsonData, to: settingsFile.path)
    }

    /// Validate known settings keys and values
    private func validateKnownSettings(_ content: [String: AnyCodable]) -> [ValidationError] {
        var errors: [ValidationError] = []

        // Check for common deprecated keys (example - extend as needed)
        let deprecatedKeys = [
            "old_setting_name": "Use 'new_setting_name' instead",
        ]

        for (key, suggestion) in deprecatedKeys where content[key] != nil {
            errors.append(ValidationError(
                type: .deprecated,
                message: "Setting '\(key)' is deprecated",
                key: key,
                suggestion: suggestion
            ))
        }

        // Validate specific known settings structure
        // Example: hooks should be an object
        if let hooks = content["hooks"]?.value {
            if !(hooks is [String: Any]) {
                errors.append(ValidationError(
                    type: .syntax,
                    message: "'hooks' must be an object",
                    key: "hooks",
                    suggestion: "Change 'hooks' to an object with hook types as keys"
                ))
            }
        }

        // Example: permissions.allow should be an array
        if let permissions = content["permissions"]?.value as? [String: Any] {
            if let allow = permissions["allow"], !(allow is [Any]) {
                errors.append(ValidationError(
                    type: .syntax,
                    message: "'permissions.allow' must be an array",
                    key: "permissions.allow",
                    suggestion: "Change to an array of permission strings"
                ))
            }
        }

        return errors
    }

    /// Merge multiple settings files according to precedence
    public func mergeSettings(_ files: [SettingsFile]) -> [String: AnyCodable] {
        // Sort by precedence (lowest first, so higher precedence overwrites)
        let sortedFiles = files.sorted { $0.type.precedence < $1.type.precedence }

        var merged: [String: Any] = [:]

        for file in sortedFiles {
            let nativeContent = file.content.mapValues(\.value)
            merged = deepMerge(merged, nativeContent)
        }

        return merged.mapValues { AnyCodable($0) }
    }

    /// Deep merge two dictionaries (recursive)
    /// Arrays are concatenated (additive), objects are deep merged, other values are replaced
    /// Per Claude Code docs: arrays accumulate across configs, deny rules take precedence over allow
    private func deepMerge(_ base: [String: Any], _ overlay: [String: Any]) -> [String: Any] {
        var result = base

        for (key, value) in overlay {
            if
                let existingDict = result[key] as? [String: Any],
                let overlayDict = value as? [String: Any] {
                // Recursively merge nested objects
                result[key] = deepMerge(existingDict, overlayDict)
            } else if
                let existingArray = result[key] as? [Any],
                let overlayArray = value as? [Any] {
                // Concatenate arrays (settings are additive for arrays)
                // Note: Deduplication is intentionally NOT done here to preserve
                // the ability to track which config contributed which values
                result[key] = existingArray + overlayArray
            } else {
                // Replace other values (higher precedence overrides lower)
                result[key] = value
            }
        }

        return result
    }
}

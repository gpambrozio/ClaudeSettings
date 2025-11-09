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
        var content: [String: SettingValue] = [:]
        var originalKeyOrder: [String] = []
        var isValid = true

        // Try to parse JSON
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            if let dict = jsonObject as? [String: Any] {
                content = dict.mapValues { SettingValue(any: $0) }
                // Preserve the original key order from the JSON file
                // JSONSerialization preserves key order since iOS 13/macOS 10.15
                originalKeyOrder = Array(dict.keys)
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
            isReadOnly: isReadOnly,
            originalKeyOrder: originalKeyOrder
        )
    }

    /// Write a settings file and return the key order that was used
    /// - Returns: The key order as written to the file (new keys first, then original order)
    public func writeSettingsFile(_ settingsFile: SettingsFile) async throws -> [String] {
        logger.debug("Writing settings file to: \(settingsFile.path.path)")

        // Convert content back to native types
        let nativeContent = settingsFile.content.mapValues(\.asAny)

        // Determine the key order: new keys first, then original order
        let existingKeys = Set(settingsFile.originalKeyOrder)
        let newKeys = nativeContent.keys.filter { !existingKeys.contains($0) }.sorted()
        let orderedKeys = newKeys + settingsFile.originalKeyOrder.filter { nativeContent.keys.contains($0) }

        // Manually build JSON with custom key ordering
        let jsonData = try serializeJSON(content: nativeContent, keyOrder: orderedKeys)

        try await fileSystemManager.writeFile(data: jsonData, to: settingsFile.path)

        return orderedKeys
    }

    /// Serialize JSON with custom key ordering
    private func serializeJSON(content: [String: Any], keyOrder: [String]) throws -> Data {
        var jsonString = "{\n"

        for (index, key) in keyOrder.enumerated() {
            guard let value = content[key] else { continue }

            // Serialize the value using JSONSerialization
            let valueData = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .withoutEscapingSlashes])
            guard let valueString = String(data: valueData, encoding: .utf8) else {
                throw SettingsError.serializationFailed("Failed to encode value for key '\(key)'")
            }

            // Escape the key for JSON
            let escapedKey = escapeJSONString(key)

            // Indent the value (pretty printing)
            let indentedValue = valueString.split(separator: "\n").enumerated().map { lineIndex, line in
                lineIndex == 0 ? String(line) : "  \(line)"
            }.joined(separator: "\n")

            jsonString += "  \"\(escapedKey)\": \(indentedValue)"

            // Add comma if not the last item
            if index < keyOrder.count - 1 {
                jsonString += ","
            }
            jsonString += "\n"
        }

        jsonString += "}\n"

        guard let data = jsonString.data(using: .utf8) else {
            throw SettingsError.serializationFailed("Failed to encode JSON string to UTF-8")
        }

        return data
    }

    /// Escape a string for use in JSON
    private func escapeJSONString(_ string: String) -> String {
        var escaped = ""
        for char in string {
            switch char {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default: escaped.append(char)
            }
        }
        return escaped
    }

    /// Validate known settings keys and values
    private func validateKnownSettings(_ content: [String: SettingValue]) -> [ValidationError] {
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
        if let hooks = content["hooks"] {
            if case .object = hooks {
                // Valid
            } else {
                errors.append(ValidationError(
                    type: .syntax,
                    message: "'hooks' must be an object",
                    key: "hooks",
                    suggestion: "Change 'hooks' to an object with hook types as keys"
                ))
            }
        }

        // Example: permissions.allow should be an array
        if let permissions = content["permissions"], case let .object(permDict) = permissions {
            if let allow = permDict["allow"] {
                if case .array = allow {
                    // Valid
                } else {
                    errors.append(ValidationError(
                        type: .syntax,
                        message: "'permissions.allow' must be an array",
                        key: "permissions.allow",
                        suggestion: "Change to an array of permission strings"
                    ))
                }
            }
        }

        return errors
    }
}

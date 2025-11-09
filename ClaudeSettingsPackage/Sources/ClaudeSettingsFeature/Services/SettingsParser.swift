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
        var isValid = true

        // Try to parse JSON
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            if let dict = jsonObject as? [String: Any] {
                content = dict.mapValues { SettingValue(any: $0) }
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
            originalData: data
        )
    }

    /// Write a settings file and update it with the written data
    /// - Parameter settingsFile: The settings file to write (passed as inout to update originalData)
    /// - Returns: The key order as written to the file (new keys first, then original order)
    public func writeSettingsFile(_ settingsFile: inout SettingsFile) async throws -> [String] {
        logger.debug("Writing settings file to: \(settingsFile.path.path)")

        // Convert content back to native types
        let nativeContent = settingsFile.content.mapValues(\.asAny)

        // Parse original JSON to extract nested key orders (including top-level)
        let nestedKeyOrders = settingsFile.originalData != nil ? extractNestedKeyOrders(from: settingsFile.originalData!) : [:]

        // Determine the key order: new keys first, then original order
        // Top-level keys are stored at the empty path ""
        let originalKeyOrder = nestedKeyOrders[""] ?? []
        let existingKeys = Set(originalKeyOrder)
        let newKeys = nativeContent.keys.filter { !existingKeys.contains($0) }.sorted()
        let orderedKeys = newKeys + originalKeyOrder.filter { nativeContent.keys.contains($0) }

        // Manually build JSON with custom key ordering
        let jsonData = try serializeJSON(content: nativeContent, keyOrder: orderedKeys, nestedKeyOrders: nestedKeyOrders)

        try await fileSystemManager.writeFile(data: jsonData, to: settingsFile.path)

        // Update the original data to reflect what was just written
        settingsFile.originalData = jsonData

        return orderedKeys
    }

    /// Serialize JSON with custom key ordering
    private func serializeJSON(content: [String: Any], keyOrder: [String], nestedKeyOrders: [String: [String]]) throws -> Data {
        let jsonString = try serializeValue(content, keyOrder: keyOrder, nestedKeyOrders: nestedKeyOrders, indent: 0, path: "")
        guard let data = (jsonString + "\n").data(using: .utf8) else {
            throw SettingsError.serializationFailed("Failed to encode JSON string to UTF-8")
        }
        return data
    }

    /// Recursively serialize a value with proper formatting
    private func serializeValue(_ value: Any, keyOrder: [String]? = nil, nestedKeyOrders: [String: [String]], indent: Int, path: String) throws -> String {
        let indentStr = String(repeating: "  ", count: indent)
        let nextIndent = indent + 1
        let nextIndentStr = String(repeating: "  ", count: nextIndent)

        if let dict = value as? [String: Any] {
            // Object
            var result = "{\n"

            // Determine key order for this object
            let objectKeyOrder: [String]
            if let providedOrder = keyOrder {
                // Top level - use provided order
                objectKeyOrder = providedOrder
            } else if let storedOrder = nestedKeyOrders[path] {
                // Nested object with stored order from original JSON
                objectKeyOrder = storedOrder.filter { dict.keys.contains($0) }
            } else {
                // No stored order - use sorted keys
                objectKeyOrder = dict.keys.sorted()
            }

            for (index, key) in objectKeyOrder.enumerated() {
                guard let val = dict[key] else { continue }

                let escapedKey = escapeJSONString(key)
                let newPath = path.isEmpty ? key : "\(path).\(key)"
                let serializedValue = try serializeValue(val, keyOrder: nil, nestedKeyOrders: nestedKeyOrders, indent: nextIndent, path: newPath)

                result += "\(nextIndentStr)\"\(escapedKey)\": \(serializedValue)"
                if index < objectKeyOrder.count - 1 {
                    result += ","
                }
                result += "\n"
            }

            result += "\(indentStr)}"
            return result

        } else if let array = value as? [Any] {
            // Array
            if array.isEmpty {
                return "[]"
            }

            var result = "[\n"
            for (index, item) in array.enumerated() {
                let newPath = "\(path)[\(index)]"
                let serializedItem = try serializeValue(item, keyOrder: nil, nestedKeyOrders: nestedKeyOrders, indent: nextIndent, path: newPath)
                result += "\(nextIndentStr)\(serializedItem)"
                if index < array.count - 1 {
                    result += ","
                }
                result += "\n"
            }
            result += "\(indentStr)]"
            return result

        } else if let str = value as? String {
            // String
            return "\"\(escapeJSONString(str))\""
        } else if let num = value as? Int {
            // Integer
            return "\(num)"
        } else if let num = value as? Double {
            // Double
            return "\(num)"
        } else if let bool = value as? Bool {
            // Boolean
            return bool ? "true" : "false"
        } else if value is NSNull {
            // Null
            return "null"
        } else {
            throw SettingsError.serializationFailed("Unsupported value type: \(type(of: value))")
        }
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

    /// Extract nested key orders from JSON data
    /// Returns a dictionary mapping JSON paths to their key orders
    private func extractNestedKeyOrders(from data: Data) -> [String: [String]] {
        guard let jsonString = String(data: data, encoding: .utf8) else {
            return [:]
        }

        var result: [String: [String]] = [:]
        _ = extractKeysRecursive(from: jsonString, startIndex: jsonString.startIndex, path: "", result: &result)
        return result
    }

    /// Recursively extract key orders from JSON string
    private func extractKeysRecursive(from jsonString: String, startIndex: String.Index, path: String, result: inout [String: [String]]) -> String.Index {
        var currentIndex = startIndex
        let endIndex = jsonString.endIndex

        // Skip whitespace
        while currentIndex < endIndex && jsonString[currentIndex].isWhitespace {
            currentIndex = jsonString.index(after: currentIndex)
        }

        // Check if this is an object
        guard currentIndex < endIndex && jsonString[currentIndex] == "{" else {
            // Not an object, skip it
            return skipValue(in: jsonString, from: currentIndex)
        }

        currentIndex = jsonString.index(after: currentIndex) // Skip opening brace
        var keys: [String] = []

        while currentIndex < endIndex {
            // Skip whitespace
            while currentIndex < endIndex && jsonString[currentIndex].isWhitespace {
                currentIndex = jsonString.index(after: currentIndex)
            }

            // Check for closing brace
            if currentIndex < endIndex && jsonString[currentIndex] == "}" {
                currentIndex = jsonString.index(after: currentIndex)
                break
            }

            // Extract key
            if currentIndex < endIndex && jsonString[currentIndex] == "\"" {
                currentIndex = jsonString.index(after: currentIndex)
                var key = ""
                var escaped = false

                while currentIndex < endIndex {
                    let char = jsonString[currentIndex]

                    if escaped {
                        switch char {
                        case "\"": key.append("\"")
                        case "\\": key.append("\\")
                        case "n": key.append("\n")
                        case "r": key.append("\r")
                        case "t": key.append("\t")
                        default: key.append(char)
                        }
                        escaped = false
                    } else if char == "\\" {
                        escaped = true
                    } else if char == "\"" {
                        keys.append(key)
                        currentIndex = jsonString.index(after: currentIndex)
                        break
                    } else {
                        key.append(char)
                    }

                    currentIndex = jsonString.index(after: currentIndex)
                }

                // Skip whitespace and colon
                while currentIndex < endIndex && (jsonString[currentIndex].isWhitespace || jsonString[currentIndex] == ":") {
                    currentIndex = jsonString.index(after: currentIndex)
                }

                // Recursively process the value if it's an object
                let newPath = path.isEmpty ? key : "\(path).\(key)"
                currentIndex = extractKeysRecursive(from: jsonString, startIndex: currentIndex, path: newPath, result: &result)

                // Skip whitespace
                while currentIndex < endIndex && jsonString[currentIndex].isWhitespace {
                    currentIndex = jsonString.index(after: currentIndex)
                }

                // Skip comma if present
                if currentIndex < endIndex && jsonString[currentIndex] == "," {
                    currentIndex = jsonString.index(after: currentIndex)
                }
            } else {
                break
            }
        }

        if !keys.isEmpty {
            result[path] = keys
        }

        return currentIndex
    }

    /// Skip over a JSON value in the string
    private func skipValue(in jsonString: String, from startIndex: String.Index) -> String.Index {
        var currentIndex = startIndex
        let endIndex = jsonString.endIndex

        // Skip whitespace
        while currentIndex < endIndex && jsonString[currentIndex].isWhitespace {
            currentIndex = jsonString.index(after: currentIndex)
        }

        guard currentIndex < endIndex else { return currentIndex }

        let char = jsonString[currentIndex]

        if char == "{" {
            // Skip object
            var depth = 0
            repeat {
                if jsonString[currentIndex] == "{" {
                    depth += 1
                } else if jsonString[currentIndex] == "}" {
                    depth -= 1
                }
                currentIndex = jsonString.index(after: currentIndex)
            } while currentIndex < endIndex && depth > 0
        } else if char == "[" {
            // Skip array
            var depth = 0
            repeat {
                if jsonString[currentIndex] == "[" {
                    depth += 1
                } else if jsonString[currentIndex] == "]" {
                    depth -= 1
                }
                currentIndex = jsonString.index(after: currentIndex)
            } while currentIndex < endIndex && depth > 0
        } else if char == "\"" {
            // Skip string
            currentIndex = jsonString.index(after: currentIndex)
            var escaped = false
            while currentIndex < endIndex {
                if escaped {
                    escaped = false
                } else if jsonString[currentIndex] == "\\" {
                    escaped = true
                } else if jsonString[currentIndex] == "\"" {
                    currentIndex = jsonString.index(after: currentIndex)
                    break
                }
                currentIndex = jsonString.index(after: currentIndex)
            }
        } else {
            // Skip primitive (number, boolean, null)
            while currentIndex < endIndex && !",]}".contains(jsonString[currentIndex]) && !jsonString[currentIndex].isWhitespace {
                currentIndex = jsonString.index(after: currentIndex)
            }
        }

        return currentIndex
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

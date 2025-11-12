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
    public func writeSettingsFile(_ settingsFile: inout SettingsFile) async throws {
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

        // Validate that the serialized JSON is actually valid by parsing it
        do {
            _ = try JSONSerialization.jsonObject(with: jsonData, options: [])
            logger.debug("Successfully validated serialized JSON")
        } catch {
            logger.error("Generated invalid JSON: \(error.localizedDescription)")
            throw SettingsError.serializationFailed("Generated JSON failed validation: \(error.localizedDescription)")
        }

        try await fileSystemManager.writeFile(data: jsonData, to: settingsFile.path)

        // Update the original data to reflect what was just written
        settingsFile.originalData = jsonData
    }

    /// Serialize JSON with custom key ordering while preserving nested object key orders
    ///
    /// This method manually serializes a dictionary to JSON instead of using JSONSerialization
    /// because JSONSerialization doesn't preserve key ordering from the original file.
    ///
    /// - Parameters:
    ///   - content: The dictionary to serialize (native Swift types)
    ///   - keyOrder: The desired order of top-level keys
    ///   - nestedKeyOrders: Dictionary mapping JSON paths to their key orders (e.g., "" for top-level, "parent.child" for nested objects)
    /// - Returns: UTF-8 encoded JSON data with custom key ordering
    /// - Throws: `SettingsError.serializationFailed` if serialization fails or UTF-8 encoding fails
    ///
    /// - Note: The output is formatted with 2-space indentation and includes a trailing newline
    private func serializeJSON(content: [String: Any], keyOrder: [String], nestedKeyOrders: [String: [String]]) throws -> Data {
        let jsonString = try serializeValue(content, keyOrder: keyOrder, nestedKeyOrders: nestedKeyOrders, indent: 0, path: "")
        guard let data = (jsonString + "\n").data(using: .utf8) else {
            throw SettingsError.serializationFailed("Failed to encode JSON string to UTF-8")
        }
        return data
    }

    /// Recursively serialize a value with proper formatting and indentation
    ///
    /// Handles all JSON value types: objects, arrays, strings, numbers, booleans, and null.
    /// For objects, uses the specified key order from `nestedKeyOrders` or falls back to sorted keys.
    ///
    /// - Parameters:
    ///   - value: The value to serialize (must be a valid JSON type)
    ///   - keyOrder: Optional explicit key order for this object (only used for top-level object)
    ///   - nestedKeyOrders: Dictionary mapping JSON paths to their key orders for nested objects
    ///   - indent: Current indentation level (number of 2-space indents)
    ///   - path: Current JSON path (e.g., "" for root, "parent.child" for nested, "array[0]" for array elements)
    /// - Returns: Formatted JSON string for this value
    /// - Throws: `SettingsError.serializationFailed` if the value type is not supported
    ///
    /// - Note: Empty arrays serialize as `[]` on a single line, non-empty arrays span multiple lines
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
                // Preserve existing keys in original order, then append new keys (sorted) at end
                let storedKeys = Set(storedOrder)
                let existingKeysInOrder = storedOrder.filter { dict.keys.contains($0) }
                let newKeysInDict = dict.keys.filter { !storedKeys.contains($0) }.sorted()
                objectKeyOrder = existingKeysInOrder + newKeysInDict
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

    /// Escape a string for use in JSON per RFC 8259
    ///
    /// Handles all required escape sequences to produce valid JSON strings:
    /// - Special characters: `"` → `\"`, `\` → `\\`
    /// - Common escapes: `\n`, `\r`, `\t`, `\b` (backspace), `\f` (form feed)
    /// - Control characters (U+0000 to U+001F): Encoded as `\uXXXX` hex sequences
    ///
    /// - Parameter string: The raw string to escape
    /// - Returns: JSON-safe escaped string (without surrounding quotes)
    ///
    /// - Note: This only escapes the string content; the caller must add surrounding quotes
    ///
    /// Example:
    /// ```swift
    /// escapeJSONString("Hello \"World\"\nNew line") // Returns: Hello \"World\"\nNew line
    /// escapeJSONString("Control: \u{0001}") // Returns: Control: \u0001
    /// ```
    private func escapeJSONString(_ string: String) -> String {
        var escaped = ""
        for char in string {
            switch char {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            case "\u{08}": escaped += "\\b" // Backspace
            case "\u{0C}": escaped += "\\f" // Form feed
            default:
                // Escape control characters (U+0000 to U+001F) as \uXXXX
                if
                    char.unicodeScalars.count == 1,
                    let scalar = char.unicodeScalars.first,
                    scalar.value <= 0x1F {
                    escaped += String(format: "\\u%04x", scalar.value)
                } else {
                    escaped.append(char)
                }
            }
        }
        return escaped
    }

    /// Extract nested key orders from JSON data by parsing the raw JSON string
    ///
    /// Parses the JSON string manually to extract the order of keys at each nesting level,
    /// which cannot be obtained from JSONSerialization (it doesn't preserve order).
    ///
    /// - Parameter data: Raw JSON data to parse
    /// - Returns: Dictionary mapping JSON paths to their key orders
    ///   - Empty string "" maps to top-level keys
    ///   - Nested paths use dot notation: "parent.child.grandchild"
    ///   - Returns empty dictionary if data is not valid UTF-8
    ///
    /// Example output:
    /// ```
    /// [
    ///   "": ["third_key", "first_key", "second_key"],
    ///   "permissions": ["defaultMode", "allow", "deny"],
    ///   "permissions.advanced": ["timeout", "retries"]
    /// ]
    /// ```
    ///
    /// - Note: Only extracts order from objects; arrays are not tracked since their order is inherent
    private func extractNestedKeyOrders(from data: Data) -> [String: [String]] {
        guard let jsonString = String(data: data, encoding: .utf8) else {
            return [:]
        }

        var result: [String: [String]] = [:]
        _ = extractKeysRecursive(from: jsonString, startIndex: jsonString.startIndex, path: "", result: &result)
        return result
    }

    /// Recursively extract key orders from JSON string by manual parsing
    ///
    /// Walks through the JSON string character-by-character to extract object keys in the order they appear.
    /// Recursively processes nested objects and arrays to build a complete path-to-keys mapping.
    ///
    /// - Parameters:
    ///   - jsonString: The JSON string being parsed
    ///   - startIndex: Current position in the string to start parsing from
    ///   - path: Current JSON path (dot-separated for objects, bracket notation for arrays, "" for root)
    ///   - result: Mutable dictionary to accumulate path → keys mappings
    /// - Returns: String index where parsing stopped (after processing this value)
    ///
    /// Algorithm:
    /// 1. Skip whitespace and determine value type
    /// 2. For arrays: iterate through elements, recursively processing each with path `parent[index]`
    /// 3. For objects: extract each key string (handling escape sequences), recursively process nested values
    /// 4. For primitives: skip the value
    /// 5. Store the list of keys for object paths in `result`
    ///
    /// - Note: Handles all JSON string escape sequences including `\uXXXX` Unicode escapes
    private func extractKeysRecursive(from jsonString: String, startIndex: String.Index, path: String, result: inout [String: [String]]) -> String.Index {
        var currentIndex = startIndex
        let endIndex = jsonString.endIndex

        // Skip whitespace
        while currentIndex < endIndex && jsonString[currentIndex].isWhitespace {
            currentIndex = jsonString.index(after: currentIndex)
        }

        guard currentIndex < endIndex else { return currentIndex }

        // Check if this is an array - process elements to extract keys from nested objects
        if jsonString[currentIndex] == "[" {
            currentIndex = jsonString.index(after: currentIndex) // Skip opening bracket
            var elementIndex = 0

            while currentIndex < endIndex {
                // Skip whitespace
                while currentIndex < endIndex && jsonString[currentIndex].isWhitespace {
                    currentIndex = jsonString.index(after: currentIndex)
                }

                // Check for closing bracket
                if currentIndex < endIndex && jsonString[currentIndex] == "]" {
                    currentIndex = jsonString.index(after: currentIndex)
                    break
                }

                // Recursively process array element (may be object, array, or primitive)
                let elementPath = "\(path)[\(elementIndex)]"
                currentIndex = extractKeysRecursive(from: jsonString, startIndex: currentIndex, path: elementPath, result: &result)
                elementIndex += 1

                // Skip whitespace
                while currentIndex < endIndex && jsonString[currentIndex].isWhitespace {
                    currentIndex = jsonString.index(after: currentIndex)
                }

                // Skip comma if present
                if currentIndex < endIndex && jsonString[currentIndex] == "," {
                    currentIndex = jsonString.index(after: currentIndex)
                }
            }

            return currentIndex
        }

        // Check if this is an object
        guard jsonString[currentIndex] == "{" else {
            // Not an object or array, skip it
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
                        case "/": key.append("/")
                        case "n": key.append("\n")
                        case "r": key.append("\r")
                        case "t": key.append("\t")
                        case "b": key.append("\u{08}") // Backspace
                        case "f": key.append("\u{0C}") // Form feed
                        case "u":
                            // Handle Unicode escape sequence \uXXXX
                            currentIndex = jsonString.index(after: currentIndex)
                            var hexString = ""
                            for _ in 0..<4 {
                                guard currentIndex < endIndex else { break }
                                hexString.append(jsonString[currentIndex])
                                currentIndex = jsonString.index(after: currentIndex)
                            }
                            if
                                let codePoint = UInt32(hexString, radix: 16),
                                let scalar = Unicode.Scalar(codePoint) {
                                key.append(String(Character(scalar)))
                            }
                            currentIndex = jsonString.index(before: currentIndex)
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

    /// Skip over a JSON value in the string without parsing its contents
    ///
    /// Used by `extractKeysRecursive` to efficiently skip over values we don't need to parse.
    /// Handles all JSON value types by tracking nesting depth (for objects/arrays) or
    /// escape sequences (for strings).
    ///
    /// - Parameters:
    ///   - jsonString: The JSON string being parsed
    ///   - startIndex: Position where the value starts
    /// - Returns: String index immediately after the value ends
    ///
    /// Handling by type:
    /// - **Objects**: Track `{` and `}` depth until fully closed
    /// - **Arrays**: Track `[` and `]` depth until fully closed
    /// - **Strings**: Skip until unescaped closing quote, tracking backslash escapes
    /// - **Primitives**: Skip until delimiter (`,`, `]`, `}`) or whitespace
    ///
    /// - Note: Does not validate JSON correctness; assumes well-formed input
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
    ///
    /// Note: Deprecation checking is handled at the UI level via DocumentationLoader.
    /// This validation focuses on structural/syntactic correctness.
    private func validateKnownSettings(_ content: [String: SettingValue]) -> [ValidationError] {
        var errors: [ValidationError] = []

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

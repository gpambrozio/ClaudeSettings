import Foundation
import Testing
@testable import ClaudeSettingsFeature

/// Tests for SettingsParser key ordering and JSON serialization
@Suite("Settings Parser Tests")
struct SettingsParserTests {
    /// Helper function to extract top-level key order from JSON data
    /// Parses the JSON string to preserve the actual order of keys as written
    private func extractTopLevelKeyOrder(from jsonData: Data) throws -> [String] {
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw NSError(domain: "SettingsParserTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert data to string"])
        }

        var keys: [String] = []
        var currentIndex = jsonString.startIndex
        let endIndex = jsonString.endIndex

        // Skip to opening brace
        while currentIndex < endIndex && jsonString[currentIndex] != "{" {
            currentIndex = jsonString.index(after: currentIndex)
        }

        guard currentIndex < endIndex else { return keys }
        currentIndex = jsonString.index(after: currentIndex) // Skip '{'

        while currentIndex < endIndex {
            // Skip whitespace
            while currentIndex < endIndex && jsonString[currentIndex].isWhitespace {
                currentIndex = jsonString.index(after: currentIndex)
            }

            // Check for closing brace
            if currentIndex < endIndex && jsonString[currentIndex] == "}" {
                break
            }

            // Extract key
            if currentIndex < endIndex && jsonString[currentIndex] == "\"" {
                currentIndex = jsonString.index(after: currentIndex)
                var key = ""

                while currentIndex < endIndex && jsonString[currentIndex] != "\"" {
                    if jsonString[currentIndex] == "\\" {
                        currentIndex = jsonString.index(after: currentIndex)
                        if currentIndex < endIndex {
                            key.append(jsonString[currentIndex])
                        }
                    } else {
                        key.append(jsonString[currentIndex])
                    }
                    currentIndex = jsonString.index(after: currentIndex)
                }

                keys.append(key)
                currentIndex = jsonString.index(after: currentIndex) // Skip closing quote

                // Skip to comma or closing brace
                while currentIndex < endIndex && jsonString[currentIndex] != "," && jsonString[currentIndex] != "}" {
                    currentIndex = jsonString.index(after: currentIndex)
                }

                if currentIndex < endIndex && jsonString[currentIndex] == "," {
                    currentIndex = jsonString.index(after: currentIndex)
                }
            } else {
                break
            }
        }

        return keys
    }

    /// Test that original key order is preserved when reading and writing
    @Test("Preserves original key order")
    func preservesOriginalKeyOrder() async throws {
        // Given: A settings file with keys in a specific order
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-order-\(UUID().uuidString).json")

        let originalJSON = """
        {
          "third_key": "value3",
          "first_key": "value1",
          "second_key": "value2"
        }
        """

        try originalJSON.write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let fileSystemManager = FileSystemManager()
        let parser = SettingsParser(fileSystemManager: fileSystemManager)

        // When: Reading and immediately writing back the file
        var settingsFile = try await parser.parseSettingsFile(at: testFile, type: .globalSettings)
        try await parser.writeSettingsFile(&settingsFile)

        // Then: The written JSON should have the same key order
        let writtenData = try Data(contentsOf: testFile)
        let keyOrder = try extractTopLevelKeyOrder(from: writtenData)

        #expect(
            keyOrder == ["third_key", "first_key", "second_key"],
            "Original key order should be preserved"
        )
    }

    /// Test that new keys are added at the top in alphabetical order
    @Test("New keys appear at top in alphabetical order")
    func newKeysAtTop() async throws {
        // Given: An existing settings file
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-new-keys-\(UUID().uuidString).json")

        let originalJSON = """
        {
          "existing_key_2": "value2",
          "existing_key_1": "value1"
        }
        """

        try originalJSON.write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let fileSystemManager = FileSystemManager()
        let parser = SettingsParser(fileSystemManager: fileSystemManager)

        // When: Adding new keys
        var settingsFile = try await parser.parseSettingsFile(at: testFile, type: .globalSettings)
        settingsFile.content["zebra_key"] = .string("new1")
        settingsFile.content["apple_key"] = .string("new2")
        settingsFile.content["middle_key"] = .string("new3")

        try await parser.writeSettingsFile(&settingsFile)

        // Then: New keys should be at the top, sorted alphabetically
        let writtenData = try Data(contentsOf: testFile)
        let keyOrder = try extractTopLevelKeyOrder(from: writtenData)

        #expect(
            keyOrder == ["apple_key", "middle_key", "zebra_key", "existing_key_2", "existing_key_1"],
            "New keys should be at top (sorted), then original keys in original order"
        )
    }

    /// Test that special characters in keys are properly escaped
    @Test("Escapes special characters in keys")
    func escapesSpecialCharactersInKeys() async throws {
        // Given: Keys with special characters that need escaping
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-escape-keys-\(UUID().uuidString).json")

        let fileSystemManager = FileSystemManager()
        let parser = SettingsParser(fileSystemManager: fileSystemManager)

        // Create a file with tricky key names
        var settingsFile = SettingsFile(
            type: .globalSettings,
            path: testFile,
            content: [
                "normal_key": .string("normal"),
                "key\"with\"quotes": .string("quoted"),
                "key\\with\\backslashes": .string("backslashed"),
                "key\nwith\nnewlines": .string("newlined"),
                "key\twith\ttabs": .string("tabbed"),
            ]
        )

        defer { try? FileManager.default.removeItem(at: testFile) }

        // When: Writing the file
        try await parser.writeSettingsFile(&settingsFile)

        // Then: The file should contain valid JSON
        let writtenData = try Data(contentsOf: testFile)
        let parsedJSON = try JSONSerialization.jsonObject(with: writtenData) as? [String: Any]

        #expect(parsedJSON != nil, "Should produce valid JSON")
        #expect(parsedJSON?["normal_key"] as? String == "normal")
        #expect(parsedJSON?["key\"with\"quotes"] as? String == "quoted")
        #expect(parsedJSON?["key\\with\\backslashes"] as? String == "backslashed")
        #expect(parsedJSON?["key\nwith\nnewlines"] as? String == "newlined")
        #expect(parsedJSON?["key\twith\ttabs"] as? String == "tabbed")
    }

    /// Test that special characters in values are properly escaped
    @Test("Escapes special characters in values")
    func escapesSpecialCharactersInValues() async throws {
        // Given: Values with special characters
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-escape-values-\(UUID().uuidString).json")

        let fileSystemManager = FileSystemManager()
        let parser = SettingsParser(fileSystemManager: fileSystemManager)

        var settingsFile = SettingsFile(
            type: .globalSettings,
            path: testFile,
            content: [
                "string_with_quotes": .string("He said \"Hello World\""),
                "string_with_backslashes": .string("C:\\Users\\Documents\\file.txt"),
                "string_with_newlines": .string("Line 1\nLine 2\nLine 3"),
                "string_with_tabs": .string("Column1\tColumn2\tColumn3"),
                "string_with_mixed": .string("Path: \"C:\\test\\file.txt\"\nStatus: OK"),
                "string_with_unicode": .string("Emoji: 🎉 Unicode: αβγ"),
                "string_with_control_chars": .string("Before\rAfter"),
            ]
        )

        defer { try? FileManager.default.removeItem(at: testFile) }

        // When: Writing the file
        try await parser.writeSettingsFile(&settingsFile)

        // Then: The file should contain valid JSON with properly escaped values
        let writtenData = try Data(contentsOf: testFile)
        let parsedJSON = try JSONSerialization.jsonObject(with: writtenData) as? [String: Any]

        #expect(parsedJSON != nil, "Should produce valid JSON")
        #expect(parsedJSON?["string_with_quotes"] as? String == "He said \"Hello World\"")
        #expect(parsedJSON?["string_with_backslashes"] as? String == "C:\\Users\\Documents\\file.txt")
        #expect(parsedJSON?["string_with_newlines"] as? String == "Line 1\nLine 2\nLine 3")
        #expect(parsedJSON?["string_with_tabs"] as? String == "Column1\tColumn2\tColumn3")
        #expect(parsedJSON?["string_with_mixed"] as? String == "Path: \"C:\\test\\file.txt\"\nStatus: OK")
        #expect(parsedJSON?["string_with_unicode"] as? String == "Emoji: 🎉 Unicode: αβγ")
        #expect(parsedJSON?["string_with_control_chars"] as? String == "Before\rAfter")
    }

    /// Test complex nested structures with special characters
    @Test("Handles complex nested structures with special characters")
    func handlesComplexNestedStructures() async throws {
        // Given: A complex settings structure with nested objects and arrays
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-complex-\(UUID().uuidString).json")

        let fileSystemManager = FileSystemManager()
        let parser = SettingsParser(fileSystemManager: fileSystemManager)

        var settingsFile = SettingsFile(
            type: .globalSettings,
            path: testFile,
            content: [
                "hooks": .object([
                    "pre-commit": .string("#!/bin/bash\necho \"Running\"\n"),
                    "post-commit": .string("notify-send \"Done!\""),
                ]),
                "paths": .array([
                    .string("/usr/local/bin"),
                    .string("C:\\Program Files\\App"),
                    .string("/path/with \"quotes\""),
                    .string("/path/with\ttabs"),
                ]),
                "config": .object([
                    "name": .string("My \"Special\" Config"),
                    "enabled": .bool(true),
                    "count": .int(42),
                    "ratio": .double(3.14),
                    "nested": .object([
                        "deep": .string("value\\with\\backslashes"),
                    ]),
                ]),
            ]
        )

        defer { try? FileManager.default.removeItem(at: testFile) }

        // When: Writing and reading back
        try await parser.writeSettingsFile(&settingsFile)
        let readBack = try await parser.parseSettingsFile(at: testFile, type: .globalSettings)

        // Then: The structure should be preserved correctly
        #expect(readBack.content.count == 3, "Should have 3 top-level keys")

        // Verify hooks
        if case let .object(hooks) = readBack.content["hooks"] {
            if case let .string(preCommit) = hooks["pre-commit"] {
                #expect(preCommit == "#!/bin/bash\necho \"Running\"\n")
            } else {
                Issue.record("pre-commit should be a string")
            }
        } else {
            Issue.record("hooks should be an object")
        }

        // Verify paths array
        if case let .array(paths) = readBack.content["paths"] {
            #expect(paths.count == 4, "Should have 4 paths")
            if case let .string(path2) = paths[1] {
                #expect(path2 == "C:\\Program Files\\App")
            }
            if case let .string(path3) = paths[2] {
                #expect(path3 == "/path/with \"quotes\"")
            }
        } else {
            Issue.record("paths should be an array")
        }

        // Verify config object
        if case let .object(config) = readBack.content["config"] {
            if case let .string(name) = config["name"] {
                #expect(name == "My \"Special\" Config")
            }
            if case let .object(nested) = config["nested"] {
                if case let .string(deep) = nested["deep"] {
                    #expect(deep == "value\\with\\backslashes")
                }
            }
        } else {
            Issue.record("config should be an object")
        }
    }

    /// Test that deleted keys don't appear in output
    @Test("Deleted keys don't appear in output")
    func deletedKeysRemovedFromOutput() async throws {
        // Given: A settings file
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-delete-\(UUID().uuidString).json")

        let originalJSON = """
        {
          "keep_this": "value1",
          "delete_this": "value2",
          "also_keep": "value3"
        }
        """

        try originalJSON.write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let fileSystemManager = FileSystemManager()
        let parser = SettingsParser(fileSystemManager: fileSystemManager)

        // When: Removing a key
        var settingsFile = try await parser.parseSettingsFile(at: testFile, type: .globalSettings)
        settingsFile.content.removeValue(forKey: "delete_this")

        try await parser.writeSettingsFile(&settingsFile)

        // Then: The written JSON should not contain the deleted key
        let writtenData = try Data(contentsOf: testFile)
        let parsedJSON = try JSONSerialization.jsonObject(with: writtenData) as? [String: Any]

        #expect(parsedJSON?["delete_this"] == nil, "Deleted key should not be in JSON")
        #expect(parsedJSON?["keep_this"] != nil, "Kept key should be in JSON")
        #expect(parsedJSON?["also_keep"] != nil, "Kept key should be in JSON")
    }

    /// Test round-trip: read → modify → write → read
    @Test("Round-trip preserves data integrity")
    func roundTripPreservesDataIntegrity() async throws {
        // Given: A complex settings file
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-roundtrip-\(UUID().uuidString).json")

        let originalJSON = """
        {
          "project_name": "MyApp",
          "version": "1.0.0",
          "settings": {
            "debug": true,
            "timeout": 30
          }
        }
        """

        try originalJSON.write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let fileSystemManager = FileSystemManager()
        let parser = SettingsParser(fileSystemManager: fileSystemManager)

        // When: Reading, modifying, writing, and reading again
        let first = try await parser.parseSettingsFile(at: testFile, type: .globalSettings)
        var modified = first
        modified.content["new_setting"] = .string("test \"value\" with\\escapes")

        try await parser.writeSettingsFile(&modified)
        let second = try await parser.parseSettingsFile(at: testFile, type: .globalSettings)

        // Then: All data should be preserved
        #expect(second.content.count == 4, "Should have 4 keys after adding one")

        if case let .string(name) = second.content["project_name"] {
            #expect(name == "MyApp")
        } else {
            Issue.record("project_name should be preserved")
        }

        if case let .string(newValue) = second.content["new_setting"] {
            #expect(newValue == "test \"value\" with\\escapes")
        } else {
            Issue.record("new_setting should have escaped characters")
        }
    }

    /// Test that nested object key order is preserved
    @Test("Preserves nested object key order")
    func preservesNestedObjectKeyOrder() async throws {
        // Given: A settings file with nested objects in specific order
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-nested-order-\(UUID().uuidString).json")

        let originalJSON = """
        {
          "permissions": {
            "defaultMode": "acceptEdits",
            "allow": [
              "Bash(git:*)"
            ],
            "deny": []
          },
          "enabledPlugins": {
            "PluginZ": false,
            "PluginA": true,
            "PluginM": true
          }
        }
        """

        try originalJSON.write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let fileSystemManager = FileSystemManager()
        let parser = SettingsParser(fileSystemManager: fileSystemManager)

        // When: Reading and writing back the file
        var settingsFile = try await parser.parseSettingsFile(at: testFile, type: .globalSettings)
        try await parser.writeSettingsFile(&settingsFile)

        // Then: The written JSON should preserve nested key order
        let writtenJSON = try String(contentsOf: testFile, encoding: .utf8)
        let lines = writtenJSON.split(separator: "\n").map(String.init)

        // Check permissions object key order
        let defaultModeLine = lines.firstIndex { $0.contains("\"defaultMode\"") }
        let allowLine = lines.firstIndex { $0.contains("\"allow\"") }
        let denyLine = lines.firstIndex { $0.contains("\"deny\"") }

        #expect(
            defaultModeLine != nil && allowLine != nil && denyLine != nil,
            "All nested keys should be present"
        )
        #expect(defaultModeLine! < allowLine!, "defaultMode should come before allow")
        #expect(allowLine! < denyLine!, "allow should come before deny")

        // Check enabledPlugins object key order
        let pluginZLine = lines.firstIndex { $0.contains("\"PluginZ\"") }
        let pluginALine = lines.firstIndex { $0.contains("\"PluginA\"") }
        let pluginMLine = lines.firstIndex { $0.contains("\"PluginM\"") }

        #expect(
            pluginZLine != nil && pluginALine != nil && pluginMLine != nil,
            "All plugin keys should be present"
        )
        #expect(pluginZLine! < pluginALine!, "PluginZ should come before PluginA")
        #expect(pluginALine! < pluginMLine!, "PluginA should come before PluginM")

        // Verify no extra spaces before colons
        for line in lines where line.contains(":") {
            #expect(!line.contains("\" :"), "Should not have space before colon")
        }
    }

    /// Test that JSON output is properly formatted with indentation
    @Test("JSON output is properly formatted")
    func jsonOutputIsProperlyFormatted() async throws {
        // Given: A settings file with nested structure
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-format-\(UUID().uuidString).json")

        let fileSystemManager = FileSystemManager()
        let parser = SettingsParser(fileSystemManager: fileSystemManager)

        var settingsFile = SettingsFile(
            type: .globalSettings,
            path: testFile,
            content: [
                "simple": .string("value"),
                "nested": .object([
                    "child": .string("value"),
                    "number": .int(42),
                ]),
            ]
        )

        defer { try? FileManager.default.removeItem(at: testFile) }

        // When: Writing the file
        try await parser.writeSettingsFile(&settingsFile)

        // Then: The output should be properly indented
        let writtenJSON = try String(contentsOf: testFile, encoding: .utf8)

        #expect(writtenJSON.contains("{\n"), "Should start with opening brace and newline")
        #expect(writtenJSON.hasSuffix("}\n"), "Should end with closing brace and newline")
        #expect(writtenJSON.contains("  \"simple\":"), "Top-level keys should be indented with 2 spaces")
        #expect(writtenJSON.contains("  \"nested\":"), "Top-level keys should be indented")

        // Verify it's valid JSON
        let data = try Data(contentsOf: testFile)
        let parsed = try JSONSerialization.jsonObject(with: data)
        #expect(parsed is [String: Any], "Should be valid JSON object")
    }

    /// Test handling of deeply nested structures (15+ levels)
    @Test("Handles deeply nested structures")
    func handlesDeeplyNestedStructures() async throws {
        // Given: A deeply nested settings structure
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-deep-nesting-\(UUID().uuidString).json")

        let fileSystemManager = FileSystemManager()
        let parser = SettingsParser(fileSystemManager: fileSystemManager)

        // Create a deeply nested structure programmatically
        func createNestedObject(depth: Int, currentDepth: Int = 0) -> SettingValue {
            if currentDepth >= depth {
                return .string("leaf-value-at-depth-\(currentDepth)")
            }
            return .object([
                "level_\(currentDepth)_key_z": .string("value-z"),
                "level_\(currentDepth)_key_a": .string("value-a"),
                "nested": createNestedObject(depth: depth, currentDepth: currentDepth + 1),
                "level_\(currentDepth)_key_m": .int(currentDepth),
            ])
        }

        var settingsFile = SettingsFile(
            type: .globalSettings,
            path: testFile,
            content: [
                "root_key_1": createNestedObject(depth: 15),
                "root_key_2": .string("simple-value"),
                "root_key_3": .array([
                    .object(["deep": createNestedObject(depth: 10)]),
                    .string("array-item"),
                ]),
            ]
        )

        defer { try? FileManager.default.removeItem(at: testFile) }

        // When: Writing and reading back the deeply nested structure
        try await parser.writeSettingsFile(&settingsFile)
        let readBack = try await parser.parseSettingsFile(at: testFile, type: .globalSettings)

        // Then: The structure should be preserved correctly
        #expect(readBack.content.count == 3, "Should have 3 top-level keys")
        #expect(readBack.isValid, "Should be valid JSON")

        // Verify we can traverse to the deepest level
        func verifyNestedDepth(_ value: SettingValue, expectedDepth: Int, currentDepth: Int = 0) -> Bool {
            if currentDepth >= expectedDepth {
                if case let .string(str) = value {
                    return str == "leaf-value-at-depth-\(expectedDepth)"
                }
                return false
            }

            if case let .object(dict) = value {
                if let nested = dict["nested"] {
                    return verifyNestedDepth(nested, expectedDepth: expectedDepth, currentDepth: currentDepth + 1)
                }
            }

            return false
        }

        if case let .object(rootObj) = readBack.content["root_key_1"] {
            if let nested = rootObj["nested"] {
                #expect(verifyNestedDepth(nested, expectedDepth: 15, currentDepth: 1), "Should preserve 15 levels of nesting")
            } else {
                Issue.record("Missing nested key in deep structure")
            }
        } else {
            Issue.record("root_key_1 should be an object")
        }

        // Verify the written JSON is actually valid
        let writtenData = try Data(contentsOf: testFile)
        let validatedJSON = try JSONSerialization.jsonObject(with: writtenData)
        #expect(validatedJSON is [String: Any], "Deep structure should produce valid JSON")
    }
}

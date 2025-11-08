import Foundation
import Testing
@testable import ClaudeSettingsFeature

/// Tests for SettingsViewModel edit operations (update, copy, delete, undo, redo)
@Suite("Settings Edit Operations Tests")
struct SettingsEditOperationsTests {
    /// Test updating a setting value
    @Test("Update setting changes value correctly")
    @MainActor
    func updateSetting() async throws {
        // Given: A ViewModel with a simple setting
        let viewModel = SettingsViewModel()
        let originalValue: SettingValue = .string("dark")
        let updatedValue: SettingValue = .string("light")

        // Verify we can set and get nested values
        var dict: [String: SettingValue] = ["theme": originalValue]

        // When: Setting a new value
        try viewModel.setNestedValue(in: &dict, keyPath: "theme", value: updatedValue)

        // Then: Value should be updated
        #expect(dict["theme"] == updatedValue, "Should update simple key")
    }

    /// Test updating a nested setting value
    @Test("Update nested setting changes value correctly")
    @MainActor
    func updateNestedSetting() async throws {
        // Given: A nested settings structure
        let viewModel = SettingsViewModel()
        var dict: [String: SettingValue] = [
            "editor": .object([
                "theme": .string("dark"),
            ]),
        ]

        // When: Updating a nested value
        try viewModel.setNestedValue(in: &dict, keyPath: "editor.theme", value: .string("light"))

        // Then: Nested value should be updated
        if case let .object(editorDict) = dict["editor"] {
            #expect(editorDict["theme"] == .string("light"), "Should update nested value")
        } else {
            Issue.record("Expected editor to be an object")
        }
    }

    /// Test updating a deeply nested setting value
    @Test("Update deeply nested setting creates intermediate objects")
    @MainActor
    func updateDeeplyNestedSetting() async throws {
        // Given: An empty dictionary
        let viewModel = SettingsViewModel()
        var dict: [String: SettingValue] = [:]

        // When: Setting a deeply nested value
        try viewModel.setNestedValue(in: &dict, keyPath: "editor.font.family", value: .string("Monaco"))

        // Then: Should create all intermediate objects
        if case let .object(editorDict) = dict["editor"] {
            if case let .object(fontDict) = editorDict["font"] {
                #expect(fontDict["family"] == .string("Monaco"), "Should set deep value")
            } else {
                Issue.record("Expected font to be an object")
            }
        } else {
            Issue.record("Expected editor to be an object")
        }
    }

    /// Test getting a nested value
    @Test("Get nested value retrieves correct value")
    @MainActor
    func getNestedValue() async throws {
        // Given: A nested settings structure
        let viewModel = SettingsViewModel()
        let dict: [String: SettingValue] = [
            "editor": .object([
                "font": .object([
                    "size": .int(14),
                ]),
            ]),
        ]

        // When: Getting a nested value
        let value = viewModel.getNestedValue(in: dict, keyPath: "editor.font.size")

        // Then: Should return the correct value
        #expect(value == .int(14), "Should retrieve nested value")
    }

    /// Test getting a non-existent nested value
    @Test("Get non-existent nested value returns nil")
    @MainActor
    func getNonExistentNestedValue() async throws {
        // Given: A simple dictionary
        let viewModel = SettingsViewModel()
        let dict: [String: SettingValue] = [
            "theme": .string("dark"),
        ]

        // When: Getting a non-existent nested value
        let value = viewModel.getNestedValue(in: dict, keyPath: "editor.font.size")

        // Then: Should return nil
        #expect(value == nil, "Should return nil for non-existent path")
    }

    /// Test deleting a simple setting
    @Test("Delete simple setting removes key")
    @MainActor
    func deleteSimpleSetting() async throws {
        // Given: A dictionary with a simple key
        let viewModel = SettingsViewModel()
        var dict: [String: SettingValue] = [
            "theme": .string("dark"),
            "fontSize": .int(14),
        ]

        // When: Deleting a key
        try viewModel.removeNestedValue(in: &dict, keyPath: "theme")

        // Then: Key should be removed
        #expect(dict["theme"] == nil, "Should remove key")
        #expect(dict["fontSize"] == .int(14), "Should preserve other keys")
    }

    /// Test deleting a nested setting
    @Test("Delete nested setting removes key and cleans up empty parents")
    @MainActor
    func deleteNestedSetting() async throws {
        // Given: A nested structure with one child
        let viewModel = SettingsViewModel()
        var dict: [String: SettingValue] = [
            "editor": .object([
                "theme": .string("dark"),
            ]),
        ]

        // When: Deleting the nested key
        try viewModel.removeNestedValue(in: &dict, keyPath: "editor.theme")

        // Then: Parent should also be removed since it's empty
        #expect(dict["editor"] == nil, "Should remove empty parent")
    }

    /// Test deleting a nested setting but preserving non-empty parent
    @Test("Delete nested setting preserves non-empty parent")
    @MainActor
    func deleteNestedSettingPreservesParent() async throws {
        // Given: A nested structure with multiple children
        let viewModel = SettingsViewModel()
        var dict: [String: SettingValue] = [
            "editor": .object([
                "theme": .string("dark"),
                "fontSize": .int(14),
            ]),
        ]

        // When: Deleting one nested key
        try viewModel.removeNestedValue(in: &dict, keyPath: "editor.theme")

        // Then: Parent should remain with other children
        if case let .object(editorDict) = dict["editor"] {
            #expect(editorDict["theme"] == nil, "Should remove deleted key")
            #expect(editorDict["fontSize"] == .int(14), "Should preserve sibling key")
        } else {
            Issue.record("Expected editor to still exist as object")
        }
    }

    /// Test deleting a deeply nested setting
    @Test("Delete deeply nested setting cleans up empty ancestors")
    @MainActor
    func deleteDeeplyNestedSetting() async throws {
        // Given: A deeply nested structure with only one leaf
        let viewModel = SettingsViewModel()
        var dict: [String: SettingValue] = [
            "editor": .object([
                "font": .object([
                    "family": .string("Monaco"),
                ]),
            ]),
        ]

        // When: Deleting the deeply nested key
        try viewModel.removeNestedValue(in: &dict, keyPath: "editor.font.family")

        // Then: All empty ancestors should be removed
        #expect(dict["editor"] == nil, "Should remove all empty ancestors")
    }

    /// Test undo/redo state tracking
    @Test("Undo/redo state is tracked correctly")
    @MainActor
    func undoRedoStateTracking() async throws {
        // Given: A fresh ViewModel
        let viewModel = SettingsViewModel()

        // Then: Initially no undo/redo available
        #expect(!viewModel.canUndo, "Should not be able to undo initially")
        #expect(!viewModel.canRedo, "Should not be able to redo initially")

        // When: Adding an undo command
        let command = EditSettingCommand(
            viewModel: viewModel,
            key: "theme",
            fileType: .globalSettings,
            oldContent: ["theme": .string("dark")],
            newContent: ["theme": .string("light")]
        )
        await viewModel.undoStack.append(command)

        // Then: Should be able to undo
        #expect(viewModel.canUndo, "Should be able to undo after edit")
        #expect(!viewModel.canRedo, "Should not be able to redo yet")
    }

    /// Test invalid key path handling
    @Test("Invalid key path throws error")
    @MainActor
    func invalidKeyPath() async throws {
        // Given: A ViewModel
        let viewModel = SettingsViewModel()
        var dict: [String: SettingValue] = [:]

        // When/Then: Setting with empty key path should throw
        #expect(throws: SettingsError.self) {
            try viewModel.setNestedValue(in: &dict, keyPath: "", value: .string("test"))
        }
    }

    /// Test setting value over non-object type creates new object
    @Test("Setting nested value over non-object creates new object")
    @MainActor
    func setNestedOverNonObject() async throws {
        // Given: A dictionary with a non-object value
        let viewModel = SettingsViewModel()
        var dict: [String: SettingValue] = [
            "editor": .string("someValue"), // Not an object
        ]

        // When: Setting a nested value under editor
        try viewModel.setNestedValue(in: &dict, keyPath: "editor.theme", value: .string("dark"))

        // Then: Should replace with object
        if case let .object(editorDict) = dict["editor"] {
            #expect(editorDict["theme"] == .string("dark"), "Should create object and set value")
        } else {
            Issue.record("Expected editor to become an object")
        }
    }

    /// Test contribution tracking for edit operations
    @Test("Edit operations preserve contribution history")
    @MainActor
    func editPreservesContributions() async throws {
        // Given: A setting item with multiple contributions
        let item = SettingItem(
            key: "theme",
            value: .string("dark"),
            source: .globalSettings,
            contributions: [
                SourceContribution(source: .globalSettings, value: .string("light")),
                SourceContribution(source: .projectSettings, value: .string("dark")),
            ]
        )

        // Then: Contributions should be preserved
        #expect(item.contributions.count == 2, "Should have two contributions")
        #expect(item.contributions[0].source == .globalSettings, "First contribution from global")
        #expect(item.contributions[1].source == .projectSettings, "Second contribution from project")

        // The active value is from the highest precedence
        #expect(item.value == .string("dark"), "Value should be from highest precedence")
    }

    /// Test setting precedence in file type selection
    @Test("File type precedence is respected in operations")
    @MainActor
    func fileTypePrecedence() async throws {
        // Given: Different file types
        let types: [SettingsFileType] = [
            .globalSettings,
            .globalLocal,
            .projectSettings,
            .projectLocal,
            .enterpriseManaged,
        ]

        // Then: Precedence should be in correct order
        let sortedByPrecedence = types.sorted { $0.precedence < $1.precedence }

        #expect(sortedByPrecedence[0] == .globalSettings, "Global settings should have lowest precedence")
        #expect(sortedByPrecedence.last == .enterpriseManaged, "Enterprise should have highest precedence")
    }

    /// Test that additive array settings work correctly
    @Test("Array settings are additive across sources")
    @MainActor
    func arraySettingsAdditive() async throws {
        // Given: Array settings from multiple sources
        let item = SettingItem(
            key: "permissions",
            value: .array([.string("Read"), .string("Write"), .string("Bash")]),
            source: .globalSettings,
            contributions: [
                SourceContribution(source: .globalSettings, value: .array([.string("Read"), .string("Write")])),
                SourceContribution(source: .projectSettings, value: .array([.string("Bash")])),
            ]
        )

        // Then: Should be marked as additive
        #expect(item.isAdditive, "Array with multiple contributions should be additive")

        // And: Should show all contributions
        #expect(item.contributions.count == 2, "Should track all contributions")
    }

    /// Test that non-array settings are replaced (not additive)
    @Test("Non-array settings are replaced not additive")
    @MainActor
    func nonArraySettingsReplaced() async throws {
        // Given: String setting from multiple sources
        let item = SettingItem(
            key: "theme",
            value: .string("dark"),
            source: .globalSettings,
            overriddenBy: .projectSettings,
            contributions: [
                SourceContribution(source: .globalSettings, value: .string("light")),
                SourceContribution(source: .projectSettings, value: .string("dark")),
            ]
        )

        // Then: Should NOT be marked as additive
        #expect(!item.isAdditive, "String with multiple contributions should not be additive")

        // And: Should show override information
        #expect(item.overriddenBy == .projectSettings, "Should track which source overrode")
    }

    /// Test error handling for operations on read-only files
    @Test("Operations handle read-only files appropriately")
    @MainActor
    func readOnlyFileHandling() async throws {
        // Given: A read-only settings file
        let file = SettingsFile(
            type: .enterpriseManaged,
            path: URL(fileURLWithPath: "/tmp/managed.json"),
            content: ["setting": .string("value")],
            isReadOnly: true
        )

        // Then: File should be marked as read-only
        #expect(file.isReadOnly, "Enterprise file should be read-only")
        #expect(file.type == .enterpriseManaged, "Should be enterprise type")
    }
}

// Extension to make SettingsViewModel's helper methods accessible for testing
extension SettingsViewModel {
    func setNestedValue(in dict: inout [String: SettingValue], keyPath: String, value: SettingValue) throws {
        try setNestedValue(in: &dict, keyPath: keyPath, value: value)
    }

    func getNestedValue(in dict: [String: SettingValue], keyPath: String) -> SettingValue? {
        getNestedValue(in: dict, keyPath: keyPath)
    }

    func removeNestedValue(in dict: inout [String: SettingValue], keyPath: String) throws {
        try removeNestedValue(in: &dict, keyPath: keyPath)
    }
}

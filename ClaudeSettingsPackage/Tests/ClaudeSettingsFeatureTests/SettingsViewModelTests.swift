import Foundation
import Testing
@testable import ClaudeSettingsFeature

/// Tests for SettingsViewModel settings hierarchy and precedence resolution
@Suite("SettingsViewModel Tests")
struct SettingsViewModelTests {
    /// Test that settings are correctly computed with proper precedence
    @Test("Settings precedence is correctly applied")
    @MainActor
    func settingsPrecedence() async throws {
        // Given: Multiple settings files with different precedence levels
        let globalFile = SettingsFile(
            type: .globalSettings,
            path: URL(fileURLWithPath: "/tmp/global.json"),
            content: [
                "theme": AnyCodable("dark"),
                "fontSize": AnyCodable(12),
            ]
        )

        let projectFile = SettingsFile(
            type: .projectSettings,
            path: URL(fileURLWithPath: "/tmp/project.json"),
            content: [
                "theme": AnyCodable("light"), // Should override global
                "tabSize": AnyCodable(2),
            ]
        )

        // When: Computing setting items
        let viewModel = SettingsViewModel()
        let items = viewModel.computeSettingItems(from: [globalFile, projectFile])

        // Then: Higher precedence values should win
        let themeItem = items.first { $0.key == "theme" }
        #expect(themeItem != nil, "Theme setting should exist")
        #expect(themeItem?.value.value as? String == "light", "Project theme should override global")
        #expect(themeItem?.overriddenBy == .projectSettings, "Should show override source")

        let fontSizeItem = items.first { $0.key == "fontSize" }
        #expect(fontSizeItem?.value.value as? Int == 12, "Global fontSize should be present")
        #expect(fontSizeItem?.overriddenBy == nil, "Should not be overridden")

        let tabSizeItem = items.first { $0.key == "tabSize" }
        #expect(tabSizeItem?.value.value as? Int == 2, "Project tabSize should be present")
    }

    /// Test that array settings track multiple contributions
    @Test("Array settings track contributions")
    @MainActor
    func arraySettingsTrackContributions() async throws {
        // Given: Array settings in multiple files
        let globalFile = SettingsFile(
            type: .globalSettings,
            path: URL(fileURLWithPath: "/tmp/global.json"),
            content: [
                "permissions": AnyCodable(["Read", "Write"]),
            ]
        )

        let projectFile = SettingsFile(
            type: .projectSettings,
            path: URL(fileURLWithPath: "/tmp/project.json"),
            content: [
                "permissions": AnyCodable(["Bash"]),
            ]
        )

        // When: Computing setting items
        let viewModel = SettingsViewModel()
        let items = viewModel.computeSettingItems(from: [globalFile, projectFile])

        // Then: Should track contributions from both sources (highest precedence wins for value)
        let permissionsItem = items.first { $0.key == "permissions" }
        #expect(permissionsItem != nil, "Permissions should exist")

        // Value shows highest precedence array
        let permissions = permissionsItem?.value.value as? [Any]
        #expect(permissions?.count == 1, "Value should be from highest precedence source")

        // But contributions show both sources
        #expect(permissionsItem?.contributions.count == 2, "Should track two contributors")
        #expect(permissionsItem?.valueType == .array, "Should be array type")
    }

    /// Test that nested objects are properly flattened
    @Test("Nested objects are flattened correctly")
    @MainActor
    func nestedObjectFlattening() async throws {
        // Given: Nested settings structure
        let file = SettingsFile(
            type: .globalSettings,
            path: URL(fileURLWithPath: "/tmp/test.json"),
            content: [
                "hooks": AnyCodable([
                    "onToolCall": "echo 'tool called'",
                    "onRead": "echo 'file read'",
                ] as [String: Any]),
            ]
        )

        // When: Computing setting items
        let viewModel = SettingsViewModel()
        let items = viewModel.computeSettingItems(from: [file])

        // Then: Should be flattened to dot notation
        let onToolCallItem = items.first { $0.key == "hooks.onToolCall" }
        #expect(onToolCallItem != nil, "Should have flattened hooks.onToolCall")
        #expect(onToolCallItem?.value.value as? String == "echo 'tool called'")

        let onReadItem = items.first { $0.key == "hooks.onRead" }
        #expect(onReadItem != nil, "Should have flattened hooks.onRead")
    }

    /// Test enterprise settings precedence (highest)
    @Test("Enterprise settings have highest precedence")
    @MainActor
    func enterpriseSettingsPrecedence() async throws {
        // Given: Enterprise and project settings with conflicting values
        let enterpriseFile = SettingsFile(
            type: .enterpriseManaged,
            path: URL(fileURLWithPath: "/tmp/enterprise.json"),
            content: [
                "maxTokens": AnyCodable(1_000),
            ]
        )

        let projectFile = SettingsFile(
            type: .projectLocal,
            path: URL(fileURLWithPath: "/tmp/project.json"),
            content: [
                "maxTokens": AnyCodable(5_000), // Should NOT override enterprise
            ]
        )

        // When: Computing setting items
        let viewModel = SettingsViewModel()
        let items = viewModel.computeSettingItems(from: [enterpriseFile, projectFile])

        // Then: Enterprise should win (highest precedence)
        let maxTokensItem = items.first { $0.key == "maxTokens" }
        #expect(maxTokensItem?.value.value as? Int == 1_000, "Enterprise should win with highest precedence")
        #expect(maxTokensItem?.overriddenBy == .enterpriseManaged, "Should show enterprise as final override")
    }

    /// Test that contribution tracking works correctly
    @Test("Source contributions are tracked")
    @MainActor
    func sourceContributions() async throws {
        // Given: Settings from multiple sources
        let global = SettingsFile(
            type: .globalSettings,
            path: URL(fileURLWithPath: "/tmp/global.json"),
            content: ["setting": AnyCodable("value1")]
        )

        let project = SettingsFile(
            type: .projectSettings,
            path: URL(fileURLWithPath: "/tmp/project.json"),
            content: ["setting": AnyCodable("value2")]
        )

        // When: Computing setting items
        let viewModel = SettingsViewModel()
        let items = viewModel.computeSettingItems(from: [global, project])

        // Then: Should track all contributions
        let item = items.first { $0.key == "setting" }
        #expect(item?.contributions.count == 2, "Should have two contributions")
        #expect(item?.contributions[0].source == .globalSettings, "First should be global")
        #expect(item?.contributions[1].source == .projectSettings, "Second should be project")
        #expect(item?.source == .globalSettings, "Source should be lowest precedence")
    }

    /// Test empty settings files
    @Test("Empty settings files are handled correctly")
    @MainActor
    func emptySettings() async throws {
        // Given: Empty settings file
        let emptyFile = SettingsFile(
            type: .globalSettings,
            path: URL(fileURLWithPath: "/tmp/empty.json"),
            content: [:]
        )

        // When: Computing setting items
        let viewModel = SettingsViewModel()
        let items = viewModel.computeSettingItems(from: [emptyFile])

        // Then: Should return empty array
        #expect(items.isEmpty, "Should have no settings")
    }
}

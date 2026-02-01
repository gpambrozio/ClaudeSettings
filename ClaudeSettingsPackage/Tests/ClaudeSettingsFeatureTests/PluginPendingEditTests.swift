import Foundation
import Testing
@testable import ClaudeSettingsFeature

// MARK: - Plugin Pending Edit Validation Tests

@Suite("PluginPendingEdit Validation")
struct PluginPendingEditValidationTests {
    @Test("Empty name is invalid")
    func emptyNameInvalid() {
        let edit = PluginPendingEdit(name: "", marketplace: "TestMarket")

        #expect(edit.validationError != nil)
        #expect(edit.validationError?.contains("Name") == true)
    }

    @Test("Empty marketplace is invalid")
    func emptyMarketplaceInvalid() {
        let edit = PluginPendingEdit(name: "test-plugin", marketplace: "")

        #expect(edit.validationError != nil)
        #expect(edit.validationError?.contains("Marketplace") == true)
    }

    @Test("Valid edit has no error")
    func validEditNoError() {
        let edit = PluginPendingEdit(name: "test-plugin", marketplace: "TestMarket")

        #expect(edit.validationError == nil)
    }

    @Test("toPlugin creates correct plugin")
    func toPluginCreatesCorrect() {
        let edit = PluginPendingEdit(name: "my-plugin", marketplace: "MyMarket", isNew: true)

        let plugin = edit.toPlugin()

        #expect(plugin.name == "my-plugin")
        #expect(plugin.marketplace == "MyMarket")
        #expect(plugin.id == "my-plugin@MyMarket")
    }

    @Test("Creates from existing plugin")
    func createsFromExisting() {
        let plugin = InstalledPlugin(
            name: "original-plugin",
            marketplace: "OriginalMarket",
            installedAt: "2026-01-20T10:00:00Z",
            dataSource: .global
        )

        let edit = PluginPendingEdit(from: plugin)

        #expect(edit.name == "original-plugin")
        #expect(edit.marketplace == "OriginalMarket")
        #expect(edit.isNew == false)
        #expect(edit.original?.name == "original-plugin")
    }

    @Test("toPlugin preserves original installedAt")
    func toPluginPreservesInstalledAt() {
        let originalDate = "2026-01-15T08:30:00Z"
        let plugin = InstalledPlugin(
            name: "my-plugin",
            marketplace: "MyMarket",
            installedAt: originalDate
        )

        let edit = PluginPendingEdit(from: plugin)
        let recreatedPlugin = edit.toPlugin()

        #expect(recreatedPlugin.installedAt == originalDate)
    }
}

// MARK: - Edge Cases

@Suite("PluginPendingEdit Edge Cases")
struct PluginPendingEditEdgeCaseTests {
    @Test("Whitespace-only name is invalid")
    func whitespaceOnlyNameInvalid() {
        let edit = PluginPendingEdit(name: "   \t\n  ", marketplace: "TestMarket")

        #expect(edit.validationError != nil)
        #expect(edit.validationError?.contains("Name") == true)
    }

    @Test("Whitespace-only marketplace is invalid")
    func whitespaceOnlyMarketplaceInvalid() {
        let edit = PluginPendingEdit(name: "test-plugin", marketplace: "   \n  ")

        #expect(edit.validationError != nil)
        #expect(edit.validationError?.contains("Marketplace") == true)
    }

    @Test("toPlugin generates new installedAt for new plugins")
    func toPluginGeneratesNewInstalledAt() {
        let edit = PluginPendingEdit(name: "new-plugin", marketplace: "Market", isNew: true)

        let plugin = edit.toPlugin()

        // Should have a valid ISO 8601 date
        #expect(plugin.installedAt != nil)
        #expect(plugin.installedAt?.contains("T") == true)
    }

    @Test("toPlugin handles nil original installedAt")
    func toPluginHandlesNilInstalledAt() {
        let original = InstalledPlugin(
            name: "no-date-plugin",
            marketplace: "Market",
            installedAt: nil
        )

        let edit = PluginPendingEdit(from: original)
        let plugin = edit.toPlugin()

        // Should generate new date when original had nil
        #expect(plugin.installedAt != nil)
    }

    @Test("Name with special characters is valid")
    func nameWithSpecialCharsValid() {
        let edit = PluginPendingEdit(name: "my-plugin_v2.0", marketplace: "TestMarket")

        #expect(edit.validationError == nil)
    }

    @Test("Name with @ symbol is valid")
    func nameWithAtSymbolValid() {
        let edit = PluginPendingEdit(name: "scoped@plugin", marketplace: "TestMarket")

        #expect(edit.validationError == nil)
    }

    @Test("toPlugin correctly computes plugin id")
    func toPluginComputesId() {
        let edit = PluginPendingEdit(name: "test-plugin", marketplace: "TestMarket")

        let plugin = edit.toPlugin()

        #expect(plugin.id == "test-plugin@TestMarket")
    }

    @Test("Creates from plugin with all fields set")
    func createsFromFullPlugin() {
        let plugin = InstalledPlugin(
            name: "full-plugin",
            marketplace: "FullMarket",
            installedAt: "2026-01-24T00:00:00Z",
            dataSource: .both,
            projectFileLocation: .local,
            installPath: "/path/to/plugin",
            version: "2.0.0"
        )

        let edit = PluginPendingEdit(from: plugin)

        #expect(edit.name == "full-plugin")
        #expect(edit.marketplace == "FullMarket")
        #expect(edit.isNew == false)
        #expect(edit.original?.installPath == "/path/to/plugin")
    }

    @Test("Default initializer creates new plugin")
    func defaultInitializerCreatesNew() {
        let edit = PluginPendingEdit(name: "default-plugin", marketplace: "DefaultMarket", isNew: true)

        #expect(edit.isNew == true)
        #expect(edit.original == nil)
    }
}

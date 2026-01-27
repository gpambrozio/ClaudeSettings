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

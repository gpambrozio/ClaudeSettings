import Foundation
import Testing
@testable import ClaudeSettingsFeature

// MARK: - Plugin Data Source Tests

@Suite("PluginDataSource Tests")
struct PluginDataSourceTests {
    @Test("Global has correct display name")
    func globalDisplayName() {
        #expect(PluginDataSource.global.displayName == "Global")
    }

    @Test("Project has correct display name")
    func projectDisplayName() {
        #expect(PluginDataSource.project.displayName == "Project")
    }

    @Test("Cache has correct display name")
    func cacheDisplayName() {
        #expect(PluginDataSource.cache.displayName == "Available")
    }

    @Test("Both has correct display name")
    func bothDisplayName() {
        #expect(PluginDataSource.both.displayName == "Both")
    }
}

// MARK: - Installed Plugin Tests

@Suite("InstalledPlugin Tests")
struct InstalledPluginTests {
    @Test("Plugin ID combines name and marketplace")
    func pluginId() {
        let plugin = InstalledPlugin(name: "my-plugin", marketplace: "ClaudeCodePlugins")

        #expect(plugin.id == "my-plugin@ClaudeCodePlugins")
    }

    @Test("Plugin parses ISO 8601 date with fractional seconds")
    func pluginDateParsing() {
        let plugin = InstalledPlugin(
            name: "test-plugin",
            marketplace: "TestMarket",
            installedAt: "2026-01-24T00:22:38.588Z"
        )

        #expect(plugin.installedDate != nil)

        let calendar = Calendar.current
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: plugin.installedDate!)
        #expect(components.year == 2_026)
        #expect(components.month == 1)
        #expect(components.day == 24)
    }

    @Test("Plugin parses ISO 8601 date without fractional seconds")
    func pluginDateParsingNoFractional() {
        let plugin = InstalledPlugin(
            name: "test-plugin",
            marketplace: "TestMarket",
            installedAt: "2026-01-24T00:22:38Z"
        )

        #expect(plugin.installedDate != nil)
    }

    @Test("Plugin handles nil installedAt")
    func pluginNilDate() {
        let plugin = InstalledPlugin(name: "no-date", marketplace: "TestMarket", installedAt: nil)

        #expect(plugin.installedDate == nil)
    }
}

// MARK: - ISO 8601 Date Parsing Tests

@Suite("ISO 8601 Date Parsing Tests")
struct ISO8601DateParsingTests {
    @Test("Parse date with fractional seconds")
    func parseFractionalSeconds() {
        let date = parseISO8601Date("2026-01-24T00:22:38.588Z")
        #expect(date != nil)
    }

    @Test("Parse date without fractional seconds")
    func parseNoFractionalSeconds() {
        let date = parseISO8601Date("2026-01-24T00:22:38Z")
        #expect(date != nil)
    }

    @Test("Parse invalid date returns nil")
    func parseInvalidDate() {
        let date = parseISO8601Date("not-a-date")
        #expect(date == nil)
    }

    @Test("Parse empty string returns nil")
    func parseEmptyString() {
        let date = parseISO8601Date("")
        #expect(date == nil)
    }
}

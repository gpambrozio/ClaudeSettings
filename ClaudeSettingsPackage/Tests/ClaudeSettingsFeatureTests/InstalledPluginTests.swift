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

    @Test("Parse date with +00:00 timezone format")
    func parsePlusZeroTimezone() {
        let date = parseISO8601Date("2026-01-24T00:22:38+00:00")
        #expect(date != nil)
    }
}

// MARK: - InstalledPlugin Codable Tests

@Suite("InstalledPlugin Codable Tests")
struct InstalledPluginCodableTests {
    @Test("Encode only persists name, marketplace, installedAt")
    func encodeOnlyPersistsBasicFields() throws {
        let plugin = InstalledPlugin(
            name: "test-plugin",
            marketplace: "TestMarket",
            installedAt: "2026-01-24T00:22:38Z",
            dataSource: .global,
            projectFileLocation: .shared,
            installPath: "/path/to/plugin",
            version: "1.0.0"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(plugin)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Should include these
        #expect(json?["name"] as? String == "test-plugin")
        #expect(json?["marketplace"] as? String == "TestMarket")
        #expect(json?["installedAt"] as? String == "2026-01-24T00:22:38Z")

        // Should NOT include these (not in CodingKeys)
        #expect(json?["dataSource"] == nil)
        #expect(json?["projectFileLocation"] == nil)
        #expect(json?["installPath"] == nil)
        #expect(json?["version"] == nil)
    }

    @Test("Decode sets default values for non-persisted fields")
    func decodeSetDefaults() throws {
        let json = """
        {
            "name": "decoded-plugin",
            "marketplace": "DecodedMarket",
            "installedAt": "2026-01-25T10:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let plugin = try decoder.decode(InstalledPlugin.self, from: json)

        #expect(plugin.name == "decoded-plugin")
        #expect(plugin.marketplace == "DecodedMarket")
        #expect(plugin.installedAt == "2026-01-25T10:00:00Z")

        // Defaults
        #expect(plugin.dataSource == .global)
        #expect(plugin.projectFileLocation == nil)
        #expect(plugin.installPath == nil)
        #expect(plugin.version == nil)
    }

    @Test("Encode/decode round-trip preserves basic fields")
    func roundTrip() throws {
        let original = InstalledPlugin(
            name: "round-trip-plugin",
            marketplace: "RoundTripMarket",
            installedAt: "2026-01-24T12:30:45Z"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(InstalledPlugin.self, from: data)

        #expect(decoded.name == original.name)
        #expect(decoded.marketplace == original.marketplace)
        #expect(decoded.installedAt == original.installedAt)
        #expect(decoded.id == original.id)
    }

    @Test("Decode handles missing installedAt")
    func decodeMissingInstalledAt() throws {
        let json = """
        {
            "name": "no-date-plugin",
            "marketplace": "TestMarket"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let plugin = try decoder.decode(InstalledPlugin.self, from: json)

        #expect(plugin.name == "no-date-plugin")
        #expect(plugin.marketplace == "TestMarket")
        #expect(plugin.installedAt == nil)
    }

    @Test("Decode throws for missing required fields")
    func decodeThrowsForMissingRequired() {
        let jsonMissingName = """
        {
            "marketplace": "TestMarket"
        }
        """.data(using: .utf8)!

        let jsonMissingMarketplace = """
        {
            "name": "test-plugin"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()

        #expect(throws: (any Error).self) {
            _ = try decoder.decode(InstalledPlugin.self, from: jsonMissingName)
        }

        #expect(throws: (any Error).self) {
            _ = try decoder.decode(InstalledPlugin.self, from: jsonMissingMarketplace)
        }
    }

    @Test("Encode produces valid JSON")
    func encodeProducesValidJSON() throws {
        let plugin = InstalledPlugin(
            name: "json-plugin",
            marketplace: "JSONMarket",
            installedAt: "2026-01-24T00:00:00Z"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(plugin)
        let jsonString = String(data: data, encoding: .utf8)

        #expect(jsonString != nil)
        #expect(jsonString?.contains("\"name\" : \"json-plugin\"") == true)
    }
}

// MARK: - InstalledPlugin Property Tests

@Suite("InstalledPlugin Property Tests")
struct InstalledPluginPropertyTests {
    @Test("Default dataSource is global")
    func defaultDataSource() {
        let plugin = InstalledPlugin(name: "test", marketplace: "Market")
        #expect(plugin.dataSource == .global)
    }

    @Test("All properties can be set in initializer")
    func allPropertiesSet() {
        let plugin = InstalledPlugin(
            name: "full-plugin",
            marketplace: "FullMarket",
            installedAt: "2026-01-24T00:00:00Z",
            dataSource: .both,
            projectFileLocation: .local,
            installPath: "/path/to/install",
            version: "2.0.0"
        )

        #expect(plugin.name == "full-plugin")
        #expect(plugin.marketplace == "FullMarket")
        #expect(plugin.installedAt == "2026-01-24T00:00:00Z")
        #expect(plugin.dataSource == .both)
        #expect(plugin.projectFileLocation == .local)
        #expect(plugin.installPath == "/path/to/install")
        #expect(plugin.version == "2.0.0")
    }

    @Test("dataSource is mutable")
    func dataSourceMutable() {
        var plugin = InstalledPlugin(name: "test", marketplace: "Market")
        #expect(plugin.dataSource == .global)

        plugin.dataSource = .project
        #expect(plugin.dataSource == .project)
    }

    @Test("projectFileLocation is mutable")
    func projectFileLocationMutable() {
        var plugin = InstalledPlugin(name: "test", marketplace: "Market")
        #expect(plugin.projectFileLocation == nil)

        plugin.projectFileLocation = .shared
        #expect(plugin.projectFileLocation == .shared)
    }
}

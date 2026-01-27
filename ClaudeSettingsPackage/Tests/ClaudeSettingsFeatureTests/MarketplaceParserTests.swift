import Foundation
import Testing
@testable import ClaudeSettingsFeature

// MARK: - Marketplace Source Tests

@Suite("MarketplaceSource Tests")
struct MarketplaceSourceTests {
    @Test("GitHub source is identified correctly")
    func githubSource() {
        let source = MarketplaceSource(source: "github", repo: "company/repo", ref: "main")

        #expect(source.isGitHub == true)
        #expect(source.isDirectory == false)
        #expect(source.repo == "company/repo")
        #expect(source.ref == "main")
    }

    @Test("Directory source is identified correctly")
    func directorySource() {
        let source = MarketplaceSource(source: "directory", path: "/path/to/plugins")

        #expect(source.isGitHub == false)
        #expect(source.isDirectory == true)
        #expect(source.path == "/path/to/plugins")
    }
}

// MARK: - Known Marketplace Tests

@Suite("KnownMarketplace Tests")
struct KnownMarketplaceTests {
    @Test("Marketplace ID is derived from name")
    func marketplaceId() {
        let marketplace = KnownMarketplace(
            name: "TestMarketplace",
            source: MarketplaceSource(source: "github", repo: "test/repo"),
            dataSource: .global
        )

        #expect(marketplace.id == "TestMarketplace")
    }

    @Test("Marketplace with all properties")
    func marketplaceAllProperties() {
        let lastUpdated = Date()
        let marketplace = KnownMarketplace(
            name: "FullMarketplace",
            source: MarketplaceSource(source: "github", repo: "company/plugins", ref: "v1.0"),
            dataSource: .both,
            installLocation: "/Users/test/.claude/plugins/marketplaces/FullMarketplace",
            lastUpdated: lastUpdated
        )

        #expect(marketplace.name == "FullMarketplace")
        #expect(marketplace.source.repo == "company/plugins")
        #expect(marketplace.source.ref == "v1.0")
        #expect(marketplace.dataSource == .both)
        #expect(marketplace.installLocation != nil)
        #expect(marketplace.lastUpdated == lastUpdated)
    }
}

// MARK: - Marketplace Parser Tests

@Suite("MarketplaceParser Tests")
struct MarketplaceParserTests {
    @Test("Parse extra marketplaces from settings content")
    func parseExtraMarketplaces() async {
        let parser = MarketplaceParser()

        let settingsContent: [String: SettingValue] = [
            "extraKnownMarketplaces": .object([
                "CustomMarketplace": .object([
                    "source": .object([
                        "source": .string("github"),
                        "repo": .string("mycompany/plugins"),
                        "ref": .string("main"),
                    ]),
                ]),
            ]),
        ]

        let result = await parser.parseExtraMarketplaces(from: settingsContent)

        #expect(result.count == 1)
        #expect(result["CustomMarketplace"]?.repo == "mycompany/plugins")
        #expect(result["CustomMarketplace"]?.ref == "main")
    }

    @Test("Parse extra marketplaces with missing extraKnownMarketplaces key")
    func parseNoExtraMarketplaces() async {
        let parser = MarketplaceParser()

        let settingsContent: [String: SettingValue] = [
            "model": .string("claude-4"),
        ]

        let result = await parser.parseExtraMarketplaces(from: settingsContent)

        #expect(result.isEmpty)
    }

    @Test("Merge marketplaces creates global entries")
    func mergeGlobalOnly() async {
        let parser = MarketplaceParser()

        let runtimeData: [String: (source: MarketplaceSource, installLocation: String?, lastUpdated: Date?)] = [
            "RuntimeMarket": (
                source: MarketplaceSource(source: "github", repo: "runtime/repo"),
                installLocation: "/path/to/install",
                lastUpdated: Date()
            ),
        ]

        let result = await parser.mergeMarketplaces(runtime: runtimeData, settings: [:])

        #expect(result.count == 1)
        #expect(result[0].name == "RuntimeMarket")
        #expect(result[0].dataSource == .global)
        #expect(result[0].installLocation == "/path/to/install")
    }

    @Test("Merge marketplaces creates project entries")
    func mergeProjectOnly() async {
        let parser = MarketplaceParser()

        let settingsData: [String: MarketplaceSource] = [
            "SettingsMarket": MarketplaceSource(source: "github", repo: "settings/repo"),
        ]

        let result = await parser.mergeMarketplaces(runtime: [:], settings: settingsData)

        #expect(result.count == 1)
        #expect(result[0].name == "SettingsMarket")
        #expect(result[0].dataSource == .project)
        #expect(result[0].installLocation == nil)
    }

    @Test("Merge marketplaces creates both entries when present in both sources")
    func mergeBothSources() async {
        let parser = MarketplaceParser()

        let runtimeData: [String: (source: MarketplaceSource, installLocation: String?, lastUpdated: Date?)] = [
            "SharedMarket": (
                source: MarketplaceSource(source: "github", repo: "runtime/version"),
                installLocation: "/installed/path",
                lastUpdated: Date()
            ),
        ]

        let settingsData: [String: MarketplaceSource] = [
            "SharedMarket": MarketplaceSource(source: "github", repo: "settings/version"),
        ]

        let result = await parser.mergeMarketplaces(runtime: runtimeData, settings: settingsData)

        #expect(result.count == 1)
        #expect(result[0].name == "SharedMarket")
        #expect(result[0].dataSource == .both)
        // Runtime source should be preferred
        #expect(result[0].source.repo == "runtime/version")
        #expect(result[0].installLocation == "/installed/path")
    }

    @Test("Merge marketplaces returns sorted results")
    func mergeSorted() async {
        let parser = MarketplaceParser()

        let runtimeData: [String: (source: MarketplaceSource, installLocation: String?, lastUpdated: Date?)] = [
            "Zebra": (source: MarketplaceSource(source: "github"), installLocation: nil, lastUpdated: nil),
            "Alpha": (source: MarketplaceSource(source: "github"), installLocation: nil, lastUpdated: nil),
        ]

        let result = await parser.mergeMarketplaces(runtime: runtimeData, settings: [:])

        #expect(result.count == 2)
        #expect(result[0].name == "Alpha")
        #expect(result[1].name == "Zebra")
    }
}

// MARK: - File I/O Test Fixtures

private enum FileIOTestFixtures {
    static let testHomeDirectory = URL(fileURLWithPath: "/tmp/parser-test-home")

    static func makeKnownMarketplacesJSON() -> Data {
        """
        {
            "TestMarketplace": {
                "source": {
                    "source": "github",
                    "repo": "test/plugins",
                    "ref": "main"
                },
                "installLocation": "/tmp/plugins/TestMarketplace",
                "lastUpdated": "2026-01-24T12:00:00.000Z"
            }
        }
        """.data(using: .utf8)!
    }

    static func makeInstalledPluginsJSON() -> Data {
        """
        {
            "version": 1,
            "plugins": {
                "plugin-a@TestMarketplace": [
                    {
                        "scope": "user",
                        "installPath": "/tmp/cache/TestMarketplace/plugin-a/1.0.0",
                        "version": "1.0.0",
                        "installedAt": "2026-01-20T10:00:00Z",
                        "lastUpdated": "2026-01-20T10:00:00Z"
                    }
                ]
            }
        }
        """.data(using: .utf8)!
    }

    static func makeMalformedJSON() -> Data {
        "{ not valid json".data(using: .utf8)!
    }
}

// MARK: - File Reading Tests

@Suite("MarketplaceParser File Reading")
struct MarketplaceParserFileReadingTests {
    @Test("parseKnownMarketplaces reads valid JSON")
    func parseKnownMarketplacesReadsValidJSON() async throws {
        let mockFS = MockFileSystemManager()
        let parser = MarketplaceParser(fileSystemManager: mockFS)
        let testPath = FileIOTestFixtures.testHomeDirectory.appendingPathComponent("known_marketplaces.json")

        await mockFS.addFile(at: testPath, content: FileIOTestFixtures.makeKnownMarketplacesJSON())

        let result = try await parser.parseKnownMarketplaces(at: testPath)

        #expect(result.count == 1)
        #expect(result["TestMarketplace"] != nil)
        #expect(result["TestMarketplace"]?.source.repo == "test/plugins")
        #expect(result["TestMarketplace"]?.installLocation == "/tmp/plugins/TestMarketplace")
    }

    @Test("parseKnownMarketplaces handles missing file")
    func parseKnownMarketplacesHandlesMissingFile() async throws {
        let mockFS = MockFileSystemManager()
        let parser = MarketplaceParser(fileSystemManager: mockFS)
        let testPath = FileIOTestFixtures.testHomeDirectory.appendingPathComponent("nonexistent.json")

        // No file added - should handle gracefully
        let result = try await parser.parseKnownMarketplaces(at: testPath)

        #expect(result.isEmpty)
    }

    @Test("parseKnownMarketplaces throws on malformed JSON")
    func parseKnownMarketplacesThrowsOnMalformedJSON() async {
        let mockFS = MockFileSystemManager()
        let parser = MarketplaceParser(fileSystemManager: mockFS)
        let testPath = FileIOTestFixtures.testHomeDirectory.appendingPathComponent("malformed.json")

        await mockFS.addFile(at: testPath, content: FileIOTestFixtures.makeMalformedJSON())

        await #expect(throws: (any Error).self) {
            _ = try await parser.parseKnownMarketplaces(at: testPath)
        }
    }

    @Test("parseInstalledPlugins reads valid JSON")
    func parseInstalledPluginsReadsValidJSON() async throws {
        let mockFS = MockFileSystemManager()
        let parser = MarketplaceParser(fileSystemManager: mockFS)
        let testPath = FileIOTestFixtures.testHomeDirectory.appendingPathComponent("installed_plugins.json")

        await mockFS.addFile(at: testPath, content: FileIOTestFixtures.makeInstalledPluginsJSON())

        let result = try await parser.parseInstalledPlugins(at: testPath)

        #expect(result.count == 1)
        #expect(result[0].name == "plugin-a")
        #expect(result[0].marketplace == "TestMarketplace")
        #expect(result[0].dataSource == .global)
    }

    @Test("parseInstalledPlugins handles missing file")
    func parseInstalledPluginsHandlesMissingFile() async throws {
        let mockFS = MockFileSystemManager()
        let parser = MarketplaceParser(fileSystemManager: mockFS)
        let testPath = FileIOTestFixtures.testHomeDirectory.appendingPathComponent("nonexistent_plugins.json")

        let result = try await parser.parseInstalledPlugins(at: testPath)

        #expect(result.isEmpty)
    }

    @Test("parseInstalledPlugins throws on malformed JSON")
    func parseInstalledPluginsThrowsOnMalformedJSON() async {
        let mockFS = MockFileSystemManager()
        let parser = MarketplaceParser(fileSystemManager: mockFS)
        let testPath = FileIOTestFixtures.testHomeDirectory.appendingPathComponent("malformed_plugins.json")

        await mockFS.addFile(at: testPath, content: FileIOTestFixtures.makeMalformedJSON())

        await #expect(throws: (any Error).self) {
            _ = try await parser.parseInstalledPlugins(at: testPath)
        }
    }
}

// MARK: - File Writing Tests

@Suite("MarketplaceParser File Writing")
struct MarketplaceParserFileWritingTests {
    // Note: The parser's save methods use FileManager.default directly (not the mock).
    // These tests use a temporary directory that actually exists on disk.

    static let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("parser-write-tests-\(UUID().uuidString)")

    @Test("saveKnownMarketplaces creates valid JSON")
    func saveKnownMarketplacesCreatesValidJSON() async throws {
        let mockFS = MockFileSystemManager()
        let parser = MarketplaceParser(fileSystemManager: mockFS)
        let testPath = Self.tempDir.appendingPathComponent("output_marketplaces.json")

        let marketplaces = [
            KnownMarketplace(
                name: "SavedMarket",
                source: MarketplaceSource(source: "github", repo: "saved/repo", ref: "v1.0"),
                dataSource: .global,
                installLocation: "/installed/path",
                lastUpdated: Date()
            ),
        ]

        try await parser.saveKnownMarketplaces(marketplaces, to: testPath)

        // Verify file was written to disk
        let writtenData = try? Data(contentsOf: testPath)
        #expect(writtenData != nil)

        // Parse back to verify structure
        if let data = writtenData {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(json?["SavedMarket"] != nil)
        }

        // Cleanup
        try? FileManager.default.removeItem(at: testPath)
    }

    @Test("saveKnownMarketplaces excludes project-only marketplaces")
    func saveKnownMarketplacesExcludesProjectOnly() async throws {
        let mockFS = MockFileSystemManager()
        let parser = MarketplaceParser(fileSystemManager: mockFS)
        let testPath = Self.tempDir.appendingPathComponent("exclude_project.json")

        let marketplaces = [
            KnownMarketplace(
                name: "GlobalMarket",
                source: MarketplaceSource(source: "github", repo: "global/repo"),
                dataSource: .global
            ),
            KnownMarketplace(
                name: "ProjectMarket",
                source: MarketplaceSource(source: "github", repo: "project/repo"),
                dataSource: .project
            ),
        ]

        try await parser.saveKnownMarketplaces(marketplaces, to: testPath)

        let writtenData = try? Data(contentsOf: testPath)
        if let data = writtenData {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(json?["GlobalMarket"] != nil)
            #expect(json?["ProjectMarket"] == nil)
        } else {
            #expect(writtenData != nil, "File should have been written")
        }

        // Cleanup
        try? FileManager.default.removeItem(at: testPath)
    }

    @Test("saveInstalledPlugins creates valid JSON structure")
    func saveInstalledPluginsCreatesValidStructure() async throws {
        let mockFS = MockFileSystemManager()
        let parser = MarketplaceParser(fileSystemManager: mockFS)
        let testPath = Self.tempDir.appendingPathComponent("output_plugins.json")

        let plugins = [
            InstalledPlugin(
                name: "new-plugin",
                marketplace: "TestMarket",
                installedAt: "2026-01-25T10:00:00Z",
                dataSource: .global
            ),
        ]

        try await parser.saveInstalledPlugins(plugins, to: testPath, existingData: nil)

        let writtenData = try? Data(contentsOf: testPath)
        #expect(writtenData != nil)

        // Parse and verify structure
        if let data = writtenData {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(json?["version"] != nil)
            #expect(json?["plugins"] != nil)

            let pluginsDict = json?["plugins"] as? [String: Any]
            #expect(pluginsDict?["new-plugin@TestMarket"] != nil)
        }

        // Cleanup
        try? FileManager.default.removeItem(at: testPath)
    }

    @Test("saveInstalledPlugins preserves existing plugin data")
    func saveInstalledPluginsPreservesExisting() async throws {
        let mockFS = MockFileSystemManager()
        let parser = MarketplaceParser(fileSystemManager: mockFS)
        let testPath = Self.tempDir.appendingPathComponent("preserve_plugins.json")

        // Existing data with installation details
        let existingData = FileIOTestFixtures.makeInstalledPluginsJSON()

        // Save the same plugin (should preserve existing details)
        let plugins = [
            InstalledPlugin(
                name: "plugin-a",
                marketplace: "TestMarketplace",
                dataSource: .global
            ),
        ]

        try await parser.saveInstalledPlugins(plugins, to: testPath, existingData: existingData)

        let writtenData = try? Data(contentsOf: testPath)
        if let data = writtenData {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let pluginsDict = json?["plugins"] as? [String: [[String: Any]]]
            let installation = pluginsDict?["plugin-a@TestMarketplace"]?.first

            // Should preserve the original install path from existing data
            #expect(installation?["installPath"] as? String == "/tmp/cache/TestMarketplace/plugin-a/1.0.0")
        } else {
            #expect(writtenData != nil, "File should have been written")
        }

        // Cleanup
        try? FileManager.default.removeItem(at: testPath)
    }
}

// MARK: - Cache Scanning Tests

@Suite("MarketplaceParser Cache Scanning")
struct MarketplaceParserCacheScanningTests {
    @Test("scanPluginsInCache returns empty for missing directory")
    func scanPluginsInCacheReturnEmptyForMissing() async {
        let parser = MarketplaceParser()
        let cacheDir = FileIOTestFixtures.testHomeDirectory.appendingPathComponent("nonexistent-cache")

        let result = await parser.scanPluginsInCache(for: "AnyMarketplace", cacheDirectory: cacheDir)

        #expect(result.isEmpty)
    }

    @Test("loadMergedPlugins merges global plugins")
    func loadMergedPluginsMergesGlobal() async {
        let parser = MarketplaceParser()

        let globalPlugins = [
            InstalledPlugin(name: "plugin-a", marketplace: "TestMarket", dataSource: .global),
            InstalledPlugin(name: "plugin-b", marketplace: "TestMarket", dataSource: .global),
        ]

        let result = await parser.loadMergedPlugins(
            globalPlugins: globalPlugins,
            projectPluginKeys: [:],
            cacheDirectory: FileIOTestFixtures.testHomeDirectory,
            marketplaceNames: []
        )

        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.dataSource == .global })
    }

    @Test("loadMergedPlugins marks plugins in both as both")
    func loadMergedPluginsMarksBoth() async {
        let parser = MarketplaceParser()

        let globalPlugins = [
            InstalledPlugin(name: "plugin-a", marketplace: "TestMarket", dataSource: .global),
        ]

        let projectPluginKeys: [String: ProjectFileLocation] = [
            "plugin-a@TestMarket": .shared,
        ]

        let result = await parser.loadMergedPlugins(
            globalPlugins: globalPlugins,
            projectPluginKeys: projectPluginKeys,
            cacheDirectory: FileIOTestFixtures.testHomeDirectory,
            marketplaceNames: []
        )

        #expect(result.count == 1)
        #expect(result[0].dataSource == .both)
        #expect(result[0].projectFileLocation == .shared)
    }

    @Test("loadMergedPlugins adds project-only plugins")
    func loadMergedPluginsAddsProjectOnly() async {
        let parser = MarketplaceParser()

        let projectPluginKeys: [String: ProjectFileLocation] = [
            "project-plugin@ProjectMarket": .local,
        ]

        let result = await parser.loadMergedPlugins(
            globalPlugins: [],
            projectPluginKeys: projectPluginKeys,
            cacheDirectory: FileIOTestFixtures.testHomeDirectory,
            marketplaceNames: []
        )

        #expect(result.count == 1)
        #expect(result[0].name == "project-plugin")
        #expect(result[0].dataSource == .project)
        #expect(result[0].projectFileLocation == .local)
    }

    @Test("loadMergedPlugins returns sorted results")
    func loadMergedPluginsReturnsSorted() async {
        let parser = MarketplaceParser()

        let globalPlugins = [
            InstalledPlugin(name: "zebra", marketplace: "Market", dataSource: .global),
            InstalledPlugin(name: "alpha", marketplace: "Market", dataSource: .global),
        ]

        let result = await parser.loadMergedPlugins(
            globalPlugins: globalPlugins,
            projectPluginKeys: [:],
            cacheDirectory: FileIOTestFixtures.testHomeDirectory,
            marketplaceNames: []
        )

        #expect(result.count == 2)
        #expect(result[0].name == "alpha")
        #expect(result[1].name == "zebra")
    }
}

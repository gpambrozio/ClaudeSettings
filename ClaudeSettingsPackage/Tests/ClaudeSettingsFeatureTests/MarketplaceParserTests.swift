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

        // Verify file was written to mock file system
        let writtenData = await mockFS.getFileData(at: testPath)
        #expect(writtenData != nil)

        // Parse back to verify structure
        if let data = writtenData {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(json?["SavedMarket"] != nil)
        }
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

        let writtenData = await mockFS.getFileData(at: testPath)
        if let data = writtenData {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(json?["GlobalMarket"] != nil)
            #expect(json?["ProjectMarket"] == nil)
        } else {
            #expect(writtenData != nil, "File should have been written")
        }
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

        let writtenData = await mockFS.getFileData(at: testPath)
        #expect(writtenData != nil)

        // Parse and verify structure
        if let data = writtenData {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(json?["version"] != nil)
            #expect(json?["plugins"] != nil)

            let pluginsDict = json?["plugins"] as? [String: Any]
            #expect(pluginsDict?["new-plugin@TestMarket"] != nil)
        }
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

        let writtenData = await mockFS.getFileData(at: testPath)
        if let data = writtenData {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let pluginsDict = json?["plugins"] as? [String: [[String: Any]]]
            let installation = pluginsDict?["plugin-a@TestMarketplace"]?.first

            // Should preserve the original install path from existing data
            #expect(installation?["installPath"] as? String == "/tmp/cache/TestMarketplace/plugin-a/1.0.0")
        } else {
            #expect(writtenData != nil, "File should have been written")
        }
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

// MARK: - Scan Available Plugins Tests

private enum ScanPluginsTestFixtures {
    static let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("scan-plugins-tests-\(UUID().uuidString)")

    static func createMarketplaceDirectory(name: String, plugins: [String: [String]]) -> URL {
        let marketDir = tempDir.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: marketDir, withIntermediateDirectories: true)

        for (pluginName, markers) in plugins {
            let pluginDir = marketDir.appendingPathComponent(pluginName)
            try? FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)

            for marker in markers {
                let markerPath = pluginDir.appendingPathComponent(marker)
                if marker.contains(".") {
                    try? "{}".write(to: markerPath, atomically: true, encoding: .utf8)
                } else {
                    try? FileManager.default.createDirectory(at: markerPath, withIntermediateDirectories: true)
                }
            }
        }

        return marketDir
    }

    static func cleanup() {
        try? FileManager.default.removeItem(at: tempDir)
    }
}

@Suite("MarketplaceParser scanAvailablePlugins")
struct MarketplaceParserScanAvailablePluginsTests {
    init() {
        try? FileManager.default.createDirectory(at: ScanPluginsTestFixtures.tempDir, withIntermediateDirectories: true)
    }

    @Test("Returns empty array for nil install location")
    func returnsEmptyForNilLocation() async {
        let parser = MarketplaceParser()
        let marketplace = KnownMarketplace(
            name: "TestMarket",
            source: MarketplaceSource(source: "github", repo: "test/repo"),
            dataSource: .global,
            installLocation: nil
        )

        let result = await parser.scanAvailablePlugins(in: marketplace, at: nil)

        #expect(result.isEmpty)
    }

    @Test("Returns empty array for nonexistent directory")
    func returnsEmptyForNonexistentDir() async {
        let parser = MarketplaceParser()
        let marketplace = KnownMarketplace(
            name: "TestMarket",
            source: MarketplaceSource(source: "github", repo: "test/repo"),
            dataSource: .global,
            installLocation: "/nonexistent/path"
        )

        let result = await parser.scanAvailablePlugins(in: marketplace, at: "/nonexistent/path")

        #expect(result.isEmpty)
    }

    @Test("Detects plugins in root directory")
    func detectsPluginsInRoot() async {
        let marketDir = ScanPluginsTestFixtures.createMarketplaceDirectory(
            name: "root-market",
            plugins: [
                "plugin-a": ["info.json"],
                "plugin-b": ["SKILL.md"],
            ]
        )
        defer { try? FileManager.default.removeItem(at: marketDir) }

        let parser = MarketplaceParser()
        let marketplace = KnownMarketplace(
            name: "root-market",
            source: MarketplaceSource(source: "github", repo: "test/repo"),
            dataSource: .global,
            installLocation: marketDir.path
        )

        let result = await parser.scanAvailablePlugins(in: marketplace, at: marketDir.path)

        #expect(result.count == 2)
        #expect(result.contains { $0.name == "plugin-a" })
        #expect(result.contains { $0.name == "plugin-b" })
    }

    @Test("Detects plugins in plugins subdirectory")
    func detectsPluginsInSubdirectory() async {
        let marketDir = ScanPluginsTestFixtures.tempDir.appendingPathComponent("subdir-market")
        try? FileManager.default.createDirectory(at: marketDir, withIntermediateDirectories: true)

        // Create plugins subdirectory
        let pluginsDir = marketDir.appendingPathComponent("plugins")
        try? FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)

        // Add plugin in subdirectory
        let pluginDir = pluginsDir.appendingPathComponent("subdir-plugin")
        try? FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        try? "{}".write(to: pluginDir.appendingPathComponent("info.json"), atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: marketDir) }

        let parser = MarketplaceParser()
        let marketplace = KnownMarketplace(
            name: "subdir-market",
            source: MarketplaceSource(source: "github", repo: "test/repo"),
            dataSource: .global,
            installLocation: marketDir.path
        )

        let result = await parser.scanAvailablePlugins(in: marketplace, at: marketDir.path)

        #expect(result.contains { $0.name == "subdir-plugin" })
    }

    @Test("Returns sorted results")
    func returnsSortedResults() async {
        let marketDir = ScanPluginsTestFixtures.createMarketplaceDirectory(
            name: "sorted-market",
            plugins: [
                "zebra-plugin": ["info.json"],
                "alpha-plugin": ["info.json"],
                "middle-plugin": ["info.json"],
            ]
        )
        defer { try? FileManager.default.removeItem(at: marketDir) }

        let parser = MarketplaceParser()
        let marketplace = KnownMarketplace(
            name: "sorted-market",
            source: MarketplaceSource(source: "github", repo: "test/repo"),
            dataSource: .global,
            installLocation: marketDir.path
        )

        let result = await parser.scanAvailablePlugins(in: marketplace, at: marketDir.path)

        #expect(result.count == 3)
        #expect(result[0].name == "alpha-plugin")
        #expect(result[1].name == "middle-plugin")
        #expect(result[2].name == "zebra-plugin")
    }

    @Test("Sets correct marketplace name on plugins")
    func setsCorrectMarketplaceName() async {
        let marketDir = ScanPluginsTestFixtures.createMarketplaceDirectory(
            name: "name-test-market",
            plugins: [
                "test-plugin": ["info.json"],
            ]
        )
        defer { try? FileManager.default.removeItem(at: marketDir) }

        let parser = MarketplaceParser()
        let marketplace = KnownMarketplace(
            name: "MySpecialMarket",
            source: MarketplaceSource(source: "github", repo: "test/repo"),
            dataSource: .global,
            installLocation: marketDir.path
        )

        let result = await parser.scanAvailablePlugins(in: marketplace, at: marketDir.path)

        #expect(result.count == 1)
        #expect(result[0].marketplace == "MySpecialMarket")
    }

    @Test("Skips directories without plugin markers")
    func skipsNonPluginDirectories() async {
        let marketDir = ScanPluginsTestFixtures.tempDir.appendingPathComponent("mixed-market")
        try? FileManager.default.createDirectory(at: marketDir, withIntermediateDirectories: true)

        // Real plugin
        let pluginDir = marketDir.appendingPathComponent("real-plugin")
        try? FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        try? "{}".write(to: pluginDir.appendingPathComponent("info.json"), atomically: true, encoding: .utf8)

        // Not a plugin (no markers)
        let notPluginDir = marketDir.appendingPathComponent("not-a-plugin")
        try? FileManager.default.createDirectory(at: notPluginDir, withIntermediateDirectories: true)
        try? "readme".write(to: notPluginDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: marketDir) }

        let parser = MarketplaceParser()
        let marketplace = KnownMarketplace(
            name: "mixed-market",
            source: MarketplaceSource(source: "github", repo: "test/repo"),
            dataSource: .global,
            installLocation: marketDir.path
        )

        let result = await parser.scanAvailablePlugins(in: marketplace, at: marketDir.path)

        #expect(result.count == 1)
        #expect(result[0].name == "real-plugin")
    }

    @Test("Deduplicates plugins found in multiple locations")
    func deduplicatesPlugins() async {
        let marketDir = ScanPluginsTestFixtures.tempDir.appendingPathComponent("dedup-market")
        try? FileManager.default.createDirectory(at: marketDir, withIntermediateDirectories: true)

        // Plugin in root
        let rootPlugin = marketDir.appendingPathComponent("dup-plugin")
        try? FileManager.default.createDirectory(at: rootPlugin, withIntermediateDirectories: true)
        try? "{}".write(to: rootPlugin.appendingPathComponent("info.json"), atomically: true, encoding: .utf8)

        // Same plugin name in plugins subdirectory
        let pluginsDir = marketDir.appendingPathComponent("plugins")
        try? FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        let subPlugin = pluginsDir.appendingPathComponent("dup-plugin")
        try? FileManager.default.createDirectory(at: subPlugin, withIntermediateDirectories: true)
        try? "{}".write(to: subPlugin.appendingPathComponent("info.json"), atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: marketDir) }

        let parser = MarketplaceParser()
        let marketplace = KnownMarketplace(
            name: "dedup-market",
            source: MarketplaceSource(source: "github", repo: "test/repo"),
            dataSource: .global,
            installLocation: marketDir.path
        )

        let result = await parser.scanAvailablePlugins(in: marketplace, at: marketDir.path)

        // Should only have one instance of dup-plugin
        let dupPluginCount = result.filter { $0.name == "dup-plugin" }.count
        #expect(dupPluginCount == 1)
    }

    @Test("Detects plugins in external_plugins subdirectory")
    func detectsPluginsInExternalPlugins() async {
        let marketDir = ScanPluginsTestFixtures.tempDir.appendingPathComponent("external-market")
        try? FileManager.default.createDirectory(at: marketDir, withIntermediateDirectories: true)

        // Create external_plugins subdirectory
        let externalDir = marketDir.appendingPathComponent("external_plugins")
        try? FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)

        let pluginDir = externalDir.appendingPathComponent("external-plugin")
        try? FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        try? "{}".write(to: pluginDir.appendingPathComponent("info.json"), atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: marketDir) }

        let parser = MarketplaceParser()
        let marketplace = KnownMarketplace(
            name: "external-market",
            source: MarketplaceSource(source: "github", repo: "test/repo"),
            dataSource: .global,
            installLocation: marketDir.path
        )

        let result = await parser.scanAvailablePlugins(in: marketplace, at: marketDir.path)

        #expect(result.contains { $0.name == "external-plugin" })
    }

    @Test("Extracts metadata from plugin")
    func extractsMetadata() async {
        let marketDir = ScanPluginsTestFixtures.tempDir.appendingPathComponent("metadata-market")
        try? FileManager.default.createDirectory(at: marketDir, withIntermediateDirectories: true)

        let pluginDir = marketDir.appendingPathComponent("metadata-plugin")
        try? FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        let infoJson = """
        {
            "version": "2.5.0",
            "description": "A plugin with metadata"
        }
        """
        try? infoJson.write(to: pluginDir.appendingPathComponent("info.json"), atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: marketDir) }

        let parser = MarketplaceParser()
        let marketplace = KnownMarketplace(
            name: "metadata-market",
            source: MarketplaceSource(source: "github", repo: "test/repo"),
            dataSource: .global,
            installLocation: marketDir.path
        )

        let result = await parser.scanAvailablePlugins(in: marketplace, at: marketDir.path)

        #expect(result.count == 1)
        #expect(result[0].version == "2.5.0")
        #expect(result[0].description == "A plugin with metadata")
    }
}

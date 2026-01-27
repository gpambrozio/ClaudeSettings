import Foundation
import Testing
@testable import ClaudeSettingsFeature

// MARK: - Test Fixtures

private enum MetadataTestFixtures {
    static let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("metadata-discovery-tests-\(UUID().uuidString)")

    static func createPluginDirectory(name: String, markers: [String] = [], files: [String: String] = [:]) -> URL {
        let pluginDir = tempDir.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        // Create marker files/directories
        for marker in markers {
            let markerPath = pluginDir.appendingPathComponent(marker)
            if marker.contains(".") {
                // It's a file
                try? "".write(to: markerPath, atomically: true, encoding: .utf8)
            } else {
                // It's a directory
                try? FileManager.default.createDirectory(at: markerPath, withIntermediateDirectories: true)
            }
        }

        // Create content files
        for (filename, content) in files {
            let filePath = pluginDir.appendingPathComponent(filename)
            // Create parent directories if needed
            try? FileManager.default.createDirectory(at: filePath.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? content.write(to: filePath, atomically: true, encoding: .utf8)
        }

        return pluginDir
    }

    static func cleanup() {
        try? FileManager.default.removeItem(at: tempDir)
    }
}

// MARK: - Plugin Detection Tests

@Suite("PluginMetadataDiscovery - looksLikePluginDirectory")
struct PluginDetectionTests {
    let discovery = PluginMetadataDiscovery()

    init() {
        try? FileManager.default.createDirectory(at: MetadataTestFixtures.tempDir, withIntermediateDirectories: true)
    }

    @Test("Detects plugin with info.json marker")
    func detectInfoJson() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "plugin-info", markers: ["info.json"])
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(discovery.looksLikePluginDirectory(dir) == true)
    }

    @Test("Detects plugin with .claude-plugin marker")
    func detectClaudePluginMarker() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "plugin-claude", markers: [".claude-plugin"])
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(discovery.looksLikePluginDirectory(dir) == true)
    }

    @Test("Detects plugin with claude-code.json marker")
    func detectClaudeCodeJson() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "plugin-code", markers: ["claude-code.json"])
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(discovery.looksLikePluginDirectory(dir) == true)
    }

    @Test("Detects plugin with plugin.json marker")
    func detectPluginJson() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "plugin-json", markers: ["plugin.json"])
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(discovery.looksLikePluginDirectory(dir) == true)
    }

    @Test("Detects plugin with SKILL.md marker")
    func detectSkillMd() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "plugin-skill", markers: ["SKILL.md"])
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(discovery.looksLikePluginDirectory(dir) == true)
    }

    @Test("Detects plugin with skills directory marker")
    func detectSkillsDir() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "plugin-skills-dir", markers: ["skills"])
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(discovery.looksLikePluginDirectory(dir) == true)
    }

    @Test("Detects plugin with commands directory marker")
    func detectCommandsDir() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "plugin-commands", markers: ["commands"])
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(discovery.looksLikePluginDirectory(dir) == true)
    }

    @Test("Detects plugin with hooks directory marker")
    func detectHooksDir() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "plugin-hooks", markers: ["hooks"])
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(discovery.looksLikePluginDirectory(dir) == true)
    }

    @Test("Returns false for empty directory")
    func emptyDirectory() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "empty-plugin", markers: [])
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(discovery.looksLikePluginDirectory(dir) == false)
    }

    @Test("Returns false for directory with unrelated files")
    func unrelatedFiles() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "not-plugin", markers: [], files: [
            "README.md": "# Not a plugin",
            "package.json": "{}",
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(discovery.looksLikePluginDirectory(dir) == false)
    }

    @Test("Returns false for nonexistent directory")
    func nonexistentDirectory() {
        let nonexistent = MetadataTestFixtures.tempDir.appendingPathComponent("does-not-exist")

        #expect(discovery.looksLikePluginDirectory(nonexistent) == false)
    }
}

// MARK: - JSON Metadata Search Tests

@Suite("PluginMetadataDiscovery - searchJSONFilesForMetadata")
struct JSONMetadataSearchTests {
    let discovery = PluginMetadataDiscovery()

    init() {
        try? FileManager.default.createDirectory(at: MetadataTestFixtures.tempDir, withIntermediateDirectories: true)
    }

    @Test("Extracts description from description key")
    func extractDescription() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "desc-plugin", files: [
            "info.json": """
            {
                "description": "A great plugin for testing"
            }
            """,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let metadata = discovery.searchJSONFilesForMetadata(in: dir)

        #expect(metadata.description == "A great plugin for testing")
    }

    @Test("Extracts version from version key")
    func extractVersion() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "version-plugin", files: [
            "info.json": """
            {
                "version": "2.1.0"
            }
            """,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let metadata = discovery.searchJSONFilesForMetadata(in: dir)

        #expect(metadata.version == "2.1.0")
    }

    @Test("Extracts skills from skills array")
    func extractSkills() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "skills-plugin", files: [
            "info.json": """
            {
                "skills": ["code-review", "testing", "documentation"]
            }
            """,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let metadata = discovery.searchJSONFilesForMetadata(in: dir)

        #expect(metadata.skills.count == 3)
        #expect(metadata.skills.contains("code-review"))
    }

    @Test("Prioritizes plugin.json over other files")
    func prioritizesPluginJson() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "priority-plugin", files: [
            "plugin.json": """
            {
                "version": "1.0.0",
                "description": "From plugin.json"
            }
            """,
            "info.json": """
            {
                "version": "2.0.0",
                "description": "From info.json"
            }
            """,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let metadata = discovery.searchJSONFilesForMetadata(in: dir)

        #expect(metadata.version == "1.0.0")
        #expect(metadata.description == "From plugin.json")
    }

    @Test("Searches nested .claude-plugin directory")
    func searchesNestedDirectory() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "nested-plugin", files: [
            ".claude-plugin/info.json": """
            {
                "description": "From nested directory"
            }
            """,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let metadata = discovery.searchJSONFilesForMetadata(in: dir)

        #expect(metadata.description == "From nested directory")
    }

    @Test("Extracts version from nested versions array")
    func extractVersionFromVersionsArray() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "versions-plugin", files: [
            "info.json": """
            {
                "versions": [
                    {
                        "version": "3.0.0",
                        "changes": "Major update with new features"
                    },
                    {
                        "version": "2.0.0",
                        "changes": "Previous version"
                    }
                ]
            }
            """,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let metadata = discovery.searchJSONFilesForMetadata(in: dir)

        #expect(metadata.version == "3.0.0")
        #expect(metadata.description == "Major update with new features")
    }

    @Test("Handles malformed JSON gracefully")
    func handlesMalformedJson() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "malformed-plugin", files: [
            "info.json": "{ not valid json }",
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let metadata = discovery.searchJSONFilesForMetadata(in: dir)

        #expect(metadata.description == nil)
        #expect(metadata.version == nil)
    }

    @Test("Returns empty metadata for empty directory")
    func emptyDirectoryReturnsEmpty() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "empty-json", files: [:])
        defer { try? FileManager.default.removeItem(at: dir) }

        let metadata = discovery.searchJSONFilesForMetadata(in: dir)

        #expect(metadata.description == nil)
        #expect(metadata.version == nil)
        #expect(metadata.skills.isEmpty)
    }

    @Test("Extracts description from summary key")
    func extractDescriptionFromSummary() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "summary-plugin", files: [
            "info.json": """
            {
                "summary": "A brief summary of the plugin"
            }
            """,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let metadata = discovery.searchJSONFilesForMetadata(in: dir)

        #expect(metadata.description == "A brief summary of the plugin")
    }
}

// MARK: - README Extraction Tests

@Suite("PluginMetadataDiscovery - extractDescriptionFromReadme")
struct ReadmeExtractionTests {
    let discovery = PluginMetadataDiscovery()

    init() {
        try? FileManager.default.createDirectory(at: MetadataTestFixtures.tempDir, withIntermediateDirectories: true)
    }

    @Test("Extracts first paragraph from README.md")
    func extractFirstParagraph() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "readme-plugin", files: [
            "README.md": """
            # My Plugin

            This is a fantastic plugin that does amazing things.

            ## Features

            - Feature 1
            """,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let description = discovery.extractDescriptionFromReadme(in: dir)

        #expect(description == "This is a fantastic plugin that does amazing things.")
    }

    @Test("Handles README with badges at top")
    func handlesBadges() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "badge-plugin", files: [
            "README.md": """
            # Plugin

            [![Build Status](https://example.com/badge.svg)](https://example.com)
            ![Coverage](https://example.com/coverage.svg)

            This is the actual description of the plugin.

            ## More info
            """,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let description = discovery.extractDescriptionFromReadme(in: dir)

        #expect(description == "This is the actual description of the plugin.")
    }

    @Test("Handles case-insensitive README filename")
    func caseInsensitiveFilename() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "case-plugin", files: [
            "readme.MD": """
            # Plugin

            This is the description.
            """,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let description = discovery.extractDescriptionFromReadme(in: dir)

        #expect(description == "This is the description.")
    }

    @Test("Handles README.txt extension")
    func readmeTxtExtension() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "txt-plugin", files: [
            "README.txt": """
            # Plugin Title

            This is a text readme description.
            """,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let description = discovery.extractDescriptionFromReadme(in: dir)

        #expect(description == "This is a text readme description.")
    }

    @Test("Truncates long descriptions to 200 characters")
    func truncatesLongDescription() {
        let longText = String(repeating: "This is a very long description. ", count: 20)
        let dir = MetadataTestFixtures.createPluginDirectory(name: "long-plugin", files: [
            "README.md": """
            # Plugin

            \(longText)

            ## More
            """,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let description = discovery.extractDescriptionFromReadme(in: dir)

        #expect(description != nil)
        #expect(description!.count <= 200)
        #expect(description!.hasSuffix("..."))
    }

    @Test("Returns nil for missing README")
    func missingReadme() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "no-readme", files: [:])
        defer { try? FileManager.default.removeItem(at: dir) }

        let description = discovery.extractDescriptionFromReadme(in: dir)

        #expect(description == nil)
    }

    @Test("Skips HTML comments and tags")
    func skipsHtmlContent() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "html-plugin", files: [
            "README.md": """
            # Plugin

            <!-- This is a comment -->
            <div align="center">
            <img src="logo.png" />
            </div>

            This is the actual description.
            """,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let description = discovery.extractDescriptionFromReadme(in: dir)

        #expect(description == "This is the actual description.")
    }

    @Test("Handles multiline paragraph")
    func handlesMultilineParagraph() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "multiline-plugin", files: [
            "README.md": """
            # Plugin

            This is a description that spans
            multiple lines but should be
            joined together.

            ## Next section
            """,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let description = discovery.extractDescriptionFromReadme(in: dir)

        #expect(description == "This is a description that spans multiple lines but should be joined together.")
    }
}

// MARK: - Full Metadata Discovery Tests

@Suite("PluginMetadataDiscovery - discoverPluginMetadata")
struct FullMetadataDiscoveryTests {
    let discovery = PluginMetadataDiscovery()

    init() {
        try? FileManager.default.createDirectory(at: MetadataTestFixtures.tempDir, withIntermediateDirectories: true)
    }

    @Test("Uses manifest metadata when available")
    func usesManifestMetadata() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "manifest-plugin", files: [:])
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create a manifest with plugin entry
        let manifest = MarketplaceManifest(
            name: "TestMarketplace",
            version: "1.0.0",
            metadata: nil,
            plugins: [
                MarketplaceManifest.PluginEntry(name: "manifest-plugin", version: "2.0.0", description: "From manifest"),
            ]
        )

        let metadata = discovery.discoverPluginMetadata(
            pluginDirectory: dir,
            pluginName: "manifest-plugin",
            marketplaceManifest: manifest
        )

        #expect(metadata.version == "2.0.0")
        #expect(metadata.description == "From manifest")
    }

    @Test("Falls back to JSON files when no manifest")
    func fallsBackToJsonFiles() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "json-fallback", files: [
            "info.json": """
            {
                "version": "1.5.0",
                "description": "From JSON file"
            }
            """,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let metadata = discovery.discoverPluginMetadata(
            pluginDirectory: dir,
            pluginName: "json-fallback",
            marketplaceManifest: nil
        )

        #expect(metadata.version == "1.5.0")
        #expect(metadata.description == "From JSON file")
    }

    @Test("Falls back to README when no JSON description")
    func fallsBackToReadme() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "readme-fallback", files: [
            "info.json": """
            {
                "version": "1.0.0"
            }
            """,
            "README.md": """
            # Plugin

            This description comes from README.
            """,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let metadata = discovery.discoverPluginMetadata(
            pluginDirectory: dir,
            pluginName: "readme-fallback",
            marketplaceManifest: nil
        )

        #expect(metadata.version == "1.0.0")
        #expect(metadata.description == "This description comes from README.")
    }

    @Test("Combines metadata from multiple sources")
    func combinesMultipleSources() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "combined-plugin", files: [
            "info.json": """
            {
                "skills": ["skill1", "skill2"]
            }
            """,
            "README.md": """
            # Plugin

            Description from README.
            """,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let manifest = MarketplaceManifest(
            name: "TestMarketplace",
            version: "1.0.0",
            metadata: nil,
            plugins: [
                MarketplaceManifest.PluginEntry(name: "combined-plugin", version: "3.0.0", description: nil),
            ]
        )

        let metadata = discovery.discoverPluginMetadata(
            pluginDirectory: dir,
            pluginName: "combined-plugin",
            marketplaceManifest: manifest
        )

        // Version from manifest
        #expect(metadata.version == "3.0.0")
        // Description from README (manifest has nil)
        #expect(metadata.description == "Description from README.")
        // Skills from JSON
        #expect(metadata.skills.count == 2)
    }

    @Test("Returns empty metadata when nothing found")
    func returnsEmptyWhenNothingFound() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "empty-plugin", files: [:])
        defer { try? FileManager.default.removeItem(at: dir) }

        let metadata = discovery.discoverPluginMetadata(
            pluginDirectory: dir,
            pluginName: "empty-plugin",
            marketplaceManifest: nil
        )

        #expect(metadata.version == nil)
        #expect(metadata.description == nil)
        #expect(metadata.skills.isEmpty)
    }
}

// MARK: - Manifest Loading Tests

@Suite("PluginMetadataDiscovery - loadMarketplaceManifest")
struct ManifestLoadingTests {
    let discovery = PluginMetadataDiscovery()

    init() {
        try? FileManager.default.createDirectory(at: MetadataTestFixtures.tempDir, withIntermediateDirectories: true)
    }

    @Test("Loads manifest from .claude-plugin/marketplace.json")
    func loadsFromClaudePluginMarketplace() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "manifest-test-1", files: [
            ".claude-plugin/marketplace.json": """
            {
                "name": "TestMarketplace",
                "version": "1.0.0",
                "plugins": [
                    {"name": "plugin1", "version": "1.0.0", "description": "Plugin 1"}
                ]
            }
            """,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let manifest = discovery.loadMarketplaceManifest(from: dir)

        #expect(manifest != nil)
        #expect(manifest?.name == "TestMarketplace")
        #expect(manifest?.plugins?.count == 1)
    }

    @Test("Loads manifest from root marketplace.json")
    func loadsFromRootMarketplace() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "manifest-test-2", files: [
            "marketplace.json": """
            {
                "name": "RootMarketplace",
                "version": "2.0.0"
            }
            """,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let manifest = discovery.loadMarketplaceManifest(from: dir)

        #expect(manifest != nil)
        #expect(manifest?.name == "RootMarketplace")
    }

    @Test("Loads manifest from .claude-plugin/plugin.json")
    func loadsFromClaudePluginPlugin() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "manifest-test-3", files: [
            ".claude-plugin/plugin.json": """
            {
                "name": "PluginManifest",
                "version": "3.0.0"
            }
            """,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let manifest = discovery.loadMarketplaceManifest(from: dir)

        #expect(manifest != nil)
        #expect(manifest?.name == "PluginManifest")
    }

    @Test("Loads manifest from root plugin.json")
    func loadsFromRootPlugin() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "manifest-test-4", files: [
            "plugin.json": """
            {
                "name": "RootPlugin",
                "version": "4.0.0"
            }
            """,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let manifest = discovery.loadMarketplaceManifest(from: dir)

        #expect(manifest != nil)
        #expect(manifest?.name == "RootPlugin")
    }

    @Test("Prioritizes .claude-plugin/marketplace.json over others")
    func prioritizesClaudePluginMarketplace() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "manifest-priority", files: [
            ".claude-plugin/marketplace.json": """
            {
                "name": "Priority1"
            }
            """,
            "marketplace.json": """
            {
                "name": "Priority2"
            }
            """,
            "plugin.json": """
            {
                "name": "Priority3"
            }
            """,
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let manifest = discovery.loadMarketplaceManifest(from: dir)

        #expect(manifest?.name == "Priority1")
    }

    @Test("Returns nil for missing manifest")
    func missingManifest() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "no-manifest", files: [:])
        defer { try? FileManager.default.removeItem(at: dir) }

        let manifest = discovery.loadMarketplaceManifest(from: dir)

        #expect(manifest == nil)
    }

    @Test("Handles malformed manifest JSON gracefully")
    func malformedManifest() {
        let dir = MetadataTestFixtures.createPluginDirectory(name: "bad-manifest", files: [
            "marketplace.json": "{ not valid json }",
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let manifest = discovery.loadMarketplaceManifest(from: dir)

        #expect(manifest == nil)
    }
}

// MARK: - PluginMetadata Tests

@Suite("PluginMetadata")
struct PluginMetadataTests {
    @Test("Default initialization has nil values and empty skills")
    func defaultInit() {
        let metadata = PluginMetadata()

        #expect(metadata.version == nil)
        #expect(metadata.description == nil)
        #expect(metadata.skills.isEmpty)
    }

    @Test("Can initialize with all values")
    func fullInit() {
        let metadata = PluginMetadata(
            version: "1.0.0",
            description: "Test description",
            skills: ["skill1", "skill2"]
        )

        #expect(metadata.version == "1.0.0")
        #expect(metadata.description == "Test description")
        #expect(metadata.skills == ["skill1", "skill2"])
    }
}

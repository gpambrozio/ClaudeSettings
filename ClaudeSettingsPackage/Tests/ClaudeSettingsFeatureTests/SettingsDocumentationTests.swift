import Foundation
import Testing
@testable import ClaudeSettingsFeature

// MARK: - Documentation Loading Tests

@Suite("Settings Documentation Loading")
struct SettingsDocumentationLoadingTests {
    @Test("Documentation loads successfully from bundle")
    func documentationLoading() async throws {
        let loader = DocumentationLoader()

        await loader.load()

        // Verify documentation loaded
        let docs = await MainActor.run { loader.documentation }
        #expect(docs != nil)

        // Verify no errors
        let error = await MainActor.run { loader.error }
        #expect(error == nil)

        // Verify not loading
        let isLoading = await MainActor.run { loader.isLoading }
        #expect(isLoading == false)
    }

    @Test("Documentation contains expected structure")
    func documentationStructure() async throws {
        let loader = DocumentationLoader()
        await loader.load()

        let docs = try #require(await MainActor.run { loader.documentation })

        // Verify version exists
        #expect(!docs.version.isEmpty)

        // Verify categories exist
        #expect(!docs.categories.isEmpty)

        // Verify tools exist
        #expect(!docs.tools.isEmpty)

        // Verify best practices exist
        #expect(!docs.bestPractices.isEmpty)
    }

    @Test("Documentation doesn't reload if already loaded")
    func noReloadWhenLoaded() async throws {
        let loader = DocumentationLoader()

        // Load once
        await loader.load()
        let firstDocs = await MainActor.run { loader.documentation }

        // Try to load again
        await loader.load()
        let secondDocs = await MainActor.run { loader.documentation }

        // Should be the same instance (not reloaded)
        #expect(firstDocs?.version == secondDocs?.version)
    }
}

// MARK: - Documentation Lookup Tests

@Suite("Settings Documentation Lookup")
struct SettingsDocumentationLookupTests {
    var loader: DocumentationLoader

    init() async throws {
        self.loader = DocumentationLoader()
        await loader.load()

        // Ensure documentation loaded
        let docs = await MainActor.run { loader.documentation }
        try #require(docs != nil)
    }

    @Test("Find documentation for existing setting")
    func findExistingSetting() async throws {
        let doc = await MainActor.run {
            loader.documentation(for: "permissions.allow")
        }

        #expect(doc != nil)
        #expect(doc?.key == "permissions.allow")
        #expect(doc?.type == "array")
    }

    @Test("Return nil for non-existent setting")
    func findNonExistentSetting() async throws {
        let doc = await MainActor.run {
            loader.documentation(for: "nonexistent.setting.key")
        }

        #expect(doc == nil)
    }

    @Test("Find documentation for model setting")
    func findModelSetting() async throws {
        let doc = await MainActor.run {
            loader.documentation(for: "model")
        }

        #expect(doc != nil)
        #expect(doc?.key == "model")
        #expect(doc?.type == "string")
    }

    @Test("Find documentation for sandbox setting")
    func findSandboxSetting() async throws {
        let doc = await MainActor.run {
            loader.documentation(for: "sandbox.enabled")
        }

        #expect(doc != nil)
        #expect(doc?.key == "sandbox.enabled")
        #expect(doc?.type == "boolean")
    }
}

// MARK: - Documentation Content Tests

@Suite("Settings Documentation Content")
struct SettingsDocumentationContentTests {
    var documentation: SettingsDocumentation

    init() async throws {
        let loader = DocumentationLoader()
        await loader.load()
        self.documentation = try #require(await MainActor.run { loader.documentation })
    }

    @Test("All categories have unique IDs")
    func uniqueCategoryIDs() {
        let categoryIDs = documentation.categories.map { $0.id }
        let uniqueIDs = Set(categoryIDs)
        #expect(categoryIDs.count == uniqueIDs.count)
    }

    @Test("All settings have unique keys")
    func uniqueSettingKeys() {
        var allKeys: [String] = []
        for category in documentation.categories {
            allKeys.append(contentsOf: category.settings.map { $0.key })
        }

        let uniqueKeys = Set(allKeys)
        #expect(allKeys.count == uniqueKeys.count)
    }

    @Test("All examples have unique UUIDs")
    func uniqueExampleIDs() {
        var allIDs: [UUID] = []
        for category in documentation.categories {
            for setting in category.settings {
                allIDs.append(contentsOf: setting.examples.map { $0.id })
            }
        }

        let uniqueIDs = Set(allIDs)
        #expect(allIDs.count == uniqueIDs.count)
    }

    @Test("Settings with enum values have type description")
    func enumTypeDescription() {
        // Find a setting with enum values
        let forceLoginMethod = documentation.documentation(for: "forceLoginMethod")
        #expect(forceLoginMethod != nil)
        #expect(forceLoginMethod?.enumValues != nil)
        #expect(forceLoginMethod?.typeDescription.contains("|") == true)
    }

    @Test("Settings with item type have generic type description")
    func itemTypeDescription() {
        // Find a setting with item type (array)
        let permissionsAllow = documentation.documentation(for: "permissions.allow")
        #expect(permissionsAllow != nil)
        #expect(permissionsAllow?.itemType != nil)
        #expect(permissionsAllow?.typeDescription.contains("<") == true)
        #expect(permissionsAllow?.typeDescription.contains(">") == true)
    }

    @Test("Settings matching prefix returns correct results")
    func settingsMatchingPrefix() {
        let permissionSettings = documentation.settings(matching: "permissions.")

        // Should find all permission settings
        #expect(!permissionSettings.isEmpty)

        // All should start with "permissions."
        for setting in permissionSettings {
            #expect(setting.key.hasPrefix("permissions."))
        }
    }

    @Test("Settings matching non-existent prefix returns empty")
    func settingsMatchingNonExistentPrefix() {
        let results = documentation.settings(matching: "nonexistent.prefix.")
        #expect(results.isEmpty)
    }
}

// MARK: - Tool Documentation Tests

@Suite("Tool Documentation")
struct ToolDocumentationTests {
    var documentation: SettingsDocumentation

    init() async throws {
        let loader = DocumentationLoader()
        await loader.load()
        self.documentation = try #require(await MainActor.run { loader.documentation })
    }

    @Test("All tools have unique names")
    func uniqueToolNames() {
        let toolNames = documentation.tools.map { $0.name }
        let uniqueNames = Set(toolNames)
        #expect(toolNames.count == uniqueNames.count)
    }

    @Test("Tool documentation contains expected tools")
    func expectedTools() {
        let toolNames = documentation.tools.map { $0.name }

        // Verify some expected tools are present
        #expect(toolNames.contains("Bash"))
        #expect(toolNames.contains("Read"))
        #expect(toolNames.contains("Write"))
        #expect(toolNames.contains("Edit"))
    }
}

// MARK: - Best Practices Tests

@Suite("Best Practices Documentation")
struct BestPracticesTests {
    var documentation: SettingsDocumentation

    init() async throws {
        let loader = DocumentationLoader()
        await loader.load()
        self.documentation = try #require(await MainActor.run { loader.documentation })
    }

    @Test("Best practices have unique titles")
    func uniqueBestPracticeTitles() {
        let titles = documentation.bestPractices.map { $0.title }
        let uniqueTitles = Set(titles)
        #expect(titles.count == uniqueTitles.count)
    }

    @Test("Best practices are not empty")
    func bestPracticesNotEmpty() {
        #expect(!documentation.bestPractices.isEmpty)

        for practice in documentation.bestPractices {
            #expect(!practice.title.isEmpty)
            #expect(!practice.description.isEmpty)
        }
    }
}

// MARK: - Error Handling Tests

@Suite("Documentation Error Handling")
struct DocumentationErrorTests {
    @Test("Error description for file not found")
    func fileNotFoundError() {
        let error = DocumentationError.fileNotFound
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description?.contains("not found") == true)
    }

    @Test("Error description for decoding failed")
    func decodingFailedError() {
        let underlyingError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let error = DocumentationError.decodingFailed(underlyingError)
        let description = error.errorDescription

        #expect(description != nil)
        #expect(description?.contains("decode") == true)
    }
}

// MARK: - Performance Tests

@Suite("Documentation Performance")
struct DocumentationPerformanceTests {
    @Test("Documentation lookup is fast (O(1))")
    func lookupPerformance() async throws {
        let loader = DocumentationLoader()
        await loader.load()
        let docs = try #require(await MainActor.run { loader.documentation })

        // Perform 1000 lookups - should complete quickly with O(1) dictionary lookup
        let startTime = Date()

        for _ in 0..<1_000 {
            _ = docs.documentation(for: "permissions.allow")
            _ = docs.documentation(for: "model")
            _ = docs.documentation(for: "sandbox.enabled")
            _ = docs.documentation(for: "nonexistent.key")
        }

        let elapsed = Date().timeIntervalSince(startTime)

        // 4000 lookups should complete in well under 1 second with O(1) lookup
        #expect(elapsed < 1.0)
    }
}

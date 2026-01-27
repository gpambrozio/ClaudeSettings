import Foundation
import Testing
@testable import ClaudeSettingsFeature

// MARK: - Pending Edit Validation Tests

@Suite("MarketplacePendingEdit Validation")
struct MarketplacePendingEditValidationTests {
    @Test("Empty name is invalid")
    func emptyNameInvalid() {
        let edit = MarketplacePendingEdit(name: "", sourceType: "github", repo: "test/repo")

        #expect(edit.validationError != nil)
        #expect(edit.validationError?.contains("Name") == true)
    }

    @Test("GitHub source without repo is invalid")
    func githubWithoutRepoInvalid() {
        let edit = MarketplacePendingEdit(name: "Test", sourceType: "github", repo: "")

        #expect(edit.validationError != nil)
        #expect(edit.validationError?.contains("Repository") == true)
    }

    @Test("Directory source without path is invalid")
    func directoryWithoutPathInvalid() {
        let edit = MarketplacePendingEdit(name: "Test", sourceType: "directory", path: "")

        #expect(edit.validationError != nil)
        #expect(edit.validationError?.contains("Path") == true)
    }

    @Test("Valid GitHub edit has no error")
    func validGithubEdit() {
        let edit = MarketplacePendingEdit(name: "Test", sourceType: "github", repo: "owner/repo")

        #expect(edit.validationError == nil)
    }

    @Test("Valid directory edit has no error")
    func validDirectoryEdit() {
        let edit = MarketplacePendingEdit(name: "Test", sourceType: "directory", path: "/path/to/plugins")

        #expect(edit.validationError == nil)
    }

    @Test("toMarketplace creates correct marketplace")
    func toMarketplaceCreatesCorrect() {
        let edit = MarketplacePendingEdit(
            name: "MyMarket",
            sourceType: "github",
            repo: "myorg/plugins",
            ref: "v1.0",
            isNew: true
        )

        let marketplace = edit.toMarketplace()

        #expect(marketplace.name == "MyMarket")
        #expect(marketplace.source.source == "github")
        #expect(marketplace.source.repo == "myorg/plugins")
        #expect(marketplace.source.ref == "v1.0")
    }

    @Test("Creates from existing marketplace")
    func createsFromExisting() {
        let source = MarketplaceSource(source: "github", repo: "original/repo", ref: "main")
        let marketplace = KnownMarketplace(
            name: "OriginalMarket",
            source: source,
            dataSource: .global,
            installLocation: "/some/path"
        )

        let edit = MarketplacePendingEdit(from: marketplace)

        #expect(edit.name == "OriginalMarket")
        #expect(edit.sourceType == "github")
        #expect(edit.repo == "original/repo")
        #expect(edit.ref == "main")
        #expect(edit.isNew == false)
        #expect(edit.original?.name == "OriginalMarket")
    }
}

// MARK: - Edge Cases

@Suite("MarketplacePendingEdit Edge Cases")
struct MarketplacePendingEditEdgeCaseTests {
    @Test("Whitespace-only name is invalid")
    func whitespaceOnlyNameInvalid() {
        let edit = MarketplacePendingEdit(name: "   \t\n  ", sourceType: "github", repo: "test/repo")

        #expect(edit.validationError != nil)
        #expect(edit.validationError?.contains("Name") == true)
    }

    @Test("Whitespace-only repo is invalid for GitHub")
    func whitespaceOnlyRepoInvalid() {
        let edit = MarketplacePendingEdit(name: "Test", sourceType: "github", repo: "   \t  ")

        #expect(edit.validationError != nil)
        #expect(edit.validationError?.contains("Repository") == true)
    }

    @Test("Whitespace-only path is invalid for directory")
    func whitespaceOnlyPathInvalid() {
        let edit = MarketplacePendingEdit(name: "Test", sourceType: "directory", path: "   \n  ")

        #expect(edit.validationError != nil)
        #expect(edit.validationError?.contains("Path") == true)
    }

    @Test("toMarketplace handles empty optional fields")
    func toMarketplaceHandlesEmptyOptionals() {
        let edit = MarketplacePendingEdit(
            name: "TestMarket",
            sourceType: "github",
            repo: "test/repo",
            path: "",
            ref: "",
            isNew: true
        )

        let marketplace = edit.toMarketplace()

        #expect(marketplace.source.path == nil)
        #expect(marketplace.source.ref == nil)
    }

    @Test("toMarketplace sets directory path only for directory source")
    func toMarketplaceSetsPathForDirectory() {
        var edit = MarketplacePendingEdit(name: "Test", sourceType: "directory", path: "/path/to/plugins")
        edit.repo = "should-be-ignored"

        let marketplace = edit.toMarketplace()

        #expect(marketplace.source.path == "/path/to/plugins")
        #expect(marketplace.source.repo == nil)
    }

    @Test("toMarketplace sets repo only for github source")
    func toMarketplaceSetsRepoForGithub() {
        var edit = MarketplacePendingEdit(name: "Test", sourceType: "github", repo: "owner/repo")
        edit.path = "/should-be-ignored"

        let marketplace = edit.toMarketplace()

        #expect(marketplace.source.repo == "owner/repo")
        #expect(marketplace.source.path == nil)
    }

    @Test("toMarketplace preserves dataSource from original")
    func toMarketplacePreservesDataSource() {
        let original = KnownMarketplace(
            name: "Original",
            source: MarketplaceSource(source: "github", repo: "old/repo"),
            dataSource: .both,
            installLocation: "/path"
        )

        var edit = MarketplacePendingEdit(from: original)
        edit.repo = "new/repo"

        let marketplace = edit.toMarketplace()

        #expect(marketplace.dataSource == .both)
    }

    @Test("Creates from marketplace with nil optional source fields")
    func createsFromMarketplaceWithNilFields() {
        let source = MarketplaceSource(source: "github", repo: nil, path: nil, ref: nil)
        let marketplace = KnownMarketplace(
            name: "MinimalMarket",
            source: source,
            dataSource: .project
        )

        let edit = MarketplacePendingEdit(from: marketplace)

        #expect(edit.name == "MinimalMarket")
        #expect(edit.repo == "")
        #expect(edit.path == "")
        #expect(edit.ref == "")
    }

    @Test("Unknown source type passes validation if name is valid")
    func unknownSourceTypeValidation() {
        let edit = MarketplacePendingEdit(name: "Test", sourceType: "unknown", repo: "", path: "")

        // Unknown source type is not github or directory, so no specific field validation
        #expect(edit.validationError == nil)
    }

    @Test("Name with special characters is valid")
    func nameWithSpecialCharsValid() {
        let edit = MarketplacePendingEdit(name: "My-Plugin_v2.0", sourceType: "github", repo: "test/repo")

        #expect(edit.validationError == nil)
    }
}

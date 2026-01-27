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

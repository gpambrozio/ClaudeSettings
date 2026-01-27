import Foundation
import Testing
@testable import ClaudeSettingsFeature

// MARK: - Marketplace Data Source Tests

@Suite("MarketplaceDataSource Tests")
struct MarketplaceDataSourceTests {
    @Test("Global has correct display name")
    func globalDisplayName() {
        #expect(MarketplaceDataSource.global.displayName == "Global")
    }

    @Test("Project has correct display name")
    func projectDisplayName() {
        #expect(MarketplaceDataSource.project.displayName == "Project")
    }

    @Test("Both has correct display name")
    func bothDisplayName() {
        #expect(MarketplaceDataSource.both.displayName == "Both")
    }
}

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

// MARK: - MarketplaceDataSource Equality Tests

@Suite("MarketplaceDataSource Equality")
struct MarketplaceDataSourceEqualityTests {
    @Test("Same values are equal")
    func sameValuesEqual() {
        #expect(MarketplaceDataSource.global == MarketplaceDataSource.global)
        #expect(MarketplaceDataSource.project == MarketplaceDataSource.project)
        #expect(MarketplaceDataSource.both == MarketplaceDataSource.both)
    }

    @Test("Different values are not equal")
    func differentValuesNotEqual() {
        #expect(MarketplaceDataSource.global != MarketplaceDataSource.project)
        #expect(MarketplaceDataSource.project != MarketplaceDataSource.both)
        #expect(MarketplaceDataSource.global != MarketplaceDataSource.both)
    }
}

// MARK: - MarketplaceDataSource Hashable Tests

@Suite("MarketplaceDataSource Hashable")
struct MarketplaceDataSourceHashableTests {
    @Test("Can be used in Set")
    func canBeUsedInSet() {
        var dataSourceSet: Set<MarketplaceDataSource> = []
        dataSourceSet.insert(.global)
        dataSourceSet.insert(.project)
        dataSourceSet.insert(.both)

        #expect(dataSourceSet.count == 3)
        #expect(dataSourceSet.contains(.global))
        #expect(dataSourceSet.contains(.project))
        #expect(dataSourceSet.contains(.both))
    }

    @Test("Can be used as Dictionary key")
    func canBeUsedAsDictKey() {
        var dict: [MarketplaceDataSource: String] = [:]
        dict[.global] = "Global value"
        dict[.project] = "Project value"

        #expect(dict[.global] == "Global value")
        #expect(dict[.project] == "Project value")
        #expect(dict[.both] == nil)
    }
}

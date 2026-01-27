import Foundation

/// Internal struct for parsing known_marketplaces.json entries
struct RuntimeMarketplaceEntry: Codable {
    let source: MarketplaceSource
    let installLocation: String?
    let lastUpdated: String?
}

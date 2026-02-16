import Foundation

/// A merged marketplace from runtime and/or settings files
public struct KnownMarketplace: Sendable, Identifiable, Hashable {
    /// The marketplace name (e.g., "ClaudeCodePlugins")
    public let name: String

    /// The marketplace source configuration
    public let source: MarketplaceSource

    /// Where this marketplace data came from
    public let dataSource: MarketplaceDataSource

    /// Install location on disk (from runtime file, if available)
    public let installLocation: String?

    /// Last updated timestamp (from runtime file, if available)
    public let lastUpdated: Date?

    public var id: String { name }

    public init(
        name: String,
        source: MarketplaceSource,
        dataSource: MarketplaceDataSource,
        installLocation: String? = nil,
        lastUpdated: Date? = nil
    ) {
        self.name = name
        self.source = source
        self.dataSource = dataSource
        self.installLocation = installLocation
        self.lastUpdated = lastUpdated
    }
}

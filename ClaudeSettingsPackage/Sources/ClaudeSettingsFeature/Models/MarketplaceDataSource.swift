import Foundation

/// Indicates where marketplace data came from
public enum MarketplaceDataSource: Sendable, Hashable {
    /// Only present in known_marketplaces.json (global CLI-managed registry)
    case global

    /// Only present in project's extraKnownMarketplaces (shareable via git)
    case project

    /// Present in both global registry and project settings
    case both

    /// Display name for the data source
    public var displayName: String {
        switch self {
        case .global:
            return "Global"
        case .project:
            return "Project"
        case .both:
            return "Both"
        }
    }
}

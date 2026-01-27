import Foundation

/// Indicates where plugin data came from
public enum PluginDataSource: Sendable, Hashable, Codable {
    /// In global installed_plugins.json
    case global

    /// In project's enabledPlugins setting only
    case project

    /// Exists in cache but not tracked in either global or project
    case cache

    /// Present in both global and project
    case both

    /// Display name for the data source
    public var displayName: String {
        switch self {
        case .global:
            return "Global"
        case .project:
            return "Project"
        case .cache:
            return "Available"
        case .both:
            return "Both"
        }
    }
}

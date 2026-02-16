import Foundation

/// A plugin available for installation from a marketplace
public struct AvailablePlugin: Plugin {
    /// The plugin name (directory name)
    public let name: String

    /// The marketplace this plugin belongs to
    public let marketplace: String

    /// Current version from info.json
    public let version: String?

    /// Description or changelog from info.json
    public let description: String?

    /// Skills provided by this plugin
    public let skills: [String]

    /// Path to the plugin in the marketplace
    public let path: URL

    public init(
        name: String,
        marketplace: String,
        version: String? = nil,
        description: String? = nil,
        skills: [String] = [],
        path: URL
    ) {
        self.name = name
        self.marketplace = marketplace
        self.version = version
        self.description = description
        self.skills = skills
        self.path = path
    }
}

import Foundation

/// An installed plugin from installed_plugins.json or cache
public struct InstalledPlugin: Plugin, Codable {
    /// The plugin name
    public let name: String

    /// The marketplace this plugin came from
    public let marketplace: String

    /// When the plugin was installed (ISO 8601 string)
    public let installedAt: String?

    /// Where this plugin data came from
    public var dataSource: PluginDataSource

    /// Which project file this plugin is declared in (nil if not in any project file)
    public var projectFileLocation: ProjectFileLocation?

    /// The install path (from cache or installed_plugins.json)
    public var installPath: String?

    /// The installed version
    public var version: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case marketplace
        case installedAt
        // dataSource, installPath, version are not persisted to JSON (they come from other sources)
    }

    public init(
        name: String,
        marketplace: String,
        installedAt: String? = nil,
        dataSource: PluginDataSource = .global,
        projectFileLocation: ProjectFileLocation? = nil,
        installPath: String? = nil,
        version: String? = nil
    ) {
        self.name = name
        self.marketplace = marketplace
        self.installedAt = installedAt
        self.dataSource = dataSource
        self.projectFileLocation = projectFileLocation
        self.installPath = installPath
        self.version = version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.marketplace = try container.decode(String.self, forKey: .marketplace)
        self.installedAt = try container.decodeIfPresent(String.self, forKey: .installedAt)
        self.dataSource = .global // Default when decoding from JSON
        self.projectFileLocation = nil
        self.installPath = nil
        self.version = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(marketplace, forKey: .marketplace)
        try container.encodeIfPresent(installedAt, forKey: .installedAt)
        // dataSource, installPath, version are not encoded
    }

    /// Parse the installedAt date string
    public var installedDate: Date? {
        guard let installedAt else { return nil }
        return parseISO8601Date(installedAt)
    }
}

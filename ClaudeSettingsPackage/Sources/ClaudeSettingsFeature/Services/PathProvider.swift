import Foundation

/// Protocol for providing file system paths
/// Abstracts path resolution to allow for testing with custom paths
public protocol PathProvider: Sendable {
    /// The user's home directory
    var homeDirectory: URL { get }

    /// The directory for storing settings backups
    var backupDirectory: URL { get }

    /// The path to the Claude configuration file (~/.claude.json)
    var claudeConfigPath: URL { get }

    /// The global .claude directory (~/.claude/)
    var globalClaudeDirectory: URL { get }

    /// The global settings file (~/.claude/settings.json)
    var globalSettingsPath: URL { get }

    /// All possible enterprise managed settings paths, in priority order
    var enterpriseManagedPaths: [URL] { get }

    /// The plugins directory (~/.claude/plugins/)
    var pluginsDirectory: URL { get }

    /// Runtime marketplace registry (~/.claude/plugins/known_marketplaces.json)
    var knownMarketplacesPath: URL { get }

    /// Installed plugins tracking (~/.claude/plugins/installed_plugins.json)
    var installedPluginsPath: URL { get }

    /// Plugin cache directory (~/.claude/plugins/cache/)
    var pluginsCacheDirectory: URL { get }

    /// Marketplace clones directory (~/.claude/plugins/marketplaces/)
    var marketplaceClonesDirectory: URL { get }
}

/// Default path provider using real system paths
public struct DefaultPathProvider: PathProvider {
    public let homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    public var backupDirectory: URL {
        homeDirectory.appendingPathComponent("Library/Application Support/ClaudeSettings/Backups")
    }

    public var claudeConfigPath: URL {
        homeDirectory.appendingPathComponent(".claude.json")
    }

    public var globalClaudeDirectory: URL {
        homeDirectory.appendingPathComponent(".claude")
    }

    public var globalSettingsPath: URL {
        globalClaudeDirectory.appendingPathComponent("settings.json")
    }

    public var enterpriseManagedPaths: [URL] {
        [
            URL(fileURLWithPath: "/Library/Application Support/Claude/managed-settings.json"),
            homeDirectory.appendingPathComponent(".claude/managed-settings.json"),
        ]
    }

    public var pluginsDirectory: URL {
        globalClaudeDirectory.appendingPathComponent("plugins")
    }

    public var knownMarketplacesPath: URL {
        pluginsDirectory.appendingPathComponent("known_marketplaces.json")
    }

    public var installedPluginsPath: URL {
        pluginsDirectory.appendingPathComponent("installed_plugins.json")
    }

    public var pluginsCacheDirectory: URL {
        pluginsDirectory.appendingPathComponent("cache")
    }

    public var marketplaceClonesDirectory: URL {
        pluginsDirectory.appendingPathComponent("marketplaces")
    }
}

/// Mock path provider for testing with configurable paths
public struct MockPathProvider: PathProvider {
    public let homeDirectory: URL
    public let backupDirectory: URL
    public let claudeConfigPath: URL
    public let globalClaudeDirectory: URL
    public let globalSettingsPath: URL
    public let enterpriseManagedPaths: [URL]
    public let pluginsDirectory: URL
    public let knownMarketplacesPath: URL
    public let installedPluginsPath: URL
    public let pluginsCacheDirectory: URL
    public let marketplaceClonesDirectory: URL

    /// Create a mock path provider with a custom home directory
    /// All other paths are derived from the home directory
    public init(homeDirectory: URL) {
        self.homeDirectory = homeDirectory
        self.backupDirectory = homeDirectory.appendingPathComponent("Backups")
        self.claudeConfigPath = homeDirectory.appendingPathComponent(".claude.json")
        self.globalClaudeDirectory = homeDirectory.appendingPathComponent(".claude")
        self.globalSettingsPath = homeDirectory.appendingPathComponent(".claude/settings.json")
        self.enterpriseManagedPaths = [
            homeDirectory.appendingPathComponent(".claude/managed-settings.json"),
        ]
        self.pluginsDirectory = homeDirectory.appendingPathComponent(".claude/plugins")
        self.knownMarketplacesPath = homeDirectory.appendingPathComponent(".claude/plugins/known_marketplaces.json")
        self.installedPluginsPath = homeDirectory.appendingPathComponent(".claude/plugins/installed_plugins.json")
        self.pluginsCacheDirectory = homeDirectory.appendingPathComponent(".claude/plugins/cache")
        self.marketplaceClonesDirectory = homeDirectory.appendingPathComponent(".claude/plugins/marketplaces")
    }

    /// Create a mock path provider with fully custom paths
    public init(
        homeDirectory: URL,
        backupDirectory: URL,
        claudeConfigPath: URL,
        globalClaudeDirectory: URL,
        enterpriseManagedPaths: [URL],
        globalSettingsPath: URL? = nil,
        pluginsDirectory: URL? = nil,
        knownMarketplacesPath: URL? = nil,
        installedPluginsPath: URL? = nil,
        pluginsCacheDirectory: URL? = nil,
        marketplaceClonesDirectory: URL? = nil
    ) {
        self.homeDirectory = homeDirectory
        self.backupDirectory = backupDirectory
        self.claudeConfigPath = claudeConfigPath
        self.globalClaudeDirectory = globalClaudeDirectory
        self.globalSettingsPath = globalSettingsPath ?? globalClaudeDirectory.appendingPathComponent("settings.json")
        self.enterpriseManagedPaths = enterpriseManagedPaths

        // Default to derived paths if not provided
        let defaultPluginsDir = globalClaudeDirectory.appendingPathComponent("plugins")
        self.pluginsDirectory = pluginsDirectory ?? defaultPluginsDir
        self.knownMarketplacesPath = knownMarketplacesPath ?? defaultPluginsDir.appendingPathComponent("known_marketplaces.json")
        self.installedPluginsPath = installedPluginsPath ?? defaultPluginsDir.appendingPathComponent("installed_plugins.json")
        self.pluginsCacheDirectory = pluginsCacheDirectory ?? defaultPluginsDir.appendingPathComponent("cache")
        self.marketplaceClonesDirectory = marketplaceClonesDirectory ?? defaultPluginsDir.appendingPathComponent("marketplaces")
    }
}

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

    /// All possible enterprise managed settings paths, in priority order
    var enterpriseManagedPaths: [URL] { get }
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

    public var enterpriseManagedPaths: [URL] {
        [
            URL(fileURLWithPath: "/Library/Application Support/Claude/managed-settings.json"),
            homeDirectory.appendingPathComponent(".claude/managed-settings.json"),
        ]
    }
}

/// Mock path provider for testing with configurable paths
public struct MockPathProvider: PathProvider {
    public let homeDirectory: URL
    public let backupDirectory: URL
    public let claudeConfigPath: URL
    public let globalClaudeDirectory: URL
    public let enterpriseManagedPaths: [URL]

    /// Create a mock path provider with a custom home directory
    /// All other paths are derived from the home directory
    public init(homeDirectory: URL) {
        self.homeDirectory = homeDirectory
        self.backupDirectory = homeDirectory.appendingPathComponent("Backups")
        self.claudeConfigPath = homeDirectory.appendingPathComponent(".claude.json")
        self.globalClaudeDirectory = homeDirectory.appendingPathComponent(".claude")
        self.enterpriseManagedPaths = [
            homeDirectory.appendingPathComponent(".claude/managed-settings.json"),
        ]
    }

    /// Create a mock path provider with fully custom paths
    public init(
        homeDirectory: URL,
        backupDirectory: URL,
        claudeConfigPath: URL,
        globalClaudeDirectory: URL,
        enterpriseManagedPaths: [URL]
    ) {
        self.homeDirectory = homeDirectory
        self.backupDirectory = backupDirectory
        self.claudeConfigPath = claudeConfigPath
        self.globalClaudeDirectory = globalClaudeDirectory
        self.enterpriseManagedPaths = enterpriseManagedPaths
    }
}

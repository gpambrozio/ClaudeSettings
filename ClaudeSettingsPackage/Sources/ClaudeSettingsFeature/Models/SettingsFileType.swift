import Foundation

/// Enum representing the different types of Claude Code settings files
/// with their precedence in the configuration hierarchy
///
/// Cases are ordered from lowest to highest precedence.
/// The raw Int value represents the precedence level (higher = higher precedence).
public enum SettingsFileType: Int, Codable, CaseIterable, Sendable, Hashable {
    // Memory files (lowest precedence)
    case globalMemory = 0
    case projectMemory
    case projectLocalMemory

    // Settings files (higher precedence)
    case globalSettings
    case globalLocal
    case projectSettings
    case projectLocal

    // Enterprise managed (highest precedence)
    case enterpriseManaged

    /// Precedence level (higher number = higher precedence)
    ///
    /// Settings are merged according to this hierarchy, with higher precedence values overriding lower ones.
    /// Based on Claude Code docs: enterprise > project-local > project-shared > global-local > global
    ///
    /// The precedence is the enum's raw Int value, determined by the case declaration order.
    public var precedence: Int {
        rawValue
    }

    /// Whether this file type is typically checked into version control
    public var isShared: Bool {
        switch self {
        case .enterpriseManaged,
             .globalSettings,
             .projectSettings,
             .globalMemory,
             .projectMemory:
            return true
        case .globalLocal,
             .projectLocal,
             .projectLocalMemory:
            return false
        }
    }

    /// Whether this is a global-level file
    public var isGlobal: Bool {
        switch self {
        case .globalSettings,
             .globalLocal,
             .globalMemory:
            return true
        case .enterpriseManaged,
             .projectSettings,
             .projectLocal,
             .projectMemory,
             .projectLocalMemory:
            return false
        }
    }

    /// The actual filename used on disk
    /// Note: This is different from rawValue, which is a descriptive identifier
    public var filename: String {
        switch self {
        case .enterpriseManaged:
            return "managed-settings.json"
        case .globalSettings,
             .projectSettings:
            return "settings.json"
        case .globalLocal,
             .projectLocal:
            return "settings.local.json"
        case .globalMemory:
            return "CLAUDE.md"
        case .projectMemory:
            return "CLAUDE-project.md"
        case .projectLocalMemory:
            return "CLAUDE.local.md"
        }
    }

    /// Display name for UI presentation
    public var displayName: String {
        switch self {
        case .enterpriseManaged:
            return "Enterprise Managed"
        case .globalSettings:
            return "Global Settings"
        case .globalLocal:
            return "Global Local"
        case .projectSettings:
            return "Project Settings"
        case .projectLocal:
            return "Project Local"
        case .globalMemory:
            return "Global Memory"
        case .projectMemory:
            return "Project Memory"
        case .projectLocalMemory:
            return "Project Local Memory"
        }
    }

    /// Construct the full path for this settings file type
    /// - Parameter baseDirectory: The base directory (home directory for global files, project root for project files)
    /// - Returns: The full URL path to the settings file
    public func path(in baseDirectory: URL) -> URL {
        switch self {
        case .globalMemory,
             .projectMemory,
             .projectLocalMemory:
            // Memory files are at root of directory
            return baseDirectory.appendingPathComponent(filename)
        case .enterpriseManaged,
             .globalSettings,
             .globalLocal,
             .projectSettings,
             .projectLocal:
            // Settings files are in .claude subdirectory
            return baseDirectory.appendingPathComponent(".claude/\(filename)")
        }
    }

    /// Returns all possible paths for enterprise managed settings
    /// Enterprise settings can exist in system-wide or user-specific locations
    /// - Parameter homeDirectory: The user's home directory
    /// - Returns: Array of possible enterprise settings paths, in priority order
    public static func enterpriseManagedPaths(homeDirectory: URL) -> [URL] {
        [
            URL(fileURLWithPath: "/Library/Application Support/Claude/managed-settings.json"),
            homeDirectory.appendingPathComponent(".claude/managed-settings.json"),
        ]
    }
}

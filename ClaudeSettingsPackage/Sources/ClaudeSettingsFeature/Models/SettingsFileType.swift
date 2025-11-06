import Foundation

/// Enum representing the different types of Claude Code settings files
/// with their precedence in the configuration hierarchy
public enum SettingsFileType: String, Codable, CaseIterable, Sendable, Hashable {
    case enterpriseManaged
    case globalSettings
    case globalLocal
    case projectSettings
    case projectLocal
    case globalMemory
    case projectMemory
    case projectLocalMemory

    /// Precedence level (higher number = higher precedence)
    /// Based on Claude Code docs: enterprise > project-local > project-shared > global-local > global
    public var precedence: Int {
        switch self {
        case .enterpriseManaged: return 100 // Highest: cannot be overridden
        case .projectLocal: return 80 // Project-specific personal settings
        case .projectSettings: return 60 // Team-shared project settings
        case .globalLocal: return 40 // Personal global settings
        case .globalSettings: return 20 // Global defaults (lowest)
        case .projectLocalMemory: return 15 // Memory files (lower than settings)
        case .projectMemory: return 10
        case .globalMemory: return 5
        }
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
        case .enterpriseManaged:
            // Enterprise managed files are in .claude subdirectory
            return baseDirectory.appendingPathComponent(".claude/\(filename)")
        case .globalSettings,
             .globalLocal:
            // Global settings are in ~/.claude/ subdirectory
            return baseDirectory.appendingPathComponent(".claude/\(filename)")
        case .projectSettings,
             .projectLocal:
            // Project settings are in .claude/ subdirectory
            return baseDirectory.appendingPathComponent(".claude/\(filename)")
        case .globalMemory:
            // Global memory file is at root of home directory
            return baseDirectory.appendingPathComponent(filename)
        case .projectMemory,
             .projectLocalMemory:
            // Project memory files are at root of project directory
            return baseDirectory.appendingPathComponent(filename)
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

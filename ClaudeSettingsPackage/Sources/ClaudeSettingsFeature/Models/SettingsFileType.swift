import Foundation

/// Enum representing the different types of Claude Code settings files
/// with their precedence in the configuration hierarchy
public enum SettingsFileType: String, Codable, CaseIterable, Sendable, Hashable {
    case enterpriseManaged = "managed-settings.json"
    case globalSettings = "settings.json"
    case globalLocal = "settings.local.json"
    case projectSettings = "project-settings.json"
    case projectLocal = "project-settings.local.json"
    case globalMemory = "CLAUDE.md"
    case projectMemory = "CLAUDE-project.md"
    case projectLocalMemory = "CLAUDE.local.md"

    /// Precedence level (higher number = higher precedence)
    public var precedence: Int {
        switch self {
        case .enterpriseManaged: return 100
        case .globalSettings: return 80
        case .globalLocal: return 85
        case .projectSettings: return 60
        case .projectLocal: return 65
        case .globalMemory: return 40
        case .projectMemory: return 20
        case .projectLocalMemory: return 25
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

    /// File extension
    public var fileExtension: String {
        if rawValue.hasSuffix(".json") {
            return "json"
        } else if rawValue.hasSuffix(".md") {
            return "md"
        }
        return ""
    }

    /// Whether this is a JSON settings file (vs markdown memory file)
    public var isJSONFile: Bool {
        fileExtension == "json"
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
}

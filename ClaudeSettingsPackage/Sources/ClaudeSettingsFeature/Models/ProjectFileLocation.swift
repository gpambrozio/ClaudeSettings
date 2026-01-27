import Foundation

/// Indicates which project file a plugin is declared in
public enum ProjectFileLocation: Sendable, Hashable, Codable {
    /// In .claude/settings.json (shareable via git)
    case shared

    /// In .claude/settings.local.json (not shared)
    case local
}

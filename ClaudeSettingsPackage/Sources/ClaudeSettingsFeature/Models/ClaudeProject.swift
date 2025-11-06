import Foundation

/// Represents a Claude Code project with its settings
public struct ClaudeProject: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public let path: URL
    public let claudeDirectory: URL
    public var hasLocalSettings: Bool
    public var hasSharedSettings: Bool
    public var hasClaudeMd: Bool
    public var hasLocalClaudeMd: Bool
    public var lastModified: Date

    public init(
        id: UUID = UUID(),
        name: String,
        path: URL,
        claudeDirectory: URL,
        hasLocalSettings: Bool = false,
        hasSharedSettings: Bool = false,
        hasClaudeMd: Bool = false,
        hasLocalClaudeMd: Bool = false,
        lastModified: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.claudeDirectory = claudeDirectory
        self.hasLocalSettings = hasLocalSettings
        self.hasSharedSettings = hasSharedSettings
        self.hasClaudeMd = hasClaudeMd
        self.hasLocalClaudeMd = hasLocalClaudeMd
        self.lastModified = lastModified
    }

    /// Check if the project directory still exists
    public var exists: Bool {
        FileManager.default.fileExists(atPath: path.path)
    }
}

import Foundation

/// Represents a Claude Code settings file
public struct SettingsFile: Identifiable, Codable, Sendable {
    public let id: UUID
    public let type: SettingsFileType
    public let path: URL
    public var content: [String: SettingValue]
    public var isValid: Bool
    public var validationErrors: [ValidationError]
    public var lastModified: Date
    public let isReadOnly: Bool

    public init(
        id: UUID = UUID(),
        type: SettingsFileType,
        path: URL,
        content: [String: SettingValue] = [:],
        isValid: Bool = true,
        validationErrors: [ValidationError] = [],
        lastModified: Date = Date(),
        isReadOnly: Bool = false
    ) {
        self.id = id
        self.type = type
        self.path = path
        self.content = content
        self.isValid = isValid
        self.validationErrors = validationErrors
        self.lastModified = lastModified
        self.isReadOnly = isReadOnly
    }
}

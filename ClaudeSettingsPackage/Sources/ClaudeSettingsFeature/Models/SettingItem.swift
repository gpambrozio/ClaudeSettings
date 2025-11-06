import Foundation

/// Represents a contribution from a specific source file
public struct SourceContribution: Sendable {
    public let source: SettingsFileType
    public let value: SettingValue

    public init(source: SettingsFileType, value: SettingValue) {
        self.source = source
        self.value = value
    }
}

/// Represents a single setting with its value and source information
public struct SettingItem: Identifiable, Sendable {
    public let id: UUID
    public let key: String
    public let value: SettingValue
    public let source: SettingsFileType
    public let overriddenBy: SettingsFileType?
    public let contributions: [SourceContribution]
    public let isDeprecated: Bool
    public let documentation: String?

    public init(
        id: UUID = UUID(),
        key: String,
        value: SettingValue,
        source: SettingsFileType,
        overriddenBy: SettingsFileType? = nil,
        contributions: [SourceContribution] = [],
        isDeprecated: Bool = false,
        documentation: String? = nil
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.source = source
        self.overriddenBy = overriddenBy
        self.contributions = contributions
        self.isDeprecated = isDeprecated
        self.documentation = documentation
    }

    /// Whether this setting is currently active (not overridden)
    public var isActive: Bool {
        overriddenBy == nil
    }

    /// Whether this setting is additive (combines values from multiple sources)
    /// True for array types that have multiple contributions
    public var isAdditive: Bool {
        if case .array = value {
            return contributions.count > 1
        }
        return false
    }
}

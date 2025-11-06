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

/// Represents a single setting with its value, type, and source information
public struct SettingItem: Identifiable, Sendable {
    public let id: UUID
    public let key: String
    public let value: SettingValue
    public let valueType: SettingValueType
    public let source: SettingsFileType
    public let overriddenBy: SettingsFileType?
    public let contributions: [SourceContribution]
    public let isDeprecated: Bool
    public let documentation: String?

    public init(
        id: UUID = UUID(),
        key: String,
        value: SettingValue,
        valueType: SettingValueType,
        source: SettingsFileType,
        overriddenBy: SettingsFileType? = nil,
        contributions: [SourceContribution] = [],
        isDeprecated: Bool = false,
        documentation: String? = nil
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.valueType = valueType
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
        valueType == .array && contributions.count > 1
    }
}

/// Type of a setting value
public enum SettingValueType: String, Sendable {
    case string
    case boolean
    case number
    case array
    case object
    case null

    /// Initialize from a value
    public init(from value: Any) {
        switch value {
        case is String:
            self = .string
        case is Bool:
            self = .boolean
        case is Int,
             is Double,
             is Float:
            self = .number
        case is [Any]:
            self = .array
        case is [String: Any]:
            self = .object
        default:
            self = .null
        }
    }

    /// Display color for this type
    public var color: String {
        switch self {
        case .string:
            return "blue"
        case .boolean:
            return "green"
        case .number:
            return "orange"
        case .array:
            return "purple"
        case .object:
            return "pink"
        case .null:
            return "gray"
        }
    }
}

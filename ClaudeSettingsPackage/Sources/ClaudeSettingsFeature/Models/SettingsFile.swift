import Foundation

/// Represents a Claude Code settings file
public struct SettingsFile: Identifiable, Codable, Sendable {
    public let id: UUID
    public let type: SettingsFileType
    public let path: URL
    public var content: [String: AnyCodable]
    public var isValid: Bool
    public var validationErrors: [ValidationError]
    public var lastModified: Date
    public let isReadOnly: Bool

    public init(
        id: UUID = UUID(),
        type: SettingsFileType,
        path: URL,
        content: [String: AnyCodable] = [:],
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

/// Type-erased wrapper for Any to make it Codable
public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues(\.value)
        } else {
            self.value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

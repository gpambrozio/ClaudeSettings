import Foundation

/// Type-safe representation of setting values
public enum SettingValue: Codable, Sendable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([SettingValue])
    case object([String: SettingValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([SettingValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: SettingValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unable to decode SettingValue"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    /// Convert to Any for compatibility with existing code
    public var asAny: Any {
        switch self {
        case let .string(value):
            return value
        case let .int(value):
            return value
        case let .double(value):
            return value
        case let .bool(value):
            return value
        case let .array(values):
            return values.map { $0.asAny }
        case let .object(dict):
            return dict.mapValues { $0.asAny }
        case .null:
            return NSNull()
        }
    }

    /// Create a SettingValue from Any
    public init(any value: Any) {
        switch value {
        case let string as String:
            self = .string(string)
        // If we don't do the extra check a 0 integer is also parsed as a `false` boolean
        case let bool as NSNumber where UnicodeScalar(UInt8(bool.objCType.pointee)) == "c":
            self = .bool(bool.boolValue)
        case let int as Int:
            self = .int(int)
        case let double as Double:
            self = .double(double)
        case let float as Float:
            self = .double(Double(float))
        case let array as [Any]:
            self = .array(array.map { SettingValue(any: $0) })
        case let dict as [String: Any]:
            self = .object(dict.mapValues { SettingValue(any: $0) })
        case is NSNull:
            self = .null
        default:
            self = .null
        }
    }

    /// Format value as a string for display
    public func formatted() -> String {
        switch self {
        case let .string(value):
            return "\"\(Self.escapeJSONString(value))\""
        case let .int(value):
            return "\(value)"
        case let .double(value):
            return "\(value)"
        case let .bool(value):
            return value ? "true" : "false"
        case let .array(values):
            if values.isEmpty {
                return "[]"
            }
            let items = values.map { $0.formatted() }.joined(separator: ", ")
            return "[\(items)]"
        case let .object(dict):
            if dict.isEmpty {
                return "{}"
            }
            let items = dict.map { "\"\(Self.escapeJSONString($0))\": \($1.formatted())" }.joined(separator: ", ")
            return "{\(items)}"
        case .null:
            return "null"
        }
    }

    /// Escape special characters in a JSON string
    /// - Parameter string: The string to escape
    /// - Returns: The escaped string suitable for JSON output
    private static func escapeJSONString(_ string: String) -> String {
        var escaped = ""
        for char in string {
            switch char {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            case "\u{08}": escaped += "\\b" // Backspace
            case "\u{0C}": escaped += "\\f" // Form feed
            default:
                // Escape control characters (U+0000 to U+001F) as \uXXXX
                if
                    char.unicodeScalars.count == 1,
                    let scalar = char.unicodeScalars.first,
                    scalar.value <= 0x1F {
                    escaped += String(format: "\\u%04x", scalar.value)
                } else {
                    escaped.append(char)
                }
            }
        }
        return escaped
    }

    /// Get the type name of this value for error messages
    public var typeName: String {
        switch self {
        case .string: "string"
        case .int: "int"
        case .double: "double"
        case .bool: "bool"
        case .array: "array"
        case .object: "object"
        case .null: "null"
        }
    }
}

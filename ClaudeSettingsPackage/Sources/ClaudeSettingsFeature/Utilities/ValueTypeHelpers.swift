import Foundation
import SwiftUI

// MARK: - SettingValue Type Display Extension

public extension SettingValue {
    /// Display name for this value's type
    var typeDisplayName: String {
        switch self {
        case .string: "String"
        case .bool: "Boolean"
        case .int,
             .double: "Number"
        case .array: "Array"
        case .object: "Object"
        case .null: "Null"
        }
    }

    /// Display color for this value's type
    var typeDisplayColor: Color {
        switch self {
        case .string: .blue
        case .bool: .green
        case .int,
             .double: .orange
        case .array: .purple
        case .object: .pink
        case .null: .gray
        }
    }
}

// MARK: - Schema Type Helpers

/// Get display color for a JSON schema type string
/// - Parameter schemaType: The type string from documentation (e.g., "string", "boolean", "integer")
/// - Returns: Color for the type
public func schemaTypeColor(_ schemaType: String) -> Color {
    switch schemaType {
    case "string": .blue
    case "boolean": .green
    case "integer",
         "number": .orange
    case "array": .purple
    case "object": .pink
    default: .gray
    }
}

// MARK: - Validation Results

/// Result of validating a value input
public enum ValidationResult<T> {
    case valid(T)
    case invalid(String)
    case empty

    public var error: String? {
        switch self {
        case let .invalid(message):
            return message
        case .empty:
            return "Value is required"
        case .valid:
            return nil
        }
    }

    public var value: T? {
        if case let .valid(value) = self {
            return value
        }
        return nil
    }
}

// MARK: - Validation Functions

/// Validate an integer input string
/// - Parameter text: The text to validate
/// - Returns: ValidationResult with the parsed Int or error message
public func validateIntegerInput(_ text: String) -> ValidationResult<Int> {
    let trimmed = text.trimmingCharacters(in: .whitespaces)

    guard !trimmed.isEmpty else {
        return .empty
    }

    if let value = Int(trimmed) {
        return .valid(value)
    } else {
        return .invalid("Must be a valid integer")
    }
}

/// Validate a double/number input string
/// - Parameter text: The text to validate
/// - Returns: ValidationResult with the parsed Double or error message
public func validateDoubleInput(_ text: String) -> ValidationResult<Double> {
    let trimmed = text.trimmingCharacters(in: .whitespaces)

    guard !trimmed.isEmpty else {
        return .empty
    }

    if let value = Double(trimmed) {
        return .valid(value)
    } else {
        return .invalid("Must be a valid number")
    }
}

/// Validate a JSON input string
/// - Parameters:
///   - text: The JSON text to validate
///   - expectedType: Optional expected type ("array" or "object") to enforce
/// - Returns: ValidationResult with the parsed SettingValue or error message
public func validateJSONInput(_ text: String, expectedType: String? = nil) -> ValidationResult<SettingValue> {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty else {
        return .empty
    }

    guard let data = trimmed.data(using: .utf8) else {
        return .invalid("Invalid text encoding")
    }

    do {
        let jsonObject = try JSONSerialization.jsonObject(with: data)

        // Verify the type matches if specified
        if let expectedType = expectedType {
            if expectedType == "array" && !(jsonObject is [Any]) {
                return .invalid("Must be a JSON array")
            }
            if expectedType == "object" && !(jsonObject is [String: Any]) {
                return .invalid("Must be a JSON object")
            }
        }

        return .valid(SettingValue(any: jsonObject))
    } catch {
        return .invalid("Invalid JSON syntax")
    }
}

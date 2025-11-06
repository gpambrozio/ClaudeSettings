import Foundation

/// Represents different types of validation errors
public enum ValidationErrorType: String, Codable, Sendable {
    case syntax
    case deprecated
    case conflict
    case permission
    case unknownKey
}

/// Represents a validation error in a settings file
public struct ValidationError: Identifiable, Codable, Sendable {
    public let id: UUID
    public let type: ValidationErrorType
    public let message: String
    public let key: String?
    public let suggestion: String?

    public init(
        id: UUID = UUID(),
        type: ValidationErrorType,
        message: String,
        key: String? = nil,
        suggestion: String? = nil
    ) {
        self.id = id
        self.type = type
        self.message = message
        self.key = key
        self.suggestion = suggestion
    }
}

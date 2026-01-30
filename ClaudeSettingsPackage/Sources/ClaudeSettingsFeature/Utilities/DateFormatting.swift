import Foundation

/// Thread-safe ISO 8601 date parsing using sendable enum wrapper
public enum ISO8601DateParsing: Sendable {
    /// Cached formatter with fractional seconds
    @MainActor
    private static let formatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Cached formatter without fractional seconds
    @MainActor
    private static let formatterStandard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Parse ISO 8601 date strings with optional fractional seconds (MainActor version)
    @MainActor
    public static func parse(_ string: String) -> Date? {
        if let date = formatterWithFractional.date(from: string) {
            return date
        }
        return formatterStandard.date(from: string)
    }

    /// Parse ISO 8601 date strings (non-isolated version, creates new formatters)
    public nonisolated static func parseNonisolated(_ string: String) -> Date? {
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractional.date(from: string) {
            return date
        }

        let formatterStandard = ISO8601DateFormatter()
        formatterStandard.formatOptions = [.withInternetDateTime]
        return formatterStandard.date(from: string)
    }
}

/// Parse ISO 8601 date strings with optional fractional seconds
/// Handles formats like "2026-01-24T00:22:38.588Z" and "2026-01-24T00:22:38Z"
/// Note: Creates new formatters each call for thread safety in non-MainActor contexts
public func parseISO8601Date(_ string: String) -> Date? {
    ISO8601DateParsing.parseNonisolated(string)
}

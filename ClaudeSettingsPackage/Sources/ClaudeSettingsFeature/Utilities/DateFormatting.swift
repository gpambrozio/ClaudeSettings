import Foundation

/// Parse ISO 8601 date strings with optional fractional seconds
/// Handles formats like "2026-01-24T00:22:38.588Z" and "2026-01-24T00:22:38Z"
public func parseISO8601Date(_ string: String) -> Date? {
    // Try with fractional seconds first (most common in JavaScript)
    let formatterWithFractional = ISO8601DateFormatter()
    formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatterWithFractional.date(from: string) {
        return date
    }

    // Fallback to standard format without fractional seconds
    let formatterStandard = ISO8601DateFormatter()
    formatterStandard.formatOptions = [.withInternetDateTime]
    return formatterStandard.date(from: string)
}

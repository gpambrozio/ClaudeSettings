import Foundation

/// Protocol for settings file parsing and serialization
/// Abstracts settings parsing to allow for testing with mock implementations
public protocol SettingsParserProtocol: Actor, Sendable {
    /// Parse a JSON settings file
    /// - Parameters:
    ///   - url: The path to the settings file
    ///   - type: The type of settings file being parsed
    /// - Returns: A parsed SettingsFile with content and metadata
    func parseSettingsFile(at url: URL, type: SettingsFileType) async throws -> SettingsFile

    /// Write a settings file to disk
    /// - Parameter settingsFile: The settings file to write (passed as inout to update originalData)
    func writeSettingsFile(_ settingsFile: inout SettingsFile) async throws
}

// MARK: - SettingsParser Protocol Conformance

extension SettingsParser: SettingsParserProtocol {}

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Transferable representation of one or more settings for drag and drop operations
public struct DraggableSetting: Codable, Transferable, Sendable {
    /// Individual setting entry
    public struct SettingEntry: Codable, Sendable {
        public let key: String
        public let value: SettingValue
        public let sourceFileType: SettingsFileType

        public init(key: String, value: SettingValue, sourceFileType: SettingsFileType) {
            self.key = key
            self.value = value
            self.sourceFileType = sourceFileType
        }
    }

    public let settings: [SettingEntry]

    /// Create a draggable setting for a single setting
    public init(key: String, value: SettingValue, sourceFileType: SettingsFileType) {
        self.settings = [SettingEntry(key: key, value: value, sourceFileType: sourceFileType)]
    }

    /// Create a draggable setting for multiple settings
    public init(settings: [SettingEntry]) {
        self.settings = settings
    }

    /// Convenience accessors for single-setting drag operations
    public var key: String {
        settings.first?.key ?? ""
    }

    public var value: SettingValue {
        settings.first?.value ?? .null
    }

    public var sourceFileType: SettingsFileType {
        settings.first?.sourceFileType ?? .globalSettings
    }

    /// Returns true if this represents a collection of multiple settings
    public var isCollection: Bool {
        settings.count > 1
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .claudeSetting)
    }
}

extension UTType {
    static var claudeSetting: UTType {
        UTType(exportedAs: "com.claude.setting")
    }
}

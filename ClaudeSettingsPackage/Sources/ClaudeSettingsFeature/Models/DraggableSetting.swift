import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Transferable representation of a setting for drag and drop operations
public struct DraggableSetting: Codable, Transferable {
    public let key: String
    public let value: SettingValue
    public let sourceFileType: SettingsFileType

    public init(key: String, value: SettingValue, sourceFileType: SettingsFileType) {
        self.key = key
        self.value = value
        self.sourceFileType = sourceFileType
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

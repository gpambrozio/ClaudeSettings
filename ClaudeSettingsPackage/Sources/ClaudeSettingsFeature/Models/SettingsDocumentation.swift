import Foundation

// MARK: - Settings Documentation Models

/// Documentation for all Claude Code settings
public struct SettingsDocumentation: Codable, Sendable {
    public let version: String
    public let categories: [SettingCategory]
    public let tools: [ToolDocumentation]
    public let bestPractices: [BestPractice]

    /// Find documentation for a specific setting key
    public func documentation(for key: String) -> SettingDocumentation? {
        for category in categories {
            if let setting = category.settings.first(where: { $0.key == key }) {
                return setting
            }
        }
        return nil
    }

    /// Find all settings matching a prefix (e.g., "permissions." returns all permission settings)
    public func settings(matching prefix: String) -> [SettingDocumentation] {
        categories.flatMap { category in
            category.settings.filter { $0.key.hasPrefix(prefix) }
        }
    }
}

/// A category of related settings
public struct SettingCategory: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let platformNote: String?
    public let settings: [SettingDocumentation]

    enum CodingKeys: String, CodingKey {
        case id, name, description, platformNote, settings
    }
}

/// Documentation for a single setting
public struct SettingDocumentation: Codable, Sendable, Identifiable {
    public let key: String
    public let type: String
    public let defaultValue: String?
    public let description: String
    public let enumValues: [String]?
    public let format: String?
    public let itemType: String?
    public let platformNote: String?
    public let relatedEnvVars: [String]?
    public let hookTypes: [String]?
    public let patterns: [String]?
    public let examples: [SettingExample]

    public var id: String { key }

    /// Display-friendly type description
    public var typeDescription: String {
        if let itemType = itemType {
            return "\(type)<\(itemType)>"
        }
        if let enumValues = enumValues {
            return enumValues.joined(separator: " | ")
        }
        return type
    }

    enum CodingKeys: String, CodingKey {
        case key, type, defaultValue, description, enumValues, format
        case itemType, platformNote, relatedEnvVars, hookTypes, patterns, examples
    }
}

/// An example of how to use a setting
public struct SettingExample: Codable, Sendable, Identifiable {
    public let code: String
    public let description: String

    public var id: String { description }
}

/// Documentation for a Claude Code tool
public struct ToolDocumentation: Codable, Sendable, Identifiable {
    public let name: String
    public let requiresPermission: Bool
    public let description: String

    public var id: String { name }
}

/// A best practice recommendation
public struct BestPractice: Codable, Sendable, Identifiable {
    public let title: String
    public let description: String

    public var id: String { title }
}

// MARK: - Documentation Loader

/// Loads and caches settings documentation from the bundle
@MainActor
public final class DocumentationLoader: ObservableObject {
    public static let shared = DocumentationLoader()

    @Published public private(set) var documentation: SettingsDocumentation?
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: Error?

    private init() {}

    /// Load documentation from the bundle
    public func load() async {
        guard documentation == nil else { return }

        isLoading = true
        error = nil

        do {
            guard let url = Bundle.module.url(forResource: "settings-documentation", withExtension: "json") else {
                throw DocumentationError.fileNotFound
            }

            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            documentation = try decoder.decode(SettingsDocumentation.self, from: data)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    /// Find documentation for a setting key
    public func documentation(for key: String) -> SettingDocumentation? {
        documentation?.documentation(for: key)
    }
}

// MARK: - Errors

public enum DocumentationError: LocalizedError {
    case fileNotFound
    case decodingFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Documentation file not found in bundle"
        case .decodingFailed(let error):
            return "Failed to decode documentation: \(error.localizedDescription)"
        }
    }
}

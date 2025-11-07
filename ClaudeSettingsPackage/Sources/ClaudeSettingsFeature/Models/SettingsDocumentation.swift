import Foundation

// MARK: - Settings Documentation Models

/// Documentation for all Claude Code settings
public struct SettingsDocumentation: Codable, Sendable {
    public let version: String
    public let categories: [SettingCategory]
    public let tools: [ToolDocumentation]
    public let bestPractices: [BestPractice]

    /// O(1) lookup dictionary for fast setting retrieval
    private let settingsByKey: [String: SettingDocumentation]

    enum CodingKeys: String, CodingKey {
        case version
        case categories
        case tools
        case bestPractices
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(String.self, forKey: .version)
        self.categories = try container.decode([SettingCategory].self, forKey: .categories)
        self.tools = try container.decode([ToolDocumentation].self, forKey: .tools)
        self.bestPractices = try container.decode([BestPractice].self, forKey: .bestPractices)

        // Build O(1) lookup dictionary
        var dict = [String: SettingDocumentation]()
        for category in categories {
            for setting in category.settings {
                dict[setting.key] = setting
            }
        }
        self.settingsByKey = dict
    }

    /// Find documentation for a specific setting key - O(1) lookup
    public func documentation(for key: String) -> SettingDocumentation? {
        settingsByKey[key]
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
        case id
        case name
        case description
        case platformNote
        case settings
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
        case key
        case type
        case defaultValue
        case description
        case enumValues
        case format
        case itemType
        case platformNote
        case relatedEnvVars
        case hookTypes
        case patterns
        case examples
    }
}

/// An example of how to use a setting
public struct SettingExample: Codable, Sendable, Identifiable {
    public let id: UUID
    public let code: String
    public let description: String

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case description
    }
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
final public class DocumentationLoader: ObservableObject {
    public static let shared = DocumentationLoader()

    @Published public private(set) var documentation: SettingsDocumentation?
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: Error?

    // Internal for testing - nonisolated so tests can create instances
    nonisolated init() { }

    /// Load documentation from the bundle using async I/O
    public func load() async {
        // Check if already loaded
        guard documentation == nil else { return }

        isLoading = true
        error = nil

        do {
            guard let url = Bundle.module.url(forResource: "settings-documentation", withExtension: "json") else {
                throw DocumentationError.fileNotFound
            }

            // Perform file I/O asynchronously (off main thread via URLSession)
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            let loadedDocs = try decoder.decode(SettingsDocumentation.self, from: data)

            // Update state (already on MainActor due to class annotation)
            documentation = loadedDocs
            isLoading = false
        } catch let decodingError as DecodingError {
            error = DocumentationError.decodingFailed(decodingError)
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
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
        case let .decodingFailed(error):
            return "Failed to decode documentation: \(error.localizedDescription)"
        }
    }
}

import Foundation

/// .claude-plugin/marketplace.json structure for parsing marketplace manifest
struct MarketplaceManifest: Codable {
    let name: String?
    let version: String?
    let metadata: Metadata?
    let plugins: [PluginEntry]?

    struct Metadata: Codable {
        let description: String?
    }

    struct PluginEntry: Codable {
        let name: String?
        let version: String?
        let description: String?
        // source can be either a String or an object - we don't need it for descriptions
        // so we just skip decoding it to avoid type mismatch errors

        enum CodingKeys: String, CodingKey {
            case name
            case version
            case description
        }
    }

    /// Find a plugin entry by name
    func plugin(named name: String) -> PluginEntry? {
        plugins?.first { $0.name == name }
    }
}

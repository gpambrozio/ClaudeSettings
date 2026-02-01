import Foundation

/// A single plugin installation entry
struct PluginInstallation: Codable {
    let scope: String
    let installPath: String
    let version: String
    let installedAt: String?
    let lastUpdated: String?
    let gitCommitSha: String?
}

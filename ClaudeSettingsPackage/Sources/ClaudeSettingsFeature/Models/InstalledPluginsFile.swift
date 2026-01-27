import Foundation

/// Root structure for installed_plugins.json
struct InstalledPluginsFile: Codable {
    let version: Int
    let plugins: [String: [PluginInstallation]]
}

import Foundation
import Logging

/// Metadata discovered for a plugin
public struct PluginMetadata: Sendable {
    public var version: String?
    public var description: String?
    public var skills: [String]

    public init(version: String? = nil, description: String? = nil, skills: [String] = []) {
        self.version = version
        self.description = description
        self.skills = skills
    }
}

/// Service for discovering plugin metadata from filesystem
/// Handles flexible plugin detection and metadata extraction
public struct PluginMetadataDiscovery: Sendable {
    private let logger = Logger(label: "com.claudesettings.plugin-metadata")

    public init() { }

    // MARK: - Plugin Detection

    /// Check if a directory looks like a plugin (has common plugin markers)
    /// - Parameter directory: The directory to check
    /// - Returns: True if the directory appears to be a plugin
    public func looksLikePluginDirectory(_ directory: URL) -> Bool {
        let fm = FileManager.default

        // Standard Claude Code plugin markers - any of these suggests it's a plugin
        // See: https://docs.anthropic.com/en/docs/claude-code/plugins
        let markers = [
            ".claude-plugin", // Plugin configuration directory
            "plugin.json", // Plugin manifest
            "SKILL.md", // Skill definition file
            "skills", // Skills directory
            "commands", // Commands directory
            "hooks", // Hooks directory
        ]

        for marker in markers {
            let markerPath = directory.appendingPathComponent(marker)
            if fm.fileExists(atPath: markerPath.path) {
                return true
            }
        }

        return false
    }

    // MARK: - Manifest Loading

    /// Load marketplace manifest from any of the common locations
    /// - Parameter marketplaceURL: The marketplace directory URL
    /// - Returns: The parsed manifest, or nil if not found
    func loadMarketplaceManifest(from marketplaceURL: URL) -> MarketplaceManifest? {
        // Try common manifest locations
        let possiblePaths = [
            marketplaceURL.appendingPathComponent(".claude-plugin/marketplace.json"),
            marketplaceURL.appendingPathComponent("marketplace.json"),
            marketplaceURL.appendingPathComponent(".claude-plugin/plugin.json"),
            marketplaceURL.appendingPathComponent("plugin.json"),
        ]

        for path in possiblePaths where FileManager.default.fileExists(atPath: path.path) {
            do {
                let data = try Data(contentsOf: path)
                return try JSONDecoder().decode(MarketplaceManifest.self, from: data)
            } catch {
                logger.debug("Failed to parse manifest at \(path.lastPathComponent): \(error)")
            }
        }

        return nil
    }

    // MARK: - Metadata Discovery

    /// Discover plugin metadata using a flexible, multi-source approach
    /// - Parameters:
    ///   - pluginDirectory: The plugin directory to scan
    ///   - pluginName: The name of the plugin
    ///   - marketplaceManifest: Optional marketplace manifest for additional metadata
    /// - Returns: Discovered metadata for the plugin
    func discoverPluginMetadata(
        pluginDirectory: URL,
        pluginName: String,
        marketplaceManifest: MarketplaceManifest?
    ) -> PluginMetadata {
        var metadata = PluginMetadata()

        // Strategy 1: Check marketplace manifest for this plugin
        if let pluginEntry = marketplaceManifest?.plugin(named: pluginName) {
            metadata.version = pluginEntry.version
            metadata.description = pluginEntry.description
        }

        // Strategy 2: Search for JSON files and extract metadata
        let jsonMetadata = searchJSONFilesForMetadata(in: pluginDirectory)
        if metadata.version == nil {
            metadata.version = jsonMetadata.version
        }
        if metadata.description == nil {
            metadata.description = jsonMetadata.description
        }
        if metadata.skills.isEmpty {
            metadata.skills = jsonMetadata.skills
        }

        // Strategy 3: Fall back to README for description
        if metadata.description == nil {
            metadata.description = extractDescriptionFromReadme(in: pluginDirectory)
        }

        return metadata
    }

    /// Search JSON files in a directory for metadata (up to 2 levels deep)
    /// - Parameter directory: The directory to search
    /// - Returns: Metadata extracted from JSON files
    public func searchJSONFilesForMetadata(in directory: URL) -> PluginMetadata {
        var metadata = PluginMetadata()
        let fm = FileManager.default

        // Find JSON files (up to 2 levels deep)
        var jsonFiles: [URL] = []

        func collectJSONFiles(in dir: URL, depth: Int) {
            guard
                depth <= 2,
                let contents = try? fm.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: []
                )
            else { return }

            for item in contents {
                var isDir: ObjCBool = false
                fm.fileExists(atPath: item.path, isDirectory: &isDir)

                if isDir.boolValue {
                    // Recurse into subdirectories (especially .claude-plugin)
                    if depth < 2 {
                        collectJSONFiles(in: item, depth: depth + 1)
                    }
                } else if item.pathExtension.lowercased() == "json" {
                    jsonFiles.append(item)
                }
            }
        }

        collectJSONFiles(in: directory, depth: 0)

        // Prioritize certain files (only standard plugin manifest files)
        let priorityOrder = ["plugin.json", "package.json"]
        jsonFiles.sort { a, b in
            let aIndex = priorityOrder.firstIndex(of: a.lastPathComponent) ?? priorityOrder.count
            let bIndex = priorityOrder.firstIndex(of: b.lastPathComponent) ?? priorityOrder.count
            return aIndex < bIndex
        }

        // Common keys that might contain description
        let descriptionKeys = ["description", "summary", "about", "overview", "changes"]
        let versionKeys = ["version", "latestVersion"]
        let skillsKeys = ["skills"]

        for jsonFile in jsonFiles {
            guard
                let data = try? Data(contentsOf: jsonFile),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            // Extract description
            if metadata.description == nil {
                for key in descriptionKeys {
                    if let desc = json[key] as? String, !desc.isEmpty {
                        metadata.description = desc
                        break
                    }
                }

                // Check nested structures (e.g., versions[0].changes)
                if
                    metadata.description == nil,
                    let versions = json["versions"] as? [[String: Any]],
                    let firstVersion = versions.first,
                    let changes = firstVersion["changes"] as? String {
                    metadata.description = changes
                }
            }

            // Extract version
            if metadata.version == nil {
                for key in versionKeys {
                    if let ver = json[key] as? String, !ver.isEmpty {
                        metadata.version = ver
                        break
                    }
                }

                // Check nested versions array
                if
                    metadata.version == nil,
                    let versions = json["versions"] as? [[String: Any]],
                    let firstVersion = versions.first,
                    let ver = firstVersion["version"] as? String {
                    metadata.version = ver
                }
            }

            // Extract skills
            if metadata.skills.isEmpty {
                for key in skillsKeys {
                    if let skills = json[key] as? [String] {
                        metadata.skills = skills
                        break
                    }
                }
            }

            // Stop if we found everything
            if metadata.description != nil, metadata.version != nil {
                break
            }
        }

        return metadata
    }

    /// Extract description from README (first meaningful paragraph)
    /// Finds any file matching "readme" case-insensitively with any extension
    /// - Parameter directory: The directory to search
    /// - Returns: The extracted description, or nil if not found
    public func extractDescriptionFromReadme(in directory: URL) -> String? {
        let fm = FileManager.default

        // Find any file matching "readme" (case-insensitive) with any extension
        guard
            let contents = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else { return nil }

        let readmeFile = contents.first { url in
            let filename = url.deletingPathExtension().lastPathComponent
            return filename.lowercased() == "readme"
        }

        guard
            let readmePath = readmeFile,
            let content = try? String(contentsOf: readmePath, encoding: .utf8)
        else { return nil }

        // Extract first meaningful paragraph (skip headers, badges, empty lines)
        let lines = content.components(separatedBy: .newlines)
        var foundContent = false
        var paragraphLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines at the start
            if trimmed.isEmpty {
                if foundContent && !paragraphLines.isEmpty {
                    // End of paragraph
                    break
                }
                continue
            }

            // Skip headers
            if trimmed.hasPrefix("#") {
                if foundContent && !paragraphLines.isEmpty {
                    break
                }
                continue
            }

            // Skip badges (markdown images/links at start)
            if trimmed.hasPrefix("[![") || trimmed.hasPrefix("![") {
                continue
            }

            // Skip HTML comments and tags
            if trimmed.hasPrefix("<!--") || trimmed.hasPrefix("<") {
                continue
            }

            // Found content
            foundContent = true
            paragraphLines.append(trimmed)
        }

        guard !paragraphLines.isEmpty else { return nil }

        let description = paragraphLines.joined(separator: " ")

        // Truncate if too long
        if description.count > 200 {
            let truncated = String(description.prefix(197))
            // Try to break at word boundary
            if let lastSpace = truncated.lastIndex(of: " ") {
                return String(truncated[..<lastSpace]) + "..."
            }
            return truncated + "..."
        }

        return description
    }
}

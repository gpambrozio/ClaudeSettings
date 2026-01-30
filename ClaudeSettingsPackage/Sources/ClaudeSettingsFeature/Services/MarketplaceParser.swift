import Foundation
import Logging

/// Errors that can occur during marketplace parsing
public enum MarketplaceParserError: LocalizedError {
    case invalidPluginKeyFormat(key: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidPluginKeyFormat(key):
            return "Invalid plugin key format '\(key)'. Expected format: 'PluginName@MarketplaceName'"
        }
    }
}

/// Service for parsing marketplace and plugin JSON files
public actor MarketplaceParser {
    private let logger = Logger(label: "com.claudesettings.marketplace")
    private let fileSystemManager: any FileSystemManagerProtocol
    private let metadataDiscovery = PluginMetadataDiscovery()

    public init(fileSystemManager: any FileSystemManagerProtocol = FileSystemManager()) {
        self.fileSystemManager = fileSystemManager
    }

    /// Parse known_marketplaces.json file
    /// - Parameter url: Path to known_marketplaces.json
    /// - Returns: Dictionary of marketplace name to marketplace data
    public func parseKnownMarketplaces(at url: URL) async throws -> [String: (source: MarketplaceSource, installLocation: String?, lastUpdated: Date?)] {
        guard await fileSystemManager.exists(at: url) else {
            logger.debug("known_marketplaces.json does not exist at \(url.path)")
            return [:]
        }

        let data = try await fileSystemManager.readFile(at: url)
        let decoder = JSONDecoder()

        let entries = try decoder.decode([String: RuntimeMarketplaceEntry].self, from: data)

        var result: [String: (source: MarketplaceSource, installLocation: String?, lastUpdated: Date?)] = [:]
        for (name, entry) in entries {
            let lastUpdated = entry.lastUpdated.flatMap { parseISO8601Date($0) }
            result[name] = (source: entry.source, installLocation: entry.installLocation, lastUpdated: lastUpdated)
        }

        logger.info("Parsed \(result.count) marketplaces from known_marketplaces.json")
        return result
    }

    /// Parse installed_plugins.json file
    /// - Parameter url: Path to installed_plugins.json
    /// - Returns: Array of installed plugins
    public func parseInstalledPlugins(at url: URL) async throws -> [InstalledPlugin] {
        guard await fileSystemManager.exists(at: url) else {
            logger.debug("installed_plugins.json does not exist at \(url.path)")
            return []
        }

        let data = try await fileSystemManager.readFile(at: url)
        let decoder = JSONDecoder()

        // Parse the file with version and plugins keys
        let file = try decoder.decode(InstalledPluginsFile.self, from: data)

        var plugins: [InstalledPlugin] = []

        // Each key is "PluginName@MarketplaceName", value is array of installations
        for (key, installations) in file.plugins {
            // Parse the key to extract name and marketplace
            let components = key.split(separator: "@", maxSplits: 1)
            guard components.count == 2 else {
                logger.error("Invalid plugin key format: \(key)")
                throw MarketplaceParserError.invalidPluginKeyFormat(key: key)
            }

            let pluginName = String(components[0])
            let marketplaceName = String(components[1])

            // Use the first (most recent) installation
            if let installation = installations.first {
                plugins.append(InstalledPlugin(
                    name: pluginName,
                    marketplace: marketplaceName,
                    installedAt: installation.installedAt,
                    dataSource: .global,
                    installPath: installation.installPath.isEmpty ? nil : installation.installPath,
                    version: installation.version
                ))
            }
        }

        logger.info("Parsed \(plugins.count) installed plugins")
        return plugins
    }

    /// Extract extraKnownMarketplaces from settings content
    /// - Parameter content: Settings file content dictionary
    /// - Returns: Dictionary of marketplace name to source configuration
    public func parseExtraMarketplaces(from content: [String: SettingValue]) -> [String: MarketplaceSource] {
        guard case let .object(extraMarketplaces)? = content["extraKnownMarketplaces"] else {
            return [:]
        }

        var result: [String: MarketplaceSource] = [:]
        for (name, value) in extraMarketplaces {
            if let source = parseMarketplaceSource(from: value) {
                result[name] = source
            }
        }

        logger.debug("Extracted \(result.count) extra marketplaces from settings")
        return result
    }

    /// Parse a MarketplaceSource from a SettingValue
    private func parseMarketplaceSource(from value: SettingValue) -> MarketplaceSource? {
        guard case let .object(dict) = value else { return nil }

        // Extract source subobject if present, or use the dict directly
        let sourceDict: [String: SettingValue]
        if case let .object(innerSource)? = dict["source"] {
            sourceDict = innerSource
        } else {
            sourceDict = dict
        }

        guard case let .string(sourceType)? = sourceDict["source"] else { return nil }

        let repo: String?
        if case let .string(r)? = sourceDict["repo"] {
            repo = r
        } else {
            repo = nil
        }

        let path: String?
        if case let .string(p)? = sourceDict["path"] {
            path = p
        } else {
            path = nil
        }

        let ref: String?
        if case let .string(r)? = sourceDict["ref"] {
            ref = r
        } else {
            ref = nil
        }

        return MarketplaceSource(source: sourceType, repo: repo, path: path, ref: ref)
    }

    /// Merge marketplaces from runtime and settings sources
    /// - Parameters:
    ///   - runtime: Marketplaces from known_marketplaces.json
    ///   - settings: Marketplaces from extraKnownMarketplaces in settings
    /// - Returns: Array of merged KnownMarketplace objects
    public func mergeMarketplaces(
        runtime: [String: (source: MarketplaceSource, installLocation: String?, lastUpdated: Date?)],
        settings: [String: MarketplaceSource]
    ) -> [KnownMarketplace] {
        var result: [KnownMarketplace] = []
        var processedNames = Set<String>()

        // Process runtime marketplaces first
        for (name, runtimeData) in runtime {
            processedNames.insert(name)

            let dataSource: MarketplaceDataSource
            let source: MarketplaceSource

            if settings[name] != nil {
                // Present in both - prefer runtime source (it's more up-to-date)
                dataSource = .both
                source = runtimeData.source
            } else {
                // Only in runtime
                dataSource = .global
                source = runtimeData.source
            }

            result.append(KnownMarketplace(
                name: name,
                source: source,
                dataSource: dataSource,
                installLocation: runtimeData.installLocation,
                lastUpdated: runtimeData.lastUpdated
            ))
        }

        // Process settings-only marketplaces
        for (name, settingsSource) in settings where !processedNames.contains(name) {
            result.append(KnownMarketplace(
                name: name,
                source: settingsSource,
                dataSource: .project,
                installLocation: nil,
                lastUpdated: nil
            ))
        }

        // Sort by name for consistent ordering
        return result.sorted { $0.name < $1.name }
    }

    // MARK: - Save Methods

    /// Save marketplaces to known_marketplaces.json
    /// - Parameters:
    ///   - marketplaces: The marketplaces to save (only runtimeOnly and both are saved)
    ///   - url: Path to known_marketplaces.json
    public func saveKnownMarketplaces(_ marketplaces: [KnownMarketplace], to url: URL) async throws {
        // Only save marketplaces that should be in the runtime file
        var entries: [String: RuntimeMarketplaceEntry] = [:]

        for marketplace in marketplaces where marketplace.dataSource != .project {
            let lastUpdatedString: String?
            if let date = marketplace.lastUpdated {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                lastUpdatedString = formatter.string(from: date)
            } else {
                lastUpdatedString = nil
            }

            entries[marketplace.name] = RuntimeMarketplaceEntry(
                source: marketplace.source,
                installLocation: marketplace.installLocation,
                lastUpdated: lastUpdatedString
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)

        // Ensure directory exists and write file
        try await fileSystemManager.writeFile(data: data, to: url)
        logger.info("Saved \(entries.count) marketplaces to known_marketplaces.json")
    }

    /// Save plugins to installed_plugins.json
    /// - Parameters:
    ///   - plugins: The plugins to save
    ///   - url: Path to installed_plugins.json
    ///   - existingData: Existing file data to preserve installation details
    ///   - cacheDirectory: The plugins cache directory for looking up install paths
    public func saveInstalledPlugins(
        _ plugins: [InstalledPlugin],
        to url: URL,
        existingData: Data?,
        cacheDirectory: URL? = nil
    ) async throws {
        // Read existing file to preserve installation details we don't track
        var existingFile: InstalledPluginsFile?
        if let data = existingData {
            existingFile = try? JSONDecoder().decode(InstalledPluginsFile.self, from: data)
        }

        var pluginsDict: [String: [PluginInstallation]] = [:]
        let now = ISO8601DateFormatter().string(from: Date())

        for plugin in plugins {
            let key = plugin.id // "PluginName@MarketplaceName"

            // Try to preserve existing installation details
            if let existing = existingFile?.plugins[key]?.first {
                pluginsDict[key] = [existing]
            } else {
                // Look up install path and version from cache if available
                var installPath = plugin.installPath ?? ""
                var version = plugin.version ?? "1.0.0"

                // If no install path, try to find it in the cache
                if installPath.isEmpty, let cacheDir = cacheDirectory {
                    if
                        let (foundPath, foundVersion) = await findLatestVersionInCache(
                            marketplace: plugin.marketplace,
                            plugin: plugin.name,
                            cacheDirectory: cacheDir
                        ) {
                        installPath = foundPath
                        version = foundVersion
                    }
                }

                // Create installation entry with proper timestamps
                let installation = PluginInstallation(
                    scope: "user",
                    installPath: installPath,
                    version: version,
                    installedAt: plugin.installedAt ?? now,
                    lastUpdated: now,
                    gitCommitSha: nil
                )
                pluginsDict[key] = [installation]
            }
        }

        let file = InstalledPluginsFile(version: existingFile?.version ?? 1, plugins: pluginsDict)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)

        // Ensure directory exists and write file
        try await fileSystemManager.writeFile(data: data, to: url)
        logger.info("Saved \(plugins.count) plugins to installed_plugins.json")
    }

    /// Find the latest version of a plugin in the cache directory
    /// - Parameters:
    ///   - marketplace: The marketplace name
    ///   - plugin: The plugin name
    ///   - cacheDirectory: The root cache directory
    /// - Returns: Tuple of (installPath, version) if found
    private func findLatestVersionInCache(
        marketplace: String,
        plugin: String,
        cacheDirectory: URL
    ) async -> (path: String, version: String)? {
        let pluginCacheDir = cacheDirectory
            .appendingPathComponent(marketplace)
            .appendingPathComponent(plugin)

        guard await fileSystemManager.exists(at: pluginCacheDir) else {
            return nil
        }

        do {
            let contents = try await fileSystemManager.contentsOfDirectory(at: pluginCacheDir)

            // Find version directories
            var versionDirs: [URL] = []
            for url in contents {
                if await fileSystemManager.isDirectory(at: url) {
                    versionDirs.append(url)
                }
            }

            // Sort using semantic version comparison (descending)
            versionDirs.sort { compareVersions($0.lastPathComponent, $1.lastPathComponent) }

            if let latestVersionDir = versionDirs.first {
                let version = latestVersionDir.lastPathComponent
                return (latestVersionDir.path, version)
            }
        } catch {
            logger.debug("Failed to scan cache directory for \(plugin)@\(marketplace): \(error)")
        }

        return nil
    }

    /// Compare two version strings using semantic versioning
    /// Returns true if v1 > v2
    private nonisolated func compareVersions(_ v1: String, _ v2: String) -> Bool {
        let components1 = v1.split(separator: ".").compactMap { Int($0) }
        let components2 = v2.split(separator: ".").compactMap { Int($0) }

        let maxLength = max(components1.count, components2.count)
        for i in 0..<maxLength {
            let c1 = i < components1.count ? components1[i] : 0
            let c2 = i < components2.count ? components2[i] : 0
            if c1 != c2 {
                return c1 > c2
            }
        }
        return false
    }

    // MARK: - Cache Scanning

    /// Scan the plugins cache directory to find plugins installed for a marketplace
    /// This detects plugins that exist on disk but may not be in installed_plugins.json
    /// - Parameters:
    ///   - marketplaceName: The marketplace to scan plugins for
    ///   - cacheDirectory: The root cache directory (~/.claude/plugins/cache/)
    /// - Returns: Array of plugin names found in the cache for this marketplace
    public func scanPluginsInCache(for marketplaceName: String, cacheDirectory: URL) async -> [String] {
        let marketplaceCacheDir = cacheDirectory.appendingPathComponent(marketplaceName)

        guard await fileSystemManager.exists(at: marketplaceCacheDir) else {
            return []
        }

        var pluginNames: [String] = []

        do {
            let contents = try await fileSystemManager.contentsOfDirectory(at: marketplaceCacheDir)

            for itemURL in contents {
                // Check if it's a directory
                guard await fileSystemManager.isDirectory(at: itemURL) else {
                    continue
                }

                // Any directory in the cache is considered a plugin
                // (the CLI controls what goes in the cache)
                pluginNames.append(itemURL.lastPathComponent)
            }
        } catch {
            logger.debug("Failed to scan cache directory for \(marketplaceName): \(error)")
        }

        return pluginNames.sorted()
    }

    /// Load plugins from multiple sources and merge them
    /// - Parameters:
    ///   - globalPlugins: Plugins from installed_plugins.json
    ///   - projectPluginKeys: Dictionary mapping plugin keys to their project file location
    ///   - cacheDirectory: The cache directory to scan
    ///   - marketplaceNames: Names of marketplaces to scan in cache
    /// - Returns: Merged array of plugins with appropriate data sources
    public func loadMergedPlugins(
        globalPlugins: [InstalledPlugin],
        projectPluginKeys: [String: ProjectFileLocation],
        cacheDirectory: URL,
        marketplaceNames: [String]
    ) async -> [InstalledPlugin] {
        var pluginsByID: [String: InstalledPlugin] = [:]

        // 1. Add global plugins from installed_plugins.json
        for plugin in globalPlugins {
            var mutablePlugin = plugin
            mutablePlugin.dataSource = .global
            pluginsByID[plugin.id] = mutablePlugin
        }

        // 2. Add project-enabled plugins (with file location tracking)
        for (key, fileLocation) in projectPluginKeys {
            let components = key.split(separator: "@", maxSplits: 1)
            guard components.count == 2 else { continue }

            let pluginName = String(components[0])
            let marketplace = String(components[1])
            let pluginId = "\(pluginName)@\(marketplace)"

            if var existing = pluginsByID[pluginId] {
                // Already exists globally, mark as both
                existing.dataSource = .both
                existing.projectFileLocation = fileLocation
                pluginsByID[pluginId] = existing
            } else {
                // Project-only plugin
                let plugin = InstalledPlugin(
                    name: pluginName,
                    marketplace: marketplace,
                    installedAt: nil,
                    dataSource: .project,
                    projectFileLocation: fileLocation
                )
                pluginsByID[pluginId] = plugin
            }
        }

        // 3. Scan cache directories for plugins not tracked elsewhere
        for marketplaceName in marketplaceNames {
            let cachedPluginNames = await scanPluginsInCache(for: marketplaceName, cacheDirectory: cacheDirectory)

            for pluginName in cachedPluginNames {
                let pluginId = "\(pluginName)@\(marketplaceName)"

                // Only add if not already tracked
                if pluginsByID[pluginId] == nil {
                    let plugin = InstalledPlugin(
                        name: pluginName,
                        marketplace: marketplaceName,
                        installedAt: nil,
                        dataSource: .cache
                    )
                    pluginsByID[pluginId] = plugin
                }
            }
        }

        return Array(pluginsByID.values).sorted { $0.name < $1.name }
    }

    // MARK: - Scan Available Plugins

    /// Scan a marketplace directory for available plugins
    /// - Parameters:
    ///   - marketplace: The marketplace to scan
    ///   - installLocation: The install location to scan (overrides marketplace.installLocation)
    /// - Returns: Array of available plugins found in the marketplace
    public func scanAvailablePlugins(
        in marketplace: KnownMarketplace,
        at installLocation: String?
    ) async -> [AvailablePlugin] {
        guard let installLocation else {
            logger.debug("No install location for marketplace \(marketplace.name)")
            return []
        }

        let marketplaceURL = URL(fileURLWithPath: installLocation)

        guard FileManager.default.fileExists(atPath: marketplaceURL.path) else {
            logger.debug("Marketplace directory does not exist: \(installLocation)")
            return []
        }

        var availablePlugins: [AvailablePlugin] = []
        var discoveredPluginNames = Set<String>()

        // Try to load marketplace manifest for plugin descriptions
        let marketplaceManifest = metadataDiscovery.loadMarketplaceManifest(from: marketplaceURL)

        // Helper to scan a directory for plugins
        func scanDirectory(_ directoryURL: URL) throws {
            let contents = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            for itemURL in contents {
                // Check if it's a directory
                var isDirectory: ObjCBool = false
                guard
                    FileManager.default.fileExists(atPath: itemURL.path, isDirectory: &isDirectory),
                    isDirectory.boolValue
                else {
                    continue
                }

                let pluginName = itemURL.lastPathComponent

                // Skip if we already discovered this plugin
                guard !discoveredPluginNames.contains(pluginName) else {
                    continue
                }

                // Check if it looks like a plugin directory
                let isLikelyPlugin = metadataDiscovery.looksLikePluginDirectory(itemURL)
                    || marketplaceManifest?.plugin(named: pluginName) != nil

                guard isLikelyPlugin else {
                    continue
                }

                // Discover metadata using flexible approach
                let metadata = metadataDiscovery.discoverPluginMetadata(
                    pluginDirectory: itemURL,
                    pluginName: pluginName,
                    marketplaceManifest: marketplaceManifest
                )

                let plugin = AvailablePlugin(
                    name: pluginName,
                    marketplace: marketplace.name,
                    version: metadata.version,
                    description: metadata.description,
                    skills: metadata.skills,
                    path: itemURL
                )
                availablePlugins.append(plugin)
                discoveredPluginNames.insert(pluginName)
            }
        }

        do {
            // Scan root directory
            try scanDirectory(marketplaceURL)

            // Scan common plugin subdirectories
            for subdir in ["plugins", "external_plugins", ".claude-plugin/plugins"] {
                let subdirURL = marketplaceURL.appendingPathComponent(subdir)
                if FileManager.default.fileExists(atPath: subdirURL.path) {
                    try scanDirectory(subdirURL)
                }
            }
        } catch {
            logger.error("Failed to scan marketplace \(marketplace.name): \(error)")
        }

        logger.info("Found \(availablePlugins.count) available plugins in \(marketplace.name)")
        return availablePlugins.sorted { $0.name < $1.name }
    }
}

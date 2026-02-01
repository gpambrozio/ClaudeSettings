import Foundation
import Logging

/// ViewModel for managing marketplace and plugin data
@MainActor
@Observable
final public class MarketplaceViewModel {
    private let pathProvider: PathProvider
    private let fileSystemManager: any FileSystemManagerProtocol
    private let fileMonitor: SettingsFileMonitor
    private let parser: MarketplaceParser
    private let logger = Logger(label: "com.claudesettings.marketplacevm")

    /// Optional project for loading project-specific extraKnownMarketplaces
    public var project: ClaudeProject?

    /// All known marketplaces (merged from runtime and settings)
    public private(set) var marketplaces: [KnownMarketplace] = []

    /// All installed plugins
    public private(set) var plugins: [InstalledPlugin] = []

    /// Whether data is currently loading
    public private(set) var isLoading = false

    /// Error message if loading failed
    public private(set) var errorMessage: String?

    /// Whether editing mode is active
    public var isEditingMode = false

    /// Pending marketplace edits (keyed by marketplace name)
    public var pendingMarketplaceEdits: [String: MarketplacePendingEdit] = [:]

    /// Pending plugin edits (keyed by plugin id)
    public var pendingPluginEdits: [String: PluginPendingEdit] = [:]

    /// Marketplaces marked for deletion
    public var marketplacesToDelete: Set<String> = []

    /// Plugins marked for deletion
    public var pluginsToDelete: Set<String> = []

    /// Available plugins cache (keyed by marketplace name)
    public private(set) var availablePluginsCache: [String: [AvailablePlugin]] = [:]

    /// Whether available plugins are loading for a marketplace
    public private(set) var loadingAvailablePlugins: Set<String> = []

    /// Plugins queued for installation (keyed by plugin id)
    public var pluginsToInstall: [String: AvailablePlugin] = [:]

    private var observerId: UUID?

    public init(
        project: ClaudeProject? = nil,
        pathProvider: PathProvider = DefaultPathProvider(),
        fileSystemManager: any FileSystemManagerProtocol = FileSystemManager(),
        fileMonitor: SettingsFileMonitor = .shared
    ) {
        self.project = project
        self.pathProvider = pathProvider
        self.fileSystemManager = fileSystemManager
        self.fileMonitor = fileMonitor
        self.parser = MarketplaceParser(fileSystemManager: fileSystemManager)
    }

    // MARK: - Backup Helper

    /// Create a backup of a file before modifying it
    /// - Parameter url: The file to backup
    private func createBackupIfExists(at url: URL) async {
        guard await fileSystemManager.exists(at: url) else { return }
        do {
            _ = try await fileSystemManager.createBackup(of: url, to: pathProvider.backupDirectory)
            logger.debug("Created backup for \(url.lastPathComponent)")
        } catch {
            logger.warning("Failed to create backup for \(url.lastPathComponent): \(error)")
        }
    }

    /// Load all marketplace and plugin data
    public func loadAll() async {
        isLoading = true
        errorMessage = nil

        do {
            // Load sequentially to avoid MainActor contention issues
            try await loadMarketplaces()
            try await loadPlugins()
            await setupFileWatcher()
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Failed to load marketplace data: \(error)")
        }

        isLoading = false
    }

    /// Load marketplaces from known_marketplaces.json and project settings
    private func loadMarketplaces() async throws {
        // Parse global marketplaces from known_marketplaces.json (CLI-managed)
        let globalMarketplaces = try await parser.parseKnownMarketplaces(at: pathProvider.knownMarketplacesPath)

        // Parse project marketplaces from extraKnownMarketplaces (shareable via git)
        var projectMarketplaces: [String: MarketplaceSource] = [:]
        if let project = project {
            let projectSettingsPath = SettingsFileType.projectSettings.path(in: project.path)
            if await fileSystemManager.exists(at: projectSettingsPath) {
                do {
                    let data = try await fileSystemManager.readFile(at: projectSettingsPath)
                    if let content = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let settingsContent = convertToSettingValues(content)
                        projectMarketplaces = await parser.parseExtraMarketplaces(from: settingsContent)
                    }
                } catch {
                    logger.warning("Failed to parse project settings for extraKnownMarketplaces: \(error)")
                }
            }
        }

        // Merge global (CLI-managed) and project (git-shareable) marketplaces
        marketplaces = await parser.mergeMarketplaces(runtime: globalMarketplaces, settings: projectMarketplaces)
        logger.info("Loaded \(marketplaces.count) marketplaces")
    }

    /// Load plugins from multiple sources:
    /// 1. Installed: installed_plugins.json (cached/installed on disk)
    /// 2. Global enabled: enabledPlugins in ~/.claude/settings.json
    /// 3. Project enabled: enabledPlugins in project settings
    /// 4. Cache: Plugins that exist in cache directory
    private func loadPlugins() async throws {
        // 1. Parse installed plugins from installed_plugins.json
        let installedPlugins = try await parser.parseInstalledPlugins(at: pathProvider.installedPluginsPath)

        // 2. Get globally enabled plugin keys from ~/.claude/settings.json
        var globalEnabledPluginKeys: Set<String> = []
        let globalSettingsPath = pathProvider.globalSettingsPath
        if await fileSystemManager.exists(at: globalSettingsPath) {
            do {
                let data = try await fileSystemManager.readFile(at: globalSettingsPath)
                if
                    let content = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let enabledPlugins = content["enabledPlugins"] as? [String: Any] {
                    globalEnabledPluginKeys = Set(enabledPlugins.keys)
                }
            } catch {
                logger.warning("Failed to parse global settings for enabledPlugins: \(error)")
            }
        }

        // 3. Get project-enabled plugin keys from both project files
        var projectPluginKeys: [String: ProjectFileLocation] = [:]
        if let project = project {
            // Read from projectSettings (shared, git-committed)
            let sharedPath = SettingsFileType.projectSettings.path(in: project.path)
            if await fileSystemManager.exists(at: sharedPath) {
                do {
                    let data = try await fileSystemManager.readFile(at: sharedPath)
                    if
                        let content = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let enabledPlugins = content["enabledPlugins"] as? [String: Any] {
                        for key in enabledPlugins.keys {
                            projectPluginKeys[key] = .shared
                        }
                    }
                } catch {
                    logger.warning("Failed to parse project settings for enabledPlugins: \(error)")
                }
            }

            // Read from projectLocal (local, not shared) - overrides shared if both exist
            let localPath = SettingsFileType.projectLocal.path(in: project.path)
            if await fileSystemManager.exists(at: localPath) {
                do {
                    let data = try await fileSystemManager.readFile(at: localPath)
                    if
                        let content = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let enabledPlugins = content["enabledPlugins"] as? [String: Any] {
                        for key in enabledPlugins.keys {
                            // Local takes precedence over shared
                            projectPluginKeys[key] = .local
                        }
                    }
                } catch {
                    logger.warning("Failed to parse project local settings for enabledPlugins: \(error)")
                }
            }
        }

        // 4. Get marketplace names for cache scanning
        let marketplaceNames = marketplaces.map { $0.name }

        // 5. Merge all sources
        plugins = await parser.loadMergedPlugins(
            installedPlugins: installedPlugins,
            globalEnabledPluginKeys: globalEnabledPluginKeys,
            projectPluginKeys: projectPluginKeys,
            cacheDirectory: pathProvider.pluginsCacheDirectory,
            marketplaceNames: marketplaceNames
        )

        logger.info(
            "Loaded \(plugins.count) plugins (installed: \(installedPlugins.count), global enabled: \(globalEnabledPluginKeys.count), project keys: \(projectPluginKeys.count))"
        )
    }

    /// Set up file watching for marketplace files
    private func setupFileWatcher() async {
        // Unregister existing observer if any
        if let existingId = observerId {
            await fileMonitor.unregisterObserver(existingId)
        }

        observerId = await fileMonitor.registerObserver(scope: .globalAndPlugins) { [weak self] url in
            Task { @MainActor in
                await self?.handleFileChange(at: url)
            }
        }
    }

    /// Handle file change notifications
    private func handleFileChange(at url: URL) async {
        logger.debug("File changed: \(url.path)")

        // Reload if it's a marketplace or plugin file
        if
            url.lastPathComponent == "known_marketplaces.json" ||
            url.lastPathComponent == "installed_plugins.json" ||
            url.lastPathComponent == "settings.json" {
            await loadAll()
        }
    }

    /// Find a marketplace by name
    public func marketplace(named name: String) -> KnownMarketplace? {
        marketplaces.first { $0.name == name }
    }

    /// Get the effective install location for a marketplace
    /// For project-only marketplaces, checks if the folder exists at the expected location
    public func effectiveInstallLocation(for marketplace: KnownMarketplace) async -> String? {
        // If marketplace has an install location, use it
        if let location = marketplace.installLocation {
            return location
        }

        // For project-only marketplaces, check if the folder exists at the expected location
        let expectedURL = pathProvider.marketplaceClonesDirectory
            .appendingPathComponent(marketplace.name)

        if await fileSystemManager.exists(at: expectedURL) {
            return expectedURL.path
        }

        return nil
    }

    /// Get all plugins from a specific marketplace (includes all data sources)
    public func plugins(from marketplaceName: String) -> [InstalledPlugin] {
        plugins.filter { $0.marketplace == marketplaceName }
    }

    /// Get plugins by data source from a marketplace
    /// - Parameters:
    ///   - marketplaceName: The marketplace to filter by
    ///   - dataSources: Which data sources to include
    /// - Returns: Filtered array of plugins
    public func plugins(from marketplaceName: String, dataSources: Set<PluginDataSource>) -> [InstalledPlugin] {
        plugins.filter { $0.marketplace == marketplaceName && dataSources.contains($0.dataSource) }
    }

    /// Get globally installed plugins only (excludes cache-only and project-only)
    public func globalPlugins(from marketplaceName: String) -> [InstalledPlugin] {
        plugins(from: marketplaceName, dataSources: [.global, .both])
    }

    /// Stop file watching (cleanup)
    public func stopFileWatcher() async {
        if let id = observerId {
            await fileMonitor.unregisterObserver(id)
            observerId = nil
        }
    }

    // MARK: - Editing Mode

    /// Start editing mode
    public func startEditing() {
        isEditingMode = true
        pendingMarketplaceEdits = [:]
        pendingPluginEdits = [:]
        marketplacesToDelete = []
        pluginsToDelete = []
        pluginsToInstall = [:]
    }

    /// Cancel editing and discard changes
    public func cancelEditing() {
        isEditingMode = false
        pendingMarketplaceEdits = [:]
        pendingPluginEdits = [:]
        marketplacesToDelete = []
        pluginsToDelete = []
        pluginsToInstall = [:]
    }

    /// Save all pending edits
    public func saveAllEdits() async throws {
        // Apply marketplace edits
        var updatedMarketplaces = marketplaces.filter { !marketplacesToDelete.contains($0.name) }

        for (_, edit) in pendingMarketplaceEdits {
            if let originalName = edit.original?.name {
                // Update existing
                if let index = updatedMarketplaces.firstIndex(where: { $0.name == originalName }) {
                    updatedMarketplaces[index] = edit.toMarketplace()
                }
            } else {
                // Add new
                updatedMarketplaces.append(edit.toMarketplace())
            }
        }

        // Apply plugin edits
        var updatedPlugins = plugins.filter { !pluginsToDelete.contains($0.id) }

        for (_, edit) in pendingPluginEdits {
            if let originalId = edit.original?.id {
                // Update existing
                if let index = updatedPlugins.firstIndex(where: { $0.id == originalId }) {
                    updatedPlugins[index] = edit.toPlugin()
                }
            } else {
                // Add new
                updatedPlugins.append(edit.toPlugin())
            }
        }

        // Install queued plugins (filter out already-installed ones)
        for (_, availablePlugin) in pluginsToInstall
            where !updatedPlugins.contains(where: { $0.id == availablePlugin.id }) {
            let newPlugin = InstalledPlugin(
                name: availablePlugin.name,
                marketplace: availablePlugin.marketplace,
                installedAt: ISO8601DateFormatter().string(from: Date())
            )
            updatedPlugins.append(newPlugin)
        }

        // Read existing plugins data for preservation
        let pluginsData: Data?
        if await fileSystemManager.exists(at: pathProvider.installedPluginsPath) {
            pluginsData = try? await fileSystemManager.readFile(at: pathProvider.installedPluginsPath)
        } else {
            pluginsData = nil
        }

        // Only save global plugins to installed_plugins.json
        // Filter out .cache (not installed) and .project (managed by project settings)
        let globalPluginsToSave = updatedPlugins.filter {
            $0.dataSource == .global || $0.dataSource == .both
        }

        // Save to temporary files first for atomic transaction
        let marketplacesPath = pathProvider.knownMarketplacesPath
        let pluginsPath = pathProvider.installedPluginsPath
        let tempMarketplacesPath = marketplacesPath.deletingLastPathComponent()
            .appendingPathComponent(".known_marketplaces.json.tmp")
        let tempPluginsPath = pluginsPath.deletingLastPathComponent()
            .appendingPathComponent(".installed_plugins.json.tmp")

        // Create backups before modifying
        await createBackupIfExists(at: marketplacesPath)
        await createBackupIfExists(at: pluginsPath)

        // Write to temp files
        try await parser.saveKnownMarketplaces(updatedMarketplaces, to: tempMarketplacesPath)
        try await parser.saveInstalledPlugins(
            globalPluginsToSave,
            to: tempPluginsPath,
            existingData: pluginsData,
            cacheDirectory: pathProvider.pluginsCacheDirectory
        )

        // Atomically move temp files to final locations
        // If either move fails, we haven't corrupted the original files
        do {
            // Remove existing files first (if they exist)
            if await fileSystemManager.exists(at: marketplacesPath) {
                try await fileSystemManager.delete(at: marketplacesPath)
            }
            try await fileSystemManager.copy(from: tempMarketplacesPath, to: marketplacesPath)
            try await fileSystemManager.delete(at: tempMarketplacesPath)

            if await fileSystemManager.exists(at: pluginsPath) {
                try await fileSystemManager.delete(at: pluginsPath)
            }
            try await fileSystemManager.copy(from: tempPluginsPath, to: pluginsPath)
            try await fileSystemManager.delete(at: tempPluginsPath)
        } catch {
            // Clean up temp files on failure
            try? await fileSystemManager.delete(at: tempMarketplacesPath)
            try? await fileSystemManager.delete(at: tempPluginsPath)
            throw error
        }

        // Update local state
        marketplaces = updatedMarketplaces.sorted { $0.name < $1.name }
        plugins = updatedPlugins

        // Exit editing mode
        isEditingMode = false
        pendingMarketplaceEdits = [:]
        pendingPluginEdits = [:]
        marketplacesToDelete = []
        pluginsToDelete = []
        pluginsToInstall = [:]

        logger.info("Saved marketplace and plugin edits")
    }

    // MARK: - Marketplace CRUD

    /// Get or create a pending edit for a marketplace
    public func pendingEdit(for marketplace: KnownMarketplace) -> MarketplacePendingEdit {
        if let existing = pendingMarketplaceEdits[marketplace.name] {
            return existing
        }
        return MarketplacePendingEdit(from: marketplace)
    }

    /// Update a pending marketplace edit
    public func updatePendingEdit(_ edit: MarketplacePendingEdit, for key: String) {
        pendingMarketplaceEdits[key] = edit
    }

    /// Create a new marketplace edit
    public func createNewMarketplace() -> MarketplacePendingEdit {
        var edit = MarketplacePendingEdit(isNew: true)
        edit.name = "NewMarketplace"
        edit.sourceType = "github"
        return edit
    }

    /// Add a new marketplace edit
    public func addNewMarketplace(_ edit: MarketplacePendingEdit) {
        pendingMarketplaceEdits[edit.name] = edit
    }

    /// Mark a marketplace for deletion
    public func deleteMarketplace(named name: String) {
        marketplacesToDelete.insert(name)
        pendingMarketplaceEdits.removeValue(forKey: name)
    }

    /// Unmark a marketplace for deletion
    public func restoreMarketplace(named name: String) {
        marketplacesToDelete.remove(name)
    }

    /// Check if a marketplace is marked for deletion
    public func isMarkedForDeletion(marketplace name: String) -> Bool {
        marketplacesToDelete.contains(name)
    }

    // MARK: - Plugin CRUD

    /// Get or create a pending edit for a plugin
    public func pendingEdit(for plugin: InstalledPlugin) -> PluginPendingEdit {
        if let existing = pendingPluginEdits[plugin.id] {
            return existing
        }
        return PluginPendingEdit(from: plugin)
    }

    /// Update a pending plugin edit
    public func updatePendingEdit(_ edit: PluginPendingEdit, for key: String) {
        pendingPluginEdits[key] = edit
    }

    /// Create a new plugin edit
    public func createNewPlugin() -> PluginPendingEdit {
        var edit = PluginPendingEdit(isNew: true)
        edit.name = "NewPlugin"
        edit.marketplace = marketplaces.first?.name ?? ""
        return edit
    }

    /// Add a new plugin edit
    public func addNewPlugin(_ edit: PluginPendingEdit) {
        pendingPluginEdits[edit.toPlugin().id] = edit
    }

    /// Mark a plugin for deletion
    public func deletePlugin(id: String) {
        pluginsToDelete.insert(id)
        pendingPluginEdits.removeValue(forKey: id)
    }

    /// Unmark a plugin for deletion
    public func restorePlugin(id: String) {
        pluginsToDelete.remove(id)
    }

    /// Check if a plugin is marked for deletion
    public func isMarkedForDeletion(plugin id: String) -> Bool {
        pluginsToDelete.contains(id)
    }

    /// Whether there are any unsaved changes
    public var hasUnsavedChanges: Bool {
        !pendingMarketplaceEdits.isEmpty || !pendingPluginEdits.isEmpty ||
            !marketplacesToDelete.isEmpty || !pluginsToDelete.isEmpty ||
            !pluginsToInstall.isEmpty
    }

    /// Whether all pending edits are valid
    public var allEditsValid: Bool {
        let marketplaceErrors = pendingMarketplaceEdits.values.contains { $0.validationError != nil }
        let pluginErrors = pendingPluginEdits.values.contains { $0.validationError != nil }
        return !marketplaceErrors && !pluginErrors
    }

    // MARK: - Available Plugins

    /// Load available plugins for a marketplace
    public func loadAvailablePlugins(for marketplace: KnownMarketplace) async {
        guard !loadingAvailablePlugins.contains(marketplace.name) else { return }

        loadingAvailablePlugins.insert(marketplace.name)

        // Use effective install location to handle project-only marketplaces
        let location = await effectiveInstallLocation(for: marketplace)
        let available = await parser.scanAvailablePlugins(in: marketplace, at: location)
        availablePluginsCache[marketplace.name] = available

        loadingAvailablePlugins.remove(marketplace.name)
        logger.info("Loaded \(available.count) available plugins for \(marketplace.name)")
    }

    /// Get available plugins for a marketplace (from cache)
    public func availablePlugins(for marketplaceName: String) -> [AvailablePlugin] {
        availablePluginsCache[marketplaceName] ?? []
    }

    /// Get all plugins for display, merging available plugins with installed-only plugins
    /// This ensures plugins that exist only in cache (not in marketplace directory) are shown
    /// - Parameter marketplaceName: The marketplace to get plugins for
    /// - Returns: Merged array of AvailablePlugin objects for display
    public func allPluginsForDisplay(from marketplaceName: String) -> [AvailablePlugin] {
        var result = availablePlugins(for: marketplaceName)
        let availableNames = Set(result.map(\.name))

        // Add any installed plugins not in available list (e.g., cache-only plugins)
        for installed in plugins(from: marketplaceName) {
            guard !availableNames.contains(installed.name) else { continue }

            // Create AvailablePlugin from InstalledPlugin
            // Description will be looked up from cache in the view if available
            let available = AvailablePlugin(
                name: installed.name,
                marketplace: installed.marketplace,
                version: installed.version,
                description: nil,
                skills: [],
                path: URL(fileURLWithPath: installed.installPath ?? "/unknown")
            )
            result.append(available)
        }

        return result.sorted { $0.name < $1.name }
    }

    /// Check if available plugins are loading for a marketplace
    public func isLoadingAvailablePlugins(for marketplaceName: String) -> Bool {
        loadingAvailablePlugins.contains(marketplaceName)
    }

    /// Look up description from cache for a plugin that doesn't have one in available plugins
    /// - Parameters:
    ///   - pluginName: The plugin name
    ///   - marketplace: The marketplace the plugin belongs to
    /// - Returns: The description if found in cache, nil otherwise
    public func descriptionFromCache(for pluginName: String, marketplace: String) -> String? {
        let metadataDiscovery = PluginMetadataDiscovery()
        let metadata = metadataDiscovery.discoverMetadataFromCache(
            pluginName: pluginName,
            marketplace: marketplace,
            cacheDirectory: pathProvider.pluginsCacheDirectory
        )
        return metadata?.description
    }

    /// Queue a plugin for installation
    public func queuePluginInstall(_ plugin: AvailablePlugin) {
        pluginsToInstall[plugin.id] = plugin
    }

    /// Remove a plugin from the installation queue
    public func unqueuePluginInstall(_ plugin: AvailablePlugin) {
        pluginsToInstall.removeValue(forKey: plugin.id)
    }

    /// Queue a plugin for installation by ID (for cache-only plugins without AvailablePlugin)
    public func queuePluginInstallById(_ pluginId: String, name: String, marketplace: String) {
        // Create a minimal AvailablePlugin with a placeholder path
        let plugin = AvailablePlugin(
            name: name,
            marketplace: marketplace,
            version: nil,
            description: nil,
            skills: [],
            path: URL(fileURLWithPath: "/placeholder")
        )
        pluginsToInstall[pluginId] = plugin
    }

    /// Remove a plugin from the installation queue by ID
    public func unqueuePluginInstallById(_ pluginId: String) {
        pluginsToInstall.removeValue(forKey: pluginId)
    }

    /// Check if a plugin is queued for installation
    public func isQueuedForInstall(_ plugin: AvailablePlugin) -> Bool {
        pluginsToInstall[plugin.id] != nil
    }

    /// Check if a plugin is already installed
    public func isPluginInstalled(_ plugin: AvailablePlugin) -> Bool {
        plugins.contains { $0.id == plugin.id }
    }

    // MARK: - Scope Management

    /// Copy a marketplace configuration to a project's settings (without removing from global)
    /// - Parameters:
    ///   - marketplace: The marketplace to copy
    ///   - settingsViewModel: The settings view model to write project settings
    ///   - includePlugins: Whether to also copy installed plugins (default: true)
    public func copyMarketplaceToProject(
        marketplace: KnownMarketplace,
        settingsViewModel: SettingsViewModel,
        includePlugins: Bool = true
    ) async throws {
        // Build the extraKnownMarketplaces entry
        let basePath = "extraKnownMarketplaces.\(marketplace.name)"
        var updates: [(key: String, value: SettingValue)] = [
            ("\(basePath).source.source", .string(marketplace.source.source)),
        ]
        if let repo = marketplace.source.repo {
            updates.append(("\(basePath).source.repo", .string(repo)))
        }
        if let ref = marketplace.source.ref {
            updates.append(("\(basePath).source.ref", .string(ref)))
        }
        if let path = marketplace.source.path {
            updates.append(("\(basePath).source.path", .string(path)))
        }

        // Also copy any globally installed plugins from this marketplace to enabledPlugins
        // Only include plugins that are actually installed globally (not cache-only)
        var copiedPluginCount = 0
        if includePlugins {
            let installedPlugins = globalPlugins(from: marketplace.name)
            for plugin in installedPlugins {
                // Format: enabledPlugins.<pluginName>@<marketplaceName> = true
                let pluginKey = "enabledPlugins.\(plugin.name)@\(marketplace.name)"
                updates.append((pluginKey, .bool(true)))
            }
            copiedPluginCount = installedPlugins.count
        }

        // Add to project settings
        try await settingsViewModel.batchUpdateSettings(updates, in: .projectSettings)

        // Reload data to update dataSource (global → both)
        await loadAll()

        logger.info("Copied marketplace '\(marketplace.name)' with \(copiedPluginCount) plugins to project settings")
    }

    /// Remove a marketplace from global known_marketplaces.json
    /// Also removes any installed plugins from that marketplace
    /// - Parameter marketplace: The marketplace to remove
    public func removeMarketplaceFromGlobal(marketplace: KnownMarketplace) async throws {
        // Create backup before modifying
        await createBackupIfExists(at: pathProvider.knownMarketplacesPath)

        // Remove marketplace from known_marketplaces.json
        let remainingMarketplaces = marketplaces.filter { $0.name != marketplace.name }
        try await parser.saveKnownMarketplaces(remainingMarketplaces, to: pathProvider.knownMarketplacesPath)

        // Also remove plugins from this marketplace from installed_plugins.json
        // Only remove plugins that are global (not project-only or cache-only)
        let pluginsToSave = plugins.filter {
            $0.marketplace != marketplace.name || ($0.dataSource != .global && $0.dataSource != .both)
        }
        let globalPluginsToRemove = plugins.filter {
            $0.marketplace == marketplace.name && ($0.dataSource == .global || $0.dataSource == .both)
        }
        let removedPluginCount = globalPluginsToRemove.count

        if removedPluginCount > 0 {
            // Create backup before modifying
            await createBackupIfExists(at: pathProvider.installedPluginsPath)

            // Get existing data for preserving unknown fields
            var pluginsData: Data?
            if await fileSystemManager.exists(at: pathProvider.installedPluginsPath) {
                pluginsData = try? await fileSystemManager.readFile(at: pathProvider.installedPluginsPath)
            }

            // Only save global plugins (filter out project-only and cache-only)
            let globalPluginsToSave = pluginsToSave.filter {
                $0.dataSource == .global || $0.dataSource == .both
            }

            try await parser.saveInstalledPlugins(
                globalPluginsToSave,
                to: pathProvider.installedPluginsPath,
                existingData: pluginsData,
                cacheDirectory: pathProvider.pluginsCacheDirectory
            )
            logger.info("Removed \(removedPluginCount) plugins from global installed_plugins.json")
        }

        // Reload data
        await loadAll()

        logger.info("Removed marketplace '\(marketplace.name)' from global registry")
    }

    /// Move a runtime-only marketplace to project settings (single project convenience method)
    /// - Parameters:
    ///   - marketplace: The marketplace to move
    ///   - settingsViewModel: The settings view model to write project settings
    public func moveMarketplaceToProject(
        marketplace: KnownMarketplace,
        settingsViewModel: SettingsViewModel
    ) async throws {
        guard marketplace.dataSource == .global else {
            logger.warning("Cannot move marketplace '\(marketplace.name)': not a runtime-only marketplace")
            return
        }

        // Copy to project first
        try await copyMarketplaceToProject(marketplace: marketplace, settingsViewModel: settingsViewModel)

        // Then remove from global
        try await removeMarketplaceFromGlobal(marketplace: marketplace)

        logger.info("Moved marketplace '\(marketplace.name)' to project settings")
    }

    /// Promote a project-only marketplace to global (add to known_marketplaces.json)
    /// Also removes from project settings so it appears as "global" only
    /// - Parameters:
    ///   - marketplace: The marketplace to promote (must be project-only)
    ///   - settingsViewModel: The settings view model to remove from project settings
    public func promoteMarketplaceToGlobal(
        marketplace: KnownMarketplace,
        settingsViewModel: SettingsViewModel
    ) async throws {
        guard marketplace.dataSource == .project else {
            logger.warning("Marketplace '\(marketplace.name)' is not project-only, cannot promote")
            return
        }

        // Use effective install location or compute the expected path
        let installLocation = await effectiveInstallLocation(for: marketplace)
            ?? pathProvider.marketplaceClonesDirectory
            .appendingPathComponent(marketplace.name)
            .path

        let globalMarketplace = KnownMarketplace(
            name: marketplace.name,
            source: marketplace.source,
            dataSource: .global,
            installLocation: installLocation,
            lastUpdated: Date()
        )

        // Create backup before modifying
        await createBackupIfExists(at: pathProvider.knownMarketplacesPath)

        // Add to global known_marketplaces.json
        var updatedMarketplaces = marketplaces.filter { $0.dataSource == .global || ($0.dataSource == .both && $0.name != marketplace.name) }
        updatedMarketplaces.append(globalMarketplace)

        try await parser.saveKnownMarketplaces(updatedMarketplaces, to: pathProvider.knownMarketplacesPath)

        // Remove from project settings (both shared and local to be thorough)
        let marketplaceKey = "extraKnownMarketplaces.\(marketplace.name)"
        try? await settingsViewModel.deleteNode(key: marketplaceKey, from: .projectSettings)
        try? await settingsViewModel.deleteNode(key: marketplaceKey, from: .projectLocal)

        // Reload data (marketplace will now appear as .global only)
        await loadAll()

        logger.info("Promoted marketplace '\(marketplace.name)' to global and removed from project settings")
    }

    // MARK: - Atomic Plugin Operations

    /// Install a plugin globally (add to installed_plugins.json)
    /// - Parameters:
    ///   - name: The plugin name
    ///   - marketplace: The marketplace the plugin belongs to
    ///   - settingsViewModel: The settings view model to write global settings
    public func installPluginGlobally(
        name: String,
        marketplace: String,
        settingsViewModel: SettingsViewModel
    ) async throws {
        let pluginId = "\(name)@\(marketplace)"

        // Check if already globally enabled
        let isAlreadyGlobal = plugins.contains {
            $0.id == pluginId && ($0.dataSource == .global || $0.dataSource == .both)
        }
        if isAlreadyGlobal {
            logger.info("Plugin '\(name)' is already enabled globally")
            return
        }

        // Add to enabledPlugins in global settings.json
        let key = "enabledPlugins.\(name)@\(marketplace)"
        try await settingsViewModel.updateSetting(key: key, value: .bool(true), in: .globalSettings)

        // Reload data
        await loadAll()
        logger.info("Enabled plugin '\(name)' globally")
    }

    /// Disable a plugin globally (remove from enabledPlugins in ~/.claude/settings.json)
    /// - Parameters:
    ///   - pluginId: The plugin ID (format: name@marketplace)
    ///   - settingsViewModel: The settings view model to write global settings
    public func uninstallPluginGlobally(
        pluginId: String,
        settingsViewModel: SettingsViewModel
    ) async throws {
        // Check if plugin is globally enabled
        guard plugins.contains(where: { $0.id == pluginId && ($0.dataSource == .global || $0.dataSource == .both) }) else {
            logger.info("Plugin '\(pluginId)' is not enabled globally")
            return
        }

        // Remove from enabledPlugins in global settings.json
        let key = "enabledPlugins.\(pluginId)"
        try await settingsViewModel.deleteSetting(key: key, from: .globalSettings)

        // Reload data
        await loadAll()
        logger.info("Disabled plugin '\(pluginId)' globally")
    }

    /// Add a plugin to a project's enabledPlugins
    /// - Parameters:
    ///   - name: The plugin name
    ///   - marketplace: The marketplace the plugin belongs to
    ///   - location: Where to add the plugin (shared or local)
    ///   - settingsViewModel: The settings view model to write project settings
    public func addPluginToProject(
        name: String,
        marketplace: String,
        location: ProjectFileLocation,
        settingsViewModel: SettingsViewModel
    ) async throws {
        let key = "enabledPlugins.\(name)@\(marketplace)"
        let fileType: SettingsFileType = location == .shared ? .projectSettings : .projectLocal

        // First remove from the other file if it exists there
        let otherFileType: SettingsFileType = location == .shared ? .projectLocal : .projectSettings
        try? await settingsViewModel.deleteSetting(key: key, from: otherFileType)

        // Add to the target file - SettingsViewModel automatically triggers loadAll()
        // when plugin-related keys change
        try await settingsViewModel.updateSetting(key: key, value: .bool(true), in: fileType)

        logger.info("Added plugin '\(name)' to project enabledPlugins (\(location == .shared ? "shared" : "local"))")
    }

    /// Remove a plugin from a project's enabledPlugins (from both files if present)
    /// - Parameters:
    ///   - name: The plugin name
    ///   - marketplace: The marketplace the plugin belongs to
    ///   - settingsViewModel: The settings view model to modify project settings
    public func removePluginFromProject(
        name: String,
        marketplace: String,
        settingsViewModel: SettingsViewModel
    ) async throws {
        let key = "enabledPlugins.\(name)@\(marketplace)"

        // Remove from both files to ensure it's fully removed
        // SettingsViewModel automatically triggers loadAll() when plugin-related keys change
        try? await settingsViewModel.deleteSetting(key: key, from: .projectSettings)
        try? await settingsViewModel.deleteSetting(key: key, from: .projectLocal)

        logger.info("Removed plugin '\(name)' from project enabledPlugins")
    }

    // MARK: - Legacy Cleanup

    /// Remove legacy marketplace/plugin entries from global settings.json
    /// - Parameter settingsViewModel: The settings view model to modify global settings
    public func cleanupLegacyGlobalEntries(settingsViewModel: SettingsViewModel) async throws {
        // Delete extraKnownMarketplaces from global settings
        do {
            try await settingsViewModel.deleteNode(key: "extraKnownMarketplaces", from: .globalSettings)
            logger.info("Removed legacy extraKnownMarketplaces from global settings.json")
        } catch {
            logger.debug("No extraKnownMarketplaces to remove or error: \(error)")
        }

        // Delete enabledPlugins from global settings
        do {
            try await settingsViewModel.deleteNode(key: "enabledPlugins", from: .globalSettings)
            logger.info("Removed legacy enabledPlugins from global settings.json")
        } catch {
            logger.debug("No enabledPlugins to remove or error: \(error)")
        }

        // Reload settings
        await settingsViewModel.loadSettings()
        await loadAll()

        logger.info("Completed legacy global entries cleanup")
    }

    /// Convert JSON dictionary to SettingValue dictionary
    private func convertToSettingValues(_ dict: [String: Any]) -> [String: SettingValue] {
        var result: [String: SettingValue] = [:]
        for (key, value) in dict {
            result[key] = convertToSettingValue(value)
        }
        return result
    }

    /// Convert a JSON value to SettingValue
    private func convertToSettingValue(_ value: Any) -> SettingValue {
        switch value {
        case let string as String:
            return .string(string)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let bool as Bool:
            return .bool(bool)
        case let array as [Any]:
            return .array(array.map { convertToSettingValue($0) })
        case let dict as [String: Any]:
            return .object(convertToSettingValues(dict))
        case is NSNull:
            return .null
        default:
            return .null
        }
    }
}

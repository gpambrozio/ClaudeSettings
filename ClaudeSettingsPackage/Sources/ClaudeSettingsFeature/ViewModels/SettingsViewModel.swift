import Foundation
import Logging
import SwiftUI

/// Editing state for a single setting
public struct PendingEdit: Equatable, Identifiable {
    public var key: String
    public var id: String { key } // Identifiable conformance
    public var value: SettingValue
    public var targetFileType: SettingsFileType
    public var originalFileType: SettingsFileType // Track where the setting originally came from
    public var validationError: String? // Validation error for this edit
    public var rawEditingText: String? // Raw text being edited (for JSON complex types)

    public init(key: String, value: SettingValue, targetFileType: SettingsFileType, originalFileType: SettingsFileType, validationError: String? = nil, rawEditingText: String? = nil) {
        self.key = key
        self.value = value
        self.targetFileType = targetFileType
        self.originalFileType = originalFileType
        self.validationError = validationError
        self.rawEditingText = rawEditingText
    }
}

/// ViewModel for managing settings of a specific project
@MainActor
@Observable
final public class SettingsViewModel {
    private let fileSystemManager: any FileSystemManagerProtocol
    private let pathProvider: PathProvider
    private let logger = Logger(label: "com.claudesettings.settings")

    public var settingsFiles: [SettingsFile] = []
    public var settingItems: [SettingItem] = []
    public var hierarchicalSettings: [HierarchicalSettingNode] = []
    public var validationErrors: [ValidationError] = []
    public var isLoading = false
    public var errorMessage: String?

    /// Index for fast node lookup by key
    private var nodeIndex: [String: HierarchicalSettingNode] = [:]

    // MARK: - Editing State

    /// Whether we're in editing mode (affects entire project settings view)
    public var isEditingMode = false

    /// Dictionary of pending edits, keyed by setting key
    public var pendingEdits: [String: PendingEdit] = [:]

    /// Whether to hide settings that only exist in global configuration files
    /// Persisted to UserDefaults so the preference survives app launches
    public var hideGlobalSettings: Bool = UserDefaults.standard.bool(forKey: "hideGlobalSettings") {
        didSet {
            UserDefaults.standard.set(hideGlobalSettings, forKey: "hideGlobalSettings")
        }
    }

    private let settingsParser: any SettingsParserProtocol
    public let project: ClaudeProject?
    private let fileMonitor: SettingsFileMonitor
    private var observerId: UUID?
    private var consecutiveReloadFailures: [URL: Int] = [:]

    /// ViewModel for marketplace and plugin data
    public private(set) var marketplaceViewModel: MarketplaceViewModel

    public init(
        project: ClaudeProject? = nil,
        fileSystemManager: any FileSystemManagerProtocol = FileSystemManager(),
        pathProvider: PathProvider = DefaultPathProvider(),
        fileMonitor: SettingsFileMonitor = .shared
    ) {
        self.project = project
        self.fileSystemManager = fileSystemManager
        self.pathProvider = pathProvider
        self.settingsParser = SettingsParser(fileSystemManager: fileSystemManager)
        self.fileMonitor = fileMonitor
        self.marketplaceViewModel = MarketplaceViewModel(
            project: project,
            pathProvider: pathProvider,
            fileSystemManager: fileSystemManager,
            fileMonitor: fileMonitor
        )
    }

    /// Internal initializer for testing with a custom settings parser
    init(
        project: ClaudeProject?,
        fileSystemManager: any FileSystemManagerProtocol,
        pathProvider: PathProvider,
        settingsParser: any SettingsParserProtocol,
        fileMonitor: SettingsFileMonitor,
        marketplaceViewModel: MarketplaceViewModel? = nil
    ) {
        self.project = project
        self.fileSystemManager = fileSystemManager
        self.pathProvider = pathProvider
        self.settingsParser = settingsParser
        self.fileMonitor = fileMonitor
        self.marketplaceViewModel = marketplaceViewModel ?? MarketplaceViewModel(
            project: project,
            pathProvider: pathProvider,
            fileSystemManager: fileSystemManager,
            fileMonitor: fileMonitor
        )
    }

    /// Whether this view model is for a project (vs global configuration)
    public var isProjectView: Bool {
        project != nil
    }

    /// Whether the global settings.json contains legacy marketplace/plugin entries
    /// These should be in dedicated files, not in settings.json
    public var hasLegacyGlobalEntries: Bool {
        guard let globalSettingsFile = settingsFiles.first(where: { $0.type == .globalSettings }) else {
            return false
        }
        let hasExtraMarketplaces = globalSettingsFile.content["extraKnownMarketplaces"] != nil
        let hasEnabledPlugins = globalSettingsFile.content["enabledPlugins"] != nil
        return hasExtraMarketplaces || hasEnabledPlugins
    }

    /// Hierarchical settings filtered based on hideGlobalSettings preference
    ///
    /// When `hideGlobalSettings` is true and viewing a project, this filters out
    /// settings that only have contributions from global configuration files.
    /// Settings that have at least one project-level contribution are kept.
    public var filteredHierarchicalSettings: [HierarchicalSettingNode] {
        guard hideGlobalSettings && isProjectView else {
            return hierarchicalSettings
        }

        // Filter to only include settings that have project-level contributions
        let projectSettingKeys = Set(settingItems.filter { item in
            item.contributions.contains { !$0.source.isGlobal }
        }.map(\.key))

        return filterHierarchicalNodes(hierarchicalSettings, keepingKeys: projectSettingKeys)
    }

    /// Recursively filter hierarchical nodes, keeping only those with matching keys
    private func filterHierarchicalNodes(_ nodes: [HierarchicalSettingNode], keepingKeys keys: Set<String>) -> [HierarchicalSettingNode] {
        nodes.compactMap { node in
            if node.isParent {
                // For parent nodes, recursively filter children
                let filteredChildren = filterHierarchicalNodes(node.children, keepingKeys: keys)
                if filteredChildren.isEmpty {
                    return nil // Remove parent if all children were filtered out
                }
                return HierarchicalSettingNode(
                    id: node.id,
                    key: node.key,
                    displayName: node.displayName,
                    nodeType: .parent(childCount: filteredChildren.count),
                    children: filteredChildren
                )
            } else {
                // For leaf nodes, check if the key should be kept
                return keys.contains(node.key) ? node : nil
            }
        }
    }

    /// Load all settings files for the current project
    public func loadSettings() async {
        await loadSettingsFiles(includeProject: project != nil, projectPath: project?.path)

        // Also load marketplace/plugin data
        await marketplaceViewModel.loadAll()
    }

    /// Load settings files with optional project scope
    private func loadSettingsFiles(includeProject: Bool, projectPath: URL?) async {
        isLoading = true
        errorMessage = nil

        do {
            var files: [SettingsFile] = []
            let homeDirectory = pathProvider.homeDirectory

            // Load enterprise managed settings first (highest precedence, cannot be overridden)
            for enterprisePath in pathProvider.enterpriseManagedPaths where await fileSystemManager.exists(at: enterprisePath) {
                let file = try await settingsParser.parseSettingsFile(
                    at: enterprisePath,
                    type: .enterpriseManaged
                )
                files.append(file)
                logger.info("Loaded enterprise managed settings from: \(enterprisePath.path)")
                break // Only load the first found enterprise settings
            }

            // Load global settings (they form the base layer)
            let globalSettingsPath = SettingsFileType.globalSettings.path(in: homeDirectory)
            if await fileSystemManager.exists(at: globalSettingsPath) {
                let file = try await settingsParser.parseSettingsFile(
                    at: globalSettingsPath,
                    type: .globalSettings
                )
                files.append(file)
            }

            let globalLocalPath = SettingsFileType.globalLocal.path(in: homeDirectory)
            if await fileSystemManager.exists(at: globalLocalPath) {
                let file = try await settingsParser.parseSettingsFile(
                    at: globalLocalPath,
                    type: .globalLocal
                )
                files.append(file)
            }

            // Load project settings if requested
            if includeProject, let projectPath {
                let projectSettingsPath = SettingsFileType.projectSettings.path(in: projectPath)
                if await fileSystemManager.exists(at: projectSettingsPath) {
                    let file = try await settingsParser.parseSettingsFile(
                        at: projectSettingsPath,
                        type: .projectSettings
                    )
                    files.append(file)
                }

                let projectLocalPath = SettingsFileType.projectLocal.path(in: projectPath)
                if await fileSystemManager.exists(at: projectLocalPath) {
                    let file = try await settingsParser.parseSettingsFile(
                        at: projectLocalPath,
                        type: .projectLocal
                    )
                    files.append(file)
                }
            }

            settingsFiles = files
            settingItems = computeSettingItems(from: files)
            hierarchicalSettings = computeHierarchicalSettings(from: settingItems)
            validationErrors = files.flatMap(\.validationErrors)

            let scope = includeProject ? "settings" : "global settings"
            logger.info("Loaded \(files.count) \(scope) files with \(settingItems.count) settings and \(validationErrors.count) validation errors")

            // Set up file watching for live updates
            await setupFileWatcher()
        } catch {
            logger.error("Failed to load settings: \(error)")
            errorMessage = userFriendlyErrorMessage(for: error)
        }

        isLoading = false
    }

    /// Set up file monitoring for settings files
    private func setupFileWatcher() async {
        // Determine scope based on whether we have a project
        let scope: SettingsScope
        if let project {
            scope = .globalAndProjects([project])
            logger.info("Registering file monitoring for global and project settings")
        } else {
            scope = .global
            logger.info("Registering file monitoring for global settings")
        }

        // Register with the centralized file monitor
        // The callback will be called on a background thread, so we need to hop to MainActor
        if let existingObserverId = observerId {
            // Update existing observer
            await fileMonitor.updateObserver(existingObserverId, scope: scope)
        } else {
            // Register new observer
            observerId = await fileMonitor.registerObserver(scope: scope) { [weak self] changedURL in
                Task { @MainActor in
                    await self?.handleFileChange(at: changedURL)
                }
            }
        }
    }

    /// Stop file watching (called when switching projects or cleaning up)
    public func stopFileWatcher() async {
        if let observerId {
            await fileMonitor.unregisterObserver(observerId)
            self.observerId = nil
        }
        consecutiveReloadFailures.removeAll()

        // Also stop marketplace file watcher
        await marketplaceViewModel.stopFileWatcher()
    }

    /// Handle file system changes
    /// Note: Debouncing is handled by SettingsFileMonitor
    private func handleFileChange(at url: URL) async {
        await reloadChangedFile(at: url)
    }

    /// Reload a specific settings file that changed externally
    private func reloadChangedFile(at url: URL) async {
        logger.info("Settings file changed externally: \(url.path)")

        // Find which settings file changed
        guard let changedFileIndex = settingsFiles.firstIndex(where: { $0.path == url }) else {
            // File not in our list - might be newly created
            logger.info("File not in loaded settings (possibly newly created): \(url.path)")
            // Do a full reload to pick up new files
            await loadSettings()
            return
        }

        let changedFileType = settingsFiles[changedFileIndex].type

        do {
            // Check if file still exists (might have been deleted)
            guard await fileSystemManager.exists(at: url) else {
                logger.info("Settings file was deleted: \(url.path)")
                // Remove from our list
                settingsFiles.remove(at: changedFileIndex)
                settingItems = computeSettingItems(from: settingsFiles)
                hierarchicalSettings = computeHierarchicalSettings(from: settingItems)
                validationErrors = settingsFiles.flatMap(\.validationErrors)
                return
            }

            // Reload the specific file
            let updatedFile = try await settingsParser.parseSettingsFile(
                at: url,
                type: changedFileType
            )

            // Update in array
            settingsFiles[changedFileIndex] = updatedFile

            // Recompute merged settings
            settingItems = computeSettingItems(from: settingsFiles)
            hierarchicalSettings = computeHierarchicalSettings(from: settingItems)
            validationErrors = settingsFiles.flatMap(\.validationErrors)

            // Reset failure counter on successful reload
            consecutiveReloadFailures[url] = 0

            logger.info("Reloaded settings from: \(url.path)")
        } catch {
            logger.error("Failed to reload changed file: \(error)")

            // Track consecutive failures to distinguish transient from persistent errors
            consecutiveReloadFailures[url, default: 0] += 1

            // Only show error message if file consistently fails to reload (likely a real problem)
            // Transient failures during file saves are expected and shouldn't alarm the user
            if consecutiveReloadFailures[url, default: 0] >= 3 {
                errorMessage = "Unable to reload \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Testing Support

    /// Internal test-only method to trigger file reload (exposed for testing)
    func _testReloadChangedFile(at url: URL) async {
        await reloadChangedFile(at: url)
    }

    /// Convert technical errors into user-friendly messages
    private func userFriendlyErrorMessage(for error: Error) -> String {
        switch error {
        case let fsError as FileSystemError:
            switch fsError {
            case .readFailed:
                return "Unable to read settings file. Please check if the file exists and you have permission to access it."
            case .writeFailed:
                return "Unable to save settings. Please check if you have write permission for this location."
            case .directoryCreationFailed:
                return "Unable to create settings directory. Please check folder permissions."
            case .directoryListFailed:
                return "Unable to access settings directory. Please check folder permissions."
            case .deleteFailed:
                return "Unable to delete settings file. Please check file permissions."
            case .copyFailed:
                return "Unable to copy settings file. Please check file permissions."
            case .attributeNotFound,
                 .attributeReadFailed:
                return "Unable to read file information. The file may be corrupted or inaccessible."
            }
        case let urlError as URLError:
            return "Network or file access error: \(urlError.localizedDescription)"
        case is DecodingError:
            return "Settings file contains invalid data format. Please check the JSON syntax."
        default:
            // Log technical details but show generic message to user
            return "Unable to load settings. Please check that your configuration files are valid and accessible."
        }
    }

    /// Compute setting items with source tracking
    func computeSettingItems(from files: [SettingsFile]) -> [SettingItem] {
        // Build a dictionary mapping keys to their source files (sorted by precedence)
        var keyToSources: [String: [(SettingsFileType, SettingValue)]] = [:]

        for file in files {
            let flattenedKeys = flattenDictionary(file.content)
            for (key, value) in flattenedKeys {
                if keyToSources[key] == nil {
                    keyToSources[key] = []
                }
                keyToSources[key]?.append((file.type, value))
            }
        }

        // Sort each key's sources by precedence and create SettingItems
        var items: [SettingItem] = []

        for (key, sources) in keyToSources {
            let sortedSources = sources.sorted { $0.0.precedence < $1.0.precedence }

            guard
                let lowestSource = sortedSources.first,
                let activeSource = sortedSources.last else { continue }

            // For arrays, settings are additive across sources
            // For other types, higher precedence overrides lower precedence
            // Track contributions for all settings to show in inspector
            let (overriddenBy, contributions): (SettingsFileType?, [SourceContribution])
            if case .array = activeSource.1, sortedSources.count > 1 {
                // Arrays are additive - track all contributing sources with their individual values
                overriddenBy = nil
                contributions = sortedSources.map { SourceContribution(source: $0.0, value: $0.1) }
            } else if sortedSources.count > 1 {
                // Non-arrays are replaced - track both base and override for display
                overriddenBy = activeSource.0
                contributions = sortedSources.map { SourceContribution(source: $0.0, value: $0.1) }
            } else {
                // Single source
                overriddenBy = nil
                contributions = sortedSources.map { SourceContribution(source: $0.0, value: $0.1) }
            }

            let item = SettingItem(
                key: key,
                value: activeSource.1,
                source: lowestSource.0,
                overriddenBy: overriddenBy,
                contributions: contributions
            )

            items.append(item)
        }

        return items.sorted { $0.key < $1.key }
    }

    /// Flatten a nested dictionary to dot-notation keys
    private func flattenDictionary(_ dict: [String: SettingValue], prefix: String = "") -> [String: SettingValue] {
        var result: [String: SettingValue] = [:]

        for (key, value) in dict {
            let fullKey = prefix.isEmpty ? key : "\(prefix).\(key)"

            if case let .object(nestedDict) = value {
                let flattened = flattenDictionary(nestedDict, prefix: fullKey)
                result.merge(flattened) { _, new in new }
            } else {
                result[fullKey] = value
            }
        }

        return result
    }

    /// Compute hierarchical settings tree from flat setting items
    ///
    /// This function transforms a flat list of dot-notation settings (e.g., "editor.theme", "editor.fontSize")
    /// into a hierarchical tree structure suitable for display in a collapsible outline view.
    ///
    /// **Algorithm Overview:**
    /// 1. Group settings by their root key (first component before the dot)
    /// 2. For each root group:
    ///    - If it contains a single setting with no dots, create a leaf node
    ///    - Otherwise, create a parent node and recursively build children
    /// 3. Return sorted root nodes
    ///
    /// **Examples:**
    /// ```
    /// Input: ["editor.theme", "editor.fontSize", "files.exclude"]
    /// Output:
    ///   - editor (parent)
    ///     - theme (leaf)
    ///     - fontSize (leaf)
    ///   - files (parent)
    ///     - exclude (leaf)
    ///
    /// Input: ["simpleValue", "nested.deep.value"]
    /// Output:
    ///   - simpleValue (leaf at root)
    ///   - nested (parent)
    ///     - deep (parent)
    ///       - value (leaf)
    /// ```
    ///
    /// - Parameter items: Flat array of setting items with dot-notation keys
    /// - Returns: Array of root-level hierarchical nodes, sorted alphabetically by key
    func computeHierarchicalSettings(from items: [SettingItem]) -> [HierarchicalSettingNode] {
        // Group settings by their root key (first component before dot)
        var rootGroups: [String: [SettingItem]] = [:]

        for item in items {
            let components = item.key.split(separator: ".", maxSplits: 1)
            let rootKey = String(components[0])

            if rootGroups[rootKey] == nil {
                rootGroups[rootKey] = []
            }
            rootGroups[rootKey]?.append(item)
        }

        // Build hierarchical nodes
        var rootNodes: [HierarchicalSettingNode] = []

        for (rootKey, groupItems) in rootGroups.sorted(by: { $0.key < $1.key }) {
            if groupItems.count == 1 && !groupItems[0].key.contains(".") {
                // Single item without dots - it's a leaf node at root level
                let item = groupItems[0]
                let node = HierarchicalSettingNode(
                    id: item.key,
                    key: item.key,
                    displayName: item.key,
                    nodeType: .leaf(item: item)
                )
                rootNodes.append(node)
            } else {
                // Multiple items or nested items - create parent node
                let children = buildChildNodes(for: groupItems, parentKey: rootKey)
                let node = HierarchicalSettingNode(
                    id: rootKey,
                    key: rootKey,
                    displayName: rootKey,
                    nodeType: .parent(childCount: children.count),
                    children: children
                )
                rootNodes.append(node)
            }
        }

        // Build index for fast lookups
        nodeIndex = buildNodeIndex(rootNodes)

        return rootNodes
    }

    /// Build an index mapping keys to nodes for O(1) lookup
    private func buildNodeIndex(_ nodes: [HierarchicalSettingNode]) -> [String: HierarchicalSettingNode] {
        var index: [String: HierarchicalSettingNode] = [:]
        for node in nodes {
            index[node.key] = node
            // Recursively index children
            let childIndex = buildNodeIndex(node.children)
            index.merge(childIndex) { _, new in new }
        }
        return index
    }

    /// Build child nodes recursively for a group of settings
    ///
    /// This is a recursive helper function that builds the child nodes for a given parent key.
    /// It works by stripping the parent prefix from each setting key and grouping by the next
    /// component, then recursively building deeper levels.
    ///
    /// **Algorithm:**
    /// 1. Strip the parent key prefix (e.g., "editor." from "editor.theme")
    /// 2. Group remaining keys by their next component
    /// 3. For each group:
    ///    - If it's a single item with no more dots, create a leaf node
    ///    - Otherwise, create a parent node and recurse
    ///
    /// **Example:**
    /// ```
    /// parentKey: "editor"
    /// items: ["editor.theme", "editor.font.size", "editor.font.family"]
    ///
    /// After stripping "editor.":
    ///   - "theme" -> single leaf
    ///   - "font.size", "font.family" -> group under "font"
    ///
    /// Output:
    ///   - theme (leaf, displayName: "theme")
    ///   - font (parent, displayName: "font")
    ///     - size (leaf, displayName: "size")
    ///     - family (leaf, displayName: "family")
    /// ```
    ///
    /// **Edge Case Handling:**
    /// Lines 413-415 handle the defensive case where an item's key doesn't start with
    /// `parentKey + "."`. This shouldn't happen given the grouping logic, but ensures
    /// robustness if the function is called with unexpected input.
    ///
    /// - Parameter items: Setting items that should all have keys starting with `parentKey`
    /// - Parameter parentKey: The parent key prefix to strip (e.g., "editor", "editor.font")
    /// - Returns: Array of child nodes, sorted alphabetically by display name
    private func buildChildNodes(for items: [SettingItem], parentKey: String) -> [HierarchicalSettingNode] {
        // Group items by their next key component after removing parent prefix
        var groups: [String: [SettingItem]] = [:]

        for item in items {
            // Remove parent key and dot from the beginning
            let remainingKey = item.key.hasPrefix(parentKey + ".")
                ? String(item.key.dropFirst(parentKey.count + 1))
                : item.key

            let components = remainingKey.split(separator: ".", maxSplits: 1)
            let nextKey = String(components[0])

            if groups[nextKey] == nil {
                groups[nextKey] = []
            }
            groups[nextKey]?.append(item)
        }

        // Build nodes for each group
        var nodes: [HierarchicalSettingNode] = []

        for (nextKey, groupItems) in groups.sorted(by: { $0.key < $1.key }) {
            if groupItems.count == 1 && groupItems[0].key == "\(parentKey).\(nextKey)" {
                // This is a leaf node
                let item = groupItems[0]
                let node = HierarchicalSettingNode(
                    id: item.key,
                    key: item.key,
                    displayName: nextKey,
                    nodeType: .leaf(item: item)
                )
                nodes.append(node)
            } else {
                // This has more nesting - create parent node
                let fullKey = "\(parentKey).\(nextKey)"
                let children = buildChildNodes(for: groupItems, parentKey: fullKey)
                let node = HierarchicalSettingNode(
                    id: fullKey,
                    key: fullKey,
                    displayName: nextKey,
                    nodeType: .parent(childCount: children.count),
                    children: children
                )
                nodes.append(node)
            }
        }

        return nodes
    }

    // MARK: - Editing Mode Operations

    /// Enter editing mode for the entire project
    public func startEditing() {
        isEditingMode = true
        pendingEdits.removeAll()

        // Pause file watching to prevent conflicts with pending edits
        Task {
            if let observerId = observerId {
                await fileMonitor.unregisterObserver(observerId)
                self.observerId = nil
                logger.info("Paused file watching for editing mode")
            }
        }

        logger.info("Entered editing mode")
    }

    /// Cancel all pending edits and exit editing mode
    public func cancelEditing() {
        let editCount = pendingEdits.count
        isEditingMode = false
        pendingEdits.removeAll()

        // Resume file watching
        Task {
            await setupFileWatcher()
            logger.info("Resumed file watching after cancelling edit mode")
        }

        logger.info("Cancelled editing mode - discarded \(editCount) pending edits")
    }

    /// Check if a specific setting has pending edits
    public func hasPendingEdit(for key: String) -> Bool {
        pendingEdits[key] != nil
    }

    /// Get the pending edit for a setting, or create a temporary one from current value.
    /// Note: This does NOT store the edit in pendingEdits - it's purely for UI display.
    /// Use updatePendingEdit() to actually store an edit.
    public func getPendingEditOrCreate(for item: SettingItem) -> PendingEdit {
        if let existing = pendingEdits[item.key] {
            return existing
        }

        // Create temporary pending edit based on the active contribution (highest precedence)
        let originalFileType = item.contributions.last?.source ?? item.source
        return PendingEdit(key: item.key, value: item.value, targetFileType: originalFileType, originalFileType: originalFileType)
    }

    /// Update a pending edit only if the value has actually changed from the original
    /// - Parameters:
    ///   - item: The original setting item
    ///   - value: The new value
    ///   - targetFileType: The file to save to
    ///   - validationError: Optional validation error to attach to this edit
    ///   - rawEditingText: Optional raw text being edited (for JSON complex types)
    public func updatePendingEditIfChanged(item: SettingItem, value: SettingValue, targetFileType: SettingsFileType, validationError: String? = nil, rawEditingText: String? = nil) {
        // Get the original file type (where the setting currently exists with highest precedence)
        let originalFileType = item.contributions.last?.source ?? item.source

        // Get the original value for this target file type
        let originalValue = item.contributions.first(where: { $0.source == targetFileType })?.value ?? item.value

        // Check if the value has actually changed
        let hasValueChanged = value != originalValue
        let hasTargetChanged = targetFileType != originalFileType

        if !hasValueChanged && !hasTargetChanged && validationError == nil {
            // Value is same as original and target hasn't changed - remove any pending edit
            pendingEdits.removeValue(forKey: item.key)
            logger.debug("Removed pending edit for '\(item.key)' (value unchanged)")
        } else {
            // Value or target has changed - create/update pending edit
            // Preserve the original file type from any existing pending edit, or use the current active source
            let preservedOriginalFileType = pendingEdits[item.key]?.originalFileType ?? originalFileType
            updatePendingEdit(
                key: item.key,
                value: value,
                targetFileType: targetFileType,
                originalFileType: preservedOriginalFileType,
                validationError: validationError,
                rawEditingText: rawEditingText
            )
        }
    }

    /// Update a pending edit (doesn't save to disk yet)
    /// - Parameters:
    ///   - key: The setting key
    ///   - value: The new value
    ///   - targetFileType: The file to save to
    ///   - originalFileType: The file where the setting originally came from
    ///   - validationError: Optional validation error to attach to this edit
    ///   - rawEditingText: Optional raw text being edited (for JSON complex types)
    public func updatePendingEdit(key: String, value: SettingValue, targetFileType: SettingsFileType, originalFileType: SettingsFileType, validationError: String? = nil, rawEditingText: String? = nil) {
        // Validate the value before storing
        let finalValidationError = validationError ?? validateValue(value)

        pendingEdits[key] = PendingEdit(
            key: key,
            value: value,
            targetFileType: targetFileType,
            originalFileType: originalFileType,
            validationError: finalValidationError,
            rawEditingText: rawEditingText
        )
        logger.debug("Updated pending edit for '\(key)' (original: \(originalFileType.displayName), target: \(targetFileType.displayName))\(finalValidationError.map { " with validation error: \($0)" } ?? "")")
    }

    /// Validate a setting value
    /// - Parameter value: The value to validate
    /// - Returns: Validation error message, or nil if valid
    private func validateValue(_ value: SettingValue) -> String? {
        // For complex types (arrays and objects), we can't do much validation here
        // since they're already parsed. Validation should happen before parsing.
        // This is more of a placeholder for future type-specific validation.
        return nil
    }

    /// Set validation error for a pending edit
    /// - Parameters:
    ///   - key: The setting key
    ///   - error: The validation error message, or nil to clear
    public func setValidationError(for key: String, error: String?) {
        guard var edit = pendingEdits[key] else { return }
        edit.validationError = error
        pendingEdits[key] = edit
    }

    /// Save all pending edits to disk with transaction support
    public func saveAllEdits() async throws {
        logger.info("Saving \(pendingEdits.count) pending edits")

        // Check for any validation errors before saving
        let editsWithErrors = pendingEdits.values.filter { $0.validationError != nil }
        guard editsWithErrors.isEmpty else {
            let errorKeys = editsWithErrors.map { $0.key }.joined(separator: ", ")
            throw SettingsError.validationFailed("Cannot save: validation errors in settings: \(errorKeys)")
        }

        // Snapshot current state for rollback in case of failure
        let originalFiles = settingsFiles
        let originalItems = settingItems
        let originalHierarchical = hierarchicalSettings

        // Group edits by target file type for efficient batching
        var editsByFile: [SettingsFileType: [(String, SettingValue)]] = [:]

        // Track settings that need to be deleted from their original file (because they moved)
        var deletesByFile: [SettingsFileType: [String]] = [:]

        for edit in pendingEdits.values {
            if editsByFile[edit.targetFileType] == nil {
                editsByFile[edit.targetFileType] = []
            }
            editsByFile[edit.targetFileType]?.append((edit.id, edit.value))

            // If the target file is different from the original, we need to delete from original (move operation)
            if edit.targetFileType != edit.originalFileType {
                if deletesByFile[edit.originalFileType] == nil {
                    deletesByFile[edit.originalFileType] = []
                }
                deletesByFile[edit.originalFileType]?.append(edit.key)
                logger.debug("Will move '\(edit.key)' from \(edit.originalFileType.displayName) to \(edit.targetFileType.displayName)")
            }
        }

        do {
            // Create backups once per file before applying any edits (both adds and deletes)
            let affectedFileTypes = Set(editsByFile.keys).union(deletesByFile.keys)
            for fileType in affectedFileTypes {
                if let file = settingsFiles.first(where: { $0.type == fileType }) {
                    _ = try await fileSystemManager.createBackup(of: file.path, to: pathProvider.backupDirectory)
                    logger.debug("Created backup for \(fileType.displayName)")
                }
            }

            // First, apply all edits to each target file
            for (fileType, edits) in editsByFile {
                try await applyEditsToFile(fileType, edits: edits)
            }

            // Then, delete settings from their original files (for move operations)
            for (fileType, keys) in deletesByFile {
                guard let fileIndex = settingsFiles.firstIndex(where: { $0.type == fileType }) else {
                    logger.warning("Cannot delete from \(fileType.displayName) - file not found")
                    continue
                }

                var file = settingsFiles[fileIndex]

                // Remove each key from the file
                var updatedContent = file.content
                for key in keys {
                    removeNestedValue(&updatedContent, for: key)
                    logger.debug("Deleted '\(key)' from \(fileType.displayName)")
                }

                file.content = updatedContent
                try await settingsParser.writeSettingsFile(&file)
                settingsFiles[fileIndex] = file
            }

            // Recompute merged settings once after all files are updated
            settingItems = computeSettingItems(from: settingsFiles)
            hierarchicalSettings = computeHierarchicalSettings(from: settingItems)

            // Clear editing state after successful save
            isEditingMode = false
            pendingEdits.removeAll()

            // Resume file watching after successful save
            await setupFileWatcher()
            logger.info("Successfully saved all edits and resumed file watching")
        } catch {
            // Rollback: restore original state
            logger.error("Save failed, rolling back changes: \(error)")
            settingsFiles = originalFiles
            settingItems = originalItems
            hierarchicalSettings = originalHierarchical

            // Re-throw the error so the UI can handle it
            throw error
        }
    }

    // MARK: - Edit Operations

    /// Apply multiple edits to a file without creating backups or recomputing settings
    /// - Parameters:
    ///   - fileType: The file type to update
    ///   - edits: Array of (key, value) pairs to apply
    /// - Throws: SettingsError if the file is read-only or other errors occur
    private func applyEditsToFile(_ fileType: SettingsFileType, edits: [(String, SettingValue)]) async throws {
        // Find or create the file
        if let fileIndex = settingsFiles.firstIndex(where: { $0.type == fileType }) {
            // File exists, update it with all edits
            var file = settingsFiles[fileIndex]

            guard !file.isReadOnly else {
                throw SettingsError.fileIsReadOnly(file.path)
            }

            // Apply all edits to the content
            var updatedContent = file.content
            for (key, value) in edits {
                try setNestedValue(&updatedContent, for: key, value: value)
            }

            // Write the file once with all changes
            file.content = updatedContent
            try await settingsParser.writeSettingsFile(&file)
            settingsFiles[fileIndex] = file

            logger.debug("Applied \(edits.count) edit(s) to \(fileType.displayName)")
        } else {
            // File doesn't exist, create it with all edits
            let homeDirectory = pathProvider.homeDirectory
            let baseDirectory = fileType.isGlobal ? homeDirectory : (project?.path ?? homeDirectory)
            let filePath = fileType.path(in: baseDirectory)

            var newContent: [String: SettingValue] = [:]
            for (key, value) in edits {
                try setNestedValue(&newContent, for: key, value: value)
            }

            var newFile = SettingsFile(
                type: fileType,
                path: filePath,
                content: newContent,
                isValid: true,
                validationErrors: [],
                lastModified: Date(),
                isReadOnly: false
            )

            try await settingsParser.writeSettingsFile(&newFile)
            settingsFiles.append(newFile)
            logger.info("Created new settings file at \(filePath.path) with \(edits.count) setting(s)")
        }
    }

    /// Update a setting value in a specific file
    /// - Parameters:
    ///   - key: The setting key to update
    ///   - value: The new value
    ///   - fileType: The file type to update (defaults to the highest precedence non-enterprise file)
    ///   - skipBackup: If true, skip creating a backup (used for batch operations)
    public func updateSetting(key: String, value: SettingValue, in fileType: SettingsFileType, skipBackup: Bool = false) async throws {
        logger.info("Updating setting '\(key)' in \(fileType.displayName)")

        // Create backup before modifying (only if file exists, unless skipped for batch operations)
        if !skipBackup, let file = settingsFiles.first(where: { $0.type == fileType }) {
            _ = try await fileSystemManager.createBackup(of: file.path, to: pathProvider.backupDirectory)
        }

        // Apply the edit using the helper
        try await applyEditsToFile(fileType, edits: [(key, value)])

        // Recompute merged settings
        settingItems = computeSettingItems(from: settingsFiles)
        hierarchicalSettings = computeHierarchicalSettings(from: settingItems)

        logger.info("Successfully updated setting '\(key)' in \(fileType.displayName)")

        // If this was a plugin-related setting (and not part of a batch), reload marketplace data
        if !skipBackup && isPluginRelatedKey(key) {
            logger.info("Plugin/marketplace setting changed, reloading marketplace data")
            await marketplaceViewModel.loadAll()
        }
    }

    /// Batch update multiple settings to a specific file with a single backup
    /// - Parameters:
    ///   - updates: Array of (key, value) tuples to update
    ///   - fileType: The file type to update
    /// - Note: This method creates a single backup before applying all updates and includes rollback on failure
    public func batchUpdateSettings(_ updates: [(key: String, value: SettingValue)], in fileType: SettingsFileType) async throws {
        guard !updates.isEmpty else { return }

        logger.info("Batch updating \(updates.count) settings in \(fileType.displayName)")

        // Snapshot the file state for potential rollback
        let fileIndex = settingsFiles.firstIndex(where: { $0.type == fileType })
        let originalFile = fileIndex.map { settingsFiles[$0] }

        // Create a single backup before batch operation
        if let file = originalFile {
            _ = try await fileSystemManager.createBackup(of: file.path, to: pathProvider.backupDirectory)
        }

        do {
            // Apply all updates (skip individual backups since we created one above)
            for (key, value) in updates {
                try await updateSetting(key: key, value: value, in: fileType, skipBackup: true)
            }

            logger.info("Successfully batch updated \(updates.count) settings in \(fileType.displayName)")

            // If any keys were plugin-related, reload marketplace data once at the end
            if updates.contains(where: { isPluginRelatedKey($0.key) }) {
                logger.info("Plugin/marketplace settings changed, reloading marketplace data")
                await marketplaceViewModel.loadAll()
            }
        } catch {
            // Rollback on failure: restore file from snapshot
            if let originalFile = originalFile, let index = fileIndex {
                logger.warning("Batch update failed, rolling back file to original state")
                var rollbackFile = originalFile
                try? await settingsParser.writeSettingsFile(&rollbackFile)
                settingsFiles[index] = rollbackFile

                // Recompute state after rollback
                settingItems = computeSettingItems(from: settingsFiles)
                hierarchicalSettings = computeHierarchicalSettings(from: settingItems)
            }
            throw error
        }
    }

    /// Batch delete multiple settings from a specific file
    /// - Parameters:
    ///   - keys: Array of setting keys to delete
    ///   - fileType: The file type to delete from
    /// - Note: This method creates a single backup before applying all deletions and includes rollback on failure
    public func batchDeleteSettings(_ keys: [String], from fileType: SettingsFileType) async throws {
        guard !keys.isEmpty else { return }

        logger.info("Batch deleting \(keys.count) settings from \(fileType.displayName)")

        // Snapshot the file state for potential rollback
        let fileIndex = settingsFiles.firstIndex(where: { $0.type == fileType })
        let originalFile = fileIndex.map { settingsFiles[$0] }

        // Create a single backup before batch operation
        if let file = originalFile {
            _ = try await fileSystemManager.createBackup(of: file.path, to: pathProvider.backupDirectory)
        }

        do {
            // Apply all deletions (skip individual backups since we created one above)
            for key in keys {
                try await deleteSetting(key: key, from: fileType, skipBackup: true)
            }

            logger.info("Successfully batch deleted \(keys.count) settings from \(fileType.displayName)")

            // If any keys were plugin-related, reload marketplace data once at the end
            if keys.contains(where: isPluginRelatedKey) {
                logger.info("Plugin/marketplace settings changed, reloading marketplace data")
                await marketplaceViewModel.loadAll()
            }
        } catch {
            // Rollback on failure: restore file from snapshot
            if let originalFile = originalFile, let index = fileIndex {
                logger.warning("Batch delete failed, rolling back file to original state")
                var rollbackFile = originalFile
                try? await settingsParser.writeSettingsFile(&rollbackFile)
                settingsFiles[index] = rollbackFile

                // Recompute state after rollback
                settingItems = computeSettingItems(from: settingsFiles)
                hierarchicalSettings = computeHierarchicalSettings(from: settingItems)
            }
            throw error
        }
    }

    /// Delete a setting from a specific file
    /// - Parameters:
    ///   - key: The setting key to delete
    ///   - fileType: The file type to delete from
    ///   - skipBackup: If true, skip creating a backup (used for batch operations)
    public func deleteSetting(key: String, from fileType: SettingsFileType, skipBackup: Bool = false) async throws {
        logger.info("Deleting setting '\(key)' from \(fileType.displayName)")

        guard let fileIndex = settingsFiles.firstIndex(where: { $0.type == fileType }) else {
            let homeDirectory = pathProvider.homeDirectory
            let baseDirectory = fileType.isGlobal ? homeDirectory : (project?.path ?? homeDirectory)
            let expectedPath = fileType.path(in: baseDirectory)
            throw SettingsError.fileNotFound(fileType, expectedPath: expectedPath)
        }

        var file = settingsFiles[fileIndex]

        guard !file.isReadOnly else {
            throw SettingsError.fileIsReadOnly(file.path)
        }

        // Create backup before modifying (unless skipped for batch operations)
        if !skipBackup {
            _ = try await fileSystemManager.createBackup(of: file.path, to: pathProvider.backupDirectory)
        }

        // Remove the nested value from the content dictionary
        var updatedContent = file.content
        removeNestedValue(&updatedContent, for: key)

        file.content = updatedContent
        try await settingsParser.writeSettingsFile(&file)

        settingsFiles[fileIndex] = file

        // Recompute merged settings
        settingItems = computeSettingItems(from: settingsFiles)
        hierarchicalSettings = computeHierarchicalSettings(from: settingItems)

        logger.info("Successfully deleted setting '\(key)' from \(fileType.displayName)")

        // If this was a plugin-related setting (and not part of a batch), reload marketplace data
        if !skipBackup && isPluginRelatedKey(key) {
            logger.info("Plugin/marketplace setting changed, reloading marketplace data")
            await marketplaceViewModel.loadAll()
        }
    }

    /// Copy a setting from one file to another
    /// - Parameters:
    ///   - key: The setting key to copy
    ///   - sourceType: The source file type
    ///   - destinationType: The destination file type
    ///   - skipBackup: If true, skip creating a backup (used for batch operations)
    public func copySetting(key: String, from sourceType: SettingsFileType, to destinationType: SettingsFileType, skipBackup: Bool = false) async throws {
        // Skip if source and destination are the same
        guard sourceType != destinationType else {
            logger.info("Skipping copy: source and destination are the same (\(sourceType.displayName))")
            return
        }

        logger.info("Copying setting '\(key)' from \(sourceType.displayName) to \(destinationType.displayName)")

        // Find the setting in the source file
        guard
            let item = settingItems.first(where: { $0.key == key }),
            let contribution = item.contributions.first(where: { $0.source == sourceType }) else {
            throw SettingsError.settingNotFound(key)
        }

        // Copy the value to the destination
        try await updateSetting(key: key, value: contribution.value, in: destinationType, skipBackup: skipBackup)

        logger.info("Successfully copied setting '\(key)' to \(destinationType.displayName)")
    }

    /// Move a setting from one file to another
    /// - Parameters:
    ///   - key: The setting key to move
    ///   - sourceType: The source file type
    ///   - destinationType: The destination file type
    public func moveSetting(key: String, from sourceType: SettingsFileType, to destinationType: SettingsFileType) async throws {
        // Skip if source and destination are the same
        guard sourceType != destinationType else {
            logger.info("Skipping move: source and destination are the same (\(sourceType.displayName))")
            return
        }

        logger.info("Moving setting '\(key)' from \(sourceType.displayName) to \(destinationType.displayName)")

        // First copy to destination
        try await copySetting(key: key, from: sourceType, to: destinationType)

        // Then delete from source
        try await deleteSetting(key: key, from: sourceType)

        logger.info("Successfully moved setting '\(key)' to \(destinationType.displayName)")
    }

    /// Find a node by key using the indexed lookup
    /// - Parameter key: The key to search for
    /// - Returns: The node if found, nil otherwise
    private func findNode(withKey key: String) -> HierarchicalSettingNode? {
        return nodeIndex[key]
    }

    /// Copy a setting or entire setting subtree from one file to another
    /// - Parameters:
    ///   - key: The setting key to copy (can be leaf or parent node)
    ///   - sourceType: The source file type
    ///   - destinationType: The destination file type
    public func copyNode(key: String, from sourceType: SettingsFileType, to destinationType: SettingsFileType) async throws {
        // Skip if source and destination are the same
        guard sourceType != destinationType else {
            logger.info("Skipping copy node: source and destination are the same (\(sourceType.displayName))")
            return
        }

        // Find the node in the hierarchical tree
        guard let node = findNode(withKey: key) else {
            throw SettingsError.settingNotFound(key)
        }

        // Get all leaf keys under this node (including the node itself if it's a leaf)
        let leafKeys = node.allLeafKeys()

        guard !leafKeys.isEmpty else {
            throw SettingsError.settingNotFound(key)
        }

        logger.info("Copying node '\(key)' (\(leafKeys.count) settings) from \(sourceType.displayName) to \(destinationType.displayName)")

        // Collect all (key, value) pairs from the source file
        var updates: [(key: String, value: SettingValue)] = []
        for leafKey in leafKeys {
            guard
                let item = settingItems.first(where: { $0.key == leafKey }),
                let contribution = item.contributions.first(where: { $0.source == sourceType }) else {
                throw SettingsError.settingNotFound(leafKey)
            }
            updates.append((leafKey, contribution.value))
        }

        // Use the unified batch update method which handles backup, rollback, and all file operations
        try await batchUpdateSettings(updates, in: destinationType)

        logger.info("Successfully copied node '\(key)' (\(leafKeys.count) settings) to \(destinationType.displayName)")
    }

    /// Move a setting or entire setting subtree from one file to another
    /// - Parameters:
    ///   - key: The setting key to move (can be leaf or parent node)
    ///   - sourceType: The source file type
    ///   - destinationType: The destination file type
    public func moveNode(key: String, from sourceType: SettingsFileType, to destinationType: SettingsFileType) async throws {
        // Skip if source and destination are the same
        guard sourceType != destinationType else {
            logger.info("Skipping move node: source and destination are the same (\(sourceType.displayName))")
            return
        }

        // Find the node in the hierarchical tree
        guard let node = findNode(withKey: key) else {
            throw SettingsError.settingNotFound(key)
        }

        // Get all leaf keys under this node (including the node itself if it's a leaf)
        let leafKeys = node.allLeafKeys()

        guard !leafKeys.isEmpty else {
            throw SettingsError.settingNotFound(key)
        }

        logger.info("Moving node '\(key)' (\(leafKeys.count) settings) from \(sourceType.displayName) to \(destinationType.displayName)")

        // Collect all (key, value) pairs from the source file
        var updates: [(key: String, value: SettingValue)] = []
        for leafKey in leafKeys {
            guard
                let item = settingItems.first(where: { $0.key == leafKey }),
                let contribution = item.contributions.first(where: { $0.source == sourceType }) else {
                throw SettingsError.settingNotFound(leafKey)
            }
            updates.append((leafKey, contribution.value))
        }

        // Use batch operations for performance (each handles its own backup and rollback)
        // First copy to destination, then delete from source
        try await batchUpdateSettings(updates, in: destinationType)
        try await batchDeleteSettings(leafKeys, from: sourceType)

        logger.info("Successfully moved node '\(key)' (\(leafKeys.count) settings) to \(destinationType.displayName)")
    }

    /// Delete a setting or entire setting subtree from a specific file
    /// - Parameters:
    ///   - key: The setting key to delete (can be leaf or parent node)
    ///   - fileType: The file type to delete from
    public func deleteNode(key: String, from fileType: SettingsFileType) async throws {
        // Find the node in the hierarchical tree
        guard let node = findNode(withKey: key) else {
            throw SettingsError.settingNotFound(key)
        }

        // Get all leaf keys under this node (including the node itself if it's a leaf)
        let leafKeys = node.allLeafKeys()

        guard !leafKeys.isEmpty else {
            throw SettingsError.settingNotFound(key)
        }

        logger.info("Deleting node '\(key)' (\(leafKeys.count) settings) from \(fileType.displayName)")

        // Use batch delete for performance (handles backup and rollback)
        try await batchDeleteSettings(leafKeys, from: fileType)

        logger.info("Successfully deleted node '\(key)' (\(leafKeys.count) settings) from \(fileType.displayName)")
    }

    // MARK: - Helper Methods

    /// Check if a key is related to plugins or marketplaces
    /// These keys require MarketplaceViewModel to reload when changed
    private func isPluginRelatedKey(_ key: String) -> Bool {
        key.hasPrefix("enabledPlugins") || key.hasPrefix("extraKnownMarketplaces")
    }

    /// Set a nested value in a dictionary using dot notation
    /// - Throws: SettingsError.typeMismatch if an existing value is not an object when we need to traverse through it
    /// - Note: For objects, new keys are merged into existing objects. For arrays, new items are appended.
    private func setNestedValue(_ dict: inout [String: SettingValue], for key: String, value: SettingValue) throws {
        let components = key.split(separator: ".")
        if components.count == 1 {
            let simpleKey = String(components[0])

            // Check for merge scenarios when an existing value exists
            if let existingValue = dict[simpleKey] {
                switch (existingValue, value) {
                case let (.object(existingDict), .object(newDict)):
                    // Merge dictionaries: new keys override existing keys
                    var merged = existingDict
                    for (newKey, newVal) in newDict {
                        merged[newKey] = newVal
                    }
                    dict[simpleKey] = .object(merged)
                    return

                case let (.array(existingArray), .array(newArray)):
                    // Append new array items to existing array
                    dict[simpleKey] = .array(existingArray + newArray)
                    return

                default:
                    // For other types or type mismatches, replace
                    break
                }
            }

            // Default: simple assignment (new key or replacement of non-mergeable types)
            dict[simpleKey] = value
        } else {
            let firstKey = String(components[0])
            let remainingKey = components.dropFirst().joined(separator: ".")

            // Get or create the nested dictionary
            var nested: [String: SettingValue]
            if let existingValue = dict[firstKey] {
                // Validate that the existing value is an object
                if case let .object(existing) = existingValue {
                    nested = existing
                } else {
                    // Type mismatch - we need to traverse through this, but it's not an object
                    throw SettingsError.typeMismatch(
                        key: key,
                        expected: "object",
                        found: existingValue.typeName
                    )
                }
            } else {
                // No existing value, create new object
                nested = [:]
            }

            // Recursively set the value
            try setNestedValue(&nested, for: remainingKey, value: value)
            dict[firstKey] = .object(nested)
        }
    }

    /// Remove a nested value from a dictionary using dot notation
    private func removeNestedValue(_ dict: inout [String: SettingValue], for key: String) {
        let components = key.split(separator: ".")
        if components.count == 1 {
            dict.removeValue(forKey: String(components[0]))
        } else {
            let firstKey = String(components[0])
            let remainingKey = components.dropFirst().joined(separator: ".")

            if case var .object(nested) = dict[firstKey] {
                removeNestedValue(&nested, for: remainingKey)

                // If the nested dictionary is now empty, remove it
                if nested.isEmpty {
                    dict.removeValue(forKey: firstKey)
                } else {
                    dict[firstKey] = .object(nested)
                }
            }
        }
    }
}

/// Errors that can occur during settings operations
public enum SettingsError: LocalizedError {
    case fileNotFound(SettingsFileType, expectedPath: URL?)
    case fileIsReadOnly(URL)
    case settingNotFound(String)
    case validationFailed(String)
    case typeMismatch(key: String, expected: String, found: String)
    case serializationFailed(String)
    case invalidFileType(String)
    case invalidKey(String)

    public var errorDescription: String? {
        switch self {
        case let .fileNotFound(type, expectedPath):
            if let path = expectedPath {
                return "Settings file '\(type.displayName)' not found at expected path: \(path.path)"
            } else {
                return "Settings file '\(type.displayName)' not found"
            }
        case let .fileIsReadOnly(url):
            return "Cannot modify read-only file: \(url.lastPathComponent)"
        case let .settingNotFound(key):
            return "Setting '\(key)' not found"
        case let .validationFailed(message):
            return message
        case let .typeMismatch(key, expected, found):
            return "Type mismatch for '\(key)': expected \(expected), but found \(found)"
        case let .serializationFailed(message):
            return "Failed to serialize settings: \(message)"
        case let .invalidFileType(message):
            return "Invalid file type: \(message)"
        case let .invalidKey(message):
            return "Invalid key: \(message)"
        }
    }
}

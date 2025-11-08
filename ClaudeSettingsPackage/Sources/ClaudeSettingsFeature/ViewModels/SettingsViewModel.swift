import Foundation
import Logging
import SwiftUI

/// ViewModel for managing settings of a specific project
@MainActor
@Observable
final public class SettingsViewModel {
    private let fileSystemManager: FileSystemManager
    private let logger = Logger(label: "com.claudesettings.settings")

    public var settingsFiles: [SettingsFile] = []
    public var settingItems: [SettingItem] = []
    public var hierarchicalSettings: [HierarchicalSettingNode] = []
    public var validationErrors: [ValidationError] = []
    public var isLoading = false
    public var errorMessage: String?

    private let settingsParser: SettingsParser
    private let project: ClaudeProject?
    private var fileWatcher: FileWatcher?
    private let debouncer = Debouncer()
    private var consecutiveReloadFailures: [URL: Int] = [:]

    // Undo/Redo support
    private var undoStack: [SettingsCommand] = []
    private var redoStack: [SettingsCommand] = []
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public init(project: ClaudeProject? = nil, fileSystemManager: FileSystemManager = FileSystemManager()) {
        self.project = project
        self.fileSystemManager = fileSystemManager
        self.settingsParser = SettingsParser(fileSystemManager: fileSystemManager)
    }

    /// Load all settings files for the current project
    public func loadSettings() {
        loadSettingsFiles(includeProject: project != nil, projectPath: project?.path)
    }

    /// Load settings files with optional project scope
    private func loadSettingsFiles(includeProject: Bool, projectPath: URL?) {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                var files: [SettingsFile] = []
                let homeDirectory = FileManager.default.homeDirectoryForCurrentUser

                // Load enterprise managed settings first (highest precedence, cannot be overridden)
                for enterprisePath in SettingsFileType.enterpriseManagedPaths(homeDirectory: homeDirectory) where await fileSystemManager.exists(at: enterprisePath) {
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
    }

    /// Set up file watcher to monitor settings files for changes
    private func setupFileWatcher() async {
        // Stop any existing watcher first
        await stopFileWatcher()

        // Only watch files that actually exist
        let pathsToWatch = settingsFiles.map(\.path)

        guard !pathsToWatch.isEmpty else {
            logger.debug("No settings files to watch")
            return
        }

        logger.info("Setting up file watcher for \(pathsToWatch.count) paths")

        // FileWatcher's callback is @Sendable but not MainActor-isolated
        // We need to explicitly hop to MainActor since this ViewModel is MainActor-isolated
        fileWatcher = FileWatcher { [weak self] changedURL in
            Task { @MainActor in
                await self?.handleFileChange(at: changedURL)
            }
        }

        await fileWatcher?.startWatching(paths: pathsToWatch)
    }

    /// Stop file watching (called when switching projects or cleaning up)
    public func stopFileWatcher() async {
        await debouncer.cancel()
        await fileWatcher?.stopWatching()
        fileWatcher = nil
        consecutiveReloadFailures.removeAll()
    }

    /// Handle file system changes with debouncing to prevent excessive reloads
    private func handleFileChange(at url: URL) async {
        // Debounce: wait 200ms before reloading to handle rapid successive changes
        await debouncer.debounce(milliseconds: 200) {
            await self.reloadChangedFile(at: url)
        }
    }

    /// Reload a specific settings file that changed externally
    private func reloadChangedFile(at url: URL) async {
        logger.info("Settings file changed externally: \(url.path)")

        // Find which settings file changed
        guard let changedFileIndex = settingsFiles.firstIndex(where: { $0.path == url }) else {
            logger.warning("Changed file not found in loaded settings: \(url.path)")
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
                contributions: contributions,
                isDeprecated: false, // TODO: Implement deprecation checking
                documentation: nil // TODO: Add documentation lookup
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

        return rootNodes
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

    // MARK: - Edit Operations

    /// Update a setting value in a specific file
    public func updateSetting(key: String, value: SettingValue, in fileType: SettingsFileType) async throws {
        logger.info("Updating setting '\(key)' in \(fileType.displayName)")

        // Find or create the target file
        let targetFile = try await getOrCreateFile(type: fileType)
        let oldContent = targetFile.content

        // Create backup before modifying
        if await fileSystemManager.exists(at: targetFile.path) {
            let backupDir = getBackupDirectory()
            _ = try await fileSystemManager.createBackup(of: targetFile.path, to: backupDir)
        }

        // Update the setting using nested key path
        var updatedContent = targetFile.content
        try setNestedValue(in: &updatedContent, keyPath: key, value: value)

        // Write back to file
        let updatedFile = SettingsFile(
            id: targetFile.id,
            type: targetFile.type,
            path: targetFile.path,
            content: updatedContent,
            isValid: true,
            validationErrors: [],
            lastModified: Date(),
            isReadOnly: targetFile.isReadOnly
        )

        try await settingsParser.writeSettingsFile(updatedFile)

        // Create undo command
        let command = EditSettingCommand(
            viewModel: self,
            key: key,
            fileType: fileType,
            oldContent: oldContent,
            newContent: updatedContent
        )
        undoStack.append(command)
        redoStack.removeAll()

        // Reload to reflect changes
        await reloadChangedFile(at: targetFile.path)

        logger.info("Successfully updated setting '\(key)'")
    }

    /// Copy a setting from one file to another
    public func copySetting(key: String, from sourceType: SettingsFileType, to targetType: SettingsFileType) async throws {
        logger.info("Copying setting '\(key)' from \(sourceType.displayName) to \(targetType.displayName)")

        // Get the value from source
        guard let sourceFile = settingsFiles.first(where: { $0.type == sourceType }),
              let value = getNestedValue(in: sourceFile.content, keyPath: key)
        else {
            throw SettingsError.settingNotFound(key: key, file: sourceType)
        }

        // Update in target file
        try await updateSetting(key: key, value: value, in: targetType)

        logger.info("Successfully copied setting '\(key)'")
    }

    /// Delete a setting from a specific file
    public func deleteSetting(key: String, from fileType: SettingsFileType) async throws {
        logger.info("Deleting setting '\(key)' from \(fileType.displayName)")

        guard let fileIndex = settingsFiles.firstIndex(where: { $0.type == fileType }) else {
            throw SettingsError.fileNotFound(type: fileType)
        }

        let targetFile = settingsFiles[fileIndex]
        let oldContent = targetFile.content

        // Create backup before modifying
        if await fileSystemManager.exists(at: targetFile.path) {
            let backupDir = getBackupDirectory()
            _ = try await fileSystemManager.createBackup(of: targetFile.path, to: backupDir)
        }

        // Remove the setting
        var updatedContent = targetFile.content
        try removeNestedValue(in: &updatedContent, keyPath: key)

        // Write back to file
        let updatedFile = SettingsFile(
            id: targetFile.id,
            type: targetFile.type,
            path: targetFile.path,
            content: updatedContent,
            isValid: true,
            validationErrors: [],
            lastModified: Date(),
            isReadOnly: targetFile.isReadOnly
        )

        try await settingsParser.writeSettingsFile(updatedFile)

        // Create undo command
        let command = DeleteSettingCommand(
            viewModel: self,
            key: key,
            fileType: fileType,
            oldContent: oldContent,
            newContent: updatedContent
        )
        undoStack.append(command)
        redoStack.removeAll()

        // Reload to reflect changes
        await reloadChangedFile(at: targetFile.path)

        logger.info("Successfully deleted setting '\(key)'")
    }

    /// Undo the last operation
    public func undo() async throws {
        guard let command = undoStack.popLast() else { return }

        try await command.undo()
        redoStack.append(command)

        logger.info("Undid last operation")
    }

    /// Redo the last undone operation
    public func redo() async throws {
        guard let command = redoStack.popLast() else { return }

        try await command.execute()
        undoStack.append(command)

        logger.info("Redid operation")
    }

    // MARK: - Helper Methods

    /// Get or create a settings file of the specified type
    private func getOrCreateFile(type: SettingsFileType) async throws -> SettingsFile {
        // Check if file already exists in our loaded files
        if let existingFile = settingsFiles.first(where: { $0.type == type }) {
            return existingFile
        }

        // Create new file
        let baseDirectory: URL
        if type.isGlobal {
            baseDirectory = FileManager.default.homeDirectoryForCurrentUser
        } else {
            guard let projectPath = project?.path else {
                throw SettingsError.noProjectSelected
            }
            baseDirectory = projectPath
        }

        let filePath = type.path(in: baseDirectory)

        // If file doesn't exist on disk, create empty one
        if !(await fileSystemManager.exists(at: filePath)) {
            let emptyFile = SettingsFile(
                type: type,
                path: filePath,
                content: [:],
                isValid: true,
                validationErrors: [],
                lastModified: Date(),
                isReadOnly: false
            )

            try await settingsParser.writeSettingsFile(emptyFile)
            return emptyFile
        }

        // File exists on disk but not loaded yet, parse it
        return try await settingsParser.parseSettingsFile(at: filePath, type: type)
    }

    /// Get backup directory
    private func getBackupDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("ClaudeSettings/backups")
    }

    /// Set a value in a nested dictionary using dot-notation key path
    private func setNestedValue(in dict: inout [String: SettingValue], keyPath: String, value: SettingValue) throws {
        let components = keyPath.split(separator: ".")
        guard !components.isEmpty else {
            throw SettingsError.invalidKeyPath(keyPath)
        }

        if components.count == 1 {
            // Base case: set directly
            dict[String(components[0])] = value
        } else {
            // Recursive case: navigate into nested object
            let firstKey = String(components[0])
            let remainingPath = components.dropFirst().joined(separator: ".")

            // Get or create nested object
            var nestedDict: [String: SettingValue]
            if case let .object(existing) = dict[firstKey] {
                nestedDict = existing
            } else {
                nestedDict = [:]
            }

            // Recursively set in nested object
            try setNestedValue(in: &nestedDict, keyPath: remainingPath, value: value)

            // Update parent
            dict[firstKey] = .object(nestedDict)
        }
    }

    /// Get a value from a nested dictionary using dot-notation key path
    private func getNestedValue(in dict: [String: SettingValue], keyPath: String) -> SettingValue? {
        let components = keyPath.split(separator: ".")
        guard !components.isEmpty else { return nil }

        if components.count == 1 {
            return dict[String(components[0])]
        } else {
            let firstKey = String(components[0])
            let remainingPath = components.dropFirst().joined(separator: ".")

            if case let .object(nestedDict) = dict[firstKey] {
                return getNestedValue(in: nestedDict, keyPath: remainingPath)
            }

            return nil
        }
    }

    /// Remove a value from a nested dictionary using dot-notation key path
    private func removeNestedValue(in dict: inout [String: SettingValue], keyPath: String) throws {
        let components = keyPath.split(separator: ".")
        guard !components.isEmpty else {
            throw SettingsError.invalidKeyPath(keyPath)
        }

        if components.count == 1 {
            // Base case: remove directly
            dict.removeValue(forKey: String(components[0]))
        } else {
            // Recursive case: navigate into nested object
            let firstKey = String(components[0])
            let remainingPath = components.dropFirst().joined(separator: ".")

            guard case var .object(nestedDict) = dict[firstKey] else {
                // Key doesn't exist or is not an object
                return
            }

            // Recursively remove from nested object
            try removeNestedValue(in: &nestedDict, keyPath: remainingPath)

            // Update parent (or remove if empty)
            if nestedDict.isEmpty {
                dict.removeValue(forKey: firstKey)
            } else {
                dict[firstKey] = .object(nestedDict)
            }
        }
    }
}

// MARK: - Command Pattern for Undo/Redo

/// Protocol for undoable commands
protocol SettingsCommand {
    func execute() async throws
    func undo() async throws
}

/// Command for editing a setting
struct EditSettingCommand: SettingsCommand {
    weak var viewModel: SettingsViewModel?
    let key: String
    let fileType: SettingsFileType
    let oldContent: [String: SettingValue]
    let newContent: [String: SettingValue]

    func execute() async throws {
        guard let viewModel else { return }

        // Apply new content
        if let fileIndex = await viewModel.settingsFiles.firstIndex(where: { $0.type == fileType }) {
            let file = await viewModel.settingsFiles[fileIndex]
            let updatedFile = SettingsFile(
                id: file.id,
                type: file.type,
                path: file.path,
                content: newContent,
                isValid: file.isValid,
                validationErrors: file.validationErrors,
                lastModified: Date(),
                isReadOnly: file.isReadOnly
            )

            try await viewModel.settingsParser.writeSettingsFile(updatedFile)
            await viewModel.reloadChangedFile(at: file.path)
        }
    }

    func undo() async throws {
        guard let viewModel else { return }

        // Restore old content
        if let fileIndex = await viewModel.settingsFiles.firstIndex(where: { $0.type == fileType }) {
            let file = await viewModel.settingsFiles[fileIndex]
            let restoredFile = SettingsFile(
                id: file.id,
                type: file.type,
                path: file.path,
                content: oldContent,
                isValid: file.isValid,
                validationErrors: file.validationErrors,
                lastModified: Date(),
                isReadOnly: file.isReadOnly
            )

            try await viewModel.settingsParser.writeSettingsFile(restoredFile)
            await viewModel.reloadChangedFile(at: file.path)
        }
    }
}

/// Command for deleting a setting
struct DeleteSettingCommand: SettingsCommand {
    weak var viewModel: SettingsViewModel?
    let key: String
    let fileType: SettingsFileType
    let oldContent: [String: SettingValue]
    let newContent: [String: SettingValue]

    func execute() async throws {
        guard let viewModel else { return }

        // Apply deletion (new content)
        if let fileIndex = await viewModel.settingsFiles.firstIndex(where: { $0.type == fileType }) {
            let file = await viewModel.settingsFiles[fileIndex]
            let updatedFile = SettingsFile(
                id: file.id,
                type: file.type,
                path: file.path,
                content: newContent,
                isValid: file.isValid,
                validationErrors: file.validationErrors,
                lastModified: Date(),
                isReadOnly: file.isReadOnly
            )

            try await viewModel.settingsParser.writeSettingsFile(updatedFile)
            await viewModel.reloadChangedFile(at: file.path)
        }
    }

    func undo() async throws {
        guard let viewModel else { return }

        // Restore deleted content
        if let fileIndex = await viewModel.settingsFiles.firstIndex(where: { $0.type == fileType }) {
            let file = await viewModel.settingsFiles[fileIndex]
            let restoredFile = SettingsFile(
                id: file.id,
                type: file.type,
                path: file.path,
                content: oldContent,
                isValid: file.isValid,
                validationErrors: file.validationErrors,
                lastModified: Date(),
                isReadOnly: file.isReadOnly
            )

            try await viewModel.settingsParser.writeSettingsFile(restoredFile)
            await viewModel.reloadChangedFile(at: file.path)
        }
    }
}

// MARK: - Errors

enum SettingsError: LocalizedError {
    case settingNotFound(key: String, file: SettingsFileType)
    case fileNotFound(type: SettingsFileType)
    case noProjectSelected
    case invalidKeyPath(String)

    var errorDescription: String? {
        switch self {
        case let .settingNotFound(key, file):
            return "Setting '\(key)' not found in \(file.displayName)"
        case let .fileNotFound(type):
            return "Settings file of type \(type.displayName) not found"
        case .noProjectSelected:
            return "No project selected. Project-level settings require an active project."
        case let .invalidKeyPath(path):
            return "Invalid key path: '\(path)'"
        }
    }
}

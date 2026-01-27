import Foundation
import Testing
@testable import ClaudeSettingsFeature

// MARK: - Test Fixtures

/// Shared test fixtures for marketplace tests
private enum TestFixtures {
    static let testHomeDirectory = URL(fileURLWithPath: "/tmp/test-home")

    static func makePathProvider() -> MockPathProvider {
        MockPathProvider(homeDirectory: testHomeDirectory)
    }

    static func makeKnownMarketplacesJSON() -> Data {
        """
        {
            "TestMarketplace": {
                "source": {
                    "source": "github",
                    "repo": "test/plugins",
                    "ref": "main"
                },
                "installLocation": "/tmp/test-home/.claude/plugins/marketplaces/TestMarketplace",
                "lastUpdated": "2026-01-24T12:00:00Z"
            },
            "AnotherMarketplace": {
                "source": {
                    "source": "directory",
                    "path": "/local/plugins"
                },
                "installLocation": "/local/plugins"
            }
        }
        """.data(using: .utf8)!
    }

    static func makeInstalledPluginsJSON() -> Data {
        """
        {
            "version": 1,
            "plugins": {
                "plugin-a@TestMarketplace": [
                    {
                        "scope": "user",
                        "installPath": "/tmp/cache/TestMarketplace/plugin-a/1.0.0",
                        "version": "1.0.0",
                        "installedAt": "2026-01-20T10:00:00Z",
                        "lastUpdated": "2026-01-20T10:00:00Z"
                    }
                ],
                "plugin-b@TestMarketplace": [
                    {
                        "scope": "user",
                        "installPath": "/tmp/cache/TestMarketplace/plugin-b/2.0.0",
                        "version": "2.0.0",
                        "installedAt": "2026-01-21T10:00:00Z",
                        "lastUpdated": "2026-01-21T10:00:00Z"
                    }
                ]
            }
        }
        """.data(using: .utf8)!
    }

    static func makeEmptyPluginsJSON() -> Data {
        """
        {
            "version": 1,
            "plugins": {}
        }
        """.data(using: .utf8)!
    }
}

// MARK: - Data Loading Tests

@Suite("MarketplaceViewModel Loading")
struct MarketplaceViewModelLoadingTests {
    @Test("loadAll completes without error when files exist")
    @MainActor
    func loadAllCompletesWithoutError() async {
        let pathProvider = TestFixtures.makePathProvider()
        let mockFS = MockFileSystemManager()

        // Set up mock files
        await mockFS.addFile(at: pathProvider.knownMarketplacesPath, content: TestFixtures.makeKnownMarketplacesJSON())
        await mockFS.addFile(at: pathProvider.installedPluginsPath, content: TestFixtures.makeInstalledPluginsJSON())

        let viewModel = MarketplaceViewModel(
            pathProvider: pathProvider,
            fileSystemManager: mockFS
        )

        await viewModel.loadAll()

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isLoading == false)
    }

    @Test("loadAll populates marketplaces array")
    @MainActor
    func loadAllPopulatesMarketplaces() async {
        let pathProvider = TestFixtures.makePathProvider()
        let mockFS = MockFileSystemManager()

        await mockFS.addFile(at: pathProvider.knownMarketplacesPath, content: TestFixtures.makeKnownMarketplacesJSON())
        await mockFS.addFile(at: pathProvider.installedPluginsPath, content: TestFixtures.makeEmptyPluginsJSON())

        let viewModel = MarketplaceViewModel(
            pathProvider: pathProvider,
            fileSystemManager: mockFS
        )

        await viewModel.loadAll()

        #expect(viewModel.marketplaces.count == 2)
        #expect(viewModel.marketplaces.contains { $0.name == "TestMarketplace" })
        #expect(viewModel.marketplaces.contains { $0.name == "AnotherMarketplace" })
    }

    @Test("loadAll populates plugins array")
    @MainActor
    func loadAllPopulatesPlugins() async {
        let pathProvider = TestFixtures.makePathProvider()
        let mockFS = MockFileSystemManager()

        await mockFS.addFile(at: pathProvider.knownMarketplacesPath, content: TestFixtures.makeKnownMarketplacesJSON())
        await mockFS.addFile(at: pathProvider.installedPluginsPath, content: TestFixtures.makeInstalledPluginsJSON())

        let viewModel = MarketplaceViewModel(
            pathProvider: pathProvider,
            fileSystemManager: mockFS
        )

        await viewModel.loadAll()

        #expect(viewModel.plugins.count == 2)
        #expect(viewModel.plugins.contains { $0.name == "plugin-a" })
        #expect(viewModel.plugins.contains { $0.name == "plugin-b" })
    }

    @Test("loadAll handles missing files gracefully")
    @MainActor
    func loadAllHandlesMissingFiles() async {
        let pathProvider = TestFixtures.makePathProvider()
        let mockFS = MockFileSystemManager()

        // No files added - both should be missing

        let viewModel = MarketplaceViewModel(
            pathProvider: pathProvider,
            fileSystemManager: mockFS
        )

        await viewModel.loadAll()

        // Should complete without error (empty results)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.marketplaces.isEmpty)
        #expect(viewModel.plugins.isEmpty)
    }

    @Test("marketplace(named:) returns correct marketplace")
    @MainActor
    func marketplaceNamedReturnsCorrect() async {
        let pathProvider = TestFixtures.makePathProvider()
        let mockFS = MockFileSystemManager()

        await mockFS.addFile(at: pathProvider.knownMarketplacesPath, content: TestFixtures.makeKnownMarketplacesJSON())
        await mockFS.addFile(at: pathProvider.installedPluginsPath, content: TestFixtures.makeEmptyPluginsJSON())

        let viewModel = MarketplaceViewModel(
            pathProvider: pathProvider,
            fileSystemManager: mockFS
        )

        await viewModel.loadAll()

        let marketplace = viewModel.marketplace(named: "TestMarketplace")

        #expect(marketplace != nil)
        #expect(marketplace?.name == "TestMarketplace")
        #expect(marketplace?.source.repo == "test/plugins")
    }

    @Test("marketplace(named:) returns nil for unknown name")
    @MainActor
    func marketplaceNamedReturnsNilForUnknown() async {
        let pathProvider = TestFixtures.makePathProvider()
        let mockFS = MockFileSystemManager()

        await mockFS.addFile(at: pathProvider.knownMarketplacesPath, content: TestFixtures.makeKnownMarketplacesJSON())
        await mockFS.addFile(at: pathProvider.installedPluginsPath, content: TestFixtures.makeEmptyPluginsJSON())

        let viewModel = MarketplaceViewModel(
            pathProvider: pathProvider,
            fileSystemManager: mockFS
        )

        await viewModel.loadAll()

        let marketplace = viewModel.marketplace(named: "NonexistentMarketplace")

        #expect(marketplace == nil)
    }

    @Test("plugins(from:) filters by marketplace name")
    @MainActor
    func pluginsFromFilters() async {
        let pathProvider = TestFixtures.makePathProvider()
        let mockFS = MockFileSystemManager()

        await mockFS.addFile(at: pathProvider.knownMarketplacesPath, content: TestFixtures.makeKnownMarketplacesJSON())
        await mockFS.addFile(at: pathProvider.installedPluginsPath, content: TestFixtures.makeInstalledPluginsJSON())

        let viewModel = MarketplaceViewModel(
            pathProvider: pathProvider,
            fileSystemManager: mockFS
        )

        await viewModel.loadAll()

        let plugins = viewModel.plugins(from: "TestMarketplace")

        #expect(plugins.count == 2)
        #expect(plugins.allSatisfy { $0.marketplace == "TestMarketplace" })
    }

    @Test("globalPlugins(from:) excludes cache-only plugins")
    @MainActor
    func globalPluginsExcludesCacheOnly() async {
        let pathProvider = TestFixtures.makePathProvider()
        let mockFS = MockFileSystemManager()

        await mockFS.addFile(at: pathProvider.knownMarketplacesPath, content: TestFixtures.makeKnownMarketplacesJSON())
        await mockFS.addFile(at: pathProvider.installedPluginsPath, content: TestFixtures.makeInstalledPluginsJSON())

        let viewModel = MarketplaceViewModel(
            pathProvider: pathProvider,
            fileSystemManager: mockFS
        )

        await viewModel.loadAll()

        let globalPlugins = viewModel.globalPlugins(from: "TestMarketplace")

        // All plugins should be global (from installed_plugins.json)
        #expect(globalPlugins.allSatisfy { $0.dataSource == .global || $0.dataSource == .both })
    }
}

// MARK: - Editing State Tests

@Suite("MarketplaceViewModel Editing")
struct MarketplaceViewModelEditingTests {
    @Test("startEditing sets isEditingMode true")
    @MainActor
    func startEditingSetsFlag() async {
        let viewModel = MarketplaceViewModel(
            pathProvider: TestFixtures.makePathProvider(),
            fileSystemManager: MockFileSystemManager()
        )

        #expect(viewModel.isEditingMode == false)

        viewModel.startEditing()

        #expect(viewModel.isEditingMode == true)
    }

    @Test("startEditing clears pending edits")
    @MainActor
    func startEditingClearsPendingEdits() async {
        let viewModel = MarketplaceViewModel(
            pathProvider: TestFixtures.makePathProvider(),
            fileSystemManager: MockFileSystemManager()
        )

        // Add some pending edits
        viewModel.pendingMarketplaceEdits["test"] = MarketplacePendingEdit(name: "test", isNew: true)
        viewModel.pluginsToInstall["test@market"] = AvailablePlugin(
            name: "test",
            marketplace: "market",
            path: URL(fileURLWithPath: "/tmp")
        )

        viewModel.startEditing()

        #expect(viewModel.pendingMarketplaceEdits.isEmpty)
        #expect(viewModel.pendingPluginEdits.isEmpty)
        #expect(viewModel.marketplacesToDelete.isEmpty)
        #expect(viewModel.pluginsToDelete.isEmpty)
        #expect(viewModel.pluginsToInstall.isEmpty)
    }

    @Test("cancelEditing resets all state")
    @MainActor
    func cancelEditingResetsState() async {
        let viewModel = MarketplaceViewModel(
            pathProvider: TestFixtures.makePathProvider(),
            fileSystemManager: MockFileSystemManager()
        )

        viewModel.startEditing()
        viewModel.pendingMarketplaceEdits["test"] = MarketplacePendingEdit(name: "test", isNew: true)
        viewModel.marketplacesToDelete.insert("other")

        viewModel.cancelEditing()

        #expect(viewModel.isEditingMode == false)
        #expect(viewModel.pendingMarketplaceEdits.isEmpty)
        #expect(viewModel.marketplacesToDelete.isEmpty)
    }

    @Test("hasUnsavedChanges returns true with pending edits")
    @MainActor
    func hasUnsavedChangesWithPendingEdits() async {
        let viewModel = MarketplaceViewModel(
            pathProvider: TestFixtures.makePathProvider(),
            fileSystemManager: MockFileSystemManager()
        )

        #expect(viewModel.hasUnsavedChanges == false)

        viewModel.pendingMarketplaceEdits["test"] = MarketplacePendingEdit(name: "test", isNew: true)

        #expect(viewModel.hasUnsavedChanges == true)
    }

    @Test("hasUnsavedChanges returns true with deletions")
    @MainActor
    func hasUnsavedChangesWithDeletions() async {
        let viewModel = MarketplaceViewModel(
            pathProvider: TestFixtures.makePathProvider(),
            fileSystemManager: MockFileSystemManager()
        )

        #expect(viewModel.hasUnsavedChanges == false)

        viewModel.marketplacesToDelete.insert("test")

        #expect(viewModel.hasUnsavedChanges == true)
    }

    @Test("hasUnsavedChanges returns true with install queue")
    @MainActor
    func hasUnsavedChangesWithInstallQueue() async {
        let viewModel = MarketplaceViewModel(
            pathProvider: TestFixtures.makePathProvider(),
            fileSystemManager: MockFileSystemManager()
        )

        #expect(viewModel.hasUnsavedChanges == false)

        viewModel.pluginsToInstall["test@market"] = AvailablePlugin(
            name: "test",
            marketplace: "market",
            path: URL(fileURLWithPath: "/tmp")
        )

        #expect(viewModel.hasUnsavedChanges == true)
    }

    @Test("hasUnsavedChanges returns false when clean")
    @MainActor
    func hasUnsavedChangesWhenClean() async {
        let viewModel = MarketplaceViewModel(
            pathProvider: TestFixtures.makePathProvider(),
            fileSystemManager: MockFileSystemManager()
        )

        viewModel.startEditing()

        #expect(viewModel.hasUnsavedChanges == false)
    }

    @Test("allEditsValid returns false with validation errors")
    @MainActor
    func allEditsValidWithErrors() async {
        let viewModel = MarketplaceViewModel(
            pathProvider: TestFixtures.makePathProvider(),
            fileSystemManager: MockFileSystemManager()
        )

        // Create edit with empty name (invalid)
        viewModel.pendingMarketplaceEdits["test"] = MarketplacePendingEdit(name: "", isNew: true)

        #expect(viewModel.allEditsValid == false)
    }

    @Test("allEditsValid returns true when all valid")
    @MainActor
    func allEditsValidWhenValid() async {
        let viewModel = MarketplaceViewModel(
            pathProvider: TestFixtures.makePathProvider(),
            fileSystemManager: MockFileSystemManager()
        )

        // Create valid edit
        var edit = MarketplacePendingEdit(name: "ValidName", isNew: true)
        edit.sourceType = "github"
        edit.repo = "owner/repo"
        viewModel.pendingMarketplaceEdits["test"] = edit

        #expect(viewModel.allEditsValid == true)
    }
}

// MARK: - Marketplace CRUD Tests

@Suite("MarketplaceViewModel Marketplace CRUD")
struct MarketplaceViewModelMarketplaceCRUDTests {
    @Test("createNewMarketplace returns valid edit object")
    @MainActor
    func createNewMarketplace() async {
        let viewModel = MarketplaceViewModel(
            pathProvider: TestFixtures.makePathProvider(),
            fileSystemManager: MockFileSystemManager()
        )

        let edit = viewModel.createNewMarketplace()

        #expect(edit.isNew == true)
        #expect(edit.name == "NewMarketplace")
        #expect(edit.sourceType == "github")
        #expect(edit.original == nil)
    }

    @Test("deleteMarketplace marks for deletion")
    @MainActor
    func deleteMarketplaceMarksForDeletion() async {
        let viewModel = MarketplaceViewModel(
            pathProvider: TestFixtures.makePathProvider(),
            fileSystemManager: MockFileSystemManager()
        )

        #expect(viewModel.isMarkedForDeletion(marketplace: "TestMarket") == false)

        viewModel.deleteMarketplace(named: "TestMarket")

        #expect(viewModel.isMarkedForDeletion(marketplace: "TestMarket") == true)
        #expect(viewModel.marketplacesToDelete.contains("TestMarket"))
    }

    @Test("restoreMarketplace removes deletion mark")
    @MainActor
    func restoreMarketplaceRemovesDeletionMark() async {
        let viewModel = MarketplaceViewModel(
            pathProvider: TestFixtures.makePathProvider(),
            fileSystemManager: MockFileSystemManager()
        )

        viewModel.deleteMarketplace(named: "TestMarket")
        #expect(viewModel.isMarkedForDeletion(marketplace: "TestMarket") == true)

        viewModel.restoreMarketplace(named: "TestMarket")

        #expect(viewModel.isMarkedForDeletion(marketplace: "TestMarket") == false)
    }

    @Test("pendingEdit creates from existing marketplace")
    @MainActor
    func pendingEditFromExisting() async {
        let pathProvider = TestFixtures.makePathProvider()
        let mockFS = MockFileSystemManager()

        await mockFS.addFile(at: pathProvider.knownMarketplacesPath, content: TestFixtures.makeKnownMarketplacesJSON())
        await mockFS.addFile(at: pathProvider.installedPluginsPath, content: TestFixtures.makeEmptyPluginsJSON())

        let viewModel = MarketplaceViewModel(
            pathProvider: pathProvider,
            fileSystemManager: mockFS
        )

        await viewModel.loadAll()

        let marketplace = viewModel.marketplaces.first { $0.name == "TestMarketplace" }!
        let edit = viewModel.pendingEdit(for: marketplace)

        #expect(edit.name == "TestMarketplace")
        #expect(edit.original?.name == "TestMarketplace")
        #expect(edit.isNew == false)
    }

    @Test("updatePendingEdit updates state")
    @MainActor
    func updatePendingEditUpdatesState() async {
        let viewModel = MarketplaceViewModel(
            pathProvider: TestFixtures.makePathProvider(),
            fileSystemManager: MockFileSystemManager()
        )

        var edit = viewModel.createNewMarketplace()
        edit.name = "UpdatedName"
        edit.repo = "new/repo"

        viewModel.updatePendingEdit(edit, for: "test-key")

        let storedEdit = viewModel.pendingMarketplaceEdits["test-key"]
        #expect(storedEdit?.name == "UpdatedName")
        #expect(storedEdit?.repo == "new/repo")
    }
}

// MARK: - Plugin Operations Tests

@Suite("MarketplaceViewModel Plugin Operations")
struct MarketplaceViewModelPluginOperationsTests {
    @Test("queuePluginInstall adds to install queue")
    @MainActor
    func queuePluginInstallAddsToQueue() async {
        let viewModel = MarketplaceViewModel(
            pathProvider: TestFixtures.makePathProvider(),
            fileSystemManager: MockFileSystemManager()
        )

        let plugin = AvailablePlugin(
            name: "test-plugin",
            marketplace: "TestMarket",
            path: URL(fileURLWithPath: "/tmp/plugin")
        )

        viewModel.queuePluginInstall(plugin)

        #expect(viewModel.pluginsToInstall[plugin.id] != nil)
        #expect(viewModel.isQueuedForInstall(plugin) == true)
    }

    @Test("unqueuePluginInstall removes from queue")
    @MainActor
    func unqueuePluginInstallRemovesFromQueue() async {
        let viewModel = MarketplaceViewModel(
            pathProvider: TestFixtures.makePathProvider(),
            fileSystemManager: MockFileSystemManager()
        )

        let plugin = AvailablePlugin(
            name: "test-plugin",
            marketplace: "TestMarket",
            path: URL(fileURLWithPath: "/tmp/plugin")
        )

        viewModel.queuePluginInstall(plugin)
        #expect(viewModel.isQueuedForInstall(plugin) == true)

        viewModel.unqueuePluginInstall(plugin)

        #expect(viewModel.isQueuedForInstall(plugin) == false)
        #expect(viewModel.pluginsToInstall[plugin.id] == nil)
    }

    @Test("isQueuedForInstall returns correct state")
    @MainActor
    func isQueuedForInstallReturnsCorrectState() async {
        let viewModel = MarketplaceViewModel(
            pathProvider: TestFixtures.makePathProvider(),
            fileSystemManager: MockFileSystemManager()
        )

        let plugin = AvailablePlugin(
            name: "test-plugin",
            marketplace: "TestMarket",
            path: URL(fileURLWithPath: "/tmp/plugin")
        )

        #expect(viewModel.isQueuedForInstall(plugin) == false)

        viewModel.queuePluginInstall(plugin)

        #expect(viewModel.isQueuedForInstall(plugin) == true)
    }

    @Test("isPluginInstalled detects installed plugins")
    @MainActor
    func isPluginInstalledDetects() async {
        let pathProvider = TestFixtures.makePathProvider()
        let mockFS = MockFileSystemManager()

        await mockFS.addFile(at: pathProvider.knownMarketplacesPath, content: TestFixtures.makeKnownMarketplacesJSON())
        await mockFS.addFile(at: pathProvider.installedPluginsPath, content: TestFixtures.makeInstalledPluginsJSON())

        let viewModel = MarketplaceViewModel(
            pathProvider: pathProvider,
            fileSystemManager: mockFS
        )

        await viewModel.loadAll()

        let installedPlugin = AvailablePlugin(
            name: "plugin-a",
            marketplace: "TestMarketplace",
            path: URL(fileURLWithPath: "/tmp")
        )

        let notInstalledPlugin = AvailablePlugin(
            name: "not-installed",
            marketplace: "TestMarketplace",
            path: URL(fileURLWithPath: "/tmp")
        )

        #expect(viewModel.isPluginInstalled(installedPlugin) == true)
        #expect(viewModel.isPluginInstalled(notInstalledPlugin) == false)
    }

    @Test("deletePlugin marks for deletion")
    @MainActor
    func deletePluginMarksForDeletion() async {
        let viewModel = MarketplaceViewModel(
            pathProvider: TestFixtures.makePathProvider(),
            fileSystemManager: MockFileSystemManager()
        )

        let pluginId = "test-plugin@TestMarket"

        #expect(viewModel.isMarkedForDeletion(plugin: pluginId) == false)

        viewModel.deletePlugin(id: pluginId)

        #expect(viewModel.isMarkedForDeletion(plugin: pluginId) == true)
        #expect(viewModel.pluginsToDelete.contains(pluginId))
    }

    @Test("restorePlugin removes deletion mark")
    @MainActor
    func restorePluginRemovesDeletionMark() async {
        let viewModel = MarketplaceViewModel(
            pathProvider: TestFixtures.makePathProvider(),
            fileSystemManager: MockFileSystemManager()
        )

        let pluginId = "test-plugin@TestMarket"

        viewModel.deletePlugin(id: pluginId)
        #expect(viewModel.isMarkedForDeletion(plugin: pluginId) == true)

        viewModel.restorePlugin(id: pluginId)

        #expect(viewModel.isMarkedForDeletion(plugin: pluginId) == false)
    }
}

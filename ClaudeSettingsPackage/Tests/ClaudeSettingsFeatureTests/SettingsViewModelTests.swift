import Foundation
import Testing
@testable import ClaudeSettingsFeature

/// Tests for SettingsViewModel settings hierarchy and precedence resolution
@Suite("SettingsViewModel Tests")
struct SettingsViewModelTests {
    /// Test that settings are correctly computed with proper precedence
    @Test("Settings precedence is correctly applied")
    @MainActor
    func settingsPrecedence() async throws {
        // Given: Multiple settings files with different precedence levels
        let globalFile = SettingsFile(
            type: .globalSettings,
            path: URL(fileURLWithPath: "/tmp/global.json"),
            content: [
                "theme": .string("dark"),
                "fontSize": .int(12),
            ]
        )

        let projectFile = SettingsFile(
            type: .projectSettings,
            path: URL(fileURLWithPath: "/tmp/project.json"),
            content: [
                "theme": .string("light"), // Should override global
                "tabSize": .int(2),
            ]
        )

        // When: Computing setting items
        let viewModel = SettingsViewModel()
        let items = viewModel.computeSettingItems(from: [globalFile, projectFile])

        // Then: Higher precedence values should win
        let themeItem = items.first { $0.key == "theme" }
        #expect(themeItem != nil, "Theme setting should exist")
        #expect(themeItem?.value == .string("light"), "Project theme should override global")
        #expect(themeItem?.overriddenBy == .projectSettings, "Should show override source")

        let fontSizeItem = items.first { $0.key == "fontSize" }
        #expect(fontSizeItem?.value == .int(12), "Global fontSize should be present")
        #expect(fontSizeItem?.overriddenBy == nil, "Should not be overridden")

        let tabSizeItem = items.first { $0.key == "tabSize" }
        #expect(tabSizeItem?.value == .int(2), "Project tabSize should be present")
    }

    /// Test that array settings track multiple contributions
    @Test("Array settings track contributions")
    @MainActor
    func arraySettingsTrackContributions() async throws {
        // Given: Array settings in multiple files
        let globalFile = SettingsFile(
            type: .globalSettings,
            path: URL(fileURLWithPath: "/tmp/global.json"),
            content: [
                "permissions": .array([.string("Read"), .string("Write")]),
            ]
        )

        let projectFile = SettingsFile(
            type: .projectSettings,
            path: URL(fileURLWithPath: "/tmp/project.json"),
            content: [
                "permissions": .array([.string("Bash")]),
            ]
        )

        // When: Computing setting items
        let viewModel = SettingsViewModel()
        let items = viewModel.computeSettingItems(from: [globalFile, projectFile])

        // Then: Should track contributions from both sources (highest precedence wins for value)
        let permissionsItem = items.first { $0.key == "permissions" }
        #expect(permissionsItem != nil, "Permissions should exist")

        // Value shows highest precedence array
        if case let .array(permissions) = permissionsItem?.value {
            #expect(permissions.count == 1, "Value should be from highest precedence source")
        } else {
            Issue.record("Expected array value")
        }

        // But contributions show both sources
        #expect(permissionsItem?.contributions.count == 2, "Should track two contributors")
    }

    /// Test that nested objects are properly flattened
    @Test("Nested objects are flattened correctly")
    @MainActor
    func nestedObjectFlattening() async throws {
        // Given: Nested settings structure
        let file = SettingsFile(
            type: .globalSettings,
            path: URL(fileURLWithPath: "/tmp/test.json"),
            content: [
                "hooks": .object([
                    "onToolCall": .string("echo 'tool called'"),
                    "onRead": .string("echo 'file read'"),
                ]),
            ]
        )

        // When: Computing setting items
        let viewModel = SettingsViewModel()
        let items = viewModel.computeSettingItems(from: [file])

        // Then: Should be flattened to dot notation
        let onToolCallItem = items.first { $0.key == "hooks.onToolCall" }
        #expect(onToolCallItem != nil, "Should have flattened hooks.onToolCall")
        #expect(onToolCallItem?.value == .string("echo 'tool called'"))

        let onReadItem = items.first { $0.key == "hooks.onRead" }
        #expect(onReadItem != nil, "Should have flattened hooks.onRead")
    }

    /// Test enterprise settings precedence (highest)
    @Test("Enterprise settings have highest precedence")
    @MainActor
    func enterpriseSettingsPrecedence() async throws {
        // Given: Enterprise and project settings with conflicting values
        let enterpriseFile = SettingsFile(
            type: .enterpriseManaged,
            path: URL(fileURLWithPath: "/tmp/enterprise.json"),
            content: [
                "maxTokens": .int(1_000),
            ]
        )

        let projectFile = SettingsFile(
            type: .projectLocal,
            path: URL(fileURLWithPath: "/tmp/project.json"),
            content: [
                "maxTokens": .int(5_000), // Should NOT override enterprise
            ]
        )

        // When: Computing setting items
        let viewModel = SettingsViewModel()
        let items = viewModel.computeSettingItems(from: [enterpriseFile, projectFile])

        // Then: Enterprise should win (highest precedence)
        let maxTokensItem = items.first { $0.key == "maxTokens" }
        #expect(maxTokensItem?.value == .int(1_000), "Enterprise should win with highest precedence")
        #expect(maxTokensItem?.overriddenBy == .enterpriseManaged, "Should show enterprise as final override")
    }

    /// Test that contribution tracking works correctly
    @Test("Source contributions are tracked")
    @MainActor
    func sourceContributions() async throws {
        // Given: Settings from multiple sources
        let global = SettingsFile(
            type: .globalSettings,
            path: URL(fileURLWithPath: "/tmp/global.json"),
            content: ["setting": .string("value1")]
        )

        let project = SettingsFile(
            type: .projectSettings,
            path: URL(fileURLWithPath: "/tmp/project.json"),
            content: ["setting": .string("value2")]
        )

        // When: Computing setting items
        let viewModel = SettingsViewModel()
        let items = viewModel.computeSettingItems(from: [global, project])

        // Then: Should track all contributions
        let item = items.first { $0.key == "setting" }
        #expect(item?.contributions.count == 2, "Should have two contributions")
        #expect(item?.contributions[0].source == .globalSettings, "First should be global")
        #expect(item?.contributions[1].source == .projectSettings, "Second should be project")
        #expect(item?.source == .globalSettings, "Source should be lowest precedence")
    }

    /// Test empty settings files
    @Test("Empty settings files are handled correctly")
    @MainActor
    func emptySettings() async throws {
        // Given: Empty settings file
        let emptyFile = SettingsFile(
            type: .globalSettings,
            path: URL(fileURLWithPath: "/tmp/empty.json"),
            content: [:]
        )

        // When: Computing setting items
        let viewModel = SettingsViewModel()
        let items = viewModel.computeSettingItems(from: [emptyFile])

        // Then: Should return empty array
        #expect(items.isEmpty, "Should have no settings")
    }

    /// Test hierarchical tree construction with simple flat settings
    @Test("Hierarchical tree handles flat settings")
    @MainActor
    func hierarchicalFlatSettings() async throws {
        // Given: Flat settings with no dots
        let viewModel = SettingsViewModel()
        let items = [
            SettingItem(
                key: "theme",
                value: .string("dark"),
                source: .globalSettings,
                contributions: [SourceContribution(source: .globalSettings, value: .string("dark"))]
            ),
            SettingItem(
                key: "fontSize",
                value: .int(14),
                source: .globalSettings,
                contributions: [SourceContribution(source: .globalSettings, value: .int(14))]
            ),
        ]

        // When: Computing hierarchical settings
        let hierarchy = viewModel.computeHierarchicalSettings(from: items)

        // Then: Should create leaf nodes at root level
        #expect(hierarchy.count == 2, "Should have two root nodes")
        #expect(hierarchy[0].key == "fontSize", "First should be fontSize (alphabetical)")
        #expect(hierarchy[0].isLeaf, "Should be a leaf node")
        #expect(hierarchy[0].displayName == "fontSize")
        #expect(hierarchy[1].key == "theme", "Second should be theme")
        #expect(hierarchy[1].isLeaf, "Should be a leaf node")
    }

    /// Test hierarchical tree construction with single-level nesting
    @Test("Hierarchical tree handles single-level nesting")
    @MainActor
    func hierarchicalSingleLevel() async throws {
        // Given: Settings with single-level nesting
        let viewModel = SettingsViewModel()
        let items = [
            SettingItem(
                key: "editor.theme",
                value: .string("dark"),
                source: .globalSettings,
                contributions: [SourceContribution(source: .globalSettings, value: .string("dark"))]
            ),
            SettingItem(
                key: "editor.fontSize",
                value: .int(14),
                source: .globalSettings,
                contributions: [SourceContribution(source: .globalSettings, value: .int(14))]
            ),
        ]

        // When: Computing hierarchical settings
        let hierarchy = viewModel.computeHierarchicalSettings(from: items)

        // Then: Should create parent with children
        #expect(hierarchy.count == 1, "Should have one root node")
        #expect(hierarchy[0].key == "editor", "Root should be editor")
        #expect(hierarchy[0].isParent, "Should be a parent node")
        #expect(hierarchy[0].children.count == 2, "Should have two children")

        let children = hierarchy[0].children
        #expect(children[0].key == "editor.fontSize", "First child key should be full key")
        #expect(children[0].displayName == "fontSize", "Display name should be stripped")
        #expect(children[0].isLeaf, "Should be a leaf")
        #expect(children[1].displayName == "theme", "Second child display name")
    }

    /// Test hierarchical tree construction with multi-level nesting
    @Test("Hierarchical tree handles multi-level nesting")
    @MainActor
    func hierarchicalMultiLevel() async throws {
        // Given: Settings with deep nesting
        let viewModel = SettingsViewModel()
        let items = [
            SettingItem(
                key: "editor.font.family",
                value: .string("Monaco"),
                source: .globalSettings,
                contributions: [SourceContribution(source: .globalSettings, value: .string("Monaco"))]
            ),
            SettingItem(
                key: "editor.font.size",
                value: .int(14),
                source: .globalSettings,
                contributions: [SourceContribution(source: .globalSettings, value: .int(14))]
            ),
            SettingItem(
                key: "editor.theme",
                value: .string("dark"),
                source: .globalSettings,
                contributions: [SourceContribution(source: .globalSettings, value: .string("dark"))]
            ),
        ]

        // When: Computing hierarchical settings
        let hierarchy = viewModel.computeHierarchicalSettings(from: items)

        // Then: Should create nested parent nodes
        #expect(hierarchy.count == 1, "Should have one root node")
        #expect(hierarchy[0].key == "editor", "Root should be editor")
        #expect(hierarchy[0].children.count == 2, "Should have font and theme")

        let editorChildren = hierarchy[0].children
        let fontNode = editorChildren.first { $0.key == "editor.font" }
        #expect(fontNode != nil, "Should have font parent node")
        #expect(fontNode?.isParent == true, "Font should be a parent")
        #expect(fontNode?.displayName == "font", "Font display name should be stripped")
        #expect(fontNode?.children.count == 2, "Font should have two children")

        let fontChildren = fontNode?.children ?? []
        #expect(fontChildren[0].displayName == "family", "First font child display name")
        #expect(fontChildren[1].displayName == "size", "Second font child display name")

        let themeNode = editorChildren.first { $0.key == "editor.theme" }
        #expect(themeNode?.isLeaf == true, "Theme should be a leaf")
    }

    /// Test hierarchical tree with mixed depths
    @Test("Hierarchical tree handles mixed depths")
    @MainActor
    func hierarchicalMixedDepths() async throws {
        // Given: Settings with varying nesting depths
        let viewModel = SettingsViewModel()
        let items = [
            SettingItem(
                key: "simpleValue",
                value: .string("test"),
                source: .globalSettings,
                contributions: [SourceContribution(source: .globalSettings, value: .string("test"))]
            ),
            SettingItem(
                key: "editor.theme",
                value: .string("dark"),
                source: .globalSettings,
                contributions: [SourceContribution(source: .globalSettings, value: .string("dark"))]
            ),
            SettingItem(
                key: "hooks.tool.onCall",
                value: .string("script.sh"),
                source: .globalSettings,
                contributions: [SourceContribution(source: .globalSettings, value: .string("script.sh"))]
            ),
        ]

        // When: Computing hierarchical settings
        let hierarchy = viewModel.computeHierarchicalSettings(from: items)

        // Then: Should handle mixed depths correctly
        #expect(hierarchy.count == 3, "Should have three root nodes")

        // Check flat setting
        let simpleNode = hierarchy.first { $0.key == "simpleValue" }
        #expect(simpleNode?.isLeaf == true, "Simple value should be leaf")

        // Check single-level nesting
        let editorNode = hierarchy.first { $0.key == "editor" }
        #expect(editorNode?.isParent == true, "Editor should be parent")
        #expect(editorNode?.children.count == 1, "Editor should have one child")

        // Check multi-level nesting
        let hooksNode = hierarchy.first { $0.key == "hooks" }
        #expect(hooksNode?.isParent == true, "Hooks should be parent")
        let toolNode = hooksNode?.children.first { $0.key == "hooks.tool" }
        #expect(toolNode?.isParent == true, "Tool should be parent")
        #expect(toolNode?.children.count == 1, "Tool should have one child")
    }

    /// Test hierarchical tree with multiple items under same parent
    @Test("Hierarchical tree groups items under same parent")
    @MainActor
    func hierarchicalGrouping() async throws {
        // Given: Multiple items under the same parent key
        let viewModel = SettingsViewModel()
        let items = [
            SettingItem(
                key: "hooks.onRead",
                value: .string("read.sh"),
                source: .globalSettings,
                contributions: [SourceContribution(source: .globalSettings, value: .string("read.sh"))]
            ),
            SettingItem(
                key: "hooks.onWrite",
                value: .string("write.sh"),
                source: .globalSettings,
                contributions: [SourceContribution(source: .globalSettings, value: .string("write.sh"))]
            ),
            SettingItem(
                key: "hooks.onDelete",
                value: .string("delete.sh"),
                source: .globalSettings,
                contributions: [SourceContribution(source: .globalSettings, value: .string("delete.sh"))]
            ),
        ]

        // When: Computing hierarchical settings
        let hierarchy = viewModel.computeHierarchicalSettings(from: items)

        // Then: Should group all under hooks parent
        #expect(hierarchy.count == 1, "Should have one root node")
        #expect(hierarchy[0].key == "hooks", "Root should be hooks")
        #expect(hierarchy[0].children.count == 3, "Should have three children")

        if case let .parent(childCount) = hierarchy[0].nodeType {
            #expect(childCount == 3, "Parent should report correct child count")
        } else {
            Issue.record("Expected parent node type")
        }

        // Verify alphabetical ordering
        let children = hierarchy[0].children
        #expect(children[0].displayName == "onDelete", "First child alphabetically")
        #expect(children[1].displayName == "onRead", "Second child alphabetically")
        #expect(children[2].displayName == "onWrite", "Third child alphabetically")
    }

    /// Test hierarchical tree preserves setting items in leaf nodes
    @Test("Hierarchical tree preserves setting items")
    @MainActor
    func hierarchicalPreservesItems() async throws {
        // Given: Settings with metadata
        let viewModel = SettingsViewModel()
        let testItem = SettingItem(
            key: "editor.theme",
            value: .string("dark"),
            source: .projectSettings,
            overriddenBy: .projectLocal,
            contributions: [
                SourceContribution(source: .projectSettings, value: .string("light")),
                SourceContribution(source: .projectLocal, value: .string("dark")),
            ]
        )
        let items = [testItem]

        // When: Computing hierarchical settings
        let hierarchy = viewModel.computeHierarchicalSettings(from: items)

        // Then: Leaf node should preserve the original item
        let leafNode = hierarchy[0].children[0]
        guard let preservedItem = leafNode.settingItem else {
            Issue.record("Leaf node should have setting item")
            return
        }

        #expect(preservedItem.key == "editor.theme", "Should preserve key")
        #expect(preservedItem.value == .string("dark"), "Should preserve value")
        #expect(preservedItem.source == .projectSettings, "Should preserve source")
        #expect(preservedItem.overriddenBy == .projectLocal, "Should preserve override")
    }

    /// Test hierarchical tree with empty input
    @Test("Hierarchical tree handles empty input")
    @MainActor
    func hierarchicalEmpty() async throws {
        // Given: Empty settings array
        let viewModel = SettingsViewModel()
        let items: [SettingItem] = []

        // When: Computing hierarchical settings
        let hierarchy = viewModel.computeHierarchicalSettings(from: items)

        // Then: Should return empty array
        #expect(hierarchy.isEmpty, "Should return empty hierarchy")
    }
}

/// Tests for SettingsViewModel file operations (batch operations, move, delete)
@Suite("SettingsViewModel File Operations")
@MainActor
struct SettingsViewModelFileOperationsTests {
    /// Helper to create a temporary settings file with given content
    func createTempSettingsFile(content: [String: SettingValue], type: SettingsFileType) async throws -> (url: URL, file: SettingsFile) {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-\(UUID().uuidString).json")

        // Convert SettingValue dictionary to JSON-compatible dictionary
        func convertToJSON(_ value: SettingValue) -> Any {
            switch value {
            case let .string(str): return str
            case let .bool(bool): return bool
            case let .int(int): return int
            case let .double(double): return double
            case let .array(arr): return arr.map { convertToJSON($0) }
            case let .object(dict): return dict.mapValues { convertToJSON($0) }
            case .null: return NSNull()
            }
        }

        let jsonDict = content.mapValues { convertToJSON($0) }
        let jsonData = try JSONSerialization.data(withJSONObject: jsonDict, options: .prettyPrinted)
        try jsonData.write(to: testFile)

        let parser = SettingsParser(fileSystemManager: FileSystemManager())
        let settingsFile = try await parser.parseSettingsFile(at: testFile, type: type)

        return (testFile, settingsFile)
    }

    /// Helper to cleanup test files
    func cleanup(_ urls: URL...) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Test batchDeleteSettings removes multiple settings in one operation
    @Test("batchDeleteSettings removes multiple settings")
    func batchDeleteSettingsRemovesMultiple() async throws {
        // Given: A settings file with multiple settings
        let (url, file) = try await createTempSettingsFile(
            content: [
                "theme": .string("dark"),
                "fontSize": .int(14),
                "tabSize": .int(4),
                "lineNumbers": .bool(true),
            ],
            type: .globalSettings
        )
        defer { cleanup(url) }

        let viewModel = SettingsViewModel()
        viewModel.settingsFiles = [file]
        viewModel.settingItems = viewModel.computeSettingItems(from: [file])

        // When: Batch deleting multiple settings
        try await viewModel.batchDeleteSettings(["theme", "fontSize", "tabSize"], from: .globalSettings)

        // Then: Settings should be deleted from the file
        let parser = SettingsParser(fileSystemManager: FileSystemManager())
        let updatedFile = try await parser.parseSettingsFile(at: url, type: .globalSettings)

        #expect(updatedFile.content["theme"] == nil, "theme should be deleted")
        #expect(updatedFile.content["fontSize"] == nil, "fontSize should be deleted")
        #expect(updatedFile.content["tabSize"] == nil, "tabSize should be deleted")
        #expect(updatedFile.content["lineNumbers"] != nil, "lineNumbers should remain")

        // And: SettingItems should be updated
        #expect(!viewModel.settingItems.contains(where: { $0.key == "theme" }), "theme should be removed from items")
        #expect(viewModel.settingItems.contains(where: { $0.key == "lineNumbers" }), "lineNumbers should remain in items")
    }

    /// Test batchDeleteSettings handles nested settings
    @Test("batchDeleteSettings removes nested settings")
    func batchDeleteSettingsRemovesNested() async throws {
        // Given: A settings file with nested settings
        let (url, file) = try await createTempSettingsFile(
            content: [
                "editor": .object([
                    "theme": .string("dark"),
                    "fontSize": .int(14),
                ]),
                "terminal": .object([
                    "shell": .string("zsh"),
                ]),
            ],
            type: .projectSettings
        )
        defer { cleanup(url) }

        let viewModel = SettingsViewModel()
        viewModel.settingsFiles = [file]
        viewModel.settingItems = viewModel.computeSettingItems(from: [file])

        // When: Batch deleting nested settings
        try await viewModel.batchDeleteSettings(["editor.theme", "editor.fontSize"], from: .projectSettings)

        // Then: Nested settings should be deleted
        let parser = SettingsParser(fileSystemManager: FileSystemManager())
        let updatedFile = try await parser.parseSettingsFile(at: url, type: .projectSettings)

        // Editor object should either be removed entirely (if empty) or be an empty object
        if let editorValue = updatedFile.content["editor"] {
            if case let .object(editorDict) = editorValue {
                #expect(editorDict.isEmpty, "editor object should be empty after deleting all children")
            } else {
                Issue.record("editor should be an object if it exists")
            }
        }
        // If editor is nil, that's also acceptable (parent removed when all children deleted)

        #expect(updatedFile.content["terminal"] != nil, "terminal should remain")
    }

    /// Test batchDeleteSettings handles empty array gracefully
    @Test("batchDeleteSettings handles empty keys array")
    func batchDeleteSettingsHandlesEmpty() async throws {
        // Given: A settings file
        let (url, file) = try await createTempSettingsFile(
            content: ["setting1": .string("value1"), "setting2": .string("value2")],
            type: .globalSettings
        )
        defer { cleanup(url) }

        let viewModel = SettingsViewModel()
        viewModel.settingsFiles = [file]
        viewModel.settingItems = viewModel.computeSettingItems(from: [file])

        // When: Batch deleting empty array
        // Then: Should not throw and should be a no-op
        try await viewModel.batchDeleteSettings([], from: .globalSettings)

        // Verify file unchanged
        let parser = SettingsParser(fileSystemManager: FileSystemManager())
        let updatedFile = try await parser.parseSettingsFile(at: url, type: .globalSettings)
        #expect(updatedFile.content["setting1"] == .string("value1"), "setting1 should remain")
        #expect(updatedFile.content["setting2"] == .string("value2"), "setting2 should remain")
    }

    /// Test moveNode moves settings between files using batch operations
    @Test("moveNode moves settings from source to destination")
    func moveNodeMovesSettings() async throws {
        // Given: Source and destination files
        let (sourceURL, sourceFile) = try await createTempSettingsFile(
            content: [
                "editor": .object([
                    "theme": .string("dark"),
                    "fontSize": .int(14),
                ]),
            ],
            type: .globalSettings
        )
        let (destURL, destFile) = try await createTempSettingsFile(
            content: ["existing": .string("value")],
            type: .projectSettings
        )
        defer { cleanup(sourceURL, destURL) }

        let viewModel = SettingsViewModel()
        viewModel.settingsFiles = [sourceFile, destFile]
        viewModel.settingItems = viewModel.computeSettingItems(from: [sourceFile, destFile])
        viewModel.hierarchicalSettings = viewModel.computeHierarchicalSettings(from: viewModel.settingItems)

        // When: Moving the editor node
        try await viewModel.moveNode(key: "editor", from: .globalSettings, to: .projectSettings)

        // Then: Settings should be in destination and removed from source
        let parser = SettingsParser(fileSystemManager: FileSystemManager())
        let updatedSource = try await parser.parseSettingsFile(at: sourceURL, type: .globalSettings)
        let updatedDest = try await parser.parseSettingsFile(at: destURL, type: .projectSettings)

        #expect(updatedSource.content["editor"] == nil, "editor should be removed from source")

        if case let .object(editorDict) = updatedDest.content["editor"] {
            #expect(editorDict["theme"] == .string("dark"), "editor.theme should be in destination")
            #expect(editorDict["fontSize"] == .int(14), "editor.fontSize should be in destination")
        } else {
            Issue.record("editor should exist in destination as object")
        }

        #expect(updatedDest.content["existing"] == .string("value"), "existing setting should remain")
    }

    /// Test moveNode handles single leaf settings
    @Test("moveNode moves single leaf setting")
    func moveNodeMovesSingleLeaf() async throws {
        // Given: Source and destination files with a single setting to move
        let (sourceURL, sourceFile) = try await createTempSettingsFile(
            content: ["theme": .string("dark"), "fontSize": .int(14)],
            type: .globalSettings
        )
        let (destURL, destFile) = try await createTempSettingsFile(
            content: [:],
            type: .projectLocal
        )
        defer { cleanup(sourceURL, destURL) }

        let viewModel = SettingsViewModel()
        viewModel.settingsFiles = [sourceFile, destFile]
        viewModel.settingItems = viewModel.computeSettingItems(from: [sourceFile, destFile])
        viewModel.hierarchicalSettings = viewModel.computeHierarchicalSettings(from: viewModel.settingItems)

        // When: Moving a single leaf setting
        try await viewModel.moveNode(key: "theme", from: .globalSettings, to: .projectLocal)

        // Then: Only that setting should be moved
        let parser = SettingsParser(fileSystemManager: FileSystemManager())
        let updatedSource = try await parser.parseSettingsFile(at: sourceURL, type: .globalSettings)
        let updatedDest = try await parser.parseSettingsFile(at: destURL, type: .projectLocal)

        #expect(updatedSource.content["theme"] == nil, "theme should be removed from source")
        #expect(updatedSource.content["fontSize"] == .int(14), "fontSize should remain in source")
        #expect(updatedDest.content["theme"] == .string("dark"), "theme should be in destination")
    }

    /// Test moveNode with same source and destination is a no-op
    @Test("moveNode skips when source equals destination")
    func moveNodeSkipsSameSourceAndDestination() async throws {
        // Given: A settings file
        let (url, file) = try await createTempSettingsFile(
            content: ["setting": .string("value")],
            type: .globalSettings
        )
        defer { cleanup(url) }

        let viewModel = SettingsViewModel()
        viewModel.settingsFiles = [file]
        viewModel.settingItems = viewModel.computeSettingItems(from: [file])
        viewModel.hierarchicalSettings = viewModel.computeHierarchicalSettings(from: viewModel.settingItems)

        // When: Moving to the same file
        // Then: Should not throw and should be a no-op
        try await viewModel.moveNode(key: "setting", from: .globalSettings, to: .globalSettings)

        // Verify file unchanged
        let parser = SettingsParser(fileSystemManager: FileSystemManager())
        let updatedFile = try await parser.parseSettingsFile(at: url, type: .globalSettings)
        #expect(updatedFile.content["setting"] == .string("value"), "setting should remain unchanged")
    }

    /// Test deleteNode removes entire parent node with children
    @Test("deleteNode removes parent node with all children")
    func deleteNodeRemovesParentWithChildren() async throws {
        // Given: A settings file with nested structure
        let (url, file) = try await createTempSettingsFile(
            content: [
                "editor": .object([
                    "theme": .string("dark"),
                    "fontSize": .int(14),
                    "font": .object([
                        "family": .string("Monaco"),
                        "size": .int(12),
                    ]),
                ]),
                "terminal": .object([
                    "shell": .string("zsh"),
                ]),
            ],
            type: .projectSettings
        )
        defer { cleanup(url) }

        let viewModel = SettingsViewModel()
        viewModel.settingsFiles = [file]
        viewModel.settingItems = viewModel.computeSettingItems(from: [file])
        viewModel.hierarchicalSettings = viewModel.computeHierarchicalSettings(from: viewModel.settingItems)

        // When: Deleting the editor parent node
        try await viewModel.deleteNode(key: "editor", from: .projectSettings)

        // Then: All editor settings should be removed
        let parser = SettingsParser(fileSystemManager: FileSystemManager())
        let updatedFile = try await parser.parseSettingsFile(at: url, type: .projectSettings)

        #expect(updatedFile.content["editor"] == nil, "editor node should be completely removed")
        #expect(updatedFile.content["terminal"] != nil, "terminal should remain")

        // And: SettingItems should be updated
        #expect(!viewModel.settingItems.contains(where: { $0.key.starts(with: "editor") }), "No editor settings should remain")
        #expect(viewModel.settingItems.contains(where: { $0.key.starts(with: "terminal") }), "terminal settings should remain")
    }

    /// Test deleteNode removes single leaf setting
    @Test("deleteNode removes single leaf setting")
    func deleteNodeRemovesSingleLeaf() async throws {
        // Given: A settings file with multiple settings
        let (url, file) = try await createTempSettingsFile(
            content: [
                "theme": .string("dark"),
                "fontSize": .int(14),
                "tabSize": .int(4),
            ],
            type: .globalSettings
        )
        defer { cleanup(url) }

        let viewModel = SettingsViewModel()
        viewModel.settingsFiles = [file]
        viewModel.settingItems = viewModel.computeSettingItems(from: [file])
        viewModel.hierarchicalSettings = viewModel.computeHierarchicalSettings(from: viewModel.settingItems)

        // When: Deleting a single leaf setting
        try await viewModel.deleteNode(key: "fontSize", from: .globalSettings)

        // Then: Only that setting should be removed
        let parser = SettingsParser(fileSystemManager: FileSystemManager())
        let updatedFile = try await parser.parseSettingsFile(at: url, type: .globalSettings)

        #expect(updatedFile.content["fontSize"] == nil, "fontSize should be removed")
        #expect(updatedFile.content["theme"] == .string("dark"), "theme should remain")
        #expect(updatedFile.content["tabSize"] == .int(4), "tabSize should remain")
    }

    /// Test deleteNode with multi-level nested structure
    @Test("deleteNode handles deeply nested parent nodes")
    func deleteNodeHandlesDeeplyNested() async throws {
        // Given: A parent node with deeply nested children
        let (url, file) = try await createTempSettingsFile(
            content: [
                "hooks": .object([
                    "onRead": .string("read.sh"),
                    "onWrite": .string("write.sh"),
                    "nested": .object([
                        "level1": .string("value1"),
                        "level2": .object([
                            "deep": .string("deepValue"),
                        ]),
                    ]),
                ]),
                "otherSetting": .string("keep"),
            ],
            type: .projectSettings
        )
        defer { cleanup(url) }

        let viewModel = SettingsViewModel()
        viewModel.settingsFiles = [file]
        viewModel.settingItems = viewModel.computeSettingItems(from: [file])
        viewModel.hierarchicalSettings = viewModel.computeHierarchicalSettings(from: viewModel.settingItems)

        // When: Deleting the parent node with nested children
        try await viewModel.deleteNode(key: "hooks", from: .projectSettings)

        // Then: All nested children should be removed
        let parser = SettingsParser(fileSystemManager: FileSystemManager())
        let updatedFile = try await parser.parseSettingsFile(at: url, type: .projectSettings)

        #expect(updatedFile.content["hooks"] == nil, "hooks node should be completely removed")
        #expect(updatedFile.content["otherSetting"] == .string("keep"), "Other settings should remain")

        // Verify all nested keys are gone from settingItems
        #expect(!viewModel.settingItems.contains(where: { $0.key.starts(with: "hooks") }), "No hooks.* settings should remain")
    }

    /// Test that PendingEdit tracks originalFileType correctly
    @Test("PendingEdit tracks original file type")
    @MainActor
    func pendingEditTracksOriginalFileType() async throws {
        // Given: A setting that exists in global settings
        let globalFile = SettingsFile(
            type: .globalSettings,
            path: URL(fileURLWithPath: "/tmp/global.json"),
            content: ["theme": .string("dark")]
        )

        let viewModel = SettingsViewModel()
        viewModel.settingsFiles = [globalFile]
        viewModel.settingItems = viewModel.computeSettingItems(from: [globalFile])

        let item = viewModel.settingItems.first { $0.key == "theme" }!

        // When: Creating a pending edit for this item
        let pendingEdit = viewModel.getPendingEditOrCreate(for: item)

        // Then: The originalFileType should match where it came from
        #expect(pendingEdit.originalFileType == .globalSettings, "Should track original file type")
        #expect(pendingEdit.targetFileType == .globalSettings, "Target should initially equal original")
    }

    /// Test that originalFileType is preserved when changing target file type
    @Test("Original file type preserved when changing target")
    @MainActor
    func originalFileTypePreservedWhenChangingTarget() async throws {
        // Given: A setting in global settings with a pending edit
        let globalFile = SettingsFile(
            type: .globalSettings,
            path: URL(fileURLWithPath: "/tmp/global.json"),
            content: ["theme": .string("dark")]
        )

        let viewModel = SettingsViewModel()
        viewModel.settingsFiles = [globalFile]
        viewModel.settingItems = viewModel.computeSettingItems(from: [globalFile])

        let item = viewModel.settingItems.first { $0.key == "theme" }!

        // When: User edits the value and changes target to project settings
        viewModel.updatePendingEditIfChanged(
            item: item,
            value: .string("light"),
            targetFileType: .projectSettings
        )

        // Then: originalFileType should still be global (where it came from)
        let pendingEdit = viewModel.pendingEdits["theme"]
        #expect(pendingEdit != nil, "Should have pending edit")
        #expect(pendingEdit?.originalFileType == .globalSettings, "Original should be preserved")
        #expect(pendingEdit?.targetFileType == .projectSettings, "Target should be updated")
        #expect(pendingEdit?.value == .string("light"), "Value should be updated")
    }

    /// Test that originalFileType remains stable through multiple target changes
    @Test("Original file type stable through multiple target changes")
    @MainActor
    func originalFileTypeStableThroughMultipleChanges() async throws {
        // Given: A setting in global settings
        let globalFile = SettingsFile(
            type: .globalSettings,
            path: URL(fileURLWithPath: "/tmp/global.json"),
            content: ["maxTokens": .int(1_000)]
        )

        let viewModel = SettingsViewModel()
        viewModel.settingsFiles = [globalFile]
        viewModel.settingItems = viewModel.computeSettingItems(from: [globalFile])

        let item = viewModel.settingItems.first { $0.key == "maxTokens" }!

        // When: User changes target multiple times
        viewModel.updatePendingEditIfChanged(
            item: item,
            value: .int(2_000),
            targetFileType: .projectSettings
        )

        viewModel.updatePendingEditIfChanged(
            item: item,
            value: .int(3_000),
            targetFileType: .projectLocal
        )

        // Then: originalFileType should still be global throughout
        let pendingEdit = viewModel.pendingEdits["maxTokens"]
        #expect(pendingEdit?.originalFileType == .globalSettings, "Original should remain global")
        #expect(pendingEdit?.targetFileType == .projectLocal, "Target should be latest")
        #expect(pendingEdit?.value == .int(3_000), "Value should be latest")
    }

    /// Test that saveAllEdits moves (not copies) settings when target differs from original
    @Test("saveAllEdits moves settings when target file changes")
    @MainActor
    func saveAllEditsMovesSettingsWhenTargetChanges() async throws {
        // Given: A setting exists in global settings, and we want to move it to project settings
        let (globalURL, globalFile) = try await createTempSettingsFile(
            content: [
                "theme": .string("dark"),
                "fontSize": .int(14),
            ],
            type: .globalSettings
        )
        let (projectURL, projectFile) = try await createTempSettingsFile(
            content: [:],
            type: .projectSettings
        )
        defer { cleanup(globalURL, projectURL) }

        let viewModel = SettingsViewModel()
        viewModel.settingsFiles = [globalFile, projectFile]
        viewModel.settingItems = viewModel.computeSettingItems(from: [globalFile, projectFile])

        // Create a pending edit that moves theme from global to project
        viewModel.pendingEdits["theme"] = PendingEdit(
            key: "theme",
            value: .string("light"),
            targetFileType: .projectSettings,
            originalFileType: .globalSettings
        )

        // When: Saving all edits
        try await viewModel.saveAllEdits()

        // Then: Setting should be removed from global and added to project (move, not copy)
        let parser = SettingsParser(fileSystemManager: FileSystemManager())
        let updatedGlobal = try await parser.parseSettingsFile(at: globalURL, type: .globalSettings)
        let updatedProject = try await parser.parseSettingsFile(at: projectURL, type: .projectSettings)

        #expect(updatedGlobal.content["theme"] == nil, "theme should be deleted from original file (global)")
        #expect(updatedGlobal.content["fontSize"] == .int(14), "fontSize should remain in global")
        #expect(updatedProject.content["theme"] == .string("light"), "theme should be in target file (project)")

        // Verify pending edits were cleared
        #expect(viewModel.pendingEdits.isEmpty, "Pending edits should be cleared after save")
    }

    /// Test that saveAllEdits copies (not moves) when target equals original
    @Test("saveAllEdits updates in place when target equals original")
    @MainActor
    func saveAllEditsUpdatesInPlaceWhenTargetEqualsOriginal() async throws {
        // Given: A setting exists in global settings, and we're just changing its value
        let (url, file) = try await createTempSettingsFile(
            content: [
                "theme": .string("dark"),
                "fontSize": .int(14),
            ],
            type: .globalSettings
        )
        defer { cleanup(url) }

        let viewModel = SettingsViewModel()
        viewModel.settingsFiles = [file]
        viewModel.settingItems = viewModel.computeSettingItems(from: [file])

        // Create a pending edit that updates the value but keeps it in the same file
        viewModel.pendingEdits["theme"] = PendingEdit(
            key: "theme",
            value: .string("light"),
            targetFileType: .globalSettings,
            originalFileType: .globalSettings
        )

        // When: Saving all edits
        try await viewModel.saveAllEdits()

        // Then: Setting should be updated in place (not deleted and re-added)
        let parser = SettingsParser(fileSystemManager: FileSystemManager())
        let updatedFile = try await parser.parseSettingsFile(at: url, type: .globalSettings)

        #expect(updatedFile.content["theme"] == .string("light"), "theme should be updated in place")
        #expect(updatedFile.content["fontSize"] == .int(14), "fontSize should remain unchanged")
    }

    /// Test that saveAllEdits handles multiple moves correctly
    @Test("saveAllEdits handles multiple moves in batch")
    @MainActor
    func saveAllEditsHandlesMultipleMoves() async throws {
        // Given: Multiple settings in global, moving them to different targets
        let (globalURL, globalFile) = try await createTempSettingsFile(
            content: [
                "setting1": .string("value1"),
                "setting2": .string("value2"),
                "setting3": .string("value3"),
            ],
            type: .globalSettings
        )
        let (projectURL, projectFile) = try await createTempSettingsFile(
            content: [:],
            type: .projectSettings
        )
        let (localURL, localFile) = try await createTempSettingsFile(
            content: [:],
            type: .projectLocal
        )
        defer { cleanup(globalURL, projectURL, localURL) }

        let viewModel = SettingsViewModel()
        viewModel.settingsFiles = [globalFile, projectFile, localFile]
        viewModel.settingItems = viewModel.computeSettingItems(from: [globalFile, projectFile, localFile])

        // Create pending edits that move settings to different files
        viewModel.pendingEdits["setting1"] = PendingEdit(
            key: "setting1",
            value: .string("value1-modified"),
            targetFileType: .projectSettings,
            originalFileType: .globalSettings
        )
        viewModel.pendingEdits["setting2"] = PendingEdit(
            key: "setting2",
            value: .string("value2-modified"),
            targetFileType: .projectLocal,
            originalFileType: .globalSettings
        )

        // When: Saving all edits
        try await viewModel.saveAllEdits()

        // Then: Settings should be moved to their respective targets
        let parser = SettingsParser(fileSystemManager: FileSystemManager())
        let updatedGlobal = try await parser.parseSettingsFile(at: globalURL, type: .globalSettings)
        let updatedProject = try await parser.parseSettingsFile(at: projectURL, type: .projectSettings)
        let updatedLocal = try await parser.parseSettingsFile(at: localURL, type: .projectLocal)

        #expect(updatedGlobal.content["setting1"] == nil, "setting1 should be deleted from global")
        #expect(updatedGlobal.content["setting2"] == nil, "setting2 should be deleted from global")
        #expect(updatedGlobal.content["setting3"] == .string("value3"), "setting3 should remain in global")

        #expect(updatedProject.content["setting1"] == .string("value1-modified"), "setting1 should be in project")
        #expect(updatedLocal.content["setting2"] == .string("value2-modified"), "setting2 should be in local")
    }

    /// Test that originalFileType tracks the highest precedence contribution
    @Test("Original file type tracks highest precedence when multiple contributions exist")
    @MainActor
    func originalFileTypeTracksHighestPrecedenceContribution() async throws {
        // Given: A setting that exists in both global and project settings (project overrides)
        let globalFile = SettingsFile(
            type: .globalSettings,
            path: URL(fileURLWithPath: "/tmp/global.json"),
            content: ["theme": .string("dark")]
        )
        let projectFile = SettingsFile(
            type: .projectSettings,
            path: URL(fileURLWithPath: "/tmp/project.json"),
            content: ["theme": .string("light")]
        )

        let viewModel = SettingsViewModel()
        viewModel.settingsFiles = [globalFile, projectFile]
        viewModel.settingItems = viewModel.computeSettingItems(from: [globalFile, projectFile])

        let item = viewModel.settingItems.first { $0.key == "theme" }!

        // Verify we have multiple contributions
        #expect(item.contributions.count == 2, "Should have two contributions")

        // When: Creating a pending edit
        let pendingEdit = viewModel.getPendingEditOrCreate(for: item)

        // Then: originalFileType should be the highest precedence source (project)
        #expect(pendingEdit.originalFileType == .projectSettings, "Original should be highest precedence")
        #expect(pendingEdit.value == .string("light"), "Value should match highest precedence")
    }

    /// Test that moving a setting with multiple contributions only removes from highest precedence
    @Test("Moving setting with multiple contributions only removes from active source")
    @MainActor
    func movingSettingWithMultipleContributionsOnlyRemovesFromActive() async throws {
        // Given: A setting exists in both global and project (project overrides)
        let (globalURL, globalFile) = try await createTempSettingsFile(
            content: ["maxTokens": .int(1_000)],
            type: .globalSettings
        )
        let (projectURL, projectFile) = try await createTempSettingsFile(
            content: ["maxTokens": .int(2_000)],
            type: .projectSettings
        )
        let (localURL, localFile) = try await createTempSettingsFile(
            content: [:],
            type: .projectLocal
        )
        defer { cleanup(globalURL, projectURL, localURL) }

        let viewModel = SettingsViewModel()
        viewModel.settingsFiles = [globalFile, projectFile, localFile]
        viewModel.settingItems = viewModel.computeSettingItems(from: [globalFile, projectFile, localFile])

        // Create a pending edit to move from project to local
        viewModel.pendingEdits["maxTokens"] = PendingEdit(
            key: "maxTokens",
            value: .int(3_000),
            targetFileType: .projectLocal,
            originalFileType: .projectSettings
        )

        // When: Saving all edits
        try await viewModel.saveAllEdits()

        // Then: Should delete from project (original) but leave global untouched
        let parser = SettingsParser(fileSystemManager: FileSystemManager())
        let updatedGlobal = try await parser.parseSettingsFile(at: globalURL, type: .globalSettings)
        let updatedProject = try await parser.parseSettingsFile(at: projectURL, type: .projectSettings)
        let updatedLocal = try await parser.parseSettingsFile(at: localURL, type: .projectLocal)

        #expect(updatedGlobal.content["maxTokens"] == .int(1_000), "Global should remain untouched")
        #expect(updatedProject.content["maxTokens"] == nil, "Project should be deleted (was original)")
        #expect(updatedLocal.content["maxTokens"] == .int(3_000), "Local should have new value")
    }

    // MARK: - Dictionary Merge and Array Append Tests

    /// Test that adding a new key to an existing dictionary merges instead of replacing
    @Test("Adding to existing dictionary merges keys")
    func addingToDictionaryMergesKeys() async throws {
        // Given: A settings file with an existing dictionary (mcpServers with existing servers)
        let (url, file) = try await createTempSettingsFile(
            content: [
                "mcpServers": .object([
                    "server1": .object(["command": .string("cmd1"), "args": .array([.string("arg1")])]),
                    "server2": .object(["command": .string("cmd2")]),
                ]),
            ],
            type: .globalSettings
        )
        defer { cleanup(url) }

        let viewModel = SettingsViewModel()
        viewModel.settingsFiles = [file]
        viewModel.settingItems = viewModel.computeSettingItems(from: [file])

        // When: Adding a new server to mcpServers (as a whole object with a new key)
        let newServers: SettingValue = .object([
            "server3": .object(["command": .string("cmd3"), "args": .array([.string("arg3")])]),
        ])
        try await viewModel.updateSetting(key: "mcpServers", value: newServers, in: .globalSettings)

        // Then: The new server should be merged with existing servers (not replace them)
        let parser = SettingsParser(fileSystemManager: FileSystemManager())
        let updatedFile = try await parser.parseSettingsFile(at: url, type: .globalSettings)

        guard case let .object(mcpServers) = updatedFile.content["mcpServers"] else {
            Issue.record("mcpServers should be an object")
            return
        }

        // All three servers should exist
        #expect(mcpServers["server1"] != nil, "server1 should still exist after merge")
        #expect(mcpServers["server2"] != nil, "server2 should still exist after merge")
        #expect(mcpServers["server3"] != nil, "server3 should be added by merge")

        // Verify server1's content is preserved
        if case let .object(server1) = mcpServers["server1"] {
            #expect(server1["command"] == .string("cmd1"), "server1 command should be preserved")
        } else {
            Issue.record("server1 should be an object")
        }
    }

    /// Test that adding to an existing dictionary can override specific keys
    @Test("Adding to dictionary overrides conflicting keys")
    func addingToDictionaryOverridesConflictingKeys() async throws {
        // Given: A settings file with an existing dictionary
        let (url, file) = try await createTempSettingsFile(
            content: [
                "mcpServers": .object([
                    "server1": .object(["command": .string("old-cmd")]),
                    "server2": .object(["command": .string("cmd2")]),
                ]),
            ],
            type: .globalSettings
        )
        defer { cleanup(url) }

        let viewModel = SettingsViewModel()
        viewModel.settingsFiles = [file]
        viewModel.settingItems = viewModel.computeSettingItems(from: [file])

        // When: Adding an object that has a conflicting key (server1) and a new key (server3)
        let newServers: SettingValue = .object([
            "server1": .object(["command": .string("new-cmd"), "extraArg": .bool(true)]),
            "server3": .object(["command": .string("cmd3")]),
        ])
        try await viewModel.updateSetting(key: "mcpServers", value: newServers, in: .globalSettings)

        // Then: server1 should be overridden, server2 preserved, server3 added
        let parser = SettingsParser(fileSystemManager: FileSystemManager())
        let updatedFile = try await parser.parseSettingsFile(at: url, type: .globalSettings)

        guard case let .object(mcpServers) = updatedFile.content["mcpServers"] else {
            Issue.record("mcpServers should be an object")
            return
        }

        #expect(mcpServers.count == 3, "Should have 3 servers total")

        // server1 should be completely replaced with new value
        if case let .object(server1) = mcpServers["server1"] {
            #expect(server1["command"] == .string("new-cmd"), "server1 command should be updated")
            #expect(server1["extraArg"] == .bool(true), "server1 should have new extraArg")
        } else {
            Issue.record("server1 should be an object")
        }

        // server2 should be preserved
        #expect(mcpServers["server2"] != nil, "server2 should still exist")

        // server3 should be added
        #expect(mcpServers["server3"] != nil, "server3 should be added")
    }

    /// Test that adding to an existing array appends instead of replacing
    @Test("Adding to existing array appends items")
    func addingToArrayAppendsItems() async throws {
        // Given: A settings file with an existing array
        let (url, file) = try await createTempSettingsFile(
            content: [
                "allowedTools": .array([.string("Read"), .string("Write")]),
            ],
            type: .globalSettings
        )
        defer { cleanup(url) }

        let viewModel = SettingsViewModel()
        viewModel.settingsFiles = [file]
        viewModel.settingItems = viewModel.computeSettingItems(from: [file])

        // When: Adding new items to the array
        let newTools: SettingValue = .array([.string("Bash"), .string("Edit")])
        try await viewModel.updateSetting(key: "allowedTools", value: newTools, in: .globalSettings)

        // Then: The new items should be appended to the existing array
        let parser = SettingsParser(fileSystemManager: FileSystemManager())
        let updatedFile = try await parser.parseSettingsFile(at: url, type: .globalSettings)

        guard case let .array(allowedTools) = updatedFile.content["allowedTools"] else {
            Issue.record("allowedTools should be an array")
            return
        }

        // Should have all 4 items: original 2 + new 2
        #expect(allowedTools.count == 4, "Should have 4 items total (2 original + 2 new)")
        #expect(allowedTools[0] == .string("Read"), "First item should be preserved")
        #expect(allowedTools[1] == .string("Write"), "Second item should be preserved")
        #expect(allowedTools[2] == .string("Bash"), "Third item should be appended")
        #expect(allowedTools[3] == .string("Edit"), "Fourth item should be appended")
    }

    /// Test that type mismatches result in replacement (not merge)
    @Test("Type mismatch replaces instead of merging")
    func typeMismatchReplaces() async throws {
        // Given: A settings file where a key has a string value
        let (url, file) = try await createTempSettingsFile(
            content: [
                "setting": .string("old-value"),
            ],
            type: .globalSettings
        )
        defer { cleanup(url) }

        let viewModel = SettingsViewModel()
        viewModel.settingsFiles = [file]
        viewModel.settingItems = viewModel.computeSettingItems(from: [file])

        // When: Setting an object value where a string existed
        let newValue: SettingValue = .object(["key": .string("value")])
        try await viewModel.updateSetting(key: "setting", value: newValue, in: .globalSettings)

        // Then: The value should be replaced (since types don't match)
        let parser = SettingsParser(fileSystemManager: FileSystemManager())
        let updatedFile = try await parser.parseSettingsFile(at: url, type: .globalSettings)

        guard case let .object(settingDict) = updatedFile.content["setting"] else {
            Issue.record("setting should now be an object")
            return
        }

        #expect(settingDict["key"] == .string("value"), "Should have the new object value")
    }

    /// Test that adding an empty dictionary preserves existing content
    @Test("Adding empty dictionary preserves existing")
    func addingEmptyDictionaryPreservesExisting() async throws {
        // Given: A settings file with an existing dictionary
        let (url, file) = try await createTempSettingsFile(
            content: [
                "mcpServers": .object([
                    "server1": .object(["command": .string("cmd1")]),
                ]),
            ],
            type: .globalSettings
        )
        defer { cleanup(url) }

        let viewModel = SettingsViewModel()
        viewModel.settingsFiles = [file]
        viewModel.settingItems = viewModel.computeSettingItems(from: [file])

        // When: Adding an empty dictionary
        try await viewModel.updateSetting(key: "mcpServers", value: .object([:]), in: .globalSettings)

        // Then: The existing content should be preserved (empty merge = no change)
        let parser = SettingsParser(fileSystemManager: FileSystemManager())
        let updatedFile = try await parser.parseSettingsFile(at: url, type: .globalSettings)

        guard case let .object(mcpServers) = updatedFile.content["mcpServers"] else {
            Issue.record("mcpServers should be an object")
            return
        }

        #expect(mcpServers["server1"] != nil, "server1 should still exist")
    }

    /// Test that adding an empty array preserves existing content
    @Test("Adding empty array preserves existing")
    func addingEmptyArrayPreservesExisting() async throws {
        // Given: A settings file with an existing array
        let (url, file) = try await createTempSettingsFile(
            content: [
                "allowedTools": .array([.string("Read"), .string("Write")]),
            ],
            type: .globalSettings
        )
        defer { cleanup(url) }

        let viewModel = SettingsViewModel()
        viewModel.settingsFiles = [file]
        viewModel.settingItems = viewModel.computeSettingItems(from: [file])

        // When: Adding an empty array
        try await viewModel.updateSetting(key: "allowedTools", value: .array([]), in: .globalSettings)

        // Then: The existing content should be preserved
        let parser = SettingsParser(fileSystemManager: FileSystemManager())
        let updatedFile = try await parser.parseSettingsFile(at: url, type: .globalSettings)

        guard case let .array(allowedTools) = updatedFile.content["allowedTools"] else {
            Issue.record("allowedTools should be an array")
            return
        }

        #expect(allowedTools.count == 2, "Should still have 2 items")
        #expect(allowedTools[0] == .string("Read"), "First item should be preserved")
        #expect(allowedTools[1] == .string("Write"), "Second item should be preserved")
    }

    /// Test that drag and drop to existing file merges settings instead of replacing
    @Test("Drag and drop merges with existing settings")
    func dragAndDropMergesSettings() async throws {
        // Given: A target project with existing settings
        let tempDir = FileManager.default.temporaryDirectory
        let projectDir = tempDir.appendingPathComponent("test-project-\(UUID().uuidString)")
        let claudeDir = projectDir.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        let projectSettingsPath = claudeDir.appendingPathComponent("settings.json")

        // Create existing settings in the project file
        let existingContent: [String: Any] = [
            "existingSetting1": "value1",
            "existingSetting2": 42,
            "editor": [
                "theme": "light",
            ],
        ]
        let existingData = try JSONSerialization.data(withJSONObject: existingContent, options: .prettyPrinted)
        try existingData.write(to: projectSettingsPath)

        defer { try? FileManager.default.removeItem(at: projectDir) }

        // Create a project instance
        let project = ClaudeProject(
            name: "TestProject",
            path: projectDir,
            claudeDirectory: claudeDir,
            hasLocalSettings: false,
            hasSharedSettings: true
        )

        // Create settings to drag and drop
        let draggableSettings = DraggableSetting(settings: [
            DraggableSetting.SettingEntry(
                key: "newSetting1",
                value: .string("newValue1"),
                sourceFileType: .globalSettings
            ),
            DraggableSetting.SettingEntry(
                key: "newSetting2",
                value: .int(123),
                sourceFileType: .globalSettings
            ),
            DraggableSetting.SettingEntry(
                key: "editor.fontSize",
                value: .int(14),
                sourceFileType: .globalSettings
            ),
        ])

        // When: Dragging and dropping the settings to the project
        try await SettingsCopyHelper.copySetting(
            setting: draggableSettings,
            to: project,
            fileType: .projectSettings
        )

        // Then: The file should contain BOTH existing and new settings
        let parser = SettingsParser(fileSystemManager: FileSystemManager())
        let updatedFile = try await parser.parseSettingsFile(at: projectSettingsPath, type: .projectSettings)

        // Verify existing settings are still there
        #expect(updatedFile.content["existingSetting1"] == .string("value1"), "Existing setting 1 should be preserved")
        #expect(updatedFile.content["existingSetting2"] == .int(42), "Existing setting 2 should be preserved")

        // Verify new settings were added
        #expect(updatedFile.content["newSetting1"] == .string("newValue1"), "New setting 1 should be added")
        #expect(updatedFile.content["newSetting2"] == .int(123), "New setting 2 should be added")

        // Verify nested settings are merged correctly
        if case let .object(editorDict) = updatedFile.content["editor"] {
            #expect(editorDict["theme"] == .string("light"), "Existing editor.theme should be preserved")
            #expect(editorDict["fontSize"] == .int(14), "New editor.fontSize should be added")
        } else {
            Issue.record("editor should exist as object with both old and new settings")
        }
    }
}

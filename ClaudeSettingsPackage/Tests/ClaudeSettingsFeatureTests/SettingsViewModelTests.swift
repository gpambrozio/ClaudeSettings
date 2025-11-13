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
}

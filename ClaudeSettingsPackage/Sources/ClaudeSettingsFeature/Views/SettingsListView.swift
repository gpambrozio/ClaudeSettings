import SwiftUI

/// View displaying the list of settings with their values
public struct SettingsListView: View {
    let settingsViewModel: SettingsViewModel
    @Binding var selectedKey: String?
    @Binding var searchText: String
    @ObservedObject var documentationLoader: DocumentationLoader
    @State private var expandedNodes: Set<String> = []
    @State private var showSaveError = false
    @State private var saveErrorMessage: String?
    @State private var showUpcomingFeatureAlert = false
    @State private var upcomingFeatureName = ""
    @State private var showAddSettingSheet = false

    public init(settingsViewModel: SettingsViewModel, selectedKey: Binding<String?>, searchText: Binding<String>, documentationLoader: DocumentationLoader = DocumentationLoader.shared) {
        self.settingsViewModel = settingsViewModel
        self._selectedKey = selectedKey
        self._searchText = searchText
        self.documentationLoader = documentationLoader
    }

    public var body: some View {
        Group {
            if settingsViewModel.isLoading {
                ProgressView("Loading settings...")
            } else if let errorMessage = settingsViewModel.errorMessage {
                ContentUnavailableView {
                    Label("Error", symbol: .exclamationmarkTriangle)
                } description: {
                    Text(errorMessage)
                }
            } else if settingsViewModel.settingItems.isEmpty {
                ContentUnavailableView {
                    Label("No Settings", symbol: .docText)
                } description: {
                    Text("No settings files found for this configuration")
                }
            } else if searchFilteredSettings.isEmpty {
                if !searchText.isEmpty {
                    ContentUnavailableView {
                        Label("No Results", symbol: .magnifyingglass)
                    } description: {
                        Text("No settings match \"\(searchText)\"")
                    }
                } else {
                    ContentUnavailableView {
                        Label("No Project Settings", symbol: .eyeSlash)
                    } description: {
                        Text("All settings are from global configuration. Toggle \"Hide Global\" to show them.")
                    }
                }
            } else {
                settingsContent
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if settingsViewModel.isEditingMode {
                    // Editing mode: Show Cancel and Save
                    Button("Cancel") {
                        settingsViewModel.cancelEditing()
                    }
                    .buttonStyle(.bordered)

                    Button("Save All") {
                        Task {
                            do {
                                try await settingsViewModel.saveAllEdits()
                            } catch {
                                saveErrorMessage = error.localizedDescription
                                showSaveError = true
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(settingsViewModel.pendingEdits.values.contains(where: { $0.validationError != nil }))

                    if !settingsViewModel.pendingEdits.isEmpty {
                        Text("\(settingsViewModel.pendingEdits.count) edited")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // Normal mode: Show Edit and Actions menu
                    Button("Edit") {
                        settingsViewModel.startEditing()
                    }
                    .buttonStyle(.bordered)

                    Menu {
                        Button("Add Setting") {
                            showAddSettingSheet = true
                        }
                        Button("Import Settings") {
                            upcomingFeatureName = "Import Settings"
                            showUpcomingFeatureAlert = true
                        }
                    } label: {
                        Label("Actions", symbol: .ellipsisCircle)
                    }
                }
            }
        }
        .alert("Save Error", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            if let saveErrorMessage {
                Text(saveErrorMessage)
            }
        }
        .alert("Coming Soon", isPresented: $showUpcomingFeatureAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\(upcomingFeatureName) is an upcoming feature that is not yet implemented. Stay tuned!")
        }
        .sheet(isPresented: $showAddSettingSheet) {
            AddSettingSheet(
                viewModel: settingsViewModel,
                documentationLoader: documentationLoader,
                onDismiss: { showAddSettingSheet = false }
            )
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        List(selection: $selectedKey) {
            // Editing Mode Indicator
            if settingsViewModel.isEditingMode {
                Section {
                    HStack {
                        Symbols.exclamationmarkCircle.image
                            .foregroundStyle(.orange)
                        Text("Editing Mode Active")
                            .font(.callout)
                            .foregroundStyle(.orange)
                        Spacer()
                        Text("Actions are disabled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.orange.opacity(0.1))
                }
            }

            // Validation Errors Section (if any)
            if !settingsViewModel.validationErrors.isEmpty {
                Section {
                    ForEach(settingsViewModel.validationErrors) { error in
                        ValidationErrorRow(error: error)
                    }
                } header: {
                    HStack {
                        Label("Validation Errors", symbol: .exclamationmarkTriangle)
                            .foregroundStyle(.red)
                        Spacer()
                        Text("\(settingsViewModel.validationErrors.count) errors")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            // Settings Section (Hierarchical)
            Section {
                ForEach(searchFilteredSettings) { node in
                    HierarchicalSettingNodeView(
                        node: node,
                        selectedKey: $selectedKey,
                        expandedNodes: $expandedNodes,
                        documentationLoader: documentationLoader,
                        settingsViewModel: settingsViewModel
                    )
                }
            } header: {
                HStack {
                    Text("Settings")
                    Spacer()
                    Text(settingsCountLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if settingsViewModel.isProjectView {
                        Toggle("Hide Global", isOn: Binding(
                            get: { settingsViewModel.hideGlobalSettings },
                            set: { settingsViewModel.hideGlobalSettings = $0 }
                        ))
                        .toggleStyle(SwitchToggleStyle())
                        .help("Hide settings from global configuration")
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search settings...")
    }

    /// Settings filtered by search text
    /// When searching, ignores hideGlobalSettings and shows all matching settings
    private var searchFilteredSettings: [HierarchicalSettingNode] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // If no search text, use the normal filtered settings (respects hideGlobalSettings)
        guard !trimmedSearch.isEmpty else {
            return settingsViewModel.filteredHierarchicalSettings
        }

        // When searching, filter all hierarchical settings (ignores hideGlobalSettings toggle)
        // to show both project and global settings that match
        return filterNodesBySearchText(settingsViewModel.hierarchicalSettings, searchText: trimmedSearch)
    }

    /// Recursively filter hierarchical nodes by search text
    private func filterNodesBySearchText(_ nodes: [HierarchicalSettingNode], searchText: String) -> [HierarchicalSettingNode] {
        nodes.compactMap { node in
            if node.isParent {
                // For parent nodes, recursively filter children
                let filteredChildren = filterNodesBySearchText(node.children, searchText: searchText)

                // Keep parent if its key matches or any children match
                if node.key.lowercased().contains(searchText) || !filteredChildren.isEmpty {
                    return HierarchicalSettingNode(
                        id: node.id,
                        key: node.key,
                        displayName: node.displayName,
                        nodeType: .parent(childCount: filteredChildren.count),
                        children: filteredChildren
                    )
                }
                return nil
            } else {
                // For leaf nodes, check if key or value contains search text
                if nodeMatchesSearch(node, searchText: searchText) {
                    return node
                }
                return nil
            }
        }
    }

    /// Check if a node matches the search text (key or value)
    private func nodeMatchesSearch(_ node: HierarchicalSettingNode, searchText: String) -> Bool {
        // Check key
        if node.key.lowercased().contains(searchText) {
            return true
        }

        // Check value if it's a leaf node
        if let item = node.settingItem {
            let valueString = item.value.searchableString.lowercased()
            if valueString.contains(searchText) {
                return true
            }
        }

        return false
    }

    /// Label showing the count of settings, accounting for filtering
    private var settingsCountLabel: String {
        let total = settingsViewModel.settingItems.count
        let filtered = countFilteredSettings()

        if filtered < total {
            return "\(filtered) of \(total) settings"
        } else {
            return "\(total) settings"
        }
    }

    /// Count the number of settings currently shown after filtering
    private func countFilteredSettings() -> Int {
        func countLeaves(_ nodes: [HierarchicalSettingNode]) -> Int {
            nodes.reduce(0) { count, node in
                if node.isParent {
                    return count + countLeaves(node.children)
                } else {
                    return count + 1
                }
            }
        }
        return countLeaves(searchFilteredSettings)
    }
}

/// Row displaying a validation error
struct ValidationErrorRow: View {
    let error: ValidationError

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            errorTypeIcon.image
                .foregroundStyle(errorColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(error.type.rawValue.capitalized)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(errorColor)

                    if let key = error.key {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(key)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(error.message)
                    .font(.body)
                    .foregroundStyle(.primary)

                if let suggestion = error.suggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var errorTypeIcon: Symbols {
        switch error.type {
        case .syntax:
            return .exclamationmarkTriangle
        case .deprecated:
            return .clockArrowCirclepath
        case .conflict:
            return .exclamationmark2
        case .permission:
            return .lockFill
        case .unknownKey:
            return .questionmarkCircle
        }
    }

    private var errorColor: Color {
        switch error.type {
        case .syntax,
             .conflict:
            return .red
        case .deprecated:
            return .orange
        case .permission:
            return .yellow
        case .unknownKey:
            return .blue
        }
    }
}

/// Hierarchical view for displaying setting nodes (either parent or leaf)
struct HierarchicalSettingNodeView: View {
    let node: HierarchicalSettingNode
    @Binding var selectedKey: String?
    @Binding var expandedNodes: Set<String>
    @ObservedObject var documentationLoader: DocumentationLoader
    let settingsViewModel: SettingsViewModel
    @State private var actionState = SettingActionState()

    var body: some View {
        if node.isParent {
            // Parent node with children - use DisclosureGroup
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedNodes.contains(node.id) },
                    set: { isExpanded in
                        if isExpanded {
                            expandedNodes.insert(node.id)
                        } else {
                            expandedNodes.remove(node.id)
                        }
                    }
                )
            ) {
                ForEach(node.children) { childNode in
                    HierarchicalSettingNodeView(
                        node: childNode,
                        selectedKey: $selectedKey,
                        expandedNodes: $expandedNodes,
                        documentationLoader: documentationLoader,
                        settingsViewModel: settingsViewModel
                    )
                    .padding(.leading, 16)
                }
            } label: {
                HStack(spacing: 6) {
                    Text(node.displayName)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(selectedKey == node.key ? .primary : .secondary)
                        .fontWeight(.medium)

                    if case let .parent(childCount) = node.nodeType {
                        Text("(\(childCount))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .parentNodeContextMenu(
                    nodeKey: node.key,
                    viewModel: settingsViewModel,
                    actionState: actionState
                )
                .draggable(DraggableSetting(settings: node.allDraggableEntries()))
            }
            .tag(node.key)
            .parentNodeActions(
                nodeKey: node.key,
                viewModel: settingsViewModel,
                actionState: actionState
            )
        } else if let item = node.settingItem {
            // Leaf node - display as regular setting item row
            SettingItemRow(
                item: item,
                isSelected: selectedKey == item.key,
                displayName: node.displayName,
                documentationLoader: documentationLoader,
                settingsViewModel: settingsViewModel
            )
            .tag(item.key)
        }
    }
}

/// Individual row displaying a setting item with source information
struct SettingItemRow: View {
    let item: SettingItem
    let isSelected: Bool
    let displayName: String?
    @ObservedObject var documentationLoader: DocumentationLoader
    let settingsViewModel: SettingsViewModel
    @State private var actionState = SettingActionState()

    init(item: SettingItem, isSelected: Bool, displayName: String? = nil, documentationLoader: DocumentationLoader = DocumentationLoader.shared, settingsViewModel: SettingsViewModel) {
        self.item = item
        self.isSelected = isSelected
        self.displayName = displayName
        self.documentationLoader = documentationLoader
        self.settingsViewModel = settingsViewModel
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayName ?? item.key)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(isSelected ? .primary : .secondary)

                    if documentationLoader.isDeprecated(item.key) {
                        Symbols.exclamationmarkTriangle.image
                            .foregroundStyle(.red)
                            .font(.body)
                    }

                    if !item.isActive {
                        Symbols.exclamationmarkTriangle.image
                            .foregroundStyle(.yellow)
                            .font(.caption)
                    }
                }

                HStack(spacing: 6) {
                    valueTypeIndicator

                    Text(valueDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Spacer()
                }

                HStack(spacing: 6) {
                    if item.isAdditive {
                        // Arrays are additive - show all contributing sources
                        ForEach(Array(item.contributions.enumerated()), id: \.offset) { index, contribution in
                            if index > 0 {
                                Symbols.plus.image
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            sourceIndicator(for: contribution.source, label: "From")
                        }
                    } else {
                        sourceIndicator(for: item.source, label: "From")

                        if let overriddenBy = item.overriddenBy {
                            // Non-arrays are overridden
                            Symbols.arrowRight.image
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            sourceIndicator(for: overriddenBy, label: "Overridden by")
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .settingItemContextMenu(
            item: item,
            viewModel: settingsViewModel,
            actionState: actionState
        )
        .settingItemActions(
            item: item,
            viewModel: settingsViewModel,
            actionState: actionState
        )
        .draggable(DraggableSetting(
            key: item.key,
            value: item.value,
            sourceFileType: item.overriddenBy ?? item.source
        ))
    }

    @ViewBuilder
    private func sourceIndicator(for type: SettingsFileType, label: String) -> some View {
        HStack(spacing: 2) {
            Circle()
                .fill(SettingsActionHelpers.sourceColor(for: type))
                .frame(width: 6, height: 6)

            Text(sourceLabel(for: type))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func sourceLabel(for type: SettingsFileType) -> String {
        SettingsActionHelpers.sourceLabel(for: type)
    }

    private var valueDescription: String {
        switch item.value {
        case let .string(string):
            return string
        case let .bool(bool):
            return bool ? "true" : "false"
        case let .int(int):
            return "\(int)"
        case let .double(double):
            return "\(double)"
        case let .array(array):
            return "[\(array.count) items]"
        case let .object(dict):
            return "{\(dict.count) keys}"
        case .null:
            return "null"
        }
    }

    @ViewBuilder
    private var valueTypeIndicator: some View {
        Text(item.value.typeDisplayName.lowercased())
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(item.value.typeDisplayColor.opacity(0.2))
            .foregroundStyle(item.value.typeDisplayColor)
            .cornerRadius(4)
    }
}

// MARK: - Previews

#Preview("Settings List - With Data") {
    @Previewable @State var selectedKey: String?
    @Previewable @State var searchText: String = ""
    @Previewable @State var viewModel = SettingsViewModel(project: nil)
    viewModel.settingItems = [
        SettingItem(
            key: "editor.fontSize",
            value: .int(14),
            source: .globalSettings,
            contributions: [SourceContribution(source: .globalSettings, value: .int(14))]
        ),
        SettingItem(
            key: "editor.theme",
            value: .string("dark"),
            source: .projectSettings,
            overriddenBy: .projectLocal,
            contributions: [
                SourceContribution(source: .projectSettings, value: .string("light")),
                SourceContribution(source: .projectLocal, value: .string("dark")),
            ]
        ),
        SettingItem(
            key: "editor.tabSize",
            value: .int(2),
            source: .globalSettings,
            contributions: [SourceContribution(source: .globalSettings, value: .int(2))]
        ),
        SettingItem(
            key: "files.exclude",
            value: .array([.string("node_modules"), .string(".git"), .string("dist")]),
            source: .globalSettings,
            contributions: [
                SourceContribution(source: .globalSettings, value: .array([.string("node_modules"), .string(".git")])),
                SourceContribution(source: .projectSettings, value: .array([.string("dist")])),
            ]
        ),
        SettingItem(
            key: "hooks.Notification",
            value: .object(["enabled": .bool(true)]),
            source: .projectSettings,
            contributions: [SourceContribution(source: .projectSettings, value: .object(["enabled": .bool(true)]))]
        ),
        SettingItem(
            key: "hooks.FileCreated",
            value: .object(["script": .string("create.sh")]),
            source: .projectSettings,
            contributions: [SourceContribution(source: .projectSettings, value: .object(["script": .string("create.sh")]))]
        ),
        SettingItem(
            key: "deprecated.setting",
            value: .bool(true),
            source: .globalSettings,
            contributions: [SourceContribution(source: .globalSettings, value: .bool(true))]
        ),
        SettingItem(
            key: "simpleValue",
            value: .string("test"),
            source: .globalSettings,
            contributions: [SourceContribution(source: .globalSettings, value: .string("test"))]
        ),
    ]
    viewModel.hierarchicalSettings = viewModel.computeHierarchicalSettings(from: viewModel.settingItems)
    viewModel.validationErrors = [
        ValidationError(
            type: .syntax,
            message: "Invalid JSON syntax in settings file",
            key: nil,
            suggestion: "Check for missing commas or brackets"
        ),
        ValidationError(
            type: .deprecated,
            message: "This setting is no longer recommended",
            key: "deprecated.setting",
            suggestion: "Use 'new.setting' instead"
        ),
    ]

    return NavigationStack {
        SettingsListView(settingsViewModel: viewModel, selectedKey: $selectedKey, searchText: $searchText)
    }
    .frame(width: 600, height: 800)
}

#Preview("Settings List - Empty") {
    @Previewable @State var selectedKey: String?
    @Previewable @State var searchText: String = ""
    @Previewable @State var viewModel = SettingsViewModel(project: nil)
    viewModel.settingItems = []

    return NavigationStack {
        SettingsListView(settingsViewModel: viewModel, selectedKey: $selectedKey, searchText: $searchText)
    }
    .frame(width: 600, height: 800)
}

#Preview("Settings List - Loading") {
    @Previewable @State var selectedKey: String?
    @Previewable @State var searchText: String = ""
    @Previewable @State var viewModel = SettingsViewModel(project: nil)
    viewModel.isLoading = true

    return NavigationStack {
        SettingsListView(settingsViewModel: viewModel, selectedKey: $selectedKey, searchText: $searchText)
    }
    .frame(width: 600, height: 800)
}

#Preview("Validation Error Row - Syntax") {
    ValidationErrorRow(
        error: ValidationError(
            type: .syntax,
            message: "Invalid JSON syntax in settings file",
            key: "editor.fontSize",
            suggestion: "Check for missing commas or brackets"
        )
    )
    .padding()
}

#Preview("Validation Error Row - Deprecated") {
    ValidationErrorRow(
        error: ValidationError(
            type: .deprecated,
            message: "This setting is no longer recommended",
            key: "old.setting",
            suggestion: "Use 'new.setting' instead"
        )
    )
    .padding()
}

#Preview("Validation Error Row - Unknown Key") {
    ValidationErrorRow(
        error: ValidationError(
            type: .unknownKey,
            message: "Unknown configuration key",
            key: "unknown.key",
            suggestion: nil
        )
    )
    .padding()
}

#Preview("Setting Item Row - String") {
    let viewModel = SettingsViewModel(project: nil)
    return SettingItemRow(
        item: SettingItem(
            key: "editor.theme",
            value: .string("dark"),
            source: .projectSettings,
            contributions: [SourceContribution(source: .projectSettings, value: .string("dark"))]
        ),
        isSelected: false,
        settingsViewModel: viewModel
    )
    .padding()
}

#Preview("Setting Item Row - Number") {
    let viewModel = SettingsViewModel(project: nil)
    return SettingItemRow(
        item: SettingItem(
            key: "editor.fontSize",
            value: .int(14),
            source: .globalSettings,
            contributions: [SourceContribution(source: .globalSettings, value: .int(14))]
        ),
        isSelected: false,
        settingsViewModel: viewModel
    )
    .padding()
}

#Preview("Setting Item Row - Array (Additive)") {
    @Previewable @State var viewModel = SettingsViewModel(project: nil)
    SettingItemRow(
        item: SettingItem(
            key: "files.exclude",
            value: .array([.string("node_modules"), .string(".git"), .string("dist")]),
            source: .globalSettings,
            contributions: [
                SourceContribution(source: .globalSettings, value: .array([.string("node_modules"), .string(".git")])),
                SourceContribution(source: .projectSettings, value: .array([.string("dist")])),
            ]
        ),
        isSelected: false,
        settingsViewModel: viewModel
    )
    .padding()
}

#Preview("Setting Item Row - Overridden") {
    @Previewable @State var viewModel = SettingsViewModel(project: nil)
    SettingItemRow(
        item: SettingItem(
            key: "editor.tabSize",
            value: .int(2),
            source: .globalSettings,
            overriddenBy: .projectLocal,
            contributions: [
                SourceContribution(source: .globalSettings, value: .int(4)),
                SourceContribution(source: .projectLocal, value: .int(2)),
            ]
        ),
        isSelected: false,
        settingsViewModel: viewModel
    )
    .padding()
}

#Preview("Setting Item Row - Deprecated") {
    @Previewable @State var viewModel = SettingsViewModel(project: nil)
    SettingItemRow(
        item: SettingItem(
            key: "model",
            value: .string("claude-sonnet-4-5-20250929"),
            source: .globalSettings,
            contributions: [SourceContribution(source: .globalSettings, value: .string("claude-sonnet-4-5-20250929"))]
        ),
        isSelected: false,
        settingsViewModel: viewModel
    )
    .padding()
}

#Preview("Setting Item Row - Selected") {
    let viewModel = SettingsViewModel(project: nil)
    return SettingItemRow(
        item: SettingItem(
            key: "editor.fontSize",
            value: .int(16),
            source: .globalSettings,
            contributions: [SourceContribution(source: .globalSettings, value: .int(16))]
        ),
        isSelected: true,
        settingsViewModel: viewModel
    )
    .padding()
}

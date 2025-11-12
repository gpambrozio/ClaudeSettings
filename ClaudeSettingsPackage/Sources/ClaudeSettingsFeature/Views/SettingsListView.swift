import SwiftUI

/// View displaying the list of settings with their values
public struct SettingsListView: View {
    let settingsViewModel: SettingsViewModel
    @Binding var selectedKey: String?
    @ObservedObject var documentationLoader: DocumentationLoader
    @State private var expandedNodes: Set<String> = []
    @State private var showSaveError = false
    @State private var saveErrorMessage: String?

    public init(settingsViewModel: SettingsViewModel, selectedKey: Binding<String?>, documentationLoader: DocumentationLoader = DocumentationLoader.shared) {
        self.settingsViewModel = settingsViewModel
        self._selectedKey = selectedKey
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
                            // TODO: Implement in Phase 1.5
                        }
                        Button("Import Settings") {
                            // TODO: Implement in Phase 2
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
    }

    @ViewBuilder
    private var settingsContent: some View {
        List(selection: $selectedKey) {
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
                ForEach(settingsViewModel.hierarchicalSettings) { node in
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
                    Text("\(settingsViewModel.settingItems.count) settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: .constant(""), prompt: "Search settings...")
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

    @State private var showDeleteConfirmation = false
    @State private var showCopySheet = false
    @State private var showMoveSheet = false
    @State private var showErrorAlert = false
    @State private var selectedSourceType: SettingsFileType?

    var body: some View {
        Group {
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
                    .onTapGesture {
                        selectedKey = node.key
                    }
                    .contextMenu {
                        Button(action: {
                            showCopySheet = true
                        }) {
                            Label("Copy to...", symbol: .arrowRightDocOnClipboard)
                        }
                        .disabled(settingsViewModel.isEditingMode)

                        Button(action: {
                            showMoveSheet = true
                        }) {
                            Label("Move to...", symbol: .arrowshapeTurnUpForward)
                        }
                        .disabled(settingsViewModel.isEditingMode)

                        Divider()

                        Button(role: .destructive, action: {
                            showDeleteConfirmation = true
                        }) {
                            Label("Delete", symbol: .trash)
                        }
                        .disabled(settingsViewModel.isEditingMode)
                    }
                }
                .tag(node.key)
                .sheet(isPresented: $showCopySheet, onDismiss: {
                    selectedSourceType = nil
                }) {
                    NodeCopyMoveSheet(
                        nodeKey: node.key,
                        mode: .copy,
                        contributingSources: SettingsActionHelpers.contributingFileTypes(for: node.key, in: settingsViewModel),
                        availableFileTypes: SettingsActionHelpers.availableFileTypes(for: settingsViewModel),
                        selectedSourceType: $selectedSourceType,
                        onConfirm: { source, destination in
                            performCopyNode(from: source, to: destination)
                            showCopySheet = false
                            selectedSourceType = nil
                        },
                        onCancel: {
                            showCopySheet = false
                            selectedSourceType = nil
                        }
                    )
                }
                .sheet(isPresented: $showMoveSheet, onDismiss: {
                    selectedSourceType = nil
                }) {
                    NodeCopyMoveSheet(
                        nodeKey: node.key,
                        mode: .move,
                        contributingSources: SettingsActionHelpers.contributingFileTypes(for: node.key, in: settingsViewModel),
                        availableFileTypes: SettingsActionHelpers.availableFileTypes(for: settingsViewModel),
                        selectedSourceType: $selectedSourceType,
                        onConfirm: { source, destination in
                            performMoveNode(from: source, to: destination)
                            showMoveSheet = false
                            selectedSourceType = nil
                        },
                        onCancel: {
                            showMoveSheet = false
                            selectedSourceType = nil
                        }
                    )
                }
                .confirmationDialog(
                    "Delete Setting Group",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    let contributingSources = SettingsActionHelpers.contributingFileTypes(for: node.key, in: settingsViewModel)

                    // Show delete option for each writable file
                    ForEach(contributingSources, id: \.self) { fileType in
                        if !SettingsActionHelpers.isReadOnly(fileType: fileType, in: settingsViewModel) {
                            Button("Delete from \(fileType.displayName)", role: .destructive) {
                                performDeleteNode(from: fileType)
                            }
                        }
                    }

                    // Option to delete from all files if there are multiple
                    let writableFiles = contributingSources.filter { !SettingsActionHelpers.isReadOnly(fileType: $0, in: settingsViewModel) }
                    if writableFiles.count > 1 {
                        Divider()
                        Button("Delete from All Files", role: .destructive) {
                            performDeleteNodeFromAll(fileTypes: writableFiles)
                        }
                    }

                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("Choose which file to delete '\(node.key)' and all its child settings from. This action cannot be undone.")
                }
                .alert("Error", isPresented: $showErrorAlert) {
                    Button("OK", role: .cancel) {
                        settingsViewModel.errorMessage = nil
                    }
                } message: {
                    if let errorMessage = settingsViewModel.errorMessage {
                        Text(errorMessage)
                    }
                }
                .onChange(of: settingsViewModel.errorMessage) { _, newValue in
                    showErrorAlert = newValue != nil
                }
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

    // MARK: - Parent Node Action Handlers

    private func performCopyNode(from source: SettingsFileType, to destination: SettingsFileType) {
        Task {
            do {
                try await settingsViewModel.copyNode(key: node.key, from: source, to: destination)
            } catch {
                await MainActor.run {
                    settingsViewModel.errorMessage = "Failed to copy '\(node.key)' from \(source.displayName) to \(destination.displayName): \(error.localizedDescription)"
                }
            }
        }
    }

    private func performMoveNode(from source: SettingsFileType, to destination: SettingsFileType) {
        Task {
            do {
                try await settingsViewModel.moveNode(key: node.key, from: source, to: destination)
            } catch {
                await MainActor.run {
                    settingsViewModel.errorMessage = "Failed to move '\(node.key)' from \(source.displayName) to \(destination.displayName): \(error.localizedDescription)"
                }
            }
        }
    }

    private func performDeleteNode(from fileType: SettingsFileType) {
        Task {
            do {
                try await settingsViewModel.deleteNode(key: node.key, from: fileType)
            } catch {
                await MainActor.run {
                    settingsViewModel.errorMessage = "Failed to delete '\(node.key)' from \(fileType.displayName): \(error.localizedDescription)"
                }
            }
        }
    }

    private func performDeleteNodeFromAll(fileTypes: [SettingsFileType]) {
        Task {
            do {
                for fileType in fileTypes where !isReadOnly(fileType: fileType) {
                    try await settingsViewModel.deleteNode(key: node.key, from: fileType)
                }
            } catch {
                await MainActor.run {
                    let fileNames = fileTypes.map { $0.displayName }.joined(separator: ", ")
                    settingsViewModel.errorMessage = "Failed to delete '\(node.key)' from all files (\(fileNames)): \(error.localizedDescription)"
                }
            }
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

    @State private var showDeleteConfirmation = false
    @State private var showCopySheet = false
    @State private var showMoveSheet = false
    @State private var showErrorAlert = false

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
        .contextMenu {
            Button(action: {
                copyToClipboard(formatValue(item.value))
            }) {
                Label("Copy Value", symbol: .docOnDoc)
            }
            .disabled(settingsViewModel.isEditingMode)

            Divider()

            Button(action: {
                showCopySheet = true
            }) {
                Label("Copy to...", symbol: .arrowRightDocOnClipboard)
            }
            .disabled(settingsViewModel.isEditingMode)

            Button(action: {
                showMoveSheet = true
            }) {
                Label("Move to...", symbol: .arrowshapeTurnUpForward)
            }
            .disabled(settingsViewModel.isEditingMode)

            Divider()

            Button(role: .destructive, action: {
                showDeleteConfirmation = true
            }) {
                Label("Delete", symbol: .trash)
            }
            .disabled(settingsViewModel.isEditingMode)
        }
        .sheet(isPresented: $showCopySheet) {
            SettingCopyMoveSheet(
                settingKey: item.key,
                mode: .copy,
                availableFileTypes: SettingsActionHelpers.availableFileTypes(for: settingsViewModel),
                onSelectDestination: { destination in
                    performCopy(to: destination)
                    showCopySheet = false
                },
                onCancel: {
                    showCopySheet = false
                }
            )
        }
        .sheet(isPresented: $showMoveSheet) {
            SettingCopyMoveSheet(
                settingKey: item.key,
                mode: .move,
                availableFileTypes: SettingsActionHelpers.availableFileTypes(for: settingsViewModel),
                onSelectDestination: { destination in
                    performMove(to: destination)
                    showMoveSheet = false
                },
                onCancel: {
                    showMoveSheet = false
                }
            )
        }
        .confirmationDialog(
            "Delete Setting",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            // Show delete option for each writable file that contains this setting
            ForEach(item.contributions, id: \.source) { contribution in
                if !SettingsActionHelpers.isReadOnly(fileType: contribution.source, in: settingsViewModel) {
                    Button("Delete from \(contribution.source.displayName)", role: .destructive) {
                        performDelete(from: contribution.source)
                    }
                }
            }

            // Option to delete from all files if there are multiple
            if item.contributions.filter({ !SettingsActionHelpers.isReadOnly(fileType: $0.source, in: settingsViewModel) }).count > 1 {
                Divider()
                Button("Delete from All Files", role: .destructive) {
                    performDeleteFromAll()
                }
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose which file to delete '\(item.key)' from. This action cannot be undone.")
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {
                settingsViewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = settingsViewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .onChange(of: settingsViewModel.errorMessage) { _, newValue in
            showErrorAlert = newValue != nil
        }
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
        switch type {
        case .globalSettings:
            return "Global"
        case .globalLocal:
            return "Global Local"
        case .projectSettings:
            return "Project"
        case .projectLocal:
            return "Project Local"
        case .enterpriseManaged:
            return "Enterprise"
        case .globalMemory,
             .projectMemory,
             .projectLocalMemory:
            return "Memory"
        }
    }

    private func sourceColor(for type: SettingsFileType) -> Color {
        switch type {
        case .enterpriseManaged:
            return .purple
        case .globalSettings,
             .globalLocal,
             .globalMemory:
            return .blue
        case .projectSettings,
             .projectLocal,
             .projectMemory,
             .projectLocalMemory:
            return .green
        }
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
        let typeInfo = valueTypeInfo
        Text(typeInfo.0)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(typeInfo.1.opacity(0.2))
            .foregroundStyle(typeInfo.1)
            .cornerRadius(4)
    }

    private var valueTypeInfo: (String, Color) {
        switch item.value {
        case .string:
            return ("string", .blue)
        case .bool:
            return ("bool", .green)
        case .int,
             .double:
            return ("number", .orange)
        case .array:
            return ("array", .purple)
        case .object:
            return ("object", .pink)
        case .null:
            return ("null", .gray)
        }
    }

    // MARK: - Action Helpers

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func formatValue(_ value: SettingValue) -> String {
        value.formatted()
    }

    // MARK: - Action Handlers

    private func performCopy(to destination: SettingsFileType) {
        let sourceType = item.contributions.last?.source ?? item.source

        Task {
            do {
                try await settingsViewModel.copySetting(key: item.key, from: sourceType, to: destination)
            } catch {
                await MainActor.run {
                    settingsViewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func performMove(to destination: SettingsFileType) {
        let sourceType = item.contributions.last?.source ?? item.source

        Task {
            do {
                try await settingsViewModel.moveSetting(key: item.key, from: sourceType, to: destination)
            } catch {
                await MainActor.run {
                    settingsViewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func performDelete(from fileType: SettingsFileType) {
        Task {
            do {
                try await settingsViewModel.deleteSetting(key: item.key, from: fileType)
            } catch {
                await MainActor.run {
                    settingsViewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func performDeleteFromAll() {
        Task {
            do {
                for contribution in item.contributions where !SettingsActionHelpers.isReadOnly(fileType: contribution.source, in: settingsViewModel) {
                    try await settingsViewModel.deleteSetting(key: item.key, from: contribution.source)
                }
            } catch {
                await MainActor.run {
                    settingsViewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Settings List - With Data") {
    @Previewable @State var selectedKey: String?
    let viewModel = SettingsViewModel(project: nil)
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
        SettingsListView(settingsViewModel: viewModel, selectedKey: $selectedKey)
    }
    .frame(width: 600, height: 800)
}

#Preview("Settings List - Empty") {
    @Previewable @State var selectedKey: String?
    let viewModel = SettingsViewModel(project: nil)
    viewModel.settingItems = []

    return NavigationStack {
        SettingsListView(settingsViewModel: viewModel, selectedKey: $selectedKey)
    }
    .frame(width: 600, height: 800)
}

#Preview("Settings List - Loading") {
    @Previewable @State var selectedKey: String?
    let viewModel = SettingsViewModel(project: nil)
    viewModel.isLoading = true

    return NavigationStack {
        SettingsListView(settingsViewModel: viewModel, selectedKey: $selectedKey)
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
    let viewModel = SettingsViewModel(project: nil)
    return SettingItemRow(
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
    let viewModel = SettingsViewModel(project: nil)
    return SettingItemRow(
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
    let viewModel = SettingsViewModel(project: nil)
    return SettingItemRow(
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

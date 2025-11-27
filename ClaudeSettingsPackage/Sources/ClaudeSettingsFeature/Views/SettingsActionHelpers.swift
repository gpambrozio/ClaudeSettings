import SwiftUI

// MARK: - Action State

/// Observable state object for managing action sheet and dialog presentation
@Observable
class SettingActionState {
    var showDeleteConfirmation = false
    var showCopySheet = false
    var showMoveSheet = false
    var showErrorAlert = false
    var selectedSourceType: SettingsFileType?

    /// Reset all state to default values
    func reset() {
        showDeleteConfirmation = false
        showCopySheet = false
        showMoveSheet = false
        showErrorAlert = false
        selectedSourceType = nil
    }

    /// Dismiss the copy sheet and reset source selection
    func dismissCopySheet() {
        showCopySheet = false
        selectedSourceType = nil
    }

    /// Dismiss the move sheet and reset source selection
    func dismissMoveSheet() {
        showMoveSheet = false
        selectedSourceType = nil
    }
}

// MARK: - Shared Action Sheets

/// Reusable sheet for copying or moving a setting to another file
struct SettingCopyMoveSheet: View {
    let settingKey: String
    let mode: CopyMoveMode
    let availableFileTypes: [SettingsFileType]
    let onSelectDestination: (SettingsFileType) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(mode.title)
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 8) {
                Text("Setting Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(settingKey)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Select Destination File")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(availableFileTypes, id: \.self) { fileType in
                    Button(action: {
                        onSelectDestination(fileType)
                    }) {
                        HStack {
                            Circle()
                                .fill(SettingsActionHelpers.sourceColor(for: fileType))
                                .frame(width: 8, height: 8)
                            Text(fileType.displayName)
                            Spacer()
                            Symbols.chevronRight.image
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding()
        .frame(width: 400)
    }
}

/// Reusable sheet for copying or moving a parent node (with source selection)
struct NodeCopyMoveSheet: View {
    let nodeKey: String
    let mode: CopyMoveMode
    let contributingSources: [SettingsFileType]
    let availableFileTypes: [SettingsFileType]
    @Binding var selectedSourceType: SettingsFileType?
    let onConfirm: (SettingsFileType, SettingsFileType) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(mode.title)
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 8) {
                Text("Setting Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(nodeKey)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Select Source File")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(contributingSources, id: \.self) { sourceType in
                    Button(action: {
                        selectedSourceType = sourceType
                    }) {
                        HStack {
                            Circle()
                                .fill(SettingsActionHelpers.sourceColor(for: sourceType))
                                .frame(width: 8, height: 8)
                            Text(sourceType.displayName)
                            Spacer()
                            Symbols.chevronRight.image
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let selectedSource = selectedSourceType {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Destination File")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(availableFileTypes, id: \.self) { destType in
                        Button(action: {
                            onConfirm(selectedSource, destType)
                        }) {
                            HStack {
                                Circle()
                                    .fill(SettingsActionHelpers.sourceColor(for: destType))
                                    .frame(width: 8, height: 8)
                                Text(destType.displayName)
                                Spacer()
                                Symbols.chevronRight.image
                                    .font(.caption)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - Shared Types

enum CopyMoveMode {
    case copy
    case move

    var title: String {
        switch self {
        case .copy: return "Copy"
        case .move: return "Move"
        }
    }
}

// MARK: - Helper Functions

enum SettingsActionHelpers {
    /// Returns the list of writable file types available for operations
    @MainActor
    static func availableFileTypes(for viewModel: SettingsViewModel) -> [SettingsFileType] {
        var types: [SettingsFileType] = []

        // Global files (always available)
        types.append(.globalSettings)
        types.append(.globalLocal)

        // Project files (only if viewing a project)
        if viewModel.isProjectView {
            types.append(.projectSettings)
            types.append(.projectLocal)
        }

        // Filter out read-only files
        return types.filter { type in
            if let file = viewModel.settingsFiles.first(where: { $0.type == type }) {
                return !file.isReadOnly
            }
            return true // Can create new files
        }
    }

    /// Checks if a file type is read-only
    @MainActor
    static func isReadOnly(fileType: SettingsFileType, in viewModel: SettingsViewModel) -> Bool {
        if let file = viewModel.settingsFiles.first(where: { $0.type == fileType }) {
            return file.isReadOnly
        }
        return false
    }

    /// Returns the color associated with a settings file type
    static func sourceColor(for type: SettingsFileType) -> Color {
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

    /// Returns the display label for a settings file type
    static func sourceLabel(for type: SettingsFileType) -> String {
        switch type {
        case .globalSettings:
            return "Global Settings"
        case .globalLocal:
            return "Global Local"
        case .projectSettings:
            return "Project Settings"
        case .projectLocal:
            return "Project Local"
        case .enterpriseManaged:
            return "Enterprise Managed"
        case .globalMemory,
             .projectMemory,
             .projectLocalMemory:
            return "Memory File"
        }
    }

    /// Returns all file types that contribute to a parent node
    @MainActor
    static func contributingFileTypes(for key: String, in viewModel: SettingsViewModel) -> [SettingsFileType] {
        let childSettings = viewModel.settingItems.filter { $0.key.hasPrefix(key + ".") || $0.key == key }
        let fileTypes = Set(childSettings.flatMap { $0.contributions.map(\.source) })
        return Array(fileTypes).sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Action Handlers

    /// Copies a setting from its source to a destination file
    static func copySetting(item: SettingItem, to destination: SettingsFileType, viewModel: SettingsViewModel) async throws {
        let sourceType = item.contributions.last?.source ?? item.source
        try await viewModel.copySetting(key: item.key, from: sourceType, to: destination)
    }

    /// Moves a setting from its source to a destination file
    static func moveSetting(item: SettingItem, to destination: SettingsFileType, viewModel: SettingsViewModel) async throws {
        let sourceType = item.contributions.last?.source ?? item.source
        try await viewModel.moveSetting(key: item.key, from: sourceType, to: destination)
    }

    /// Deletes a setting from a specific file
    static func deleteSetting(item: SettingItem, from fileType: SettingsFileType, viewModel: SettingsViewModel) async throws {
        try await viewModel.deleteSetting(key: item.key, from: fileType)
    }

    /// Deletes a setting from all writable files that contain it
    @MainActor
    static func deleteSettingFromAll(item: SettingItem, viewModel: SettingsViewModel) async throws {
        for contribution in item.contributions where !isReadOnly(fileType: contribution.source, in: viewModel) {
            try await viewModel.deleteSetting(key: item.key, from: contribution.source)
        }
    }

    /// Copies a parent node from source to destination file
    static func copyNode(key: String, from source: SettingsFileType, to destination: SettingsFileType, viewModel: SettingsViewModel) async throws {
        try await viewModel.copyNode(key: key, from: source, to: destination)
    }

    /// Moves a parent node from source to destination file
    static func moveNode(key: String, from source: SettingsFileType, to destination: SettingsFileType, viewModel: SettingsViewModel) async throws {
        try await viewModel.moveNode(key: key, from: source, to: destination)
    }

    /// Deletes a parent node from a specific file
    static func deleteNode(key: String, from fileType: SettingsFileType, viewModel: SettingsViewModel) async throws {
        try await viewModel.deleteNode(key: key, from: fileType)
    }

    /// Deletes a parent node from all specified files
    @MainActor
    static func deleteNodeFromAll(key: String, fileTypes: [SettingsFileType], viewModel: SettingsViewModel) async throws {
        for fileType in fileTypes where !isReadOnly(fileType: fileType, in: viewModel) {
            try await viewModel.deleteNode(key: key, from: fileType)
        }
    }
}

// MARK: - View Modifiers

/// View modifier that adds action sheets, confirmation dialogs, and error handling for a setting item (leaf node)
struct SettingItemActionsModifier: ViewModifier {
    let item: SettingItem
    let viewModel: SettingsViewModel
    @Bindable var actionState: SettingActionState

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $actionState.showCopySheet) {
                SettingCopyMoveSheet(
                    settingKey: item.key,
                    mode: .copy,
                    availableFileTypes: SettingsActionHelpers.availableFileTypes(for: viewModel),
                    onSelectDestination: { destination in
                        Task {
                            do {
                                try await SettingsActionHelpers.copySetting(item: item, to: destination, viewModel: viewModel)
                                await MainActor.run {
                                    actionState.dismissCopySheet()
                                }
                            } catch {
                                await MainActor.run {
                                    let source = item.contributions.last?.source ?? item.source
                                    viewModel.errorMessage = "Failed to copy '\(item.key)' from \(source.displayName) to \(destination.displayName): \(error.localizedDescription)"
                                }
                            }
                        }
                    },
                    onCancel: {
                        actionState.dismissCopySheet()
                    }
                )
            }
            .sheet(isPresented: $actionState.showMoveSheet) {
                SettingCopyMoveSheet(
                    settingKey: item.key,
                    mode: .move,
                    availableFileTypes: SettingsActionHelpers.availableFileTypes(for: viewModel),
                    onSelectDestination: { destination in
                        Task {
                            do {
                                try await SettingsActionHelpers.moveSetting(item: item, to: destination, viewModel: viewModel)
                                await MainActor.run {
                                    actionState.dismissMoveSheet()
                                }
                            } catch {
                                await MainActor.run {
                                    let source = item.contributions.last?.source ?? item.source
                                    viewModel.errorMessage = "Failed to move '\(item.key)' from \(source.displayName) to \(destination.displayName): \(error.localizedDescription)"
                                }
                            }
                        }
                    },
                    onCancel: {
                        actionState.dismissMoveSheet()
                    }
                )
            }
            .confirmationDialog(
                "Delete Setting",
                isPresented: $actionState.showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                // Show delete option for each writable file that contains this setting
                ForEach(item.contributions, id: \.source) { contribution in
                    if !SettingsActionHelpers.isReadOnly(fileType: contribution.source, in: viewModel) {
                        Button("Delete from \(contribution.source.displayName)", role: .destructive) {
                            Task {
                                do {
                                    try await SettingsActionHelpers.deleteSetting(item: item, from: contribution.source, viewModel: viewModel)
                                } catch {
                                    await MainActor.run {
                                        viewModel.errorMessage = "Failed to delete '\(item.key)' from \(contribution.source.displayName): \(error.localizedDescription)"
                                    }
                                }
                            }
                        }
                    }
                }

                // Option to delete from all files if there are multiple
                if item.contributions.filter({ !SettingsActionHelpers.isReadOnly(fileType: $0.source, in: viewModel) }).count > 1 {
                    Divider()
                    Button("Delete from All Files", role: .destructive) {
                        Task {
                            do {
                                try await SettingsActionHelpers.deleteSettingFromAll(item: item, viewModel: viewModel)
                            } catch {
                                await MainActor.run {
                                    let fileNames = item.contributions.map { $0.source.displayName }.joined(separator: ", ")
                                    viewModel.errorMessage = "Failed to delete '\(item.key)' from all files (\(fileNames)): \(error.localizedDescription)"
                                }
                            }
                        }
                    }
                }

                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Choose which file to delete '\(item.key)' from. This action cannot be undone.")
            }
            .alert("Error", isPresented: $actionState.showErrorAlert) {
                Button("OK", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                }
            }
            .onChange(of: viewModel.errorMessage) { _, newValue in
                actionState.showErrorAlert = newValue != nil
            }
    }
}

/// View modifier that adds action sheets, confirmation dialogs, and error handling for a parent node
struct ParentNodeActionsModifier: ViewModifier {
    let nodeKey: String
    let viewModel: SettingsViewModel
    @Bindable var actionState: SettingActionState

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $actionState.showCopySheet, onDismiss: {
                actionState.selectedSourceType = nil
            }) {
                NodeCopyMoveSheet(
                    nodeKey: nodeKey,
                    mode: .copy,
                    contributingSources: SettingsActionHelpers.contributingFileTypes(for: nodeKey, in: viewModel),
                    availableFileTypes: SettingsActionHelpers.availableFileTypes(for: viewModel),
                    selectedSourceType: $actionState.selectedSourceType,
                    onConfirm: { source, destination in
                        Task {
                            do {
                                try await SettingsActionHelpers.copyNode(key: nodeKey, from: source, to: destination, viewModel: viewModel)
                                await MainActor.run {
                                    actionState.dismissCopySheet()
                                }
                            } catch {
                                await MainActor.run {
                                    viewModel.errorMessage = "Failed to copy '\(nodeKey)' from \(source.displayName) to \(destination.displayName): \(error.localizedDescription)"
                                }
                            }
                        }
                    },
                    onCancel: {
                        actionState.dismissCopySheet()
                    }
                )
            }
            .sheet(isPresented: $actionState.showMoveSheet, onDismiss: {
                actionState.selectedSourceType = nil
            }) {
                NodeCopyMoveSheet(
                    nodeKey: nodeKey,
                    mode: .move,
                    contributingSources: SettingsActionHelpers.contributingFileTypes(for: nodeKey, in: viewModel),
                    availableFileTypes: SettingsActionHelpers.availableFileTypes(for: viewModel),
                    selectedSourceType: $actionState.selectedSourceType,
                    onConfirm: { source, destination in
                        Task {
                            do {
                                try await SettingsActionHelpers.moveNode(key: nodeKey, from: source, to: destination, viewModel: viewModel)
                                await MainActor.run {
                                    actionState.dismissMoveSheet()
                                }
                            } catch {
                                await MainActor.run {
                                    viewModel.errorMessage = "Failed to move '\(nodeKey)' from \(source.displayName) to \(destination.displayName): \(error.localizedDescription)"
                                }
                            }
                        }
                    },
                    onCancel: {
                        actionState.dismissMoveSheet()
                    }
                )
            }
            .confirmationDialog(
                "Delete Setting Group",
                isPresented: $actionState.showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                let contributingSources = SettingsActionHelpers.contributingFileTypes(for: nodeKey, in: viewModel)

                // Show delete option for each writable file
                ForEach(contributingSources, id: \.self) { fileType in
                    if !SettingsActionHelpers.isReadOnly(fileType: fileType, in: viewModel) {
                        Button("Delete from \(fileType.displayName)", role: .destructive) {
                            Task {
                                do {
                                    try await SettingsActionHelpers.deleteNode(key: nodeKey, from: fileType, viewModel: viewModel)
                                } catch {
                                    await MainActor.run {
                                        viewModel.errorMessage = "Failed to delete '\(nodeKey)' from \(fileType.displayName): \(error.localizedDescription)"
                                    }
                                }
                            }
                        }
                    }
                }

                // Option to delete from all files if there are multiple
                let writableFiles = contributingSources.filter { !SettingsActionHelpers.isReadOnly(fileType: $0, in: viewModel) }
                if writableFiles.count > 1 {
                    Divider()
                    Button("Delete from All Files", role: .destructive) {
                        Task {
                            do {
                                try await SettingsActionHelpers.deleteNodeFromAll(key: nodeKey, fileTypes: writableFiles, viewModel: viewModel)
                            } catch {
                                await MainActor.run {
                                    let fileNames = writableFiles.map { $0.displayName }.joined(separator: ", ")
                                    viewModel.errorMessage = "Failed to delete '\(nodeKey)' from all files (\(fileNames)): \(error.localizedDescription)"
                                }
                            }
                        }
                    }
                }

                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Choose which file to delete '\(nodeKey)' and all its child settings from. This action cannot be undone.")
            }
            .alert("Error", isPresented: $actionState.showErrorAlert) {
                Button("OK", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                }
            }
            .onChange(of: viewModel.errorMessage) { _, newValue in
                actionState.showErrorAlert = newValue != nil
            }
    }
}

/// View modifier that adds a context menu for setting items (leaf nodes)
struct SettingItemContextMenuModifier: ViewModifier {
    let item: SettingItem
    let viewModel: SettingsViewModel
    let actionState: SettingActionState

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(action: {
                copyToClipboard(formatValue(item.value))
            }) {
                Label("Copy Value", symbol: .docOnDoc)
            }
            .disabled(viewModel.isEditingMode)

            Divider()

            Button(action: {
                actionState.showCopySheet = true
            }) {
                Label("Copy to...", symbol: .arrowRightDocOnClipboard)
            }
            .disabled(viewModel.isEditingMode)

            Button(action: {
                actionState.showMoveSheet = true
            }) {
                Label("Move to...", symbol: .arrowshapeTurnUpForward)
            }
            .disabled(viewModel.isEditingMode)

            Divider()

            Button(role: .destructive, action: {
                actionState.showDeleteConfirmation = true
            }) {
                Label("Delete", symbol: .trash)
            }
            .disabled(viewModel.isEditingMode)
        }
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func formatValue(_ value: SettingValue) -> String {
        value.formatted()
    }
}

/// View modifier that adds a context menu for parent nodes
struct ParentNodeContextMenuModifier: ViewModifier {
    let nodeKey: String
    let viewModel: SettingsViewModel
    let actionState: SettingActionState

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(action: {
                actionState.showCopySheet = true
            }) {
                Label("Copy to...", symbol: .arrowRightDocOnClipboard)
            }
            .disabled(viewModel.isEditingMode)

            Button(action: {
                actionState.showMoveSheet = true
            }) {
                Label("Move to...", symbol: .arrowshapeTurnUpForward)
            }
            .disabled(viewModel.isEditingMode)

            Divider()

            Button(role: .destructive, action: {
                actionState.showDeleteConfirmation = true
            }) {
                Label("Delete", symbol: .trash)
            }
            .disabled(viewModel.isEditingMode)
        }
    }
}

/// Wrapper modifier that only applies ParentNodeActionsModifier if both nodeKey and viewModel are non-nil
struct OptionalParentNodeActionsModifier: ViewModifier {
    let nodeKey: String?
    let viewModel: SettingsViewModel?
    let actionState: SettingActionState

    func body(content: Content) -> some View {
        if let nodeKey = nodeKey, let viewModel = viewModel {
            content.parentNodeActions(
                nodeKey: nodeKey,
                viewModel: viewModel,
                actionState: actionState
            )
        } else {
            content
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Conditional view modifier
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Conditional view modifier that unwraps an optional value
    /// - Parameters:
    ///   - value: A closure returning an optional value
    ///   - transform: A transform to apply if the value is non-nil
    /// - Returns: The transformed view if value is non-nil, otherwise the original view
    @ViewBuilder
    func ifLet<T, Transform: View>(
        _ value: @autoclosure () -> T?,
        transform: (Self, T) -> Transform
    ) -> some View {
        if let unwrapped = value() {
            transform(self, unwrapped)
        } else {
            self
        }
    }

    /// Adds action sheets and dialogs for setting item operations
    func settingItemActions(
        item: SettingItem,
        viewModel: SettingsViewModel,
        actionState: SettingActionState
    ) -> some View {
        modifier(SettingItemActionsModifier(
            item: item,
            viewModel: viewModel,
            actionState: actionState
        ))
    }

    /// Adds action sheets and dialogs for parent node operations
    func parentNodeActions(
        nodeKey: String,
        viewModel: SettingsViewModel,
        actionState: SettingActionState
    ) -> some View {
        modifier(ParentNodeActionsModifier(
            nodeKey: nodeKey,
            viewModel: viewModel,
            actionState: actionState
        ))
    }

    /// Adds a context menu for setting items (leaf nodes)
    func settingItemContextMenu(
        item: SettingItem,
        viewModel: SettingsViewModel,
        actionState: SettingActionState
    ) -> some View {
        modifier(SettingItemContextMenuModifier(
            item: item,
            viewModel: viewModel,
            actionState: actionState
        ))
    }

    /// Adds a context menu for parent nodes
    func parentNodeContextMenu(
        nodeKey: String,
        viewModel: SettingsViewModel,
        actionState: SettingActionState
    ) -> some View {
        modifier(ParentNodeContextMenuModifier(
            nodeKey: nodeKey,
            viewModel: viewModel,
            actionState: actionState
        ))
    }
}

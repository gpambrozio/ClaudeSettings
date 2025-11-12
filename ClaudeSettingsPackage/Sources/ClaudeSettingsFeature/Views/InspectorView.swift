import AppKit
import SwiftUI

/// Inspector view showing details and actions for the selected item
public struct InspectorView: View {
    let selectedKey: String?
    let settingsViewModel: SettingsViewModel?
    @ObservedObject var documentationLoader: DocumentationLoader

    @State private var showDeleteConfirmation = false
    @State private var showCopySheet = false
    @State private var showMoveSheet = false
    @State private var showErrorAlert = false
    @State private var selectedSourceType: SettingsFileType?

    public var body: some View {
        Group {
            if let key = selectedKey, let viewModel = settingsViewModel {
                settingDetails(key: key, viewModel: viewModel)
            } else {
                emptyState
            }
        }
        .frame(minWidth: 200, idealWidth: 250)
    }

    @ViewBuilder
    private func settingDetails(key: String, viewModel: SettingsViewModel) -> some View {
        if let item = viewModel.settingItems.first(where: { $0.key == key }) {
            // Leaf node with actual setting value
            leafNodeDetails(item: item)
        } else if let doc = documentationLoader.documentation(for: key) {
            // Parent node with documentation
            parentNodeDetails(key: key, documentation: doc)
        } else {
            // Parent node without documentation
            parentNodeWithoutDocumentation(key: key, viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func leafNodeDetails(item: SettingItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Key section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    HStack {
                        Text(item.key)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)

                        let typeInfo = getTypeInfo(item.value)
                        Text(typeInfo.0)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(typeInfo.1.opacity(0.2))
                            .foregroundStyle(typeInfo.1)
                            .cornerRadius(6)

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
                }

                // Show all source contributions
                ForEach(Array(item.contributions.enumerated()), id: \.offset) { index, contribution in
                    Divider()

                    contributionRow(
                        contribution: contribution,
                        item: item,
                        index: index,
                        isOverridden: !item.isAdditive && index < item.contributions.count - 1
                    )
                }

                // Documentation section
                if documentationLoader.documentationWithFallback(for: item.key) != nil {
                    Divider()

                    DocumentationSectionView(
                        settingItem: item,
                        documentationLoader: documentationLoader
                    )
                }

                Divider()

                // Actions section
                if let viewModel = settingsViewModel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Actions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        HStack(spacing: 20) {
                            Button(action: {
                                copyToClipboard(formatValue(item.value))
                            }) {
                                Text("Copy Value")
                                    .padding(.horizontal, 10)
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isEditingMode)

                            Spacer()
                        }

                        HStack(spacing: 20) {
                            Button(action: {
                                showCopySheet = true
                            }) {
                                Text("Copy to...")
                                    .padding(.horizontal, 10)
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isEditingMode)

                            Button(action: {
                                showMoveSheet = true
                            }) {
                                Text("Move to...")
                                    .padding(.horizontal, 10)
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isEditingMode)

                            Spacer()
                        }

                        Button(action: {
                            showDeleteConfirmation = true
                        }) {
                            Text("Delete")
                                .padding(.horizontal, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(viewModel.isEditingMode)
                    }
                }

                Spacer()
            }
            .padding()
            .sheet(isPresented: $showCopySheet) {
                copyMoveSheet(item: item, mode: .copy)
            }
            .sheet(isPresented: $showMoveSheet) {
                copyMoveSheet(item: item, mode: .move)
            }
            .confirmationDialog(
                "Delete Setting",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                if let viewModel = settingsViewModel {
                    // Show delete option for each writable file that contains this setting
                    ForEach(item.contributions, id: \.source) { contribution in
                        if !isReadOnly(fileType: contribution.source, in: viewModel) {
                            Button("Delete from \(contribution.source.displayName)", role: .destructive) {
                                performDelete(item: item, from: contribution.source)
                            }
                        }
                    }

                    // Option to delete from all files if there are multiple
                    if item.contributions.filter({ !isReadOnly(fileType: $0.source, in: viewModel) }).count > 1 {
                        Divider()
                        Button("Delete from All Files", role: .destructive) {
                            performDeleteFromAll(item: item)
                        }
                    }
                }

                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Choose which file to delete '\(item.key)' from. This action cannot be undone.")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {
                    settingsViewModel?.errorMessage = nil
                }
            } message: {
                if let errorMessage = settingsViewModel?.errorMessage {
                    Text(errorMessage)
                }
            }
            .onChange(of: settingsViewModel?.errorMessage) { _, newValue in
                showErrorAlert = newValue != nil
            }
        }
    }

    // MARK: - Contribution Row

    @ViewBuilder
    private func contributionRow(
        contribution: SourceContribution,
        item: SettingItem,
        index: Int,
        isOverridden: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Get pending edit if it exists
            let pendingEdit = settingsViewModel?.getPendingEditOrCreate(for: item)
            let isEditingThisContribution = (settingsViewModel?.isEditingMode ?? false) &&
                pendingEdit?.targetFileType == contribution.source

            // Header: either file type selector (when editing) or label
            if isEditingThisContribution {
                contributionHeaderEditing(item: item, pendingEdit: pendingEdit)
            } else {
                contributionHeaderNormal(contribution: contribution, isOverridden: isOverridden)
            }

            // Value: either editor (when editing) or static text
            if isEditingThisContribution, let pendingEdit = pendingEdit {
                typeAwareEditor(for: pendingEdit.value, item: item, pendingEdit: pendingEdit)
                    .padding(.top, 4)
            } else {
                Text(formatValue(contribution.value))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .opacity(isOverridden ? 0.6 : 1)
            }
        }
    }

    @ViewBuilder
    private func contributionHeaderEditing(item: SettingItem, pendingEdit: PendingEdit?) -> some View {
        if let viewModel = settingsViewModel {
            Menu {
                ForEach(availableFileTypes(for: viewModel), id: \.self) { fileType in
                    Button(action: {
                        // Update the target file type for this pending edit
                        // Find the value from this file's contribution, or use current edited value
                        let newValue: SettingValue
                        if let contribution = item.contributions.first(where: { $0.source == fileType }) {
                            newValue = contribution.value
                        } else {
                            newValue = pendingEdit?.value ?? item.value
                        }
                        viewModel.updatePendingEditIfChanged(item: item, value: newValue, targetFileType: fileType)
                    }) {
                        HStack {
                            Text(fileType.displayName)
                            if pendingEdit?.targetFileType == fileType {
                                Symbols.checkmarkCircle.image
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Circle()
                        .fill(sourceColor(for: pendingEdit?.targetFileType ?? .globalSettings))
                        .frame(width: 8, height: 8)
                    Text(pendingEdit?.targetFileType.displayName ?? "Select file")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Symbols.chevronUpChevronDown.image
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func contributionHeaderNormal(contribution: SourceContribution, isOverridden: Bool) -> some View {
        HStack {
            Circle()
                .fill(sourceColor(for: contribution.source))
                .frame(width: 8, height: 8)
            Text(sourceLabel(for: contribution.source))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if isOverridden {
                Text("(overridden)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }

    // MARK: - Copy/Move Sheet

    enum CopyMoveMode {
        case copy
        case move

        var title: String {
            switch self {
            case .copy: return "Copy Setting"
            case .move: return "Move Setting"
            }
        }

        var actionTitle: String {
            switch self {
            case .copy: return "Copy"
            case .move: return "Move"
            }
        }
    }

    @ViewBuilder
    private func copyMoveSheet(item: SettingItem, mode: CopyMoveMode) -> some View {
        VStack(spacing: 20) {
            Text(mode.title)
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 8) {
                Text("Setting Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.key)
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

                if let viewModel = settingsViewModel {
                    ForEach(availableFileTypes(for: viewModel), id: \.self) { fileType in
                        Button(action: {
                            if mode == .copy {
                                performCopy(item: item, to: fileType)
                                showCopySheet = false
                            } else {
                                performMove(item: item, to: fileType)
                                showMoveSheet = false
                            }
                        }) {
                            HStack {
                                Circle()
                                    .fill(sourceColor(for: fileType))
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
            }

            HStack {
                Button("Cancel") {
                    if mode == .copy {
                        showCopySheet = false
                    } else {
                        showMoveSheet = false
                    }
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding()
        .frame(width: 400)
    }

    /// Sheet for copying/moving a parent node (shows source selection)
    private func copyMoveSheetForNode(key: String, mode: CopyMoveMode) -> some View {
        VStack(spacing: 20) {
            Text(mode.title)
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 8) {
                Text("Setting Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(key)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }

            if let viewModel = settingsViewModel {
                let contributingSources = contributingFileTypes(for: key, in: viewModel)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Source File")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(contributingSources, id: \.self) { sourceType in
                        Button(action: {
                            // Show destination picker for this source
                            selectedSourceType = sourceType
                        }) {
                            HStack {
                                Circle()
                                    .fill(sourceColor(for: sourceType))
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

                        ForEach(availableFileTypes(for: viewModel), id: \.self) { destType in
                            Button(action: {
                                if mode == .copy {
                                    performCopyNode(key: key, from: selectedSource, to: destType)
                                    showCopySheet = false
                                    selectedSourceType = nil
                                } else {
                                    performMoveNode(key: key, from: selectedSource, to: destType)
                                    showMoveSheet = false
                                    selectedSourceType = nil
                                }
                            }) {
                                HStack {
                                    Circle()
                                        .fill(sourceColor(for: destType))
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
            }

            HStack {
                Button("Cancel") {
                    if mode == .copy {
                        showCopySheet = false
                    } else {
                        showMoveSheet = false
                    }
                    selectedSourceType = nil
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding()
        .frame(width: 400)
    }

    @ViewBuilder
    private func parentNodeDetails(key: String, documentation: SettingDocumentation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Key section for parent node
                VStack(alignment: .leading, spacing: 8) {
                    Text("Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    HStack {
                        Text(key)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)

                        Text(documentation.typeDescription)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.pink.opacity(0.2))
                            .foregroundStyle(.pink)
                            .cornerRadius(6)
                    }
                }

                Divider()

                // Documentation section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Documentation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    // Type and default value
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Type:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(documentation.typeDescription)
                                .font(.callout.monospaced())
                        }

                        if let defaultValue = documentation.defaultValue {
                            HStack {
                                Text("Default:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(defaultValue)
                                    .font(.callout.monospaced())
                            }
                        }

                        if let platformNote = documentation.platformNote {
                            HStack {
                                Symbols.exclamationmarkCircle.image
                                    .font(.caption2)
                                Text(platformNote)
                                    .font(.caption)
                            }
                            .foregroundStyle(.orange)
                        }
                    }

                    // Description
                    Text(documentation.description)
                        .font(.body)
                        .foregroundStyle(.primary)

                    // Hook types (specific to hooks setting)
                    if let hookTypes = documentation.hookTypes, !hookTypes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Available hook types:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(hookTypes, id: \.self) { hookType in
                                Text("• \(hookType)")
                                    .font(.callout.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Related environment variables
                    if let envVars = documentation.relatedEnvVars, !envVars.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Related environment variables:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(envVars, id: \.self) { envVar in
                                Text("• \(envVar)")
                                    .font(.callout.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Patterns (for permissions)
                    if let patterns = documentation.patterns, !patterns.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pattern syntax:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(patterns, id: \.self) { pattern in
                                Text("• \(pattern)")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Examples
                    if !documentation.examples.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Examples:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(documentation.examples) { example in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(example.description)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)

                                    Text(example.code)
                                        .font(.callout.monospaced())
                                        .padding(8)
                                        .background(Color.primary.opacity(0.05))
                                        .cornerRadius(4)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }

                // Actions section
                if let viewModel = settingsViewModel {
                    let contributingSources = contributingFileTypes(for: key, in: viewModel)

                    if !contributingSources.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Actions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            HStack(spacing: 20) {
                                Button(action: {
                                    showCopySheet = true
                                }) {
                                    Text("Copy to...")
                                        .padding(.horizontal, 10)
                                }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.isEditingMode)

                                Button(action: {
                                    showMoveSheet = true
                                }) {
                                    Text("Move to...")
                                        .padding(.horizontal, 10)
                                }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.isEditingMode)

                                Spacer()
                            }

                            Button(action: {
                                showDeleteConfirmation = true
                            }) {
                                Text("Delete")
                                    .padding(.horizontal, 10)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .disabled(viewModel.isEditingMode)
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        .sheet(isPresented: $showCopySheet, onDismiss: {
            selectedSourceType = nil
        }) {
            if let key = selectedKey {
                copyMoveSheetForNode(key: key, mode: .copy)
            }
        }
        .sheet(isPresented: $showMoveSheet, onDismiss: {
            selectedSourceType = nil
        }) {
            if let key = selectedKey {
                copyMoveSheetForNode(key: key, mode: .move)
            }
        }
        .confirmationDialog(
            "Delete Setting Group",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if let key = selectedKey, let viewModel = settingsViewModel {
                let contributingSources = contributingFileTypes(for: key, in: viewModel)

                // Show delete option for each writable file
                ForEach(contributingSources, id: \.self) { fileType in
                    if !isReadOnly(fileType: fileType, in: viewModel) {
                        Button("Delete from \(fileType.displayName)", role: .destructive) {
                            performDeleteNode(key: key, from: fileType)
                        }
                    }
                }

                // Option to delete from all files if there are multiple
                let writableFiles = contributingSources.filter { !isReadOnly(fileType: $0, in: viewModel) }
                if writableFiles.count > 1 {
                    Divider()
                    Button("Delete from All Files", role: .destructive) {
                        performDeleteNodeFromAll(key: key, fileTypes: writableFiles)
                    }
                }
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            if let key = selectedKey {
                Text("Choose which file to delete '\(key)' and all its child settings from. This action cannot be undone.")
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {
                settingsViewModel?.errorMessage = nil
            }
        } message: {
            if let errorMessage = settingsViewModel?.errorMessage {
                Text(errorMessage)
            }
        }
        .onChange(of: settingsViewModel?.errorMessage) { _, newValue in
            showErrorAlert = newValue != nil
        }
    }

    @ViewBuilder
    private func parentNodeWithoutDocumentation(key: String, viewModel: SettingsViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Key section for parent node
                VStack(alignment: .leading, spacing: 8) {
                    Text("Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text(key)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Parent Setting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text("This is a parent setting that contains \(childCount(for: key, in: viewModel)) child settings.")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Text("Select a child setting to view its details, or expand this node to see all children.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                // Actions section
                let contributingSources = contributingFileTypes(for: key, in: viewModel)

                if !contributingSources.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Actions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        HStack(spacing: 20) {
                            Button(action: {
                                showCopySheet = true
                            }) {
                                Text("Copy to...")
                                    .padding(.horizontal, 10)
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isEditingMode)

                            Button(action: {
                                showMoveSheet = true
                            }) {
                                Text("Move to...")
                                    .padding(.horizontal, 10)
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isEditingMode)

                            Spacer()
                        }

                        Button(action: {
                            showDeleteConfirmation = true
                        }) {
                            Text("Delete")
                                .padding(.horizontal, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(viewModel.isEditingMode)
                    }
                }

                Spacer()
            }
            .padding()
        }
        .sheet(isPresented: $showCopySheet, onDismiss: {
            selectedSourceType = nil
        }) {
            if let key = selectedKey {
                copyMoveSheetForNode(key: key, mode: .copy)
            }
        }
        .sheet(isPresented: $showMoveSheet, onDismiss: {
            selectedSourceType = nil
        }) {
            if let key = selectedKey {
                copyMoveSheetForNode(key: key, mode: .move)
            }
        }
        .confirmationDialog(
            "Delete Setting Group",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if let key = selectedKey {
                let contributingSources = contributingFileTypes(for: key, in: viewModel)

                // Show delete option for each writable file
                ForEach(contributingSources, id: \.self) { fileType in
                    if !isReadOnly(fileType: fileType, in: viewModel) {
                        Button("Delete from \(fileType.displayName)", role: .destructive) {
                            performDeleteNode(key: key, from: fileType)
                        }
                    }
                }

                // Option to delete from all files if there are multiple
                let writableFiles = contributingSources.filter { !isReadOnly(fileType: $0, in: viewModel) }
                if writableFiles.count > 1 {
                    Divider()
                    Button("Delete from All Files", role: .destructive) {
                        performDeleteNodeFromAll(key: key, fileTypes: writableFiles)
                    }
                }
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            if let key = selectedKey {
                Text("Choose which file to delete '\(key)' and all its child settings from. This action cannot be undone.")
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {
                settingsViewModel?.errorMessage = nil
            }
        } message: {
            if let errorMessage = settingsViewModel?.errorMessage {
                Text(errorMessage)
            }
        }
        .onChange(of: settingsViewModel?.errorMessage) { _, newValue in
            showErrorAlert = newValue != nil
        }
    }

    private func childCount(for key: String, in viewModel: SettingsViewModel) -> Int {
        viewModel.settingItems.filter { $0.key.hasPrefix(key + ".") }.count
    }

    @ViewBuilder
    private func sourceInfo(for item: SettingItem) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(sourceColor(for: item.source))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(sourceLabel(for: item.source))
                    .font(.body)

                Text(item.source.filename)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func overrideInfo(type: SettingsFileType) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(sourceColor(for: type))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(sourceLabel(for: type))
                    .font(.body)

                Text("This value overrides the original")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sourceLabel(for type: SettingsFileType) -> String {
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

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Selection", symbol: .listBullet)
        } description: {
            Text("Select a setting to view details")
        }
    }

    private func formatValue(_ value: SettingValue) -> String {
        value.formatted()
    }

    private func getTypeInfo(_ value: SettingValue) -> (String, Color) {
        switch value {
        case .string:
            return ("String", .blue)
        case .bool:
            return ("Boolean", .green)
        case .int,
             .double:
            return ("Number", .orange)
        case .array:
            return ("Array", .purple)
        case .object:
            return ("Object", .pink)
        case .null:
            return ("Null", .gray)
        }
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Type-Aware Editor

    @ViewBuilder
    private func typeAwareEditor(for value: SettingValue, item: SettingItem, pendingEdit: PendingEdit) -> some View {
        if let viewModel = settingsViewModel {
            switch value {
            case let .bool(boolValue):
                Toggle(isOn: Binding(
                    get: { if case let .bool(val) = pendingEdit.value { return val } else { return boolValue } },
                    set: { viewModel.updatePendingEditIfChanged(item: item, value: .bool($0), targetFileType: pendingEdit.targetFileType) }
                )) { EmptyView() }
                    .toggleStyle(.switch)

            case let .string(stringValue):
                // Check if documentation has enum values
                if
                    let doc = documentationLoader.documentationWithFallback(for: item.key),
                    let enumValues = doc.enumValues, !enumValues.isEmpty {
                    // Use menu for enum values
                    Menu {
                        ForEach(enumValues, id: \.self) { enumValue in
                            Button(enumValue) {
                                viewModel.updatePendingEditIfChanged(item: item, value: .string(enumValue), targetFileType: pendingEdit.targetFileType)
                            }
                        }
                    } label: {
                        HStack {
                            if case let .string(currentValue) = pendingEdit.value {
                                Text(currentValue)
                                    .font(.system(.body, design: .monospaced))
                            } else {
                                Text(stringValue)
                                    .font(.system(.body, design: .monospaced))
                            }
                            Symbols.chevronUpChevronDown.image
                                .font(.caption2)
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Regular text field
                    TextField("Value", text: Binding(
                        get: { if case let .string(val) = pendingEdit.value { return val } else { return stringValue } },
                        set: { viewModel.updatePendingEditIfChanged(item: item, value: .string($0), targetFileType: pendingEdit.targetFileType) }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

            case .int:
                NumberTextFieldView(
                    item: item,
                    pendingEdit: pendingEdit,
                    viewModel: viewModel,
                    numberType: .integer
                )

            case .double:
                NumberTextFieldView(
                    item: item,
                    pendingEdit: pendingEdit,
                    viewModel: viewModel,
                    numberType: .double
                )

            case .array,
                 .object:
                // For complex types, use a text editor with JSON
                JSONTextEditorView(
                    item: item,
                    pendingEdit: pendingEdit,
                    viewModel: viewModel
                )

            case .null:
                Text("null")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func availableFileTypes(for viewModel: SettingsViewModel) -> [SettingsFileType] {
        // Return writable file types that exist or can be created
        var types: [SettingsFileType] = []

        // Global files (always available)
        types.append(.globalSettings)
        types.append(.globalLocal)

        // Project files (only if there's a project)
        if viewModel.settingItems.contains(where: { !$0.source.isGlobal }) {
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

    // MARK: - Copy/Move/Delete Actions

    private func performCopy(item: SettingItem, to destination: SettingsFileType) {
        guard let viewModel = settingsViewModel else { return }

        // Find the source file type for the active value
        let sourceType = item.contributions.last?.source ?? item.source

        Task {
            do {
                try await viewModel.copySetting(key: item.key, from: sourceType, to: destination)
            } catch {
                await MainActor.run {
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func performMove(item: SettingItem, to destination: SettingsFileType) {
        guard let viewModel = settingsViewModel else { return }

        // Find the source file type for the active value
        let sourceType = item.contributions.last?.source ?? item.source

        Task {
            do {
                try await viewModel.moveSetting(key: item.key, from: sourceType, to: destination)
            } catch {
                await MainActor.run {
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func performDelete(item: SettingItem, from fileType: SettingsFileType) {
        guard let viewModel = settingsViewModel else { return }

        Task {
            do {
                try await viewModel.deleteSetting(key: item.key, from: fileType)
            } catch {
                await MainActor.run {
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func performDeleteFromAll(item: SettingItem) {
        guard let viewModel = settingsViewModel else { return }

        // Delete from all writable files that have this setting
        Task {
            do {
                for contribution in item.contributions where !isReadOnly(fileType: contribution.source, in: viewModel) {
                    try await viewModel.deleteSetting(key: item.key, from: contribution.source)
                }
            } catch {
                await MainActor.run {
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Node Operations (for parent nodes)

    /// Get all file types that contribute to a parent node (any child settings)
    private func contributingFileTypes(for key: String, in viewModel: SettingsViewModel) -> [SettingsFileType] {
        let childSettings = viewModel.settingItems.filter { $0.key.hasPrefix(key + ".") || $0.key == key }
        let fileTypes = Set(childSettings.flatMap { $0.contributions.map(\.source) })
        return Array(fileTypes).sorted { $0.displayName < $1.displayName }
    }

    private func performCopyNode(key: String, from source: SettingsFileType, to destination: SettingsFileType) {
        guard let viewModel = settingsViewModel else { return }

        Task {
            do {
                try await viewModel.copyNode(key: key, from: source, to: destination)
            } catch {
                await MainActor.run {
                    viewModel.errorMessage = "Failed to copy '\(key)' from \(source.displayName) to \(destination.displayName): \(error.localizedDescription)"
                }
            }
        }
    }

    private func performMoveNode(key: String, from source: SettingsFileType, to destination: SettingsFileType) {
        guard let viewModel = settingsViewModel else { return }

        Task {
            do {
                try await viewModel.moveNode(key: key, from: source, to: destination)
            } catch {
                await MainActor.run {
                    viewModel.errorMessage = "Failed to move '\(key)' from \(source.displayName) to \(destination.displayName): \(error.localizedDescription)"
                }
            }
        }
    }

    private func performDeleteNode(key: String, from fileType: SettingsFileType) {
        guard let viewModel = settingsViewModel else { return }

        Task {
            do {
                try await viewModel.deleteNode(key: key, from: fileType)
            } catch {
                await MainActor.run {
                    viewModel.errorMessage = "Failed to delete '\(key)' from \(fileType.displayName): \(error.localizedDescription)"
                }
            }
        }
    }

    private func performDeleteNodeFromAll(key: String, fileTypes: [SettingsFileType]) {
        guard let viewModel = settingsViewModel else { return }

        Task {
            do {
                for fileType in fileTypes where !isReadOnly(fileType: fileType, in: viewModel) {
                    try await viewModel.deleteNode(key: key, from: fileType)
                }
            } catch {
                await MainActor.run {
                    let fileNames = fileTypes.map { $0.displayName }.joined(separator: ", ")
                    viewModel.errorMessage = "Failed to delete '\(key)' from all files (\(fileNames)): \(error.localizedDescription)"
                }
            }
        }
    }

    private func isReadOnly(fileType: SettingsFileType, in viewModel: SettingsViewModel) -> Bool {
        if let file = viewModel.settingsFiles.first(where: { $0.type == fileType }) {
            return file.isReadOnly
        }
        return false
    }

    public init(
        selectedKey: String?,
        settingsViewModel: SettingsViewModel?,
        documentationLoader: DocumentationLoader = .shared
    ) {
        self.selectedKey = selectedKey
        self.settingsViewModel = settingsViewModel
        self.documentationLoader = documentationLoader
    }
}

// MARK: - JSON Text Editor Helper

/// Helper view for editing JSON with local state to prevent cursor jumping
private struct JSONTextEditorView: View {
    let item: SettingItem
    let pendingEdit: PendingEdit
    let viewModel: SettingsViewModel

    @State private var localText = ""
    @State private var localValidationError: String?
    @State private var isUpdatingFromExternal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: $localText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 100)
                .border(localValidationError != nil ? Color.red.opacity(0.5) : Color.secondary.opacity(0.3))
                .onChange(of: localText) { _, newText in
                    // Only validate if this isn't an external update
                    guard !isUpdatingFromExternal else { return }
                    validateAndUpdate(newText)
                }
                .onAppear {
                    // Initialize local text from pending edit
                    localText = pendingEdit.rawEditingText ?? pendingEdit.value.formatted()
                    localValidationError = pendingEdit.validationError
                }
                .onChange(of: pendingEdit.rawEditingText) { _, newRawText in
                    // Sync external changes (like switching target file)
                    // Guard against cycles: only update if different from current local text
                    let newText = newRawText ?? pendingEdit.value.formatted()
                    guard newText != localText else { return }

                    isUpdatingFromExternal = true
                    localText = newText
                    isUpdatingFromExternal = false
                }
                .onChange(of: pendingEdit.validationError) { oldValue, newError in
                    // Only update if actually changed to avoid unnecessary updates
                    guard oldValue != newError else { return }
                    localValidationError = newError
                }

            if let validationError = localValidationError {
                HStack(spacing: 4) {
                    Symbols.exclamationmarkTriangle.image
                        .font(.caption2)
                    Text(validationError)
                        .font(.caption)
                }
                .foregroundStyle(.red)
            }
        }
    }

    private func validateAndUpdate(_ newText: String) {
        // Try to parse as JSON
        if
            let data = newText.data(using: .utf8),
            let jsonObject = try? JSONSerialization.jsonObject(with: data) {
            // Valid JSON - check if it differs from original before creating edit
            let newValue = SettingValue(any: jsonObject)
            viewModel.updatePendingEditIfChanged(
                item: item,
                value: newValue,
                targetFileType: pendingEdit.targetFileType,
                validationError: nil,
                rawEditingText: newText
            )
            localValidationError = nil
        } else if !newText.isEmpty {
            // Invalid JSON - always create pending edit with error
            viewModel.updatePendingEdit(
                key: item.key,
                value: pendingEdit.value, // Keep old value
                targetFileType: pendingEdit.targetFileType,
                validationError: "Invalid JSON syntax",
                rawEditingText: newText
            )
            localValidationError = "Invalid JSON syntax"
        } else {
            // Empty text - always create pending edit with error
            viewModel.updatePendingEdit(
                key: item.key,
                value: pendingEdit.value, // Keep old value
                targetFileType: pendingEdit.targetFileType,
                validationError: "Value is required",
                rawEditingText: newText
            )
            localValidationError = "Value is required"
        }
    }
}

// MARK: - Number TextField View

private struct NumberTextFieldView: View {
    let item: SettingItem
    let pendingEdit: PendingEdit
    let viewModel: SettingsViewModel
    let numberType: NumberType

    enum NumberType {
        case integer
        case double
    }

    @State private var localText = ""
    @State private var localValidationError: String?
    @State private var isUpdatingFromExternal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(numberType == .integer ? "Enter integer" : "Enter number", text: $localText)
                .textFieldStyle(.roundedBorder)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(localValidationError != nil ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
                )
                .onChange(of: localText) { _, newText in
                    guard !isUpdatingFromExternal else { return }
                    validateAndUpdate(newText)
                }
                .onAppear {
                    localText = pendingEdit.rawEditingText ?? pendingEdit.value.formatted()
                    localValidationError = pendingEdit.validationError
                }
                .onChange(of: pendingEdit.rawEditingText) { _, newRawText in
                    let newText = newRawText ?? pendingEdit.value.formatted()
                    guard newText != localText else { return }

                    isUpdatingFromExternal = true
                    localText = newText
                    isUpdatingFromExternal = false
                }
                .onChange(of: pendingEdit.validationError) { oldValue, newError in
                    guard oldValue != newError else { return }
                    localValidationError = newError
                }

            if let validationError = localValidationError {
                HStack(spacing: 4) {
                    Symbols.exclamationmarkTriangle.image
                        .font(.caption2)
                    Text(validationError)
                        .font(.caption)
                }
                .foregroundStyle(.red)
            }
        }
    }

    private func validateAndUpdate(_ newText: String) {
        let trimmedText = newText.trimmingCharacters(in: .whitespaces)

        // Check for empty input
        guard !trimmedText.isEmpty else {
            viewModel.updatePendingEdit(
                key: item.key,
                value: pendingEdit.value,
                targetFileType: pendingEdit.targetFileType,
                validationError: "Value is required",
                rawEditingText: trimmedText
            )
            localValidationError = "Value is required"
            return
        }

        // Validate based on number type
        switch numberType {
        case .integer:
            if let intValue = Int(trimmedText) {
                // Valid integer
                viewModel.updatePendingEditIfChanged(
                    item: item,
                    value: .int(intValue),
                    targetFileType: pendingEdit.targetFileType,
                    validationError: nil,
                    rawEditingText: trimmedText
                )
                localValidationError = nil
            } else {
                // Invalid integer
                viewModel.updatePendingEdit(
                    key: item.key,
                    value: pendingEdit.value,
                    targetFileType: pendingEdit.targetFileType,
                    validationError: "Must be a valid integer",
                    rawEditingText: trimmedText
                )
                localValidationError = "Must be a valid integer"
            }

        case .double:
            if let doubleValue = Double(trimmedText) {
                // Valid double
                viewModel.updatePendingEditIfChanged(
                    item: item,
                    value: .double(doubleValue),
                    targetFileType: pendingEdit.targetFileType,
                    validationError: nil,
                    rawEditingText: trimmedText
                )
                localValidationError = nil
            } else {
                // Invalid double
                viewModel.updatePendingEdit(
                    key: item.key,
                    value: pendingEdit.value,
                    targetFileType: pendingEdit.targetFileType,
                    validationError: "Must be a valid number",
                    rawEditingText: trimmedText
                )
                localValidationError = "Must be a valid number"
            }
        }
    }
}

// MARK: - NSTextView Extension for Smart Quotes

/// Disable smart quotes and dashes app-wide for JSON/code editing
extension NSTextView {
    open override var frame: CGRect {
        didSet {
            isAutomaticQuoteSubstitutionEnabled = false
            isAutomaticDashSubstitutionEnabled = false
            isAutomaticTextReplacementEnabled = false
        }
    }
}

// MARK: - Previews

#Preview("Inspector - With Selection") {
    @Previewable var settingItems: [SettingItem] = [
        SettingItem(
            key: "editor.fontSize",
            value: .int(16),
            source: .globalSettings,
            contributions: [
                SourceContribution(source: .globalSettings, value: .int(14)),
                SourceContribution(source: .projectLocal, value: .int(16)),
            ]
        ),
        SettingItem(
            key: "editor.theme",
            value: .string("dark"),
            source: .projectSettings,
            contributions: [SourceContribution(source: .projectSettings, value: .string("dark"))]
        ),
    ]

    let viewModel = SettingsViewModel(project: nil)
    viewModel.settingItems = settingItems

    return InspectorView(selectedKey: "editor.fontSize", settingsViewModel: viewModel)
        .frame(width: 300, height: 600)
}

#Preview("Inspector - Array (Additive)") {
    @Previewable var settingItems: [SettingItem] = [
        SettingItem(
            key: "files.exclude",
            value: .array([.string("node_modules"), .string(".git"), .string("dist"), .string("build")]),
            source: .globalSettings,
            contributions: [
                SourceContribution(source: .globalSettings, value: .array([.string("node_modules"), .string(".git")])),
                SourceContribution(source: .projectSettings, value: .array([.string("dist")])),
                SourceContribution(source: .projectLocal, value: .array([.string("build")])),
            ]
        ),
    ]

    let viewModel = SettingsViewModel(project: nil)
    viewModel.settingItems = settingItems

    return InspectorView(selectedKey: "files.exclude", settingsViewModel: viewModel)
        .frame(width: 300, height: 600)
}

#Preview("Inspector - Deprecated Setting") {
    let viewModel = SettingsViewModel(project: nil)
    viewModel.settingItems = [
        SettingItem(
            key: "deprecated.setting",
            value: .bool(true),
            source: .globalSettings,
            contributions: [SourceContribution(source: .globalSettings, value: .bool(true))]
        ),
    ]

    return InspectorView(selectedKey: "deprecated.setting", settingsViewModel: viewModel)
        .frame(width: 300, height: 600)
}

#Preview("Inspector - Object Type") {
    @Previewable var settingItems: [SettingItem] = [
        SettingItem(
            key: "editor.config",
            value: .object(["tabSize": .int(2), "insertSpaces": .bool(true), "detectIndentation": .bool(false)]),
            source: .projectSettings,
            contributions: [
                SourceContribution(
                    source: .projectSettings,
                    value: .object(["tabSize": .int(2), "insertSpaces": .bool(true), "detectIndentation": .bool(false)])
                ),
            ]
        ),
    ]

    let viewModel = SettingsViewModel(project: nil)
    viewModel.settingItems = settingItems

    return InspectorView(selectedKey: "editor.config", settingsViewModel: viewModel)
        .frame(width: 300, height: 600)
}

#Preview("Inspector - Editing Boolean") {
    @Previewable var settingItems: [SettingItem] = [
        SettingItem(
            key: "editor.formatOnSave",
            value: .bool(true),
            source: .globalSettings,
            contributions: [
                SourceContribution(source: .globalSettings, value: .bool(false)),
                SourceContribution(source: .projectLocal, value: .bool(true)),
            ]
        ),
    ]

    let viewModel = SettingsViewModel(project: nil)
    viewModel.settingItems = settingItems

    // Start editing mode and create pending edit
    viewModel.isEditingMode = true
    viewModel.pendingEdits["editor.formatOnSave"] = PendingEdit(
        key: "editor.formatOnSave",
        value: .bool(true),
        targetFileType: .projectLocal
    )

    return InspectorView(
        selectedKey: "editor.formatOnSave",
        settingsViewModel: viewModel
    )
    .frame(width: 500, height: 600)
}

#Preview("Inspector - Empty State") {
    InspectorView(selectedKey: nil, settingsViewModel: nil)
        .frame(width: 300, height: 600)
}

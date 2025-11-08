import SwiftUI

/// Inspector view showing details and actions for the selected item
public struct InspectorView: View {
    let selectedKey: String?
    let settingsViewModel: SettingsViewModel?
    @ObservedObject var documentationLoader: DocumentationLoader

    // Edit state
    @State private var isEditMode = false
    @State private var editedValue: SettingValue?
    @State private var selectedTargetFileType: SettingsFileType?
    @State private var showingDeleteConfirmation = false
    @State private var showingMoveConfirmation = false
    @State private var showingCopySheet = false
    @State private var showingMoveSheet = false
    @State private var operationMessage: String?
    @State private var operationError: String?

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

                        if item.isDeprecated {
                            Symbols.clockArrowCirclepath.image
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }

                        if !item.isActive {
                            Symbols.exclamationmarkTriangle.image
                                .foregroundStyle(.yellow)
                                .font(.caption)
                        }
                    }
                }

                // Show editor if in edit mode
                if isEditMode {
                    Divider()

                    SettingEditorView(
                        item: item,
                        documentation: documentationLoader.documentationWithFallback(for: item.key),
                        editedValue: $editedValue
                    )

                    // Target file selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Save To")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        targetFilePicker(for: item)
                    }

                    // Save/Cancel buttons
                    HStack(spacing: 8) {
                        Button("Cancel") {
                            cancelEdit()
                        }
                        .buttonStyle(.bordered)

                        Button("Save") {
                            Task {
                                await saveEdit(for: item)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(editedValue == nil || selectedTargetFileType == nil)
                    }
                } else {
                    // Show all source contributions
                    ForEach(Array(item.contributions.enumerated()), id: \.offset) { index, contribution in
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Circle()
                                    .fill(sourceColor(for: contribution.source))
                                    .frame(width: 8, height: 8)
                                Text(sourceLabel(for: contribution.source))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)

                                // Show override indicator for non-additive settings
                                if !item.isAdditive && index < item.contributions.count - 1 {
                                    Text("(overridden)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .italic()
                                }

                                Spacer()

                                // Delete button for each contribution
                                Button {
                                    selectedTargetFileType = contribution.source
                                    showingDeleteConfirmation = true
                                } label: {
                                    Symbols.trash.image
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                                .disabled(contribution.source == .enterpriseManaged)
                            }

                            Text(formatValue(contribution.value))
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .opacity(!item.isAdditive && index < item.contributions.count - 1 ? 0.6 : 1)
                        }
                    }
                }

                // Documentation section
                if !isEditMode, documentationLoader.documentationWithFallback(for: item.key) != nil || item.documentation != nil {
                    Divider()

                    DocumentationSectionView(
                        settingItem: item,
                        documentationLoader: documentationLoader
                    )
                }

                // Show operation message/error
                if let message = operationMessage {
                    Divider()
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.green)
                }

                if let error = operationError {
                    Divider()
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                Divider()

                // Actions section
                if !isEditMode {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Actions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Button("Copy Value") {
                                    copyToClipboard(formatValue(item.value))
                                }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)

                                Button("Edit") {
                                    startEdit(for: item)
                                }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)
                            }

                            HStack(spacing: 8) {
                                Button("Copy To...") {
                                    showingCopySheet = true
                                }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)

                                Button("Move To...") {
                                    showingMoveSheet = true
                                }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        .confirmationDialog("Delete Setting", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let fileType = selectedTargetFileType {
                    Task {
                        await deleteSetting(key: item.key, from: fileType)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let fileType = selectedTargetFileType {
                Text("Delete '\(item.key)' from \(sourceLabel(for: fileType))?\n\nCurrent value: \(formatValue(item.value))")
            }
        }
        .sheet(isPresented: $showingCopySheet) {
            copySheet(for: item)
        }
        .sheet(isPresented: $showingMoveSheet) {
            moveSheet(for: item)
        }
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

                Spacer()
            }
            .padding()
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

                Spacer()
            }
            .padding()
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

    // MARK: - Edit Operations

    private func startEdit(for item: SettingItem) {
        isEditMode = true
        editedValue = item.value
        // Default to the highest precedence writable file
        selectedTargetFileType = item.contributions.last(where: { $0.source != .enterpriseManaged })?.source
        operationMessage = nil
        operationError = nil
    }

    private func cancelEdit() {
        isEditMode = false
        editedValue = nil
        selectedTargetFileType = nil
        operationMessage = nil
        operationError = nil
    }

    private func saveEdit(for item: SettingItem) async {
        guard let value = editedValue, let fileType = selectedTargetFileType, let viewModel = settingsViewModel else {
            return
        }

        do {
            try await viewModel.updateSetting(key: item.key, value: value, in: fileType)
            operationMessage = "Successfully updated '\(item.key)'"
            operationError = nil
            isEditMode = false
            editedValue = nil
            selectedTargetFileType = nil
        } catch {
            operationError = "Failed to save: \(error.localizedDescription)"
            operationMessage = nil
        }
    }

    private func deleteSetting(key: String, from fileType: SettingsFileType) async {
        guard let viewModel = settingsViewModel else { return }

        do {
            try await viewModel.deleteSetting(key: key, from: fileType)
            operationMessage = "Successfully deleted '\(key)'"
            operationError = nil
        } catch {
            operationError = "Failed to delete: \(error.localizedDescription)"
            operationMessage = nil
        }
    }

    @ViewBuilder
    private func targetFilePicker(for item: SettingItem) -> some View {
        let writableFileTypes = item.contributions
            .map(\.source)
            .filter { $0 != .enterpriseManaged }

        if writableFileTypes.isEmpty {
            Text("No writable locations available")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Picker("Target File", selection: $selectedTargetFileType) {
                ForEach(writableFileTypes, id: \.self) { fileType in
                    HStack {
                        Circle()
                            .fill(sourceColor(for: fileType))
                            .frame(width: 8, height: 8)
                        Text(sourceLabel(for: fileType))
                    }
                    .tag(fileType as SettingsFileType?)
                }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private func copySheet(for item: SettingItem) -> some View {
        NavigationStack {
            Form {
                Section("Copy Setting") {
                    Text("Copy '\(item.key)' to another file")
                        .font(.body)
                }

                Section("Target File") {
                    let availableTargets = SettingsFileType.allCases.filter { $0 != .enterpriseManaged }
                    ForEach(availableTargets, id: \.self) { fileType in
                        Button {
                            Task {
                                await copySetting(key: item.key, from: item.source, to: fileType)
                                showingCopySheet = false
                            }
                        } label: {
                            HStack {
                                Circle()
                                    .fill(sourceColor(for: fileType))
                                    .frame(width: 12, height: 12)
                                Text(sourceLabel(for: fileType))
                                Spacer()
                                Text(fileType.filename)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Copy Setting")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingCopySheet = false
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
    }

    @ViewBuilder
    private func moveSheet(for item: SettingItem) -> some View {
        NavigationStack {
            Form {
                Section("Move Setting") {
                    Text("Move '\(item.key)' from \(sourceLabel(for: item.source)) to another file")
                        .font(.body)
                }

                Section("Target File") {
                    let availableTargets = SettingsFileType.allCases.filter { $0 != .enterpriseManaged && $0 != item.source }
                    ForEach(availableTargets, id: \.self) { fileType in
                        Button {
                            selectedTargetFileType = fileType
                            showingMoveConfirmation = true
                        } label: {
                            HStack {
                                Circle()
                                    .fill(sourceColor(for: fileType))
                                    .frame(width: 12, height: 12)
                                Text(sourceLabel(for: fileType))
                                Spacer()
                                Text(fileType.filename)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Move Setting")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingMoveSheet = false
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
        .confirmationDialog("Confirm Move", isPresented: $showingMoveConfirmation) {
            Button("Move", role: .destructive) {
                if let targetType = selectedTargetFileType {
                    Task {
                        await moveSetting(key: item.key, from: item.source, to: targetType)
                        showingMoveSheet = false
                        selectedTargetFileType = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                selectedTargetFileType = nil
            }
        } message: {
            if let targetType = selectedTargetFileType {
                Text("Move '\(item.key)' from \(sourceLabel(for: item.source)) to \(sourceLabel(for: targetType))?\n\nThis will delete it from the source file.")
            }
        }
    }

    private func copySetting(key: String, from sourceType: SettingsFileType, to targetType: SettingsFileType) async {
        guard let viewModel = settingsViewModel else { return }

        do {
            try await viewModel.copySetting(key: key, from: sourceType, to: targetType)
            operationMessage = "Successfully copied '\(key)' to \(sourceLabel(for: targetType))"
            operationError = nil
        } catch {
            operationError = "Failed to copy: \(error.localizedDescription)"
            operationMessage = nil
        }
    }

    private func moveSetting(key: String, from sourceType: SettingsFileType, to targetType: SettingsFileType) async {
        guard let viewModel = settingsViewModel else { return }

        do {
            try await viewModel.moveSetting(key: key, from: sourceType, to: targetType)
            operationMessage = "Successfully moved '\(key)' to \(sourceLabel(for: targetType))"
            operationError = nil
        } catch {
            operationError = "Failed to move: \(error.localizedDescription)"
            operationMessage = nil
        }
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
            ],
            documentation: "Controls the font size of the editor"
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
            ],
            documentation: "Files and directories to exclude from file operations"
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
            contributions: [SourceContribution(source: .globalSettings, value: .bool(true))],
            isDeprecated: true,
            documentation: "This setting is deprecated and will be removed in version 2"
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
            ],
            documentation: "Editor configuration object"
        ),
    ]

    let viewModel = SettingsViewModel(project: nil)
    viewModel.settingItems = settingItems

    return InspectorView(selectedKey: "editor.config", settingsViewModel: viewModel)
        .frame(width: 300, height: 600)
}

#Preview("Inspector - Empty State") {
    InspectorView(selectedKey: nil, settingsViewModel: nil)
        .frame(width: 300, height: 600)
}

import AppKit
import SwiftUI

/// Inspector view showing details and actions for the selected item
public struct InspectorView: View {
    let selectedKey: String?
    let settingsViewModel: SettingsViewModel?
    @ObservedObject var documentationLoader: DocumentationLoader
    @State private var actionState = SettingActionState()

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
                    SectionHeader(text: "Key")

                    HStack {
                        Text(item.key)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)

                        TypeBadge(value: item.value)

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
                        SectionHeader(text: "Actions")

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
                                actionState.showCopySheet = true
                            }) {
                                Text("Copy to...")
                                    .padding(.horizontal, 10)
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isEditingMode)

                            Button(action: {
                                actionState.showMoveSheet = true
                            }) {
                                Text("Move to...")
                                    .padding(.horizontal, 10)
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isEditingMode)

                            Spacer()
                        }

                        Button(action: {
                            actionState.showDeleteConfirmation = true
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
            .ifLet(settingsViewModel) { view, viewModel in
                view.settingItemActions(
                    item: item,
                    viewModel: viewModel,
                    actionState: actionState
                )
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
            // Show editor for the original contribution (where the setting came from)
            // This ensures the editor is visible even when the target file has no contribution yet
            let isEditingThisContribution = (settingsViewModel?.isEditingMode ?? false) &&
                pendingEdit?.originalFileType == contribution.source

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
                ForEach(SettingsActionHelpers.availableFileTypes(for: viewModel), id: \.self) { fileType in
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
                        .fill(SettingsActionHelpers.sourceColor(for: pendingEdit?.targetFileType ?? .globalSettings))
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
                .fill(SettingsActionHelpers.sourceColor(for: contribution.source))
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

    @ViewBuilder
    private func parentNodeDetails(key: String, documentation: SettingDocumentation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Key section for parent node
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(text: "Key")

                    HStack {
                        Text(key)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)

                        TypeBadge(schemaType: documentation.type, description: documentation.typeDescription)
                    }
                }

                Divider()

                // Documentation section - reuses DocumentationSectionView
                DocumentationSectionView(
                    documentation: documentation,
                    isDeprecated: documentation.deprecated == true
                )

                // Actions section
                if let viewModel = settingsViewModel {
                    let contributingSources = SettingsActionHelpers.contributingFileTypes(for: key, in: viewModel)

                    if !contributingSources.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(text: "Actions")

                            HStack(spacing: 20) {
                                Button(action: {
                                    actionState.showCopySheet = true
                                }) {
                                    Text("Copy to...")
                                        .padding(.horizontal, 10)
                                }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.isEditingMode)

                                Button(action: {
                                    actionState.showMoveSheet = true
                                }) {
                                    Text("Move to...")
                                        .padding(.horizontal, 10)
                                }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.isEditingMode)

                                Spacer()
                            }

                            Button(action: {
                                actionState.showDeleteConfirmation = true
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
        .modifier(OptionalParentNodeActionsModifier(
            nodeKey: selectedKey,
            viewModel: settingsViewModel,
            actionState: actionState
        ))
    }

    @ViewBuilder
    private func parentNodeWithoutDocumentation(key: String, viewModel: SettingsViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Key section for parent node
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(text: "Key")

                    Text(key)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(text: "Parent Setting")

                    Text("This is a parent setting that contains \(childCount(for: key, in: viewModel)) child settings.")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Text("Select a child setting to view its details, or expand this node to see all children.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                // Actions section
                let contributingSources = SettingsActionHelpers.contributingFileTypes(for: key, in: viewModel)

                if !contributingSources.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(text: "Actions")

                        HStack(spacing: 20) {
                            Button(action: {
                                actionState.showCopySheet = true
                            }) {
                                Text("Copy to...")
                                    .padding(.horizontal, 10)
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isEditingMode)

                            Button(action: {
                                actionState.showMoveSheet = true
                            }) {
                                Text("Move to...")
                                    .padding(.horizontal, 10)
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isEditingMode)

                            Spacer()
                        }

                        Button(action: {
                            actionState.showDeleteConfirmation = true
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
        .parentNodeActions(
            nodeKey: key,
            viewModel: viewModel,
            actionState: actionState
        )
    }

    private func childCount(for key: String, in viewModel: SettingsViewModel) -> Int {
        viewModel.settingItems.filter { $0.key.hasPrefix(key + ".") }.count
    }

    @ViewBuilder
    private func sourceInfo(for item: SettingItem) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(SettingsActionHelpers.sourceColor(for: item.source))
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
                .fill(SettingsActionHelpers.sourceColor(for: type))
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
        SettingsActionHelpers.sourceLabel(for: type)
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
                BooleanToggleEditor(
                    value: Binding(
                        get: { if case let .bool(val) = pendingEdit.value { return val } else { return boolValue } },
                        set: { viewModel.updatePendingEditIfChanged(item: item, value: .bool($0), targetFileType: pendingEdit.targetFileType) }
                    ),
                    showLabel: false
                )

            case let .string(stringValue):
                // Check if documentation has enum values
                if
                    let doc = documentationLoader.documentationWithFallback(for: item.key),
                    let enumValues = doc.enumValues, !enumValues.isEmpty {
                    // Use picker for enum values (standardized across the app)
                    EnumPickerEditor(
                        values: enumValues,
                        selection: Binding(
                            get: { if case let .string(val) = pendingEdit.value { return val } else { return stringValue } },
                            set: { viewModel.updatePendingEditIfChanged(item: item, value: .string($0), targetFileType: pendingEdit.targetFileType) }
                        )
                    )
                } else {
                    // Regular text field
                    StringTextFieldEditor(
                        placeholder: "Value",
                        text: Binding(
                            get: { if case let .string(val) = pendingEdit.value { return val } else { return stringValue } },
                            set: { viewModel.updatePendingEditIfChanged(item: item, value: .string($0), targetFileType: pendingEdit.targetFileType) }
                        )
                    )
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
            JSONTextEditor(text: $localText, hasError: localValidationError != nil)
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
                ValidationErrorView(message: validationError)
            }
        }
    }

    private func validateAndUpdate(_ newText: String) {
        let result = validateJSONInput(newText)

        if let value = result.value {
            viewModel.updatePendingEditIfChanged(
                item: item,
                value: value,
                targetFileType: pendingEdit.targetFileType,
                validationError: nil,
                rawEditingText: newText
            )
            localValidationError = nil
        } else {
            viewModel.updatePendingEdit(
                key: item.key,
                value: pendingEdit.value, // Keep old value
                targetFileType: pendingEdit.targetFileType,
                originalFileType: pendingEdit.originalFileType,
                validationError: result.error,
                rawEditingText: newText
            )
            localValidationError = result.error
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
            NumberTextFieldEditor(
                placeholder: numberType == .integer ? "Enter integer" : "Enter number",
                text: $localText,
                hasError: localValidationError != nil
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
                ValidationErrorView(message: validationError)
            }
        }
    }

    private func validateAndUpdate(_ newText: String) {
        let trimmedText = newText.trimmingCharacters(in: .whitespaces)

        // Validate based on number type using shared validation functions
        switch numberType {
        case .integer:
            let result = validateIntegerInput(trimmedText)
            if let value = result.value {
                viewModel.updatePendingEditIfChanged(
                    item: item,
                    value: .int(value),
                    targetFileType: pendingEdit.targetFileType,
                    validationError: nil,
                    rawEditingText: trimmedText
                )
                localValidationError = nil
            } else {
                viewModel.updatePendingEdit(
                    key: item.key,
                    value: pendingEdit.value,
                    targetFileType: pendingEdit.targetFileType,
                    originalFileType: pendingEdit.originalFileType,
                    validationError: result.error,
                    rawEditingText: trimmedText
                )
                localValidationError = result.error
            }

        case .double:
            let result = validateDoubleInput(trimmedText)
            if let value = result.value {
                viewModel.updatePendingEditIfChanged(
                    item: item,
                    value: .double(value),
                    targetFileType: pendingEdit.targetFileType,
                    validationError: nil,
                    rawEditingText: trimmedText
                )
                localValidationError = nil
            } else {
                viewModel.updatePendingEdit(
                    key: item.key,
                    value: pendingEdit.value,
                    targetFileType: pendingEdit.targetFileType,
                    originalFileType: pendingEdit.originalFileType,
                    validationError: result.error,
                    rawEditingText: trimmedText
                )
                localValidationError = result.error
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
        targetFileType: .projectLocal,
        originalFileType: .globalSettings
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

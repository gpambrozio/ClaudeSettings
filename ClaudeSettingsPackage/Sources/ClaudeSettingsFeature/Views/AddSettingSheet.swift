import AppKit
import SwiftUI

/// Sheet for adding a new setting to a configuration file
struct AddSettingSheet: View {
    let viewModel: SettingsViewModel
    @ObservedObject var documentationLoader: DocumentationLoader
    let onDismiss: () -> Void

    @State private var selectedCategory: SettingCategory?
    @State private var selectedSetting: SettingDocumentation?
    @State private var selectedFileType: SettingsFileType = .globalSettings
    @State private var currentValue: SettingValue = .null
    @State private var validationError: String?
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage: String?

    // Editor state for different types
    @State private var stringValue = ""
    @State private var boolValue = false
    @State private var intValue = ""
    @State private var doubleValue = ""
    @State private var jsonValue = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Setting")
                    .font(.title2)
                    .bold()
                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Content
            if let documentation = documentationLoader.documentation {
                HSplitView {
                    // Left: Category and setting selection
                    settingSelectionPane(documentation: documentation)
                        .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)

                    // Right: Configuration pane
                    configurationPane
                        .frame(minWidth: 300)
                }
            } else {
                ContentUnavailableView {
                    Label("Loading", symbol: .gearshape)
                } description: {
                    ProgressView()
                }
            }

            Divider()

            // Footer with actions
            HStack {
                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add Setting") {
                    Task {
                        await addSetting()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAddSetting)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .resizable(key: "AddSettingSheet", defaultWidth: 700, defaultHeight: 600)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .task {
            await documentationLoader.load()
        }
    }

    // MARK: - Setting Selection Pane

    @ViewBuilder
    private func settingSelectionPane(documentation: SettingsDocumentation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(text: "Select Setting")
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)

            List(selection: $selectedCategory) {
                ForEach(documentation.categories) { category in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { selectedCategory?.id == category.id },
                            set: { if $0 { selectedCategory = category } }
                        )
                    ) {
                        ForEach(availableSettings(in: category)) { setting in
                            settingRow(setting)
                                .tag(setting)
                        }
                    } label: {
                        HStack {
                            Text(category.name)
                                .font(.headline)
                            Spacer()
                            Text("\(availableSettings(in: category).count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private func settingRow(_ setting: SettingDocumentation) -> some View {
        Button(action: {
            selectSetting(setting)
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(setting.key)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(selectedSetting?.key == setting.key ? .primary : .secondary)

                    Text(setting.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if selectedSetting?.key == setting.key {
                    Symbols.checkmarkCircle.image
                        .foregroundStyle(.tint)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Filter settings to only show those not already present in any settings file
    private func availableSettings(in category: SettingCategory) -> [SettingDocumentation] {
        let existingKeys = Set(viewModel.settingItems.map(\.key))
        return category.settings.filter { setting in
            // Don't show deprecated settings
            if setting.deprecated == true { return false }
            // Don't show settings that already exist
            if existingKeys.contains(setting.key) { return false }
            return true
        }
    }

    // MARK: - Configuration Pane

    @ViewBuilder
    private var configurationPane: some View {
        if let setting = selectedSetting {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Setting key and type badge
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(text: "Setting")

                        HStack {
                            Text(setting.key)
                                .font(.system(.title3, design: .monospaced))

                            TypeBadge(schemaType: setting.type, description: setting.typeDescription)
                        }
                    }

                    Divider()

                    // File type selector
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(text: "Destination File")

                        Picker("", selection: $selectedFileType) {
                            ForEach(SettingsActionHelpers.availableFileTypes(for: viewModel), id: \.self) { fileType in
                                HStack {
                                    Circle()
                                        .fill(SettingsActionHelpers.sourceColor(for: fileType))
                                        .frame(width: 8, height: 8)
                                    Text(fileType.displayName)
                                }
                                .tag(fileType)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    Divider()

                    // Value editor
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(text: "Value")

                        valueEditor(for: setting)

                        if let validationError {
                            ValidationErrorView(message: validationError)
                        }

                        if let defaultValue = setting.defaultValue {
                            MetadataRow(label: "Default", value: defaultValue)
                        }
                    }

                    Divider()

                    // Documentation section - reuses DocumentationSectionView
                    DocumentationSectionView(
                        documentation: setting,
                        showHeader: true,
                        maxExamples: 2
                    )

                    Spacer()
                }
                .padding()
            }
        } else {
            VStack {
                Spacer()
                ContentUnavailableView {
                    Label("No Setting Selected", symbol: .listBullet)
                } description: {
                    Text("Select a setting from the list to configure it")
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Value Editor

    @ViewBuilder
    private func valueEditor(for setting: SettingDocumentation) -> some View {
        switch setting.type {
        case "boolean":
            Toggle(isOn: $boolValue) {
                Text(boolValue ? "true" : "false")
                    .font(.system(.body, design: .monospaced))
            }
            .toggleStyle(.switch)
            .onChange(of: boolValue) { _, newValue in
                currentValue = .bool(newValue)
                validationError = nil
            }

        case "string":
            if let enumValues = setting.enumValues, !enumValues.isEmpty {
                Picker("", selection: $stringValue) {
                    ForEach(enumValues, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .onChange(of: stringValue) { _, newValue in
                    currentValue = .string(newValue)
                    validationError = nil
                }
            } else {
                TextField("Enter value", text: $stringValue)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: stringValue) { _, newValue in
                        if newValue.isEmpty {
                            validationError = "Value is required"
                        } else {
                            currentValue = .string(newValue)
                            validationError = nil
                        }
                    }
            }

        case "integer":
            TextField("Enter integer", text: $intValue)
                .textFieldStyle(.roundedBorder)
                .onChange(of: intValue) { _, newValue in
                    validateInteger(newValue)
                }

        case "number":
            TextField("Enter number", text: $doubleValue)
                .textFieldStyle(.roundedBorder)
                .onChange(of: doubleValue) { _, newValue in
                    validateDouble(newValue)
                }

        case "array",
             "object":
            VStack(alignment: .leading, spacing: 4) {
                TextEditor(text: $jsonValue)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 100)
                    .border(validationError != nil ? Color.red.opacity(0.5) : Color.secondary.opacity(0.3))
                    .onChange(of: jsonValue) { _, newValue in
                        validateJSON(newValue, expectedType: setting.type)
                    }
            }

        default:
            TextField("Enter value", text: $stringValue)
                .textFieldStyle(.roundedBorder)
                .onChange(of: stringValue) { _, newValue in
                    currentValue = .string(newValue)
                    validationError = newValue.isEmpty ? "Value is required" : nil
                }
        }
    }

    // MARK: - Validation

    private func validateInteger(_ text: String) {
        let result = validateIntegerInput(text)
        if let value = result.value {
            currentValue = .int(value)
            validationError = nil
        } else {
            validationError = result.error
        }
    }

    private func validateDouble(_ text: String) {
        let result = validateDoubleInput(text)
        if let value = result.value {
            currentValue = .double(value)
            validationError = nil
        } else {
            validationError = result.error
        }
    }

    private func validateJSON(_ text: String, expectedType: String) {
        let result = validateJSONInput(text, expectedType: expectedType)
        if let value = result.value {
            currentValue = value
            validationError = nil
        } else {
            validationError = result.error
        }
    }

    // MARK: - Actions

    private func selectSetting(_ setting: SettingDocumentation) {
        selectedSetting = setting
        validationError = nil

        // Reset editor state and set default values
        switch setting.type {
        case "boolean":
            if let defaultValue = setting.defaultValue {
                boolValue = defaultValue.lowercased() == "true"
            } else {
                boolValue = false
            }
            currentValue = .bool(boolValue)

        case "string":
            if let enumValues = setting.enumValues, !enumValues.isEmpty {
                stringValue = setting.defaultValue ?? enumValues.first ?? ""
            } else {
                stringValue = setting.defaultValue ?? ""
            }
            currentValue = .string(stringValue)
            if stringValue.isEmpty && setting.enumValues == nil {
                validationError = "Value is required"
            }

        case "integer":
            intValue = setting.defaultValue ?? ""
            if let value = Int(intValue) {
                currentValue = .int(value)
            } else if !intValue.isEmpty {
                validationError = "Must be a valid integer"
            } else {
                validationError = "Value is required"
            }

        case "number":
            doubleValue = setting.defaultValue ?? ""
            if let value = Double(doubleValue) {
                currentValue = .double(value)
            } else if !doubleValue.isEmpty {
                validationError = "Must be a valid number"
            } else {
                validationError = "Value is required"
            }

        case "array":
            jsonValue = setting.defaultValue ?? "[]"
            validateJSON(jsonValue, expectedType: "array")

        case "object":
            jsonValue = setting.defaultValue ?? "{}"
            validateJSON(jsonValue, expectedType: "object")

        default:
            stringValue = setting.defaultValue ?? ""
            currentValue = .string(stringValue)
        }
    }

    private var canAddSetting: Bool {
        selectedSetting != nil && validationError == nil && !isSaving
    }

    private func addSetting() async {
        guard let setting = selectedSetting else { return }

        isSaving = true

        do {
            try await viewModel.updateSetting(
                key: setting.key,
                value: currentValue,
                in: selectedFileType
            )

            await MainActor.run {
                onDismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
                isSaving = false
            }
        }
    }
}

// MARK: - Preview

#Preview("Add Setting Sheet") {
    @Previewable let viewModel = SettingsViewModel(project: nil)

    return AddSettingSheet(
        viewModel: viewModel,
        documentationLoader: DocumentationLoader.shared,
        onDismiss: { }
    )
    .frame(width: 1_500, height: 1_000)
}

import SwiftUI

/// Sheet for editing a setting value with type-aware UI
struct SettingEditorSheet: View {
    let item: SettingItem
    let viewModel: SettingsViewModel
    let documentationLoader: DocumentationLoader
    let onSave: (SettingValue, SettingsFileType) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editedValue: SettingValue
    @State private var selectedTargetFile: SettingsFileType
    @State private var errorMessage: String?

    // For editing different types
    @State private var stringValue: String = ""
    @State private var boolValue: Bool = false
    @State private var intValue: String = ""
    @State private var doubleValue: String = ""
    @State private var arrayText: String = ""
    @State private var objectText: String = ""
    @State private var selectedEnumValue: String = ""

    init(
        item: SettingItem,
        viewModel: SettingsViewModel,
        documentationLoader: DocumentationLoader,
        onSave: @escaping (SettingValue, SettingsFileType) -> Void
    ) {
        self.item = item
        self.viewModel = viewModel
        self.documentationLoader = documentationLoader
        self.onSave = onSave

        // Initialize with highest precedence contribution (the active value)
        let activeContribution = item.contributions.last ?? item.contributions[0]
        _editedValue = State(initialValue: activeContribution.value)
        _selectedTargetFile = State(initialValue: activeContribution.source)

        // Initialize type-specific state based on value type
        switch activeContribution.value {
        case let .string(value):
            _stringValue = State(initialValue: value)
        case let .bool(value):
            _boolValue = State(initialValue: value)
        case let .int(value):
            _intValue = State(initialValue: String(value))
        case let .double(value):
            _doubleValue = State(initialValue: String(value))
        case let .array(values):
            _arrayText = State(initialValue: formatArrayForEditing(values))
        case let .object(dict):
            _objectText = State(initialValue: formatObjectForEditing(dict))
        case .null:
            break
        }

        // If documentation has enum values, select the current one
        if case let .string(value) = activeContribution.value {
            _selectedEnumValue = State(initialValue: value)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Setting Information") {
                    LabeledContent("Key") {
                        Text(item.key)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    LabeledContent("Type") {
                        Text(valueTypeDescription)
                            .font(.caption)
                    }
                }

                Section("Value") {
                    valueEditor
                }

                Section("Target File") {
                    Picker("Save to", selection: $selectedTargetFile) {
                        ForEach(availableTargetFiles, id: \.self) { fileType in
                            Text(fileTypeLabel(fileType))
                                .tag(fileType)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("The setting will be saved to this file")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let documentation = documentationLoader.documentationWithFallback(for: item.key) {
                    Section("Documentation") {
                        Text(documentation.description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = errorMessage {
                    Section {
                        HStack {
                            Symbols.exclamationmarkTriangle.image
                                .foregroundStyle(.red)
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Setting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    @ViewBuilder
    private var valueEditor: some View {
        let documentation = documentationLoader.documentationWithFallback(for: item.key)

        if let enumValues = documentation?.enumValues, !enumValues.isEmpty {
            // Use Menu for enum values
            Picker("Value", selection: $selectedEnumValue) {
                ForEach(enumValues, id: \.self) { enumValue in
                    Text(enumValue).tag(enumValue)
                }
            }
            .pickerStyle(.menu)
        } else {
            switch editedValue {
            case .bool:
                Toggle("Value", isOn: $boolValue)
            case .string:
                TextField("Value", text: $stringValue)
                    .font(.system(.body, design: .monospaced))
            case .int:
                TextField("Value", text: $intValue)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: intValue) { _, newValue in
                        validateIntValue(newValue)
                    }
            case .double:
                TextField("Value", text: $doubleValue)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: doubleValue) { _, newValue in
                        validateDoubleValue(newValue)
                    }
            case .array:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Array (JSON format)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $arrayText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 100)
                        .onChange(of: arrayText) { _, newValue in
                            validateArrayText(newValue)
                        }
                }
            case .object:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Object (JSON format)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $objectText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 150)
                        .onChange(of: objectText) { _, newValue in
                            validateObjectText(newValue)
                        }
                }
            case .null:
                Text("null")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var availableTargetFiles: [SettingsFileType] {
        // Get unique file types from contributions
        var files = Set(item.contributions.map(\.source))

        // Also allow saving to any writable settings file
        let writableTypes: [SettingsFileType] = [
            .globalSettings,
            .globalLocal,
            .projectSettings,
            .projectLocal
        ]

        for type in writableTypes {
            files.insert(type)
        }

        // Remove enterprise managed (read-only)
        files.remove(.enterpriseManaged)

        return Array(files).sorted { $0.precedence < $1.precedence }
    }

    private func fileTypeLabel(_ type: SettingsFileType) -> String {
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
            return "Enterprise Managed (Read-Only)"
        case .globalMemory,
             .projectMemory,
             .projectLocalMemory:
            return "Memory File"
        }
    }

    private var valueTypeDescription: String {
        switch editedValue {
        case .string:
            return "String"
        case .bool:
            return "Boolean"
        case .int:
            return "Integer"
        case .double:
            return "Number"
        case .array:
            return "Array"
        case .object:
            return "Object"
        case .null:
            return "Null"
        }
    }

    private var isValid: Bool {
        errorMessage == nil
    }

    private func validateIntValue(_ text: String) {
        if Int(text) == nil && !text.isEmpty {
            errorMessage = "Please enter a valid integer"
        } else {
            errorMessage = nil
        }
    }

    private func validateDoubleValue(_ text: String) {
        if Double(text) == nil && !text.isEmpty {
            errorMessage = "Please enter a valid number"
        } else {
            errorMessage = nil
        }
    }

    private func validateArrayText(_ text: String) {
        do {
            let jsonData = Data(text.utf8)
            let parsed = try JSONSerialization.jsonObject(with: jsonData)
            if parsed is [Any] {
                errorMessage = nil
            } else {
                errorMessage = "Value must be a JSON array"
            }
        } catch {
            errorMessage = "Invalid JSON: \(error.localizedDescription)"
        }
    }

    private func validateObjectText(_ text: String) {
        do {
            let jsonData = Data(text.utf8)
            let parsed = try JSONSerialization.jsonObject(with: jsonData)
            if parsed is [String: Any] {
                errorMessage = nil
            } else {
                errorMessage = "Value must be a JSON object"
            }
        } catch {
            errorMessage = "Invalid JSON: \(error.localizedDescription)"
        }
    }

    private func saveChanges() {
        // Build the new value based on the type
        let newValue: SettingValue

        let documentation = documentationLoader.documentationWithFallback(for: item.key)
        if let enumValues = documentation?.enumValues, !enumValues.isEmpty {
            newValue = .string(selectedEnumValue)
        } else {
            switch editedValue {
            case .bool:
                newValue = .bool(boolValue)
            case .string:
                newValue = .string(stringValue)
            case .int:
                if let intVal = Int(intValue) {
                    newValue = .int(intVal)
                } else {
                    errorMessage = "Invalid integer value"
                    return
                }
            case .double:
                if let doubleVal = Double(doubleValue) {
                    newValue = .double(doubleVal)
                } else {
                    errorMessage = "Invalid number value"
                    return
                }
            case .array:
                do {
                    let jsonData = Data(arrayText.utf8)
                    let parsed = try JSONSerialization.jsonObject(with: jsonData)
                    if let array = parsed as? [Any] {
                        newValue = .array(array.map { SettingValue(any: $0) })
                    } else {
                        errorMessage = "Value must be a JSON array"
                        return
                    }
                } catch {
                    errorMessage = "Invalid JSON: \(error.localizedDescription)"
                    return
                }
            case .object:
                do {
                    let jsonData = Data(objectText.utf8)
                    let parsed = try JSONSerialization.jsonObject(with: jsonData)
                    if let dict = parsed as? [String: Any] {
                        newValue = .object(dict.mapValues { SettingValue(any: $0) })
                    } else {
                        errorMessage = "Value must be a JSON object"
                        return
                    }
                } catch {
                    errorMessage = "Invalid JSON: \(error.localizedDescription)"
                    return
                }
            case .null:
                newValue = .null
            }
        }

        onSave(newValue, selectedTargetFile)
        dismiss()
    }

    private static func formatArrayForEditing(_ values: [SettingValue]) -> String {
        let array = values.map(\.asAny)
        if let data = try? JSONSerialization.data(withJSONObject: array, options: [.prettyPrinted, .withoutEscapingSlashes]),
           let string = String(data: data, encoding: .utf8)
        {
            return string
        }
        return "[]"
    }

    private static func formatObjectForEditing(_ dict: [String: SettingValue]) -> String {
        let object = dict.mapValues(\.asAny)
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
           let string = String(data: data, encoding: .utf8)
        {
            return string
        }
        return "{}"
    }
}

// MARK: - Previews

#Preview("String Editor") {
    @Previewable @State var saved = false

    let item = SettingItem(
        key: "editor.theme",
        value: .string("dark"),
        source: .globalSettings,
        contributions: [SourceContribution(source: .globalSettings, value: .string("dark"))]
    )

    let viewModel = SettingsViewModel(project: nil)

    return SettingEditorSheet(
        item: item,
        viewModel: viewModel,
        documentationLoader: .shared
    ) { value, target in
        saved = true
    }
}

#Preview("Boolean Editor") {
    @Previewable @State var saved = false

    let item = SettingItem(
        key: "editor.minimap.enabled",
        value: .bool(true),
        source: .globalSettings,
        contributions: [SourceContribution(source: .globalSettings, value: .bool(true))]
    )

    let viewModel = SettingsViewModel(project: nil)

    return SettingEditorSheet(
        item: item,
        viewModel: viewModel,
        documentationLoader: .shared
    ) { value, target in
        saved = true
    }
}

#Preview("Number Editor") {
    @Previewable @State var saved = false

    let item = SettingItem(
        key: "editor.fontSize",
        value: .int(14),
        source: .globalSettings,
        contributions: [SourceContribution(source: .globalSettings, value: .int(14))]
    )

    let viewModel = SettingsViewModel(project: nil)

    return SettingEditorSheet(
        item: item,
        viewModel: viewModel,
        documentationLoader: .shared
    ) { value, target in
        saved = true
    }
}

#Preview("Array Editor") {
    @Previewable @State var saved = false

    let item = SettingItem(
        key: "files.exclude",
        value: .array([.string("node_modules"), .string(".git")]),
        source: .globalSettings,
        contributions: [
            SourceContribution(source: .globalSettings, value: .array([.string("node_modules"), .string(".git")])),
        ]
    )

    let viewModel = SettingsViewModel(project: nil)

    return SettingEditorSheet(
        item: item,
        viewModel: viewModel,
        documentationLoader: .shared
    ) { value, target in
        saved = true
    }
}

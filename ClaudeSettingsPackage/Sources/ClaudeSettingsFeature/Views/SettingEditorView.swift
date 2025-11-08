import SwiftUI

/// View for editing a setting value with type-aware controls
struct SettingEditorView: View {
    let item: SettingItem
    let documentation: SettingDocumentation?
    @Binding var editedValue: SettingValue?
    @State private var textValue: String = ""
    @State private var boolValue: Bool = false
    @State private var intValue: String = ""
    @State private var doubleValue: String = ""
    @State private var jsonText: String = ""
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Edit Value")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            editor
                .onAppear {
                    initializeEditState()
                }

            if let error = validationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch item.value {
        case .string:
            if let enumValues = documentation?.enumValues, !enumValues.isEmpty {
                // Show menu/picker for enum values
                enumEditor(values: enumValues)
            } else {
                // Show text field for string values
                stringEditor
            }
        case .bool:
            boolEditor
        case .int:
            intEditor
        case .double:
            doubleEditor
        case .array,
             .object:
            jsonEditor
        case .null:
            Text("null (cannot edit)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stringEditor: some View {
        TextField("Value", text: $textValue)
            .textFieldStyle(.roundedBorder)
            .onChange(of: textValue) { _, newValue in
                editedValue = .string(newValue)
                validationError = nil
            }
    }

    @ViewBuilder
    private func enumEditor(values: [String]) -> some View {
        Menu {
            ForEach(values, id: \.self) { value in
                Button(value) {
                    textValue = value
                    editedValue = .string(value)
                    validationError = nil
                }
            }
        } label: {
            HStack {
                Text(textValue.isEmpty ? "Select value..." : textValue)
                    .foregroundStyle(textValue.isEmpty ? .secondary : .primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var boolEditor: some View {
        Toggle(isOn: $boolValue) {
            Text(boolValue ? "true" : "false")
                .font(.system(.body, design: .monospaced))
        }
        .onChange(of: boolValue) { _, newValue in
            editedValue = .bool(newValue)
            validationError = nil
        }
    }

    @ViewBuilder
    private var intEditor: some View {
        TextField("Integer value", text: $intValue)
            .textFieldStyle(.roundedBorder)
            .onChange(of: intValue) { _, newValue in
                if let intVal = Int(newValue) {
                    editedValue = .int(intVal)
                    validationError = nil
                } else if newValue.isEmpty {
                    editedValue = nil
                    validationError = nil
                } else {
                    validationError = "Must be a valid integer"
                    editedValue = nil
                }
            }
    }

    @ViewBuilder
    private var doubleEditor: some View {
        TextField("Decimal value", text: $doubleValue)
            .textFieldStyle(.roundedBorder)
            .onChange(of: doubleValue) { _, newValue in
                if let doubleVal = Double(newValue) {
                    editedValue = .double(doubleVal)
                    validationError = nil
                } else if newValue.isEmpty {
                    editedValue = nil
                    validationError = nil
                } else {
                    validationError = "Must be a valid number"
                    editedValue = nil
                }
            }
    }

    @ViewBuilder
    private var jsonEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: $jsonText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 100, maxHeight: 200)
                .border(Color.secondary.opacity(0.3))
                .onChange(of: jsonText) { _, newValue in
                    validateJSON(newValue)
                }

            Text("Enter valid JSON")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func initializeEditState() {
        switch item.value {
        case let .string(value):
            textValue = value
            editedValue = item.value
        case let .bool(value):
            boolValue = value
            editedValue = item.value
        case let .int(value):
            intValue = "\(value)"
            editedValue = item.value
        case let .double(value):
            doubleValue = "\(value)"
            editedValue = item.value
        case .array,
             .object:
            jsonText = formatJSON(item.value)
            editedValue = item.value
        case .null:
            editedValue = item.value
        }
    }

    private func validateJSON(_ text: String) {
        guard !text.isEmpty else {
            editedValue = nil
            validationError = nil
            return
        }

        do {
            guard let data = text.data(using: .utf8) else {
                validationError = "Invalid text encoding"
                editedValue = nil
                return
            }

            let jsonObject = try JSONSerialization.jsonObject(with: data)

            // Convert to SettingValue
            if let array = jsonObject as? [Any] {
                editedValue = .array(array.map { SettingValue(any: $0) })
                validationError = nil
            } else if let dict = jsonObject as? [String: Any] {
                editedValue = .object(dict.mapValues { SettingValue(any: $0) })
                validationError = nil
            } else {
                validationError = "Must be a JSON array or object"
                editedValue = nil
            }
        } catch {
            validationError = "Invalid JSON: \(error.localizedDescription)"
            editedValue = nil
        }
    }

    private func formatJSON(_ value: SettingValue) -> String {
        let nativeValue = value.asAny
        guard let data = try? JSONSerialization.data(withJSONObject: nativeValue, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let string = String(data: data, encoding: .utf8) else {
            return value.formatted()
        }
        return string
    }
}

#Preview("String Editor") {
    @Previewable @State var editedValue: SettingValue?

    let item = SettingItem(
        key: "editor.theme",
        value: .string("dark"),
        source: .globalSettings,
        contributions: [SourceContribution(source: .globalSettings, value: .string("dark"))]
    )

    SettingEditorView(
        item: item,
        documentation: nil,
        editedValue: $editedValue
    )
    .padding()
    .frame(width: 300)
}

#Preview("Boolean Editor") {
    @Previewable @State var editedValue: SettingValue?

    let item = SettingItem(
        key: "editor.autoSave",
        value: .bool(true),
        source: .globalSettings,
        contributions: [SourceContribution(source: .globalSettings, value: .bool(true))]
    )

    SettingEditorView(
        item: item,
        documentation: nil,
        editedValue: $editedValue
    )
    .padding()
    .frame(width: 300)
}

#Preview("Integer Editor") {
    @Previewable @State var editedValue: SettingValue?

    let item = SettingItem(
        key: "editor.fontSize",
        value: .int(14),
        source: .globalSettings,
        contributions: [SourceContribution(source: .globalSettings, value: .int(14))]
    )

    SettingEditorView(
        item: item,
        documentation: nil,
        editedValue: $editedValue
    )
    .padding()
    .frame(width: 300)
}

#Preview("Enum Editor") {
    @Previewable @State var editedValue: SettingValue?

    let item = SettingItem(
        key: "terminal.shell",
        value: .string("bash"),
        source: .globalSettings,
        contributions: [SourceContribution(source: .globalSettings, value: .string("bash"))]
    )

    let doc = SettingDocumentation(
        key: "terminal.shell",
        type: "string",
        defaultValue: "bash",
        description: "Default shell",
        enumValues: ["bash", "zsh", "fish", "sh"],
        format: nil,
        itemType: nil,
        platformNote: nil,
        relatedEnvVars: nil,
        hookTypes: nil,
        patterns: nil,
        examples: []
    )

    SettingEditorView(
        item: item,
        documentation: doc,
        editedValue: $editedValue
    )
    .padding()
    .frame(width: 300)
}

#Preview("Array Editor") {
    @Previewable @State var editedValue: SettingValue?

    let item = SettingItem(
        key: "files.exclude",
        value: .array([.string("node_modules"), .string(".git")]),
        source: .globalSettings,
        contributions: [SourceContribution(source: .globalSettings, value: .array([.string("node_modules"), .string(".git")]))]
    )

    SettingEditorView(
        item: item,
        documentation: nil,
        editedValue: $editedValue
    )
    .padding()
    .frame(width: 300, height: 300)
}

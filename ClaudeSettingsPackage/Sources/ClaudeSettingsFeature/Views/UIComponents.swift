import SwiftUI

// MARK: - Section Header

/// Standardized section header used throughout the app
struct SectionHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

// MARK: - Type Badge

/// Displays a colored badge for a setting's type
struct TypeBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .cornerRadius(6)
    }

    /// Create from a SettingValue
    init(value: SettingValue) {
        self.text = value.typeDisplayName
        self.color = value.typeDisplayColor
    }

    /// Create from a schema type string
    init(schemaType: String, description: String? = nil) {
        self.text = description ?? schemaType.capitalized
        self.color = schemaTypeColor(schemaType)
    }

    /// Create with explicit text and color
    init(text: String, color: Color) {
        self.text = text
        self.color = color
    }
}

// MARK: - Validation Error View

/// Displays a validation error message with warning icon
struct ValidationErrorView: View {
    let message: String

    var body: some View {
        HStack(spacing: 4) {
            Symbols.exclamationmarkTriangle.image
                .font(.caption2)
            Text(message)
                .font(.caption)
        }
        .foregroundStyle(.red)
    }
}

// MARK: - Example Code Block

/// Displays a code example with description
struct ExampleCodeBlock: View {
    let example: SettingExample

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(example.description)
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(example.code)
                .font(.callout.monospaced())
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(4)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Metadata Row

/// Displays a label: value pair for setting metadata
struct MetadataRow: View {
    let label: String
    let value: String
    var monospaced = true

    var body: some View {
        HStack {
            Text("\(label):")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .callout.monospaced() : .callout)
        }
    }
}

// MARK: - Platform Note View

/// Displays a platform-specific note with warning styling
struct PlatformNoteView: View {
    let note: String

    var body: some View {
        HStack {
            Symbols.exclamationmarkCircle.image
                .font(.caption2)
            Text(note)
                .font(.caption)
        }
        .foregroundStyle(.orange)
    }
}

// MARK: - Bulleted List View

/// Displays a bulleted list of items
struct BulletedListView: View {
    let title: String
    let items: [String]
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(items, id: \.self) { item in
                Text("• \(item)")
                    .font(monospaced ? .callout.monospaced() : .callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Deprecation Warning

/// Displays a deprecation warning banner
struct DeprecationWarning: View {
    var body: some View {
        HStack(spacing: 6) {
            Symbols.exclamationmarkTriangle.image
                .foregroundStyle(.red)
            Text("DEPRECATED")
                .font(.headline)
                .foregroundStyle(.red)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .cornerRadius(6)
    }
}

// MARK: - Value Editors

/// Toggle editor for boolean values with optional true/false label
struct BooleanToggleEditor: View {
    @Binding var value: Bool
    var showLabel = true

    var body: some View {
        Toggle(isOn: $value) {
            if showLabel {
                Text(value ? "true" : "false")
                    .font(.system(.body, design: .monospaced))
            } else {
                EmptyView()
            }
        }
        .toggleStyle(.switch)
    }
}

/// Text field editor for string values
struct StringTextFieldEditor: View {
    let placeholder: String
    @Binding var text: String
    var hasError = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(hasError ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
            )
    }
}

/// Picker editor for enum/selection values
struct EnumPickerEditor: View {
    let values: [String]
    @Binding var selection: String

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(values, id: \.self) { value in
                Text(value).tag(value)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }
}

/// Text field editor for number values (integer or double)
struct NumberTextFieldEditor: View {
    let placeholder: String
    @Binding var text: String
    var hasError = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(hasError ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
            )
    }
}

/// Text editor for JSON values (arrays and objects)
struct JSONTextEditor: View {
    @Binding var text: String
    var hasError = false
    var minHeight: CGFloat = 100

    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: minHeight)
            .border(hasError ? Color.red.opacity(0.5) : Color.secondary.opacity(0.3))
    }
}

// MARK: - Previews

#Preview("Section Headers") {
    VStack(alignment: .leading, spacing: 16) {
        SectionHeader(text: "Documentation")
        SectionHeader(text: "Value")
        SectionHeader(text: "Examples")
    }
    .padding()
}

#Preview("Type Badges") {
    VStack(spacing: 8) {
        TypeBadge(schemaType: "string", description: "String")
        TypeBadge(schemaType: "boolean", description: "Boolean")
        TypeBadge(schemaType: "integer", description: "Integer")
        TypeBadge(schemaType: "array", description: "Array<String>")
        TypeBadge(schemaType: "object", description: "Object")
    }
    .padding()
}

#Preview("Validation Error") {
    ValidationErrorView(message: "Must be a valid integer")
        .padding()
}

#Preview("Metadata Rows") {
    VStack(alignment: .leading, spacing: 8) {
        MetadataRow(label: "Type", value: "string")
        MetadataRow(label: "Default", value: "auto")
        MetadataRow(label: "Note", value: "Platform specific", monospaced: false)
    }
    .padding()
}

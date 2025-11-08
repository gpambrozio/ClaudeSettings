import SwiftUI

/// Sheet for copying a setting to another file
struct CopySettingSheet: View {
    let item: SettingItem
    let viewModel: SettingsViewModel
    let onCopy: (SettingsFileType) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTargetFile: SettingsFileType = .globalSettings

    var body: some View {
        NavigationStack {
            Form {
                Section("Setting to Copy") {
                    LabeledContent("Key") {
                        Text(item.key)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    LabeledContent("Value") {
                        Text(item.value.formatted())
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(3)
                    }
                }

                Section("Copy To") {
                    Picker("Target File", selection: $selectedTargetFile) {
                        ForEach(availableTargetFiles, id: \.self) { fileType in
                            VStack(alignment: .leading) {
                                Text(fileTypeLabel(fileType))
                                Text(fileType.filename)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(fileType)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section {
                    Text("The setting will be copied to the selected file. If the key already exists, it will be overwritten.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Copy Setting")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy") {
                        onCopy(selectedTargetFile)
                        dismiss()
                    }
                }
            }
        }
    }

    private var availableTargetFiles: [SettingsFileType] {
        // All writable settings files
        let writableTypes: [SettingsFileType] = [
            .globalSettings,
            .globalLocal,
            .projectSettings,
            .projectLocal,
        ]

        return writableTypes.sorted { $0.precedence < $1.precedence }
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
}

// MARK: - Previews

#Preview("Copy Setting Sheet") {
    let item = SettingItem(
        key: "editor.fontSize",
        value: .int(14),
        source: .globalSettings,
        contributions: [SourceContribution(source: .globalSettings, value: .int(14))]
    )

    let viewModel = SettingsViewModel(project: nil)

    return CopySettingSheet(
        item: item,
        viewModel: viewModel
    ) { targetFile in
        print("Copying to \(targetFile)")
    }
}

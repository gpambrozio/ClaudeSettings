import SwiftUI

/// Inspector view showing details and actions for the selected item
public struct InspectorView: View {
    let selectedKey: String?
    let settingsViewModel: SettingsViewModel?
    @ObservedObject var documentationLoader: DocumentationLoader

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
                            }

                            Text(formatValue(contribution.value))
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .opacity(!item.isAdditive && index < item.contributions.count - 1 ? 0.6 : 1)
                        }
                    }

                    // Documentation section - show comprehensive docs if available
                    if let settingDoc = documentationLoader.documentation(for: item.key) {
                        Divider()

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
                                    Text(settingDoc.typeDescription)
                                        .font(.caption.monospaced())
                                }

                                if let defaultValue = settingDoc.defaultValue {
                                    HStack {
                                        Text("Default:")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(defaultValue)
                                            .font(.caption.monospaced())
                                    }
                                }

                                if let platformNote = settingDoc.platformNote {
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
                            Text(settingDoc.description)
                                .font(.caption)
                                .foregroundStyle(.primary)

                            // Related environment variables
                            if let envVars = settingDoc.relatedEnvVars, !envVars.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Related environment variables:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    ForEach(envVars, id: \.self) { envVar in
                                        Text("• \(envVar)")
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            // Patterns (for permissions)
                            if let patterns = settingDoc.patterns, !patterns.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Pattern syntax:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    ForEach(patterns, id: \.self) { pattern in
                                        Text("• \(pattern)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            // Examples
                            if !settingDoc.examples.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Examples:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    ForEach(settingDoc.examples) { example in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(example.description)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)

                                            Text(example.code)
                                                .font(.caption.monospaced())
                                                .padding(8)
                                                .background(Color.primary.opacity(0.05))
                                                .cornerRadius(4)
                                                .textSelection(.enabled)
                                        }
                                    }
                                }
                            }
                        }
                    } else if let documentation = item.documentation {
                        // Fallback to basic documentation if no comprehensive docs available
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Documentation")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            Text(documentation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Actions section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Actions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        HStack(spacing: 8) {
                            Button("Copy Value") {
                                copyToClipboard(formatValue(item.value))
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)

                            Button("Edit") {
                                // TODO: Implement in Phase 1.5
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)

                            Button("Delete") {
                                // TODO: Implement in Phase 1.5
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .tint(.red)

                            Spacer()
                        }
                    }

                    Spacer()
                }
                .padding()
            }
        } else {
            emptyState
        }
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
            documentation: "This setting is deprecated and will be removed in version 2.0"
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

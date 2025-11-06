import SwiftUI

/// Inspector view showing details and actions for the selected item
public struct InspectorView: View {
    let selectedKey: String?
    let settingsViewModel: SettingsViewModel?

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

                            let typeInfo = getTypeInfo(item.valueType)
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

                    if let documentation = item.documentation {
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

    private func formatValue(_ value: AnyCodable) -> String {
        switch value.value {
        case let string as String:
            return "\"\(string)\""
        case let bool as Bool:
            return bool ? "true" : "false"
        case let int as Int:
            return "\(int)"
        case let double as Double:
            return "\(double)"
        case let array as [Any]:
            return formatArray(array)
        case let dict as [String: Any]:
            return formatDict(dict)
        default:
            return "null"
        }
    }

    private func formatArray(_ array: [Any]) -> String {
        let items = array.prefix(5).map { item -> String in
            if let string = item as? String {
                return "\"\(string)\""
            } else {
                return "\(item)"
            }
        }
        let preview = items.joined(separator: ", ")
        if array.count > 5 {
            return "[\(preview), ... (\(array.count - 5) more)]"
        } else {
            return "[\(preview)]"
        }
    }

    private func formatDict(_ dict: [String: Any]) -> String {
        let keys = dict.keys.prefix(3).sorted()
        let preview = keys.map { "\($0): ..." }.joined(separator: ", ")
        if dict.count > 3 {
            return "{ \(preview), ... (\(dict.count - 3) more) }"
        } else {
            return "{ \(preview) }"
        }
    }

    private func getTypeInfo(_ valueType: SettingValueType) -> (String, Color) {
        switch valueType {
        case .string:
            return ("String", .blue)
        case .boolean:
            return ("Boolean", .green)
        case .number:
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

    public init(selectedKey: String?, settingsViewModel: SettingsViewModel?) {
        self.selectedKey = selectedKey
        self.settingsViewModel = settingsViewModel
    }
}

// MARK: - Previews

#Preview("Inspector - With Selection") {
    let viewModel = SettingsViewModel(project: nil)
    viewModel.settingItems = [
        SettingItem(
            key: "editor.fontSize",
            value: AnyCodable(16),
            valueType: .number,
            source: .globalSettings,
            contributions: [
                SourceContribution(source: .globalSettings, value: AnyCodable(14)),
                SourceContribution(source: .projectLocal, value: AnyCodable(16)),
            ],
            documentation: "Controls the font size of the editor"
        ),
        SettingItem(
            key: "editor.theme",
            value: AnyCodable("dark"),
            valueType: .string,
            source: .projectSettings,
            contributions: [SourceContribution(source: .projectSettings, value: AnyCodable("dark"))]
        ),
    ]

    return InspectorView(selectedKey: "editor.fontSize", settingsViewModel: viewModel)
        .frame(width: 300, height: 600)
}

#Preview("Inspector - Array (Additive)") {
    let viewModel = SettingsViewModel(project: nil)
    viewModel.settingItems = [
        SettingItem(
            key: "files.exclude",
            value: AnyCodable(["node_modules", ".git", "dist", "build"]),
            valueType: .array,
            source: .globalSettings,
            contributions: [
                SourceContribution(source: .globalSettings, value: AnyCodable(["node_modules", ".git"])),
                SourceContribution(source: .projectSettings, value: AnyCodable(["dist"])),
                SourceContribution(source: .projectLocal, value: AnyCodable(["build"])),
            ],
            documentation: "Files and directories to exclude from file operations"
        ),
    ]

    return InspectorView(selectedKey: "files.exclude", settingsViewModel: viewModel)
        .frame(width: 300, height: 600)
}

#Preview("Inspector - Deprecated Setting") {
    let viewModel = SettingsViewModel(project: nil)
    viewModel.settingItems = [
        SettingItem(
            key: "deprecated.setting",
            value: AnyCodable(true),
            valueType: .boolean,
            source: .globalSettings,
            contributions: [SourceContribution(source: .globalSettings, value: AnyCodable(true))],
            isDeprecated: true,
            documentation: "This setting is deprecated and will be removed in version 2.0"
        ),
    ]

    return InspectorView(selectedKey: "deprecated.setting", settingsViewModel: viewModel)
        .frame(width: 300, height: 600)
}

#Preview("Inspector - Object Type") {
    let viewModel = SettingsViewModel(project: nil)
    viewModel.settingItems = [
        SettingItem(
            key: "editor.config",
            value: AnyCodable(["tabSize": 2, "insertSpaces": true, "detectIndentation": false]),
            valueType: .object,
            source: .projectSettings,
            contributions: [
                SourceContribution(
                    source: .projectSettings,
                    value: AnyCodable(["tabSize": 2, "insertSpaces": true, "detectIndentation": false])
                ),
            ],
            documentation: "Editor configuration object"
        ),
    ]

    return InspectorView(selectedKey: "editor.config", settingsViewModel: viewModel)
        .frame(width: 300, height: 600)
}

#Preview("Inspector - Empty State") {
    InspectorView(selectedKey: nil, settingsViewModel: nil)
        .frame(width: 300, height: 600)
}

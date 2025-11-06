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

                    Divider()

                    // Value section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Value")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Text(formatValue(item.value))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    Divider()

                    // Type section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        HStack {
                            let typeInfo = getTypeInfo(item.valueType)
                            Text(typeInfo.0)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(typeInfo.1.opacity(0.2))
                                .foregroundStyle(typeInfo.1)
                                .cornerRadius(6)

                            Spacer()
                        }
                    }

                    Divider()

                    // Source section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Source")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        sourceInfo(for: item)
                    }

                    if item.isAdditive {
                        // Show individual contributions for additive arrays
                        ForEach(Array(item.contributions.enumerated()), id: \.offset) { _, contribution in
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
                                }

                                Text(formatValue(contribution.value))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    } else if let overriddenBy = item.overriddenBy {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Override")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            overrideInfo(type: overriddenBy)
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

                        VStack(spacing: 8) {
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

                Text(item.source.rawValue)
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

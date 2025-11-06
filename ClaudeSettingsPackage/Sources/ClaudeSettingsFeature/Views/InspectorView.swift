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
        if let value = viewModel.mergedSettings[key] {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Key section
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

                    // Value section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Value")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Text(formatValue(value))
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
                            let typeInfo = getTypeInfo(value)
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

                        // TODO: Implement source tracking in Phase 1.4
                        Text("Merged Configuration")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                                copyToClipboard(formatValue(value))
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

    private func getTypeInfo(_ value: AnyCodable) -> (String, Color) {
        switch value.value {
        case is String:
            return ("String", .blue)
        case is Bool:
            return ("Boolean", .green)
        case is Int,
             is Double:
            return ("Number", .orange)
        case is [Any]:
            return ("Array", .purple)
        case is [String: Any]:
            return ("Object", .pink)
        default:
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

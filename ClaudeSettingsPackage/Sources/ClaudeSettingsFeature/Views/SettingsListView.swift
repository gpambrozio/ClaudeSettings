import SwiftUI

/// View displaying the list of settings with their values
public struct SettingsListView: View {
    let settingsViewModel: SettingsViewModel
    @Binding var selectedKey: String?

    public var body: some View {
        Group {
            if settingsViewModel.isLoading {
                ProgressView("Loading settings...")
            } else if let errorMessage = settingsViewModel.errorMessage {
                ContentUnavailableView {
                    Label("Error", symbol: .exclamationmarkTriangle)
                } description: {
                    Text(errorMessage)
                }
            } else if settingsViewModel.mergedSettings.isEmpty {
                ContentUnavailableView {
                    Label("No Settings", symbol: .docText)
                } description: {
                    Text("No settings files found for this configuration")
                }
            } else {
                settingsContent
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add Setting") {
                        // TODO: Implement in Phase 1.5
                    }
                    Button("Import Settings") {
                        // TODO: Implement in Phase 2
                    }
                } label: {
                    Label("Actions", symbol: .ellipsisCircle)
                }
            }
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        List(selection: $selectedKey) {
            Section {
                ForEach(sortedSettingKeys, id: \.self) { key in
                    SettingRow(
                        key: key,
                        value: settingsViewModel.mergedSettings[key]!,
                        isSelected: selectedKey == key
                    )
                    .tag(key)
                }
            } header: {
                HStack {
                    Text("Merged Configuration")
                    Spacer()
                    Text("\(settingsViewModel.mergedSettings.count) settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: .constant(""), prompt: "Search settings...")
    }

    private var sortedSettingKeys: [String] {
        settingsViewModel.mergedSettings.keys.sorted()
    }

    public init(settingsViewModel: SettingsViewModel, selectedKey: Binding<String?>) {
        self.settingsViewModel = settingsViewModel
        self._selectedKey = selectedKey
    }
}

/// Individual row displaying a setting key-value pair
struct SettingRow: View {
    let key: String
    let value: AnyCodable
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(key)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Text(valueDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            valueTypeIndicator
        }
        .padding(.vertical, 4)
    }

    private var valueDescription: String {
        switch value.value {
        case let string as String:
            return string
        case let bool as Bool:
            return bool ? "true" : "false"
        case let int as Int:
            return "\(int)"
        case let double as Double:
            return "\(double)"
        case let array as [Any]:
            return "[\(array.count) items]"
        case let dict as [String: Any]:
            return "{\(dict.count) keys}"
        default:
            return "null"
        }
    }

    @ViewBuilder
    private var valueTypeIndicator: some View {
        let typeInfo = valueTypeInfo
        Text(typeInfo.0)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(typeInfo.1.opacity(0.2))
            .foregroundStyle(typeInfo.1)
            .cornerRadius(4)
    }

    private var valueTypeInfo: (String, Color) {
        switch value.value {
        case is String:
            return ("string", .blue)
        case is Bool:
            return ("bool", .green)
        case is Int,
             is Double:
            return ("number", .orange)
        case is [Any]:
            return ("array", .purple)
        case is [String: Any]:
            return ("object", .pink)
        default:
            return ("null", .gray)
        }
    }
}

import SwiftUI

// MARK: - Shared Action Sheets

/// Reusable sheet for copying or moving a setting to another file
struct SettingCopyMoveSheet: View {
    let settingKey: String
    let mode: CopyMoveMode
    let availableFileTypes: [SettingsFileType]
    let onSelectDestination: (SettingsFileType) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(mode.title)
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 8) {
                Text("Setting Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(settingKey)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Select Destination File")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(availableFileTypes, id: \.self) { fileType in
                    Button(action: {
                        onSelectDestination(fileType)
                    }) {
                        HStack {
                            Circle()
                                .fill(SettingsActionHelpers.sourceColor(for: fileType))
                                .frame(width: 8, height: 8)
                            Text(fileType.displayName)
                            Spacer()
                            Symbols.chevronRight.image
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding()
        .frame(width: 400)
    }
}

/// Reusable sheet for copying or moving a parent node (with source selection)
struct NodeCopyMoveSheet: View {
    let nodeKey: String
    let mode: CopyMoveMode
    let contributingSources: [SettingsFileType]
    let availableFileTypes: [SettingsFileType]
    @Binding var selectedSourceType: SettingsFileType?
    let onConfirm: (SettingsFileType, SettingsFileType) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(mode.title)
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 8) {
                Text("Setting Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(nodeKey)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Select Source File")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(contributingSources, id: \.self) { sourceType in
                    Button(action: {
                        selectedSourceType = sourceType
                    }) {
                        HStack {
                            Circle()
                                .fill(SettingsActionHelpers.sourceColor(for: sourceType))
                                .frame(width: 8, height: 8)
                            Text(sourceType.displayName)
                            Spacer()
                            Symbols.chevronRight.image
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let selectedSource = selectedSourceType {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Destination File")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(availableFileTypes, id: \.self) { destType in
                        Button(action: {
                            onConfirm(selectedSource, destType)
                        }) {
                            HStack {
                                Circle()
                                    .fill(SettingsActionHelpers.sourceColor(for: destType))
                                    .frame(width: 8, height: 8)
                                Text(destType.displayName)
                                Spacer()
                                Symbols.chevronRight.image
                                    .font(.caption)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - Shared Types

enum CopyMoveMode {
    case copy
    case move

    var title: String {
        switch self {
        case .copy: return "Copy Setting"
        case .move: return "Move Setting"
        }
    }
}

// MARK: - Helper Functions

enum SettingsActionHelpers {
    /// Returns the list of writable file types available for operations
    static func availableFileTypes(for viewModel: SettingsViewModel) -> [SettingsFileType] {
        var types: [SettingsFileType] = []

        // Global files (always available)
        types.append(.globalSettings)
        types.append(.globalLocal)

        // Project files (only if there's a project)
        if viewModel.settingItems.contains(where: { !$0.source.isGlobal }) {
            types.append(.projectSettings)
            types.append(.projectLocal)
        }

        // Filter out read-only files
        return types.filter { type in
            if let file = viewModel.settingsFiles.first(where: { $0.type == type }) {
                return !file.isReadOnly
            }
            return true // Can create new files
        }
    }

    /// Checks if a file type is read-only
    static func isReadOnly(fileType: SettingsFileType, in viewModel: SettingsViewModel) -> Bool {
        if let file = viewModel.settingsFiles.first(where: { $0.type == fileType }) {
            return file.isReadOnly
        }
        return false
    }

    /// Returns the color associated with a settings file type
    static func sourceColor(for type: SettingsFileType) -> Color {
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

    /// Returns all file types that contribute to a parent node
    static func contributingFileTypes(for key: String, in viewModel: SettingsViewModel) -> [SettingsFileType] {
        let childSettings = viewModel.settingItems.filter { $0.key.hasPrefix(key + ".") || $0.key == key }
        let fileTypes = Set(childSettings.flatMap { $0.contributions.map(\.source) })
        return Array(fileTypes).sorted { $0.displayName < $1.displayName }
    }
}

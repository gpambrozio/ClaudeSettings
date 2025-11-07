import SwiftUI

/// Displays documentation information for a settings item
struct DocumentationSectionView: View {
    let settingItem: SettingItem
    @ObservedObject var documentationLoader: DocumentationLoader

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text("Documentation")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if documentationLoader.isLoading {
                loadingState
            } else if let settingDoc = documentationLoader.documentationWithFallback(for: settingItem.key) {
                comprehensiveDocumentation(settingDoc)
            } else if let documentation = settingItem.documentation {
                basicDocumentation(documentation)
            }
        }
    }

    // MARK: - Comprehensive Documentation

    @ViewBuilder
    private func comprehensiveDocumentation(_ settingDoc: SettingDocumentation) -> some View {
        // Type and default value
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Type:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(settingDoc.typeDescription)
                    .font(.callout.monospaced())
            }

            if let defaultValue = settingDoc.defaultValue {
                HStack {
                    Text("Default:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(defaultValue)
                        .font(.callout.monospaced())
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
            .font(.body)
            .foregroundStyle(.primary)

        // Related environment variables
        if let envVars = settingDoc.relatedEnvVars, !envVars.isEmpty {
            environmentVariablesSection(envVars)
        }

        // Patterns (for permissions)
        if let patterns = settingDoc.patterns, !patterns.isEmpty {
            patternsSection(patterns)
        }

        // Examples
        if !settingDoc.examples.isEmpty {
            examplesSection(settingDoc.examples)
        }
    }

    // MARK: - Documentation Subsections

    @ViewBuilder
    private func environmentVariablesSection(_ envVars: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Related environment variables:")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(envVars, id: \.self) { envVar in
                Text("• \(envVar)")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func patternsSection(_ patterns: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pattern syntax:")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(patterns, id: \.self) { pattern in
                Text("• \(pattern)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func examplesSection(_ examples: [SettingExample]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Examples:")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(examples) { example in
                VStack(alignment: .leading, spacing: 4) {
                    Text(example.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text(example.code)
                        .font(.callout.monospaced())
                        .padding(8)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(4)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Basic Documentation

    @ViewBuilder
    private func basicDocumentation(_ documentation: String) -> some View {
        Text(documentation)
            .font(.body)
            .foregroundStyle(.secondary)
    }

    // MARK: - Loading State

    @ViewBuilder
    private var loadingState: some View {
        HStack {
            ProgressView()
                .controlSize(.small)
            Text("Loading documentation...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Previews

#Preview("Documentation - Comprehensive") {
    let loader = DocumentationLoader.shared
    let settingItem = SettingItem(
        key: "permissions.allow",
        value: .array([.string("Bash(git:*)")]),
        source: .globalSettings,
        contributions: [SourceContribution(source: .globalSettings, value: .array([.string("Bash(git:*)")]))],
        documentation: "Controls which tools and commands are allowed"
    )

    return DocumentationSectionView(settingItem: settingItem, documentationLoader: loader)
        .padding()
        .frame(width: 300)
}

#Preview("Documentation - Basic Fallback") {
    let loader = DocumentationLoader.shared
    let settingItem = SettingItem(
        key: "unknown.setting",
        value: .bool(true),
        source: .globalSettings,
        contributions: [SourceContribution(source: .globalSettings, value: .bool(true))],
        documentation: "This is some basic documentation without comprehensive details"
    )

    return DocumentationSectionView(settingItem: settingItem, documentationLoader: loader)
        .padding()
        .frame(width: 300)
}

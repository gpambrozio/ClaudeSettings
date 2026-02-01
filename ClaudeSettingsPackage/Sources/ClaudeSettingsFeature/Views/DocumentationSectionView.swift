import SwiftUI

/// Displays documentation information for a setting
struct DocumentationSectionView: View {
    let documentation: SettingDocumentation
    let isDeprecated: Bool
    let showHeader: Bool
    let maxExamples: Int?

    /// Initialize with a SettingDocumentation directly
    init(
        documentation: SettingDocumentation,
        isDeprecated: Bool = false,
        showHeader: Bool = true,
        maxExamples: Int? = nil
    ) {
        self.documentation = documentation
        self.isDeprecated = isDeprecated
        self.showHeader = showHeader
        self.maxExamples = maxExamples
    }

    /// Convenience initializer for use with SettingItem and DocumentationLoader
    init(
        settingItem: SettingItem,
        documentationLoader: DocumentationLoader,
        showHeader: Bool = true,
        maxExamples: Int? = nil
    ) {
        // Try to get documentation, fall back to a minimal version if not found
        if let doc = documentationLoader.documentationWithFallback(for: settingItem.key) {
            self.documentation = doc
        } else {
            // Create minimal documentation from the setting item
            self.documentation = SettingDocumentation(
                key: settingItem.key,
                type: settingItem.value.typeName,
                defaultValue: nil,
                description: "No documentation available for this setting.",
                deprecated: nil,
                enumValues: nil,
                format: nil,
                itemType: nil,
                platformNote: nil,
                relatedEnvVars: nil,
                hookTypes: nil,
                patterns: nil,
                examples: []
            )
        }
        self.isDeprecated = documentationLoader.isDeprecated(settingItem.key)
        self.showHeader = showHeader
        self.maxExamples = maxExamples
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showHeader {
                SectionHeader(text: "Documentation")
            }

            if isDeprecated {
                DeprecationWarning()
            }

            documentationContent
        }
    }

    // MARK: - Documentation Content

    @ViewBuilder
    private var documentationContent: some View {
        // Type and default value
        VStack(alignment: .leading, spacing: 4) {
            MetadataRow(label: "Type", value: documentation.typeDescription)

            if let defaultValue = documentation.defaultValue {
                MetadataRow(label: "Default", value: defaultValue)
            }

            if let platformNote = documentation.platformNote {
                PlatformNoteView(note: platformNote)
            }
        }

        // Description
        Text(documentation.description)
            .font(.body)
            .foregroundStyle(.primary)

        // Hook types (specific to hooks setting)
        if let hookTypes = documentation.hookTypes, !hookTypes.isEmpty {
            BulletedListView(
                title: "Available hook types:",
                items: Array(hookTypes.keys).sorted(),
                monospaced: true
            )
        }

        // Related environment variables
        if let envVars = documentation.relatedEnvVars, !envVars.isEmpty {
            BulletedListView(
                title: "Related environment variables:",
                items: envVars,
                monospaced: true
            )
        }

        // Patterns (for permissions)
        if let patterns = documentation.patterns, !patterns.isEmpty {
            BulletedListView(
                title: "Pattern syntax:",
                items: patterns,
                monospaced: false
            )
        }

        // Examples
        if !documentation.examples.isEmpty {
            examplesSection
        }
    }

    // MARK: - Examples Section

    @ViewBuilder
    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(text: "Examples")

            let examplesToShow = maxExamples.map { Array(documentation.examples.prefix($0)) }
                ?? Array(documentation.examples)

            ForEach(examplesToShow) { example in
                ExampleCodeBlock(example: example)
            }
        }
    }
}

// MARK: - Previews

#Preview("Documentation - Comprehensive") {
    DocumentationSectionView(
        documentation: SettingDocumentation(
            key: "permissions.allow",
            type: "array",
            defaultValue: "[]",
            description: "Specifies which tools Claude can use without asking for confirmation.",
            deprecated: nil,
            enumValues: nil,
            format: nil,
            itemType: "string",
            platformNote: "Some tools may not be available on all platforms",
            relatedEnvVars: ["CLAUDE_ALLOWED_TOOLS"],
            hookTypes: nil,
            patterns: ["Tool(pattern:*)", "Tool(*)", "Tool"],
            examples: [
                SettingExample(
                    id: UUID(),
                    code: "\"permissions\": { \"allow\": [\"Bash(git:*)\"] }",
                    description: "Allow all git commands"
                ),
                SettingExample(
                    id: UUID(),
                    code: "\"permissions\": { \"allow\": [\"Read\", \"Write\"] }",
                    description: "Allow file operations"
                ),
            ]
        )
    )
    .padding()
    .frame(width: 350)
}

#Preview("Documentation - Deprecated") {
    DocumentationSectionView(
        documentation: SettingDocumentation(
            key: "oldSetting",
            type: "boolean",
            defaultValue: "false",
            description: "This setting is deprecated and will be removed.",
            deprecated: true,
            enumValues: nil,
            format: nil,
            itemType: nil,
            platformNote: nil,
            relatedEnvVars: nil,
            hookTypes: nil,
            patterns: nil,
            examples: []
        ),
        isDeprecated: true
    )
    .padding()
    .frame(width: 350)
}

#Preview("Documentation - Limited Examples") {
    DocumentationSectionView(
        documentation: SettingDocumentation(
            key: "theme",
            type: "string",
            defaultValue: "auto",
            description: "Controls the color theme of the interface.",
            deprecated: nil,
            enumValues: ["dark", "light", "auto"],
            format: nil,
            itemType: nil,
            platformNote: nil,
            relatedEnvVars: nil,
            hookTypes: nil,
            patterns: nil,
            examples: [
                SettingExample(id: UUID(), code: "\"theme\": \"dark\"", description: "Dark mode"),
                SettingExample(id: UUID(), code: "\"theme\": \"light\"", description: "Light mode"),
                SettingExample(id: UUID(), code: "\"theme\": \"auto\"", description: "System default"),
            ]
        ),
        maxExamples: 2
    )
    .padding()
    .frame(width: 350)
}

#Preview("Documentation - No Header") {
    DocumentationSectionView(
        documentation: SettingDocumentation(
            key: "setting",
            type: "string",
            defaultValue: nil,
            description: "A simple setting without much documentation.",
            deprecated: nil,
            enumValues: nil,
            format: nil,
            itemType: nil,
            platformNote: nil,
            relatedEnvVars: nil,
            hookTypes: nil,
            patterns: nil,
            examples: []
        ),
        showHeader: false
    )
    .padding()
    .frame(width: 350)
}

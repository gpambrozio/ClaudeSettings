import AppKit
import SwiftUI

/// Inspector view showing details and actions for the selected item
public struct InspectorView: View {
    let selectedKey: String?
    let settingsViewModel: SettingsViewModel?
    @ObservedObject var documentationLoader: DocumentationLoader
    let availableProjects: [ClaudeProject]

    @State private var actionState = SettingActionState()
    @State private var marketplaceToMove: KnownMarketplace?

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
        // Check if it's a marketplace key
        if key.hasPrefix("marketplace:") {
            let name = String(key.dropFirst("marketplace:".count))
            if let marketplace = viewModel.marketplaceViewModel.marketplace(named: name) {
                marketplaceDetails(marketplace: marketplace, viewModel: viewModel)
            } else if let edit = viewModel.marketplaceViewModel.pendingMarketplaceEdits[name] {
                newMarketplaceDetails(edit: edit, viewModel: viewModel)
            } else {
                emptyState
            }
        }
        // Regular settings
        else if let item = viewModel.settingItems.first(where: { $0.key == key }) {
            // Leaf node with actual setting value
            leafNodeDetails(item: item)
        } else if let doc = documentationLoader.documentation(for: key) {
            // Parent node with documentation
            parentNodeDetails(key: key, documentation: doc)
        } else {
            // Parent node without documentation
            parentNodeWithoutDocumentation(key: key, viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func leafNodeDetails(item: SettingItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Key section
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(text: "Key")

                    HStack {
                        Text(item.key)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)

                        TypeBadge(value: item.value)

                        if documentationLoader.isDeprecated(item.key) {
                            Symbols.exclamationmarkTriangle.image
                                .foregroundStyle(.red)
                                .font(.body)
                        }

                        if !item.isActive {
                            Symbols.exclamationmarkTriangle.image
                                .foregroundStyle(.yellow)
                                .font(.caption)
                        }
                    }
                }

                // CLI-managed key warning (when viewing in global settings)
                if let viewModel = settingsViewModel, !viewModel.isProjectView && isCliManagedKey(item.key) {
                    cliManagedKeyWarning(for: item.key)
                }

                // Show all source contributions
                ForEach(Array(item.contributions.enumerated()), id: \.offset) { index, contribution in
                    Divider()

                    contributionRow(
                        contribution: contribution,
                        item: item,
                        index: index,
                        isOverridden: !item.isAdditive && index < item.contributions.count - 1
                    )
                }

                // Documentation section
                if documentationLoader.documentationWithFallback(for: item.key) != nil {
                    Divider()

                    DocumentationSectionView(
                        settingItem: item,
                        documentationLoader: documentationLoader
                    )
                }

                Divider()

                // Actions section
                if let viewModel = settingsViewModel {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(text: "Actions")

                        HStack(spacing: 20) {
                            Button(action: {
                                copyToClipboard(formatValue(item.value))
                            }) {
                                Text("Copy Value")
                                    .padding(.horizontal, 10)
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isEditingMode)

                            Spacer()
                        }

                        HStack(spacing: 20) {
                            Button(action: {
                                actionState.showCopySheet = true
                            }) {
                                Text("Copy to...")
                                    .padding(.horizontal, 10)
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isEditingMode)

                            Button(action: {
                                actionState.showMoveSheet = true
                            }) {
                                Text("Move to...")
                                    .padding(.horizontal, 10)
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isEditingMode)

                            Spacer()
                        }

                        Button(action: {
                            actionState.showDeleteConfirmation = true
                        }) {
                            Text("Delete")
                                .padding(.horizontal, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(viewModel.isEditingMode)
                    }
                }

                Spacer()
            }
            .padding()
            .ifLet(settingsViewModel) { view, viewModel in
                view.settingItemActions(
                    item: item,
                    viewModel: viewModel,
                    actionState: actionState
                )
            }
        }
    }

    // MARK: - Contribution Row

    @ViewBuilder
    private func contributionRow(
        contribution: SourceContribution,
        item: SettingItem,
        index: Int,
        isOverridden: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Get pending edit if it exists
            let pendingEdit = settingsViewModel?.getPendingEditOrCreate(for: item)
            // Show editor for the original contribution (where the setting came from)
            // This ensures the editor is visible even when the target file has no contribution yet
            let isEditingThisContribution = (settingsViewModel?.isEditingMode ?? false) &&
                pendingEdit?.originalFileType == contribution.source

            // Header: either file type selector (when editing) or label
            if isEditingThisContribution {
                contributionHeaderEditing(item: item, pendingEdit: pendingEdit)
            } else {
                contributionHeaderNormal(contribution: contribution, isOverridden: isOverridden)
            }

            // Value: either editor (when editing) or static text
            if isEditingThisContribution, let pendingEdit = pendingEdit {
                typeAwareEditor(for: pendingEdit.value, item: item, pendingEdit: pendingEdit)
                    .padding(.top, 4)
            } else {
                Text(formatValue(contribution.value))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .opacity(isOverridden ? 0.6 : 1)
            }
        }
    }

    @ViewBuilder
    private func contributionHeaderEditing(item: SettingItem, pendingEdit: PendingEdit?) -> some View {
        if let viewModel = settingsViewModel {
            Menu {
                ForEach(SettingsActionHelpers.availableFileTypes(for: viewModel), id: \.self) { fileType in
                    Button(action: {
                        // Update the target file type for this pending edit
                        // Find the value from this file's contribution, or use current edited value
                        let newValue: SettingValue
                        if let contribution = item.contributions.first(where: { $0.source == fileType }) {
                            newValue = contribution.value
                        } else {
                            newValue = pendingEdit?.value ?? item.value
                        }
                        viewModel.updatePendingEditIfChanged(item: item, value: newValue, targetFileType: fileType)
                    }) {
                        HStack {
                            Text(fileType.displayName)
                            if pendingEdit?.targetFileType == fileType {
                                Symbols.checkmarkCircle.image
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Circle()
                        .fill(SettingsActionHelpers.sourceColor(for: pendingEdit?.targetFileType ?? .globalSettings))
                        .frame(width: 8, height: 8)
                    Text(pendingEdit?.targetFileType.displayName ?? "Select file")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Symbols.chevronUpChevronDown.image
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func contributionHeaderNormal(contribution: SourceContribution, isOverridden: Bool) -> some View {
        HStack {
            Circle()
                .fill(SettingsActionHelpers.sourceColor(for: contribution.source))
                .frame(width: 8, height: 8)
            Text(sourceLabel(for: contribution.source))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if isOverridden {
                Text("(overridden)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }

    @ViewBuilder
    private func parentNodeDetails(key: String, documentation: SettingDocumentation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Key section for parent node
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(text: "Key")

                    HStack {
                        Text(key)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)

                        TypeBadge(schemaType: documentation.type, description: documentation.typeDescription)
                    }
                }

                // CLI-managed key warning (when viewing in global settings)
                if let viewModel = settingsViewModel, !viewModel.isProjectView && isCliManagedKey(key) {
                    cliManagedKeyWarning(for: key)
                }

                Divider()

                // Documentation section - reuses DocumentationSectionView
                DocumentationSectionView(
                    documentation: documentation,
                    isDeprecated: documentation.deprecated == true
                )

                // Actions section
                if let viewModel = settingsViewModel {
                    let contributingSources = SettingsActionHelpers.contributingFileTypes(for: key, in: viewModel)

                    if !contributingSources.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(text: "Actions")

                            HStack(spacing: 20) {
                                Button(action: {
                                    actionState.showCopySheet = true
                                }) {
                                    Text("Copy to...")
                                        .padding(.horizontal, 10)
                                }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.isEditingMode)

                                Button(action: {
                                    actionState.showMoveSheet = true
                                }) {
                                    Text("Move to...")
                                        .padding(.horizontal, 10)
                                }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.isEditingMode)

                                Spacer()
                            }

                            Button(action: {
                                actionState.showDeleteConfirmation = true
                            }) {
                                Text("Delete")
                                    .padding(.horizontal, 10)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .disabled(viewModel.isEditingMode)
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        .modifier(OptionalParentNodeActionsModifier(
            nodeKey: selectedKey,
            viewModel: settingsViewModel,
            actionState: actionState
        ))
    }

    @ViewBuilder
    private func parentNodeWithoutDocumentation(key: String, viewModel: SettingsViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Key section for parent node
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(text: "Key")

                    Text(key)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                // CLI-managed key warning (when viewing in global settings)
                if !viewModel.isProjectView && isCliManagedKey(key) {
                    cliManagedKeyWarning(for: key)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(text: "Parent Setting")

                    Text("This is a parent setting that contains \(childCount(for: key, in: viewModel)) child settings.")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Text("Select a child setting to view its details, or expand this node to see all children.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                // Actions section
                let contributingSources = SettingsActionHelpers.contributingFileTypes(for: key, in: viewModel)

                if !contributingSources.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(text: "Actions")

                        HStack(spacing: 20) {
                            Button(action: {
                                actionState.showCopySheet = true
                            }) {
                                Text("Copy to...")
                                    .padding(.horizontal, 10)
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isEditingMode)

                            Button(action: {
                                actionState.showMoveSheet = true
                            }) {
                                Text("Move to...")
                                    .padding(.horizontal, 10)
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isEditingMode)

                            Spacer()
                        }

                        Button(action: {
                            actionState.showDeleteConfirmation = true
                        }) {
                            Text("Delete")
                                .padding(.horizontal, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(viewModel.isEditingMode)
                    }
                }

                Spacer()
            }
            .padding()
        }
        .parentNodeActions(
            nodeKey: key,
            viewModel: viewModel,
            actionState: actionState
        )
    }

    private func childCount(for key: String, in viewModel: SettingsViewModel) -> Int {
        viewModel.settingItems.filter { $0.key.hasPrefix(key + ".") }.count
    }

    // MARK: - CLI-Managed Key Warning

    /// Check if a key is CLI-managed (marketplaces/plugins that should be in dedicated JSON files)
    private func isCliManagedKey(_ key: String) -> Bool {
        key == "extraKnownMarketplaces" || key.hasPrefix("extraKnownMarketplaces.") ||
            key == "enabledPlugins" || key.hasPrefix("enabledPlugins.")
    }

    @ViewBuilder
    private func cliManagedKeyWarning(for key: String) -> some View {
        let isMarketplace = key == "extraKnownMarketplaces" || key.hasPrefix("extraKnownMarketplaces.")
        let isPlugin = key == "enabledPlugins" || key.hasPrefix("enabledPlugins.")

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Symbols.exclamationmarkCircle.image
                    .foregroundStyle(.orange)
                    .font(.caption)

                Text("Global Setting — CLI Managed")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
            }

            if isMarketplace {
                Text("Global marketplaces should be managed by the Claude CLI, not in settings.json. The CLI stores them in ~/.claude/plugins/known_marketplaces.json.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("Use `claude plugin marketplace add` to add global marketplaces. Project-specific marketplaces can still be added to project settings.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .italic()
            } else if isPlugin {
                Text("Global plugins should be managed by the Claude CLI, not in settings.json. The CLI stores them in ~/.claude/plugins/installed_plugins.json.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("Use `claude plugin install` to install global plugins. Project-specific plugins can still be added to project settings.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Marketplace Helpers

    @ViewBuilder
    private func marketplaceDataSourceBadge(_ dataSource: MarketplaceDataSource) -> some View {
        let (color, icon): (Color, Symbols) = switch dataSource {
        case .global:
            (.blue, .arrowDownCircle)
        case .project:
            (.orange, .gearshape)
        case .both:
            (.green, .checkmarkCircle)
        }

        icon.image
            .foregroundStyle(color)
            .font(.caption)
    }

    private func sourceLabel(for type: SettingsFileType) -> String {
        SettingsActionHelpers.sourceLabel(for: type)
    }

    // MARK: - Marketplace Details

    @ViewBuilder
    private func marketplaceDetails(marketplace: KnownMarketplace, viewModel: SettingsViewModel) -> some View {
        let marketplaceVM = viewModel.marketplaceViewModel
        let isEditing = marketplaceVM.isEditingMode
        let isDeleted = marketplaceVM.isMarkedForDeletion(marketplace: marketplace.name)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(text: "Marketplace")

                    HStack {
                        Text(marketplace.name)
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.semibold)
                            .strikethrough(isDeleted)
                            .foregroundStyle(isDeleted ? .red : .primary)
                            .textSelection(.enabled)

                        Spacer()

                        marketplaceDataSourceBadge(marketplace.dataSource)
                    }
                }

                Divider()

                // Source Configuration
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(text: "Source")

                    if isEditing && !isDeleted {
                        marketplaceEditForm(for: marketplace, viewModel: viewModel)
                    } else {
                        marketplaceReadOnlyInfo(marketplace: marketplace, viewModel: viewModel)
                    }
                }

                // Plugin Management (dual toggles)
                Divider()
                pluginManagementSection(for: marketplace, viewModel: viewModel)

                // Marketplace Actions
                if isEditing && !isDeleted {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(text: "Marketplace Actions")

                        Button("Delete Marketplace", role: .destructive) {
                            // Also mark all plugins from this marketplace for deletion
                            let plugins = marketplaceVM.plugins(from: marketplace.name)
                            for plugin in plugins {
                                marketplaceVM.deletePlugin(id: plugin.id)
                            }
                            marketplaceVM.deleteMarketplace(named: marketplace.name)
                        }
                        .buttonStyle(.bordered)

                        Text("Deleting the marketplace will also remove all installed plugins from it.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if isDeleted {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(text: "Marketplace Actions")

                        Button("Restore Marketplace") {
                            // Also restore all plugins from this marketplace
                            let plugins = marketplaceVM.plugins(from: marketplace.name)
                            for plugin in plugins {
                                marketplaceVM.restorePlugin(id: plugin.id)
                            }
                            marketplaceVM.restoreMarketplace(named: marketplace.name)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Scope Management
                if !isEditing && !isDeleted {
                    // Global or both marketplace → Copy to Project
                    if (marketplace.dataSource == .global || marketplace.dataSource == .both) && !availableProjects.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(text: "Scope")

                            Text("This marketplace is installed globally. Copy it to a project to share the configuration via git.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button("Copy to Project...") {
                                marketplaceToMove = marketplace
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    // Project marketplace → Make Global
                    if marketplace.dataSource == .project {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(text: "Scope")

                            Text("This marketplace is project-only. Make it global to install on your machine.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button("Make Global") {
                                Task { @MainActor in
                                    do {
                                        try await marketplaceVM.promoteMarketplaceToGlobal(
                                            marketplace: marketplace,
                                            settingsViewModel: viewModel
                                        )
                                    } catch {
                                        viewModel.errorMessage = "Failed to promote marketplace: \(error.localizedDescription)"
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        .task(id: marketplace.name) {
            // Auto-load available plugins when marketplace details are shown
            if await marketplaceVM.effectiveInstallLocation(for: marketplace) != nil {
                await marketplaceVM.loadAvailablePlugins(for: marketplace)
            }
        }
        // Sheet: Pick project for Copy to Project
        // Using sheet(item:) to avoid race condition with state
        .sheet(item: $marketplaceToMove) { marketplace in
            CopyMarketplaceToProjectSheet(
                marketplace: marketplace,
                projects: availableProjects,
                marketplaceViewModel: marketplaceVM,
                onComplete: {
                    marketplaceToMove = nil
                }
            )
        }
    }

    @ViewBuilder
    private func marketplaceReadOnlyInfo(marketplace: KnownMarketplace, viewModel: SettingsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Type", value: marketplace.source.source)

            if let repo = marketplace.source.repo {
                LabeledContent("Repository", value: repo)
            }

            if let path = marketplace.source.path {
                LabeledContent("Path", value: path)
            }

            if let ref = marketplace.source.ref {
                LabeledContent("Branch/Tag", value: ref)
            }

            if let location = marketplace.installLocation {
                LabeledContent("Install Location", value: location)
            }

            if let lastUpdated = marketplace.lastUpdated {
                LabeledContent("Last Updated") {
                    Text(lastUpdated, style: .relative)
                }
            }
        }
        .font(.caption)
    }

    // MARK: - Dual-Toggle Plugin Management

    /// Dual-toggle plugin management section
    /// Shows "Installed" toggle (always) and "In Project" toggle (when in project view)
    /// Note: Each row uses PluginToggleRowView which properly observes @Observable changes
    @ViewBuilder
    private func pluginManagementSection(for marketplace: KnownMarketplace, viewModel: SettingsViewModel) -> some View {
        let marketplaceVM = viewModel.marketplaceViewModel
        let plugins = marketplaceVM.allPlugins(from: marketplace.name, enabledPluginKeys: [])

        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(text: "Plugins (\(plugins.count))")

            if plugins.isEmpty {
                Text("No plugins found for this marketplace")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                // Column headers
                pluginToggleHeaders(showProjectColumn: viewModel.isProjectView)

                ForEach(plugins, id: \.id) { plugin in
                    pluginToggleRow(
                        plugin: plugin,
                        marketplaceVM: marketplaceVM,
                        settingsVM: viewModel
                    )
                }

                // Help text
                Text("Global = install on your machine. Project = declare in settings (Shared is git-committed, Local is not).")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
    }

    /// Column headers for the dual-toggle table
    @ViewBuilder
    private func pluginToggleHeaders(showProjectColumn: Bool) -> some View {
        HStack {
            Text("Plugin")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Spacer()

            Text("Global")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
                .textCase(.uppercase)
                .frame(width: 70)

            if showProjectColumn {
                Text("Project")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                    .textCase(.uppercase)
                    .frame(width: 70)
            }
        }
        .padding(.bottom, 4)
    }

    /// A single row with plugin name, description, global toggle, and project picker
    /// Now uses a dedicated View struct for proper @Observable observation
    @ViewBuilder
    private func pluginToggleRow(
        plugin: InstalledPlugin,
        marketplaceVM: MarketplaceViewModel,
        settingsVM: SettingsViewModel
    ) -> some View {
        PluginToggleRowView(
            pluginId: plugin.id,
            pluginName: plugin.name,
            pluginMarketplace: plugin.marketplace,
            marketplaceVM: marketplaceVM,
            settingsVM: settingsVM
        )
    }

    /// Get the label for the project location picker
    private func projectLocationLabel(isInProject: Bool, location: ProjectFileLocation?) -> String {
        guard isInProject else { return "None" }
        switch location {
        case .shared:
            return "Shared"
        case .local:
            return "Local"
        case nil:
            return "Project"
        }
    }

    @ViewBuilder
    private func marketplaceEditForm(for marketplace: KnownMarketplace, viewModel: SettingsViewModel) -> some View {
        let marketplaceVM = viewModel.marketplaceViewModel
        let edit = marketplaceVM.pendingEdit(for: marketplace)

        VStack(alignment: .leading, spacing: 12) {
            // Source Type Picker
            Picker("Type", selection: Binding(
                get: { edit.sourceType },
                set: { newValue in
                    var updated = edit
                    updated.sourceType = newValue
                    marketplaceVM.updatePendingEdit(updated, for: marketplace.name)
                }
            )) {
                Text("GitHub").tag("github")
                Text("Directory").tag("directory")
            }
            .pickerStyle(.segmented)

            // GitHub fields
            if edit.sourceType == "github" {
                TextField("Repository (org/repo)", text: Binding(
                    get: { edit.repo },
                    set: { newValue in
                        var updated = edit
                        updated.repo = newValue
                        marketplaceVM.updatePendingEdit(updated, for: marketplace.name)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

                TextField("Branch/Tag (optional)", text: Binding(
                    get: { edit.ref },
                    set: { newValue in
                        var updated = edit
                        updated.ref = newValue
                        marketplaceVM.updatePendingEdit(updated, for: marketplace.name)
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }

            // Directory fields
            if edit.sourceType == "directory" {
                TextField("Path", text: Binding(
                    get: { edit.path },
                    set: { newValue in
                        var updated = edit
                        updated.path = newValue
                        marketplaceVM.updatePendingEdit(updated, for: marketplace.name)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            }

            // Validation error
            if let error = edit.validationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func newMarketplaceDetails(edit: MarketplacePendingEdit, viewModel: SettingsViewModel) -> some View {
        let marketplaceVM = viewModel.marketplaceViewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(text: "New Marketplace")

                    TextField("Name", text: Binding(
                        get: { edit.name },
                        set: { newValue in
                            var updated = edit
                            // Remove old key, add new one
                            marketplaceVM.pendingMarketplaceEdits.removeValue(forKey: edit.name)
                            updated.name = newValue
                            marketplaceVM.pendingMarketplaceEdits[newValue] = updated
                        }
                    ))
                    .font(.system(.title2, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                }

                Divider()

                // Source Configuration
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(text: "Source")

                    // Source Type Picker
                    Picker("Type", selection: Binding(
                        get: { edit.sourceType },
                        set: { newValue in
                            var updated = edit
                            updated.sourceType = newValue
                            marketplaceVM.pendingMarketplaceEdits[edit.name] = updated
                        }
                    )) {
                        Text("GitHub").tag("github")
                        Text("Directory").tag("directory")
                    }
                    .pickerStyle(.segmented)

                    // GitHub fields
                    if edit.sourceType == "github" {
                        TextField("Repository (org/repo)", text: Binding(
                            get: { edit.repo },
                            set: { newValue in
                                var updated = edit
                                updated.repo = newValue
                                marketplaceVM.pendingMarketplaceEdits[edit.name] = updated
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                        TextField("Branch/Tag (optional)", text: Binding(
                            get: { edit.ref },
                            set: { newValue in
                                var updated = edit
                                updated.ref = newValue
                                marketplaceVM.pendingMarketplaceEdits[edit.name] = updated
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    // Directory fields
                    if edit.sourceType == "directory" {
                        TextField("Path", text: Binding(
                            get: { edit.path },
                            set: { newValue in
                                var updated = edit
                                updated.path = newValue
                                marketplaceVM.pendingMarketplaceEdits[edit.name] = updated
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    }

                    // Validation error
                    if let error = edit.validationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Spacer()
            }
            .padding()
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

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Type-Aware Editor

    @ViewBuilder
    private func typeAwareEditor(for value: SettingValue, item: SettingItem, pendingEdit: PendingEdit) -> some View {
        if let viewModel = settingsViewModel {
            switch value {
            case let .bool(boolValue):
                BooleanToggleEditor(
                    value: Binding(
                        get: { if case let .bool(val) = pendingEdit.value { return val } else { return boolValue } },
                        set: { viewModel.updatePendingEditIfChanged(item: item, value: .bool($0), targetFileType: pendingEdit.targetFileType) }
                    ),
                    showLabel: false
                )

            case let .string(stringValue):
                // Check if documentation has enum values
                if
                    let doc = documentationLoader.documentationWithFallback(for: item.key),
                    let enumValues = doc.enumValues, !enumValues.isEmpty {
                    // Use picker for enum values (standardized across the app)
                    EnumPickerEditor(
                        values: enumValues,
                        selection: Binding(
                            get: { if case let .string(val) = pendingEdit.value { return val } else { return stringValue } },
                            set: { viewModel.updatePendingEditIfChanged(item: item, value: .string($0), targetFileType: pendingEdit.targetFileType) }
                        )
                    )
                } else {
                    // Regular text field
                    StringTextFieldEditor(
                        placeholder: "Value",
                        text: Binding(
                            get: { if case let .string(val) = pendingEdit.value { return val } else { return stringValue } },
                            set: { viewModel.updatePendingEditIfChanged(item: item, value: .string($0), targetFileType: pendingEdit.targetFileType) }
                        )
                    )
                }

            case .int:
                NumberTextFieldView(
                    item: item,
                    pendingEdit: pendingEdit,
                    viewModel: viewModel,
                    numberType: .integer
                )

            case .double:
                NumberTextFieldView(
                    item: item,
                    pendingEdit: pendingEdit,
                    viewModel: viewModel,
                    numberType: .double
                )

            case .array,
                 .object:
                // For complex types, use a text editor with JSON
                JSONTextEditorView(
                    item: item,
                    pendingEdit: pendingEdit,
                    viewModel: viewModel
                )

            case .null:
                Text("null")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    public init(
        selectedKey: String?,
        settingsViewModel: SettingsViewModel?,
        documentationLoader: DocumentationLoader = .shared,
        availableProjects: [ClaudeProject] = []
    ) {
        self.selectedKey = selectedKey
        self.settingsViewModel = settingsViewModel
        self.documentationLoader = documentationLoader
        self.availableProjects = availableProjects
    }
}

// MARK: - Move Marketplace to Project Sheet

/// Row for displaying a project in the picker (supports multi-select)
private struct ProjectPickerRow: View {
    let project: ClaudeProject
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Checkbox
                Group {
                    if isSelected {
                        Symbols.checkmarkCircleFill.image
                            .foregroundStyle(.tint)
                    } else {
                        Symbols.circle.image
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.title3)

                // Project info
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(project.path.path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Sheet for selecting which project(s) to copy a marketplace to
private struct CopyMarketplaceToProjectSheet: View {
    let marketplace: KnownMarketplace
    let projects: [ClaudeProject]
    let marketplaceViewModel: MarketplaceViewModel
    let onComplete: () -> Void

    @State private var selectedProjectIDs: Set<UUID> = []
    @State private var includePlugins = true
    @State private var isCopying = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    /// Number of global plugins that will be moved
    private var globalPluginCount: Int {
        marketplaceViewModel.globalPlugins(from: marketplace.name).count
    }

    private var selectedProjects: [ClaudeProject] {
        projects.filter { selectedProjectIDs.contains($0.id) }
    }

    private var confirmButtonTitle: String {
        let count = selectedProjectIDs.count
        if count == 0 {
            return "Copy to Project"
        } else if count == 1 {
            return "Copy to 1 Project"
        } else {
            return "Copy to \(count) Projects"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Copy Marketplace to Project")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Info message
                    HStack(alignment: .top, spacing: 10) {
                        Symbols.infoCircle.image
                            .foregroundStyle(.blue)
                            .font(.title3)
                        Text("This will copy \"\(marketplace.name)\" to the selected project(s). The marketplace will remain in your global registry.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)

                    // Project picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select project(s):")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        ForEach(projects, id: \.id) { project in
                            ProjectPickerRow(
                                project: project,
                                isSelected: selectedProjectIDs.contains(project.id),
                                onToggle: {
                                    if selectedProjectIDs.contains(project.id) {
                                        selectedProjectIDs.remove(project.id)
                                    } else {
                                        selectedProjectIDs.insert(project.id)
                                    }
                                }
                            )
                        }
                    }

                    // Plugin option
                    if globalPluginCount > 0 {
                        Divider()
                            .padding(.vertical, 8)

                        Toggle(isOn: $includePlugins) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Also include installed plugins")
                                    .font(.subheadline)
                                Text("\(globalPluginCount) plugin\(globalPluginCount == 1 ? "" : "s") will be added to selected project(s)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }

            Divider()

            // Footer - always visible
            HStack {
                if isCopying {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, 8)
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(confirmButtonTitle) {
                    copyToProjects()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedProjectIDs.isEmpty || isCopying)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 550)
    }

    private func copyToProjects() {
        guard !selectedProjects.isEmpty else { return }

        isCopying = true
        errorMessage = nil

        Task { @MainActor in
            do {
                // Copy marketplace config to each selected project
                for project in selectedProjects {
                    let targetViewModel = SettingsViewModel(project: project)
                    await targetViewModel.loadSettings()

                    try await marketplaceViewModel.copyMarketplaceToProject(
                        marketplace: marketplace,
                        settingsViewModel: targetViewModel,
                        includePlugins: includePlugins
                    )
                }

                onComplete()
            } catch {
                errorMessage = error.localizedDescription
                isCopying = false
            }
        }
    }
}

// MARK: - Plugin Toggle Row View

/// A dedicated View struct for plugin toggle rows that properly observes @Observable
/// This is necessary because SwiftUI's observation tracking doesn't work correctly
/// with helper functions - it needs a proper View struct to establish the observation context.
private struct PluginToggleRowView: View {
    let pluginId: String
    let pluginName: String
    let pluginMarketplace: String
    let marketplaceVM: MarketplaceViewModel
    let settingsVM: SettingsViewModel

    var body: some View {
        // Look up current state from viewmodel - this creates proper observation
        // because we're accessing the @Observable property inside a View's body
        let currentPlugin = marketplaceVM.plugins.first { $0.id == pluginId }
        let isInstalled = currentPlugin.map { $0.dataSource == .global || $0.dataSource == .both } ?? false
        let isInProject = currentPlugin.map { $0.dataSource == .project || $0.dataSource == .both } ?? false
        let projectLocation = currentPlugin?.projectFileLocation

        // Look up description from available plugins cache
        let availablePlugin = marketplaceVM.availablePlugins(for: pluginMarketplace)
            .first { $0.name == pluginName }
        let description = availablePlugin?.description

        HStack(alignment: .top, spacing: 8) {
            Symbols.puzzlepiece.image
                .foregroundStyle(.secondary)
                .font(.caption)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(pluginName)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .textSelection(.enabled)

                if let description {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                } else {
                    Text("No description available")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                        .italic()
                }
            }

            Spacer()

            // Global toggle - controls installed_plugins.json
            Toggle("", isOn: Binding(
                get: { isInstalled },
                set: { newValue in
                    Task { @MainActor in
                        do {
                            if newValue {
                                try await marketplaceVM.installPluginGlobally(
                                    name: pluginName,
                                    marketplace: pluginMarketplace
                                )
                            } else {
                                try await marketplaceVM.uninstallPluginGlobally(pluginId: pluginId)
                            }
                        } catch {
                            settingsVM.errorMessage = "Failed to update plugin: \(error.localizedDescription)"
                        }
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 70)
            .help("Global: Install on your machine")

            // Project picker - only visible in project view
            if settingsVM.isProjectView {
                Menu {
                    Button {
                        Task { @MainActor in
                            do {
                                try await marketplaceVM.removePluginFromProject(
                                    name: pluginName,
                                    marketplace: pluginMarketplace,
                                    settingsViewModel: settingsVM
                                )
                            } catch {
                                settingsVM.errorMessage = "Failed to update plugin: \(error.localizedDescription)"
                            }
                        }
                    } label: {
                        HStack {
                            Text("None")
                            if !isInProject {
                                Symbols.checkmarkCircle.image
                            }
                        }
                    }

                    Divider()

                    Button {
                        Task { @MainActor in
                            do {
                                try await marketplaceVM.addPluginToProject(
                                    name: pluginName,
                                    marketplace: pluginMarketplace,
                                    location: .shared,
                                    settingsViewModel: settingsVM
                                )
                            } catch {
                                settingsVM.errorMessage = "Failed to update plugin: \(error.localizedDescription)"
                            }
                        }
                    } label: {
                        HStack {
                            Text("Shared")
                            Text("(git-committed)")
                                .foregroundStyle(.secondary)
                            if isInProject && projectLocation == .shared {
                                Symbols.checkmarkCircle.image
                            }
                        }
                    }

                    Button {
                        Task { @MainActor in
                            do {
                                try await marketplaceVM.addPluginToProject(
                                    name: pluginName,
                                    marketplace: pluginMarketplace,
                                    location: .local,
                                    settingsViewModel: settingsVM
                                )
                            } catch {
                                settingsVM.errorMessage = "Failed to update plugin: \(error.localizedDescription)"
                            }
                        }
                    } label: {
                        HStack {
                            Text("Local")
                            Text("(not shared)")
                                .foregroundStyle(.secondary)
                            if isInProject && projectLocation == .local {
                                Symbols.checkmarkCircle.image
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(projectLocationLabel)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .frame(width: 45, alignment: .trailing)
                        Symbols.chevronUpChevronDown.image
                            .font(.caption2)
                    }
                    .foregroundStyle(isInProject ? .orange : .secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 70)
                .help("Project: Declare in this project's settings")
            }
        }
        .padding(.vertical, 4)
    }

    /// Computed property for project location label
    private var projectLocationLabel: String {
        let currentPlugin = marketplaceVM.plugins.first { $0.id == pluginId }
        let isInProject = currentPlugin.map { $0.dataSource == .project || $0.dataSource == .both } ?? false
        let location = currentPlugin?.projectFileLocation

        guard isInProject else { return "None" }
        switch location {
        case .shared:
            return "Shared"
        case .local:
            return "Local"
        case nil:
            return "Project"
        }
    }
}

// MARK: - JSON Text Editor Helper

/// Helper view for editing JSON with local state to prevent cursor jumping
private struct JSONTextEditorView: View {
    let item: SettingItem
    let pendingEdit: PendingEdit
    let viewModel: SettingsViewModel

    @State private var localText = ""
    @State private var localValidationError: String?
    @State private var isUpdatingFromExternal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            JSONTextEditor(text: $localText, hasError: localValidationError != nil)
                .onChange(of: localText) { _, newText in
                    // Only validate if this isn't an external update
                    guard !isUpdatingFromExternal else { return }
                    validateAndUpdate(newText)
                }
                .onAppear {
                    // Initialize local text from pending edit
                    localText = pendingEdit.rawEditingText ?? pendingEdit.value.formatted()
                    localValidationError = pendingEdit.validationError
                }
                .onChange(of: pendingEdit.rawEditingText) { _, newRawText in
                    // Sync external changes (like switching target file)
                    // Guard against cycles: only update if different from current local text
                    let newText = newRawText ?? pendingEdit.value.formatted()
                    guard newText != localText else { return }

                    isUpdatingFromExternal = true
                    localText = newText
                    isUpdatingFromExternal = false
                }
                .onChange(of: pendingEdit.validationError) { oldValue, newError in
                    // Only update if actually changed to avoid unnecessary updates
                    guard oldValue != newError else { return }
                    localValidationError = newError
                }

            if let validationError = localValidationError {
                ValidationErrorView(message: validationError)
            }
        }
    }

    private func validateAndUpdate(_ newText: String) {
        let result = validateJSONInput(newText)

        if let value = result.value {
            viewModel.updatePendingEditIfChanged(
                item: item,
                value: value,
                targetFileType: pendingEdit.targetFileType,
                validationError: nil,
                rawEditingText: newText
            )
            localValidationError = nil
        } else {
            viewModel.updatePendingEdit(
                key: item.key,
                value: pendingEdit.value, // Keep old value
                targetFileType: pendingEdit.targetFileType,
                originalFileType: pendingEdit.originalFileType,
                validationError: result.error,
                rawEditingText: newText
            )
            localValidationError = result.error
        }
    }
}

// MARK: - Number TextField View

private struct NumberTextFieldView: View {
    let item: SettingItem
    let pendingEdit: PendingEdit
    let viewModel: SettingsViewModel
    let numberType: NumberType

    enum NumberType {
        case integer
        case double
    }

    @State private var localText = ""
    @State private var localValidationError: String?
    @State private var isUpdatingFromExternal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            NumberTextFieldEditor(
                placeholder: numberType == .integer ? "Enter integer" : "Enter number",
                text: $localText,
                hasError: localValidationError != nil
            )
            .onChange(of: localText) { _, newText in
                guard !isUpdatingFromExternal else { return }
                validateAndUpdate(newText)
            }
            .onAppear {
                localText = pendingEdit.rawEditingText ?? pendingEdit.value.formatted()
                localValidationError = pendingEdit.validationError
            }
            .onChange(of: pendingEdit.rawEditingText) { _, newRawText in
                let newText = newRawText ?? pendingEdit.value.formatted()
                guard newText != localText else { return }

                isUpdatingFromExternal = true
                localText = newText
                isUpdatingFromExternal = false
            }
            .onChange(of: pendingEdit.validationError) { oldValue, newError in
                guard oldValue != newError else { return }
                localValidationError = newError
            }

            if let validationError = localValidationError {
                ValidationErrorView(message: validationError)
            }
        }
    }

    private func validateAndUpdate(_ newText: String) {
        let trimmedText = newText.trimmingCharacters(in: .whitespaces)

        // Validate based on number type using shared validation functions
        switch numberType {
        case .integer:
            let result = validateIntegerInput(trimmedText)
            if let value = result.value {
                viewModel.updatePendingEditIfChanged(
                    item: item,
                    value: .int(value),
                    targetFileType: pendingEdit.targetFileType,
                    validationError: nil,
                    rawEditingText: trimmedText
                )
                localValidationError = nil
            } else {
                viewModel.updatePendingEdit(
                    key: item.key,
                    value: pendingEdit.value,
                    targetFileType: pendingEdit.targetFileType,
                    originalFileType: pendingEdit.originalFileType,
                    validationError: result.error,
                    rawEditingText: trimmedText
                )
                localValidationError = result.error
            }

        case .double:
            let result = validateDoubleInput(trimmedText)
            if let value = result.value {
                viewModel.updatePendingEditIfChanged(
                    item: item,
                    value: .double(value),
                    targetFileType: pendingEdit.targetFileType,
                    validationError: nil,
                    rawEditingText: trimmedText
                )
                localValidationError = nil
            } else {
                viewModel.updatePendingEdit(
                    key: item.key,
                    value: pendingEdit.value,
                    targetFileType: pendingEdit.targetFileType,
                    originalFileType: pendingEdit.originalFileType,
                    validationError: result.error,
                    rawEditingText: trimmedText
                )
                localValidationError = result.error
            }
        }
    }
}

// MARK: - NSTextView Extension for Smart Quotes

/// Disable smart quotes and dashes app-wide for JSON/code editing
extension NSTextView {
    open override var frame: CGRect {
        didSet {
            isAutomaticQuoteSubstitutionEnabled = false
            isAutomaticDashSubstitutionEnabled = false
            isAutomaticTextReplacementEnabled = false
        }
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
            ]
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
            ]
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
            contributions: [SourceContribution(source: .globalSettings, value: .bool(true))]
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
            ]
        ),
    ]

    let viewModel = SettingsViewModel(project: nil)
    viewModel.settingItems = settingItems

    return InspectorView(selectedKey: "editor.config", settingsViewModel: viewModel)
        .frame(width: 300, height: 600)
}

#Preview("Inspector - Editing Boolean") {
    @Previewable var settingItems: [SettingItem] = [
        SettingItem(
            key: "editor.formatOnSave",
            value: .bool(true),
            source: .globalSettings,
            contributions: [
                SourceContribution(source: .globalSettings, value: .bool(false)),
                SourceContribution(source: .projectLocal, value: .bool(true)),
            ]
        ),
    ]

    let viewModel = SettingsViewModel(project: nil)
    viewModel.settingItems = settingItems

    // Start editing mode and create pending edit
    viewModel.isEditingMode = true
    viewModel.pendingEdits["editor.formatOnSave"] = PendingEdit(
        key: "editor.formatOnSave",
        value: .bool(true),
        targetFileType: .projectLocal,
        originalFileType: .globalSettings
    )

    return InspectorView(
        selectedKey: "editor.formatOnSave",
        settingsViewModel: viewModel
    )
    .frame(width: 500, height: 600)
}

#Preview("Inspector - Empty State") {
    InspectorView(selectedKey: nil, settingsViewModel: nil)
        .frame(width: 300, height: 600)
}

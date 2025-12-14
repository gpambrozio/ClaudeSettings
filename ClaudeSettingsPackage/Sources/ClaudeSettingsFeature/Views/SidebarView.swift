import AppKit
import SwiftUI

/// Represents different selections in the sidebar
public enum SidebarSelection: Hashable, Identifiable {
    case globalSettings
    case project(ClaudeProject)

    public var id: String {
        switch self {
        case .globalSettings:
            return "global"
        case let .project(project):
            return project.id.uuidString
        }
    }
}

/// Sidebar view showing global settings and project list
public struct SidebarView: View {
    @Bindable var viewModel: ProjectListViewModel
    @Binding var selection: SidebarSelection?
    let searchText: String
    @State private var droppedSetting: DraggableSetting?
    @State private var targetProject: ClaudeProject?
    @State private var showFileTypeDialog = false
    @State private var showErrorAlert = false
    @State private var errorMessage: String?

    // Global config drop state
    @State private var droppedGlobalSetting: DraggableSetting?
    @State private var showGlobalFileTypeDialog = false

    /// Whether we're actively searching (non-empty search text)
    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Normalized search text for matching
    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Projects filtered by search text (shows projects with matching project-specific settings)
    private var filteredProjects: [ClaudeProject] {
        guard isSearching else {
            return viewModel.projects
        }

        return viewModel.projects.filter { project in
            projectHasMatchingSettings(project, searchText: normalizedSearchText)
        }
    }

    /// Check if global settings should be shown based on search text
    private var shouldShowGlobalSettings: Bool {
        guard isSearching else {
            return true
        }
        return globalSettingsMatchSearch(searchText: normalizedSearchText)
    }

    public var body: some View {
        List(selection: $selection) {
            // Global Settings Section (hide if searching and no match)
            if shouldShowGlobalSettings {
                Section("Global Settings") {
                    GlobalConfigRow(
                        droppedSetting: $droppedGlobalSetting,
                        showFileTypeDialog: $showGlobalFileTypeDialog
                    )
                }
            }

            // Projects Section
            Section {
                if filteredProjects.isEmpty {
                    if isSearching {
                        ContentUnavailableView {
                            Label("No Matching Projects", symbol: .magnifyingglass)
                        } description: {
                            Text("No projects have settings matching \"\(searchText)\"")
                        }
                    } else if viewModel.projects.isEmpty {
                        ContentUnavailableView {
                            Label("No Projects", symbol: .folder)
                        } description: {
                            Text("No Claude projects found")
                        } actions: {
                            Button("Scan for Projects") {
                                viewModel.scanProjects()
                            }
                        }
                    }
                } else {
                    ForEach(filteredProjects) { project in
                        ProjectRow(
                            project: project,
                            selection: $selection,
                            droppedSetting: $droppedSetting,
                            targetProject: $targetProject,
                            showFileTypeDialog: $showFileTypeDialog
                        )
                    }
                }
            } header: {
                HStack {
                    if isSearching {
                        Text("Projects (\(filteredProjects.count) of \(viewModel.projects.count))")
                    } else {
                        Text("Projects (\(viewModel.projects.count))")
                    }
                    Spacer()
                    Button(action: { viewModel.refresh() }) {
                        Symbols.plusCircle.image
                            .imageScale(.small)
                    }
                    .buttonStyle(.plain)
                    .help("Scan for projects")
                }
            }
        }
        .navigationTitle("Claude Settings")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { viewModel.refresh() }) {
                    Label("Refresh", symbol: .gearshape)
                }
            }
        }
        .task {
            if viewModel.projects.isEmpty {
                viewModel.scanProjects()
            }
        }
        .alert(alertTitle, isPresented: $showFileTypeDialog) {
            Button("Project File (.claude/settings.json)") {
                copySettingToProject(fileType: .projectSettings)
            }
            Button("Local File (.claude/settings.local.json)") {
                copySettingToProject(fileType: .projectLocal)
            }
            Button("Cancel", role: .cancel) {
                droppedSetting = nil
                targetProject = nil
            }
        } message: {
            if let setting = droppedSetting, let project = targetProject {
                Text(alertMessage(setting: setting, project: project))
            }
        }
        .alert("Copy Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .alert(globalAlertTitle, isPresented: $showGlobalFileTypeDialog) {
            Button("Global File (~/.claude/settings.json)") {
                copySettingToGlobal(fileType: .globalSettings)
            }
            Button("Local File (~/.claude/settings.local.json)") {
                copySettingToGlobal(fileType: .globalLocal)
            }
            Button("Cancel", role: .cancel) {
                droppedGlobalSetting = nil
            }
        } message: {
            if let setting = droppedGlobalSetting {
                Text(globalAlertMessage(setting: setting))
            }
        }
    }

    private var alertTitle: String {
        guard let setting = droppedSetting else { return "Copy to Project" }
        return setting.isCollection ? "Copy Settings to Project" : "Copy Setting to Project"
    }

    private func alertMessage(setting: DraggableSetting, project: ClaudeProject) -> String {
        if setting.isCollection {
            return "Where would you like to copy \(setting.settings.count) settings to '\(project.name)'?"
        } else {
            return "Where would you like to copy '\(setting.key)' to '\(project.name)'?"
        }
    }

    private var globalAlertTitle: String {
        guard let setting = droppedGlobalSetting else { return "Copy to Global Configuration" }
        return setting.isCollection ? "Copy Settings to Global Configuration" : "Copy Setting to Global Configuration"
    }

    private func globalAlertMessage(setting: DraggableSetting) -> String {
        if setting.isCollection {
            return "Where would you like to copy \(setting.settings.count) settings to Global Configuration?"
        } else {
            return "Where would you like to copy '\(setting.key)' to Global Configuration?"
        }
    }

    private func copySettingToGlobal(fileType: SettingsFileType) {
        guard let setting = droppedGlobalSetting else {
            return
        }

        Task {
            do {
                try await SettingsCopyHelper.copySettingToGlobal(
                    setting: setting,
                    fileType: fileType
                )
                droppedGlobalSetting = nil
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to copy setting(s): \(error.localizedDescription)"
                    showErrorAlert = true
                    droppedGlobalSetting = nil
                }
            }
        }
    }

    private func copySettingToProject(fileType: SettingsFileType) {
        guard
            let setting = droppedSetting,
            let project = targetProject else {
            return
        }

        Task {
            do {
                try await SettingsCopyHelper.copySetting(
                    setting: setting,
                    to: project,
                    fileType: fileType
                )
                droppedSetting = nil
                targetProject = nil
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to copy setting(s): \(error.localizedDescription)"
                    showErrorAlert = true
                    droppedSetting = nil
                    targetProject = nil
                }
            }
        }
    }

    /// Check if a project has project-specific settings (not global) matching the search text
    private func projectHasMatchingSettings(_ project: ClaudeProject, searchText: String) -> Bool {
        // Check project settings file (.claude/settings.json)
        let projectSettingsPath = project.claudeDirectory.appendingPathComponent("settings.json")
        if fileContainsSearchText(at: projectSettingsPath, searchText: searchText) {
            return true
        }

        // Check local project settings file (.claude/settings.local.json)
        let projectLocalPath = project.claudeDirectory.appendingPathComponent("settings.local.json")
        if fileContainsSearchText(at: projectLocalPath, searchText: searchText) {
            return true
        }

        return false
    }

    /// Check if global settings contain the search text
    private func globalSettingsMatchSearch(searchText: String) -> Bool {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let claudeDir = homeDirectory.appendingPathComponent(".claude")

        // Check global settings file (~/.claude/settings.json)
        let globalSettingsPath = claudeDir.appendingPathComponent("settings.json")
        if fileContainsSearchText(at: globalSettingsPath, searchText: searchText) {
            return true
        }

        // Check local global settings file (~/.claude/settings.local.json)
        let globalLocalPath = claudeDir.appendingPathComponent("settings.local.json")
        if fileContainsSearchText(at: globalLocalPath, searchText: searchText) {
            return true
        }

        return false
    }

    /// Check if a file at the given path contains the search text (case-insensitive)
    private func fileContainsSearchText(at url: URL, searchText: String) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8).lowercased()
            return content.contains(searchText)
        } catch {
            return false
        }
    }

    public init(viewModel: ProjectListViewModel, selection: Binding<SidebarSelection?>, searchText: String = "") {
        self.viewModel = viewModel
        self._selection = selection
        self.searchText = searchText
    }
}

/// Individual project row with drag and drop support
struct ProjectRow: View {
    let project: ClaudeProject
    @Binding var selection: SidebarSelection?
    @Binding var droppedSetting: DraggableSetting?
    @Binding var targetProject: ClaudeProject?
    @Binding var showFileTypeDialog: Bool
    @State private var isDropTargeted = false

    var body: some View {
        NavigationLink(value: SidebarSelection.project(project)) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.headline)

                    HStack(spacing: 8) {
                        if project.hasSharedSettings {
                            Text("project")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                        if project.hasLocalSettings {
                            Text("local")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Spacer()
            }
            .padding(.vertical, 2)
        }
        .background(isDropTargeted ? Color.accentColor.opacity(0.2) : Color.clear)
        .contextMenu {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([project.path])
            } label: {
                Label("Reveal in Finder", symbol: .macwindow)
            }
        }
        .dropDestination(for: DraggableSetting.self) { items, _ in
            if let setting = items.first {
                droppedSetting = setting
                targetProject = project
                showFileTypeDialog = true
                return true
            }
            return false
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
    }
}

/// Global configuration row with drag and drop support
struct GlobalConfigRow: View {
    @Binding var droppedSetting: DraggableSetting?
    @Binding var showFileTypeDialog: Bool
    @State private var isDropTargeted = false

    var body: some View {
        NavigationLink(value: SidebarSelection.globalSettings) {
            Label {
                Text("Global Configuration")
            } icon: {
                Symbols.globe.image
                    .foregroundStyle(.blue)
            }
        }
        .background(isDropTargeted ? Color.accentColor.opacity(0.2) : Color.clear)
        .dropDestination(for: DraggableSetting.self) { items, _ in
            if let setting = items.first {
                droppedSetting = setting
                showFileTypeDialog = true
                return true
            }
            return false
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
    }
}

#Preview("Sidebar - With Projects") {
    @Previewable @State var selection: SidebarSelection? = .globalSettings
    let viewModel = ProjectListViewModel()
    viewModel.projects = [
        ClaudeProject(
            name: "My iOS App",
            path: URL(fileURLWithPath: "/Users/developer/Projects/MyApp"),
            claudeDirectory: URL(fileURLWithPath: "/Users/developer/Projects/MyApp/.claude"),
            hasLocalSettings: true,
            hasSharedSettings: true
        ),
        ClaudeProject(
            name: "Backend Service",
            path: URL(fileURLWithPath: "/Users/developer/Projects/Backend"),
            claudeDirectory: URL(fileURLWithPath: "/Users/developer/Projects/Backend/.claude"),
            hasLocalSettings: false,
            hasSharedSettings: true
        ),
        ClaudeProject(
            name: "Web Dashboard",
            path: URL(fileURLWithPath: "/Users/developer/Projects/Dashboard"),
            claudeDirectory: URL(fileURLWithPath: "/Users/developer/Projects/Dashboard/.claude"),
            hasLocalSettings: true,
            hasSharedSettings: false
        ),
    ]

    return NavigationSplitView {
        SidebarView(viewModel: viewModel, selection: $selection)
    } detail: {
        Text("Detail View")
    }
    .frame(width: 800, height: 600)
}

#Preview("Sidebar - Empty State") {
    @Previewable @State var selection: SidebarSelection?
    let viewModel = ProjectListViewModel()
    viewModel.projects = []

    return NavigationSplitView {
        SidebarView(viewModel: viewModel, selection: $selection)
    } detail: {
        Text("Detail View")
    }
    .frame(width: 800, height: 600)
}

#Preview("Sidebar - Loading State") {
    @Previewable @State var selection: SidebarSelection?
    let viewModel = ProjectListViewModel()
    viewModel.projects = []
    viewModel.isLoading = true

    return NavigationSplitView {
        SidebarView(viewModel: viewModel, selection: $selection)
    } detail: {
        Text("Detail View")
    }
    .frame(width: 800, height: 600)
}

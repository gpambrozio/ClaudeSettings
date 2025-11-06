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

    public var body: some View {
        List(selection: $selection) {
            // Global Settings Section
            Section("Global Settings") {
                NavigationLink(value: SidebarSelection.globalSettings) {
                    Label {
                        Text("Global Configuration")
                    } icon: {
                        Symbols.globe.image
                            .foregroundStyle(.blue)
                    }
                }
            }

            // Projects Section
            Section {
                if viewModel.projects.isEmpty {
                    ContentUnavailableView {
                        Label("No Projects", symbol: .folder)
                    } description: {
                        Text("No Claude projects found")
                    } actions: {
                        Button("Scan for Projects") {
                            viewModel.scanProjects()
                        }
                    }
                } else {
                    ForEach(viewModel.projects) { project in
                        NavigationLink(value: SidebarSelection.project(project)) {
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
                            .padding(.vertical, 2)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Projects (\(viewModel.projects.count))")
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
    }

    public init(viewModel: ProjectListViewModel, selection: Binding<SidebarSelection?>) {
        self.viewModel = viewModel
        self._selection = selection
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

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

                                Text(project.path.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                HStack(spacing: 8) {
                                    if project.hasSharedSettings {
                                        Label("settings.json", symbol: .docText)
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                    }
                                    if project.hasLocalSettings {
                                        Label("local", symbol: .docText)
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

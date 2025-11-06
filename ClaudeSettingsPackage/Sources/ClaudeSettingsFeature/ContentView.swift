import SwiftUI

public struct ContentView: View {
    @State private var viewModel = ProjectListViewModel()

    public var body: some View {
        NavigationSplitView {
            // Sidebar with projects
            List(viewModel.projects) { project in
                NavigationLink(value: project) {
                    VStack(alignment: .leading) {
                        Text(project.name)
                            .font(.headline)
                        Text(project.path.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Claude Projects")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") {
                        viewModel.refresh()
                    }
                }
            }
        } detail: {
            if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView {
                    Label {
                        Text("Error")
                    } icon: {
                        Symbols.exclamationmarkTriangle.image
                    }
                } description: {
                    Text(errorMessage)
                }
            } else if viewModel.isLoading {
                ProgressView("Loading projects...")
            } else if viewModel.projects.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("No Projects")
                    } icon: {
                        Symbols.folder.image
                    }
                } description: {
                    Text("No Claude projects found")
                } actions: {
                    Button("Scan for Projects") {
                        viewModel.scanProjects()
                    }
                }
            } else {
                ContentUnavailableView {
                    Label {
                        Text("Select a Project")
                    } icon: {
                        Symbols.sidebarLeft.image
                    }
                } description: {
                    Text("Choose a project from the sidebar")
                }
            }
        }
        .task {
            viewModel.scanProjects()
        }
    }

    public init() { }
}

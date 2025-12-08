import SwiftUI

public struct ContentView: View {
    @State private var projectListViewModel = ProjectListViewModel()
    @State private var sidebarSelection: SidebarSelection?
    @State private var selectedSettingKey: String?
    @State private var settingsViewModel: SettingsViewModel?
    @StateObject private var documentationLoader = DocumentationLoader.shared
    @State private var selectionChangeTask: Task<Void, Never>?
    @State private var searchText = ""

    public var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // Sidebar: Global Settings + Projects
            SidebarView(viewModel: projectListViewModel, selection: $sidebarSelection, searchText: searchText)
        } content: {
            // Content Area: Settings List
            Group {
                if let viewModel = settingsViewModel {
                    SettingsListView(settingsViewModel: viewModel, selectedKey: $selectedSettingKey, searchText: $searchText)
                } else {
                    emptyContentState
                }
            }
            .searchable(text: $searchText, prompt: "Search settings...")
        } detail: {
            // Inspector: Details & Actions
            InspectorView(
                selectedKey: selectedSettingKey,
                settingsViewModel: settingsViewModel,
                documentationLoader: documentationLoader
            )
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            await documentationLoader.load()
        }
        .onChange(of: sidebarSelection) { _, newSelection in
            // Cancel any in-flight selection change to prevent race conditions
            selectionChangeTask?.cancel()

            // onChange requires synchronous callback, so wrap async operation in Task
            selectionChangeTask = Task {
                await handleSelectionChange(newSelection)
            }
        }
    }

    @ViewBuilder
    private var emptyContentState: some View {
        if projectListViewModel.isLoading {
            ProgressView("Loading projects...")
        } else if let errorMessage = projectListViewModel.errorMessage {
            ContentUnavailableView {
                Label("Error", symbol: .exclamationmarkTriangle)
            } description: {
                Text(errorMessage)
            }
        } else {
            ContentUnavailableView {
                Label("Select Configuration", symbol: .sidebarLeft)
            } description: {
                Text("Choose global settings or a project from the sidebar")
            }
        }
    }

    private func handleSelectionChange(_ newSelection: SidebarSelection?) async {
        // Clear selected key when changing selections
        selectedSettingKey = nil

        // Clean up the old view model's file watcher before replacing it
        // Wait for cleanup to complete to avoid race conditions
        if let oldViewModel = settingsViewModel {
            await oldViewModel.stopFileWatcher()
        }

        // Check if task was cancelled during cleanup
        guard !Task.isCancelled else { return }

        // Create and load the appropriate ViewModel
        switch newSelection {
        case .globalSettings:
            let viewModel = SettingsViewModel(project: nil)
            settingsViewModel = viewModel
            await viewModel.loadSettings()
        case let .project(project):
            let viewModel = SettingsViewModel(project: project)
            settingsViewModel = viewModel
            await viewModel.loadSettings()
        case .none:
            settingsViewModel = nil
        }
    }

    public init() { }
}

#Preview("Content View - Default State") {
    ContentView()
        .frame(width: 1_200, height: 800)
}

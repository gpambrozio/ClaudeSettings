import SwiftUI

public struct ContentView: View {
    @State private var projectListViewModel = ProjectListViewModel()
    @State private var sidebarSelection: SidebarSelection?
    @State private var selectedSettingKey: String?

    // Create settings view model based on selection
    private var settingsViewModel: SettingsViewModel? {
        switch sidebarSelection {
        case .globalSettings:
            return SettingsViewModel(project: nil)
        case let .project(project):
            return SettingsViewModel(project: project)
        case .none:
            return nil
        }
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // Sidebar: Global Settings + Projects
            SidebarView(viewModel: projectListViewModel, selection: $sidebarSelection)
        } content: {
            // Content Area: Settings List
            if let viewModel = settingsViewModel {
                SettingsListView(settingsViewModel: viewModel, selectedKey: $selectedSettingKey)
                    .id(sidebarSelection?.id) // Force refresh when selection changes
                    .task {
                        viewModel.loadSettings()
                    }
            } else {
                emptyContentState
            }
        } detail: {
            // Inspector: Details & Actions
            InspectorView(selectedKey: selectedSettingKey, settingsViewModel: settingsViewModel)
        }
        .navigationSplitViewStyle(.balanced)
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

    public init() { }
}

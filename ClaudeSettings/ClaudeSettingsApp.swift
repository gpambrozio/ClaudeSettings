import SwiftUI
import ClaudeSettingsFeature

@main
struct ClaudeSettingsApp: App {
    @StateObject private var updaterController = UpdaterController()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updaterController: updaterController)
            }
        }
    }
}

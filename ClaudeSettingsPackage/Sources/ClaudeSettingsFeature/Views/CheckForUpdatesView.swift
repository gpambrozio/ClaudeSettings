import SwiftUI

/// A view that displays a "Check for Updates..." button in a menu.
/// This view observes the UpdaterController and enables/disables based on update state.
public struct CheckForUpdatesView: View {
    @ObservedObject private var updaterController: UpdaterController

    public init(updaterController: UpdaterController) {
        self.updaterController = updaterController
    }

    public var body: some View {
        Button("Check for Updates...") {
            updaterController.checkForUpdates()
        }
        .disabled(!updaterController.canCheckForUpdates)
    }
}

import Foundation
import Sparkle

/// A controller class that manages the Sparkle updater for the application.
/// This class wraps SPUStandardUpdaterController and provides SwiftUI-friendly bindings.
@MainActor
public final class UpdaterController: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    /// Whether the user can check for updates (not currently checking)
    @Published public private(set) var canCheckForUpdates = false

    /// The date of the last update check, if any
    public var lastUpdateCheckDate: Date? {
        updaterController.updater.lastUpdateCheckDate
    }

    public init() {
        // Create the updater controller with default user driver
        // startingUpdater: true means it will start automatically
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Observe canCheckForUpdates changes
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Programmatically trigger an update check
    public func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Whether automatic update checks are enabled
    public var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    /// The interval between automatic update checks (in seconds)
    public var updateCheckInterval: TimeInterval {
        get { updaterController.updater.updateCheckInterval }
        set { updaterController.updater.updateCheckInterval = newValue }
    }

    /// Whether automatic downloads are enabled
    public var automaticallyDownloadsUpdates: Bool {
        get { updaterController.updater.automaticallyDownloadsUpdates }
        set { updaterController.updater.automaticallyDownloadsUpdates = newValue }
    }
}

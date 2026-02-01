import Foundation

// MARK: - Plugin Protocol

/// Common interface for plugin types (available and installed)
public protocol Plugin: Sendable, Identifiable, Hashable {
    /// The plugin name
    var name: String { get }

    /// The marketplace this plugin belongs to
    var marketplace: String { get }
}

public extension Plugin {
    /// Unique identifier combining name and marketplace
    var id: String { "\(name)@\(marketplace)" }
}

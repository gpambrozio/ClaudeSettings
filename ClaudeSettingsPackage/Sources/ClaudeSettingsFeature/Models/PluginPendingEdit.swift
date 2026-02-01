import Foundation

/// Pending edit for a plugin
public struct PluginPendingEdit: Sendable {
    public let original: InstalledPlugin?
    public var name: String
    public var marketplace: String
    public var isNew: Bool

    public init(original: InstalledPlugin? = nil, name: String = "", marketplace: String = "", isNew: Bool = false) {
        self.original = original
        self.name = name
        self.marketplace = marketplace
        self.isNew = isNew
    }

    /// Create from existing plugin
    public init(from plugin: InstalledPlugin) {
        self.original = plugin
        self.name = plugin.name
        self.marketplace = plugin.marketplace
        self.isNew = false
    }

    /// Convert back to InstalledPlugin
    public func toPlugin() -> InstalledPlugin {
        InstalledPlugin(
            name: name,
            marketplace: marketplace,
            installedAt: original?.installedAt ?? ISO8601DateFormatter().string(from: Date())
        )
    }

    /// Validation error if any
    public var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Name is required"
        }
        if marketplace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Marketplace is required"
        }
        return nil
    }
}

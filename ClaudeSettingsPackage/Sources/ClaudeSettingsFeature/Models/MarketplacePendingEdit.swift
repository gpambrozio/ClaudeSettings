import Foundation

/// Pending edit for a marketplace
public struct MarketplacePendingEdit: Sendable {
    public let original: KnownMarketplace?
    public var name: String
    public var sourceType: String
    public var repo: String
    public var path: String
    public var ref: String
    public var isNew: Bool

    public init(
        original: KnownMarketplace? = nil,
        name: String = "",
        sourceType: String = "github",
        repo: String = "",
        path: String = "",
        ref: String = "",
        isNew: Bool = false
    ) {
        self.original = original
        self.name = name
        self.sourceType = sourceType
        self.repo = repo
        self.path = path
        self.ref = ref
        self.isNew = isNew
    }

    /// Create from existing marketplace
    public init(from marketplace: KnownMarketplace) {
        self.original = marketplace
        self.name = marketplace.name
        self.sourceType = marketplace.source.source
        self.repo = marketplace.source.repo ?? ""
        self.path = marketplace.source.path ?? ""
        self.ref = marketplace.source.ref ?? ""
        self.isNew = false
    }

    /// Convert back to KnownMarketplace
    public func toMarketplace() -> KnownMarketplace {
        let source = MarketplaceSource(
            source: sourceType,
            repo: sourceType == "github" ? (repo.isEmpty ? nil : repo) : nil,
            path: sourceType == "directory" ? (path.isEmpty ? nil : path) : nil,
            ref: ref.isEmpty ? nil : ref
        )
        return KnownMarketplace(
            name: name,
            source: source,
            dataSource: original?.dataSource ?? .global,
            installLocation: original?.installLocation,
            lastUpdated: original?.lastUpdated ?? Date()
        )
    }

    /// Validation error if any
    public var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Name is required"
        }
        if sourceType == "github" && repo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Repository is required for GitHub sources"
        }
        if sourceType == "directory" && path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Path is required for directory sources"
        }
        return nil
    }
}

import Foundation

/// Source configuration for a marketplace
public struct MarketplaceSource: Codable, Sendable, Hashable {
    /// The source type ("github" or "directory")
    public let source: String

    /// For github sources - the repository path (e.g., "company/repo")
    public let repo: String?

    /// For directory sources - the local path
    public let path: String?

    /// Optional branch or tag reference
    public let ref: String?

    public init(source: String, repo: String? = nil, path: String? = nil, ref: String? = nil) {
        self.source = source
        self.repo = repo
        self.path = path
        self.ref = ref
    }

    /// Whether this is a GitHub source
    public var isGitHub: Bool {
        source == "github"
    }

    /// Whether this is a directory source
    public var isDirectory: Bool {
        source == "directory"
    }
}

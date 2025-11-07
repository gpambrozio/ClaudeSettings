import Foundation

/// Represents a node in the hierarchical settings tree
public struct HierarchicalSettingNode: Identifiable, Sendable {
    public let id: String
    public let key: String
    public let displayName: String
    public let nodeType: NodeType
    public var children: [HierarchicalSettingNode]

    public enum NodeType: Sendable {
        case parent(childCount: Int)
        case leaf(item: SettingItem)
    }

    public init(
        id: String,
        key: String,
        displayName: String,
        nodeType: NodeType,
        children: [HierarchicalSettingNode] = []
    ) {
        self.id = id
        self.key = key
        self.displayName = displayName
        self.nodeType = nodeType
        self.children = children
    }

    /// Returns true if this node is a parent with children
    public var isParent: Bool {
        if case .parent = nodeType { true } else { false }
    }

    /// Returns true if this node is a leaf with an actual setting value
    public var isLeaf: Bool {
        if case .leaf = nodeType { true } else { false }
    }

    /// Returns the setting item if this is a leaf node
    public var settingItem: SettingItem? {
        if case let .leaf(item) = nodeType {
            return item
        }
        return nil
    }
}

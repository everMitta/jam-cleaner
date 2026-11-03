import Foundation

/// A path-component prefix tree (Trie) that enables O(k) ancestor and descendant exclusion checks.
/// - If an ancestor is marked `isExcluded = true`, the target path and all its children are protected.
/// - If a descendant node exists below a target directory, the directory contains a protected child and cannot be bulk-deleted without preserving the excluded subtree.
public struct ExclusionPrefixTree: Sendable {
    private struct Node: Sendable {
        var children: [String: Node] = [:]
        var isExcluded: Bool = false
    }

    private var root = Node()

    public init(excludedPaths: [String] = []) {
        for path in excludedPaths {
            insert(path: path)
        }
    }

    /// Normalizes a filesystem path into canonical components.
    public static func normalizedComponents(for path: String) -> [String] {
        let expanded = (path as NSString).expandingTildeInPath
        let standardized = (expanded as NSString).standardizingPath
        return standardized.split(separator: "/").map(String.init)
    }

    /// Registers a path (and implicitly all its descendants) as protected.
    public mutating func insert(path: String) {
        let components = Self.normalizedComponents(for: path)
        guard !components.isEmpty else { return }
        Self.insert(components: ArraySlice(components), into: &root)
    }

    private static func insert(components: ArraySlice<String>, into node: inout Node) {
        guard let head = components.first else {
            node.isExcluded = true
            return
        }
        var child = node.children[head] ?? Node()
        insert(components: components.dropFirst(), into: &child)
        node.children[head] = child
    }

    /// Returns `true` if `path` itself or any of its ancestor directories is registered as excluded.
    public func isPathOrAncestorExcluded(_ path: String) -> Bool {
        let components = Self.normalizedComponents(for: path)
        guard !components.isEmpty else { return true }
        var current = root
        for component in components {
            guard let next = current.children[component] else {
                return false
            }
            if next.isExcluded {
                return true
            }
            current = next
        }
        return current.isExcluded
    }

    /// Returns `true` if `path` is an ancestor of at least one excluded descendant path.
    /// When true, `path` must NEVER be removed via a single recursive `removeItem(atPath:)` call without skipping the protected child.
    public func hasExcludedDescendant(_ path: String) -> Bool {
        let components = Self.normalizedComponents(for: path)
        guard !components.isEmpty else { return true }
        var current = root
        for component in components {
            guard let next = current.children[component] else {
                return false
            }
            if next.isExcluded {
                return true
            }
            current = next
        }
        return !current.children.isEmpty
    }
}

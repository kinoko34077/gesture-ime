import Foundation

public final class BindingTrieNode: @unchecked Sendable {
    public let behavior: BindingBehavior?
    public let children: [Direction8: BindingTrieNode]

    public init(behavior: BindingBehavior? = nil, children: [Direction8: BindingTrieNode] = [:]) {
        self.behavior = behavior
        self.children = children
    }

    public var eligibleDirections: Set<Direction8> { Set(children.keys) }
}

public struct BindingTrie: @unchecked Sendable {
    public let root: BindingTrieNode
    public init(root: BindingTrieNode) { self.root = root }

    public func node(for path: GesturePath) -> BindingTrieNode? {
        var node = root
        for token in path.tokens {
            guard let child = node.children[token.direction] else { return nil }
            node = child
        }
        return node
    }
}

public enum BindingTrieCompiler {
    private final class BuilderNode {
        var behavior: BindingBehavior?
        var children: [Direction8: BuilderNode] = [:]
    }

    public static func compile(_ bindingSet: BindingSet, keyID: String) throws -> BindingTrie {
        let root = BuilderNode()
        var seen = Set<GesturePath>()
        for binding in bindingSet.bindings where binding.keyID == keyID {
            guard binding.path.tokens.count <= ProfileLimits.pathDepth else { throw ProfileValidationError(.pathDepth) }
            guard !seen.contains(binding.path) else {
                throw ProfileValidationError(.duplicateBindingPath, "\(bindingSet.id):\(keyID)")
            }
            seen.insert(binding.path)
            var node = root
            for token in binding.path.tokens {
                if let existing = node.children[token.direction] {
                    node = existing
                } else {
                    let child = BuilderNode()
                    node.children[token.direction] = child
                    node = child
                }
            }
            node.behavior = binding.behavior
        }
        return BindingTrie(root: freeze(root))
    }

    private static func freeze(_ node: BuilderNode) -> BindingTrieNode {
        BindingTrieNode(
            behavior: node.behavior,
            children: node.children.mapValues(freeze)
        )
    }
}

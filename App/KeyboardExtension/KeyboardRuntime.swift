import Foundation
import GestureIMECore

struct KeyboardKeyRuntime: Identifiable {
    let id: String
    let title: String
    let trie: BindingTrie
}

struct KeyboardLayoutRuntime {
    let rows: [[KeyboardKeyRuntime]]
    let profileRevision: String
    let defaultPolicy: GesturePolicy

    static func compile(profile: ProfileBundle, layerID: String = "base") throws -> KeyboardLayoutRuntime {
        guard let layer = profile.layers.first(where: { $0.id == layerID }),
              let layout = profile.layouts.first(where: { $0.id == layer.layoutRef }),
              let bindingSet = profile.bindingSets.first(where: { $0.id == layer.bindingSetRef }) else {
            throw ProfileValidationError(.missingReference, layerID)
        }

        let keyDefinitions = Dictionary(uniqueKeysWithValues: profile.keyDefinitions.map { ($0.id, $0) })
        let grouped = Dictionary(grouping: layout.placements, by: \.row)
        let rows = try grouped.keys.sorted().map { row in
            try grouped[row, default: []]
                .sorted { lhs, rhs in
                    if lhs.column == rhs.column { return lhs.keyID < rhs.keyID }
                    return lhs.column < rhs.column
                }
                .map { placement in
                    guard let definition = keyDefinitions[placement.keyID] else {
                        throw ProfileValidationError(.missingReference, placement.keyID)
                    }
                    let trie = try BindingTrieCompiler.compile(bindingSet, keyID: placement.keyID)
                    return KeyboardKeyRuntime(
                        id: placement.keyID,
                        title: definition.presentation?.text ?? placement.keyID,
                        trie: trie
                    )
                }
        }

        return KeyboardLayoutRuntime(
            rows: rows,
            profileRevision: "\(profile.id):\(profile.version)",
            defaultPolicy: profile.gesturePolicy
        )
    }
}

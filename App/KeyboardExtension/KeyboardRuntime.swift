import Foundation
import GestureIMECore

struct KeyboardKeyRuntime: Identifiable {
    let id: String
    let title: String
    let role: String?
    let trie: BindingTrie
    let row: Int
    let column: Int
    let width: Int
    let height: Int
}

struct KeyboardLayoutRuntime {
    let keys: [KeyboardKeyRuntime]
    let rowCount: Int
    let columnCount: Int
    let profileRevision: String
    let defaultPolicy: GesturePolicy

    static func compile(profile: ProfileBundle, layerID: String = "base") throws -> KeyboardLayoutRuntime {
        guard let layer = profile.layers.first(where: { $0.id == layerID }),
              let layout = profile.layouts.first(where: { $0.id == layer.layoutRef }),
              let bindingSet = profile.bindingSets.first(where: { $0.id == layer.bindingSetRef }) else {
            throw ProfileValidationError(.missingReference, layerID)
        }

        let keyDefinitions = Dictionary(uniqueKeysWithValues: profile.keyDefinitions.map { ($0.id, $0) })

        let keys = try layout.placements.map { placement in
            guard let definition = keyDefinitions[placement.keyID] else {
                throw ProfileValidationError(.missingReference, placement.keyID)
            }
            let trie = try BindingTrieCompiler.compile(bindingSet, keyID: placement.keyID)
            return KeyboardKeyRuntime(
                id: placement.keyID,
                title: definition.presentation?.text ?? placement.keyID,
                role: definition.role,
                trie: trie,
                row: placement.row,
                column: placement.column,
                width: max(1, Int((placement.width ?? 1).rounded())),
                height: max(1, Int((placement.height ?? 1).rounded()))
            )
        }

        let columnCount = keys.map { $0.column + $0.width }.max() ?? 1
        let rowCount = keys.map { $0.row + $0.height }.max() ?? 1

        return KeyboardLayoutRuntime(
            keys: keys,
            rowCount: rowCount,
            columnCount: columnCount,
            profileRevision: "\(profile.id):\(profile.version)",
            defaultPolicy: profile.gesturePolicy
        )
    }
}

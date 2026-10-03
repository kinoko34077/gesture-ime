import Foundation

struct KeyboardKeyRuntime: Identifiable {
    let id: String
    let title: String
    let role: String?
    let firstStagePresentation: [String: String]
    let row: Int
    let column: Int
    let width: Int
    let height: Int
}

struct KeyboardLayoutRuntime {
    let sharedRuntime: IOSSharedGestureRuntimeAdapter
    let keys: [KeyboardKeyRuntime]
    let rowCount: Int
    let columnCount: Int
    let profileRevision: String
    let defaultPolicy: FfiGesturePolicy

    static func compile(profileJSON: String, layerID: String = "base") throws -> KeyboardLayoutRuntime {
        let sharedRuntime = try IOSSharedGestureRuntimeAdapter(profileJSON: profileJSON)
        let layout = try sharedRuntime.compileLayout(layerID: layerID)

        let keys = layout.keys.map { key in
            let presentations = Dictionary(
                uniqueKeysWithValues: key.firstStagePresentations.compactMap { presentation in
                    guard let text = presentation.text, !text.isEmpty else { return nil }
                    return (String(describing: presentation.direction).lowercased(), text)
                }
            )

            return KeyboardKeyRuntime(
                id: key.id,
                title: key.title ?? key.id,
                role: key.role,
                firstStagePresentation: presentations,
                row: Int(key.row),
                column: Int(key.column),
                width: max(1, Int(key.width.rounded())),
                height: max(1, Int(key.height.rounded()))
            )
        }

        return KeyboardLayoutRuntime(
            sharedRuntime: sharedRuntime,
            keys: keys,
            rowCount: Int(layout.rowCount),
            columnCount: Int(layout.columnCount),
            profileRevision: sharedRuntime.profileRevision,
            defaultPolicy: sharedRuntime.defaultPolicy()
        )
    }
}

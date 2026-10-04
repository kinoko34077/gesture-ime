import Foundation

// #69 §17 — presets generate *ordinary* Profile v3 data (Boards, entries,
// text.insert Actions, transitions). They are not runtime modes and can be
// edited freely afterwards.

public enum ProfileV3Preset: String, CaseIterable, Identifiable, Sendable {
    case japanese12
    case latin12
    case qwerty
    case numeric
    case fourWay
    case eightWay
    case multiStage
    case empty

    public var id: String { rawValue }

    public var displayKey: ProfileV3DisplayKey {
        switch self {
        case .japanese12: .presetJapanese12
        case .latin12: .presetLatin12
        case .qwerty: .presetQwerty
        case .numeric: .presetNumeric
        case .fourWay: .presetFourWay
        case .eightWay: .presetEightWay
        case .multiStage: .presetMultiStage
        case .empty: .presetEmpty
        }
    }
}

/// One flick group: center/tap first, then W, N, E, S, then diagonals
/// NE, SE, SW, NW (conventional Japanese 12-key order: あ い う え お).
struct ProfileV3PresetFlickKey {
    let label: String
    let outputs: [String]
}

extension ProfileDocument {
    private static let flickOrder: [ProfileV3Direction] = [
        .west, .north, .east, .south, .northEast, .southEast, .southWest, .northWest
    ]

    /// Creates a new Layer whose root Board (and any relative Boards) are
    /// generated from `preset`. Returns the new Layer ID.
    @discardableResult
    public mutating func v3CreateLayer(
        fromPreset preset: ProfileV3Preset,
        layerID requestedLayerID: String,
        name: String?
    ) throws -> String {
        try Self.v3ValidateSemanticID(requestedLayerID, field: "layer.id")
        let rootBoardID = try v3UniqueBoardID(base: "board.\(requestedLayerID)")
        try v3CreateBoard(id: rootBoardID)

        switch preset {
        case .japanese12:
            try v3FillTwelveKey(rootBoardID: rootBoardID, keys: Self.japaneseTwelveKeys)
        case .latin12:
            try v3FillTwelveKey(rootBoardID: rootBoardID, keys: Self.latinTwelveKeys)
        case .qwerty:
            try v3FillQwerty(rootBoardID: rootBoardID)
        case .numeric:
            try v3FillGrid(
                rootBoardID: rootBoardID,
                rows: [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["*", "0", "#"]]
            )
        case .fourWay:
            try v3AddFlickKey(
                rootBoardID: rootBoardID,
                entryID: "\(rootBoardID).key",
                rect: ProfileV3Rect(x: -1, y: -1, width: 2, height: 2),
                key: ProfileV3PresetFlickKey(label: "あ", outputs: ["あ", "い", "う", "え", "お"])
            )
        case .eightWay:
            try v3AddFlickKey(
                rootBoardID: rootBoardID,
                entryID: "\(rootBoardID).key",
                rect: ProfileV3Rect(x: -1, y: -1, width: 2, height: 2),
                key: ProfileV3PresetFlickKey(
                    label: "8方向",
                    outputs: ["0", "4", "2", "6", "8", "3", "9", "7", "1"]
                )
            )
        case .multiStage:
            try v3FillMultiStage(rootBoardID: rootBoardID)
        case .empty:
            break
        }

        try v3CreateLayer(id: requestedLayerID, name: name, rootBoardID: rootBoardID)
        return requestedLayerID
    }

    static let japaneseTwelveKeys: [[ProfileV3PresetFlickKey]] = [
        [
            .init(label: "あ", outputs: ["あ", "い", "う", "え", "お"]),
            .init(label: "か", outputs: ["か", "き", "く", "け", "こ"]),
            .init(label: "さ", outputs: ["さ", "し", "す", "せ", "そ"])
        ],
        [
            .init(label: "た", outputs: ["た", "ち", "つ", "て", "と"]),
            .init(label: "な", outputs: ["な", "に", "ぬ", "ね", "の"]),
            .init(label: "は", outputs: ["は", "ひ", "ふ", "へ", "ほ"])
        ],
        [
            .init(label: "ま", outputs: ["ま", "み", "む", "め", "も"]),
            .init(label: "や", outputs: ["や", "「", "ゆ", "」", "よ"]),
            .init(label: "ら", outputs: ["ら", "り", "る", "れ", "ろ"])
        ],
        [
            .init(label: "、。", outputs: ["、", "。", "？", "！", "…"]),
            .init(label: "わ", outputs: ["わ", "を", "ん", "ー", "〜"]),
            .init(label: "ー", outputs: ["ー"])
        ]
    ]

    static let latinTwelveKeys: [[ProfileV3PresetFlickKey]] = [
        [
            .init(label: "@#/&_", outputs: ["@", "#", "/", "&", "_"]),
            .init(label: "ABC", outputs: ["a", "b", "c"]),
            .init(label: "DEF", outputs: ["d", "e", "f"])
        ],
        [
            .init(label: "GHI", outputs: ["g", "h", "i"]),
            .init(label: "JKL", outputs: ["j", "k", "l"]),
            .init(label: "MNO", outputs: ["m", "n", "o"])
        ],
        [
            .init(label: "PQRS", outputs: ["p", "q", "r", "s"]),
            .init(label: "TUV", outputs: ["t", "u", "v"]),
            .init(label: "WXYZ", outputs: ["w", "x", "y", "z"])
        ],
        [
            .init(label: "'\"()", outputs: ["'", "\"", "(", ")"]),
            .init(label: ".,?!", outputs: [".", ",", "?", "!"]),
            .init(label: "-", outputs: ["-"])
        ]
    ]

    private mutating func v3FillTwelveKey(
        rootBoardID: String,
        keys: [[ProfileV3PresetFlickKey]]
    ) throws {
        for (row, rowKeys) in keys.enumerated() {
            for (column, key) in rowKeys.enumerated() {
                try v3AddFlickKey(
                    rootBoardID: rootBoardID,
                    entryID: "\(rootBoardID).r\(row)c\(column)",
                    rect: ProfileV3Rect(x: column * 2 - 3, y: row * 2 - 4, width: 2, height: 2),
                    key: key
                )
            }
        }
    }

    private mutating func v3FillGrid(rootBoardID: String, rows: [[String]]) throws {
        for (row, labels) in rows.enumerated() {
            for (column, label) in labels.enumerated() {
                try v3CreateEntry(
                    boardID: rootBoardID,
                    id: "\(rootBoardID).r\(row)c\(column)",
                    rect: ProfileV3Rect(x: column * 2 - 3, y: row * 2 - 4, width: 2, height: 2),
                    resolver: Self.v3TextResolver(label)
                )
            }
        }
    }

    private mutating func v3FillQwerty(rootBoardID: String) throws {
        let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        for (row, letters) in rows.enumerated() {
            let offset = row  // stagger by half a key per row
            for (column, letter) in letters.enumerated() {
                let text = String(letter)
                try v3CreateEntry(
                    boardID: rootBoardID,
                    id: "\(rootBoardID).\(text)",
                    rect: ProfileV3Rect(x: column * 2 - 10 + offset, y: row * 2 - 3, width: 2, height: 2),
                    resolver: Self.v3TextResolver(text)
                )
            }
        }
    }

    private mutating func v3FillMultiStage(rootBoardID: String) throws {
        // Stage 1: a/b/c/d/e; north continues to Stage 2 with f/g/h/i/j.
        let stageTwo = try v3UniqueBoardID(base: "\(rootBoardID).stage2")
        try v3CreateBoard(id: stageTwo)
        try v3FillRelativeBoard(boardID: stageTwo, outputs: ["f", "g", "h", "i", "j"])

        let stageOne = try v3UniqueBoardID(base: "\(rootBoardID).stage1")
        try v3CreateBoard(id: stageOne)
        try v3FillRelativeBoard(boardID: stageOne, outputs: ["a", "b", "c", "d", "e"])
        let north = try v3ImmediateDirectionSlots(boardID: stageOne)
            .first { $0.direction == .north }?.entry
        if let north {
            try v3SetEntryResolver(
                boardID: stageOne,
                entryID: north.id,
                resolver: Self.v3TextResolver("c→", transitionTo: stageTwo)
            )
        }

        try v3CreateEntry(
            boardID: rootBoardID,
            id: "\(rootBoardID).key",
            rect: ProfileV3Rect(x: -1, y: -1, width: 2, height: 2),
            resolver: Self.v3TextResolver("a…j", transitionTo: stageOne)
        )
    }

    private mutating func v3AddFlickKey(
        rootBoardID: String,
        entryID: String,
        rect: ProfileV3Rect,
        key: ProfileV3PresetFlickKey
    ) throws {
        guard key.outputs.count > 1 else {
            try v3CreateEntry(
                boardID: rootBoardID,
                id: entryID,
                rect: rect,
                resolver: Self.v3TextResolver(key.outputs.first ?? key.label)
            )
            return
        }
        let relative = try v3UniqueBoardID(base: "\(entryID).flick")
        try v3CreateBoard(id: relative)
        try v3FillRelativeBoard(boardID: relative, outputs: key.outputs)
        try v3CreateEntry(
            boardID: rootBoardID,
            id: entryID,
            rect: rect,
            resolver: Self.v3TextResolver(key.label, transitionTo: relative)
        )
    }

    /// outputs[0] = center (tap), then W, N, E, S, NE, SE, SW, NW.
    private mutating func v3FillRelativeBoard(boardID: String, outputs: [String]) throws {
        guard let center = outputs.first else { return }
        try v3CreateEntry(
            boardID: boardID,
            id: "\(boardID).center",
            rect: ProfileV3Rect(x: -1, y: -1, width: 2, height: 2),
            resolver: Self.v3TextResolver(center)
        )
        for (direction, text) in zip(Self.flickOrder, outputs.dropFirst()) {
            try v3SetDirectionText(boardID: boardID, direction: direction, text: text)
        }
    }
}

import Foundation

// #73 / #69 §§3, 8–10, 15, 17 — editor foundation that stays a *view* over the
// one canonical Profile v3 document. Nothing in this file introduces a second
// semantic store: policy, direction slots and presets read/write ordinary
// Profile JSON through the same document mutations the runtime validates.

// MARK: - GesturePolicy (common + partial per-source override)

public enum ProfileV3GesturePolicyField: String, CaseIterable, Identifiable, Sendable {
    case deadZone
    case initialCellCommitDistance
    case subsequentCellCommitDistance
    case angularHysteresisDegrees
    case stageBacktrackDwellMs

    public var id: String { rawValue }

    public var displayKey: ProfileV3DisplayKey {
        switch self {
        case .deadZone: .policyDeadZone
        case .initialCellCommitDistance: .policyInitialCommit
        case .subsequentCellCommitDistance: .policySubsequentCommit
        case .angularHysteresisDegrees: .policyHysteresis
        case .stageBacktrackDwellMs: .policyBacktrackDwell
        }
    }

    /// Editable range mirroring the shared-runtime validator.
    public var range: ClosedRange<Double> {
        switch self {
        case .deadZone: 0...2
        case .initialCellCommitDistance, .subsequentCellCommitDistance: 0.01...4
        case .angularHysteresisDegrees: 0...44
        case .stageBacktrackDwellMs:
            Double(ProfileV3GesturePolicyValues.dwellRange.lowerBound)
                ...Double(ProfileV3GesturePolicyValues.dwellRange.upperBound)
        }
    }

    public var step: Double {
        switch self {
        case .stageBacktrackDwellMs: 50
        case .angularHysteresisDegrees: 1
        default: 0.01
        }
    }
}

public struct ProfileV3GesturePolicyValues: Equatable, Sendable {
    public static let defaultStageBacktrackDwellMs = 1000
    public static let dwellRange = 100...10_000

    public var deadZone: Double
    public var initialCellCommitDistance: Double
    public var subsequentCellCommitDistance: Double
    public var angularHysteresisDegrees: Double
    public var stageBacktrackDwellMs: Int

    public init(
        deadZone: Double,
        initialCellCommitDistance: Double,
        subsequentCellCommitDistance: Double,
        angularHysteresisDegrees: Double,
        stageBacktrackDwellMs: Int = ProfileV3GesturePolicyValues.defaultStageBacktrackDwellMs
    ) {
        self.deadZone = deadZone
        self.initialCellCommitDistance = initialCellCommitDistance
        self.subsequentCellCommitDistance = subsequentCellCommitDistance
        self.angularHysteresisDegrees = angularHysteresisDegrees
        self.stageBacktrackDwellMs = stageBacktrackDwellMs
    }

    /// Same constraints as the shared Rust validator.
    public var isValid: Bool {
        let finite = [
            deadZone,
            initialCellCommitDistance,
            subsequentCellCommitDistance,
            angularHysteresisDegrees
        ].allSatisfy(\.isFinite)
        return finite
            && (0...2).contains(deadZone)
            && initialCellCommitDistance > 0 && initialCellCommitDistance <= 4
            && subsequentCellCommitDistance > 0 && subsequentCellCommitDistance <= 4
            && initialCellCommitDistance >= deadZone
            && subsequentCellCommitDistance >= deadZone
            && angularHysteresisDegrees >= 0 && angularHysteresisDegrees < 45
            && Self.dwellRange.contains(stageBacktrackDwellMs)
    }

    public func value(_ field: ProfileV3GesturePolicyField) -> Double {
        switch field {
        case .deadZone: deadZone
        case .initialCellCommitDistance: initialCellCommitDistance
        case .subsequentCellCommitDistance: subsequentCellCommitDistance
        case .angularHysteresisDegrees: angularHysteresisDegrees
        case .stageBacktrackDwellMs: Double(stageBacktrackDwellMs)
        }
    }

    public mutating func set(_ field: ProfileV3GesturePolicyField, _ value: Double) {
        switch field {
        case .deadZone: deadZone = value
        case .initialCellCommitDistance: initialCellCommitDistance = value
        case .subsequentCellCommitDistance: subsequentCellCommitDistance = value
        case .angularHysteresisDegrees: angularHysteresisDegrees = value
        case .stageBacktrackDwellMs: stageBacktrackDwellMs = Int(value.rounded())
        }
    }

    /// Effective policy for a stage entered from a source carrying `partial`.
    public func applying(_ partial: ProfileV3GesturePolicyOverride?) -> Self {
        guard let partial else { return self }
        var result = self
        for field in ProfileV3GesturePolicyField.allCases {
            if let value = partial.value(field) {
                result.set(field, value)
            }
        }
        return result
    }
}

/// Optional *partial* per-source override; unset fields inherit (#69 §3.2).
public struct ProfileV3GesturePolicyOverride: Equatable, Sendable {
    public var deadZone: Double?
    public var initialCellCommitDistance: Double?
    public var subsequentCellCommitDistance: Double?
    public var angularHysteresisDegrees: Double?
    public var stageBacktrackDwellMs: Int?

    public init(
        deadZone: Double? = nil,
        initialCellCommitDistance: Double? = nil,
        subsequentCellCommitDistance: Double? = nil,
        angularHysteresisDegrees: Double? = nil,
        stageBacktrackDwellMs: Int? = nil
    ) {
        self.deadZone = deadZone
        self.initialCellCommitDistance = initialCellCommitDistance
        self.subsequentCellCommitDistance = subsequentCellCommitDistance
        self.angularHysteresisDegrees = angularHysteresisDegrees
        self.stageBacktrackDwellMs = stageBacktrackDwellMs
    }

    public var isEmpty: Bool {
        ProfileV3GesturePolicyField.allCases.allSatisfy { value($0) == nil }
    }

    public func value(_ field: ProfileV3GesturePolicyField) -> Double? {
        switch field {
        case .deadZone: deadZone
        case .initialCellCommitDistance: initialCellCommitDistance
        case .subsequentCellCommitDistance: subsequentCellCommitDistance
        case .angularHysteresisDegrees: angularHysteresisDegrees
        case .stageBacktrackDwellMs: stageBacktrackDwellMs.map(Double.init)
        }
    }

    public mutating func set(_ field: ProfileV3GesturePolicyField, _ value: Double?) {
        switch field {
        case .deadZone: deadZone = value
        case .initialCellCommitDistance: initialCellCommitDistance = value
        case .subsequentCellCommitDistance: subsequentCellCommitDistance = value
        case .angularHysteresisDegrees: angularHysteresisDegrees = value
        case .stageBacktrackDwellMs: stageBacktrackDwellMs = value.map { Int($0.rounded()) }
        }
    }
}

extension ProfileDocument {
    public func v3GesturePolicyValues() throws -> ProfileV3GesturePolicyValues {
        let top = try v3TopObject()
        guard
            let policy = top["gesturePolicy"]?.objectValue,
            let deadZone = policy["deadZone"]?.doubleValue,
            let initial = policy["initialCellCommitDistance"]?.doubleValue,
            let subsequent = policy["subsequentCellCommitDistance"]?.doubleValue,
            let hysteresis = policy["angularHysteresisDegrees"]?.doubleValue
        else {
            throw ProfileAuthoringError.invalidJSON("Invalid v3 gesturePolicy")
        }
        return ProfileV3GesturePolicyValues(
            deadZone: deadZone,
            initialCellCommitDistance: initial,
            subsequentCellCommitDistance: subsequent,
            angularHysteresisDegrees: hysteresis,
            stageBacktrackDwellMs: policy["stageBacktrackDwellMs"]?.intValue
                ?? ProfileV3GesturePolicyValues.defaultStageBacktrackDwellMs
        )
    }

    /// Writes the one Profile-wide common policy, preserving unknown keys.
    public mutating func v3SetGesturePolicyValues(
        _ values: ProfileV3GesturePolicyValues
    ) throws {
        guard values.isValid else {
            throw ProfileAuthoringError.invalidJSON("入力設定の値が有効範囲外です")
        }
        var top = try v3TopObject()
        var object = top["gesturePolicy"]?.objectValue ?? [:]
        object["deadZone"] = .decimal(values.deadZone)
        object["initialCellCommitDistance"] = .decimal(values.initialCellCommitDistance)
        object["subsequentCellCommitDistance"] = .decimal(values.subsequentCellCommitDistance)
        object["angularHysteresisDegrees"] = .decimal(values.angularHysteresisDegrees)
        object["stageBacktrackDwellMs"] = .integer(Int64(values.stageBacktrackDwellMs))
        top["gesturePolicy"] = .object(object)
        root = .object(top)
    }

    public func v3EntryPolicyOverride(
        boardID: String,
        entryID: String
    ) throws -> ProfileV3GesturePolicyOverride? {
        let entry = try v3EntryObject(boardID: boardID, entryID: entryID)
        guard let object = entry["gesturePolicyOverride"]?.objectValue else {
            return nil
        }
        var result = ProfileV3GesturePolicyOverride()
        for field in ProfileV3GesturePolicyField.allCases {
            result.set(field, object[field.rawValue]?.doubleValue)
        }
        return result
    }

    /// Sets (or with `nil`/empty, removes) a source entry's partial override.
    /// The merged policy is validated exactly like the runtime does.
    public mutating func v3SetEntryPolicyOverride(
        boardID: String,
        entryID: String,
        override partial: ProfileV3GesturePolicyOverride?
    ) throws {
        if let partial, !partial.isEmpty {
            let merged = try v3GesturePolicyValues().applying(partial)
            guard merged.isValid else {
                throw ProfileAuthoringError.invalidJSON(
                    "このキーの入力設定は共通設定と組み合わせると有効範囲外です"
                )
            }
        }
        try v3MutateEntry(boardID: boardID, entryID: entryID) { entry in
            guard let partial, !partial.isEmpty else {
                entry.removeValue(forKey: "gesturePolicyOverride")
                return
            }
            var object = entry["gesturePolicyOverride"]?.objectValue ?? [:]
            for field in ProfileV3GesturePolicyField.allCases {
                if let value = partial.value(field) {
                    object[field.rawValue] = field == .stageBacktrackDwellMs
                        ? .integer(Int64(value.rounded()))
                        : .decimal(value)
                } else {
                    object.removeValue(forKey: field.rawValue)
                }
            }
            entry["gesturePolicyOverride"] = .object(object)
        }
    }
}

// MARK: - Simple text output (easy inspector view over onRelease/presentation)

extension ProfileDocument {
    /// The single `text.insert` literal of an entry's default release, when the
    /// entry is simple enough for the easy inspector to edit it directly.
    public func v3SimpleTextOutput(boardID: String, entryID: String) throws -> String? {
        let entry = try v3EntryObject(boardID: boardID, entryID: entryID)
        guard
            let behavior = entry["resolver"]?.objectValue?["default"]?.objectValue,
            let actions = behavior["onRelease"]?.arrayValue,
            actions.count == 1,
            let action = actions[0].objectValue,
            action["actionID"]?.stringValue == "text.insert",
            let text = action["arguments"]?.objectValue?["text"]?.objectValue,
            (text["transforms"]?.arrayValue ?? []).isEmpty
        else {
            return nil
        }
        return text["base"]?.stringValue
    }

    /// Sets display text + `text.insert` release for a simple entry.
    public mutating func v3SetSimpleTextOutput(
        boardID: String,
        entryID: String,
        text: String
    ) throws {
        guard !text.isEmpty, text.unicodeScalars.count <= 64 else {
            throw ProfileAuthoringError.invalidJSON("入力文字は1〜64文字で指定してください")
        }
        try v3MutateDefaultBehavior(boardID: boardID, entryID: entryID) { behavior in
            var presentation = behavior["presentation"]?.objectValue ?? [:]
            var resolved = presentation["text"]?.objectValue ?? [:]
            resolved["base"] = .string(text)
            if resolved["transforms"] == nil {
                resolved["transforms"] = .array([])
            }
            presentation["text"] = .object(resolved)
            behavior["presentation"] = .object(presentation)
            behavior["onRelease"] = .array([Self.v3TextInsertNode(text)])
        }
    }

    static func v3TextInsertNode(_ text: String) -> JSONNode {
        v3ActionNode(ProfileActionDraft(
            actionID: "text.insert",
            arguments: ["text": .object([
                "base": .string(text),
                "transforms": .array([])
            ])]
        ))
    }

    static func v3TextResolver(_ text: String, transitionTo target: String? = nil) -> JSONNode {
        var behavior: [String: JSONNode] = [
            "presentation": .object([
                "text": .object([
                    "base": .string(text),
                    "transforms": .array([])
                ])
            ])
        ]
        if let target {
            behavior["transition"] = v3TransitionNode(
                ProfileV3TransitionDraft(targetBoardID: target, lifetime: .transient)
            )
        } else {
            behavior["onRelease"] = .array([v3TextInsertNode(text)])
        }
        return .object([
            "cases": .array([]),
            "default": .object(behavior)
        ])
    }
}

// MARK: - Direction slots (editor view over relative Board geometry)

/// Eight immediate directions in screen coordinates (y grows downward).
/// These are *views* over the target Board's entries, never stored topology.
public enum ProfileV3Direction: String, CaseIterable, Identifiable, Sendable {
    case north, northEast, east, southEast, south, southWest, west, northWest

    public var id: String { rawValue }

    public var unitX: Int {
        switch self {
        case .east, .northEast, .southEast: 1
        case .west, .northWest, .southWest: -1
        case .north, .south: 0
        }
    }

    public var unitY: Int {
        switch self {
        case .south, .southEast, .southWest: 1
        case .north, .northEast, .northWest: -1
        case .east, .west: 0
        }
    }

    public var isDiagonal: Bool { unitX != 0 && unitY != 0 }

    public var angleDegrees: Double {
        ProfileV3Direction.normalizedAngle(dx: Double(unitX), dy: Double(unitY))
    }

    /// Canonical 2×2 relative-Board rect for this direction's first ring.
    public var defaultRect: ProfileV3Rect {
        ProfileV3Rect(x: unitX * 2 - 1, y: unitY * 2 - 1, width: 2, height: 2)
    }

    public var displayKey: ProfileV3DisplayKey {
        switch self {
        case .north: .directionNorth
        case .northEast: .directionNorthEast
        case .east: .directionEast
        case .southEast: .directionSouthEast
        case .south: .directionSouth
        case .southWest: .directionSouthWest
        case .west: .directionWest
        case .northWest: .directionNorthWest
        }
    }

    static func normalizedAngle(dx: Double, dy: Double) -> Double {
        let raw = atan2(dy, dx) * 180 / .pi
        return raw < 0 ? raw + 360 : raw
    }
}

public struct ProfileV3DirectionSlot: Equatable, Identifiable, Sendable {
    public let direction: ProfileV3Direction
    public let entry: ProfileV3BoardEntrySummary?

    public var id: String { direction.rawValue }
}

extension ProfileV3Rect {
    /// Center in logical cells (relative rects are authored in half-cell atoms).
    public var centerCells: (x: Double, y: Double) {
        ((Double(x) + Double(width) / 2) / 2, (Double(y) + Double(height) / 2) / 2)
    }

    public var containsOrigin: Bool {
        x <= 0 && y <= 0 && maxX > 0 && maxY > 0
    }
}

extension ProfileDocument {
    /// Immediate (first-ring) entry for each of the eight directions of a
    /// relative Board. An entry belongs to the nearest direction within 22.5°
    /// and a center radius ≤ 1.5 cells; farther/sparse entries remain visible
    /// only through ordinary Board editing.
    public func v3ImmediateDirectionSlots(boardID: String) throws -> [ProfileV3DirectionSlot] {
        let entries = try v3BoardEntries(boardID: boardID)
        return ProfileV3Direction.allCases.map { direction in
            let match = entries
                .filter { !$0.rect.containsOrigin }
                .compactMap { entry -> (ProfileV3BoardEntrySummary, Double)? in
                    let center = entry.rect.centerCells
                    let radius = max(abs(center.x), abs(center.y))
                    guard radius > 0, radius <= 1.5 else { return nil }
                    let angle = ProfileV3Direction.normalizedAngle(dx: center.x, dy: center.y)
                    let delta = abs(angle - direction.angleDegrees)
                        .truncatingRemainder(dividingBy: 360)
                    guard min(delta, 360 - delta) <= 22.5 else { return nil }
                    return (entry, radius)
                }
                .min { lhs, rhs in
                    lhs.1 != rhs.1 ? lhs.1 < rhs.1 : lhs.0.id < rhs.0.id
                }?.0
            return ProfileV3DirectionSlot(direction: direction, entry: match)
        }
    }

    /// Sets the text output of a direction slot, creating the canonical first
    /// ring entry when absent. `nil` removes the slot's entry. Returns the
    /// affected entry ID.
    @discardableResult
    public mutating func v3SetDirectionText(
        boardID: String,
        direction: ProfileV3Direction,
        text: String?
    ) throws -> String? {
        let slot = try v3ImmediateDirectionSlots(boardID: boardID)
            .first { $0.direction == direction }
        if let existing = slot?.entry {
            guard let text, !text.isEmpty else {
                try v3DeleteEntry(boardID: boardID, entryID: existing.id)
                return nil
            }
            try v3SetSimpleTextOutput(boardID: boardID, entryID: existing.id, text: text)
            return existing.id
        }
        guard let text, !text.isEmpty else { return nil }
        let entryID = try v3UniqueEntryID(boardID: boardID, base: "\(boardID).\(direction.rawValue)")
        try v3CreateEntry(
            boardID: boardID,
            id: entryID,
            rect: direction.defaultRect,
            resolver: Self.v3TextResolver(text)
        )
        return entryID
    }

    public func v3UniqueEntryID(boardID: String, base: String) throws -> String {
        let existing = Set(try v3BoardEntries(boardID: boardID).map(\.id))
        let trimmed = String(base.prefix(120))
        if !existing.contains(trimmed) { return trimmed }
        var index = 2
        while existing.contains("\(trimmed)-\(index)") { index += 1 }
        return "\(trimmed)-\(index)"
    }

    public func v3UniqueBoardID(base: String) throws -> String {
        let existing = Set(try v3BoardSummaries().map(\.id))
        let trimmed = String(base.prefix(120))
        if !existing.contains(trimmed) { return trimmed }
        var index = 2
        while existing.contains("\(trimmed)-\(index)") { index += 1 }
        return "\(trimmed)-\(index)"
    }
}

// MARK: - Canvas viewport / hit-testing / interaction (#69 §8.2–8.3)

public struct ProfileV3CanvasFrame: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    public func contains(x px: Double, y py: Double) -> Bool {
        px >= x && px < x + width && py >= y && py < y + height
    }

    /// Touch halo: grows to at least `minimum` around the same center.
    /// Semantic geometry is unchanged.
    public func expanded(toMinimum minimum: Double) -> ProfileV3CanvasFrame {
        let w = max(width, minimum)
        let h = max(height, minimum)
        return ProfileV3CanvasFrame(x: midX - w / 2, y: midY - h / 2, width: w, height: h)
    }
}

/// Explicit viewport state. It changes only on Board open, explicit
/// 全体表示, or an explicit pan/zoom — never as a side effect of editing.
public struct ProfileV3CanvasViewport: Equatable, Sendable {
    public static let atomicSizeRange: ClosedRange<Double> = 6...120

    /// Points per authored atom (half logical cell).
    public var atomicSize: Double
    /// Screen position of atom coordinate (0, 0).
    public var originX: Double
    public var originY: Double

    public init(atomicSize: Double, originX: Double, originY: Double) {
        self.atomicSize = atomicSize
        self.originX = originX
        self.originY = originY
    }

    public static func fitting(
        rects: [ProfileV3Rect],
        width: Double,
        height: Double,
        margin: Double = 16
    ) -> ProfileV3CanvasViewport {
        let minX = rects.map(\.x).min() ?? -6
        let minY = rects.map(\.y).min() ?? -6
        let maxX = rects.map(\.maxX).max() ?? 6
        let maxY = rects.map(\.maxY).max() ?? 6
        // Pad so empty neighbouring cells remain reachable for creation.
        let spanX = Double(max(maxX - minX + 2, 6))
        let spanY = Double(max(maxY - minY + 2, 6))
        let usableW = max(width - margin * 2, 1)
        let usableH = max(height - margin * 2, 1)
        let size = min(
            max(min(usableW / spanX, usableH / spanY), atomicSizeRange.lowerBound),
            atomicSizeRange.upperBound
        )
        let centerX = Double(minX + maxX) / 2
        let centerY = Double(minY + maxY) / 2
        return ProfileV3CanvasViewport(
            atomicSize: size,
            originX: width / 2 - centerX * size,
            originY: height / 2 - centerY * size
        )
    }

    public func frame(for rect: ProfileV3Rect) -> ProfileV3CanvasFrame {
        ProfileV3CanvasFrame(
            x: originX + Double(rect.x) * atomicSize,
            y: originY + Double(rect.y) * atomicSize,
            width: Double(rect.width) * atomicSize,
            height: Double(rect.height) * atomicSize
        )
    }

    public func atom(x: Double, y: Double) -> (x: Int, y: Int) {
        (Int(floor((x - originX) / atomicSize)), Int(floor((y - originY) / atomicSize)))
    }

    public func atomicDelta(_ points: Double) -> Int {
        Int((points / atomicSize).rounded())
    }

    public mutating func pan(dx: Double, dy: Double) {
        originX += dx
        originY += dy
    }

    /// Zooms around a fixed screen anchor.
    public mutating func zoom(by scale: Double, anchorX: Double, anchorY: Double) {
        guard scale.isFinite, scale > 0 else { return }
        let next = min(
            max(atomicSize * scale, Self.atomicSizeRange.lowerBound),
            Self.atomicSizeRange.upperBound
        )
        let applied = next / atomicSize
        originX = anchorX - (anchorX - originX) * applied
        originY = anchorY - (anchorY - originY) * applied
        atomicSize = next
    }
}

public enum ProfileV3CanvasTool: String, CaseIterable, Identifiable, Sendable {
    case select
    case create
    case pan

    public var id: String { rawValue }

    public var displayKey: ProfileV3DisplayKey {
        switch self {
        case .select: .modeSelect
        case .create: .modeCreate
        case .pan: .modePan
        }
    }
}

public enum ProfileV3CanvasHit: Equatable, Sendable {
    case resizeHandle(entryID: String)
    case entry(entryID: String)
    case empty(x: Int, y: Int)
}

/// One deterministic owner per touch-down, independent of view z-order.
public enum ProfileV3CanvasHitTester {
    public static let minimumTouchTarget: Double = 44
    public static let resizeHandleSize: Double = 44

    public static func resizeHandleFrame(
        for rect: ProfileV3Rect,
        viewport: ProfileV3CanvasViewport
    ) -> ProfileV3CanvasFrame {
        let frame = viewport.frame(for: rect)
        return ProfileV3CanvasFrame(
            x: frame.x + frame.width - resizeHandleSize / 2,
            y: frame.y + frame.height - resizeHandleSize / 2,
            width: resizeHandleSize,
            height: resizeHandleSize
        )
    }

    public static func hit(
        x: Double,
        y: Double,
        entries: [(id: String, rect: ProfileV3Rect)],
        selectedEntryID: String?,
        viewport: ProfileV3CanvasViewport
    ) -> ProfileV3CanvasHit {
        // 1. The selected entry's resize handle.
        if let selectedEntryID,
           let selected = entries.first(where: { $0.id == selectedEntryID }),
           resizeHandleFrame(for: selected.rect, viewport: viewport).contains(x: x, y: y) {
            return .resizeHandle(entryID: selectedEntryID)
        }

        // 2. Exact semantic rect (entries never overlap; ID breaks ties).
        if let exact = entries
            .filter({ viewport.frame(for: $0.rect).contains(x: x, y: y) })
            .min(by: { $0.id < $1.id }) {
            return .entry(entryID: exact.id)
        }

        // 3. Ergonomic halo for small entries: nearest center wins.
        let halo = entries.compactMap { item -> (String, Double)? in
            let frame = viewport.frame(for: item.rect)
            guard frame.expanded(toMinimum: minimumTouchTarget).contains(x: x, y: y) else {
                return nil
            }
            return (item.id, hypot(frame.midX - x, frame.midY - y))
        }
        if let nearest = halo.min(by: { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }) {
            return .entry(entryID: nearest.0)
        }

        let atom = viewport.atom(x: x, y: y)
        return .empty(x: atom.x, y: atom.y)
    }
}

/// Gesture-lifetime owner. Candidate rects derive from the rect captured at
/// touch-down plus the snapped cumulative translation, so the viewport and the
/// base rect never feed back into themselves while dragging.
public struct ProfileV3CanvasInteraction: Equatable, Sendable {
    public enum Operation: Equatable, Sendable {
        case none
        case move(entryID: String, startRect: ProfileV3Rect)
        case resize(entryID: String, startRect: ProfileV3Rect)
        case create(startX: Int, startY: Int)
        case pan(startViewport: ProfileV3CanvasViewport)
    }

    public let operation: Operation

    public init(operation: Operation) {
        self.operation = operation
    }

    public static func begin(
        hit: ProfileV3CanvasHit,
        tool: ProfileV3CanvasTool,
        entries: [(id: String, rect: ProfileV3Rect)],
        viewport: ProfileV3CanvasViewport
    ) -> ProfileV3CanvasInteraction {
        if tool == .pan {
            return .init(operation: .pan(startViewport: viewport))
        }
        switch hit {
        case .resizeHandle(let id):
            guard let rect = entries.first(where: { $0.id == id })?.rect else { break }
            return .init(operation: .resize(entryID: id, startRect: rect))
        case .entry(let id):
            guard let rect = entries.first(where: { $0.id == id })?.rect else { break }
            return .init(operation: .move(entryID: id, startRect: rect))
        case .empty(let x, let y):
            if tool == .create {
                return .init(operation: .create(startX: x, startY: y))
            }
        }
        return .init(operation: .none)
    }

    public var targetEntryID: String? {
        switch operation {
        case .move(let id, _), .resize(let id, _): id
        default: nil
        }
    }

    public func candidateRect(
        translationX: Double,
        translationY: Double,
        currentX: Double,
        currentY: Double,
        viewport: ProfileV3CanvasViewport
    ) -> ProfileV3Rect? {
        switch operation {
        case .move(_, let start):
            return ProfileV3Rect(
                x: start.x + viewport.atomicDelta(translationX),
                y: start.y + viewport.atomicDelta(translationY),
                width: start.width,
                height: start.height
            )
        case .resize(_, let start):
            return ProfileV3Rect(
                x: start.x,
                y: start.y,
                width: max(1, start.width + viewport.atomicDelta(translationX)),
                height: max(1, start.height + viewport.atomicDelta(translationY))
            )
        case .create(let startX, let startY):
            let end = viewport.atom(x: currentX, y: currentY)
            return ProfileV3Rect(
                x: min(startX, end.x),
                y: min(startY, end.y),
                width: abs(end.x - startX) + 1,
                height: abs(end.y - startY) + 1
            )
        case .none, .pan:
            return nil
        }
    }

    public func pannedViewport(translationX: Double, translationY: Double) -> ProfileV3CanvasViewport? {
        guard case .pan(var viewport) = operation else { return nil }
        viewport.pan(dx: translationX, dy: translationY)
        return viewport
    }
}

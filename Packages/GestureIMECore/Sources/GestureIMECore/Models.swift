import Foundation

public enum Direction8: String, Codable, CaseIterable, Hashable, Sendable {
    case n, ne, e, se, s, sw, w, nw

    public static let canonicalOrder: [Direction8] = [.n, .ne, .e, .se, .s, .sw, .w, .nw]

    public var centerDegrees: Double {
        switch self {
        case .e: 0
        case .se: 45
        case .s: 90
        case .sw: 135
        case .w: 180
        case .nw: 225
        case .n: 270
        case .ne: 315
        }
    }
}

public struct GestureToken: Codable, Hashable, Sendable {
    public var direction: Direction8
    public init(direction: Direction8) { self.direction = direction }
}

public struct GesturePath: Codable, Hashable, Sendable {
    public var tokens: [GestureToken]

    public init(_ tokens: [GestureToken] = []) { self.tokens = tokens }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.tokens = try container.decode([GestureToken].self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(tokens)
    }
}

public struct GesturePoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }

    public func distance(to other: GesturePoint) -> Double {
        hypot(other.x - x, other.y - y)
    }
}

public struct GestureSize: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
    public var minimumDimension: Double { min(width, height) }
}

public struct GesturePolicy: Codable, Equatable, Sendable {
    public var deadZone: Double
    public var stage1CommitDistance: Double
    public var stage2CommitDistance: Double
    public var angularHysteresisDegrees: Double
    public var maxDirectionalStages: Int

    public init(
        deadZone: Double,
        stage1CommitDistance: Double,
        stage2CommitDistance: Double,
        angularHysteresisDegrees: Double,
        maxDirectionalStages: Int
    ) {
        self.deadZone = deadZone
        self.stage1CommitDistance = stage1CommitDistance
        self.stage2CommitDistance = stage2CommitDistance
        self.angularHysteresisDegrees = angularHysteresisDegrees
        self.maxDirectionalStages = maxDirectionalStages
    }
}

public struct ActionInvocation: Codable, Equatable, Sendable {
    public var actionID: String
    public var arguments: [String: JSONValue]
    public init(actionID: String, arguments: [String: JSONValue]) {
        self.actionID = actionID
        self.arguments = arguments
    }
}

public struct BindingPresentation: Codable, Equatable, Sendable {
    public var text: String?
    public var accessibilityLabel: String?

    public init(text: String? = nil, accessibilityLabel: String? = nil) {
        self.text = text
        self.accessibilityLabel = accessibilityLabel
    }
}

public struct RepeatBehavior: Codable, Equatable, Sendable {
    public var intervalMs: Int
    public var actions: [ActionInvocation]

    public init(intervalMs: Int, actions: [ActionInvocation]) {
        self.intervalMs = intervalMs
        self.actions = actions
    }
}

public struct HoldBehavior: Codable, Equatable, Sendable {
    public var delayMs: Int
    public var onStart: [ActionInvocation]
    public var repeatBehavior: RepeatBehavior?
    public var suppressOnReleaseAfterStart: Bool

    public init(
        delayMs: Int,
        onStart: [ActionInvocation],
        repeatBehavior: RepeatBehavior? = nil,
        suppressOnReleaseAfterStart: Bool
    ) {
        self.delayMs = delayMs
        self.onStart = onStart
        self.repeatBehavior = repeatBehavior
        self.suppressOnReleaseAfterStart = suppressOnReleaseAfterStart
    }

    enum CodingKeys: String, CodingKey {
        case delayMs, onStart, repeatBehavior = "repeat", suppressOnReleaseAfterStart
    }
}

public struct BindingBehavior: Codable, Equatable, Sendable {
    public var presentation: BindingPresentation?
    public var onRelease: [ActionInvocation]
    public var hold: HoldBehavior?

    public init(
        presentation: BindingPresentation? = nil,
        onRelease: [ActionInvocation],
        hold: HoldBehavior? = nil
    ) {
        self.presentation = presentation
        self.onRelease = onRelease
        self.hold = hold
    }
}

public struct Binding: Codable, Equatable, Sendable {
    public var keyID: String
    public var path: GesturePath
    public var behavior: BindingBehavior

    public init(keyID: String, path: GesturePath, behavior: BindingBehavior) {
        self.keyID = keyID
        self.path = path
        self.behavior = behavior
    }
}

public struct BindingSet: Codable, Equatable, Sendable {
    public var id: String
    public var bindings: [Binding]

    public init(id: String, bindings: [Binding]) {
        self.id = id
        self.bindings = bindings
    }
}

public struct KeyDefinition: Codable, Equatable, Sendable {
    public var id: String
    public var presentation: BindingPresentation?
    public var role: String?

    public init(id: String, presentation: BindingPresentation? = nil, role: String? = nil) {
        self.id = id
        self.presentation = presentation
        self.role = role
    }
}

public struct LayoutPlacement: Codable, Equatable, Sendable {
    public var keyID: String
    public var row: Int
    public var column: Int
    public var width: Double?
    public var height: Double?

    public init(
        keyID: String,
        row: Int,
        column: Int,
        width: Double? = nil,
        height: Double? = nil
    ) {
        self.keyID = keyID
        self.row = row
        self.column = column
        self.width = width
        self.height = height
    }
}

public struct Layout: Codable, Equatable, Sendable {
    public var id: String
    public var placements: [LayoutPlacement]

    public init(id: String, placements: [LayoutPlacement]) {
        self.id = id
        self.placements = placements
    }
}

public struct Layer: Codable, Equatable, Sendable {
    public var id: String
    public var layoutRef: String
    public var bindingSetRef: String

    public init(id: String, layoutRef: String, bindingSetRef: String) {
        self.id = id
        self.layoutRef = layoutRef
        self.bindingSetRef = bindingSetRef
    }
}

public struct Macro: Codable, Equatable, Sendable {
    public var id: String
    public var actions: [ActionInvocation]

    public init(id: String, actions: [ActionInvocation]) {
        self.id = id
        self.actions = actions
    }
}

public struct ProfileBundle: Codable, Equatable, Sendable {
    public var schema: String
    public var id: String
    public var name: String
    public var version: Int
    public var gesturePolicy: GesturePolicy
    public var keyDefinitions: [KeyDefinition]
    public var layouts: [Layout]
    public var bindingSets: [BindingSet]
    public var layers: [Layer]
    public var macros: [Macro]
    public var theme: [String: JSONValue]?

    public init(
        schema: String,
        id: String,
        name: String,
        version: Int,
        gesturePolicy: GesturePolicy,
        keyDefinitions: [KeyDefinition],
        layouts: [Layout],
        bindingSets: [BindingSet],
        layers: [Layer],
        macros: [Macro],
        theme: [String: JSONValue]? = nil
    ) {
        self.schema = schema
        self.id = id
        self.name = name
        self.version = version
        self.gesturePolicy = gesturePolicy
        self.keyDefinitions = keyDefinitions
        self.layouts = layouts
        self.bindingSets = bindingSets
        self.layers = layers
        self.macros = macros
        self.theme = theme
    }
}

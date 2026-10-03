import Foundation

public extension GesturePolicy {
    init(
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

public extension BindingPresentation {
    init(text: String? = nil, accessibilityLabel: String? = nil) {
        self.text = text
        self.accessibilityLabel = accessibilityLabel
    }
}

public extension RepeatBehavior {
    init(intervalMs: Int, actions: [ActionInvocation]) {
        self.intervalMs = intervalMs
        self.actions = actions
    }
}

public extension HoldBehavior {
    init(
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
}

public extension BindingBehavior {
    init(
        presentation: BindingPresentation? = nil,
        onRelease: [ActionInvocation],
        hold: HoldBehavior? = nil
    ) {
        self.presentation = presentation
        self.onRelease = onRelease
        self.hold = hold
    }
}

public extension Binding {
    init(keyID: String, path: GesturePath, behavior: BindingBehavior) {
        self.keyID = keyID
        self.path = path
        self.behavior = behavior
    }
}

public extension BindingSet {
    init(id: String, bindings: [Binding]) {
        self.id = id
        self.bindings = bindings
    }
}

public extension KeyDefinition {
    init(id: String, presentation: BindingPresentation? = nil, role: String? = nil) {
        self.id = id
        self.presentation = presentation
        self.role = role
    }
}

public extension LayoutPlacement {
    init(
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

public extension Layout {
    init(id: String, placements: [LayoutPlacement]) {
        self.id = id
        self.placements = placements
    }
}

public extension Layer {
    init(id: String, layoutRef: String, bindingSetRef: String) {
        self.id = id
        self.layoutRef = layoutRef
        self.bindingSetRef = bindingSetRef
    }
}

public extension Macro {
    init(id: String, actions: [ActionInvocation]) {
        self.id = id
        self.actions = actions
    }
}

public extension ProfileBundle {
    init(
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

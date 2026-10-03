import Foundation

public enum GestureTerminal: String, Equatable, Sendable {
    case committed, cancelled, invalidated
}

public struct GestureSessionResult: Equatable, Sendable {
    public var terminal: GestureTerminal
    public var path: GesturePath
    public var dispatchedActions: [ActionInvocation]
}

public struct GestureSession: @unchecked Sendable {
    public let keyID: String
    public let profileRevision: String
    public let policy: GesturePolicy
    public let keySize: GestureSize

    public private(set) var path = GesturePath()
    public private(set) var anchor: GesturePoint
    public private(set) var candidateDirection: Direction8?
    public private(set) var committedDirectionalStages = 0
    public private(set) var terminal: GestureTerminal?
    public private(set) var dispatchedActions: [ActionInvocation] = []
    public private(set) var commitAnchors: [GesturePoint] = []

    private var currentNode: BindingTrieNode
    private var currentTimeMs: Int
    private var holdDueMs: Int?
    private var repeatDueMs: Int?
    private var holdStarted = false
    private var holdLocked = false

    public init(keyID: String, profileRevision: String, trie: BindingTrie, policy: GesturePolicy, keySize: GestureSize, touchDown: GesturePoint, atMs: Int = 0) {
        self.keyID = keyID
        self.profileRevision = profileRevision
        self.policy = policy
        self.keySize = keySize
        self.anchor = touchDown
        self.currentNode = trie.root
        self.currentTimeMs = atMs
        scheduleCurrentHold(atMs: atMs)
    }

    public var eligibleDirections: Set<Direction8> { currentNode.eligibleDirections }

    public mutating func move(to point: GesturePoint, atMs: Int? = nil) {
        guard terminal == nil else { return }
        if let atMs { advanceTime(toMs: atMs) }
        guard !holdLocked, committedDirectionalStages < policy.maxDirectionalStages else { return }
        let scale = keySize.minimumDimension
        guard scale.isFinite, scale > 0 else { return }
        let dx = point.x - anchor.x
        let dy = point.y - anchor.y
        let normalized = hypot(dx, dy) / scale
        guard normalized >= policy.deadZone, !currentNode.children.isEmpty else {
            candidateDirection = nil
            return
        }
        let angle = Self.angleDegrees(dx: dx, dy: dy)
        let nearest = currentNode.children.keys.min { lhs, rhs in
            let ld = Self.angularDistance(angle, lhs.centerDegrees)
            let rd = Self.angularDistance(angle, rhs.centerDegrees)
            if ld == rd { return Self.rank(lhs) < Self.rank(rhs) }
            return ld < rd
        }
        guard let nearest else { return }
        if let current = candidateDirection, current != nearest {
            let nd = Self.angularDistance(angle, nearest.centerDegrees)
            let cd = Self.angularDistance(angle, current.centerDegrees)
            if nd + policy.angularHysteresisDegrees < cd { candidateDirection = nearest }
        } else if candidateDirection == nil {
            candidateDirection = nearest
        }

        let threshold = committedDirectionalStages == 0 ? policy.stage1CommitDistance : policy.stage2CommitDistance
        guard normalized >= threshold, let direction = candidateDirection, let child = currentNode.children[direction] else { return }
        cancelHoldSchedule()
        path.tokens.append(GestureToken(direction: direction))
        currentNode = child
        committedDirectionalStages += 1
        anchor = point
        commitAnchors.append(point)
        candidateDirection = nil
        scheduleCurrentHold(atMs: currentTimeMs)
    }

    public mutating func advanceTime(toMs target: Int) {
        guard terminal == nil, target >= currentTimeMs else { return }
        if let hold = currentNode.behavior?.hold, let due = holdDueMs, !holdStarted, due <= target {
            dispatchedActions.append(contentsOf: hold.onStart)
            holdStarted = true
            holdLocked = true
            candidateDirection = nil
            if let repeating = hold.repeatBehavior { repeatDueMs = due + repeating.intervalMs }
        }
        if holdStarted, let repeating = currentNode.behavior?.hold?.repeatBehavior {
            while let due = repeatDueMs, due <= target, terminal == nil {
                dispatchedActions.append(contentsOf: repeating.actions)
                repeatDueMs = due + repeating.intervalMs
            }
        }
        currentTimeMs = target
    }

    public mutating func touchUp(atMs: Int? = nil) -> GestureSessionResult {
        if let atMs { advanceTime(toMs: atMs) }
        guard terminal == nil else { return result() }
        if let behavior = currentNode.behavior {
            let suppress = holdStarted && (behavior.hold?.suppressOnReleaseAfterStart ?? false)
            if !suppress { dispatchedActions.append(contentsOf: behavior.onRelease) }
        }
        terminal = .committed
        cancelHoldSchedule()
        return result()
    }

    public mutating func cancel(atMs: Int? = nil) -> GestureSessionResult {
        if let atMs { advanceTime(toMs: atMs) }
        guard terminal == nil else { return result() }
        terminal = .cancelled
        cancelHoldSchedule()
        return result()
    }

    public mutating func invalidate(atMs: Int? = nil) -> GestureSessionResult {
        if let atMs { advanceTime(toMs: atMs) }
        guard terminal == nil else { return result() }
        terminal = .invalidated
        cancelHoldSchedule()
        return result()
    }

    private mutating func scheduleCurrentHold(atMs: Int) {
        holdStarted = false
        holdLocked = false
        repeatDueMs = nil
        if let hold = currentNode.behavior?.hold { holdDueMs = atMs + hold.delayMs }
        else { holdDueMs = nil }
    }

    private mutating func cancelHoldSchedule() {
        holdDueMs = nil
        repeatDueMs = nil
    }

    private func result() -> GestureSessionResult {
        GestureSessionResult(terminal: terminal ?? .cancelled, path: path, dispatchedActions: dispatchedActions)
    }

    private static func rank(_ direction: Direction8) -> Int {
        Direction8.canonicalOrder.firstIndex(of: direction) ?? Int.max
    }

    private static func angleDegrees(dx: Double, dy: Double) -> Double {
        let raw = atan2(dy, dx) * 180 / .pi
        return raw < 0 ? raw + 360 : raw
    }

    private static func angularDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let delta = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(delta, 360 - delta)
    }
}

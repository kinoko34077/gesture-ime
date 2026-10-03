import Foundation
import SwiftUI
import GestureIMECore

@MainActor
final class HarnessViewModel: ObservableObject {
    enum ProfileMode: String, CaseIterable, Identifiable {
        case cardinal = "4-way"
        case extended = "Diagonal + 2-stage"
        var id: String { rawValue }
    }

    enum TrialIntent: String, CaseIterable, Identifiable {
        case singleStage = "Single-stage trial"
        case twoStage = "Two-stage trial"
        var id: String { rawValue }
    }

    @Published var mode: ProfileMode = .extended
    @Published var trialIntent: TrialIntent = .singleStage
    @Published var deadZone = 0.15
    @Published var stage1Distance = 0.40
    @Published var stage2Distance = 0.40
    @Published var hysteresis = 8.0

    @Published private(set) var trace: [CGPoint] = []
    @Published private(set) var anchor: CGPoint?
    @Published private(set) var commitAnchors: [CGPoint] = []
    @Published private(set) var pathText = "[]"
    @Published private(set) var candidateText = "—"
    @Published private(set) var eligibleDirections: [Direction8] = []
    @Published private(set) var actionLog: [String] = []
    @Published private(set) var terminalText = "idle"

    @Published private(set) var trials = 0
    @Published private(set) var stage2Observed = 0
    @Published private(set) var accidentalStage2 = 0
    @Published private(set) var deliberateStage2Success = 0

    private var session: GestureSession?
    private var tracking = false

    var accidentalRateText: String {
        guard trials > 0 else { return "—" }
        return String(format: "%.1f%%", Double(accidentalStage2) * 100 / Double(trials))
    }

    var stage2RateText: String {
        guard trials > 0 else { return "—" }
        return String(format: "%.1f%%", Double(stage2Observed) * 100 / Double(trials))
    }

    func beginIfNeeded(start: CGPoint, keySize: CGSize) {
        guard !tracking else { return }
        tracking = true
        trace = [start]
        actionLog = []
        terminalText = "tracking"

        do {
            let trie = try makeTrie()
            let policy = GesturePolicy(
                deadZone: deadZone,
                stage1CommitDistance: max(stage1Distance, deadZone),
                stage2CommitDistance: max(stage2Distance, deadZone),
                angularHysteresisDegrees: hysteresis,
                maxDirectionalStages: 2
            )
            session = GestureSession(
                keyID: "kana.a",
                profileRevision: mode.rawValue,
                trie: trie,
                policy: policy,
                keySize: GestureSize(width: Double(keySize.width), height: Double(keySize.height)),
                touchDown: GesturePoint(x: Double(start.x), y: Double(start.y))
            )
            refresh()
        } catch {
            actionLog = ["setup error: \(error)"]
            tracking = false
        }
    }

    func move(to point: CGPoint) {
        guard tracking, var active = session else { return }
        trace.append(point)
        active.move(to: GesturePoint(x: Double(point.x), y: Double(point.y)))
        session = active
        refresh()
    }

    func end(at point: CGPoint) {
        guard tracking, var active = session else { return }
        trace.append(point)
        active.move(to: GesturePoint(x: Double(point.x), y: Double(point.y)))
        let result = active.touchUp()
        session = active
        tracking = false
        record(result)
        refresh()
    }

    func resetVisuals() {
        tracking = false
        session = nil
        trace = []
        anchor = nil
        commitAnchors = []
        pathText = "[]"
        candidateText = "—"
        eligibleDirections = []
        actionLog = []
        terminalText = "idle"
    }

    func resetMetrics() {
        trials = 0
        stage2Observed = 0
        accidentalStage2 = 0
        deliberateStage2Success = 0
    }

    private func record(_ result: GestureSessionResult) {
        trials += 1
        if result.path.tokens.count >= 2 {
            stage2Observed += 1
            if trialIntent == .singleStage { accidentalStage2 += 1 }
            if trialIntent == .twoStage { deliberateStage2Success += 1 }
        }
        terminalText = result.terminal.rawValue
        actionLog = result.dispatchedActions.map(Self.actionSummary)
    }

    private func refresh() {
        guard let active = session else { return }
        anchor = CGPoint(x: CGFloat(active.anchor.x), y: CGFloat(active.anchor.y))
        commitAnchors = active.commitAnchors.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        pathText = "[" + active.path.tokens.map { $0.direction.rawValue.uppercased() }.joined(separator: ",") + "]"
        candidateText = active.candidateDirection?.rawValue.uppercased() ?? "—"
        eligibleDirections = Direction8.canonicalOrder.filter(active.eligibleDirections.contains)
        if let terminal = active.terminal {
            terminalText = terminal.rawValue
        }
    }

    private func makeTrie() throws -> BindingTrie {
        var bindings: [GestureIMECore.Binding] = [
            binding([], label: "tap"),
            binding([.w], label: "W"),
            binding([.n], label: "N"),
            binding([.e], label: "E"),
            binding([.s], label: "S")
        ]
        if mode == .extended {
            bindings += [
                binding([.ne], label: "NE"),
                binding([.e, .n], label: "E,N"),
                binding([.e, .e], label: "E,E")
            ]
        }
        return try BindingTrieCompiler.compile(
            BindingSet(id: "harness.bindings", bindings: bindings),
            keyID: "kana.a"
        )
    }

    private func binding(_ directions: [Direction8], label: String) -> GestureIMECore.Binding {
        GestureIMECore.Binding(
            keyID: "kana.a",
            path: GesturePath(directions.map { GestureToken(direction: $0) }),
            behavior: BindingBehavior(
                presentation: BindingPresentation(text: label, accessibilityLabel: label),
                onRelease: [ActionInvocation(actionID: "text.insert", arguments: ["text": .string(label)])],
                hold: nil
            )
        )
    }

    private static func actionSummary(_ action: ActionInvocation) -> String {
        if action.actionID == "text.insert", let text = action.arguments["text"]?.stringValue {
            return "\(action.actionID)(\(text))"
        }
        return action.actionID
    }
}

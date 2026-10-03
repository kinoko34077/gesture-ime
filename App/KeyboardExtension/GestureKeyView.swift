import UIKit
import GestureIMECore

@MainActor
protocol GestureKeyViewDelegate: AnyObject {
    func gestureKeyViewShouldBegin(_ keyView: GestureKeyView) -> Bool
    func gestureKeyViewDidEndTouch(_ keyView: GestureKeyView)
    func gestureKeyView(_ keyView: GestureKeyView, didDispatch actions: [ActionInvocation])
}

@MainActor
final class GestureKeyView: UIView {
    weak var delegate: GestureKeyViewDelegate?

    private let runtime: KeyboardKeyRuntime
    private let profileRevision: String
    private let policyStore: GesturePolicyStore

    private let titleLabel = UILabel()
    private var directionLabels: [Direction8: UILabel] = [:]

    private var session: GestureSession?
    private var sessionStart: TimeInterval = 0
    private var ownsNativeTouch = false

    private var normalBackgroundColor: UIColor {
        runtime.role == "control" ? .secondarySystemFill : .systemBackground
    }

    init(runtime: KeyboardKeyRuntime, profileRevision: String, policyStore: GesturePolicyStore) {
        self.runtime = runtime
        self.profileRevision = profileRevision
        self.policyStore = policyStore
        super.init(frame: .zero)

        isMultipleTouchEnabled = false
        layer.cornerRadius = 10
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.withAlphaComponent(0.45).cgColor
        backgroundColor = normalBackgroundColor

        titleLabel.text = runtime.title
        titleLabel.textAlignment = .center
        titleLabel.font = .systemFont(
            ofSize: runtime.role == "control" ? 18 : 29,
            weight: runtime.role == "control" ? .regular : .medium
        )
        titleLabel.textColor = .label
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.6
        addSubview(titleLabel)

        for direction in [Direction8.w, .n, .e, .s] {
            guard let text = oneStageLabel(direction), !text.isEmpty else { continue }
            let label = UILabel()
            label.text = text
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 13, weight: .regular)
            label.textColor = .secondaryLabel
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.7
            addSubview(label)
            directionLabels[direction] = label
        }

        accessibilityLabel = runtime.title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let centerWidth = bounds.width * 0.52
        let centerHeight = min(bounds.height * 0.56, 42)
        titleLabel.frame = CGRect(
            x: (bounds.width - centerWidth) / 2,
            y: (bounds.height - centerHeight) / 2,
            width: centerWidth,
            height: centerHeight
        )

        let hintWidth = max(24, bounds.width * 0.28)
        let hintHeight: CGFloat = 20

        directionLabels[.n]?.frame = CGRect(
            x: (bounds.width - hintWidth) / 2,
            y: 3,
            width: hintWidth,
            height: hintHeight
        )
        directionLabels[.s]?.frame = CGRect(
            x: (bounds.width - hintWidth) / 2,
            y: bounds.height - hintHeight - 3,
            width: hintWidth,
            height: hintHeight
        )
        directionLabels[.w]?.frame = CGRect(
            x: 3,
            y: (bounds.height - hintHeight) / 2,
            width: hintWidth,
            height: hintHeight
        )
        directionLabels[.e]?.frame = CGRect(
            x: bounds.width - hintWidth - 3,
            y: (bounds.height - hintHeight) / 2,
            width: hintWidth,
            height: hintHeight
        )
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touches.count == 1, let touch = touches.first else { return }
        ownsNativeTouch = true
        guard delegate?.gestureKeyViewShouldBegin(self) ?? true else {
            resetVisualState()
            return
        }

        let point = touch.location(in: self)
        sessionStart = touch.timestamp
        session = GestureSession(
            keyID: runtime.id,
            profileRevision: profileRevision,
            trie: runtime.trie,
            policy: policyStore.policy,
            keySize: GestureSize(width: Double(bounds.width), height: Double(bounds.height)),
            touchDown: GesturePoint(x: Double(point.x), y: Double(point.y)),
            atMs: 0
        )
        backgroundColor = .tertiarySystemFill
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard var active = session, let touch = touches.first else { return }
        let point = touch.location(in: self)
        active.move(
            to: GesturePoint(x: Double(point.x), y: Double(point.y)),
            atMs: elapsedMs(touch)
        )
        session = active
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer { finishNativeTouch() }
        guard var active = session, let touch = touches.first else {
            resetVisualState()
            return
        }

        let point = touch.location(in: self)
        active.move(
            to: GesturePoint(x: Double(point.x), y: Double(point.y)),
            atMs: elapsedMs(touch)
        )
        let result = active.touchUp(atMs: elapsedMs(touch))
        session = nil
        resetVisualState()
        delegate?.gestureKeyView(self, didDispatch: result.dispatchedActions)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelCurrentGesture()
        finishNativeTouch()
    }

    func cancelCurrentGesture() {
        if var active = session {
            _ = active.cancel()
        }
        session = nil
        resetVisualState()
    }

    private func oneStageLabel(_ direction: Direction8) -> String? {
        runtime.trie
            .node(for: GesturePath([GestureToken(direction: direction)]))?
            .behavior?
            .presentation?
            .text
    }

    private func finishNativeTouch() {
        if ownsNativeTouch {
            ownsNativeTouch = false
            delegate?.gestureKeyViewDidEndTouch(self)
        }
    }

    private func elapsedMs(_ touch: UITouch) -> Int {
        max(0, Int((touch.timestamp - sessionStart) * 1000))
    }

    private func resetVisualState() {
        backgroundColor = normalBackgroundColor
    }
}

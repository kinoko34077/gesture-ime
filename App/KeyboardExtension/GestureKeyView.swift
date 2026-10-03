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
    private let hintLabel = UILabel()

    private var session: GestureSession?
    private var sessionStart: TimeInterval = 0
    private var ownsNativeTouch = false

    init(runtime: KeyboardKeyRuntime, profileRevision: String, policyStore: GesturePolicyStore) {
        self.runtime = runtime
        self.profileRevision = profileRevision
        self.policyStore = policyStore
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        isMultipleTouchEnabled = false
        layer.cornerRadius = 8
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.cgColor
        backgroundColor = .secondarySystemBackground

        titleLabel.text = runtime.title
        titleLabel.textAlignment = .center
        titleLabel.font = .systemFont(ofSize: 20, weight: .medium)

        hintLabel.textAlignment = .center
        hintLabel.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
        hintLabel.textColor = .secondaryLabel
        hintLabel.numberOfLines = 1

        let stack = UIStackView(arrangedSubviews: [titleLabel, hintLabel])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        accessibilityLabel = runtime.title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        refreshHint()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard var active = session, let touch = touches.first else { return }
        let point = touch.location(in: self)
        active.move(
            to: GesturePoint(x: Double(point.x), y: Double(point.y)),
            atMs: elapsedMs(touch)
        )
        session = active
        refreshHint()
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

    private func finishNativeTouch() {
        if ownsNativeTouch {
            ownsNativeTouch = false
            delegate?.gestureKeyViewDidEndTouch(self)
        }
    }

    private func elapsedMs(_ touch: UITouch) -> Int {
        max(0, Int((touch.timestamp - sessionStart) * 1000))
    }

    private func refreshHint() {
        guard let session else {
            hintLabel.text = nil
            return
        }
        let path = session.path.tokens.map { $0.direction.rawValue.uppercased() }.joined(separator: ",")
        let eligible = Direction8.canonicalOrder
            .filter(session.eligibleDirections.contains)
            .map { $0.rawValue.uppercased() }
            .joined(separator: " ")
        hintLabel.text = path.isEmpty ? eligible : "[\(path)] \(eligible)"
    }

    private func resetVisualState() {
        backgroundColor = .secondarySystemBackground
        hintLabel.text = nil
    }
}

import UIKit

@MainActor
protocol GestureKeyViewDelegate: AnyObject {
    func gestureKeyViewShouldBegin(_ keyView: GestureKeyView) -> Bool
    func gestureKeyViewDidEndTouch(_ keyView: GestureKeyView)
    func gestureKeyView(_ keyView: GestureKeyView, didDispatch actions: [FfiActionInvocation])
}

@MainActor
final class GestureKeyView: UIView {
    weak var delegate: GestureKeyViewDelegate?

    private let runtime: KeyboardKeyRuntime
    private let sharedRuntime: IOSSharedGestureRuntimeAdapter
    private let profileRevision: String
    private let policyStore: GesturePolicyStore

    private let titleLabel = UILabel()
    private var directionLabels: [String: UILabel] = [:]

    private var session: IOSSharedGestureSessionAdapter?
    private var sessionStart: TimeInterval = 0
    private var ownsNativeTouch = false

    private var normalBackgroundColor: UIColor {
        runtime.role == "control" ? .secondarySystemFill : .systemBackground
    }

    init(
        runtime: KeyboardKeyRuntime,
        sharedRuntime: IOSSharedGestureRuntimeAdapter,
        profileRevision: String,
        policyStore: GesturePolicyStore
    ) {
        self.runtime = runtime
        self.sharedRuntime = sharedRuntime
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

        for direction in ["w", "n", "e", "s"] {
            guard let text = runtime.firstStagePresentation[direction], !text.isEmpty else { continue }
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

        directionLabels["n"]?.frame = CGRect(
            x: (bounds.width - hintWidth) / 2,
            y: 3,
            width: hintWidth,
            height: hintHeight
        )
        directionLabels["s"]?.frame = CGRect(
            x: (bounds.width - hintWidth) / 2,
            y: bounds.height - hintHeight - 3,
            width: hintWidth,
            height: hintHeight
        )
        directionLabels["w"]?.frame = CGRect(
            x: 3,
            y: (bounds.height - hintHeight) / 2,
            width: hintWidth,
            height: hintHeight
        )
        directionLabels["e"]?.frame = CGRect(
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

        do {
            session = try sharedRuntime.beginSession(
                keyID: runtime.id,
                keyWidth: Double(bounds.width),
                keyHeight: Double(bounds.height),
                touchX: Double(point.x),
                touchY: Double(point.y),
                atMs: 0,
                policyOverride: policyStore.policy
            )
            backgroundColor = .tertiarySystemFill
        } catch {
            session = nil
            resetVisualState()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let active = session, let touch = touches.first else { return }
        let point = touch.location(in: self)
        do {
            _ = try active.move(
                x: Double(point.x),
                y: Double(point.y),
                atMs: elapsedMs(touch)
            )
        } catch {
            _ = try? active.cancel(atMs: elapsedMs(touch))
            session = nil
            resetVisualState()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer { finishNativeTouch() }
        guard let active = session, let touch = touches.first else {
            resetVisualState()
            return
        }

        let point = touch.location(in: self)
        let atMs = elapsedMs(touch)

        do {
            _ = try active.move(
                x: Double(point.x),
                y: Double(point.y),
                atMs: atMs
            )
            let result = try active.touchUp(atMs: atMs)
            session = nil
            resetVisualState()
            delegate?.gestureKeyView(self, didDispatch: result.dispatchedActions)
        } catch {
            _ = try? active.cancel(atMs: atMs)
            session = nil
            resetVisualState()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelCurrentGesture()
        finishNativeTouch()
    }

    func cancelCurrentGesture() {
        if let active = session {
            _ = try? active.cancel()
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

    private func elapsedMs(_ touch: UITouch) -> Int64 {
        max(0, Int64((touch.timestamp - sessionStart) * 1000))
    }

    private func resetVisualState() {
        backgroundColor = normalBackgroundColor
    }
}

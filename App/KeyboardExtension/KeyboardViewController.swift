import UIKit
import GestureIMECore

@MainActor
final class KeyboardViewController: UIInputViewController, GestureKeyViewDelegate {
    private let keyboardStack = UIStackView()
    private var tuningPanel: TuningPanelView?
    private var heightConstraint: NSLayoutConstraint?

    private var layoutRuntime: KeyboardLayoutRuntime?
    private var policyStore: GesturePolicyStore?
    private var keyViews: [ObjectIdentifier: GestureKeyView] = [:]
    private var touchingKeys = Set<ObjectIdentifier>()
    private var blockedByMultitouch = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        keyboardStack.axis = .vertical
        keyboardStack.spacing = 5
        keyboardStack.distribution = .fillEqually
        keyboardStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardStack)

        do {
            let profile = try BuiltInProfileLoader.load()
            let runtime = try KeyboardLayoutRuntime.compile(profile: profile)
            let store = GesturePolicyStore(defaultPolicy: runtime.defaultPolicy)
            layoutRuntime = runtime
            policyStore = store
            installKeyboard(runtime: runtime, store: store)
        } catch {
            installError(String(describing: error))
        }

        heightConstraint = view.heightAnchor.constraint(equalToConstant: 300)
        heightConstraint?.priority = .defaultHigh

        NSLayoutConstraint.activate([
            keyboardStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 5),
            keyboardStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -5),
            keyboardStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),
            keyboardStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -5),
            heightConstraint!
        ])
    }

    private func installKeyboard(runtime: KeyboardLayoutRuntime, store: GesturePolicyStore) {
        for row in runtime.rows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 5
            rowStack.distribution = .fillEqually

            for keyRuntime in row {
                let key = GestureKeyView(
                    runtime: keyRuntime,
                    profileRevision: runtime.profileRevision,
                    policyStore: store
                )
                key.delegate = self
                keyViews[ObjectIdentifier(key)] = key
                rowStack.addArrangedSubview(key)
            }
            keyboardStack.addArrangedSubview(rowStack)
        }
    }

    private func installError(_ message: String) {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 12)
        label.text = "Profile load failed\n\(message)"
        keyboardStack.addArrangedSubview(label)
    }

    func gestureKeyViewShouldBegin(_ keyView: GestureKeyView) -> Bool {
        let id = ObjectIdentifier(keyView)
        touchingKeys.insert(id)

        guard touchingKeys.count == 1, !blockedByMultitouch else {
            blockedByMultitouch = true
            for view in keyViews.values {
                view.cancelCurrentGesture()
            }
            return false
        }
        return true
    }

    func gestureKeyViewDidEndTouch(_ keyView: GestureKeyView) {
        touchingKeys.remove(ObjectIdentifier(keyView))
        if touchingKeys.isEmpty {
            blockedByMultitouch = false
        }
    }

    func gestureKeyView(_ keyView: GestureKeyView, didDispatch actions: [ActionInvocation]) {
        guard !blockedByMultitouch else { return }
        for action in actions {
            dispatch(action)
        }
    }

    private func dispatch(_ action: ActionInvocation) {
        switch action.actionID {
        case "text.insert", "text.directInsert":
            if let text = action.arguments["text"]?.stringValue {
                textDocumentProxy.insertText(text)
            }

        case "edit.delete":
            if let count = action.arguments["count"]?.intValue, count > 0 {
                for _ in 0..<count {
                    textDocumentProxy.deleteBackward()
                }
            }

        case "cursor.move":
            if let offset = action.arguments["offset"]?.intValue {
                textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
            }

        case "system.nextKeyboard":
            advanceToNextInputMode()

        case "system.dismissKeyboard":
            dismissKeyboard()

        case "panel.open":
            if action.arguments["panel"]?.stringValue == "tuning" {
                showTuning()
            }

        default:
            break
        }
    }

    private func showTuning() {
        guard tuningPanel == nil, let policyStore else { return }
        keyboardStack.isHidden = true

        let panel = TuningPanelView(store: policyStore)
        panel.onClose = { [weak self] in self?.hideTuning() }
        view.addSubview(panel)
        tuningPanel = panel

        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.topAnchor.constraint(equalTo: view.topAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func hideTuning() {
        tuningPanel?.removeFromSuperview()
        tuningPanel = nil
        keyboardStack.isHidden = false
    }
}

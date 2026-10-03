import UIKit
import GestureIMECore

@MainActor
final class KeyboardViewController: UIInputViewController, GestureKeyViewDelegate {
    private let policyStore = GesturePolicyStore.shared
    private let keyboardStack = UIStackView()
    private var tuningPanel: TuningPanelView?
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        keyboardStack.axis = .vertical
        keyboardStack.spacing = 5
        keyboardStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardStack)

        for row in BuiltInJapaneseProfile.kanaRows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 5
            rowStack.distribution = .fillEqually

            for spec in row {
                let key = GestureKeyView(spec: spec, policyStore: policyStore)
                key.delegate = self
                rowStack.addArrangedSubview(key)
            }
            keyboardStack.addArrangedSubview(rowStack)
        }

        let settingsButton = UIButton(type: .system)
        settingsButton.setTitle("⚙︎ 感度設定", for: .normal)
        settingsButton.titleLabel?.font = .systemFont(ofSize: 13)
        settingsButton.addAction(UIAction { [weak self] _ in self?.showTuning() }, for: .touchUpInside)
        keyboardStack.addArrangedSubview(settingsButton)

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

    func gestureKeyView(_ keyView: GestureKeyView, didDispatch actions: [ActionInvocation]) {
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
                for _ in 0..<count { textDocumentProxy.deleteBackward() }
            }

        case "cursor.move":
            if let offset = action.arguments["offset"]?.intValue {
                textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
            }

        case "system.nextKeyboard":
            advanceToNextInputMode()

        case "system.dismissKeyboard":
            dismissKeyboard()

        default:
            break
        }
    }

    private func showTuning() {
        guard tuningPanel == nil else { return }
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

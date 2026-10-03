import UIKit
import GestureIMECore

@MainActor
final class KeyboardViewController: UIInputViewController, GestureKeyViewDelegate {
    private let candidateBar = CandidateBarView()
    private let keyboardGrid = KeyboardGridView()
    private var tuningPanel: TuningPanelView?
    private var heightConstraint: NSLayoutConstraint?

    private var layoutRuntime: KeyboardLayoutRuntime?
    private var policyStore: GesturePolicyStore?
    private var composition: AzooKeyCompositionBridge?
    private var keyViews: [ObjectIdentifier: GestureKeyView] = [:]
    private var touchingKeys = Set<ObjectIdentifier>()
    private var blockedByMultitouch = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        candidateBar.translatesAutoresizingMaskIntoConstraints = false
        keyboardGrid.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(candidateBar)
        view.addSubview(keyboardGrid)

        let composition = AzooKeyCompositionBridge(proxy: textDocumentProxy)
        composition.onCandidatesChanged = { [weak self] snapshots in
            self?.candidateBar.render(
                candidates: snapshots.map(\.text),
                selectedIndex: snapshots.first(where: \.selected)?.index
            )
        }
        candidateBar.onCandidateSelected = { [weak composition] index in
            composition?.selectCandidate(at: index)
        }
        self.composition = composition

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

        heightConstraint = view.heightAnchor.constraint(equalToConstant: 344)
        heightConstraint?.priority = .defaultHigh

        NSLayoutConstraint.activate([
            candidateBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 5),
            candidateBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -5),
            candidateBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            candidateBar.heightAnchor.constraint(equalToConstant: 44),

            keyboardGrid.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 5),
            keyboardGrid.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -5),
            keyboardGrid.topAnchor.constraint(equalTo: candidateBar.bottomAnchor, constant: 4),
            keyboardGrid.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -5),

            heightConstraint!
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        composition?.setTextDocumentProxy(textDocumentProxy)
    }

    override func viewWillDisappear(_ animated: Bool) {
        composition?.close()
        super.viewWillDisappear(animated)
    }

    private func installKeyboard(runtime: KeyboardLayoutRuntime, store: GesturePolicyStore) {
        var items: [KeyboardGridView.Item] = []

        for keyRuntime in runtime.keys {
            let key = GestureKeyView(
                runtime: keyRuntime,
                profileRevision: runtime.profileRevision,
                policyStore: store
            )
            key.delegate = self
            keyViews[ObjectIdentifier(key)] = key

            items.append(
                KeyboardGridView.Item(
                    view: key,
                    row: keyRuntime.row,
                    column: keyRuntime.column,
                    width: keyRuntime.width,
                    height: keyRuntime.height
                )
            )
        }

        keyboardGrid.install(
            items,
            rowCount: runtime.rowCount,
            columnCount: runtime.columnCount
        )
    }

    private func installError(_ message: String) {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 12)
        label.text = "Profile load failed\n\(message)"
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12)
        ])
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
        case "text.insert":
            if let text = action.arguments["text"]?.stringValue {
                composition?.insert(text)
            }

        case "text.directInsert":
            if let text = action.arguments["text"]?.stringValue {
                composition?.directInsert(text)
            }

        case "edit.delete":
            if let count = action.arguments["count"]?.intValue, count > 0 {
                composition?.deleteBackward(count: count)
            }

        case "cursor.move":
            if let offset = action.arguments["offset"]?.intValue {
                composition?.moveCursor(offset)
            }

        case "conversion.commit":
            composition?.commitSelectionOrRaw()

        case "conversion.selectCandidate":
            if let index = action.arguments["index"]?.intValue {
                composition?.selectCandidate(at: index)
            }

        case "system.nextKeyboard":
            composition?.commitSelectionOrRaw()
            advanceToNextInputMode()

        case "system.dismissKeyboard":
            composition?.commitSelectionOrRaw()
            dismissKeyboard()

        case "panel.open":
            guard let panel = action.arguments["panel"]?.stringValue else { return }
            if panel == "tuning" {
                showTuning()
            } else {
                // Mode/emoji/symbol panels are intentionally routed through
                // the azooKey product integration seam rather than redefined
                // in Gesture/Profile semantics.
            }

        default:
            break
        }
    }

    private func showTuning() {
        guard tuningPanel == nil, let policyStore else { return }
        candidateBar.isHidden = true
        keyboardGrid.isHidden = true

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
        candidateBar.isHidden = false
        keyboardGrid.isHidden = false
    }
}

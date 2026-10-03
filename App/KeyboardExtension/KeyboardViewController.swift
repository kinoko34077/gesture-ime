import UIKit
import GestureIMECore

final class KeyboardViewController: UIInputViewController {
    private let tuningStore = GestureTuningStore()

    private var profile: ProfileBundle?
    private var bindingSet: BindingSet?
    private var tries: [String: BindingTrie] = [:]
    private var sessions: [ObjectIdentifier: GestureSession] = [:]

    private let rootStack = UIStackView()
    private let tuningStack = UIStackView()
    private var heightConstraint: NSLayoutConstraint?

    private var deadZoneSlider = UISlider()
    private var stage1Slider = UISlider()
    private var stage2Slider = UISlider()
    private var hysteresisSlider = UISlider()

    private var deadZoneValue = UILabel()
    private var stage1Value = UILabel()
    private var stage2Value = UILabel()
    private var hysteresisValue = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        preferredContentSize = CGSize(width: 0, height: 300)

        rootStack.axis = .vertical
        rootStack.spacing = 6
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)

        heightConstraint = view.heightAnchor.constraint(equalToConstant: 300)
        heightConstraint?.priority = .init(999)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            heightConstraint!
        ])

        buildTuningPanel()

        do {
            let loaded = try BuiltInProfileLoader.load()
            profile = loaded
            guard
                let layer = loaded.layers.first(where: { $0.id == "base" }),
                let layout = loaded.layouts.first(where: { $0.id == layer.layoutRef }),
                let bindings = loaded.bindingSets.first(where: { $0.id == layer.bindingSetRef })
            else {
                throw ProfileValidationError(.missingReference, "base layer")
            }
            bindingSet = bindings
            for key in loaded.keyDefinitions {
                tries[key.id] = try BindingTrieCompiler.compile(bindings, keyID: key.id)
            }
            buildKeyboard(profile: loaded, layout: layout)
        } catch {
            showLoadError(error)
        }
    }

    private func buildKeyboard(profile: ProfileBundle, layout: Layout) {
        let definitions = Dictionary(uniqueKeysWithValues: profile.keyDefinitions.map { ($0.id, $0) })
        let grouped = Dictionary(grouping: layout.placements, by: \.row)

        for rowIndex in grouped.keys.sorted() {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 5
            row.distribution = .fillEqually

            for placement in (grouped[rowIndex] ?? []).sorted(by: { $0.column < $1.column }) {
                let title = definitions[placement.keyID]?.presentation?.text ?? placement.keyID
                let key = GestureKeyView(keyID: placement.keyID, title: title)
                wire(key)
                row.addArrangedSubview(key)
            }
            rootStack.addArrangedSubview(row)
        }
    }

    private func wire(_ key: GestureKeyView) {
        let identity = ObjectIdentifier(key)

        key.onTouchDown = { [weak self, weak key] point, size in
            guard let self, let key, let trie = self.tries[key.keyID] else { return }
            self.sessions[identity] = GestureSession(
                keyID: key.keyID,
                profileRevision: String(self.profile?.version ?? 0),
                trie: trie,
                policy: self.tuningStore.policy,
                keySize: GestureSize(width: Double(size.width), height: Double(size.height)),
                touchDown: GesturePoint(x: Double(point.x), y: Double(point.y))
            )
        }

        key.onTouchMove = { [weak self] point in
            guard let self, var session = self.sessions[identity] else { return }
            session.move(to: GesturePoint(x: Double(point.x), y: Double(point.y)))
            self.sessions[identity] = session
        }

        key.onTouchUp = { [weak self] point in
            guard let self, var session = self.sessions.removeValue(forKey: identity) else { return }
            session.move(to: GesturePoint(x: Double(point.x), y: Double(point.y)))
            let result = session.touchUp()
            self.execute(result.dispatchedActions)
        }

        key.onTouchCancel = { [weak self] in
            guard let self, var session = self.sessions.removeValue(forKey: identity) else { return }
            _ = session.cancel()
        }
    }

    private func execute(_ actions: [ActionInvocation]) {
        for action in actions {
            switch action.actionID {
            case "text.insert", "text.directInsert":
                if let text = action.arguments["text"]?.stringValue {
                    textDocumentProxy.insertText(text)
                }
            case "edit.delete":
                guard let count = action.arguments["count"]?.intValue else { continue }
                if count > 0 {
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
            case "panel.open":
                if action.arguments["panel"]?.stringValue == "tuning" {
                    toggleTuningPanel()
                }
            case "noop":
                break
            default:
                break
            }
        }
    }

    private func buildTuningPanel() {
        tuningStack.axis = .vertical
        tuningStack.spacing = 4
        tuningStack.isHidden = true
        tuningStack.backgroundColor = .secondarySystemBackground
        tuningStack.layer.cornerRadius = 8
        tuningStack.isLayoutMarginsRelativeArrangement = true
        tuningStack.layoutMargins = .init(top: 6, left: 8, bottom: 6, right: 8)

        tuningStack.addArrangedSubview(tuningRow(
            title: "Dead zone", slider: deadZoneSlider, valueLabel: deadZoneValue,
            range: 0.05...0.50, value: tuningStore.deadZone, action: #selector(deadZoneChanged)
        ))
        tuningStack.addArrangedSubview(tuningRow(
            title: "Stage 1", slider: stage1Slider, valueLabel: stage1Value,
            range: 0.15...1.20, value: tuningStore.stage1Distance, action: #selector(stage1Changed)
        ))
        tuningStack.addArrangedSubview(tuningRow(
            title: "Stage 2", slider: stage2Slider, valueLabel: stage2Value,
            range: 0.15...1.50, value: tuningStore.stage2Distance, action: #selector(stage2Changed)
        ))
        tuningStack.addArrangedSubview(tuningRow(
            title: "Hysteresis", slider: hysteresisSlider, valueLabel: hysteresisValue,
            range: 0...30, value: tuningStore.hysteresis, action: #selector(hysteresisChanged)
        ))

        let reset = UIButton(type: .system)
        reset.setTitle("Reset gesture tuning", for: .normal)
        reset.addTarget(self, action: #selector(resetTuning), for: .touchUpInside)
        tuningStack.addArrangedSubview(reset)

        rootStack.addArrangedSubview(tuningStack)
        refreshTuningLabels()
    }

    private func tuningRow(
        title: String,
        slider: UISlider,
        valueLabel: UILabel,
        range: ClosedRange<Double>,
        value: Double,
        action: Selector
    ) -> UIView {
        let container = UIStackView()
        container.axis = .horizontal
        container.spacing = 6

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 12)
        label.widthAnchor.constraint(equalToConstant: 68).isActive = true

        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.value = Float(value)
        slider.addTarget(self, action: action, for: .valueChanged)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.textAlignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 42).isActive = true

        container.addArrangedSubview(label)
        container.addArrangedSubview(slider)
        container.addArrangedSubview(valueLabel)
        return container
    }

    private func toggleTuningPanel() {
        tuningStack.isHidden.toggle()
        let height: CGFloat = tuningStack.isHidden ? 300 : 455
        heightConstraint?.constant = height
        preferredContentSize = CGSize(width: 0, height: height)
        UIView.animate(withDuration: 0.15) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func deadZoneChanged() {
        tuningStore.setDeadZone(Double(deadZoneSlider.value))
        syncSlidersFromStore()
    }

    @objc private func stage1Changed() {
        tuningStore.setStage1(Double(stage1Slider.value))
        syncSlidersFromStore()
    }

    @objc private func stage2Changed() {
        tuningStore.setStage2(Double(stage2Slider.value))
        syncSlidersFromStore()
    }

    @objc private func hysteresisChanged() {
        tuningStore.setHysteresis(Double(hysteresisSlider.value))
        syncSlidersFromStore()
    }

    @objc private func resetTuning() {
        tuningStore.reset()
        syncSlidersFromStore()
    }

    private func syncSlidersFromStore() {
        deadZoneSlider.value = Float(tuningStore.deadZone)
        stage1Slider.value = Float(tuningStore.stage1Distance)
        stage2Slider.value = Float(tuningStore.stage2Distance)
        hysteresisSlider.value = Float(tuningStore.hysteresis)
        refreshTuningLabels()
    }

    private func refreshTuningLabels() {
        deadZoneValue.text = String(format: "%.2f", tuningStore.deadZone)
        stage1Value.text = String(format: "%.2f", tuningStore.stage1Distance)
        stage2Value.text = String(format: "%.2f", tuningStore.stage2Distance)
        hysteresisValue.text = String(format: "%.1f", tuningStore.hysteresis)
    }

    private func showLoadError(_ error: Error) {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = "Profile load failed\n\(error)"
        rootStack.addArrangedSubview(label)
    }
}

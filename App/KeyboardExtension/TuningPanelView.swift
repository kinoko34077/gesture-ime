import UIKit

@MainActor
final class TuningPanelView: UIView {
    var onClose: (() -> Void)?

    private let store: GesturePolicyStore
    private let stack = UIStackView()

    init(store: GesturePolicyStore) {
        self.store = store
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .systemBackground

        stack.axis = .vertical
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let header = UIStackView()
        header.axis = .horizontal

        let title = UILabel()
        title.text = "Gesture tuning"
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        let reset = UIButton(type: .system)
        reset.setTitle("初期値", for: .normal)
        reset.addAction(UIAction { [weak self] _ in
            self?.store.resetToProfileDefaults()
            self?.rebuildControls()
        }, for: .touchUpInside)

        let close = UIButton(type: .system)
        close.setTitle("閉じる", for: .normal)
        close.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)

        header.addArrangedSubview(title)
        header.addArrangedSubview(reset)
        header.addArrangedSubview(close)
        stack.addArrangedSubview(header)
        installControls()

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func rebuildControls() {
        while stack.arrangedSubviews.count > 1 {
            let view = stack.arrangedSubviews.last!
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        installControls()
    }

    private func installControls() {
        addSlider("Dead zone", value: store.deadZone, range: 0.02...0.60) { [weak store] in store?.setDeadZone($0) }
        addSlider("Stage 1", value: store.stage1, range: 0.10...1.50) { [weak store] in store?.setStage1($0) }
        addSlider("Stage 2", value: store.stage2, range: 0.10...1.80) { [weak store] in store?.setStage2($0) }
        addSlider("Hysteresis", value: store.hysteresis, range: 0...30, suffix: "°") { [weak store] in store?.setHysteresis($0) }
    }

    private func addSlider(
        _ name: String,
        value: Double,
        range: ClosedRange<Double>,
        suffix: String = "",
        apply: @escaping (Double) -> Void
    ) {
        let valueLabel = UILabel()
        valueLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textAlignment = .right
        valueLabel.text = Self.format(value, suffix: suffix)

        let nameLabel = UILabel()
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.text = name

        let header = UIStackView(arrangedSubviews: [nameLabel, valueLabel])
        header.axis = .horizontal

        let slider = UISlider()
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.value = Float(value)
        slider.addAction(
            UIAction { _ in
                let newValue = Double(slider.value)
                valueLabel.text = Self.format(newValue, suffix: suffix)
                apply(newValue)
            },
            for: .valueChanged
        )

        let group = UIStackView(arrangedSubviews: [header, slider])
        group.axis = .vertical
        group.spacing = 0
        stack.addArrangedSubview(group)
    }

    private static func format(_ value: Double, suffix: String) -> String {
        String(format: "%.2f%@", value, suffix)
    }
}

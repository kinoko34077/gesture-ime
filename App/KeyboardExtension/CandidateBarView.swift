import UIKit

@MainActor
final class CandidateBarView: UIView {
    var onCandidateSelected: ((Int) -> Void)?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var buttons: [UIButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .secondarySystemBackground

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 6),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -6),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 4),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -4),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func render(candidates: [String], selectedIndex: Int?) {
        buttons.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        buttons.removeAll(keepingCapacity: true)

        if candidates.isEmpty {
            let label = UILabel()
            label.text = " "
            label.textColor = .secondaryLabel
            stackView.addArrangedSubview(label)
            return
        }

        for (index, candidate) in candidates.enumerated() {
            var config = UIButton.Configuration.plain()
            config.title = candidate
            config.baseForegroundColor = .label
            config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)

            if selectedIndex == index {
                config.background.backgroundColor = .tertiarySystemFill
                config.background.cornerRadius = 8
            }

            let button = UIButton(configuration: config)
            button.tag = index
            button.titleLabel?.font = .systemFont(ofSize: 18)
            button.addTarget(self, action: #selector(candidatePressed(_:)), for: .touchUpInside)
            stackView.addArrangedSubview(button)
            buttons.append(button)
        }
    }

    @objc private func candidatePressed(_ sender: UIButton) {
        onCandidateSelected?(sender.tag)
    }
}

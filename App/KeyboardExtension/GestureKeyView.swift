import UIKit

final class GestureKeyView: UIControl {
    let keyID: String

    var onTouchDown: ((CGPoint, CGSize) -> Void)?
    var onTouchMove: ((CGPoint) -> Void)?
    var onTouchUp: ((CGPoint) -> Void)?
    var onTouchCancel: (() -> Void)?

    private let titleLabel = UILabel()

    init(keyID: String, title: String) {
        self.keyID = keyID
        super.init(frame: .zero)

        isMultipleTouchEnabled = false
        layer.cornerRadius = 8
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.cgColor
        backgroundColor = UIColor.secondarySystemBackground

        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 19, weight: .medium)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.6
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        isHighlighted = true
        backgroundColor = UIColor.tertiarySystemFill
        onTouchDown?(touch.location(in: self), bounds.size)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        onTouchMove?(touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer {
            isHighlighted = false
            backgroundColor = UIColor.secondarySystemBackground
        }
        guard let touch = touches.first else { return }
        onTouchUp?(touch.location(in: self))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isHighlighted = false
        backgroundColor = UIColor.secondarySystemBackground
        onTouchCancel?()
    }
}

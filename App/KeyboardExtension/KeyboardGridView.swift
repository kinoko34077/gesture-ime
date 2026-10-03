import UIKit

@MainActor
final class KeyboardGridView: UIView {
    struct Item {
        let view: UIView
        let row: Int
        let column: Int
        let width: Int
        let height: Int
    }

    var rowCount: Int = 1 {
        didSet { setNeedsLayout() }
    }

    var columnCount: Int = 1 {
        didSet { setNeedsLayout() }
    }

    var spacing: CGFloat = 5 {
        didSet { setNeedsLayout() }
    }

    private var items: [Item] = []

    func install(_ newItems: [Item], rowCount: Int, columnCount: Int) {
        items.forEach { $0.view.removeFromSuperview() }
        items = newItems
        self.rowCount = max(1, rowCount)
        self.columnCount = max(1, columnCount)

        for item in items {
            addSubview(item.view)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let columns = CGFloat(max(1, columnCount))
        let rows = CGFloat(max(1, rowCount))
        let unitWidth = max(0, (bounds.width - spacing * (columns - 1)) / columns)
        let unitHeight = max(0, (bounds.height - spacing * (rows - 1)) / rows)

        for item in items {
            let x = CGFloat(item.column) * (unitWidth + spacing)
            let y = CGFloat(item.row) * (unitHeight + spacing)
            let width = CGFloat(item.width) * unitWidth + CGFloat(max(0, item.width - 1)) * spacing
            let height = CGFloat(item.height) * unitHeight + CGFloat(max(0, item.height - 1)) * spacing
            item.view.frame = CGRect(x: x, y: y, width: width, height: height)
        }
    }
}

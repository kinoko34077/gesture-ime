import SwiftUI
import GestureIMEProfileAuthoring

struct ProductBoardCanvas: View {
    @ObservedObject var editor: ProfileV3EditorModel

    @State private var viewport: ProfileV3CanvasViewport?
    @State private var liveViewport: ProfileV3CanvasViewport?
    @State private var interaction: ProfileV3CanvasInteraction?
    @State private var candidate: ProfileV3Rect?
    @State private var pinchBase: ProfileV3CanvasViewport?
    @State private var userAdjustedViewport = false
    @State private var fittedBoardID: String?

    private var hitItems: [(id: String, rect: ProfileV3Rect)] {
        editor.entries.map { ($0.id, $0.rect) }
    }

    var body: some View {
        GeometryReader { proxy in
            let current = liveViewport ?? viewport ?? fitted(proxy.size)

            ZStack {
                Rectangle()
                    .fill(Color(.systemBackground))

                ProductAtomicGrid(
                    viewport: current,
                    size: proxy.size
                )

                ForEach(editor.entries) { entry in
                    entryView(entry, viewport: current)
                }

                if let candidate {
                    candidateView(
                        candidate,
                        viewport: current
                    )
                }
            }
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.separator), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .gesture(dragGesture(size: proxy.size))
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let base = pinchBase
                            ?? viewport
                            ?? fitted(proxy.size)
                        if pinchBase == nil {
                            pinchBase = base
                        }
                        var next = base
                        next.zoom(
                            by: Double(value.magnification),
                            anchorX: Double(proxy.size.width / 2),
                            anchorY: Double(proxy.size.height / 2)
                        )
                        liveViewport = next
                        userAdjustedViewport = true
                    }
                    .onEnded { _ in
                        if let liveViewport {
                            viewport = liveViewport
                        }
                        self.liveViewport = nil
                        pinchBase = nil
                    }
            )
            .overlay(alignment: .topTrailing) {
                canvasControls(size: proxy.size)
                    .padding(6)
            }
            .onAppear {
                reconcileFit(
                    size: proxy.size,
                    boardID: editor.currentBoardID
                )
            }
            .onChange(of: proxy.size) { _, newSize in
                reconcileFit(
                    size: newSize,
                    boardID: editor.currentBoardID
                )
            }
            .onChange(of: editor.currentBoardID) { _, boardID in
                userAdjustedViewport = false
                fittedBoardID = nil
                reconcileFit(
                    size: proxy.size,
                    boardID: boardID
                )
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("キーボード編集キャンバス")
        }
    }

    @ViewBuilder
    private func entryView(
        _ entry: ProfileV3BoardEntrySummary,
        viewport: ProfileV3CanvasViewport
    ) -> some View {
        let selected = editor.selectedEntryID == entry.id
        let rect = interaction?.targetEntryID == entry.id
            ? (candidate ?? entry.rect)
            : entry.rect
        let valid = interaction?.targetEntryID != entry.id
            || rect == entry.rect
            || editor.canPlaceEntry(entry.id, rect: rect)
        let frame = viewport.frame(for: rect)

        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(
                    valid
                        ? (selected
                            ? Color.accentColor.opacity(0.18)
                            : Color(.secondarySystemBackground))
                        : Color.red.opacity(0.14)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(
                            valid
                                ? (selected ? Color.accentColor : Color(.separator))
                                : Color.red,
                            lineWidth: selected ? 2 : 1
                        )
                }

            Text(entry.presentationText ?? "・")
                .font(.callout)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .padding(3)

            if entry.transition != nil {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 8, weight: .bold))
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                    .padding(4)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            if !valid {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topTrailing
                    )
                    .padding(4)
                    .accessibilityHidden(true)
            }
        }
        .frame(
            width: CGFloat(frame.width),
            height: CGFloat(frame.height)
        )
        .position(
            x: CGFloat(frame.midX),
            y: CGFloat(frame.midY)
        )
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(
            entry.accessibilityLabel
                ?? entry.presentationText
                ?? "キー"
        )
        .accessibilityValue(
            selected ? "選択中" : ""
        )
        .accessibilityAddTraits(
            selected ? .isSelected : []
        )
        .accessibilityAction(named: "選択") {
            editor.selectEntry(entry.id)
        }

        if selected,
           interaction?.targetEntryID != entry.id {
            let handle =
                ProfileV3CanvasHitTester
                    .resizeHandleFrame(
                        for: entry.rect,
                        viewport: viewport
                    )

            Circle()
                .fill(Color.accentColor)
                .frame(width: 20, height: 20)
                .overlay {
                    Image(
                        systemName:
                            "arrow.up.left.and.arrow.down.right"
                    )
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                }
                .position(
                    x: CGFloat(handle.midX),
                    y: CGFloat(handle.midY)
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func candidateView(
        _ rect: ProfileV3Rect,
        viewport: ProfileV3CanvasViewport
    ) -> some View {
        let frame = viewport.frame(for: rect)
        let valid: Bool

        if let entryID = interaction?.targetEntryID {
            valid = editor.canPlaceEntry(
                entryID,
                rect: rect
            )
        } else {
            valid = editor.canCreateEntry(rect)
        }

        return RoundedRectangle(cornerRadius: 7)
            .stroke(
                valid ? Color.accentColor : Color.red,
                style: StrokeStyle(
                    lineWidth: 2,
                    dash: [5, 4]
                )
            )
            .overlay {
                if !valid {
                    Image(systemName: "xmark.circle.fill")
                        .accessibilityHidden(true)
                }
            }
            .frame(
                width: CGFloat(frame.width),
                height: CGFloat(frame.height)
            )
            .position(
                x: CGFloat(frame.midX),
                y: CGFloat(frame.midY)
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func canvasControls(
        size: CGSize
    ) -> some View {
        HStack(spacing: 4) {
            Button {
                zoom(
                    by: 1 / 1.25,
                    size: size
                )
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("縮小")

            Button {
                zoom(
                    by: 1.25,
                    size: size
                )
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("拡大")

            Button("全体") {
                fitAll(size)
            }
            .font(.caption.bold())
            .frame(minHeight: 36)
            .accessibilityLabel("全体表示")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .background(
            .thinMaterial,
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private func dragGesture(
        size: CGSize
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let base = viewport ?? fitted(size)

                if interaction == nil {
                    let hit =
                        ProfileV3CanvasHitTester.hit(
                            x: Double(value.startLocation.x),
                            y: Double(value.startLocation.y),
                            entries: hitItems,
                            selectedEntryID:
                                editor.selectedEntryID,
                            viewport: base
                        )
                    let started =
                        ProfileV3CanvasInteraction.begin(
                            hit: hit,
                            tool: editor.tool,
                            entries: hitItems,
                            viewport: base
                        )
                    interaction = started
                    if let target = started.targetEntryID {
                        editor.selectEntry(target)
                    }
                }

                guard let interaction else {
                    return
                }

                if let panned =
                        interaction.pannedViewport(
                            translationX:
                                Double(value.translation.width),
                            translationY:
                                Double(value.translation.height)
                        ) {
                    liveViewport = panned
                    userAdjustedViewport = true
                    return
                }

                candidate =
                    interaction.candidateRect(
                        translationX:
                            Double(value.translation.width),
                        translationY:
                            Double(value.translation.height),
                        currentX:
                            Double(value.location.x),
                        currentY:
                            Double(value.location.y),
                        viewport: base
                    )
            }
            .onEnded { _ in
                defer {
                    interaction = nil
                    candidate = nil
                    liveViewport = nil
                }

                if let liveViewport {
                    viewport = liveViewport
                    userAdjustedViewport = true
                    return
                }

                guard
                    let interaction,
                    let candidate
                else {
                    return
                }

                switch interaction.operation {
                case .move(let entryID, let start),
                     .resize(let entryID, let start):
                    guard
                        candidate != start,
                        editor.canPlaceEntry(
                            entryID,
                            rect: candidate
                        )
                    else {
                        return
                    }
                    editor.setEntryRect(
                        entryID,
                        rect: candidate
                    )

                case .create:
                    guard editor.canCreateEntry(candidate)
                    else {
                        return
                    }
                    editor.createEntry(rect: candidate)

                case .none, .pan:
                    break
                }
            }
    }

    private func fitted(
        _ size: CGSize
    ) -> ProfileV3CanvasViewport {
        ProfileV3CanvasViewport.fitting(
            rects: editor.entries.map(\.rect),
            width: Double(size.width),
            height: Double(size.height)
        )
    }

    private func reconcileFit(
        size: CGSize,
        boardID: String?
    ) {
        guard
            size.width > 0,
            size.height > 0
        else {
            return
        }

        if fittedBoardID != boardID {
            userAdjustedViewport = false
        }

        guard !userAdjustedViewport else {
            return
        }

        viewport = fitted(size)
        liveViewport = nil
        fittedBoardID = boardID
    }

    private func fitAll(
        _ size: CGSize
    ) {
        userAdjustedViewport = false
        viewport = fitted(size)
        liveViewport = nil
        fittedBoardID = editor.currentBoardID
    }

    private func zoom(
        by scale: Double,
        size: CGSize
    ) {
        var next = viewport ?? fitted(size)
        next.zoom(
            by: scale,
            anchorX: Double(size.width / 2),
            anchorY: Double(size.height / 2)
        )
        viewport = next
        userAdjustedViewport = true
    }
}

private struct ProductAtomicGrid: View {
    let viewport: ProfileV3CanvasViewport
    let size: CGSize

    var body: some View {
        Canvas { context, _ in
            let step = CGFloat(viewport.atomicSize) * 2
            guard step >= 6 else {
                return
            }

            var path = Path()
            var x =
                CGFloat(viewport.originX)
                    .truncatingRemainder(
                        dividingBy: step
                    )
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(
                    to: CGPoint(
                        x: x,
                        y: size.height
                    )
                )
                x += step
            }

            var y =
                CGFloat(viewport.originY)
                    .truncatingRemainder(
                        dividingBy: step
                    )
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(
                    to: CGPoint(
                        x: size.width,
                        y: y
                    )
                )
                y += step
            }

            context.stroke(
                path,
                with:
                    .color(
                        .secondary.opacity(0.16)
                    ),
                lineWidth: 0.5
            )

            var origin = Path()
            origin.move(
                to: CGPoint(
                    x: CGFloat(viewport.originX),
                    y: 0
                )
            )
            origin.addLine(
                to: CGPoint(
                    x: CGFloat(viewport.originX),
                    y: size.height
                )
            )
            origin.move(
                to: CGPoint(
                    x: 0,
                    y: CGFloat(viewport.originY)
                )
            )
            origin.addLine(
                to: CGPoint(
                    x: size.width,
                    y: CGFloat(viewport.originY)
                )
            )

            context.stroke(
                origin,
                with:
                    .color(
                        .secondary.opacity(0.45)
                    ),
                lineWidth: 1
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

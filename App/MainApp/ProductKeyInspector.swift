import SwiftUI
import GestureIMEProfileAuthoring

struct ProductKeyInspector: View {
    @ObservedObject var editor: ProfileV3EditorModel
    let entry: ProfileV3BoardEntrySummary
    let stageDepth: Int
    let onOpenNextStage: () -> Void

    @State private var displayText = ""
    @State private var tapText = ""

    var body: some View {
        LazyVStack(
            alignment: .leading,
            spacing: 0
        ) {
            header

            Divider()

            basicFields

            Divider()

            flickSection

            Divider()

            stageAndHoldSection

            Divider()

            conditionSummary

            Divider()

            geometrySection

            Divider()

            advancedSection
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 24)
        .onAppear(perform: syncDrafts)
        .onChange(of: entry) { _, _ in
            syncDrafts()
        }
        .onDisappear {
            commitBasicDrafts()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(entry.presentationText ?? "キー")
                .font(.headline)
                .lineLimit(1)

            Spacer(minLength: 8)

            Menu {
                Button("複製") {
                    editor.duplicateSelectedEntry(
                        rect: neighbourRect
                    )
                }
                .disabled(
                    !editor.canCreateEntry(
                        neighbourRect
                    )
                )

                Button("コピー") {
                    editor.copySelectedEntry()
                }

                if let pasteRect {
                    Button("右に貼り付け") {
                        editor.pasteCopiedEntry(
                            rect: pasteRect
                        )
                    }
                    .disabled(
                        !editor.canCreateEntry(
                            pasteRect
                        )
                    )
                }

                Divider()

                Button("削除", role: .destructive) {
                    editor.deleteSelectedEntry()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("キーの操作")
        }
        .frame(minHeight: 48)
    }

    private var basicFields: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            ProductSectionHeader(
                "入力",
                help:
                    "表示はキー上の文字、タップは指を動かさず離したときの入力です。"
            )

            HStack(alignment: .firstTextBaseline) {
                Text("表示")
                    .frame(width: 52, alignment: .leading)
                TextField(
                    "キー上の文字",
                    text: $displayText
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    editor.setSelectedDisplayText(
                        displayText
                    )
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(stageDepth > 1 ? "中央" : "タップ")
                    .frame(width: 52, alignment: .leading)
                TextField(
                    "入力する文字",
                    text: $tapText
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    editor.setSelectedTapText(
                        tapText
                    )
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var flickSection: some View {
        VStack(
            alignment: .leading,
            spacing: 6
        ) {
            ProductSectionHeader(
                "フリック先",
                help:
                    "8方向の入力を同じ位置関係で編集します。空欄の方向は入力先なしです。"
            )

            ProductFlickGrid(editor: editor)
        }
        .padding(.vertical, 8)
    }

    private var stageAndHoldSection: some View {
        VStack(
            alignment: .leading,
            spacing: 6
        ) {
            ProductSectionHeader(
                "続きの操作",
                help:
                    "次の段階では、選んだフリック先からさらに続けて入力できます。"
            )

            HStack {
                Label(
                    entry.transition == nil
                        ? "次の段階なし"
                        : "次の段階あり",
                    systemImage:
                        entry.transition == nil
                        ? "arrow.turn.down.right"
                        : "arrow.turn.down.right.circle.fill"
                )
                .font(.subheadline)

                Spacer()

                Button(
                    entry.transition == nil
                        ? "追加して編集"
                        : "編集",
                    action: onOpenNextStage
                )
            }
            .frame(minHeight: 44)

            HStack {
                Label(
                    holdSummary,
                    systemImage: "hand.tap"
                )
                .font(.subheadline)
                Spacer()
            }
            .frame(minHeight: 44)
        }
        .padding(.vertical, 8)
    }

    private var conditionSummary: some View {
        HStack(spacing: 8) {
            ProductSectionHeader(
                "条件",
                help:
                    "入力欄や変換状態などに応じて、このキーの表示や動作を切り替えます。"
            )

            Text(
                "\(editor.selectedRules?.branches.count ?? 0)件"
            )
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var geometrySection: some View {
        VStack(
            alignment: .leading,
            spacing: 4
        ) {
            ProductSectionHeader(
                "位置・大きさ",
                help:
                    "横・縦は位置、幅・高さはキーの大きさです。＋/−で1単位ずつ変更します。"
            )

            HStack(spacing: 6) {
                ProductGeometryAdjuster(
                    title: "横",
                    value: entry.rect.x
                ) { delta in
                    var rect = entry.rect
                    rect.x += delta
                    editor.setSelectedEntryRect(rect)
                }

                ProductGeometryAdjuster(
                    title: "縦",
                    value: entry.rect.y
                ) { delta in
                    var rect = entry.rect
                    rect.y += delta
                    editor.setSelectedEntryRect(rect)
                }

                ProductGeometryAdjuster(
                    title: "幅",
                    value: entry.rect.width
                ) { delta in
                    var rect = entry.rect
                    rect.width += delta
                    if rect.width > 0 {
                        editor.setSelectedEntryRect(rect)
                    }
                }

                ProductGeometryAdjuster(
                    title: "高さ",
                    value: entry.rect.height
                ) { delta in
                    var rect = entry.rect
                    rect.height += delta
                    if rect.height > 0 {
                        editor.setSelectedEntryRect(rect)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var advancedSection: some View {
        DisclosureGroup("高度な設定") {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                if let transition = entry.transition {
                    HStack(spacing: 8) {
                        Text("次の段階")
                        Spacer()
                        Picker(
                            "次の段階の持続",
                            selection: Binding(
                                get: {
                                    transition.lifetime
                                },
                                set: {
                                    editor
                                        .setSelectedTransitionLifetime(
                                            $0
                                        )
                                }
                            )
                        ) {
                            Text("離すと戻る")
                                .tag(
                                    ProfileV3TransitionLifetime
                                        .transient
                                )
                            Text("そのまま維持")
                                .tag(
                                    ProfileV3TransitionLifetime
                                        .persistent
                                )
                        }
                        .labelsHidden()

                        ProductInfoButton(
                            title: "次の段階",
                            message:
                                "「離すと戻る」は指を離した時に元へ戻り、「そのまま維持」は切り替えた段階を維持します。"
                        )
                    }
                    .frame(minHeight: 44)
                }

                overrideControls
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 12)
    }

    private var overrideControls: some View {
        let enabled = editor.selectedOverride != nil

        return VStack(
            alignment: .leading,
            spacing: 8
        ) {
            HStack {
                Toggle(
                    "このキーだけ入力判定を変える",
                    isOn: Binding(
                        get: { enabled },
                        set: { on in
                            if on {
                                editor.setSelectedOverride(
                                    ProfileV3GesturePolicyOverride()
                                )
                            } else {
                                editor.setSelectedOverride(nil)
                            }
                        }
                    )
                )
                ProductInfoButton(
                    title: "キー個別の入力判定",
                    message:
                        "共通のフリック判定から、このキーに必要な項目だけ上書きできます。"
                )
            }

            if enabled,
               let common = editor.policyValues {
                ForEach(
                    ProfileV3GesturePolicyField.allCases
                ) { field in
                    ProductPolicyOverrideRow(
                        field: field,
                        common: common,
                        override: editor.selectedOverride
                    ) { next in
                        editor.setSelectedOverride(next)
                    }
                }
            }
        }
    }

    private var holdSummary: String {
        guard let hold = entry.hold else {
            return "長押しなし"
        }
        return "長押し \(hold.delayMs)ms"
    }

    private var neighbourRect: ProfileV3Rect {
        ProfileV3Rect(
            x: entry.rect.x + entry.rect.width,
            y: entry.rect.y,
            width: entry.rect.width,
            height: entry.rect.height
        )
    }

    private var pasteRect: ProfileV3Rect? {
        guard let copied = editor.copiedEntryRect else {
            return nil
        }
        return ProfileV3Rect(
            x: entry.rect.x + entry.rect.width,
            y: entry.rect.y,
            width: copied.width,
            height: copied.height
        )
    }

    private func syncDrafts() {
        displayText = entry.presentationText ?? ""
        tapText = editor.selectedTapText ?? ""
    }

    private func commitBasicDrafts() {
        if displayText
            != (entry.presentationText ?? "") {
            editor.setSelectedDisplayText(displayText)
        }
        if !tapText.isEmpty,
           tapText != (editor.selectedTapText ?? "") {
            editor.setSelectedTapText(tapText)
        }
    }
}

private struct ProductFlickGrid: View {
    @ObservedObject var editor: ProfileV3EditorModel

    private let layout: [[ProfileV3Direction?]] = [
        [.northWest, .north, .northEast],
        [.west, nil, .east],
        [.southWest, .south, .southEast]
    ]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { column in
                        if let direction =
                                layout[row][column] {
                            ProductFlickDirectionCell(
                                direction: direction,
                                initial:
                                    editor
                                        .selectedDirectionSlots
                                        .first {
                                            $0.direction
                                                == direction
                                        }?
                                        .entry?
                                        .presentationText
                                    ?? ""
                            ) { text in
                                ensureFlickBoard(
                                    for: text
                                )
                                editor.setDirectionText(
                                    direction,
                                    text: text
                                )
                            }
                        } else {
                            ProductFlickCenterCell(
                                initial:
                                    editor.selectedTapText
                                    ?? ""
                            ) { text in
                                if !text.isEmpty {
                                    editor.setSelectedTapText(
                                        text
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func ensureFlickBoard(
        for text: String
    ) {
        guard
            !text
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty,
            editor.selectedNextStageBoardID == nil
        else {
            return
        }
        editor.createNextStageForSelected()
    }
}

private struct ProductFlickDirectionCell: View {
    let direction: ProfileV3Direction
    let initial: String
    let onCommit: (String) -> Void

    @State private var text = ""

    var body: some View {
        VStack(spacing: 2) {
            Text(
                ProfileV3DisplayCatalog
                    .title(direction.displayKey)
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            TextField("", text: $text)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .frame(height: 44)
                .onSubmit {
                    onCommit(text)
                }
                .accessibilityLabel(
                    ProfileV3DisplayCatalog
                        .title(direction.displayKey)
                )
        }
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            height: 64
        )
        .onAppear {
            text = initial
        }
        .onChange(of: initial) { _, next in
            text = next
        }
        .onDisappear {
            if text != initial {
                onCommit(text)
            }
        }
    }
}

private struct ProductFlickCenterCell: View {
    let initial: String
    let onCommit: (String) -> Void
    @State private var text = ""

    var body: some View {
        VStack(spacing: 2) {
            Text("中央")
                .font(.caption2)
                .foregroundStyle(.secondary)

            TextField("", text: $text)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .frame(height: 44)
                .onSubmit {
                    onCommit(text)
                }
                .accessibilityLabel("中央")
        }
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            height: 64
        )
        .onAppear {
            text = initial
        }
        .onChange(of: initial) { _, next in
            text = next
        }
        .onDisappear {
            if !text.isEmpty, text != initial {
                onCommit(text)
            }
        }
    }
}

private struct ProductGeometryAdjuster: View {
    let title: String
    let value: Int
    let onChange: (Int) -> Void

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Text("\(value)")
                    .font(.callout.monospacedDigit())
                    .frame(
                        minWidth: 20,
                        alignment: .trailing
                    )

                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            Color(
                                .tertiarySystemFill
                            )
                        )

                    VStack(spacing: 0) {
                        Text("+")
                            .font(.caption.bold())
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity
                            )
                        Divider()
                        Text("−")
                            .font(.caption.bold())
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity
                            )
                    }
                }
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { tap in
                            onChange(
                                tap.location.y < 22
                                    ? 1
                                    : -1
                            )
                        }
                )
                .accessibilityHidden(true)
            }
        }
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: 64
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                onChange(1)
            case .decrement:
                onChange(-1)
            @unknown default:
                break
            }
        }
    }
}

private struct ProductPolicyOverrideRow: View {
    let field: ProfileV3GesturePolicyField
    let common: ProfileV3GesturePolicyValues
    let override: ProfileV3GesturePolicyOverride?
    let onChange: (ProfileV3GesturePolicyOverride) -> Void

    var body: some View {
        let current = override?.value(field)

        VStack(spacing: 4) {
            HStack {
                Toggle(
                    ProfileV3DisplayCatalog
                        .title(field.displayKey),
                    isOn: Binding(
                        get: { current != nil },
                        set: { enabled in
                            var next =
                                override
                                ?? ProfileV3GesturePolicyOverride()
                            next.set(
                                field,
                                enabled
                                    ? common.value(field)
                                    : nil
                            )
                            onChange(next)
                        }
                    )
                )

                if let current {
                    Text(valueText(current))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let current {
                Slider(
                    value: Binding(
                        get: { current },
                        set: { value in
                            var next =
                                override
                                ?? ProfileV3GesturePolicyOverride()
                            next.set(field, value)
                            onChange(next)
                        }
                    ),
                    in: field.range,
                    step: field.step
                )
                .accessibilityLabel(
                    ProfileV3DisplayCatalog
                        .title(field.displayKey)
                )
            }
        }
    }

    private func valueText(
        _ value: Double
    ) -> String {
        field == .stageBacktrackDwellMs
            || field == .angularHysteresisDegrees
            ? String(Int(value.rounded()))
            : String(format: "%.2f", value)
    }
}

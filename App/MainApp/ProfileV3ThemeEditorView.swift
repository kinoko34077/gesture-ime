import SwiftUI
import UIKit
import UniformTypeIdentifiers
import GestureIMEProfileAuthoring
import GestureIMEProductSettings

/// #157 U7: mobile-first Design editor. The Preview is the shared product
/// renderer over the edited Profile; settings remain presentation-only.
struct ProfileV3ThemeEditorView: View {
    @EnvironmentObject private var productSettings: ProductSettingsModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @ObservedObject var editor: ProfileV3EditorModel
    @State private var importingTheme = false

    private static let colorLabels: [(String, String)] = [
        ("keyboardBackground", "背景"),
        ("keyFill", "キー"),
        ("keyPressedFill", "押したキー"),
        ("border", "枠線"),
        ("text", "文字"),
        ("guideText", "フリック補助の文字"),
        ("candidateBackground", "変換候補の背景"),
        ("candidateText", "変換候補の文字"),
        ("candidateSelection", "選択中の候補"),
        ("overlayFill", "フリック表示の背景")
    ]

    static let weightLabels: [(String, String)] = [
        ("light", "細い"),
        ("regular", "標準"),
        ("medium", "中"),
        ("semibold", "やや太い"),
        ("bold", "太い")
    ]

    var body: some View {
        GeometryReader { geometry in
            let theme = editor.keyboardTheme
            let inset = CGFloat(
                ProfileV3DesignLayoutPolicy.contentInset(
                    usableWidth: Double(
                        geometry.size.width
                    )
                )
            )

            ScrollView {
                LazyVStack(spacing: 0) {
                    ProfileV3ProductPreview(
                        presentation:
                            IOSKeyboardPresentation(theme: theme),
                        surface: editor.previewSurface(),
                        composition: .product
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: previewHeight)
                    .accessibilityHint(
                        "現在のデザイン変更を即時に反映します"
                    )

                    Divider()

                    VStack(
                        alignment: .leading,
                        spacing: 16
                    ) {
                        colorSection(theme: theme)
                        typographySection(theme: theme)
                    }
                    .padding(.horizontal, inset)
                    .padding(
                        .vertical,
                        CGFloat(
                            ProfileV3DesignLayoutPolicy
                                .sectionGap
                        )
                    )
                }
            }
        }
        .navigationTitle(
            ProfileV3DisplayCatalog.title(.sectionDesign)
        )
        .toolbar {
            ToolbarItemGroup(
                placement: .topBarTrailing
            ) {
                Button("保存") {
                    editor.save()
                }
                .disabled(
                    !canSave
                        || !editor.validation.valid
                )

                Menu {
                    if let url = editor.exportThemeURL() {
                        ShareLink(item: url) {
                            Label(
                                "デザインを書き出し",
                                systemImage:
                                    "square.and.arrow.up"
                            )
                        }
                    }

                    Button {
                        importingTheme = true
                    } label: {
                        Label(
                            "デザインを読み込み",
                            systemImage:
                                "square.and.arrow.down"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(
                    "デザインのその他の操作"
                )
            }
        }
        .fileImporter(
            isPresented: $importingTheme,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: importTheme
        )
        .safeAreaInset(edge: .bottom) {
            if let message = editor.errorMessage {
                ProfileV3InlineAuthoringError(
                    message: message,
                    correctionHint:
                        "現在のデザインは保持されています。内容または共有状態を確認して、もう一度操作してください。"
                )
            }
        }
    }

    @ViewBuilder
    private func colorSection(
        theme: IOSKeyboardTheme
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            sectionHeading("色")

            ForEach(
                Self.colorLabels.indices,
                id: \.self
            ) { position in
                let item =
                    Self.colorLabels[position]
                let token = item.0
                let label = item.1

                HStack(spacing: 8) {
                    ColorPicker(
                        label,
                        selection: Binding(
                            get: {
                                IOSKeyboardPresentation(
                                    theme: theme
                                )
                                .swiftUIColor(
                                    IOSKeyboardColorRole(
                                        rawValue: token
                                    ) ?? .keyFill
                                )
                            },
                            set: {
                                editor.setThemeToken(
                                    token,
                                    value: .string(
                                        Self.hex($0)
                                    )
                                )
                            }
                        )
                    )
                    .frame(
                        minHeight: 44,
                        maxWidth: .infinity,
                        alignment: .leading
                    )

                    if theme.colors[token] != nil {
                        Button("自動") {
                            editor.setThemeToken(
                                token,
                                value: nil
                            )
                        }
                        .buttonStyle(.borderless)
                        .frame(
                            minHeight: CGFloat(
                                ProfileV3DesignLayoutPolicy
                                    .colorRowMinimumHeight
                            )
                        )
                    }
                }

                if position
                    < Self.colorLabels.count - 1 {
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func typographySection(
        theme: IOSKeyboardTheme
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            sectionHeading("形・文字")

            sliderRow(
                "角の丸み",
                key: "cornerRadius",
                value: theme.cornerRadius,
                range: 0...24,
                fallback:
                    IOSKeyboardPresentation
                        .defaultCornerRadius
            )

            Divider()

            sliderRow(
                "キー文字の大きさ",
                key: "keyFontSize",
                value: theme.keyFontSize,
                range: 8...40,
                fallback:
                    IOSKeyboardPresentation
                        .defaultKeyFontSize
            )

            Divider()

            HStack(spacing: 8) {
                Text("キー文字の太さ")

                Spacer(minLength: 8)

                Picker(
                    "キー文字の太さ",
                    selection: Binding(
                        get: {
                            theme.keyFontWeight ?? ""
                        },
                        set: {
                            editor.setThemeToken(
                                "keyFontWeight",
                                value:
                                    $0.isEmpty
                                    ? nil
                                    : .string($0)
                            )
                        }
                    )
                ) {
                    Text("自動").tag("")
                    ForEach(
                        Self.weightLabels,
                        id: \.0
                    ) {
                        Text($0.1).tag($0.0)
                    }
                }
                .labelsHidden()
            }
            .frame(
                            minHeight: CGFloat(
                                ProfileV3DesignLayoutPolicy
                                    .colorRowMinimumHeight
                            )
                        )

            Divider()

            sliderRow(
                "補助表示の大きさ",
                key: "guideFontSize",
                value: theme.guideFontSize,
                range: 6...24,
                fallback:
                    IOSKeyboardPresentation
                        .defaultGuideFontSize
            )

            Divider()

            sliderRow(
                "補助表示の濃さ",
                key: "guideOpacity",
                value: theme.guideOpacity,
                range: 0...1,
                fallback:
                    IOSKeyboardPresentation
                        .defaultGuideOpacity
            )
        }
    }

    private func sectionHeading(
        _ title: String
    ) -> some View {
        Text(title)
            .font(.headline)
            .frame(
                minHeight: CGFloat(
                    ProfileV3DesignLayoutPolicy
                        .sectionHeadingBaseHeight
                ),
                maxWidth: .infinity,
                alignment: .leading
            )
            .padding(.bottom, 4)
    }

    private func sliderRow(
        _ title: String,
        key: String,
        value: Double?,
        range: ClosedRange<Double>,
        fallback: Double
    ) -> some View {
        let step =
            range.upperBound <= 1
            ? 0.1
            : 1.0
        let displayed =
            min(
                range.upperBound,
                max(
                    range.lowerBound,
                    value ?? fallback
                )
            )
        let valueText =
            String(
                format:
                    step < 1
                    ? "%.1f"
                    : "%.0f",
                displayed
            )
        let visibleValue =
            value == nil
            ? "自動 · " + valueText
            : valueText

        return VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text(title)

                    Spacer(minLength: 8)

                    Text(visibleValue)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(title)

                    Text(visibleValue)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(
                minHeight: CGFloat(
                    ProfileV3DesignLayoutPolicy
                        .continuousLabelLineHeight
                )
            )

            Slider(
                value: Binding(
                    get: {
                        let current =
                            editor.keyboardThemeValue(
                                key: key
                            )
                            ?? fallback
                        return min(
                            range.upperBound,
                            max(
                                range.lowerBound,
                                current
                            )
                        )
                    },
                    set: { next in
                        editor.setThemeToken(
                            key,
                            value: .decimal(next)
                        )
                    }
                ),
                in: range,
                step: step
            )
            .frame(
                minHeight: CGFloat(
                    ProfileV3DesignLayoutPolicy
                        .continuousSliderAllocation
                )
            )
            .accessibilityLabel(title)
            .accessibilityValue(visibleValue)
        }
        .frame(
            minHeight: CGFloat(
                ProfileV3DesignLayoutPolicy
                    .continuousRowBaseHeight
            )
        )
        .contextMenu {
            if value != nil {
                Button("自動に戻す") {
                    editor.setThemeToken(
                        key,
                        value: nil
                    )
                }
            }
        }
    }

    private var previewHeight: CGFloat {
        let base =
            IOSKeyboardLayoutPolicy.baseHeight(
                compactVertical:
                    verticalSizeClass == .compact
            )
        let scaled =
            (
                try? productSettings.values
                    .scaledKeyboardHeight(
                        baseHeight: base
                    )
            ) ?? base
        return CGFloat(scaled)
    }

    private var canSave: Bool {
        switch editor.persistenceState {
        case .dirty,
             .savedLocallyDeliveryFailed:
            true
        case .savedLocally,
             .savedLocallyAndDelivered:
            false
        }
    }

    private func importTheme(
        _ result: Result<[URL], Error>
    ) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                return
            }

            let scoped =
                url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                editor.applyThemeTransfer(
                    try Data(contentsOf: url)
                )
            } catch {
                editor.errorMessage =
                    error.localizedDescription
            }

        case .failure(let error):
            editor.errorMessage =
                error.localizedDescription
        }
    }

    static func hex(_ color: Color) -> String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        UIColor(color).getRed(
            &r,
            green: &g,
            blue: &b,
            alpha: &a
        )

        func byte(_ value: CGFloat) -> Int {
            Int(
                (
                    min(max(value, 0), 1)
                    * 255
                ).rounded()
            )
        }

        return String(
            format: "#%02X%02X%02X%02X",
            byte(r),
            byte(g),
            byte(b),
            byte(a)
        )
    }
}

/// Shared renderer over the actual Board, plus candidate and flick-overlay
/// samples so every token is visible.
struct ProfileV3ProductPreview: View {
    let presentation: IOSKeyboardPresentation
    let surface: FfiProfileV3BoardSurface?
    let composition: ProfileV3PreviewComposition

    var body: some View {
        VStack(spacing: 4) {
            if composition.contains(.candidateBar) {
                HStack(spacing: 4) {
                    IOSKeyboardCandidateChip(text: "変換", selected: true, expanded: false, presentation: presentation) {}
                    IOSKeyboardCandidateChip(text: "候補", selected: false, expanded: false, presentation: presentation) {}
                    Spacer()
                }
                .frame(height: 44)
                .background(presentation.swiftUIColor(.candidateBackground))
            }

            GeometryReader { geometry in
                if let surface,
                   let mapping = IOSProfileV3BoardGeometryMapping(
                    surface: surface,
                    width: Double(geometry.size.width),
                    height: Double(geometry.size.height)
                   ) {
                    ZStack(alignment: .topLeading) {
                        if composition.contains(.boardKeys) {
                            ForEach(surface.entries, id: \.id) { entry in
                                let frame = mapping.frame(for: entry.rect)
                                IOSKeyboardKeyCap(
                                    text: entry.text ?? "",
                                    guides: composition.contains(.flickGuides) ? entry.guides : [],
                                    pressed: false,
                                    presentation: presentation
                                )
                                .frame(width: CGFloat(frame.width), height: CGFloat(frame.height))
                                .position(x: CGFloat(frame.x + frame.width / 2), y: CGFloat(frame.y + frame.height / 2))
                            }
                        }
                        if composition.contains(.relativeOverlay) {
                            HStack(spacing: 2) {
                                IOSKeyboardOverlayCell(text: "い", isCandidate: false, isEndpoint: false, presentation: presentation)
                                IOSKeyboardOverlayCell(text: "あ", isCandidate: true, isEndpoint: true, presentation: presentation)
                                IOSKeyboardOverlayCell(text: "う", isCandidate: false, isEndpoint: false, presentation: presentation)
                            }
                            .frame(width: 132, height: 40)
                            .position(x: geometry.size.width - 74, y: 24)
                        }
                    }
                } else {
                    Text("プレビューを表示できません（プロファイルにエラーがあります）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(presentation.swiftUIColor(.keyboardBackground))
        .accessibilityLabel("キーボードのプレビュー（実際のキーボード表示）")
    }
}

extension IOSKeyboardTheme {
    func uiColor(_ token: String) -> Color? {
        guard let value = colors[token] else { return nil }
        return Color(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
    }
}

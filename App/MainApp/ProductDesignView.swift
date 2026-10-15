import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import GestureIMEProfileAuthoring

struct ProductDesignView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ObservedObject var editor: ProfileV3EditorModel

    @State private var importingTheme = false

    private static let colorLabels: [(String, String)] = [
        ("keyboardBackground", "背景"),
        ("keyFill", "キー"),
        ("keyPressedFill", "押したキー"),
        ("border", "枠線"),
        ("text", "文字"),
        ("guideText", "フリック補助"),
        ("candidateBackground", "候補の背景"),
        ("candidateText", "候補の文字"),
        ("candidateSelection", "選択中の候補"),
        ("overlayFill", "フリック表示の背景")
    ]

    private static let weightLabels: [(String, String)] = [
        ("light", "細い"),
        ("regular", "標準"),
        ("medium", "中"),
        ("semibold", "やや太い"),
        ("bold", "太い")
    ]

    var body: some View {
        VStack(spacing: 0) {
            ProductDesignComparisonPreview(editor: editor)
                .frame(height: previewHeight)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    colorSection
                    typographySection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("デザイン")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let url = editor.exportThemeURL() {
                        ShareLink(item: url) {
                            Label(
                                "デザインを書き出し",
                                systemImage: "square.and.arrow.up"
                            )
                        }
                    }

                    Button {
                        importingTheme = true
                    } label: {
                        Label(
                            "デザインを読み込み",
                            systemImage: "square.and.arrow.down"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("デザインの操作")
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
                ProductInlineError(message: message) {
                    editor.errorMessage = nil
                }
            }
        }
    }

    private var previewHeight: CGFloat {
        verticalSizeClass == .compact ? 150 : 220
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("色")
                .font(.headline)
                .frame(minHeight: 36)

            ForEach(
                Self.colorLabels.indices,
                id: \.self
            ) { index in
                let item = Self.colorLabels[index]
                let token = item.0
                let label = item.1

                HStack(spacing: 8) {
                    ColorPicker(
                        label,
                        selection: Binding(
                            get: {
                                IOSKeyboardPresentation(
                                    theme: editor.keyboardTheme
                                )
                                .swiftUIColor(
                                    IOSKeyboardColorRole(
                                        rawValue: token
                                    ) ?? .keyFill
                                )
                            },
                            set: { color in
                                editor.setThemeToken(
                                    token,
                                    value: .string(
                                        Self.hex(color)
                                    )
                                )
                            }
                        )
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 44,
                        alignment: .leading
                    )

                    if editor.keyboardTheme.colors[token] != nil {
                        Button("自動") {
                            editor.setThemeToken(
                                token,
                                value: nil
                            )
                        }
                        .frame(minHeight: 44)
                    }
                }

                if index < Self.colorLabels.count - 1 {
                    Divider()
                }
            }
        }
    }

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("形・文字")
                .font(.headline)
                .frame(minHeight: 36)

            ProductDesignSliderRow(
                title: "角の丸み",
                value: themeNumericValue("cornerRadius"),
                fallback: IOSKeyboardPresentation.defaultCornerRadius,
                range: 0...24
            ) {
                editor.setThemeToken(
                    "cornerRadius",
                    value: .decimal($0)
                )
            } onReset: {
                editor.setThemeToken(
                    "cornerRadius",
                    value: nil
                )
            }

            Divider()

            ProductDesignSliderRow(
                title: "キー文字の大きさ",
                value: themeNumericValue("keyFontSize"),
                fallback: IOSKeyboardPresentation.defaultKeyFontSize,
                range: 8...40
            ) {
                editor.setThemeToken(
                    "keyFontSize",
                    value: .decimal($0)
                )
            } onReset: {
                editor.setThemeToken(
                    "keyFontSize",
                    value: nil
                )
            }

            Divider()

            HStack(spacing: 8) {
                Text("キー文字の太さ")
                Spacer(minLength: 8)
                Picker(
                    "キー文字の太さ",
                    selection: Binding(
                        get: {
                            editor.keyboardTheme
                                .keyFontWeight ?? ""
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
                    ForEach(Self.weightLabels, id: \.0) {
                        Text($0.1).tag($0.0)
                    }
                }
                .labelsHidden()
            }
            .frame(minHeight: 52)

            Divider()

            ProductDesignSliderRow(
                title: "補助表示の大きさ",
                value: themeNumericValue("guideFontSize"),
                fallback: IOSKeyboardPresentation.defaultGuideFontSize,
                range: 6...24
            ) {
                editor.setThemeToken(
                    "guideFontSize",
                    value: .decimal($0)
                )
            } onReset: {
                editor.setThemeToken(
                    "guideFontSize",
                    value: nil
                )
            }

            Divider()

            ProductDesignSliderRow(
                title: "補助表示の濃さ",
                value: themeNumericValue("guideOpacity"),
                fallback: IOSKeyboardPresentation.defaultGuideOpacity,
                range: 0...1
            ) {
                editor.setThemeToken(
                    "guideOpacity",
                    value: .decimal($0)
                )
            } onReset: {
                editor.setThemeToken(
                    "guideOpacity",
                    value: nil
                )
            }
        }
    }

    private func themeNumericValue(
        _ key: String
    ) -> Double? {
        let theme = editor.keyboardTheme
        return switch key {
        case "cornerRadius": theme.cornerRadius
        case "keyFontSize": theme.keyFontSize
        case "guideFontSize": theme.guideFontSize
        case "guideOpacity": theme.guideOpacity
        default: nil
        }
    }

    private func importTheme(
        _ result: Result<[URL], Error>
    ) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
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
            if (error as? CocoaError)?.code
                != .userCancelled {
                editor.errorMessage =
                    error.localizedDescription
            }
        }
    }

    private static func hex(_ color: Color) -> String {
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

private struct ProductDesignComparisonPreview: View {
    @ObservedObject var editor: ProfileV3EditorModel

    private let composition = ProfileV3PreviewComposition(
        primitives: [.boardKeys, .flickGuides]
    )

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let half = width / 2

            ZStack {
                previewLayer(
                    theme:
                        editor.persistedKeyboardTheme
                        ?? editor.keyboardTheme,
                    surface:
                        editor.persistedDesignPreviewSurface(),
                    unavailable:
                        "元ではこの段階が未保存です"
                )
                .frame(
                    width: width,
                    height: geometry.size.height
                )
                .mask {
                    HStack(spacing: 0) {
                        Rectangle()
                            .frame(width: half)
                        Spacer(minLength: 0)
                    }
                }

                previewLayer(
                    theme: editor.keyboardTheme,
                    surface:
                        editor.currentDesignPreviewSurface(),
                    unavailable:
                        "編集後を表示できません"
                )
                .frame(
                    width: width,
                    height: geometry.size.height
                )
                .mask {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle()
                            .frame(width: half)
                    }
                }

                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 1)
                    .accessibilityHidden(true)

                HStack(spacing: 0) {
                    Text("元")
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                    Text("編集後")
                        .frame(
                            maxWidth: .infinity,
                            alignment: .trailing
                        )
                }
                .font(.caption.bold())
                .padding(8)
                .frame(
                    maxHeight: .infinity,
                    alignment: .top
                )
                .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "保存済みと編集中のキーボード比較"
        )
    }

    @ViewBuilder
    private func previewLayer(
        theme: IOSKeyboardTheme,
        surface: FfiProfileV3BoardSurface?,
        unavailable: String
    ) -> some View {
        if let surface {
            ProfileV3ProductPreview(
                presentation:
                    IOSKeyboardPresentation(theme: theme),
                surface: surface,
                composition: composition
            )
        } else {
            Text(unavailable)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .background(
                    IOSKeyboardPresentation(theme: theme)
                        .swiftUIColor(.keyboardBackground)
                )
        }
    }
}

private struct ProductDesignSliderRow: View {
    let title: String
    let value: Double?
    let fallback: Double
    let range: ClosedRange<Double>
    let onChange: (Double) -> Void
    let onReset: () -> Void

    var body: some View {
        let step = range.upperBound <= 1 ? 0.1 : 1.0
        let current = min(
            range.upperBound,
            max(range.lowerBound, value ?? fallback)
        )
        let number = String(
            format: step < 1 ? "%.1f" : "%.0f",
            current
        )

        VStack(spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(value == nil ? "自動 · " + number : number)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if value != nil {
                    Button("自動", action: onReset)
                        .font(.caption)
                }
            }
            .frame(minHeight: 28)

            Slider(
                value: Binding(
                    get: { current },
                    set: onChange
                ),
                in: range,
                step: step
            )
            .frame(minHeight: 44)
            .accessibilityLabel(title)
        }
        .frame(minHeight: 72)
    }
}

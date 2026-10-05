import SwiftUI
import UIKit
import GestureIMEProfileAuthoring

/// #74 / #91 / #95 §F9: Theme editor whose preview is the shared keyboard
/// renderer drawing the edited Profile's actual initial Board. Theme edits are
/// presentation-only and never touch Board geometry or Actions.
struct ProfileV3ThemeEditorView: View {
    @ObservedObject var editor: ProfileV3EditorModel

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
        ("light", "細い"), ("regular", "標準"), ("medium", "中"), ("semibold", "やや太い"), ("bold", "太い")
    ]

    var body: some View {
        let theme = editor.keyboardTheme
        ProfileV3ResizableWorkspace(storageKey: "design") {
            ProfileV3ProductPreview(
                presentation: IOSKeyboardPresentation(theme: theme),
                surface: editor.previewSurface(),
                composition: .product
            )
        } secondary: {
        Form {
            Section("色") {
                ForEach(Self.colorLabels, id: \.0) { item in
                    let token = item.0
                    let label = item.1
                    HStack {
                        ColorPicker(
                            label,
                            selection: Binding(
                                get: { IOSKeyboardPresentation(theme: theme).swiftUIColor(IOSKeyboardColorRole(rawValue: token) ?? .keyFill) },
                                set: { editor.setThemeToken(token, value: .string(Self.hex($0))) }
                            )
                        )
                        if theme.colors[token] != nil {
                            Button("自動") { editor.setThemeToken(token, value: nil) }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                    }
                }
            }
            Section("形・文字") {
                numberRow("角の丸み", key: "cornerRadius", value: theme.cornerRadius, range: 0...24, fallback: 6)
                numberRow("キー文字の大きさ", key: "keyFontSize", value: theme.keyFontSize, range: 8...40, fallback: 23)
                Picker("キー文字の太さ", selection: Binding(
                    get: { theme.keyFontWeight ?? "" },
                    set: { editor.setThemeToken("keyFontWeight", value: $0.isEmpty ? nil : .string($0)) }
                )) {
                    Text("自動").tag("")
                    ForEach(Self.weightLabels, id: \.0) { Text($0.1).tag($0.0) }
                }
                numberRow("補助表示の大きさ", key: "guideFontSize", value: theme.guideFontSize, range: 6...24, fallback: 9)
                numberRow("補助表示の濃さ", key: "guideOpacity", value: theme.guideOpacity, range: 0...1, fallback: 0.6)
            }
        }
        }
        .navigationTitle(ProfileV3DisplayCatalog.title(.sectionDesign))
    }

    private func numberRow(
        _ title: String,
        key: String,
        value: Double?,
        range: ClosedRange<Double>,
        fallback: Double
    ) -> some View {
        let step = range.upperBound <= 1 ? 0.1 : 1
        return Stepper(
            onIncrement: {
                editor.setThemeToken(key, value: .decimal(min(range.upperBound, (value ?? fallback) + step)))
            },
            onDecrement: {
                editor.setThemeToken(key, value: .decimal(max(range.lowerBound, (value ?? fallback) - step)))
            }
        ) {
            HStack {
                Text(title)
                Spacer()
                Text(value.map { String(format: step < 1 ? "%.1f" : "%.0f", $0) } ?? "自動")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    static func hex(_ color: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X%02X", byte(r), byte(g), byte(b), byte(a))
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
        .padding(4)
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

import SwiftUI
import UIKit
import GestureIMEProfileAuthoring

/// #74 / #69 §12: simple Theme editor with live preview through the same
/// `IOSKeyboardTheme` token model the keyboard renderer uses. Theme edits are
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

    var body: some View {
        let theme = editor.keyboardTheme
        Form {
            Section("プレビュー") {
                ProfileV3ThemePreview(theme: theme)
                    .frame(height: 120)
            }
            Section("色") {
                ForEach(Self.colorLabels, id: \.0) { item in
                    let token = item.0
                    let label = item.1
                    HStack {
                        ColorPicker(
                            label,
                            selection: Binding(
                                get: { theme.uiColor(token) ?? Color.gray },
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
                numberRow("補助表示の大きさ", key: "guideFontSize", value: theme.guideFontSize, range: 6...24, fallback: 9)
                numberRow("補助表示の濃さ", key: "guideOpacity", value: theme.guideOpacity, range: 0...1, fallback: 0.6)
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

private struct ProfileV3ThemePreview: View {
    let theme: IOSKeyboardTheme

    var body: some View {
        let radius = CGFloat(theme.cornerRadius ?? 6)
        HStack(spacing: 6) {
            ForEach(["あ", "か", "さ"], id: \.self) { label in
                ZStack {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(theme.uiColor(label == "か" ? "keyPressedFill" : "keyFill") ?? Color(.systemGray5))
                        .overlay(
                            RoundedRectangle(cornerRadius: radius)
                                .stroke(theme.uiColor("border") ?? Color(.systemGray3))
                        )
                    Text(label)
                        .font(.system(size: CGFloat(theme.keyFontSize ?? 23)))
                        .foregroundStyle(theme.uiColor("text") ?? .primary)
                    Text("い")
                        .font(.system(size: CGFloat(theme.guideFontSize ?? 9)))
                        .foregroundStyle(theme.uiColor("guideText") ?? .primary)
                        .opacity(theme.guideOpacity ?? 0.6)
                        .offset(x: -24)
                }
                .frame(width: 80, height: 60)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.uiColor("keyboardBackground") ?? Color(.systemGray6))
        .accessibilityLabel("デザインのプレビュー")
    }
}

extension IOSKeyboardTheme {
    func uiColor(_ token: String) -> Color? {
        guard let value = colors[token] else { return nil }
        return Color(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
    }
}

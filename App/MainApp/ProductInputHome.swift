import SwiftUI
import GestureIMEProfileAuthoring

struct ProductInputHome: View {
    let editor: ProfileV3EditorModel?

    var body: some View {
        Group {
            if let editor {
                List {
                    NavigationLink {
                        ProductGestureSettings(editor: editor)
                    } label: {
                        Label("フリック判定", systemImage: "hand.draw")
                    }

                    NavigationLink {
                        ProductRuleIndex(editor: editor)
                    } label: {
                        Label("条件", systemImage: "arrow.triangle.branch")
                    }

                    NavigationLink {
                        ProductStateList(editor: editor)
                    } label: {
                        Label("状態", systemImage: "switch.2")
                    }

                    NavigationLink {
                        ProductTransformList(editor: editor)
                    } label: {
                        Label("文字変換", systemImage: "character.textbox")
                    }

                    NavigationLink {
                        ProductMacroList(editor: editor)
                    } label: {
                        Label("マクロ", systemImage: "list.bullet.rectangle")
                    }

                    NavigationLink {
                        ProductConversionStatus()
                    } label: {
                        HStack {
                            Label("変換・辞書", systemImage: "text.book.closed")
                            Spacer()
                            Text("端末内")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                ProductEmptyWorkspace()
            }
        }
        .navigationTitle("入力")
    }
}

struct ProductGestureSettings: View {
    @ObservedObject var editor: ProfileV3EditorModel

    var body: some View {
        List {
            if let values = editor.policyValues {
                ForEach(ProfileV3GesturePolicyField.allCases) { field in
                    ProductGestureSettingRow(
                        field: field,
                        values: values
                    ) { next in
                        editor.updatePolicyValues(next)
                    }
                }
            }
        }
        .navigationTitle("フリック判定")
        .safeAreaInset(edge: .bottom) {
            if let message = editor.errorMessage {
                ProductInlineError(message: message) {
                    editor.errorMessage = nil
                }
            }
        }
    }
}

private struct ProductGestureSettingRow: View {
    let field: ProfileV3GesturePolicyField
    let values: ProfileV3GesturePolicyValues
    let onChange: (ProfileV3GesturePolicyValues) -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(ProfileV3DisplayCatalog.title(field.displayKey))
                ProductInfoButton(
                    title: ProfileV3DisplayCatalog.title(field.displayKey),
                    message: help
                )
                Spacer()
                Text(valueText(values.value(field)))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { values.value(field) },
                    set: { value in
                        var next = values
                        next.set(field, value)
                        onChange(next)
                    }
                ),
                in: field.range,
                step: field.step
            )
            .accessibilityLabel(ProfileV3DisplayCatalog.title(field.displayKey))
        }
        .frame(minHeight: 64)
    }

    private var help: String {
        switch field {
        case .deadZone:
            "指を動かしてもフリックとして扱わない中心付近の範囲です。"
        case .initialCellCommitDistance:
            "最初の方向を確定するまでに必要な移動量です。"
        case .subsequentCellCommitDistance:
            "次の段階で方向を確定するまでに必要な移動量です。"
        case .angularHysteresisDegrees:
            "方向境界付近で判定が揺れにくくなる幅です。"
        case .stageBacktrackDwellMs:
            "前の段階へ戻る判定までの滞在時間です。"
        }
    }

    private func valueText(_ value: Double) -> String {
        switch field {
        case .stageBacktrackDwellMs:
            "\(Int(value.rounded())) ms"
        case .angularHysteresisDegrees:
            "\(Int(value.rounded()))°"
        default:
            String(format: "%.2f", value)
        }
    }
}

struct ProductConversionStatus: View {
    var body: some View {
        List {
            LabeledContent("かな漢字変換") {
                Text("端末内")
            }
            LabeledContent("入力の学習") {
                Text("オフ")
            }
        }
        .navigationTitle("変換・辞書")
    }
}

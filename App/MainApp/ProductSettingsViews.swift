import Foundation
import SwiftUI
import GestureIMEProfileAuthoring

struct ProductSettingsHome: View {
    @EnvironmentObject private var productSettings:
        ProductSettingsModel

    let editor: ProfileV3EditorModel?
    @State private var confirmingReset = false

    var body: some View {
        List {
            Section {
                hapticRow
                heightRow
                keySoundRow
            } header: {
                HStack(spacing: 2) {
                    Text("キーボード")
                    ProductInfoButton(
                        title: "キーボードの追加方法",
                        message:
                            "iPhoneの「設定」→「一般」→「キーボード」→「キーボード」→「新しいキーボードを追加」からGesture IMEを有効にします。入力欄では地球儀キーから切り替えます。"
                    )
                }
            }

            if !productSettings.isEditable {
                Section {
                    Label(
                        productSettings.deliveryStatus,
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            Section("情報") {
                LabeledContent("表示言語") {
                    Text("日本語（固定）")
                        .foregroundStyle(.secondary)
                }

                if let editor {
                    NavigationLink {
                        ProductDeveloperView(editor: editor)
                    } label: {
                        Label("開発者", systemImage: "hammer")
                    }
                }
            }

            Section("プライバシー") {
                Text(
                    "フルアクセス不要。入力内容の学習・送信は行わず、かな漢字変換は端末内で処理します。"
                )
                .font(.footnote)
            }
        }
        .navigationTitle("設定")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        confirmingReset = true
                    } label: {
                        Label(
                            "キーボード設定を初期値に戻す",
                            systemImage: "arrow.counterclockwise"
                        )
                    }
                    .disabled(!productSettings.isEditable)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("設定の操作")
            }
        }
        .confirmationDialog(
            "キーボード設定を初期値に戻しますか？",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("初期値に戻す", role: .destructive) {
                productSettings.reset()
            }
            Button("キャンセル", role: .cancel) {}
        }
        .safeAreaInset(edge: .bottom) {
            if let message = productSettings.errorMessage {
                ProductInlineError(message: message) {
                    productSettings.errorMessage = nil
                }
            }
        }
    }

    private var hapticRow: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                Text("触覚")
                ProductInfoButton(
                    title: "触覚",
                    message:
                        "キーボードの触覚フィードバック強度です。「試す」はアプリ側の触覚経路だけを確認し、キーボード本体での発生までは保証しません。"
                )

                Spacer()

                Text(
                    productSettings.values.hapticStrength == 0
                        ? "オフ"
                        : String(
                            format: "%.1f",
                            productSettings.values.hapticStrength
                        )
                )
                .foregroundStyle(.secondary)
                .monospacedDigit()

                Button("試す") {
                    productSettings.testHaptic()
                }
                .buttonStyle(.bordered)
            }

            Slider(
                value: Binding(
                    get: {
                        productSettings.values.hapticStrength
                    },
                    set: {
                        productSettings.setHapticStrength($0)
                    }
                ),
                in: 0...1,
                step: 0.1
            )
            .disabled(!productSettings.isEditable)
            .accessibilityLabel("触覚の強さ")

            if let status = productSettings.hapticTestStatus {
                HStack(alignment: .top, spacing: 6) {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                    Button {
                        productSettings.clearHapticTestStatus()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("触覚テスト結果を閉じる")
                }
            }
        }
        .frame(minHeight: 72)
    }

    private var heightRow: some View {
        let stored =
            productSettings.values.keyboardHeightScale
        let ordinary =
            ProfileV3SettingsLayoutPolicy
                .ordinaryHeightScaleValue(
                    storedScale: stored
                )
        let outside =
            ProfileV3SettingsLayoutPolicy
                .isOutsideOrdinaryHeightScaleRange(
                    stored
                )

        return VStack(spacing: 4) {
            HStack(spacing: 2) {
                Text("キーボード高さ")
                ProductInfoButton(
                    title: "キーボード高さ",
                    message:
                        "通常設定では0.80〜1.25倍の実用範囲だけを選べます。以前の保存値が範囲外でも、スライダーを動かすまでは値を保持します。"
                )
                Spacer()
                Text(
                    String(format: "%.2f倍", stored)
                )
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { ordinary },
                    set: {
                        productSettings
                            .setKeyboardHeightScale($0)
                    }
                ),
                in:
                    ProfileV3SettingsLayoutPolicy
                        .ordinaryHeightScaleRange,
                step:
                    ProfileV3SettingsLayoutPolicy
                        .ordinaryHeightScaleStep
            )
            .disabled(!productSettings.isEditable)
            .accessibilityLabel("キーボード高さ")

            if outside {
                Text(
                    "保存値は通常設定の範囲外です。スライダーを動かすと通常範囲へ戻ります。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
            }
        }
        .frame(minHeight: 72)
    }

    private var keySoundRow: some View {
        HStack(spacing: 2) {
            Text("キー音")
            ProductInfoButton(
                title: "キー音",
                message:
                    "Gesture IMEのキー音を切り替えます。実際の音量・消音はiOSの「キーボードのクリック」設定に従います。"
            )

            Spacer()

            Toggle(
                "キー音",
                isOn: Binding(
                    get: {
                        productSettings.effectiveKeySoundEnabled
                    },
                    set: {
                        productSettings.setKeySound($0)
                    }
                )
            )
            .labelsHidden()
            .disabled(!productSettings.keySoundEditable)
        }
        .frame(minHeight: 52)
    }
}

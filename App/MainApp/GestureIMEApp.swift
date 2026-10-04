import Foundation
import SwiftUI
import GestureIMEProfileAuthoring

@main
struct GestureIMEApp: App {
    @StateObject private var library = ProfileLibraryModel()
    @StateObject private var productSettings = ProductSettingsModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(productSettings)
        }
    }
}

private struct RootView: View {
    var body: some View {
        TabView {
            ProfileLibraryView()
                .tabItem {
                    Label("キーボード", systemImage: "keyboard")
                }

            SetupView()
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
        }
    }
}

private struct SetupView: View {
    @EnvironmentObject private var productSettings: ProductSettingsModel

    var body: some View {
        NavigationStack {
            List {
                Section("キーボードの追加") {
                    Text("Gesture IME はiPhoneのキーボードとして使えます。")
                    Text("設定 → 一般 → キーボード → キーボード → 新しいキーボードを追加 から有効にします。")
                    Text("入力欄で地球儀キーを押してキーボードを切り替えます。")
                }

                Section(ProfileV3DisplayCatalog.title(.sectionKeyboardSettings)) {
                    Stepper(
                        onIncrement: productSettings.incrementHaptic,
                        onDecrement: productSettings.decrementHaptic
                    ) {
                        HStack {
                            Text("触覚フィードバックの強さ")
                            Spacer()
                            Text(String(format: "%.2f", productSettings.values.hapticStrength))
                                .monospacedDigit()
                        }
                    }

                    Stepper(
                        onIncrement: productSettings.incrementHeightScale,
                        onDecrement: productSettings.decrementHeightScale
                    ) {
                        HStack {
                            Text("キーボードの高さ")
                            Spacer()
                            Text(String(format: "%.2fx", productSettings.values.keyboardHeightScale))
                                .monospacedDigit()
                        }
                    }

                    Button("キーボード設定を初期値に戻す") {
                        productSettings.reset()
                    }

                    if let errorMessage = productSettings.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("設定の反映") {
                    Text(productSettings.deliveryStatus)
                    Text("触覚と高さはこの端末の設定で、キーボード配置データには保存されません。")
                }

                Section("キーボード配置の反映") {
                    Text("このアプリでキーボード配置を編集・検証します。")
                    Text("編集した配置をキーボード本体へ反映する機能は、共有領域の権限が用意されるまで利用できません。")
                }
            }
            .navigationTitle("Gesture IME")
        }
    }
}

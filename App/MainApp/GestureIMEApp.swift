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

/// #92 / #95 §F7: four tabs; all eight categories are ≤1 tap from the root.
/// Every tab works on one shared editor model for the selected Profile.
@MainActor
final class ProfileV3Workspace: ObservableObject {
    @Published var selectedProfileID: String?
    private var editors: [String: ProfileV3EditorModel] = [:]

    func editor(library: ProfileLibraryModel) -> ProfileV3EditorModel? {
        let v3IDs = library.profiles.map(\.id).filter { library.isProfileV3(profileID: $0) }
        let id = [selectedProfileID, library.activeProfileID].compactMap { $0 }
            .first(where: v3IDs.contains) ?? v3IDs.first
        guard let id else { return nil }
        if let cached = editors[id] { return cached }
        let created = ProfileV3EditorModel(library: library, profileID: id)
        editors[id] = created
        return created
    }
}

private struct RootView: View {
    @EnvironmentObject private var library: ProfileLibraryModel
    @StateObject private var workspace = ProfileV3Workspace()

    var body: some View {
        let editor = workspace.editor(library: library)
        TabView {
            NavigationStack {
                Group {
                    if let editor {
                        ProfileV3OverviewEditorView(library: library, editor: editor)
                            .id(editor.profileID)
                    } else {
                        ProfileV3EmptyWorkspace()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        ProfileV3ProfileMenu(workspace: workspace)
                    }
                }
            }
            .tabItem { Label(ProfileV3AppTab.edit.title, systemImage: "keyboard") }

            NavigationStack {
                List {
                    if let editor {
                        NavigationLink {
                            ProfileV3InputSettingsView(editor: editor)
                        } label: {
                            Label(ProfileV3AppCategory.inputSettings.title, systemImage: "hand.draw")
                        }
                        NavigationLink {
                            ProfileV3TransformEditorView(editor: editor)
                        } label: {
                            Label(ProfileV3AppCategory.conversionDictionary.title, systemImage: "character.textbox")
                        }
                    } else {
                        ProfileV3EmptyWorkspace()
                    }
                    Section("変換・辞書の状態") {
                        Text("かな漢字変換はこの端末内の辞書で行います。")
                        Text("入力の学習は行いません（学習機能はオフです）。")
                    }
                }
                .navigationTitle(ProfileV3AppTab.input.title)
            }
            .tabItem { Label(ProfileV3AppTab.input.title, systemImage: "hand.draw") }

            NavigationStack {
                if let editor {
                    ProfileV3ThemeEditorView(editor: editor)
                        .id(editor.profileID)
                } else {
                    ProfileV3EmptyWorkspace()
                }
            }
            .tabItem { Label(ProfileV3AppTab.design.title, systemImage: "paintpalette") }

            NavigationStack {
                List {
                    NavigationLink {
                        SetupView()
                    } label: {
                        Label(ProfileV3AppCategory.keyboardSettings.title, systemImage: "slider.horizontal.3")
                    }
                    NavigationLink {
                        ProfileV3LanguageView(editor: editor)
                    } label: {
                        Label(ProfileV3AppCategory.language.title, systemImage: "globe")
                    }
                    NavigationLink {
                        ProfileV3PrivacyView()
                    } label: {
                        Label(ProfileV3AppCategory.privacy.title, systemImage: "hand.raised")
                    }
                    NavigationLink {
                        ProfileLibraryView()
                    } label: {
                        Label(ProfileV3AppCategory.advanced.title, systemImage: "wrench.and.screwdriver")
                    }
                }
                .navigationTitle(ProfileV3AppTab.settings.title)
            }
            .tabItem { Label(ProfileV3AppTab.settings.title, systemImage: "gearshape") }
        }
    }
}

private struct ProfileV3ProfileMenu: View {
    @EnvironmentObject private var library: ProfileLibraryModel
    @ObservedObject var workspace: ProfileV3Workspace

    var body: some View {
        Menu {
            ForEach(library.profiles.filter { library.isProfileV3(profileID: $0.id) }) { profile in
                Button {
                    workspace.selectedProfileID = profile.id
                } label: {
                    if library.activeProfileID == profile.id {
                        Label(profile.name, systemImage: "checkmark.circle")
                    } else {
                        Text(profile.name)
                    }
                }
            }
            Divider()
            Button {
                library.createEmptyV3()
                workspace.selectedProfileID = library.profiles.last?.id
            } label: {
                Label("新しいキーボード", systemImage: "plus")
            }
        } label: {
            Label("キーボード一覧", systemImage: "list.bullet")
        }
    }
}

private struct ProfileV3EmptyWorkspace: View {
    @EnvironmentObject private var library: ProfileLibraryModel

    var body: some View {
        VStack(spacing: 12) {
            Text("編集できるキーボードがありません。")
            Button("新しいキーボードを作る") { library.createEmptyV3() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

private struct ProfileV3LanguageView: View {
    let editor: ProfileV3EditorModel?

    var body: some View {
        List {
            Section("表示言語") {
                Text("日本語")
            }
            Section {
                if let editor, !editor.layers.isEmpty {
                    ForEach(editor.layers) { layer in
                        HStack {
                            Text(layer.name ?? layer.id)
                            Spacer()
                            if layer.isInitial {
                                Text("最初に表示").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("キーボード面がありません。")
                }
            } header: {
                Text("入力に使うキーボード面")
            } footer: {
                Text("キーボード面の追加・並べ替えは「編集」から行います。")
            }
        }
        .navigationTitle("言語")
    }
}

private struct ProfileV3PrivacyView: View {
    var body: some View {
        List {
            Text("フルアクセスは要求しません。")
            Text("入力内容の学習・送信は行いません。")
            Text("かな漢字変換はこの端末内で完結します。")
        }
        .navigationTitle("プライバシー")
    }
}

private struct SetupView: View {
    @EnvironmentObject private var productSettings: ProductSettingsModel

    var body: some View {
        List {
                Section("キーボードの追加") {
                    Text("Gesture IME はiPhoneのキーボードとして使えます。")
                    Text("設定 → 一般 → キーボード → キーボード → 新しいキーボードを追加 から有効にします。")
                    Text("入力欄で地球儀キーを押してキーボードを切り替えます。")
                }

                Section {
                    Group {
                        Stepper(
                            onIncrement: productSettings.incrementHaptic,
                            onDecrement: productSettings.decrementHaptic
                        ) {
                            HStack {
                                Text("触覚フィードバックの強さ")
                                Spacer()
                                Text(String(format: "%.1f", productSettings.values.hapticStrength))
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
                                Text(String(format: "%.2f倍", productSettings.values.keyboardHeightScale))
                                    .monospacedDigit()
                            }
                        }

                        Toggle("キーを押したときの音", isOn: Binding(
                            get: { productSettings.values.keySoundEnabled },
                            set: { productSettings.setKeySound($0) }
                        ))
                        Text("音の有無・大きさは iOS の「設定 → サウンドと触覚 → キーボードのフィードバック → サウンド」にも従います。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("キーボード設定を初期値に戻す") {
                            productSettings.reset()
                        }
                    }
                    .disabled(!productSettings.isEditable)

                    if let errorMessage = productSettings.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(ProfileV3DisplayCatalog.title(.sectionKeyboardSettings))
                } footer: {
                    if !productSettings.isEditable {
                        Label(productSettings.deliveryStatus, systemImage: "lock")
                            .accessibilityLabel("利用できません: " + productSettings.deliveryStatus)
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
            .navigationTitle("キーボード設定")
    }
}

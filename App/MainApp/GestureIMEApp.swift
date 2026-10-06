import Foundation
import SwiftUI
import GestureIMEProfileAuthoring
import GestureIMEProductSettings

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
    private let editors = ProfileV3EditorSessionCache<ProfileV3EditorModel>()

    func resolvedProfileID(library: ProfileLibraryModel) -> String? {
        let v3IDs = library.profiles.map(\.id).filter { library.isProfileV3(profileID: $0) }
        return [selectedProfileID, library.activeProfileID].compactMap { $0 }
            .first(where: v3IDs.contains) ?? v3IDs.first
    }

    func editor(library: ProfileLibraryModel) -> ProfileV3EditorModel? {
        guard let id = resolvedProfileID(library: library) else { return nil }
        return editors.session(for: id) {
            ProfileV3EditorModel(library: library, profileID: id)
        }
    }

    func existingEditor(profileID: String) -> ProfileV3EditorModel? {
        editors.existingSession(for: profileID)
    }

    func select(profileID: String) {
        selectedProfileID = profileID
    }

    func removeSession(profileID: String) {
        editors.remove(profileID: profileID)
        if selectedProfileID == profileID {
            selectedProfileID = nil
        }
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
                .toolbar { profileScopeToolbar }
            }
            .tabItem { Label(ProfileV3AppTab.edit.title, systemImage: "keyboard") }

            NavigationStack {
                ProfileV3InputLandingView(editor: editor)
                    .toolbar { profileScopeToolbar }
            }
            .tabItem { Label(ProfileV3AppTab.input.title, systemImage: "hand.draw") }

            NavigationStack {
                Group {
                    if let editor {
                        ProfileV3ThemeEditorView(editor: editor)
                            .id(editor.profileID)
                    } else {
                        ProfileV3EmptyWorkspace()
                    }
                }
                .toolbar { profileScopeToolbar }
            }
            .tabItem { Label(ProfileV3AppTab.design.title, systemImage: "paintpalette") }

            NavigationStack {
                ProfileV3SettingsLandingView(editor: editor)
                    .toolbar { profileScopeToolbar }
            }
            .tabItem { Label(ProfileV3AppTab.settings.title, systemImage: "gearshape") }
        }
    }

    @ToolbarContentBuilder
    private var profileScopeToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            ProfileV3ProfileMenu(workspace: workspace)
        }
    }
}

private struct ProfileV3InputLandingView: View {
    let editor: ProfileV3EditorModel?

    var body: some View {
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
                    Label(ProfileV3AppCategory.transformTables.title, systemImage: "character.textbox")
                }

                NavigationLink {
                    ProfileV3SemanticCollectionOverview(editor: editor, kind: .states)
                } label: {
                    Label(ProfileV3AppCategory.states.title, systemImage: "switch.2")
                }

                NavigationLink {
                    ProfileV3SemanticCollectionOverview(editor: editor, kind: .macros)
                } label: {
                    Label(ProfileV3AppCategory.macros.title, systemImage: "list.bullet.rectangle")
                }

                NavigationLink {
                    ProfileV3ConversionStatusView()
                } label: {
                    HStack {
                        Label(ProfileV3AppCategory.conversionDictionary.title, systemImage: "text.book.closed")
                        Spacer()
                        Text("端末内・学習オフ")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ProfileV3EmptyWorkspace()
            }
        }
        .navigationTitle(ProfileV3AppTab.input.title)
    }
}

private enum ProfileV3SemanticCollectionKind {
    case states
    case macros

    var title: String {
        switch self {
        case .states: ProfileV3AppCategory.states.title
        case .macros: ProfileV3AppCategory.macros.title
        }
    }

    var systemImage: String {
        switch self {
        case .states: "switch.2"
        case .macros: "list.bullet.rectangle"
        }
    }

    @MainActor
    func count(in editor: ProfileV3EditorModel) -> Int {
        switch self {
        case .states: editor.states.count
        case .macros: editor.macros.count
        }
    }
}

private struct ProfileV3SemanticCollectionOverview: View {
    @ObservedObject var editor: ProfileV3EditorModel
    let kind: ProfileV3SemanticCollectionKind

    var body: some View {
        List {
            let count = kind.count(in: editor)
            if count == 0 {
                ContentUnavailableView(
                    "\(kind.title)はありません",
                    systemImage: kind.systemImage
                )
            } else {
                LabeledContent("登録済み") {
                    Text("\(count)件")
                        .monospacedDigit()
                }
            }
        }
        .navigationTitle(kind.title)
    }
}

private struct ProfileV3ConversionStatusView: View {
    var body: some View {
        List {
            LabeledContent("かな漢字変換") {
                Text("端末内")
            }
            LabeledContent("入力の学習") {
                Text("オフ")
            }
        }
        .navigationTitle(ProfileV3AppCategory.conversionDictionary.title)
    }
}

private struct ProfileV3SettingsLandingView: View {
    let editor: ProfileV3EditorModel?

    var body: some View {
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
                if let editor {
                    ProfileV3AdvancedSettingsView(editor: editor)
                        .id(editor.profileID)
                } else {
                    ProfileV3EmptyWorkspace()
                }
            } label: {
                Label(ProfileV3AppCategory.advanced.title, systemImage: "hammer")
            }
        }
        .navigationTitle(ProfileV3AppTab.settings.title)
    }
}

private struct ProfileV3ProfileMenu: View {
    @EnvironmentObject private var library: ProfileLibraryModel
    @ObservedObject var workspace: ProfileV3Workspace
    @State private var showingManager = false

    var body: some View {
        let profiles = library.profiles.filter { library.isProfileV3(profileID: $0.id) }
        let scopedID = workspace.resolvedProfileID(library: library)
        let scopedName = profiles.first(where: { $0.id == scopedID })?.name

        Menu {
            ForEach(profiles) { profile in
                Button {
                    workspace.select(profileID: profile.id)
                } label: {
                    if scopedID == profile.id {
                        Label(profile.name, systemImage: "checkmark")
                    } else {
                        Text(profile.name)
                    }
                }
            }

            Divider()

            Button {
                showingManager = true
            } label: {
                Label("キーボードを管理", systemImage: "list.bullet")
            }

            Button {
                if let id = library.createEmptyV3() {
                    workspace.select(profileID: id)
                }
            } label: {
                Label("新しいキーボード", systemImage: "plus")
            }
        } label: {
            Label(scopedName ?? "キーボード", systemImage: "keyboard")
        }
        .accessibilityLabel("編集中のキーボード: " + (scopedName ?? "なし"))
        .sheet(isPresented: $showingManager) {
            NavigationStack {
                ProfileLibraryView(workspace: workspace)
            }
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
    @EnvironmentObject private var library: ProfileLibraryModel

    var body: some View {
        List {
                Section("キーボードの追加") {
                    Text("Gesture IME はiPhoneのキーボードとして使えます。")
                    Text("設定 → 一般 → キーボード → キーボード → 新しいキーボードを追加 から有効にします。")
                    Text("入力欄で地球儀キーを押してキーボードを切り替えます。")
                }

                Section {
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
                    .disabled(!productSettings.isEditable)

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
                    .disabled(!productSettings.isEditable)

                    Toggle("キーを押したときの音", isOn: Binding(
                        get: { productSettings.effectiveKeySoundEnabled },
                        set: { productSettings.setKeySound($0) }
                    ))
                    .disabled(!productSettings.keySoundEditable)

                    Text(productSettings.keySoundStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("キーボード設定を初期値に戻す") {
                        productSettings.reset()
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
                    Text("触覚・高さはこの端末の設定で、キーボード配置データには保存されません。")
                    Text(productSettings.keySoundStatus)
                }

                Section("キーボード配置の反映") {
                    Text("このアプリでキーボード配置を編集・検証します。")
                    Text(library.profileDeliveryStatus)
                }


            }
            .navigationTitle("キーボード設定")
    }
}

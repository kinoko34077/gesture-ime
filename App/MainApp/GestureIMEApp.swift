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
                    ProfileV3StateEditorView(editor: editor)
                } label: {
                    Label(ProfileV3AppCategory.states.title, systemImage: "switch.2")
                }

                NavigationLink {
                    ProfileV3MacroEditorView(editor: editor)
                } label: {
                    Label(
                        ProfileV3AppCategory.macros.title,
                        systemImage: "list.bullet.rectangle"
                    )
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
                Label("開発者", systemImage: "hammer")
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
    @EnvironmentObject private var productSettings:
        ProductSettingsModel

    @State private var helpTopic:
        KeyboardSettingsHelpTopic?
    @State private var confirmingReset = false

    var body: some View {
        GeometryReader { geometry in
            let inset = CGFloat(
                ProfileV3SettingsLayoutPolicy
                    .contentInset(
                        usableWidth:
                            Double(geometry.size.width)
                    )
            )

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: CGFloat(
                        ProfileV3SettingsLayoutPolicy
                            .sectionGap
                    )
                ) {
                    setupHelpRow

                    VStack(
                        alignment: .leading,
                        spacing: 0
                    ) {
                        hapticSliderRow

                        Divider()

                        heightSliderRow

                        Divider()

                        keySoundRow

                        if !productSettings.isEditable {
                            Divider()

                            Label(
                                productSettings.deliveryStatus,
                                systemImage: "lock"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: CGFloat(
                                    ProfileV3SettingsLayoutPolicy
                                        .ordinaryRowMinimumHeight
                                ),
                                alignment: .leading
                            )
                            .accessibilityLabel(
                                "利用できません: "
                                    + productSettings
                                        .deliveryStatus
                            )
                        }
                    }

                }
                .padding(.horizontal, inset)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("キーボード設定")
        .toolbar {
            ToolbarItem(
                placement: .topBarTrailing
            ) {
                Menu {
                    Button(
                        role: .destructive
                    ) {
                        confirmingReset = true
                    } label: {
                        Label(
                            "初期値に戻す",
                            systemImage:
                                "arrow.counterclockwise"
                        )
                    }
                    .disabled(
                        !productSettings.isEditable
                    )
                } label: {
                    Image(
                        systemName: "ellipsis.circle"
                    )
                }
                .accessibilityLabel(
                    "キーボード設定のその他の操作"
                )
            }
        }
        .sheet(item: $helpTopic) { topic in
            KeyboardSettingsHelpSheet(topic: topic)
        }
        .alert(
            "初期値に戻しますか？",
            isPresented: $confirmingReset
        ) {
            Button("キャンセル", role: .cancel) {}
            Button(
                "初期値に戻す",
                role: .destructive
            ) {
                productSettings.reset()
            }
        } message: {
            Text(
                "触覚の強さ、キーボードの高さ、キー音を初期値へ戻します。"
            )
        }
        .safeAreaInset(edge: .bottom) {
            if let message =
                    productSettings.errorMessage {
                ProfileV3InlineAuthoringError(
                    message: message,
                    correctionHint:
                        "設定の共有状態を確認して、もう一度操作してください。"
                )
            }
        }
    }

    private var setupHelpRow: some View {
        Button {
            helpTopic = .setup
        } label: {
            HStack(spacing: 8) {
                Label(
                    "キーボードの追加方法",
                    systemImage: "keyboard"
                )

                Spacer(minLength: 8)

                Image(systemName: "info.circle")
                    .font(.system(size: 17))
                    .accessibilityHidden(true)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: CGFloat(
                    ProfileV3SettingsLayoutPolicy
                        .ordinaryRowMinimumHeight
                ),
                alignment: .leading
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(
            "iPhoneでGesture IMEを有効にする方法を表示します"
        )
    }

    private var hapticSliderRow: some View {
        settingsSliderRow(
            title: "触覚フィードバックの強さ",
            valueText: String(
                format: "%.1f",
                productSettings.values.hapticStrength
            ),
            accessibilityValue: String(
                format: "%.1f",
                productSettings.values.hapticStrength
            )
        ) {
            Slider(
                value: Binding(
                    get: {
                        productSettings
                            .values
                            .hapticStrength
                    },
                    set: {
                        productSettings
                            .setHapticStrength($0)
                    }
                ),
                in: 0...1
            )
            .disabled(!productSettings.isEditable)
        }
    }

    private var heightSliderRow: some View {
        settingsSliderRow(
            title: "キーボードの高さ",
            valueText: String(
                format: "%.2f倍",
                productSettings
                    .values
                    .keyboardHeightScale
            ),
            accessibilityValue: String(
                format: "%.2f倍",
                productSettings
                    .values
                    .keyboardHeightScale
            )
        ) {
            Slider(
                value: Binding(
                    get: {
                        ProfileV3SettingsLayoutPolicy
                            .heightSliderPosition(
                                scale:
                                    productSettings
                                        .values
                                        .keyboardHeightScale
                            )
                    },
                    set: { position in
                        productSettings
                            .setKeyboardHeightScale(
                                ProfileV3SettingsLayoutPolicy
                                    .heightScale(
                                        sliderPosition:
                                            position
                                    )
                            )
                    }
                ),
                in: 0...1
            )
            .disabled(!productSettings.isEditable)
            .accessibilityHint(
                "中央が1.00倍です"
            )
        }
    }

    private var keySoundRow: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            HStack(spacing: 4) {
                Text("キーを押したときの音")

                Button {
                    helpTopic = .keySound
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "キー音の説明"
                )

                Spacer(minLength: 8)

                Toggle(
                    "キー音",
                    isOn: Binding(
                        get: {
                            productSettings
                                .effectiveKeySoundEnabled
                        },
                        set: {
                            productSettings
                                .setKeySound($0)
                        }
                    )
                )
                .labelsHidden()
                .disabled(
                    !productSettings.keySoundEditable
                )
            }
            .frame(
                minHeight: CGFloat(
                    ProfileV3SettingsLayoutPolicy
                        .ordinaryRowMinimumHeight
                )
            )

            if productSettings.isEditable
                && !productSettings.keySoundEditable {
                Text(productSettings.keySoundStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                    .accessibilityLabel(
                        "キー音を利用できません: "
                            + productSettings.keySoundStatus
                    )
            }
        }
    }

    private func settingsSliderRow<Control: View>(
        title: String,
        valueText: String,
        accessibilityValue: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)

                Spacer(minLength: 8)

                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(
                minHeight: CGFloat(
                    ProfileV3SettingsLayoutPolicy
                        .sliderLabelLineHeight
                )
            )

            control()
                .frame(
                    minHeight: CGFloat(
                        ProfileV3SettingsLayoutPolicy
                            .sliderAllocation
                    )
                )
                .accessibilityLabel(title)
                .accessibilityValue(
                    accessibilityValue
                )
        }
        .frame(
            minHeight: CGFloat(
                ProfileV3SettingsLayoutPolicy
                    .sliderRowBaseHeight
            )
        )
    }


}

private enum KeyboardSettingsHelpTopic:
    String,
    Identifiable {
    case setup
    case keySound

    var id: String { rawValue }

    var title: String {
        switch self {
        case .setup:
            "キーボードの追加方法"
        case .keySound:
            "キー音"
        }
    }

    var body: String {
        switch self {
        case .setup:
            """
            iPhoneの「設定」→「一般」→「キーボード」→「キーボード」→「新しいキーボードを追加」からGesture IMEを有効にします。

            入力欄では地球儀キーからGesture IMEへ切り替えます。
            """

        case .keySound:
            """
            Gesture IMEのキー音を切り替えます。実際の音量・消音はiOSの「キーボードのクリック」設定に従います。
            """
        }
    }
}

private struct KeyboardSettingsHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    let topic: KeyboardSettingsHelpTopic

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(topic.body)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                    .padding(16)
            }
            .navigationTitle(topic.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}

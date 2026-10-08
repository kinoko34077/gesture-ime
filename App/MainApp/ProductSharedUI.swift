import SwiftUI
import UniformTypeIdentifiers
import GestureIMEProfileAuthoring

struct ProductInfoButton: View {
    let title: String
    let message: String
    @State private var presented = false

    var body: some View {
        Button {
            presented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 16))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + "の説明")
        .popover(isPresented: $presented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
            }
            .padding(16)
            .frame(idealWidth: 280, maxWidth: 320, alignment: .leading)
            .presentationCompactAdaptation(.popover)
        }
    }
}

struct ProductInlineError: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("閉じる")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .accessibilityElement(children: .combine)
    }
}

struct ProductSectionHeader: View {
    let title: String
    let help: String?

    init(_ title: String, help: String? = nil) {
        self.title = title
        self.help = help
    }

    var body: some View {
        HStack(spacing: 2) {
            Text(title)
                .font(.subheadline.bold())
            if let help {
                ProductInfoButton(title: title, message: help)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
    }
}

struct ProductTextEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let label: String
    let initialValue: String
    let onSave: (String) -> Void

    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField(label, text: $text)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { text = initialValue }
        }
    }
}

struct ProductEmptyWorkspace: View {
    @EnvironmentObject private var library: ProfileLibraryModel

    var body: some View {
        ContentUnavailableView {
            Label("キーボードがありません", systemImage: "keyboard")
        } description: {
            Text("新しいキーボードを作成すると編集を始められます。")
        } actions: {
            Button("新しいキーボード") {
                _ = library.createEmptyV3()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct ProductProfileScopeButton: View {
    @EnvironmentObject private var library: ProfileLibraryModel
    @ObservedObject var workspace: ProfileV3Workspace
    @State private var showingManager = false
    @State private var activationError: String?

    var body: some View {
        let profiles = library.profiles.filter {
            library.isProfileV3(profileID: $0.id)
        }
        let selectedID = workspace.resolvedProfileID(library: library)
        let selectedName = profiles.first(where: { $0.id == selectedID })?.name
        let activeName = profiles.first {
            $0.id == library.activeProfileID
        }?.name

        Menu {
            Section("編集中") {
                ForEach(profiles) { profile in
                    Button {
                        workspace.select(profileID: profile.id)
                    } label: {
                        if selectedID == profile.id {
                            Label(profile.name, systemImage: "checkmark")
                        } else {
                            Text(profile.name)
                        }
                    }
                }
            }

            Section("使用中") {
                Text(activeName ?? "なし")
            }

            if let selectedID, selectedID != library.activeProfileID {
                Button {
                    let editor = workspace.editor(library: library)
                    if editor?.saveAndActivateForKeyboard() != true {
                        activationError = editor?.errorMessage
                            ?? "キーボードを切り替えられませんでした。"
                    }
                } label: {
                    Label(
                        requiresSave(profileID: selectedID)
                            ? "保存して使う"
                            : "このキーボードを使う",
                        systemImage: "checkmark.circle"
                    )
                }
            }

            Divider()

            Button {
                if let id = library.createEmptyV3() {
                    workspace.select(profileID: id)
                }
            } label: {
                Label("新しいキーボード", systemImage: "plus")
            }

            Button {
                showingManager = true
            } label: {
                Label("キーボードを管理", systemImage: "list.bullet")
            }
        } label: {
            Label(selectedName ?? "キーボード", systemImage: "keyboard")
                .lineLimit(1)
        }
        .accessibilityLabel("編集中のキーボード: " + (selectedName ?? "なし"))
        .sheet(isPresented: $showingManager) {
            NavigationStack {
                ProductProfileManagerView(workspace: workspace)
            }
        }
        .alert(
            "キーボードを切り替えられません",
            isPresented: Binding(
                get: { activationError != nil },
                set: { if !$0 { activationError = nil } }
            )
        ) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(activationError ?? "")
        }
    }

    private func requiresSave(profileID: String) -> Bool {
        guard let editor = workspace.existingEditor(profileID: profileID)
        else { return false }
        if case .dirty = editor.persistenceState {
            return true
        }
        return false
    }
}

private struct ProductProfileManagerView: View {
    @EnvironmentObject private var library: ProfileLibraryModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var workspace: ProfileV3Workspace

    @State private var importing = false
    @State private var renameTarget: ProfileSummary?
    @State private var deleteTarget: ProfileSummary?

    var body: some View {
        let profiles = library.profiles.filter {
            library.isProfileV3(profileID: $0.id)
        }
        let selectedID = workspace.resolvedProfileID(library: library)

        List {
            ForEach(profiles) { profile in
                Button {
                    workspace.select(profileID: profile.id)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                                .foregroundStyle(.primary)
                            if library.activeProfileID == profile.id {
                                Text("使用中")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if selectedID == profile.id {
                            Image(systemName: "checkmark")
                                .accessibilityLabel("編集中")
                        }
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteTarget = profile
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                    Button {
                        if let id = library.clone(profileID: profile.id) {
                            workspace.select(profileID: id)
                        }
                    } label: {
                        Label("複製", systemImage: "plus.square.on.square")
                    }
                }
                .contextMenu {
                    Button {
                        renameTarget = profile
                    } label: {
                        Label("名前を変更", systemImage: "pencil")
                    }
                    if let url = library.exportURL(profileID: profile.id) {
                        ShareLink(item: url) {
                            Label("書き出し", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .navigationTitle("キーボード")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    importing = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .accessibilityLabel("読み込む")

                Button {
                    if let id = library.createEmptyV3() {
                        workspace.select(profileID: id)
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新しいキーボード")
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
            }
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if let id = library.importV3Profile(from: url) {
                    workspace.select(profileID: id)
                }
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled {
                    library.errorMessage = error.localizedDescription
                }
            }
        }
        .sheet(item: $renameTarget) { profile in
            ProductTextEditSheet(
                title: "名前を変更",
                label: "名前",
                initialValue: profile.name
            ) { name in
                library.rename(profileID: profile.id, name: name)
                workspace.existingEditor(profileID: profile.id)?.reload()
            }
        }
        .alert(
            "キーボードを削除",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )
        ) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                guard let profile = deleteTarget else { return }
                let wasSelected = selectedID == profile.id
                workspace.removeSession(profileID: profile.id)
                library.delete(profileID: profile.id)
                if wasSelected {
                    workspace.selectedProfileID = nil
                }
                deleteTarget = nil
            }
        } message: {
            if let profile = deleteTarget {
                let active = library.activeProfileID == profile.id
                Text(
                    active
                        ? "使用中の「\(profile.name)」を削除します。保存されていない編集も破棄されます。"
                        : "「\(profile.name)」を削除します。保存されていない編集も破棄されます。"
                )
            }
        }
        .alert(
            "エラー",
            isPresented: Binding(
                get: { library.errorMessage != nil && deleteTarget == nil },
                set: { if !$0 { library.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.errorMessage ?? "")
        }
    }
}

struct ProductSaveControls: View {
    @ObservedObject var editor: ProfileV3EditorModel

    private var status: (String, String) {
        switch editor.persistenceState {
        case .dirty:
            ("未保存", "circle.fill")
        case .savedLocally:
            ("保存済", "checkmark")
        case .savedLocallyAndDelivered:
            ("反映済", "checkmark.circle.fill")
        case .savedLocallyDeliveryFailed:
            ("反映失敗", "exclamationmark.triangle.fill")
        }
    }

    private var canSave: Bool {
        guard editor.validation.valid else { return false }
        return switch editor.persistenceState {
        case .dirty, .savedLocallyDeliveryFailed:
            true
        case .savedLocally, .savedLocallyAndDelivered:
            false
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Label(status.0, systemImage: status.1)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("保存状態: " + status.0)

            Button("保存") {
                editor.save()
            }
            .disabled(!canSave)
        }
    }
}

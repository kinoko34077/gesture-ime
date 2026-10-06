import SwiftUI
import UniformTypeIdentifiers
import GestureIMEProfileAuthoring

struct ProfileLibraryView: View {
    @EnvironmentObject private var library: ProfileLibraryModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var workspace: ProfileV3Workspace

    @State private var importing = false
    @State private var deleteTarget: ProfileSummary?
    @State private var renameTarget: ProfileSummary?

    var body: some View {
        let profiles = library.profiles.filter {
            library.isProfileV3(profileID: $0.id)
        }
        let scopedID = workspace.resolvedProfileID(library: library)

        List {
            if profiles.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("キーボードがありません。")
                            .font(.headline)
                        Button("新しいキーボードを作る") {
                            createAndOpen()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Section {
                    ForEach(profiles) { profile in
                        Button {
                            workspace.select(profileID: profile.id)
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
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

                                if scopedID == profile.id {
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
                                duplicate(profile)
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

                            Button {
                                duplicate(profile)
                            } label: {
                                Label("複製", systemImage: "plus.square.on.square")
                            }

                            if let url = library.exportURL(profileID: profile.id) {
                                ShareLink(item: url) {
                                    Label("書き出し", systemImage: "square.and.arrow.up")
                                }
                            }
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
                    createAndOpen()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新しいキーボード")
            }

            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") {
                    dismiss()
                }
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
                    dismiss()
                }

            case .failure(let error):
                library.errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $renameTarget) { profile in
            ProfileRenameSheet(profile: profile) { name in
                rename(profile, to: name)
            }
        }
        .alert(
            "キーボードを削除",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )
        ) {
            Button("キャンセル", role: .cancel) {
                deleteTarget = nil
            }
            Button("削除", role: .destructive) {
                if let profile = deleteTarget {
                    delete(profile)
                }
                deleteTarget = nil
            }
        } message: {
            if let profile = deleteTarget {
                Text(deleteMessage(for: profile))
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

    private func createAndOpen() {
        guard let id = library.createEmptyV3() else { return }
        workspace.select(profileID: id)
        dismiss()
    }

    private func duplicate(_ profile: ProfileSummary) {
        if let editor = workspace.existingEditor(profileID: profile.id) {
            _ = editor.duplicateProfile()
        } else {
            _ = library.clone(profileID: profile.id)
        }
    }

    private func rename(_ profile: ProfileSummary, to name: String) {
        if let editor = workspace.existingEditor(profileID: profile.id) {
            editor.renameProfile(name)
            editor.save()
        } else {
            library.rename(profileID: profile.id, name: name)
        }
    }

    private func delete(_ profile: ProfileSummary) {
        library.delete(profileID: profile.id)
        workspace.removeSession(profileID: profile.id)
    }

    private func deleteMessage(for profile: ProfileSummary) -> String {
        var lines = [
            "「\(profile.name)」を削除します。元に戻せません。"
        ]

        if workspace.resolvedProfileID(library: library) == profile.id {
            lines.append("現在編集中のキーボードです。")
        }

        if workspace.existingEditor(profileID: profile.id)?.persistenceState == .dirty {
            lines.append("未保存の編集も失われます。")
        }

        if library.activeProfileID == profile.id {
            lines.append(
                "アプリ内の「使用中」指定は解除されます。共有済みのキーボード内容は直ちに消去されない場合があります。"
            )
        }

        return lines.joined(separator: "\n")
    }
}

private struct ProfileRenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let profile: ProfileSummary
    let onSave: (String) -> Void

    @State private var name: String

    init(
        profile: ProfileSummary,
        onSave: @escaping (String) -> Void
    ) {
        self.profile = profile
        self.onSave = onSave
        _name = State(initialValue: profile.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("名前", text: $name)
            }
            .navigationTitle("名前を変更")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(name)
                        dismiss()
                    }
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
    }
}

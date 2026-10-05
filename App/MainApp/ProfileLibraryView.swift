import SwiftUI
import UniformTypeIdentifiers

struct ProfileLibraryView: View {
    @EnvironmentObject private var library: ProfileLibraryModel
    @State private var importing = false

    var body: some View {
        Group {
            List {
                Section {
                    ForEach(library.profiles) { profile in
                        NavigationLink {
                            if library.isProfileV3(profileID: profile.id) {
                                ProfileV3OverviewEditorView(
                                    library: library,
                                    profileID: profile.id
                                )
                            } else {
                                ProfileEditorView(
                                    library: library,
                                    profileID: profile.id
                                )
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(profile.name)
                                }
                                Spacer()
                                if library.activeProfileID == profile.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                library.delete(profileID: profile.id)
                            } label: {
                                Label("削除", systemImage: "trash")
                            }

                            Button {
                                library.clone(profileID: profile.id)
                            } label: {
                                Label("複製", systemImage: "plus.square.on.square")
                            }
                            .tint(.blue)
                        }
                    }
                } header: {
                    Text("このアプリ内のキーボード")
                } footer: {
                    Text("使用中のキーボードの選択はこのアプリ内でのみ有効です。キーボード本体への反映は別途対応予定です。")
                }
            }
            .navigationTitle("キーボード")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        importing = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }

                    Menu {
                        Button {
                            library.createEmptyV3()
                        } label: {
                            Label("新しいキーボード", systemImage: "square.grid.3x3")
                        }

                        Button {
                            library.createFromBuiltIn()
                        } label: {
                            Label("組み込みキーボードを複製（開発用）", systemImage: "keyboard")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    library.importProfile(from: url)
                } else if case .failure(let error) = result {
                    library.errorMessage = error.localizedDescription
                }
            }
            .alert(
                "エラー",
                isPresented: Binding(
                    get: { library.errorMessage != nil },
                    set: { if !$0 { library.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(library.errorMessage ?? "")
            }
        }
    }
}

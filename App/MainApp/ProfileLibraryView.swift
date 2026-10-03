import SwiftUI
import UniformTypeIdentifiers

struct ProfileLibraryView: View {
    @EnvironmentObject private var library: ProfileLibraryModel
    @State private var importing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(library.profiles) { profile in
                        NavigationLink {
                            ProfileEditorView(library: library, profileID: profile.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(profile.name)
                                    Text(profile.id)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                library.clone(profileID: profile.id)
                            } label: {
                                Label("Clone", systemImage: "plus.square.on.square")
                            }
                            .tint(.blue)
                        }
                    }
                } header: {
                    Text("App-local Profiles")
                } footer: {
                    Text("Active selection is app-local in Phase 5A; Keyboard Extension delivery is a separate capability gate.")
                }
            }
            .navigationTitle("Profiles")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        importing = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }

                    Button {
                        library.createFromBuiltIn()
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
                "Profile error",
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

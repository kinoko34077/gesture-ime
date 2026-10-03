import SwiftUI
import GestureIMEProfileAuthoring

struct ProfileEditorView: View {
    @EnvironmentObject private var libraryEnvironment: ProfileLibraryModel
    @StateObject private var editor: ProfileEditorModel

    private let library: ProfileLibraryModel

    init(library: ProfileLibraryModel, profileID: String) {
        self.library = library
        _editor = StateObject(
            wrappedValue: ProfileEditorModel(library: library, profileID: profileID)
        )
    }

    var body: some View {
        Form {
            Section("Profile") {
                TextField(
                    "Name",
                    text: Binding(
                        get: { editor.name },
                        set: { editor.rename($0) }
                    )
                )

                HStack {
                    Text("Validation")
                    Spacer()
                    if editor.validation.valid {
                        Label("Valid", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    } else {
                        Text(editor.validation.errorCode ?? "Invalid")
                            .foregroundStyle(.red)
                    }
                }

                if !editor.validation.valid, let detail = editor.validation.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button("Use as app-local active Profile") {
                    library.setActive(profileID: editor.profileID)
                }

                if let url = library.exportURL(profileID: editor.profileID) {
                    ShareLink(item: url) {
                        Label("Export JSON", systemImage: "square.and.arrow.up")
                    }
                }
            }

            if let policy = editor.policy() {
                GesturePolicySection(policy: policy, onChange: editor.updatePolicy)
            }

            Section("Layer") {
                Picker(
                    "Layer",
                    selection: Binding(
                        get: { editor.selectedLayerID },
                        set: { editor.selectLayer($0) }
                    )
                ) {
                    ForEach(editor.layerIDs, id: \.self) { layer in
                        Text(layer).tag(layer)
                    }
                }
            }

            Section("Keys") {
                ForEach(editor.keys) { key in
                    NavigationLink {
                        KeyEditorView(editor: editor, key: key)
                    } label: {
                        HStack {
                            Text(key.title)
                                .frame(width: 48, alignment: .leading)
                            VStack(alignment: .leading) {
                                Text(key.id)
                                Text("r\(key.row) c\(key.column) · \(format(key.width))×\(format(key.height))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(editor.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    editor.save()
                }
                .disabled(!editor.validation.valid)
            }
        }
        .alert(
            "Profile error",
            isPresented: Binding(
                get: { editor.errorMessage != nil },
                set: { if !$0 { editor.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editor.errorMessage ?? "")
        }
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

private struct GesturePolicySection: View {
    @State private var policy: ProfileGesturePolicy
    let onChange: (ProfileGesturePolicy) -> Void

    init(policy: ProfileGesturePolicy, onChange: @escaping (ProfileGesturePolicy) -> Void) {
        _policy = State(initialValue: policy)
        self.onChange = onChange
    }

    var body: some View {
        Section("Gesture Policy") {
            slider("Dead zone", value: $policy.deadZone, range: 0...2)
            slider("Stage 1", value: $policy.stage1CommitDistance, range: 0.01...4)
            slider("Stage 2", value: $policy.stage2CommitDistance, range: 0.01...4)
            slider("Hysteresis", value: $policy.angularHysteresisDegrees, range: 0...44)
        }
        .onChange(of: policy) { _, value in
            onChange(value)
        }
    }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
        }
    }
}

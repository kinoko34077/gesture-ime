import SwiftUI
import Foundation
import GestureIMEProfileAuthoring

struct ProfileEditorView: View {
    @StateObject private var editor: ProfileEditorModel
    @State private var creatingBoard = false

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

                LabeledContent(
                    "Input model",
                    value: editor.isBoardGraphV2 ? "Board Graph v2" : "GesturePath v1"
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

                if !editor.isBoardGraphV2 {
                    Button("Migrate to Board Graph v2") {
                        editor.migrateToV2()
                    }
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
                GesturePolicySection(
                    policy: policy,
                    boardGraph: editor.isBoardGraphV2,
                    onChange: editor.updatePolicy
                )
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

            if editor.isBoardGraphV2 {
                Section("Boards") {
                    ForEach(editor.boards) { board in
                        NavigationLink {
                            BoardEditorView(editor: editor, boardID: board.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(board.id)
                                Text("\(board.entryCount) entries" + (board.holdTrigger == nil ? "" : " · Hold"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button {
                        creatingBoard = true
                    } label: {
                        Label("Create Board", systemImage: "plus")
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
        .sheet(isPresented: $creatingBoard) {
            CreateBoardSheet(editor: editor)
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
    let boardGraph: Bool
    let onChange: (ProfileGesturePolicy) -> Void

    init(
        policy: ProfileGesturePolicy,
        boardGraph: Bool,
        onChange: @escaping (ProfileGesturePolicy) -> Void
    ) {
        _policy = State(initialValue: policy)
        self.boardGraph = boardGraph
        self.onChange = onChange
    }

    var body: some View {
        Section("Gesture Policy") {
            slider("Dead zone", value: $policy.deadZone, range: 0...2)
            slider(
                boardGraph ? "Initial cell" : "Stage 1",
                value: $policy.stage1CommitDistance,
                range: 0.01...4
            )
            slider(
                boardGraph ? "Subsequent cell" : "Stage 2",
                value: $policy.stage2CommitDistance,
                range: 0.01...4
            )
            slider("Hysteresis", value: $policy.angularHysteresisDegrees, range: 0...44)

            if boardGraph {
                Text("Board Graph v2 has no two-stage authoring ceiling. Runtime transition depth is resource-bounded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

private struct CreateBoardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var editor: ProfileEditorModel
    @State private var boardID = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Board ID", text: $boardID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .navigationTitle("Create Board")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        editor.createBoard(id: boardID)
                        dismiss()
                    }
                    .disabled(boardID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

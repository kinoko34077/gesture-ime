import SwiftUI
import GestureIMEProfileAuthoring

struct BoardEditorView: View {
    @ObservedObject var editor: ProfileEditorModel
    let boardID: String

    @State private var editingEntry: ProfileBoardEntrySummary?
    @State private var addingEntry = false

    @State private var holdEnabled: Bool
    @State private var holdDelayMs: Int
    @State private var holdTargetBoardID: String
    @State private var holdLifetime: ProfileBoardTransitionLifetime

    init(editor: ProfileEditorModel, boardID: String) {
        self.editor = editor
        self.boardID = boardID

        let hold = editor.boardHoldTrigger(boardID: boardID)
        _holdEnabled = State(initialValue: hold != nil)
        _holdDelayMs = State(initialValue: hold?.delayMs ?? 450)
        _holdTargetBoardID = State(
            initialValue: hold?.transition.targetBoardID
                ?? editor.boards.first?.id
                ?? boardID
        )
        _holdLifetime = State(initialValue: hold?.transition.lifetime ?? .transient)
    }

    private var entries: [ProfileBoardEntrySummary] {
        editor.boardEntries(boardID: boardID)
    }

    var body: some View {
        Form {
            Section("Entries") {
                ForEach(entries) { entry in
                    Button {
                        editingEntry = entry
                    } label: {
                        HStack {
                            Text(entry.coordinate.displayName)
                                .monospaced()
                                .frame(width: 80, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.presentationText ?? endpointLabel(entry))
                                    .foregroundStyle(.primary)
                                if let transition = entry.transition {
                                    Text("→ \(transition.targetBoardID) [\(transition.lifetime.rawValue)]")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            editor.removeBoardEntry(
                                boardID: boardID,
                                coordinate: entry.coordinate
                            )
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                Button {
                    addingEntry = true
                } label: {
                    Label("Add relative-coordinate entry", systemImage: "plus")
                }
            }

            Section("Hold → Board") {
                Toggle("Enable Hold transition", isOn: $holdEnabled)

                if holdEnabled {
                    Stepper(
                        "Delay: \(holdDelayMs) ms",
                        value: $holdDelayMs,
                        in: 50...5000,
                        step: 25
                    )
                    Picker("Target", selection: $holdTargetBoardID) {
                        ForEach(editor.boards.map(\.id), id: \.self) { id in
                            Text(id).tag(id)
                        }
                    }
                    Picker("Lifetime", selection: $holdLifetime) {
                        ForEach(ProfileBoardTransitionLifetime.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                }

                Button("Apply Hold transition") {
                    editor.setBoardHoldTransition(
                        boardID: boardID,
                        delayMs: holdDelayMs,
                        transition: holdEnabled
                            ? ProfileBoardTransitionDraft(
                                targetBoardID: holdTargetBoardID,
                                lifetime: holdLifetime
                            )
                            : nil
                    )
                }
                .disabled(holdEnabled && holdTargetBoardID.isEmpty)
            }
        }
        .navigationTitle(boardID)
        .sheet(item: $editingEntry) { entry in
            BoardEntryEditorView(
                editor: editor,
                boardID: boardID,
                existing: entry
            )
        }
        .sheet(isPresented: $addingEntry) {
            BoardEntryEditorView(
                editor: editor,
                boardID: boardID,
                existing: nil
            )
        }
    }

    private func endpointLabel(_ entry: ProfileBoardEntrySummary) -> String {
        if let action = entry.actions.first {
            return action.actionID
        }
        if entry.transition != nil {
            return "Board transition"
        }
        return "Presentation only"
    }
}

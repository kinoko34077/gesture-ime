import SwiftUI
import GestureIMEProfileAuthoring

struct BoardEntryEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var editor: ProfileEditorModel
    let boardID: String
    let existing: ProfileBoardEntrySummary?

    @State private var x: Int
    @State private var y: Int
    @State private var presentation: String

    @State private var actionEnabled: Bool
    @State private var action: CommonActionOption
    @State private var argumentText: String

    @State private var transitionEnabled: Bool
    @State private var targetBoardID: String
    @State private var lifetime: ProfileBoardTransitionLifetime

    init(
        editor: ProfileEditorModel,
        boardID: String,
        existing: ProfileBoardEntrySummary?
    ) {
        self.editor = editor
        self.boardID = boardID
        self.existing = existing

        _x = State(initialValue: existing?.coordinate.x ?? 1)
        _y = State(initialValue: existing?.coordinate.y ?? 0)
        _presentation = State(initialValue: existing?.presentationText ?? "")

        let currentAction = existing?.actions.first
        let actionOption = CommonActionOption.from(currentAction?.actionID ?? "text.insert")
        _actionEnabled = State(initialValue: currentAction != nil)
        _action = State(initialValue: actionOption)

        let argument: String
        if let key = actionOption.argumentKey,
           let value = currentAction?.arguments[key] {
            if let string = value.stringValue {
                argument = string
            } else if let integer = value.intValue {
                argument = String(integer)
            } else {
                argument = ""
            }
        } else {
            argument = existing?.presentationText ?? ""
        }
        _argumentText = State(initialValue: argument)

        let transition = existing?.transition
        _transitionEnabled = State(initialValue: transition != nil)
        _targetBoardID = State(
            initialValue: transition?.targetBoardID
                ?? editor.boards.first?.id
                ?? boardID
        )
        _lifetime = State(initialValue: transition?.lifetime ?? .transient)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Relative coordinate") {
                    Stepper("x: \(x)", value: $x, in: -32...32)
                    Stepper("y: \(y)", value: $y, in: -32...32)
                    Text("(0, 0) is the Board-local origin.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Presentation") {
                    TextField("Displayed hint", text: $presentation)
                }

                Section("Release Action") {
                    Toggle("Dispatch Action on release", isOn: $actionEnabled)
                    if actionEnabled {
                        Picker("Action", selection: $action) {
                            ForEach(CommonActionOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }

                        if let key = action.argumentKey {
                            TextField(key, text: $argumentText)
                                .keyboardType(
                                    action.integerArgument
                                        ? .numbersAndPunctuation
                                        : .default
                                )
                        }
                    }
                }

                Section("Board Transition") {
                    Toggle("Transition to another Board", isOn: $transitionEnabled)
                    if transitionEnabled {
                        Picker("Target", selection: $targetBoardID) {
                            ForEach(editor.boards.map(\.id), id: \.self) { id in
                                Text(id).tag(id)
                            }
                        }
                        Picker("Lifetime", selection: $lifetime) {
                            ForEach(ProfileBoardTransitionLifetime.allCases) { value in
                                Text(value.rawValue).tag(value)
                            }
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add Board Entry" : "Edit Board Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        editor.upsertBoardEntry(
                            boardID: boardID,
                            originalCoordinate: existing?.coordinate,
                            coordinate: ProfileBoardCoordinate(x: x, y: y),
                            presentationText: presentation.isEmpty ? nil : presentation,
                            action: actionEnabled
                                ? action.makeDraft(argumentText: argumentText)
                                : nil,
                            transition: transitionEnabled
                                ? ProfileBoardTransitionDraft(
                                    targetBoardID: targetBoardID,
                                    lifetime: lifetime
                                )
                                : nil
                        )
                        dismiss()
                    }
                    .disabled(
                        transitionEnabled && targetBoardID.isEmpty
                    )
                }
            }
        }
    }
}

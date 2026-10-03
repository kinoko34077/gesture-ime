import SwiftUI
import GestureIMEProfileAuthoring

struct BindingEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var editor: ProfileEditorModel
    let keyID: String
    let existing: ProfileBindingSummary?

    @State private var stageCount: Int
    @State private var stage1: ProfileDirection
    @State private var stage2: ProfileDirection
    @State private var presentation: String
    @State private var action: CommonActionOption
    @State private var argumentText: String

    init(
        editor: ProfileEditorModel,
        keyID: String,
        existing: ProfileBindingSummary?
    ) {
        self.editor = editor
        self.keyID = keyID
        self.existing = existing

        let path = existing?.path ?? [.ne, .ne]
        _stageCount = State(initialValue: existing == nil ? 2 : path.count)
        _stage1 = State(initialValue: path.first ?? .n)
        _stage2 = State(initialValue: path.dropFirst().first ?? .n)
        let initialPresentation = existing?.presentationText ?? ""
        _presentation = State(initialValue: initialPresentation)

        let current = existing?.actions.first
        let option = CommonActionOption.from(current?.actionID ?? "text.insert")
        _action = State(initialValue: option)

        let argument: String
        if let key = option.argumentKey, let value = current?.arguments[key] {
            if let string = value.stringValue {
                argument = string
            } else if let integer = value.intValue {
                argument = String(integer)
            } else {
                argument = ""
            }
        } else {
            argument = option == .textInsert ? initialPresentation : ""
        }
        _argumentText = State(initialValue: argument)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Gesture Path") {
                    Picker("Stages", selection: $stageCount) {
                        Text("Tap").tag(0)
                        Text("1 stage").tag(1)
                        Text("2 stages").tag(2)
                    }
                    .pickerStyle(.segmented)

                    if stageCount >= 1 {
                        directionPicker("Stage 1", selection: $stage1)
                    }
                    if stageCount == 2 {
                        directionPicker("Stage 2", selection: $stage2)
                    }

                    Text(pathDescription)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Section("Presentation") {
                    TextField("Displayed hint", text: $presentation)
                }

                Section("Action") {
                    Picker("Action", selection: $action) {
                        ForEach(CommonActionOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }

                    if let key = action.argumentKey {
                        TextField(
                            key,
                            text: $argumentText
                        )
                        .keyboardType(action.integerArgument ? .numbersAndPunctuation : .default)
                    }
                }

                if existing != nil && existing?.path != path {
                    Section {
                        Text("Changing the path removes the old path and writes the new one. If the new path already exists, it is replaced deterministically.")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add Binding" : "Edit Binding")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        editor.upsertBinding(
                            keyID: keyID,
                            originalPath: existing?.path,
                            path: path,
                            presentationText: presentation.isEmpty ? nil : presentation,
                            action: action.makeDraft(argumentText: argumentText)
                        )
                        dismiss()
                    }
                }
            }
        }
    }

    private var path: [ProfileDirection] {
        switch stageCount {
        case 0: []
        case 1: [stage1]
        default: [stage1, stage2]
        }
    }

    private var pathDescription: String {
        path.isEmpty ? "[]" : "[" + path.map(\.displayName).joined(separator: ",") + "]"
    }

    private func directionPicker(
        _ title: String,
        selection: Binding<ProfileDirection>
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(ProfileDirection.allCases) { direction in
                Text(direction.displayName).tag(direction)
            }
        }
    }
}

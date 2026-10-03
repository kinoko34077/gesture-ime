import SwiftUI
import Foundation
import GestureIMEProfileAuthoring

struct KeyEditorView: View {
    @ObservedObject var editor: ProfileEditorModel
    let key: ProfileKeySummary

    @State private var title: String
    @State private var row: Int
    @State private var column: Int
    @State private var width: Double
    @State private var height: Double
    @State private var editingBinding: ProfileBindingSummary?
    @State private var addingBinding = false

    init(editor: ProfileEditorModel, key: ProfileKeySummary) {
        self.editor = editor
        self.key = key
        _title = State(initialValue: key.title)
        _row = State(initialValue: key.row)
        _column = State(initialValue: key.column)
        _width = State(initialValue: key.width)
        _height = State(initialValue: key.height)
    }

    private var bindings: [ProfileBindingSummary] {
        editor.bindings(keyID: key.id)
    }

    var body: some View {
        Form {
            Section("Key") {
                LabeledContent("ID", value: key.id)
                TextField("Label", text: $title)
                Stepper("Row: \(row)", value: $row, in: 0...255)
                Stepper("Column: \(column)", value: $column, in: 0...255)
                Stepper("Width: \(format(width))", value: $width, in: 0.5...32, step: 0.5)
                Stepper("Height: \(format(height))", value: $height, in: 0.5...32, step: 0.5)

                Button("Apply key/layout changes") {
                    editor.updateKey(
                        keyID: key.id,
                        title: title,
                        row: row,
                        column: column,
                        width: width,
                        height: height
                    )
                }
            }

            Section("Bindings") {
                ForEach(bindings) { binding in
                    Button {
                        editingBinding = binding
                    } label: {
                        HStack {
                            Text(pathLabel(binding.path))
                                .monospaced()
                                .frame(width: 80, alignment: .leading)
                            Text(binding.presentationText ?? binding.actions.first?.actionID ?? "No action")
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            editor.removeBinding(keyID: key.id, path: binding.path)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                Button {
                    addingBinding = true
                } label: {
                    Label("Add binding", systemImage: "plus")
                }
            }
        }
        .navigationTitle(key.title)
        .sheet(item: $editingBinding) { binding in
            BindingEditorView(editor: editor, keyID: key.id, existing: binding)
        }
        .sheet(isPresented: $addingBinding) {
            BindingEditorView(editor: editor, keyID: key.id, existing: nil)
        }
    }

    private func pathLabel(_ path: [ProfileDirection]) -> String {
        path.isEmpty ? "Tap" : "[" + path.map(\.displayName).joined(separator: ",") + "]"
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

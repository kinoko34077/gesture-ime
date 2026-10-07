import SwiftUI

struct ProductSemanticIDSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let initialID: String
    let confirmTitle: String
    let onConfirm: (String) -> Bool

    @State private var semanticID = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("識別子", text: $semanticID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                LabeledContent("使用可能") {
                    Text("英数字 . _ -")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle) {
                        let id = semanticID.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        if onConfirm(id) {
                            dismiss()
                        }
                    }
                    .disabled(
                        semanticID.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
            .onAppear { semanticID = initialID }
        }
    }
}

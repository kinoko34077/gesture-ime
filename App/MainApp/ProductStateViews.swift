import SwiftUI
import GestureIMEProfileAuthoring

struct ProductStateList: View {
    @ObservedObject var editor: ProfileV3EditorModel
    @State private var creatingType: ProfileV3StateType?
    @State private var duplicating: ProfileV3StateSummary?
    @State private var deleting: ProfileV3StateSummary?

    var body: some View {
        List {
            if editor.states.isEmpty {
                ContentUnavailableView(
                    "状態はありません",
                    systemImage: "switch.2"
                )
            } else {
                ForEach(editor.states) { state in
                    NavigationLink {
                        ProductStateDetail(
                            editor: editor,
                            stateID: state.id
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.id)
                            Text(typeLabel(state.type))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleting = state
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                        Button {
                            duplicating = state
                        } label: {
                            Label("複製", systemImage: "plus.square.on.square")
                        }
                    }
                }
            }
        }
        .navigationTitle("状態")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("オン / オフ") {
                        creatingType = .boolean
                    }
                    Button("選択肢") {
                        creatingType = .enumeration
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("状態を追加")
            }
        }
        .sheet(item: $creatingType) { type in
            ProductNewStateSheet(editor: editor, type: type)
        }
        .sheet(item: $duplicating) { state in
            ProductSemanticIDSheet(
                title: "状態を複製",
                initialID: state.id + "-copy",
                confirmTitle: "複製"
            ) { id in
                editor.duplicateState(
                    id: state.id,
                    newID: id
                )
            }
        }
        .confirmationDialog(
            "状態を削除しますか？",
            isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                if let deleting {
                    _ = editor.deleteState(id: deleting.id)
                }
                deleting = nil
            }
            Button("キャンセル", role: .cancel) {}
        }
        .safeAreaInset(edge: .bottom) {
            if let message = editor.errorMessage {
                ProductInlineError(message: message) {
                    editor.errorMessage = nil
                }
            }
        }
    }

    private func typeLabel(_ type: ProfileV3StateType) -> String {
        switch type {
        case .boolean: "オン / オフ"
        case .enumeration: "選択肢"
        }
    }
}

private struct ProductNewStateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var editor: ProfileV3EditorModel
    let type: ProfileV3StateType

    @State private var semanticID = ""
    @State private var boolDefault = false
    @State private var enumInitial = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("識別子", text: $semanticID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("作成後は識別子を変更しません。")
                }

                switch type {
                case .boolean:
                    Toggle("初期値", isOn: $boolDefault)

                case .enumeration:
                    TextField("最初の選択肢", text: $enumInitial)
                }
            }
            .navigationTitle("状態を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        let id = semanticID.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        let created: Bool
                        switch type {
                        case .boolean:
                            created = editor.createBooleanState(
                                id: id,
                                defaultValue: boolDefault
                            )
                        case .enumeration:
                            created = editor.createEnumState(
                                id: id,
                                initialValue: enumInitial
                            )
                        }
                        if created { dismiss() }
                    }
                    .disabled(!canCreate)
                }
            }
        }
    }

    private var canCreate: Bool {
        let id = semanticID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !id.isEmpty else { return false }
        switch type {
        case .boolean:
            return true
        case .enumeration:
            return !enumInitial.isEmpty
        }
    }
}

private struct ProductStateDetail: View {
    @ObservedObject var editor: ProfileV3EditorModel
    let stateID: String

    @State private var values: [String] = []
    @State private var defaultValue = ""
    @State private var loaded = false

    private var state: ProfileV3StateSummary? {
        editor.states.first { $0.id == stateID }
    }

    var body: some View {
        List {
            if let state {
                LabeledContent("識別子") {
                    Text(state.id)
                        .textSelection(.enabled)
                }

                switch state.type {
                case .boolean:
                    Toggle(
                        "初期値",
                        isOn: Binding(
                            get: {
                                if case .bool(let value) = state.defaultValue {
                                    return value
                                }
                                return false
                            },
                            set: {
                                _ = editor.updateBooleanState(
                                    id: state.id,
                                    defaultValue: $0
                                )
                            }
                        )
                    )

                case .enumeration:
                    Section("選択肢") {
                        ForEach(values.indices, id: \.self) { index in
                            TextField(
                                "値",
                                text: Binding(
                                    get: { values[index] },
                                    set: { values[index] = $0 }
                                )
                            )
                        }
                        .onMove { source, destination in
                            values.move(
                                fromOffsets: source,
                                toOffset: destination
                            )
                        }
                        .onDelete { offsets in
                            guard values.count - offsets.count >= 1 else {
                                return
                            }
                            values.remove(atOffsets: offsets)
                            if !values.contains(defaultValue) {
                                defaultValue = values.first ?? ""
                            }
                        }

                        Button {
                            values.append("")
                        } label: {
                            Label("選択肢を追加", systemImage: "plus")
                        }
                    }

                    Picker("初期値", selection: $defaultValue) {
                        ForEach(values, id: \.self) { value in
                            Text(value.isEmpty ? "（空）" : value)
                                .tag(value)
                        }
                    }

                    Button("変更を適用") {
                        _ = editor.updateEnumState(
                            id: state.id,
                            values: values,
                            defaultValue: defaultValue
                        )
                    }
                    .disabled(
                        ProfileV3StateAuthoringPolicy.enumValidationError(
                            values: values,
                            defaultValue: defaultValue
                        ) != nil
                    )
                }
            }
        }
        .navigationTitle(stateID)
        .toolbar {
            if state?.type == .enumeration {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
        .onAppear {
            loadIfNeeded()
        }
        .safeAreaInset(edge: .bottom) {
            if let message = editor.errorMessage {
                ProductInlineError(message: message) {
                    editor.errorMessage = nil
                }
            }
        }
    }

    private func loadIfNeeded() {
        guard !loaded, let state else { return }
        if case .enumeration = state.type {
            values = state.values
            defaultValue = state.defaultValue.stringValue
                ?? state.values.first
                ?? ""
        }
        loaded = true
    }
}

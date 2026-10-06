import SwiftUI
import GestureIMEProfileAuthoring

struct ProfileV3StateEditorView: View {
    @ObservedObject var editor: ProfileV3EditorModel
    @State private var showingCreate = false
    @State private var localError: String?

    var body: some View {
        List {
            if editor.states.isEmpty {
                ContentUnavailableView {
                    Label("状態はありません", systemImage: "switch.2")
                } description: {
                    Text("オン／オフ、または複数の選択肢を持つ状態を追加できます。")
                } actions: {
                    Button("状態を追加") {
                        showingCreate = true
                    }
                }
            } else {
                ForEach(editor.states) { state in
                    NavigationLink {
                        ProfileV3StateDetailView(
                            editor: editor,
                            state: state
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.id)
                            Text(summary(state))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44, alignment: .leading)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            if !editor.deleteState(id: state.id) {
                                captureEditorError(
                                    fallback: "状態を削除できません。"
                                )
                            }
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button {
                            if editor.duplicateState(id: state.id) == nil {
                                captureEditorError(
                                    fallback: "状態を複製できません。"
                                )
                            }
                        } label: {
                            Label(
                                "複製",
                                systemImage: "plus.square.on.square"
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle(ProfileV3AppCategory.states.title)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    editor.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!editor.canUndo)
                .accessibilityLabel("取り消す")

                Button {
                    editor.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!editor.canRedo)
                .accessibilityLabel("やり直す")

                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("状態を追加")
            }
        }
        .sheet(isPresented: $showingCreate) {
            ProfileV3CreateStateSheet(editor: editor)
        }
        .safeAreaInset(edge: .bottom) {
            if let localError {
                ProfileV3InlineAuthoringError(
                    message: localError,
                    correctionHint:
                        "参照中の条件または状態の内容を確認して、もう一度操作してください。"
                )
            }
        }
    }

    private func summary(_ state: ProfileV3StateSummary) -> String {
        switch state.type {
        case .boolean:
            return "オン／オフ・初期値 "
                + (stateBooleanDefault(state) ? "オン" : "オフ")

        case .enumeration:
            return "\(state.values.count)個の値・初期値「\(stateEnumDefault(state))」"
        }
    }

    private func captureEditorError(fallback: String) {
        localError = editor.errorMessage ?? fallback
        editor.errorMessage = nil
    }
}

private enum ProfileV3CreateStateKind: String, CaseIterable, Identifiable {
    case boolean
    case enumeration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .boolean: "オン／オフ"
        case .enumeration: "選択肢"
        }
    }
}

private struct ProfileV3CreateStateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var editor: ProfileV3EditorModel

    @State private var kind: ProfileV3CreateStateKind = .boolean
    @State private var booleanDefault = false
    @State private var enumInitialValue = ""
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("種類") {
                    Picker("種類", selection: $kind) {
                        ForEach(ProfileV3CreateStateKind.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                switch kind {
                case .boolean:
                    Section("初期値") {
                        Toggle("オン", isOn: $booleanDefault)
                    }

                case .enumeration:
                    Section("最初の値") {
                        TextField(
                            "例: 通常",
                            text: $enumInitialValue
                        )
                    }
                }
            }
            .navigationTitle("状態を追加")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if let localError {
                    ProfileV3InlineAuthoringError(
                        message: localError,
                        correctionHint:
                            "入力内容は残っています。修正して、もう一度追加してください。"
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        create()
                    }
                }
            }
        }
    }

    private func create() {
        localError = nil

        switch kind {
        case .boolean:
            if editor.createBooleanState(
                defaultValue: booleanDefault
            ) != nil {
                dismiss()
            } else {
                captureEditorError()
            }

        case .enumeration:
            if let error =
                ProfileV3StateAuthoringPolicy.enumValidationError(
                    values: [enumInitialValue],
                    defaultValue: enumInitialValue
                ) {
                localError = error
                return
            }

            if editor.createEnumState(
                initialValue: enumInitialValue
            ) != nil {
                dismiss()
            } else {
                captureEditorError()
            }
        }
    }

    private func captureEditorError() {
        localError =
            editor.errorMessage
            ?? "状態を追加できません。"
        editor.errorMessage = nil
    }
}

private struct ProfileV3StateDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var editor: ProfileV3EditorModel
    let state: ProfileV3StateSummary

    @State private var booleanDefault: Bool
    @State private var enumValues: [String]
    @State private var enumDefault: String
    @State private var showingAddValue = false
    @State private var pendingDefaultDeletion: PendingDefaultDeletion?
    @State private var localError: String?

    private struct PendingDefaultDeletion: Identifiable {
        let index: Int
        let value: String

        var id: String { "\(index):\(value)" }
    }

    init(
        editor: ProfileV3EditorModel,
        state: ProfileV3StateSummary
    ) {
        _editor = ObservedObject(wrappedValue: editor)
        self.state = state
        _booleanDefault = State(initialValue: stateBooleanDefault(state))
        _enumValues = State(initialValue: state.values)
        _enumDefault = State(initialValue: stateEnumDefault(state))
    }

    var body: some View {
        Form {
            Section("状態") {
                LabeledContent("識別子") {
                    Text(state.id)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                LabeledContent("種類") {
                    Text(
                        state.type == .boolean
                            ? "オン／オフ"
                            : "選択肢"
                    )
                }
            }

            switch state.type {
            case .boolean:
                Section("初期値") {
                    Toggle("オン", isOn: $booleanDefault)
                }

            case .enumeration:
                enumEditor
            }
        }
        .navigationTitle(state.id)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let localError {
                ProfileV3InlineAuthoringError(
                    message: localError,
                    correctionHint:
                        "現在の入力は残っています。内容を修正して、もう一度保存してください。"
                )
            }
        }
        .toolbar {
            if state.type == .enumeration {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    save()
                }
            }
        }
        .sheet(isPresented: $showingAddValue) {
            ProfileV3EnumValueSheet(
                existingValues: enumValues
            ) { value in
                enumValues.append(value)
            }
        }
        .sheet(item: $pendingDefaultDeletion) { pending in
            ProfileV3DefaultReplacementSheet(
                values: enumValues,
                deletingIndex: pending.index
            ) { replacement in
                applyDeletion(
                    index: pending.index,
                    replacementDefault: replacement
                )
            }
        }
    }

    @ViewBuilder
    private var enumEditor: some View {
        Section("値") {
            ForEach(enumValues.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(enumValues[index])

                        if enumValues[index] == enumDefault {
                            Text("初期値")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Menu {
                        profileV3MoveMenuItems(
                            canMoveUp: index > 0,
                            canMoveDown:
                                index + 1 < enumValues.count,
                            onMoveUp: {
                                moveValue(index, by: -1)
                            },
                            onMoveDown: {
                                moveValue(index, by: 1)
                            }
                        )

                        Divider()

                        Button("削除", role: .destructive) {
                            requestDelete(index)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(
                        "\(enumValues[index]) の操作"
                    )
                }
                .frame(minHeight: 44)
            }
            .onMove { source, destination in
                enumValues.move(
                    fromOffsets: source,
                    toOffset: destination
                )
            }

            Button {
                showingAddValue = true
            } label: {
                Label("値を追加", systemImage: "plus")
            }
        }

        Section("初期値") {
            Picker("初期値", selection: $enumDefault) {
                ForEach(enumValues, id: \.self) { value in
                    Text(value).tag(value)
                }
            }
        }
    }

    private func moveValue(_ index: Int, by offset: Int) {
        guard let moved =
            ProfileV3StateAuthoringPolicy.movedValues(
                enumValues,
                from: index,
                by: offset
            ) else {
            return
        }
        enumValues = moved
    }

    private func requestDelete(_ index: Int) {
        localError = nil

        guard enumValues.indices.contains(index) else {
            return
        }

        if enumValues.count <= 1 {
            localError =
                "最後の値は削除できません。列挙型には1つ以上の値が必要です。"
            return
        }

        if enumValues[index] == enumDefault {
            pendingDefaultDeletion = PendingDefaultDeletion(
                index: index,
                value: enumValues[index]
            )
            return
        }

        applyDeletion(
            index: index,
            replacementDefault: nil
        )
    }

    private func applyDeletion(
        index: Int,
        replacementDefault: String?
    ) {
        guard let result =
            ProfileV3StateAuthoringPolicy.deletingEnumValue(
                at: index,
                values: enumValues,
                defaultValue: enumDefault,
                replacementDefault: replacementDefault
            ) else {
            localError =
                "初期値を置き換えてから削除してください。"
            return
        }

        enumValues = result.values
        enumDefault = result.defaultValue
        pendingDefaultDeletion = nil
    }

    private func save() {
        localError = nil

        switch state.type {
        case .boolean:
            if editor.updateBooleanState(
                id: state.id,
                defaultValue: booleanDefault
            ) {
                dismiss()
            } else {
                captureEditorError()
            }

        case .enumeration:
            if let error =
                ProfileV3StateAuthoringPolicy.enumValidationError(
                    values: enumValues,
                    defaultValue: enumDefault
                ) {
                localError = error
                return
            }

            if editor.updateEnumState(
                id: state.id,
                values: enumValues,
                defaultValue: enumDefault
            ) {
                dismiss()
            } else {
                captureEditorError()
            }
        }
    }

    private func captureEditorError() {
        localError =
            editor.errorMessage
            ?? "状態を保存できません。"
        editor.errorMessage = nil
    }
}

private struct ProfileV3EnumValueSheet: View {
    @Environment(\.dismiss) private var dismiss
    let existingValues: [String]
    let onAdd: (String) -> Void

    @State private var value = ""
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("値", text: $value)
            }
            .navigationTitle("値を追加")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if let localError {
                    ProfileV3InlineAuthoringError(
                        message: localError,
                        correctionHint:
                            "入力した値は残っています。別の値に修正してください。"
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        add()
                    }
                }
            }
        }
    }

    private func add() {
        localError = nil

        if value.isEmpty {
            localError = "空の値は登録できません。"
            return
        }

        if existingValues.contains(value) {
            localError = "同じ値はすでに登録されています。"
            return
        }

        if existingValues.count >= 32 {
            localError = "列挙型の値は32個までです。"
            return
        }

        onAdd(value)
        dismiss()
    }
}

private struct ProfileV3DefaultReplacementSheet: View {
    @Environment(\.dismiss) private var dismiss
    let values: [String]
    let deletingIndex: Int
    let onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(
                    values.indices.filter {
                        $0 != deletingIndex
                    },
                    id: \.self
                ) { index in
                    Button(values[index]) {
                        onSelect(values[index])
                        dismiss()
                    }
                }
            }
            .navigationTitle("新しい初期値")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private func stateBooleanDefault(
    _ state: ProfileV3StateSummary
) -> Bool {
    if case .bool(let value) = state.defaultValue {
        return value
    }
    return false
}

private func stateEnumDefault(
    _ state: ProfileV3StateSummary
) -> String {
    if case .string(let value) = state.defaultValue {
        return value
    }
    return state.values.first ?? ""
}

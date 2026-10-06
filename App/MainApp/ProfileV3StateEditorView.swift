import SwiftUI
import GestureIMEProfileAuthoring

struct ProfileV3StateEditorView: View {
    @ObservedObject var editor: ProfileV3EditorModel

    @State private var createKind: StateCreateKind?
    @State private var localError: String?

    var body: some View {
        List {
            if editor.states.isEmpty {
                ContentUnavailableView(
                    "状態はありません",
                    systemImage: "switch.2",
                    description: Text(
                        "オン／オフ、または複数の選択肢を持つ状態を追加できます。"
                    )
                )
            } else {
                ForEach(editor.states) { state in
                    NavigationLink {
                        ProfileV3StateDetailView(
                            editor: editor,
                            stateID: state.id
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
                    .swipeActions(
                        edge: .trailing,
                        allowsFullSwipe: false
                    ) {
                        Button(role: .destructive) {
                            delete(state)
                        } label: {
                            Label("削除", systemImage: "trash")
                        }

                        Button {
                            duplicate(state)
                        } label: {
                            Label(
                                "複製",
                                systemImage: "plus.square.on.square"
                            )
                        }
                    }
                    .contextMenu {
                        Button {
                            duplicate(state)
                        } label: {
                            Label(
                                "複製",
                                systemImage: "plus.square.on.square"
                            )
                        }

                        Button(role: .destructive) {
                            delete(state)
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("状態")
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

                Menu {
                    Button {
                        createKind = .boolean
                    } label: {
                        Label("オン／オフ", systemImage: "switch.2")
                    }

                    Button {
                        createKind = .enumeration
                    } label: {
                        Label(
                            "選択肢",
                            systemImage: "list.bullet"
                        )
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("状態を追加")
            }
        }
        .sheet(item: $createKind) { kind in
            ProfileV3StateCreateSheet(
                editor: editor,
                kind: kind
            )
        }
        .safeAreaInset(edge: .bottom) {
            if let localError {
                ProfileV3InlineAuthoringError(
                    message: localError,
                    correctionHint:
                        "参照している条件を変更するか、状態の内容を修正してからもう一度操作してください。"
                )
            }
        }
    }

    private func summary(_ state: ProfileV3StateSummary) -> String {
        switch state.type {
        case .boolean:
            return "オン／オフ・初期値: "
                + (booleanDefault(state) ? "オン" : "オフ")
        case .enumeration:
            return "選択肢 (state.values.count)個・初期値: "
                + enumDefault(state)
        }
    }

    private func duplicate(_ state: ProfileV3StateSummary) {
        guard editor.duplicateState(id: state.id) != nil else {
            captureEditorError(fallback: "状態を複製できません")
            return
        }
        localError = nil
    }

    private func delete(_ state: ProfileV3StateSummary) {
        guard editor.deleteState(id: state.id) else {
            captureEditorError(fallback: "状態を削除できません")
            return
        }
        localError = nil
    }

    private func captureEditorError(fallback: String) {
        localError = editor.errorMessage ?? fallback
        editor.errorMessage = nil
    }
}

private enum StateCreateKind: String, Identifiable {
    case boolean
    case enumeration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .boolean: "オン／オフの状態"
        case .enumeration: "選択肢の状態"
        }
    }
}

private struct ProfileV3StateCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var editor: ProfileV3EditorModel
    let kind: StateCreateKind

    @State private var booleanDefault = false
    @State private var firstValue = ""
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("種類") {
                        Text(kind.title)
                    }

                    switch kind {
                    case .boolean:
                        Toggle(
                            "初期値",
                            isOn: $booleanDefault
                        )

                    case .enumeration:
                        TextField(
                            "最初の選択肢",
                            text: $firstValue
                        )
                    }
                }

                if let localError {
                    Section {
                        ProfileV3InlineAuthoringError(
                            message: localError,
                            correctionHint:
                                "入力内容を残したまま修正して、もう一度追加してください。"
                        )
                        .listRowInsets(EdgeInsets())
                    }
                }
            }
            .navigationTitle("状態を追加")
            .navigationBarTitleDisplayMode(.inline)
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
        switch kind {
        case .boolean:
            guard editor.createBooleanState(
                defaultValue: booleanDefault
            ) != nil else {
                captureEditorError(
                    fallback: "状態を追加できません"
                )
                return
            }

        case .enumeration:
            guard !firstValue
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty else {
                localError = "最初の選択肢を入力してください。"
                return
            }

            guard editor.createEnumState(
                values: [firstValue],
                defaultValue: firstValue
            ) != nil else {
                captureEditorError(
                    fallback: "状態を追加できません"
                )
                return
            }
        }

        dismiss()
    }

    private func captureEditorError(fallback: String) {
        localError = editor.errorMessage ?? fallback
        editor.errorMessage = nil
    }
}

private struct ProfileV3StateDetailView: View {
    @ObservedObject var editor: ProfileV3EditorModel
    let stateID: String

    @State private var newValue = ""
    @State private var localError: String?
    @State private var pendingDefaultDeletion: String?

    var body: some View {
        Group {
            if let state {
                List {
                    Section("状態") {
                        LabeledContent("ID") {
                            Text(state.id)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }

                        LabeledContent("種類") {
                            Text(
                                state.type == .boolean
                                    ? "オン／オフ"
                                    : "選択肢"
                            )
                        }

                        switch state.type {
                        case .boolean:
                            Toggle(
                                "初期値",
                                isOn: Binding(
                                    get: { booleanDefault(state) },
                                    set: { value in
                                        if !editor.setBooleanState(
                                            id: state.id,
                                            defaultValue: value
                                        ) {
                                            captureEditorError(
                                                fallback:
                                                    "初期値を変更できません"
                                            )
                                        } else {
                                            localError = nil
                                        }
                                    }
                                )
                            )

                        case .enumeration:
                            Picker(
                                "初期値",
                                selection: Binding(
                                    get: {
                                        enumDefault(state)
                                    },
                                    set: { value in
                                        commitEnum(
                                            values: state.values,
                                            defaultValue: value
                                        )
                                    }
                                )
                            ) {
                                ForEach(
                                    state.values,
                                    id: \.self
                                ) { value in
                                    Text(value).tag(value)
                                }
                            }
                        }
                    }

                    if state.type == .enumeration {
                        enumValuesSection(state)
                    }
                }
                .toolbar {
                    if state.type == .enumeration {
                        ToolbarItem(
                            placement: .topBarTrailing
                        ) {
                            EditButton()
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "状態が見つかりません",
                    systemImage: "questionmark.circle"
                )
            }
        }
        .navigationTitle(stateID)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let localError {
                ProfileV3InlineAuthoringError(
                    message: localError,
                    correctionHint:
                        "入力内容を確認して、もう一度操作してください。"
                )
            }
        }
        .confirmationDialog(
            "削除後の初期値",
            isPresented: Binding(
                get: { pendingDefaultDeletion != nil },
                set: {
                    if !$0 {
                        pendingDefaultDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let state,
               let deleting = pendingDefaultDeletion {
                ForEach(
                    state.values.filter { $0 != deleting },
                    id: \.self
                ) { replacement in
                    Button(replacement) {
                        deleteDefaultValue(
                            deleting,
                            replacement: replacement,
                            state: state
                        )
                    }
                }
            }

            Button("キャンセル", role: .cancel) {
                pendingDefaultDeletion = nil
            }
        } message: {
            Text(
                "この値は現在の初期値です。削除後に使う初期値を選んでください。"
            )
        }
    }

    private var state: ProfileV3StateSummary? {
        editor.states.first { $0.id == stateID }
    }

    @ViewBuilder
    private func enumValuesSection(
        _ state: ProfileV3StateSummary
    ) -> some View {
        Section {
            ForEach(
                Array(state.values.enumerated()),
                id: \.element
            ) { index, value in
                HStack(spacing: 8) {
                    Text(value)

                    Spacer()

                    if value == enumDefault(state) {
                        Image(systemName: "checkmark")
                            .accessibilityLabel("初期値")
                    }

                    Menu {
                        profileV3MoveMenuItems(
                            canMoveUp: index > 0,
                            canMoveDown:
                                index + 1 < state.values.count,
                            onMoveUp: {
                                moveValue(
                                    state,
                                    from: index,
                                    by: -1
                                )
                            },
                            onMoveDown: {
                                moveValue(
                                    state,
                                    from: index,
                                    by: 1
                                )
                            }
                        )

                        Divider()

                        Button(
                            "削除",
                            role: .destructive
                        ) {
                            requestDeleteValue(
                                value,
                                from: state
                            )
                        }
                        .disabled(state.values.count <= 1)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(
                        "(value) の操作"
                    )
                }
                .frame(minHeight: 44)
            }
            .onMove { source, destination in
                var values = state.values
                values.move(
                    fromOffsets: source,
                    toOffset: destination
                )
                commitEnum(
                    values: values,
                    defaultValue: enumDefault(state)
                )
            }

            HStack(spacing: 8) {
                TextField(
                    "新しい選択肢",
                    text: $newValue
                )

                Button("追加") {
                    addValue(to: state)
                }
                .frame(minHeight: 44)
            }

            if let localError {
                ProfileV3InlineAuthoringError(
                    message: localError,
                    correctionHint:
                        "入力中の値は保持されています。重複や空欄を修正してください。"
                )
                .listRowInsets(EdgeInsets())
            }
        } header: {
            Text("選択肢")
        }
    }

    private func addValue(
        to state: ProfileV3StateSummary
    ) {
        guard !newValue
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty else {
            localError = "選択肢を入力してください。"
            return
        }

        let values = state.values + [newValue]
        let currentDefault = enumDefault(state)
        guard ProfileV3StateAuthoringPolicy.isValidEnum(
            values: values,
            defaultValue: currentDefault
        ) else {
            localError =
                state.values.contains(newValue)
                    ? "同じ選択肢は追加できません。"
                    : "選択肢は32個までです。"
            return
        }

        guard commitEnum(
            values: values,
            defaultValue: currentDefault
        ) else {
            return
        }

        newValue = ""
        localError = nil
    }

    @discardableResult
    private func commitEnum(
        values: [String],
        defaultValue: String
    ) -> Bool {
        guard editor.setEnumState(
            id: stateID,
            values: values,
            defaultValue: defaultValue
        ) else {
            captureEditorError(
                fallback: "状態を変更できません"
            )
            return false
        }
        localError = nil
        return true
    }

    private func moveValue(
        _ state: ProfileV3StateSummary,
        from index: Int,
        by offset: Int
    ) {
        let target = index + offset
        guard state.values.indices.contains(index),
              state.values.indices.contains(target) else {
            return
        }

        var values = state.values
        values.swapAt(index, target)
        _ = commitEnum(
            values: values,
            defaultValue: enumDefault(state)
        )
    }

    private func requestDeleteValue(
        _ value: String,
        from state: ProfileV3StateSummary
    ) {
        let currentDefault = enumDefault(state)
        if value == currentDefault {
            pendingDefaultDeletion = value
            return
        }

        guard let index = state.values.firstIndex(
            of: value
        ), let deletion =
            ProfileV3StateAuthoringPolicy
                .deletingEnumValue(
                    at: index,
                    values: state.values,
                    defaultValue: currentDefault,
                    replacementDefault: nil
                ) else {
            localError = "この選択肢は削除できません。"
            return
        }

        _ = commitEnum(
            values: deletion.values,
            defaultValue: deletion.defaultValue
        )
    }

    private func deleteDefaultValue(
        _ value: String,
        replacement: String,
        state: ProfileV3StateSummary
    ) {
        defer {
            pendingDefaultDeletion = nil
        }

        guard let index = state.values.firstIndex(
            of: value
        ), let deletion =
            ProfileV3StateAuthoringPolicy
                .deletingEnumValue(
                    at: index,
                    values: state.values,
                    defaultValue: enumDefault(state),
                    replacementDefault: replacement
                ) else {
            localError =
                "削除後の初期値を選べません。"
            return
        }

        _ = commitEnum(
            values: deletion.values,
            defaultValue: deletion.defaultValue
        )
    }

    private func captureEditorError(fallback: String) {
        localError = editor.errorMessage ?? fallback
        editor.errorMessage = nil
    }
}

private func booleanDefault(
    _ state: ProfileV3StateSummary
) -> Bool {
    if case .bool(let value) = state.defaultValue {
        return value
    }
    return false
}

private func enumDefault(
    _ state: ProfileV3StateSummary
) -> String {
    if case .string(let value) = state.defaultValue {
        return value
    }
    return state.values.first ?? ""
}

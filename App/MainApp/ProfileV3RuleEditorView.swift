import SwiftUI
import GestureIMEProfileAuthoring

/// #102 / #95 §F4: IF/ELSE rules for the selected entry. IF branches are the
/// resolver's cases (first match wins); ELSE is the default behavior and
/// cannot be deleted. Branches outside the §F4 vocabulary are read-only and
/// written back unchanged.
struct ProfileV3RuleSection: View {
    @ObservedObject var editor: ProfileV3EditorModel
    let entryID: String

    var body: some View {
        if let rules = editor.selectedRules {
            VStack(alignment: .leading, spacing: 6) {
                Text("条件で変える（もし〜なら）").font(.subheadline.bold())
                ForEach(Array(rules.branches.enumerated()), id: \.offset) { index, branch in
                    if branch.isAdvanced {
                        branchRow(rules: rules, index: index, branch: branch)
                    } else {
                        branchRow(rules: rules, index: index, branch: branch)
                            .draggable(String(index))
                            .dropDestination(for: String.self) { items, _ in
                                guard let from = items.first.flatMap(Int.init) else { return false }
                                var updated = rules
                                guard updated.moveOrdinaryBranch(from: from, to: index) else { return false }
                                return editor.setSelectedRules(updated)
                            }
                    }
                }
                HStack {
                    Text("それ以外").font(.caption.bold())
                    Text(ProfileV3Rules.simpleText(of: rules.elseBehavior).map { "「\($0)」" }
                        ?? "上のタップ・フリック設定")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    var updated = rules
                    updated.branches.append(.editable(
                        condition: ProfileV3RuleCondition(terms: [ProfileV3RuleTerm(.flag(.conversionActive))]),
                        behavior: rules.elseBehavior,
                        extra: [:]
                    ))
                    editor.setSelectedRules(updated)
                } label: {
                    Label("条件を追加", systemImage: "plus")
                }
                .font(.caption)
                Text("上から順に調べ、最初に当てはまった条件の動作を使います。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func branchRow(
        rules: ProfileV3RuleSet,
        index: Int,
        branch: ProfileV3RuleBranch
    ) -> some View {
        ProfileV3HierarchyRow(depth: 1) {
            HStack(alignment: .top) {
                switch branch {
                case .advanced:
                    Label("詳細設定で編集された条件", systemImage: "lock")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .editable(let condition, let behavior, let extra):
                    NavigationLink {
                        ProfileV3RuleBranchEditor(
                            editor: editor,
                            condition: condition,
                            behavior: ProfileV3BranchBehavior(behavior),
                            onSave: { newCondition, newBehavior in
                                var updated = rules
                                updated.branches[index] = .editable(
                                    condition: newCondition,
                                    behavior: newBehavior.applied(to: behavior),
                                    extra: extra
                                )
                                return editor.setSelectedRules(updated)
                            }
                        )
                    } label: {
                        VStack(alignment: .leading) {
                            Text("もし " + Self.describe(condition))
                                .font(.caption)
                            Text(Self.describe(ProfileV3BranchBehavior(behavior)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if !branch.isAdvanced {
                    Menu {
                        profileV3MoveMenuItems(
                            canMoveUp: rules.canMoveOrdinaryBranch(
                                from: index,
                                to: index - 1
                            ),
                            canMoveDown: rules.canMoveOrdinaryBranch(
                                from: index,
                                to: index + 1
                            ),
                            onMoveUp: { move(rules, index, by: -1) },
                            onMoveDown: { move(rules, index, by: 1) }
                        )
                        Divider()
                        Button("削除", role: .destructive) {
                            var updated = rules
                            guard updated.deleteOrdinaryBranch(at: index) else {
                                return
                            }
                            editor.setSelectedRules(updated)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("条件の操作")
                }
            }
        }
    }

    private func move(_ rules: ProfileV3RuleSet, _ index: Int, by offset: Int) {
        var updated = rules
        guard updated.moveOrdinaryBranch(from: index, to: index + offset) else { return }
        editor.setSelectedRules(updated)
    }

    static func describe(_ condition: ProfileV3RuleCondition) -> String {
        let parts = condition.terms.map(describe)
        switch condition.combine {
        case .single: return parts.first ?? ""
        case .all: return "すべて: " + parts.joined(separator: "・")
        case .any: return "いずれか: " + parts.joined(separator: "・")
        }
    }

    static func describe(_ term: ProfileV3RuleTerm) -> String {
        let base: String
        switch term.test {
        case .flag(let flag): base = ProfileV3RuleKind.flag(flag).title
        case .factEquals(let fact, let value):
            base = "\(ProfileV3RuleKind.fact(fact).title)が「\(ProfileV3RuleKind.valueLabel(fact, value))」"
        case .stateEquals(let state, let value): base = "状態 \(state) が「\(Self.literalText(value))」"
        case .transformMatch(let table): base = "直前の文字が変換表 \(table) に含まれる"
        }
        return term.negated ? "「\(base)」でない" : base
    }

    static func describe(_ behavior: ProfileV3BranchBehavior) -> String {
        var parts: [String] = []
        if let text = behavior.displayText { parts.append("表示「\(text)」") }
        if !behavior.actionsEditable {
            parts.append("詳細設定の動作")
        } else if !behavior.actions.isEmpty {
            let titles = behavior.actions.map { action in
                CommonActionOption.exact(action.actionID)?.displayTitle ?? action.actionID
            }
            parts.append("動作 " + titles.joined(separator: " → "))
        }
        if let target = behavior.transition?.targetBoardID { parts.append("次の段階 \(target)") }
        return "→ " + (parts.isEmpty ? "何もしない" : parts.joined(separator: "・"))
    }

    static func literalText(_ value: JSONNode) -> String {
        switch value {
        case .string(let text): return text
        case .bool(let flag): return flag ? "オン" : "オフ"
        default: return ""
        }
    }
}

enum ProfileV3RuleKind: Hashable, Identifiable {
    case flag(ProfileV3RuleFlag)
    case fact(ProfileV3RuleStringFact)
    case state
    case transformMatch

    var id: String { title }

    static let all: [ProfileV3RuleKind] =
        ProfileV3RuleFlag.allCases.map(ProfileV3RuleKind.flag)
        + ProfileV3RuleStringFact.allCases.map(ProfileV3RuleKind.fact)
        + [.state, .transformMatch]

    var title: String {
        switch self {
        case .flag(.conversionActive): "変換中"
        case .flag(.conversionHasCandidates): "変換候補がある"
        case .flag(.compositionEmpty): "入力中の文字がない"
        case .flag(.autocapitalizeNext): "自動で大文字にする位置"
        case .fact(.returnKey): "Return用途"
        case .fact(.keyboardType): "入力欄の種類"
        case .fact(.layerID): "キーボード面"
        case .state: "状態"
        case .transformMatch: "直前の文字が変換表に含まれる"
        }
    }

    static func valueLabel(_ fact: ProfileV3RuleStringFact, _ value: String) -> String {
        let labels: [String: String] = switch fact {
        case .returnKey: [
            "default": "標準", "go": "開く", "search": "検索", "send": "送信", "next": "次へ",
            "done": "完了", "join": "参加", "route": "経路", "continue": "続ける", "emergencyCall": "緊急"
        ]
        case .keyboardType: [
            "default": "標準", "ascii": "英字", "numbers": "数字と記号", "url": "URL", "email": "メール",
            "phone": "電話番号", "decimal": "小数", "twitter": "SNS", "webSearch": "Web検索"
        ]
        case .layerID: [:]
        }
        return labels[value] ?? value
    }

    init(_ test: ProfileV3RuleTest) {
        switch test {
        case .flag(let flag): self = .flag(flag)
        case .factEquals(let fact, _): self = .fact(fact)
        case .stateEquals: self = .state
        case .transformMatch: self = .transformMatch
        }
    }
}

private struct ProfileV3RuleBranchEditor: View {
    @ObservedObject var editor: ProfileV3EditorModel
    let onSave: (ProfileV3RuleCondition, ProfileV3BranchBehavior) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var condition: ProfileV3RuleCondition
    @State private var behavior: ProfileV3BranchBehavior
    @State private var saveError: String?

    init(
        editor: ProfileV3EditorModel,
        condition: ProfileV3RuleCondition,
        behavior: ProfileV3BranchBehavior,
        onSave: @escaping (ProfileV3RuleCondition, ProfileV3BranchBehavior) -> Bool
    ) {
        self.editor = editor
        self.onSave = onSave
        _condition = State(initialValue: condition)
        _behavior = State(initialValue: behavior)
        _saveError = State(initialValue: nil)
    }

    var body: some View {
        Form {
            Section {
                if condition.terms.count > 1 {
                    Picker("組み合わせ", selection: $condition.combine) {
                        Text("すべて満たす").tag(ProfileV3RuleCondition.Combine.all)
                        Text("いずれかを満たす").tag(ProfileV3RuleCondition.Combine.any)
                    }
                }
                ForEach(condition.terms.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("条件 \(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        termEditor(index)
                        if condition.terms.count > 1 {
                            Button("この条件を削除", role: .destructive) {
                                condition.terms.remove(at: index)
                                if condition.terms.count == 1 {
                                    condition.combine = .single
                                }
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Button {
                    if condition.combine == .single {
                        condition.combine = .all
                    }
                    condition.terms.append(
                        ProfileV3RuleTerm(.flag(.compositionEmpty))
                    )
                } label: {
                    Label("条件を重ねる", systemImage: "plus.circle")
                }
            } header: {
                Text("もし")
            } footer: {
                Text("上から順に条件を判定します。「〜でない」や、すべて／いずれかの組み合わせもここで設定できます。")
            }

            Section("表示") {
                TextField("キーに表示する文字", text: Binding(
                    get: { behavior.displayText ?? "" },
                    set: { behavior.displayText = $0.isEmpty ? nil : $0 }
                ))
            }

            Section {
                ProfileV3CommonActionStackEditor(
                    editor: editor,
                    actions: $behavior.actions,
                    sourceEditable:
                        behavior.actionsEditable,
                    maximumActions: 16
                )
            } header: {
                Text("すること")
            } footer: {
                if behavior.actionsEditable {
                    Text(
                        "上から順に実行します。マクロと同じ動作編集を使います。"
                    )
                }
            }

            Section("次の段階") {
                Picker("移動先", selection: Binding(
                    get: { behavior.transition?.targetBoardID ?? "" },
                    set: { target in
                        behavior.transition = target.isEmpty ? nil : ProfileV3TransitionDraft(
                            targetBoardID: target,
                            lifetime: behavior.transition?.lifetime ?? .transient
                        )
                    }
                )) {
                    Text("なし").tag("")
                    ForEach(editor.boards) { Text($0.id).tag($0.id) }
                }
            }
        }
        .navigationTitle("条件と動作")
        .safeAreaInset(edge: .bottom) {
            if let saveError {
                ProfileV3InlineAuthoringError(
                    message: saveError,
                    correctionHint: "内容を修正して、もう一度保存してください。"
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    if onSave(condition, behavior) {
                        dismiss()
                    } else {
                        saveError = editor.errorMessage ?? "条件を保存できません"
                        editor.errorMessage = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func termEditor(_ index: Int) -> some View {
        let term = condition.terms[index]
        Picker("種類", selection: Binding(
            get: { ProfileV3RuleKind(term.test) },
            set: { condition.terms[index].test = defaultTest(for: $0) }
        )) {
            ForEach(availableKinds) { Text($0.title).tag($0) }
        }

        switch term.test {
        case .flag:
            EmptyView()

        case .transformMatch(let tableID):
            Picker("変換表", selection: Binding(
                get: { tableID },
                set: { condition.terms[index].test = .transformMatch(tableID: $0) }
            )) {
                ForEach(editor.transformRows) {
                    Text($0.displayTitle).tag($0.id)
                }
            }
            if let table = editor.transformRows.first(where: { $0.id == tableID }) {
                NavigationLink {
                    ProfileV3TransformEditorView(
                        editor: editor,
                        focusedTableID: tableID
                    )
                } label: {
                    Label(
                        "「\(table.displayTitle)」を変換表で見る",
                        systemImage: "tablecells"
                    )
                }
            }

        case .factEquals(let fact, let value):
            Picker("値", selection: Binding(
                get: { value },
                set: { condition.terms[index].test = .factEquals(fact, $0) }
            )) {
                ForEach(values(for: fact, current: value), id: \.self) {
                    Text(ProfileV3RuleKind.valueLabel(fact, $0)).tag($0)
                }
            }

        case .stateEquals(let stateID, let value):
            Picker("状態", selection: Binding(
                get: { stateID },
                set: {
                    condition.terms[index].test = .stateEquals(
                        stateID: $0,
                        value: defaultValue(for: $0)
                    )
                }
            )) {
                ForEach(editor.states) { Text($0.id).tag($0.id) }
            }
            stateValuePicker(index: index, stateID: stateID, value: value)
        }

        Toggle(
            "「〜でない」にする",
            isOn: $condition.terms[index].negated
        )
    }

    private func values(
        for fact: ProfileV3RuleStringFact,
        current: String
    ) -> [String] {
        let list = fact.catalog ?? editor.layers.map(\.id)
        return list.contains(current) || current.isEmpty
            ? list
            : [current] + list
    }

    @ViewBuilder
    private func stateValuePicker(
        index: Int,
        stateID: String,
        value: JSONNode
    ) -> some View {
        let options: [JSONNode] = {
            guard let state = editor.states.first(where: { $0.id == stateID }) else {
                return [value]
            }
            return state.type == .boolean
                ? [.bool(true), .bool(false)]
                : state.values.map(JSONNode.string)
        }()
        Picker("値", selection: Binding(
            get: { ProfileV3RuleSection.literalText(value) },
            set: { text in
                if let match = options.first(where: {
                    ProfileV3RuleSection.literalText($0) == text
                }) {
                    condition.terms[index].test = .stateEquals(
                        stateID: stateID,
                        value: match
                    )
                }
            }
        )) {
            ForEach(
                options.map(ProfileV3RuleSection.literalText),
                id: \.self
            ) {
                Text($0).tag($0)
            }
        }
    }

    private var availableKinds: [ProfileV3RuleKind] {
        ProfileV3RuleKind.all.filter {
            switch $0 {
            case .state:
                !editor.states.isEmpty
            case .transformMatch:
                !editor.transformRows.isEmpty
            default:
                true
            }
        }
    }

    private func defaultValue(for stateID: String) -> JSONNode {
        guard let state = editor.states.first(where: { $0.id == stateID }) else {
            return .bool(true)
        }
        return state.type == .boolean
            ? .bool(true)
            : .string(state.values.first ?? "")
    }

    private func defaultTest(
        for kind: ProfileV3RuleKind
    ) -> ProfileV3RuleTest {
        switch kind {
        case .flag(let flag):
            .flag(flag)
        case .fact(let fact):
            .factEquals(
                fact,
                fact.catalog?.first ?? editor.layers.first?.id ?? ""
            )
        case .state:
            .stateEquals(
                stateID: editor.states.first?.id ?? "",
                value: defaultValue(
                    for: editor.states.first?.id ?? ""
                )
            )
        case .transformMatch:
            .transformMatch(
                tableID: editor.transformRows.first?.id ?? ""
            )
        }
    }
}

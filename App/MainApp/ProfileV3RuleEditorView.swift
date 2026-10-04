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
                    branchRow(rules: rules, index: index, branch: branch)
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
    private func branchRow(rules: ProfileV3RuleSet, index: Int, branch: ProfileV3RuleBranch) -> some View {
        HStack(alignment: .top) {
            switch branch {
            case .advanced:
                Label("詳細条件（読み取り専用・詳細設定のJSONで編集）", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .editable(let condition, let behavior, let extra):
                NavigationLink {
                    ProfileV3RuleBranchEditor(
                        editor: editor,
                        condition: condition,
                        output: ProfileV3Rules.simpleText(of: behavior),
                        onSave: { newCondition, newOutput in
                            var updated = rules
                            let newBehavior = newOutput.map(ProfileV3Rules.textBehavior) ?? behavior
                            updated.branches[index] = .editable(
                                condition: newCondition, behavior: newBehavior, extra: extra
                            )
                            editor.setSelectedRules(updated)
                        }
                    )
                } label: {
                    VStack(alignment: .leading) {
                        Text("もし " + Self.describe(condition)).font(.caption)
                        Text(ProfileV3Rules.simpleText(of: behavior).map { "→「\($0)」" } ?? "→ 詳細な動作")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Menu {
                Button("上へ") { move(rules, index, by: -1) }.disabled(index == 0)
                Button("下へ") { move(rules, index, by: 1) }.disabled(index == rules.branches.count - 1)
                Button("削除", role: .destructive) {
                    var updated = rules
                    updated.branches.remove(at: index)
                    editor.setSelectedRules(updated)
                }
            } label: {
                Image(systemName: "ellipsis.circle").accessibilityLabel("条件の操作")
            }
        }
    }

    private func move(_ rules: ProfileV3RuleSet, _ index: Int, by offset: Int) {
        var updated = rules
        updated.branches.swapAt(index, index + offset)
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
        case .factEquals(let fact, let value): base = "\(ProfileV3RuleKind.fact(fact).title)が「\(value)」"
        case .stateEquals(let state, let value): base = "状態 \(state) が「\(Self.literalText(value))」"
        case .transformMatch(let table): base = "直前の文字が変換表 \(table) に含まれる"
        }
        return term.negated ? "「\(base)」でない" : base
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
    @State var condition: ProfileV3RuleCondition
    @State var output: String?
    let onSave: (ProfileV3RuleCondition, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var outputText = ""

    init(
        editor: ProfileV3EditorModel,
        condition: ProfileV3RuleCondition,
        output: String?,
        onSave: @escaping (ProfileV3RuleCondition, String?) -> Void
    ) {
        self.editor = editor
        _condition = State(initialValue: condition)
        _output = State(initialValue: output)
        _outputText = State(initialValue: output ?? "")
        self.onSave = onSave
    }

    var body: some View {
        Form {
            if condition.terms.count > 1 {
                Picker("組み合わせ", selection: $condition.combine) {
                    Text("すべて当てはまる").tag(ProfileV3RuleCondition.Combine.all)
                    Text("いずれかが当てはまる").tag(ProfileV3RuleCondition.Combine.any)
                }
            }
            ForEach(condition.terms.indices, id: \.self) { index in
                Section("条件 \(index + 1)") {
                    termEditor(index)
                    if condition.terms.count > 1 {
                        Button("この条件を削除", role: .destructive) {
                            condition.terms.remove(at: index)
                            if condition.terms.count == 1 { condition.combine = .single }
                        }
                    }
                }
            }
            Button {
                if condition.combine == .single { condition.combine = .all }
                condition.terms.append(ProfileV3RuleTerm(.flag(.compositionEmpty)))
            } label: {
                Label("条件を重ねる", systemImage: "plus")
            }
            Section("そのときの動作") {
                if output != nil {
                    TextField("入力する文字", text: $outputText)
                } else {
                    Text("詳細な動作です（詳細設定で編集）").foregroundStyle(.secondary)
                    Button("文字の入力に置き換える") { output = "" }
                }
            }
        }
        .navigationTitle("もし〜なら")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    onSave(condition, output == nil ? nil : outputText)
                    dismiss()
                }
                .disabled(output != nil && outputText.isEmpty)
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
        case .transformMatch:
            Picker("変換表", selection: Binding(
                get: { if case .transformMatch(let id) = condition.terms[index].test { id } else { "" } },
                set: { condition.terms[index].test = .transformMatch(tableID: $0) }
            )) {
                ForEach(editor.transformTables) { Text($0.id).tag($0.id) }
            }
        case .factEquals(let fact, let value):
            TextField("値", text: Binding(
                get: { value },
                set: { condition.terms[index].test = .factEquals(fact, $0) }
            ))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        case .stateEquals(let stateID, let value):
            Picker("状態", selection: Binding(
                get: { stateID },
                set: { condition.terms[index].test = .stateEquals(stateID: $0, value: defaultValue(for: $0)) }
            )) {
                ForEach(editor.states) { Text($0.id).tag($0.id) }
            }
            stateValuePicker(index: index, stateID: stateID, value: value)
        }
        Toggle("「〜でない」にする", isOn: $condition.terms[index].negated)
    }

    @ViewBuilder
    private func stateValuePicker(index: Int, stateID: String, value: JSONNode) -> some View {
        let options: [JSONNode] = {
            guard let state = editor.states.first(where: { $0.id == stateID }) else { return [value] }
            return state.type == .boolean ? [.bool(true), .bool(false)] : state.values.map(JSONNode.string)
        }()
        Picker("値", selection: Binding(
            get: { ProfileV3RuleSection.literalText(value) },
            set: { text in
                if let match = options.first(where: { ProfileV3RuleSection.literalText($0) == text }) {
                    condition.terms[index].test = .stateEquals(stateID: stateID, value: match)
                }
            }
        )) {
            ForEach(options.map(ProfileV3RuleSection.literalText), id: \.self) { Text($0).tag($0) }
        }
    }

    private var availableKinds: [ProfileV3RuleKind] {
        ProfileV3RuleKind.all.filter {
            switch $0 {
            case .state: !editor.states.isEmpty
            case .transformMatch: !editor.transformTables.isEmpty
            default: true
            }
        }
    }

    private func defaultValue(for stateID: String) -> JSONNode {
        guard let state = editor.states.first(where: { $0.id == stateID }) else { return .bool(true) }
        return state.type == .boolean ? .bool(true) : .string(state.values.first ?? "")
    }

    private func defaultTest(for kind: ProfileV3RuleKind) -> ProfileV3RuleTest {
        switch kind {
        case .flag(let flag): .flag(flag)
        case .fact(let fact): .factEquals(fact, "")
        case .state:
            .stateEquals(stateID: editor.states.first?.id ?? "", value: defaultValue(for: editor.states.first?.id ?? ""))
        case .transformMatch: .transformMatch(tableID: editor.transformTables.first?.id ?? "")
        }
    }
}

import SwiftUI
import GestureIMEProfileAuthoring

struct ProductRuleIndex: View {
    @ObservedObject var editor: ProfileV3EditorModel

    var body: some View {
        List {
            if let boardID = editor.currentBoardID {
                if editor.entries.isEmpty {
                    ContentUnavailableView(
                        "キーがありません",
                        systemImage: "keyboard"
                    )
                } else {
                    ForEach(editor.entries) { entry in
                        NavigationLink {
                            ProductRuleEditor(
                                editor: editor,
                                boardID: boardID,
                                entryID: entry.id
                            )
                        } label: {
                            HStack {
                                Text(entry.presentationText ?? "キー")
                                Spacer()
                                Text("\(ruleCount(boardID: boardID, entryID: entry.id))件")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("条件")
    }

    private func ruleCount(
        boardID: String,
        entryID: String
    ) -> Int {
        editor.rules(
            boardID: boardID,
            entryID: entryID
        )?.branches.count ?? 0
    }
}

struct ProductRuleEditor: View {
    @ObservedObject var editor: ProfileV3EditorModel
    let boardID: String
    let entryID: String

    @State private var adding = false
    @State private var presetReturnUsage: String?

    private var rules: ProfileV3RuleSet? {
        editor.rules(
            boardID: boardID,
            entryID: entryID
        )
    }

    private var returnUsages: [String] {
        ProfileV3RuleStringFact.returnKey.catalog ?? []
    }

    var body: some View {
        List {
            Section("Return用途") {
                ProductRuleTableHeader()

                ForEach(returnUsages, id: \.self) { usage in
                    if let index = returnBranchIndex(usage) {
                        NavigationLink {
                            ProductRuleBehaviorEditor(
                                editor: editor,
                                boardID: boardID,
                                entryID: entryID,
                                branchIndex: index
                            )
                        } label: {
                            returnRow(
                                usage: usage,
                                behavior: branchBehavior(index)
                            )
                        }
                        .contextMenu {
                            Button("削除", role: .destructive) {
                                deleteBranch(index)
                            }
                        }
                    } else {
                        Button {
                            presetReturnUsage = usage
                            adding = true
                        } label: {
                            returnRow(
                                usage: usage,
                                behavior: nil
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                NavigationLink {
                    ProductRuleBehaviorEditor(
                        editor: editor,
                        boardID: boardID,
                        entryID: entryID,
                        branchIndex: nil
                    )
                } label: {
                    returnRow(
                        usage: "その他",
                        behavior: rules.map {
                            ProfileV3BranchBehavior($0.elseBehavior)
                        }
                    )
                }
            }

            Section("その他の条件") {
                if otherBranchIndices.isEmpty {
                    Text("条件なし")
                        .foregroundStyle(.secondary)
                }

                ForEach(otherBranchIndices, id: \.self) { index in
                    if let rules,
                       case .advanced = rules.branches[index] {
                        HStack {
                            Label("高度な条件", systemImage: "lock")
                            Spacer()
                            Text("保持")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        NavigationLink {
                            ProductRuleBehaviorEditor(
                                editor: editor,
                                boardID: boardID,
                                entryID: entryID,
                                branchIndex: index
                            )
                        } label: {
                            Text(conditionSummary(index))
                        }
                        .contextMenu {
                            Button("上へ") {
                                moveBranch(index, by: -1)
                            }
                            .disabled(!canMove(index, by: -1))

                            Button("下へ") {
                                moveBranch(index, by: 1)
                            }
                            .disabled(!canMove(index, by: 1))

                            Button("削除", role: .destructive) {
                                deleteBranch(index)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(keyTitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presetReturnUsage = nil
                    adding = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("条件を追加")
            }
        }
        .sheet(isPresented: $adding) {
            ProductNewRuleSheet(
                editor: editor,
                presetReturnUsage: presetReturnUsage
            ) { condition in
                addBranch(condition)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let message = editor.errorMessage {
                ProductInlineError(message: message) {
                    editor.errorMessage = nil
                }
            }
        }
    }

    private var keyTitle: String {
        editor.entries.first { $0.id == entryID }?
            .presentationText ?? "条件"
    }

    private var otherBranchIndices: [Int] {
        guard let rules else { return [] }
        return rules.branches.indices.filter {
            !isReturnBranch($0)
        }
    }

    private func isReturnBranch(_ index: Int) -> Bool {
        guard let rules,
              rules.branches.indices.contains(index),
              case .editable(let condition, _, _) = rules.branches[index],
              condition.combine == .single,
              condition.terms.count == 1,
              let term = condition.terms.first,
              !term.negated,
              case .factEquals(.returnKey, _) = term.test
        else {
            return false
        }
        return true
    }

    private func returnBranchIndex(_ usage: String) -> Int? {
        guard let rules else { return nil }
        return rules.branches.indices.first { index in
            guard case .editable(let condition, _, _) = rules.branches[index],
                  condition.combine == .single,
                  condition.terms.count == 1,
                  let term = condition.terms.first,
                  !term.negated,
                  case .factEquals(.returnKey, let value) = term.test
            else {
                return false
            }
            return value == usage
        }
    }

    private func branchBehavior(
        _ index: Int
    ) -> ProfileV3BranchBehavior? {
        guard let rules,
              rules.branches.indices.contains(index),
              case .editable(_, let behavior, _) = rules.branches[index]
        else {
            return nil
        }
        return ProfileV3BranchBehavior(behavior)
    }

    private func returnRow(
        usage: String,
        behavior: ProfileV3BranchBehavior?
    ) -> some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 0) {
            GridRow {
                Text(usageLabel(usage))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(behavior?.displayText ?? "—")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(actionSummary(behavior))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(
                    systemName:
                        behavior?.transition == nil
                        ? "minus"
                        : "arrow.turn.down.right"
                )
                .frame(width: 24)
                .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .frame(minHeight: 44)
    }

    private func actionSummary(
        _ behavior: ProfileV3BranchBehavior?
    ) -> String {
        guard let behavior else { return "追加" }
        guard behavior.actionsEditable else { return "高度" }
        if behavior.actions.isEmpty { return "なし" }
        if behavior.actions.count == 1 {
            return CommonActionOption.exact(
                behavior.actions[0].actionID
            )?.displayTitle ?? behavior.actions[0].actionID
        }
        return "\(behavior.actions.count)動作"
    }

    private func usageLabel(_ value: String) -> String {
        switch value {
        case "default": "通常"
        case "go": "Go"
        case "search": "検索"
        case "send": "送信"
        case "next": "次へ"
        case "done": "完了"
        case "join": "参加"
        case "route": "経路"
        case "continue": "続ける"
        case "emergencyCall": "緊急通報"
        default: value
        }
    }

    private func conditionSummary(_ index: Int) -> String {
        guard let rules,
              rules.branches.indices.contains(index),
              case .editable(let condition, _, _) = rules.branches[index]
        else {
            return "高度な条件"
        }
        return ProductRuleConditionFormatter.summary(condition)
    }

    private func addBranch(
        _ condition: ProfileV3RuleCondition
    ) {
        guard var next = rules else { return }
        next.branches.append(
            .editable(
                condition: condition,
                behavior: next.elseBehavior,
                extra: [:]
            )
        )
        _ = editor.setRules(
            boardID: boardID,
            entryID: entryID,
            rules: next
        )
    }

    private func deleteBranch(_ index: Int) {
        guard var next = rules else { return }
        guard next.deleteOrdinaryBranch(at: index) else { return }
        _ = editor.setRules(
            boardID: boardID,
            entryID: entryID,
            rules: next
        )
    }

    private func canMove(
        _ index: Int,
        by offset: Int
    ) -> Bool {
        guard let rules else { return false }
        return rules.canMoveOrdinaryBranch(
            from: index,
            to: index + offset
        )
    }

    private func moveBranch(
        _ index: Int,
        by offset: Int
    ) {
        guard var next = rules,
              next.moveOrdinaryBranch(
                from: index,
                to: index + offset
              )
        else {
            return
        }
        _ = editor.setRules(
            boardID: boardID,
            entryID: entryID,
            rules: next
        )
    }
}

private struct ProductRuleTableHeader: View {
    var body: some View {
        Grid(horizontalSpacing: 8) {
            GridRow {
                Text("用途")
                Text("表示")
                Text("動作")
                Text("次")
            }
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}

private enum ProductRulePurpose: String, CaseIterable, Identifiable {
    case returnUsage
    case keyboardType
    case conversionActive
    case conversionCandidates
    case compositionEmpty
    case autocapitalize
    case layer
    case state
    case transform

    var id: String { rawValue }

    var title: String {
        switch self {
        case .returnUsage: "Return用途"
        case .keyboardType: "入力欄の種類"
        case .conversionActive: "変換中"
        case .conversionCandidates: "変換候補がある"
        case .compositionEmpty: "入力中の文字がない"
        case .autocapitalize: "自動大文字位置"
        case .layer: "キーボード面"
        case .state: "独自状態"
        case .transform: "直前文字・文字変換"
        }
    }

    var group: String {
        switch self {
        case .returnUsage: "Return用途"
        case .keyboardType: "入力欄の種類"
        case .conversionActive, .conversionCandidates: "変換状態"
        case .compositionEmpty, .autocapitalize: "入力状態"
        case .layer: "キーボード面"
        case .state: "独自状態"
        case .transform: "直前文字・文字変換"
        }
    }
}

private struct ProductNewRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var editor: ProfileV3EditorModel
    let onAdd: (ProfileV3RuleCondition) -> Void

    @State private var purpose: ProductRulePurpose?
    @State private var stringValue = ""
    @State private var stateID = ""
    @State private var stateStringValue = ""
    @State private var stateBoolValue = false
    @State private var transformID = ""

    init(
        editor: ProfileV3EditorModel,
        presetReturnUsage: String?,
        onAdd: @escaping (ProfileV3RuleCondition) -> Void
    ) {
        self.editor = editor
        self.onAdd = onAdd
        _purpose = State(
            initialValue:
                presetReturnUsage == nil
                ? nil
                : .returnUsage
        )
        _stringValue = State(initialValue: presetReturnUsage ?? "")
    }

    var body: some View {
        NavigationStack {
            Group {
                if let purpose {
                    form(purpose)
                } else {
                    purposeList
                }
            }
            .navigationTitle("条件を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }

                if purpose != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("追加") {
                            if let condition = makeCondition() {
                                onAdd(condition)
                                dismiss()
                            }
                        }
                        .disabled(makeCondition() == nil)
                    }
                }
            }
        }
    }

    private var purposeList: some View {
        List {
            ForEach(purposeGroups, id: \.self) { group in
                Section(group) {
                    ForEach(
                        ProductRulePurpose.allCases.filter {
                            $0.group == group
                        }
                    ) { item in
                        Button(item.title) {
                            choose(item)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func form(
        _ purpose: ProductRulePurpose
    ) -> some View {
        Form {
            LabeledContent("条件") {
                Text(purpose.title)
            }

            switch purpose {
            case .returnUsage:
                Picker("用途", selection: $stringValue) {
                    ForEach(
                        ProfileV3RuleStringFact.returnKey.catalog ?? [],
                        id: \.self
                    ) { value in
                        Text(value).tag(value)
                    }
                }

            case .keyboardType:
                Picker("入力欄", selection: $stringValue) {
                    ForEach(
                        ProfileV3RuleStringFact.keyboardType.catalog ?? [],
                        id: \.self
                    ) { value in
                        Text(value).tag(value)
                    }
                }

            case .conversionActive,
                 .conversionCandidates,
                 .compositionEmpty,
                 .autocapitalize:
                Text("この状態のとき")
                    .foregroundStyle(.secondary)

            case .layer:
                Picker("キーボード面", selection: $stringValue) {
                    ForEach(editor.layers) { layer in
                        Text(layer.name ?? "キーボード面")
                            .tag(layer.id)
                    }
                }

            case .state:
                Picker("状態", selection: $stateID) {
                    ForEach(editor.states) { state in
                        Text(state.id).tag(state.id)
                    }
                }
                stateValueEditor

            case .transform:
                Picker("文字変換", selection: $transformID) {
                    ForEach(
                        Array(editor.transformRows.enumerated()),
                        id: \.element.id
                    ) { index, table in
                        Text(table.ordinaryTitle(position: index))
                            .tag(table.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var stateValueEditor: some View {
        if let state = editor.states.first(where: { $0.id == stateID }) {
            switch state.type {
            case .boolean:
                Toggle("値", isOn: $stateBoolValue)
            case .enumeration:
                Picker("値", selection: $stateStringValue) {
                    ForEach(state.values, id: \.self) {
                        Text($0).tag($0)
                    }
                }
            }
        }
    }

    private var purposeGroups: [String] {
        var result: [String] = []
        for item in ProductRulePurpose.allCases
        where !result.contains(item.group) {
            result.append(item.group)
        }
        return result
    }

    private func choose(
        _ purpose: ProductRulePurpose
    ) {
        self.purpose = purpose
        switch purpose {
        case .returnUsage:
            stringValue =
                ProfileV3RuleStringFact.returnKey.catalog?.first ?? ""
        case .keyboardType:
            stringValue =
                ProfileV3RuleStringFact.keyboardType.catalog?.first ?? ""
        case .layer:
            stringValue = editor.layers.first?.id ?? ""
        case .state:
            stateID = editor.states.first?.id ?? ""
            syncStateValue()
        case .transform:
            transformID = editor.transformRows.first?.id ?? ""
        default:
            break
        }
    }

    private func syncStateValue() {
        guard let state = editor.states.first(
            where: { $0.id == stateID }
        ) else {
            return
        }
        switch state.type {
        case .boolean:
            if case .bool(let value) = state.defaultValue {
                stateBoolValue = value
            }
        case .enumeration:
            stateStringValue =
                state.defaultValue.stringValue
                ?? state.values.first
                ?? ""
        }
    }

    private func makeCondition() -> ProfileV3RuleCondition? {
        guard let purpose else { return nil }
        let term: ProfileV3RuleTerm

        switch purpose {
        case .returnUsage:
            guard !stringValue.isEmpty else { return nil }
            term = ProfileV3RuleTerm(
                .factEquals(.returnKey, stringValue)
            )

        case .keyboardType:
            guard !stringValue.isEmpty else { return nil }
            term = ProfileV3RuleTerm(
                .factEquals(.keyboardType, stringValue)
            )

        case .conversionActive:
            term = ProfileV3RuleTerm(.flag(.conversionActive))

        case .conversionCandidates:
            term = ProfileV3RuleTerm(
                .flag(.conversionHasCandidates)
            )

        case .compositionEmpty:
            term = ProfileV3RuleTerm(.flag(.compositionEmpty))

        case .autocapitalize:
            term = ProfileV3RuleTerm(
                .flag(.autocapitalizeNext)
            )

        case .layer:
            guard !stringValue.isEmpty else { return nil }
            term = ProfileV3RuleTerm(
                .factEquals(.layerID, stringValue)
            )

        case .state:
            guard let state = editor.states.first(
                where: { $0.id == stateID }
            ) else {
                return nil
            }
            let value: JSONNode
            switch state.type {
            case .boolean:
                value = .bool(stateBoolValue)
            case .enumeration:
                guard !stateStringValue.isEmpty else {
                    return nil
                }
                value = .string(stateStringValue)
            }
            term = ProfileV3RuleTerm(
                .stateEquals(
                    stateID: state.id,
                    value: value
                )
            )

        case .transform:
            guard !transformID.isEmpty else { return nil }
            term = ProfileV3RuleTerm(
                .transformMatch(tableID: transformID)
            )
        }

        return ProfileV3RuleCondition(terms: [term])
    }
}

struct ProductRuleBehaviorEditor: View {
    @ObservedObject var editor: ProfileV3EditorModel
    let boardID: String
    let entryID: String
    let branchIndex: Int?

    @State private var behavior: ProfileV3BranchBehavior?
    @State private var loaded = false

    var body: some View {
        List {
            if let behavior {
                Section("表示") {
                    TextField(
                        "表示",
                        text: Binding(
                            get: { behavior.displayText ?? "" },
                            set: { value in
                                updateBehavior {
                                    $0.displayText = value
                                }
                            }
                        )
                    )
                }

                if behavior.actionsEditable {
                    ProductActionSequenceSection(
                        editor: editor,
                        actions: Binding(
                            get: {
                                self.behavior?.actions ?? []
                            },
                            set: { value in
                                updateBehavior {
                                    $0.actions = value
                                }
                            }
                        )
                    )
                } else {
                    Section("動作") {
                        Text("高度な動作を保持")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("次の段階") {
                    transitionEditor(behavior)
                }
            }
        }
        .navigationTitle(branchIndex == nil ? "その他" : "条件")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("適用") {
                    apply()
                }
                .disabled(behavior == nil)
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

    @ViewBuilder
    private func transitionEditor(
        _ behavior: ProfileV3BranchBehavior
    ) -> some View {
        let target = editor.entries.first {
            $0.id == entryID
        }?.transition?.targetBoardID

        if let existing = behavior.transition,
           existing.targetBoardID != target {
            LabeledContent("次の段階") {
                Text("高度な遷移を保持")
                    .foregroundStyle(.secondary)
            }
        } else if let target {
            Toggle(
                "このキーの次の段階へ進む",
                isOn: Binding(
                    get: {
                        self.behavior?.transition != nil
                    },
                    set: { enabled in
                        updateBehavior {
                            $0.transition =
                                enabled
                                ? ProfileV3TransitionDraft(
                                    targetBoardID: target,
                                    lifetime: .transient
                                )
                                : nil
                        }
                    }
                )
            )

            if self.behavior?.transition != nil {
                Picker(
                    "持続",
                    selection: Binding(
                        get: {
                            self.behavior?.transition?.lifetime
                                ?? .transient
                        },
                        set: { lifetime in
                            updateBehavior {
                                $0.transition?.lifetime = lifetime
                            }
                        }
                    )
                ) {
                    Text("離すと戻る")
                        .tag(ProfileV3TransitionLifetime.transient)
                    Text("そのまま維持")
                        .tag(ProfileV3TransitionLifetime.persistent)
                }
            }
        } else {
            Text("次の段階なし")
                .foregroundStyle(.secondary)
        }
    }

    private func updateBehavior(
        _ mutation: (inout ProfileV3BranchBehavior) -> Void
    ) {
        guard var next = behavior else { return }
        mutation(&next)
        behavior = next
    }

    private func loadIfNeeded() {
        guard !loaded,
              let rules = editor.rules(
                boardID: boardID,
                entryID: entryID
              )
        else {
            return
        }

        if let branchIndex {
            guard rules.branches.indices.contains(branchIndex),
                  case .editable(_, let node, _) =
                    rules.branches[branchIndex]
            else {
                return
            }
            behavior = ProfileV3BranchBehavior(node)
        } else {
            behavior = ProfileV3BranchBehavior(
                rules.elseBehavior
            )
        }
        loaded = true
    }

    private func apply() {
        guard let behavior,
              var rules = editor.rules(
                boardID: boardID,
                entryID: entryID
              )
        else {
            return
        }

        if let branchIndex {
            guard rules.branches.indices.contains(branchIndex),
                  case .editable(
                    let condition,
                    let original,
                    let extra
                  ) = rules.branches[branchIndex]
            else {
                return
            }
            rules.branches[branchIndex] = .editable(
                condition: condition,
                behavior: behavior.applied(to: original),
                extra: extra
            )
        } else {
            rules.elseBehavior = behavior.applied(
                to: rules.elseBehavior
            )
        }

        _ = editor.setRules(
            boardID: boardID,
            entryID: entryID,
            rules: rules
        )
    }
}

enum ProductRuleConditionFormatter {
    static func summary(
        _ condition: ProfileV3RuleCondition
    ) -> String {
        let pieces = condition.terms.map { term in
            let body: String
            switch term.test {
            case .flag(let flag):
                switch flag {
                case .conversionActive: body = "変換中"
                case .conversionHasCandidates: body = "変換候補あり"
                case .compositionEmpty: body = "入力文字なし"
                case .autocapitalizeNext: body = "自動大文字位置"
                }
            case .factEquals(let fact, let value):
                switch fact {
                case .returnKey: body = "Return: \(value)"
                case .keyboardType: body = "入力欄: \(value)"
                case .layerID: body = "キーボード面: \(value)"
                }
            case .stateEquals(let stateID, let value):
                body = "状態 \(stateID) = \(valueDescription(value))"
            case .transformMatch:
                body = "直前文字が変換表に一致"
            }
            return term.negated ? "NOT \(body)" : body
        }

        switch condition.combine {
        case .single:
            return pieces.first ?? "条件"
        case .all:
            return pieces.joined(separator: " AND ")
        case .any:
            return pieces.joined(separator: " OR ")
        }
    }

    private static func valueDescription(
        _ value: JSONNode
    ) -> String {
        switch value {
        case .string(let value): return value
        case .bool(let value): return value ? "ON" : "OFF"
        default: return "値"
        }
    }
}

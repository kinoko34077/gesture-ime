import GestureIMEProfileAuthoring

enum CommonActionOption: String, CaseIterable, Identifiable {
    case noop
    case textInsert = "text.insert"
    case textDirectInsert = "text.directInsert"
    case editDelete = "edit.delete"
    case cursorMove = "cursor.move"
    case layerSet = "layer.set"
    case layerPush = "layer.push"
    case layerPop = "layer.pop"
    case profileSwitch = "profile.switch"
    case conversionCommit = "conversion.commit"
    case conversionSelectCandidate = "conversion.selectCandidate"
    case panelOpen = "panel.open"
    case macroRun = "macro.run"
    case systemNextKeyboard = "system.nextKeyboard"
    case systemDismissKeyboard = "system.dismissKeyboard"

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .noop: "何もしない"
        case .textInsert: "文字を入力"
        case .textDirectInsert: "文字を直接入力"
        case .editDelete: "文字を削除"
        case .cursorMove: "カーソルを移動"
        case .layerSet: "キーボード面を切り替え"
        case .layerPush: "キーボード面を一時切り替え"
        case .layerPop: "前のキーボード面へ戻る"
        case .profileSwitch: "プロファイルを切り替え"
        case .conversionCommit: "変換を確定"
        case .conversionSelectCandidate: "変換候補を選ぶ"
        case .panelOpen: "パネルを開く"
        case .macroRun: "マクロを実行"
        case .systemNextKeyboard: "次のキーボードへ"
        case .systemDismissKeyboard: "キーボードを閉じる"
        }
    }

    /// Options that can be fully configured from the current phone editor.
    /// profile.switch needs a profile-library picker owned outside one Profile
    /// editing session, so it remains an advanced action here.
    static var ruleEditorOptions: [CommonActionOption] {
        allCases.filter { $0 != .noop && $0 != .profileSwitch }
    }

    var argumentKey: String? {
        switch self {
        case .textInsert, .textDirectInsert: "text"
        case .editDelete: "count"
        case .cursorMove: "offset"
        case .layerSet, .layerPush: "layer"
        case .profileSwitch: "profile"
        case .conversionSelectCandidate: "index"
        case .panelOpen: "panel"
        case .macroRun: "macro"
        default: nil
        }
    }

    var integerArgument: Bool {
        self == .editDelete || self == .cursorMove || self == .conversionSelectCandidate
    }

    /// Existing ordinary editors keep their historical simple drafting
    /// contract. The IF/ELSE editor uses the rule-specific helpers below.
    func makeDraft(argumentText: String) -> ProfileActionDraft {
        guard let argumentKey else {
            return ProfileActionDraft(actionID: rawValue)
        }
        if integerArgument {
            return ProfileActionDraft(
                actionID: rawValue,
                arguments: [argumentKey: .integer(Int64(argumentText) ?? defaultInteger)]
            )
        }
        return ProfileActionDraft(
            actionID: rawValue,
            arguments: [argumentKey: .string(argumentText)]
        )
    }

    private var resolvedStringArgument: Bool {
        self == .textInsert || self == .textDirectInsert
    }

    func ruleArgumentText(from action: ProfileActionDraft) -> String? {
        guard let argumentKey else { return nil }
        return ProfileV3RuleActionDrafting.argumentText(
            from: action,
            key: argumentKey,
            resolvedString: resolvedStringArgument
        )
    }

    func makeRuleDraft(
        argumentText: String,
        preserving previous: ProfileActionDraft?
    ) -> ProfileActionDraft {
        ProfileV3RuleActionDrafting.makeDraft(
            actionID: rawValue,
            argumentKey: argumentKey,
            argumentText: argumentText,
            integerArgument: integerArgument,
            defaultInteger: defaultInteger,
            resolvedStringArgument: resolvedStringArgument,
            preserving: previous
        )
    }

    private var defaultInteger: Int64 {
        switch self {
        case .editDelete: 1
        case .cursorMove: 1
        case .conversionSelectCandidate: 0
        default: 0
        }
    }

    static func from(_ actionID: String) -> CommonActionOption {
        CommonActionOption(rawValue: actionID) ?? .noop
    }

    static func exact(_ actionID: String) -> CommonActionOption? {
        CommonActionOption(rawValue: actionID)
    }
}

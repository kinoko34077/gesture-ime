import GestureIMEProfileAuthoring

enum CommonActionPurpose: String, CaseIterable, Identifiable {
    case text
    case editing
    case keyboard
    case conversion
    case panel
    case automation
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "文字入力"
        case .editing: "編集"
        case .keyboard: "キーボード面"
        case .conversion: "変換"
        case .panel: "パネル"
        case .automation: "マクロ"
        case .system: "キーボード本体"
        }
    }
}

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

    /// Options that can be fully configured from one Profile editing session.
    /// profile.switch needs a profile-library picker owned outside this scope,
    /// so it remains preserved but read-only in ordinary Action authoring.
    static var ordinaryEditorOptions: [CommonActionOption] {
        allCases.filter {
            $0 != .noop && $0 != .profileSwitch
        }
    }

    /// Compatibility alias for the existing Rule editor call sites while U6
    /// moves Rule and Macro onto one ordinary Action grammar.
    static var ruleEditorOptions: [CommonActionOption] {
        ordinaryEditorOptions
    }

    var purpose: CommonActionPurpose {
        switch self {
        case .textInsert, .textDirectInsert:
            .text
        case .editDelete, .cursorMove:
            .editing
        case .layerSet, .layerPush, .layerPop:
            .keyboard
        case .conversionCommit, .conversionSelectCandidate:
            .conversion
        case .panelOpen:
            .panel
        case .macroRun:
            .automation
        case .systemNextKeyboard, .systemDismissKeyboard:
            .system
        case .noop, .profileSwitch:
            .system
        }
    }

    var argumentLabel: String {
        switch self {
        case .textInsert, .textDirectInsert:
            "入力する文字"
        case .editDelete:
            "削除する文字数"
        case .cursorMove:
            "移動量"
        case .conversionSelectCandidate:
            "候補番号"
        case .panelOpen:
            "パネル"
        case .layerSet, .layerPush:
            "キーボード面"
        case .macroRun:
            "マクロ"
        default:
            "値"
        }
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

    func ordinaryArgumentText(
        from action: ProfileActionDraft
    ) -> String? {
        guard let argumentKey else { return nil }
        return ProfileV3RuleActionDrafting.argumentText(
            from: action,
            key: argumentKey,
            resolvedString: resolvedStringArgument
        )
    }

    func makeOrdinaryDraft(
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

    func ruleArgumentText(from action: ProfileActionDraft) -> String? {
        ordinaryArgumentText(from: action)
    }

    func makeRuleDraft(
        argumentText: String,
        preserving previous: ProfileActionDraft?
    ) -> ProfileActionDraft {
        makeOrdinaryDraft(
            argumentText: argumentText,
            preserving: previous
        )
    }

    static func supportsOrdinaryEditing(
        _ action: ProfileActionDraft
    ) -> Bool {
        guard
            let option = exact(action.actionID),
            ordinaryEditorOptions.contains(option)
        else {
            return false
        }

        let allowedKeys =
            option.argumentKey.map { Set([$0]) }
            ?? Set<String>()
        return Set(action.arguments.keys)
            .isSubset(of: allowedKeys)
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

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

    var resolvedStringArgument: Bool {
        self == .textInsert || self == .textDirectInsert
    }

    func argumentText(from action: ProfileActionDraft) -> String? {
        guard let argumentKey else { return nil }
        return ProfileV3RuleActionDrafting.argumentText(
            from: action,
            key: argumentKey,
            resolvedString: resolvedStringArgument
        )
    }

    func makeDraft(
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

    static func from(_ actionID: String) -> CommonActionOption? {
        CommonActionOption(rawValue: actionID)
    }
}

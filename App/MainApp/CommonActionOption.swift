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
}

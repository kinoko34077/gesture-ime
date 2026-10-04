import Foundation

// #92 / #95 §F7: the frozen top-level IA. Four tabs; each of the eight
// categories lives in exactly one tab and is reachable in ≤1 tap.

public enum ProfileV3AppCategory: String, CaseIterable, Sendable {
    case keyboardEditor, inputSettings, conversionDictionary, design
    case keyboardSettings, language, privacy, advanced

    public var title: String {
        switch self {
        case .keyboardEditor: "キーボードを編集"
        case .inputSettings: "入力設定"
        case .conversionDictionary: "変換・辞書"
        case .design: "デザイン"
        case .keyboardSettings: "キーボード設定"
        case .language: "言語"
        case .privacy: "プライバシー"
        case .advanced: "詳細設定・開発者向け"
        }
    }
}

public enum ProfileV3AppTab: String, CaseIterable, Sendable {
    case edit, input, design, settings

    public var title: String {
        switch self {
        case .edit: "編集"
        case .input: "入力"
        case .design: "デザイン"
        case .settings: "設定"
        }
    }

    /// Categories shown in this tab. A single-category tab opens it directly
    /// (0 taps); otherwise each is one row (1 tap).
    public var categories: [ProfileV3AppCategory] {
        switch self {
        case .edit: [.keyboardEditor]
        case .input: [.inputSettings, .conversionDictionary]
        case .design: [.design]
        case .settings: [.keyboardSettings, .language, .privacy, .advanced]
        }
    }

    public static func taps(to category: ProfileV3AppCategory) -> Int? {
        guard let tab = allCases.first(where: { $0.categories.contains(category) }) else { return nil }
        return tab.categories.count == 1 ? 0 : 1
    }
}

import Foundation

// #157 U1 / P13: task-domain IA. Four tabs; Profile is global scope.
// Every canonical ordinary destination lives in exactly one tab and is
// reachable in <= 1 tap from that tab's root.

public enum ProfileV3AppCategory: String, CaseIterable, Sendable {
    case keyboardEditor
    case inputSettings
    case transformTables
    case states
    case macros
    case conversionDictionary
    case design
    case keyboardSettings
    case language
    case privacy
    case advanced

    public var title: String {
        switch self {
        case .keyboardEditor: "キーボードを編集"
        case .inputSettings: "ジェスチャー設定"
        case .transformTables: "文字変換表"
        case .states: "状態"
        case .macros: "マクロ"
        case .conversionDictionary: "変換・辞書の状態"
        case .design: "デザイン"
        case .keyboardSettings: "キーボード設定"
        case .language: "言語"
        case .privacy: "プライバシー"
        case .advanced: "開発者"
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
        case .edit:
            [.keyboardEditor]
        case .input:
            [.inputSettings, .transformTables, .states, .macros, .conversionDictionary]
        case .design:
            [.design]
        case .settings:
            [.keyboardSettings, .language, .privacy, .advanced]
        }
    }

    public static func taps(to category: ProfileV3AppCategory) -> Int? {
        guard let tab = allCases.first(where: { $0.categories.contains(category) }) else { return nil }
        return tab.categories.count == 1 ? 0 : 1
    }
}


/// #95 §F7: one mutable authoring session per Profile identity.
///
/// The App owns the concrete editor type; this cache is deliberately generic so
/// session identity can be verified without importing SwiftUI/App storage.
public final class ProfileV3EditorSessionCache<Session: AnyObject> {
    private var sessions: [String: Session] = [:]

    public init() {}

    public func session(for profileID: String, create: () -> Session) -> Session {
        if let existing = sessions[profileID] {
            return existing
        }
        let created = create()
        sessions[profileID] = created
        return created
    }

    public func existingSession(for profileID: String) -> Session? {
        sessions[profileID]
    }

    public func remove(profileID: String) {
        sessions.removeValue(forKey: profileID)
    }
}

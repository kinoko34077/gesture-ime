import Foundation

// #69 §10 — one Display Catalog. Internal schema/API identifiers stay stable;
// ordinary UI resolves every label/help through this catalog. Japanese is the
// current primary display language. Raw IDs belong only to 詳細設定/debug.

public struct ProfileV3DisplayText: Equatable, Sendable {
    public let title: String
    public let shortLabel: String
    public let help: String
    public let unit: String?

    public init(title: String, shortLabel: String? = nil, help: String, unit: String? = nil) {
        self.title = title
        self.shortLabel = shortLabel ?? title
        self.help = help
        self.unit = unit
    }
}

public enum ProfileV3DisplayKey: String, CaseIterable, Sendable {
    // Containing-app information architecture (#69 §8)
    case sectionKeyboardEditor
    case sectionInputSettings
    case sectionConversion
    case sectionDesign
    case sectionKeyboardSettings
    case sectionLanguage
    case sectionPrivacy
    case sectionAdvanced

    // GesturePolicy (#69 §9)
    case policyDeadZone
    case policyInitialCommit
    case policySubsequentCommit
    case policyHysteresis
    case policyBacktrackDwell

    // Concepts
    case conceptProfile
    case conceptLayer
    case conceptBoard
    case conceptEntry
    case conceptInitialLayer

    // Canvas
    case modeSelect
    case modeCreate
    case modePan
    case actionFitAll
    case actionZoomIn
    case actionZoomOut
    case actionUndo
    case actionRedo
    case actionSave
    case actionPreview
    case actionDelete
    case actionDuplicate
    case actionCopy
    case actionPaste
    case actionBack
    case actionUseAsActive
    case actionExport
    case actionRename

    // Easy inspector (#69 §8.4)
    case inspectorDisplayText
    case inspectorTap
    case inspectorDirections
    case inspectorFlickAssist
    case inspectorNextStage
    case inspectorHold
    case inspectorPosition
    case inspectorSize
    case inspectorNoSelection
    case inspectorComplexEntry

    // Advanced (#69 §8.5)
    case advancedSection
    case advancedPolicyOverride
    case advancedInherited
    case advancedConditions
    case advancedTransitionLifetime
    case advancedInternalID
    case advancedRawJSON
    case advancedProfileSemantics
    case advancedInboundReferences

    // Directions
    case directionCenter
    case directionNorth
    case directionNorthEast
    case directionEast
    case directionSouthEast
    case directionSouth
    case directionSouthWest
    case directionWest
    case directionNorthWest

    // Transition lifetimes
    case lifetimeTransient
    case lifetimePersistent

    // Presets (#69 §17)
    case presetSection
    case presetJapanese12
    case presetLatin12
    case presetQwerty
    case presetNumeric
    case presetFourWay
    case presetEightWay
    case presetMultiStage
    case presetEmpty

    // Validation / status
    case statusValid
    case statusInvalid
}

public enum ProfileV3DisplayCatalog {
    public static func text(_ key: ProfileV3DisplayKey) -> ProfileV3DisplayText {
        switch key {
        case .sectionKeyboardEditor:
            .init(title: "キーボードを編集", help: "キーの配置・フリック先・多段階入力を編集します。")
        case .sectionInputSettings:
            .init(title: "入力設定", help: "すべてのキーに共通するフリックの判定を調整します。")
        case .sectionConversion:
            .init(title: "変換・辞書", help: "変換候補や文字変換表を設定します。")
        case .sectionDesign:
            .init(title: "デザイン", help: "キーボードの見た目を設定します。")
        case .sectionKeyboardSettings:
            .init(title: "キーボード設定", help: "触覚フィードバックやキーボードの高さなどを設定します。")
        case .sectionLanguage:
            .init(title: "言語", help: "入力に使う言語やキーボード面を選びます。")
        case .sectionPrivacy:
            .init(title: "プライバシー", help: "フルアクセスや学習・通信の扱いを確認します。")
        case .sectionAdvanced:
            .init(title: "詳細設定 / 開発者向け", shortLabel: "詳細設定", help: "内部ID・JSON・条件分岐など上級者向けの項目です。")

        case .policyDeadZone:
            .init(title: "無反応距離", help: "指を少し動かしてもフリックと判定しない範囲です。大きくすると誤フリックが減ります。", unit: "マス")
        case .policyInitialCommit:
            .init(title: "1段階目の確定距離", help: "最初のフリック先を選ぶのに必要な移動距離です。", unit: "マス")
        case .policySubsequentCommit:
            .init(title: "2段階目以降の確定距離", help: "多段階入力で次の段階の行き先を選ぶのに必要な移動距離です。", unit: "マス")
        case .policyHysteresis:
            .init(title: "方向切替の遊び", help: "方向の境目で指が揺れても選択がちらつかないようにする余裕です。", unit: "度")
        case .policyBacktrackDwell:
            .init(title: "前の段階へ戻るまでの時間", help: "多段階入力中、中央や何もない方向で指を止めているとこの時間で1段階戻ります。", unit: "ミリ秒")

        case .conceptProfile:
            .init(title: "キーボード", help: "キー配置と動作をまとめた設定一式です。")
        case .conceptLayer:
            .init(title: "キーボード面", help: "かな・英字・記号など、切り替えて使う入力面です。")
        case .conceptBoard:
            .init(title: "入力面", help: "キーやフリック先を配置する面です。")
        case .conceptEntry:
            .init(title: "キー", help: "入力面に置かれた1つのキーまたはフリック先です。")
        case .conceptInitialLayer:
            .init(title: "最初に表示", help: "キーボードを開いた時に最初に表示されるキーボード面です。")

        case .modeSelect:
            .init(title: "選択・移動", shortLabel: "移動", help: "キーを選んでドラッグで移動します。角の丸をドラッグすると大きさを変えます。")
        case .modeCreate:
            .init(title: "キーを追加", shortLabel: "追加", help: "空いている場所をドラッグして新しいキーを作ります。")
        case .modePan:
            .init(title: "表示を動かす", shortLabel: "表示", help: "ドラッグで表示位置を動かし、ピンチで拡大・縮小します。")
        case .actionFitAll:
            .init(title: "全体表示", help: "入力面全体が収まるように表示を合わせます。")
        case .actionZoomIn:
            .init(title: "拡大", help: "表示を拡大します。")
        case .actionZoomOut:
            .init(title: "縮小", help: "表示を縮小します。")
        case .actionUndo:
            .init(title: "取り消す", help: "直前の変更を取り消します。")
        case .actionRedo:
            .init(title: "やり直す", help: "取り消した変更をやり直します。")
        case .actionSave:
            .init(title: "保存", help: "検証に成功した内容を保存します。")
        case .actionPreview:
            .init(title: "プレビュー", help: "実際の入力ランタイムで表示を確認します。")
        case .actionDelete:
            .init(title: "削除", help: "選択中の項目を削除します。取り消すで元に戻せます。")
        case .actionDuplicate:
            .init(title: "複製", help: "選択中のキーを隣に複製します。")
        case .actionCopy:
            .init(title: "コピー", help: "選択中のキーをコピーします。")
        case .actionPaste:
            .init(title: "貼り付け", help: "コピーしたキーを隣に貼り付けます。")
        case .actionBack:
            .init(title: "前の入力面へ", shortLabel: "戻る", help: "1つ前の入力面に戻ります。")
        case .actionUseAsActive:
            .init(title: "このキーボードを使う", help: "このキーボードをアプリ内で有効にします。")
        case .actionExport:
            .init(title: "書き出し", help: "キーボード設定をファイルとして書き出します。")
        case .actionRename:
            .init(title: "名前を変更", help: "名前を変更します。")

        case .inspectorDisplayText:
            .init(title: "表示文字", help: "キーの上に表示する文字です。")
        case .inspectorTap:
            .init(title: "タップ", help: "触れて離した時に入力される文字です。")
        case .inspectorDirections:
            .init(title: "フリック先", help: "上下左右・斜めに弾いた時に入力される文字です。空欄にするとそのフリック先を削除します。")
        case .inspectorFlickAssist:
            .init(title: "フリック補助表示", help: "キーの上にフリック先の文字を小さく表示します。")
        case .inspectorNextStage:
            .init(title: "次の段階", help: "このキーから続けて操作できる次の入力面です。")
        case .inspectorHold:
            .init(title: "長押し", help: "長押しした時の動作です。")
        case .inspectorPosition:
            .init(title: "位置", help: "入力面上の位置（半マス単位）です。")
        case .inspectorSize:
            .init(title: "大きさ", help: "キーの幅と高さ（半マス単位）です。")
        case .inspectorNoSelection:
            .init(title: "キーが選択されていません", help: "入力面のキーをタップすると、ここで内容を編集できます。")
        case .inspectorComplexEntry:
            .init(title: "条件付きの動作", help: "このキーは条件分岐や複数の動作を含むため、詳細設定で編集します。")

        case .advancedSection:
            .init(title: "詳細設定", help: "条件分岐・内部ID・JSONなど上級者向けの項目です。")
        case .advancedPolicyOverride:
            .init(title: "このキーだけ入力設定を変える", help: "このキーから始まる段階だけ、共通の入力設定を一部上書きします。未指定の項目は共通設定に従います。")
        case .advancedInherited:
            .init(title: "共通設定に従う", help: "入力設定の値をそのまま使います。")
        case .advancedConditions:
            .init(title: "条件と動作（JSON）", help: "条件分岐・動作の全体をJSONで直接編集します。")
        case .advancedTransitionLifetime:
            .init(title: "次の段階の持続", help: "一時的: 指を離すと元に戻ります。固定: 指を離しても切り替わったままになります。")
        case .advancedInternalID:
            .init(title: "内部ID", help: "プロファイル内部で使われる識別子です。")
        case .advancedRawJSON:
            .init(title: "JSONを直接編集", help: "検証してから適用します。")
        case .advancedProfileSemantics:
            .init(title: "状態・変換表・マクロ（JSON）", help: "プロファイル全体の状態・文字変換表・マクロを編集します。")
        case .advancedInboundReferences:
            .init(title: "この入力面を使っている場所", help: "この入力面へ移動するキーやキーボード面の一覧です。")

        case .directionCenter:
            .init(title: "中央", help: "動かさずに離した時です。")
        case .directionNorth:
            .init(title: "上", help: "上に弾いた時です。")
        case .directionNorthEast:
            .init(title: "右上", help: "右上に弾いた時です。")
        case .directionEast:
            .init(title: "右", help: "右に弾いた時です。")
        case .directionSouthEast:
            .init(title: "右下", help: "右下に弾いた時です。")
        case .directionSouth:
            .init(title: "下", help: "下に弾いた時です。")
        case .directionSouthWest:
            .init(title: "左下", help: "左下に弾いた時です。")
        case .directionWest:
            .init(title: "左", help: "左に弾いた時です。")
        case .directionNorthWest:
            .init(title: "左上", help: "左上に弾いた時です。")

        case .lifetimeTransient:
            .init(title: "一時的", help: "指を離すと元の入力面に戻ります。")
        case .lifetimePersistent:
            .init(title: "固定", help: "指を離しても切り替えた入力面のままです。")

        case .presetSection:
            .init(title: "ひな形から追加", help: "よく使う配置からキーボード面を作ります。作成後は自由に編集できます。")
        case .presetJapanese12:
            .init(title: "日本語12キー", help: "あ〜わ行のフリック入力です。")
        case .presetLatin12:
            .init(title: "英字12キー", help: "ABC/DEF…のフリック入力です。")
        case .presetQwerty:
            .init(title: "QWERTY", help: "パソコンと同じ英字配列です。")
        case .presetNumeric:
            .init(title: "数字", help: "電話型の数字配列です。")
        case .presetFourWay:
            .init(title: "4方向フリック", help: "上下左右の4方向に弾くキーの例です。")
        case .presetEightWay:
            .init(title: "8方向フリック", help: "斜めを含む8方向に弾くキーの例です。")
        case .presetMultiStage:
            .init(title: "多段階フリック", help: "弾いた先からさらに弾ける多段階入力の例です。")
        case .presetEmpty:
            .init(title: "空の入力面", help: "何もない入力面から作ります。")

        case .statusValid:
            .init(title: "検証OK", help: "このキーボードは有効です。")
        case .statusInvalid:
            .init(title: "要修正", help: "保存・有効化する前に修正が必要です。")
        }
    }

    public static func title(_ key: ProfileV3DisplayKey) -> String { text(key).title }
    public static func help(_ key: ProfileV3DisplayKey) -> String { text(key).help }

    /// Ordinary-UI title for common Action IDs; unknown IDs fall back to a
    /// generic label so raw IDs never become the ordinary label.
    public static func actionTitle(_ actionID: String) -> String {
        switch actionID {
        case "text.insert": "文字を入力"
        case "text.directInsert": "文字を直接入力"
        case "text.transform": "文字を変換"
        case "edit.delete": "削除"
        case "cursor.move": "カーソル移動"
        case "composition.confirm": "確定"
        case "conversion.next": "次の変換候補"
        case "layer.set": "キーボード面を切替"
        case "layer.push": "キーボード面を一時切替"
        case "layer.pop": "前のキーボード面へ"
        case "state.set": "状態を変更"
        case "keyboard.next": "次のキーボード"
        case "keyboard.dismiss": "キーボードを閉じる"
        case "macro.run": "まとめた動作"
        case "noop": "何もしない"
        default: "その他の動作"
        }
    }

    /// Error text shown in ordinary UI for runtime validation codes.
    public static func validationMessage(code: String?) -> String {
        switch code {
        case nil: "検証に失敗しました"
        case "InvalidGesturePolicy": "入力設定の値が有効範囲外です"
        case "MissingReference": "存在しない入力面・キー・表を参照しています"
        case "OverlappingBoardEntries", "BoardRectOverlap": "キー同士が重なっています"
        default: "検証に失敗しました（詳細設定で確認できます）"
        }
    }
}

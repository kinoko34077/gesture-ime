import Foundation
import Combine
import GestureIMEProfileAuthoring

enum ProfileV3PersistenceState: Equatable {
    case dirty
    case savedLocally
    case savedLocallyAndDelivered
    case savedLocallyDeliveryFailed(String)
}

@MainActor
final class ProfileV3EditorModel: ObservableObject {
    @Published private(set) var name = ""
    @Published private(set) var validation: ProfileValidation = .validResult
    @Published private(set) var layers: [ProfileV3LayerSummary] = []
    @Published private(set) var boards: [ProfileV3BoardSummary] = []
    @Published private(set) var entries: [ProfileV3BoardEntrySummary] = []
    @Published private(set) var inboundReferences: [ProfileV3BoardReference] = []
    @Published private(set) var states: [ProfileV3StateSummary] = []
    @Published private(set) var transformTables: [ProfileV3TransformTableSummary] = []
    @Published private(set) var macros: [ProfileV3MacroSummary] = []
    @Published private(set) var policy: ProfileGesturePolicy?
    @Published private(set) var policyValues: ProfileV3GesturePolicyValues?
    @Published private(set) var selectedOverride: ProfileV3GesturePolicyOverride?
    @Published private(set) var selectedSimpleText: String?
    @Published private(set) var selectedTapText: String?
    @Published private(set) var selectedDirectionSlots: [ProfileV3DirectionSlot] = []
    @Published var tool: ProfileV3CanvasTool = .select
    @Published private(set) var selectedGuideOverrides: [String: String] = [:]
    @Published private(set) var themeTokens: [String: JSONNode] = [:]
    @Published private(set) var transformRows: [ProfileV3TransformTableRows] = []
    @Published private(set) var boardPath: [String] = []
    @Published var selectedLayerID = ""
    @Published var selectedEntryID: String? {
        didSet { refreshSelectionDerived() }
    }
    @Published private(set) var hasCopiedEntry = false
    @Published private(set) var copiedEntryRect: ProfileV3Rect?
    @Published private(set) var persistenceState: ProfileV3PersistenceState = .savedLocally
    @Published var errorMessage: String?

    let profileID: String

    private struct EntryClipboard {
        let boardID: String
        let entryID: String
    }

    private let library: ProfileLibraryModel
    private var history: ProfileDocumentHistory?
    private var persistedDocumentData: Data?
    private var lastPersistedState: ProfileV3PersistenceState = .savedLocally
    private var entryClipboard: EntryClipboard?

    init(library: ProfileLibraryModel, profileID: String) {
        self.library = library
        self.profileID = profileID
        reload()
    }

    var currentBoardID: String? { boardPath.last }
    var canUndo: Bool { history?.canUndo == true }
    var canRedo: Bool { history?.canRedo == true }

    func reload() {
        do {
            let document = try library.document(id: profileID)
            guard document.isProfileV3 else {
                throw ProfileAuthoringError.invalidJSON(
                    "ProfileV3EditorModel requires gesture-ime.profile.v3"
                )
            }
            history = ProfileDocumentHistory(document: document)
            persistedDocumentData = try document.encoded(pretty: false)
            lastPersistedState = .savedLocally
            persistenceState = .savedLocally
            errorMessage = nil
            try refreshDerived(resetNavigation: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() {
        guard let document = history?.document else { return }
        do {
            let result = try library.validate(document)
            guard result.valid else {
                throw ProfileAuthoringError.validationFailed(
                    code: result.errorCode,
                    detail: result.detail
                )
            }

            let outcome = try library.save(document)
            persistedDocumentData = try document.encoded(pretty: false)
            switch outcome {
            case .savedLocally:
                lastPersistedState = .savedLocally
                errorMessage = nil
            case .savedLocallyAndDelivered:
                lastPersistedState = .savedLocallyAndDelivered
                errorMessage = nil
            case .savedLocallyDeliveryFailed(let detail):
                lastPersistedState = .savedLocallyDeliveryFailed(detail)
                errorMessage =
                    "プロファイルはアプリ内に保存されましたが、キーボード本体への反映に失敗しました。\(detail)"
            }
            persistenceState = lastPersistedState
            validation = result
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setActive() {
        library.setActive(profileID: profileID)
    }

    /// Activate only after a user explicitly chooses to use this Profile.
    /// A dirty in-memory Profile must be saved successfully before publishing;
    /// selection for editing alone must never alter the active keyboard.
    @discardableResult
    func saveAndActivateForKeyboard() -> Bool {
        if case .dirty = persistenceState {
            save()
            if case .dirty = persistenceState {
                return false
            }
        }

        guard validation.valid else {
            errorMessage = "入力内容を確認してからキーボードを切り替えてください。"
            return false
        }

        library.setActive(profileID: profileID)
        guard library.activeProfileID == profileID else {
            errorMessage = library.errorMessage
                ?? "キーボード本体への反映を確認できませんでした。"
            return false
        }

        // setActive publishes the saved document before setting the active ID.
        lastPersistedState = .savedLocallyAndDelivered
        refreshPersistenceState()
        errorMessage = nil
        return true
    }


    func exportURL() -> URL? {
        library.exportURL(profileID: profileID)
    }

    @discardableResult
    func duplicateProfile() -> String? {
        guard let document = history?.document else { return nil }
        return library.clone(document: document)
    }

    func encodedProfileJSON(pretty: Bool = true) -> String? {
        guard let document = history?.document,
              let data = try? document.encoded(pretty: pretty) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func undo() {
        guard var history else { return }
        guard history.undo() else { return }
        self.history = history
        try? refreshDerived(resetNavigation: false)
    }

    func redo() {
        guard var history else { return }
        guard history.redo() else { return }
        self.history = history
        try? refreshDerived(resetNavigation: false)
    }

    func renameProfile(_ value: String) {
        mutate { try $0.rename(value) }
    }

    func updatePolicy(_ value: ProfileGesturePolicy) {
        mutate { document in
            var policy = value
            policy.deadZone = min(max(policy.deadZone, 0), 2)
            policy.stage1CommitDistance = min(
                max(policy.stage1CommitDistance, max(policy.deadZone, 0.01)),
                4
            )
            policy.stage2CommitDistance = min(
                max(policy.stage2CommitDistance, max(policy.deadZone, 0.01)),
                4
            )
            policy.angularHysteresisDegrees = min(
                max(policy.angularHysteresisDegrees, 0),
                44
            )
            policy.maxDirectionalStages = 16
            try document.setGesturePolicy(policy)
        }
    }

    func selectLayer(_ layerID: String) {
        guard let layer = layers.first(where: { $0.id == layerID }) else { return }
        selectedLayerID = layer.id
        boardPath = [layer.rootBoardID]
        selectedEntryID = nil
        try? refreshBoardDerived()
    }

    func createLayer(id: String, name: String?) {
        let boardID = "board." + id
        mutate { document in
            try document.v3CreateBoard(id: boardID)
            try document.v3CreateLayer(
                id: id,
                name: name,
                rootBoardID: boardID
            )
        }
        if layers.contains(where: { $0.id == id }) {
            selectLayer(id)
        }
    }

    func duplicateSelectedLayer(
        newLayerID: String,
        name: String?,
        newRootBoardID: String
    ) {
        let source = selectedLayerID
        mutate { document in
            try document.v3DuplicateLayer(
                sourceLayerID: source,
                newLayerID: newLayerID,
                newName: name,
                newRootBoardID: newRootBoardID
            )
        }
        if layers.contains(where: { $0.id == newLayerID }) {
            selectLayer(newLayerID)
        }
    }

    func renameSelectedLayer(_ name: String?) {
        let layerID = selectedLayerID
        mutate {
            try $0.v3RenameLayer(id: layerID, name: name)
        }
    }

    func setSelectedLayerInitial() {
        let layerID = selectedLayerID
        mutate {
            try $0.v3SetInitialLayer(layerID)
        }
    }

    func deleteSelectedLayer() {
        let layerID = selectedLayerID
        mutate {
            try $0.v3DeleteLayer(id: layerID)
        }
        if let first = layers.first {
            selectLayer(first.id)
        }
    }

    func createBoard(id: String) {
        mutate { try $0.v3CreateBoard(id: id) }
    }

    func duplicateCurrentBoard(newBoardID: String) {
        guard let currentBoardID else { return }
        mutate {
            try $0.v3DuplicateBoard(
                sourceBoardID: currentBoardID,
                newBoardID: newBoardID
            )
        }
        if boards.contains(where: { $0.id == newBoardID }) {
            navigate(to: newBoardID)
        }
    }

    func deleteCurrentBoard() {
        guard let currentBoardID else { return }
        mutate {
            try $0.v3DeleteBoard(id: currentBoardID)
        }
        if let layer = layers.first(where: { $0.id == selectedLayerID }) {
            boardPath = [layer.rootBoardID]
            selectedEntryID = nil
            try? refreshBoardDerived()
        }
    }

    func navigate(to boardID: String) {
        guard boards.contains(where: { $0.id == boardID }) else { return }
        boardPath.append(boardID)
        selectedEntryID = nil
        try? refreshBoardDerived()
    }

    func navigateBack() {
        guard boardPath.count > 1 else { return }
        boardPath.removeLast()
        selectedEntryID = nil
        try? refreshBoardDerived()
    }

    func navigateToRoot() {
        guard let layer = layers.first(where: { $0.id == selectedLayerID }) else { return }
        boardPath = [layer.rootBoardID]
        selectedEntryID = nil
        try? refreshBoardDerived()
    }

    func openInboundReference(_ reference: ProfileV3BoardReference) {
        switch reference.kind {
        case .layerRoot:
            if let layerID = reference.layerID {
                selectLayer(layerID)
            }

        case .entryTransition, .holdTransition:
            guard let sourceBoardID = reference.sourceBoardID else { return }
            navigate(to: sourceBoardID)
            if let sourceEntryID = reference.sourceEntryID,
               entries.contains(where: { $0.id == sourceEntryID }) {
                selectedEntryID = sourceEntryID
            }
        }
    }

    func selectEntry(_ entryID: String?) {
        selectedEntryID = entryID
    }

    // MARK: - #73 easy inspector / policy / presets

    var selectedEntry: ProfileV3BoardEntrySummary? {
        guard let selectedEntryID else { return nil }
        return entries.first { $0.id == selectedEntryID }
    }

    /// Relative Board reached from the selected entry (its 次の段階).
    var selectedNextStageBoardID: String? {
        selectedEntry?.transition?.targetBoardID
    }

    /// The Board whose directional values the selected key edits.
    /// After navigating into a stage, its origin key edits that *same* Board;
    /// editing its directions must not silently create a further stage.
    var selectedFlickEditBoardID: String? {
        if let target = selectedNextStageBoardID { return target }
        if boardPath.count > 1, selectedEntry?.rect.containsOrigin == true {
            return currentBoardID
        }
        return nil
    }


    /// An immediately flickable root key enters its relative Board at touch-down.
    /// Its Hold must therefore belong to the relative origin entry, not the root.
    var selectedHoldStageBoardID: String? {
        guard let entry = selectedEntry else { return nil }
        if let flickBoard = entry.transition?.targetBoardID {
            return (try? history?.document.v3BoardEntries(boardID: flickBoard))?
                .first(where: { $0.rect.containsOrigin })?
                .hold?.transition?.targetBoardID
        }
        return entry.hold?.transition?.targetBoardID
    }

    // MARK: - #102 IF/ELSE rules (#95 §F4)

    var selectedRules: ProfileV3RuleSet? {
        guard let boardID = currentBoardID, let entryID = selectedEntryID else { return nil }
        return rules(boardID: boardID, entryID: entryID)
    }

    func rules(
        boardID: String,
        entryID: String
    ) -> ProfileV3RuleSet? {
        try? history?.document.v3EntryRules(
            boardID: boardID,
            entryID: entryID
        )
    }

    @discardableResult
    func setRules(
        boardID: String,
        entryID: String,
        rules: ProfileV3RuleSet
    ) -> Bool {
        do {
            try mutateThrowing {
                try $0.v3SetEntryRules(
                    boardID: boardID,
                    entryID: entryID,
                    rules: rules
                )
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func setSelectedRules(_ rules: ProfileV3RuleSet) -> Bool {
        guard let boardID = currentBoardID, let entryID = selectedEntryID else { return false }
        return setRules(
            boardID: boardID,
            entryID: entryID,
            rules: rules
        )
    }

    func updatePolicyValues(_ values: ProfileV3GesturePolicyValues) {
        mutate { try $0.v3SetGesturePolicyValues(values) }
    }

    func setSelectedOverride(_ partial: ProfileV3GesturePolicyOverride?) {
        guard let boardID = currentBoardID, let entryID = selectedEntryID else { return }
        mutate {
            try $0.v3SetEntryPolicyOverride(
                boardID: boardID,
                entryID: entryID,
                override: partial
            )
        }
    }

    func setSelectedDisplayText(_ text: String) {
        guard let boardID = currentBoardID,
              let entry = selectedEntry else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        mutate {
            try $0.v3SetEntryDefaultPresentation(
                boardID: boardID,
                entryID: entry.id,
                text: value.isEmpty ? nil : value,
                accessibilityLabel: entry.accessibilityLabel
            )
        }
    }

    /// タップ: own text output for a simple key, or the center (origin) of the
    /// next-stage Board for a flick key.
    func setSelectedTapText(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let boardID = currentBoardID, let entry = selectedEntry else { return }
        if let target = entry.transition?.targetBoardID {
            guard let document = history?.document,
                  let origin = try? document.v3BoardEntries(boardID: target)
                    .first(where: { $0.rect.containsOrigin }) else {
                mutate {
                    let id = try $0.v3UniqueEntryID(boardID: target, base: "\(target).center")
                    try $0.v3CreateEntry(
                        boardID: target,
                        id: id,
                        rect: ProfileV3Rect(x: -1, y: -1, width: 2, height: 2)
                    )
                    try $0.v3SetSimpleTextOutput(boardID: target, entryID: id, text: value)
                }
                return
            }
            mutate { try $0.v3SetSimpleTextOutput(boardID: target, entryID: origin.id, text: value) }
        } else {
            mutate { try $0.v3SetSimpleTextOutput(boardID: boardID, entryID: entry.id, text: value) }
        }
    }

    func setDirectionText(_ direction: ProfileV3Direction, text: String) {
        guard let target = selectedFlickEditBoardID else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        mutate {
            try $0.v3SetDirectionText(
                boardID: target,
                direction: direction,
                text: value.isEmpty ? nil : value
            )
        }
    }

    /// A missing direction is a visible editor slot, never a runtime hit
    /// target. Users can explicitly create a real next stage from that slot.
    func nextStageForDirection(_ direction: ProfileV3Direction) -> String? {
        guard let boardID = selectedFlickEditBoardID,
              let document = history?.document else { return nil }
        return (try? document.v3ImmediateDirectionSlots(boardID: boardID))?
            .first(where: { $0.direction == direction })?
            .entry?.transition?.targetBoardID
    }

    func directionHasExistingOutput(_ direction: ProfileV3Direction) -> Bool {
        guard let boardID = selectedFlickEditBoardID,
              let document = history?.document,
              let entry = (try? document.v3ImmediateDirectionSlots(boardID: boardID))?
                .first(where: { $0.direction == direction })?.entry else {
            return false
        }
        return !entry.onRelease.isEmpty
            || entry.caseCount > 0
            || entry.hold != nil
    }

    /// Only an intentional user action turns an empty direction into a
    /// transition. Existing release text requires an explicit confirmation;
    /// conditional and Hold behaviors are never overwritten by this shortcut.
    func openOrCreateDirectionStage(
        _ direction: ProfileV3Direction,
        replacingOutput: Bool
    ) -> String? {
        if let existing = nextStageForDirection(direction) { return existing }
        if selectedFlickEditBoardID == nil {
            createNextStageForSelected()
        }
        guard let parentBoardID = selectedFlickEditBoardID,
              let document = history?.document else { return nil }

        let existingEntry = (try? document.v3ImmediateDirectionSlots(
            boardID: parentBoardID
        ))?.first(where: { $0.direction == direction })?.entry

        if let existingEntry {
            guard existingEntry.caseCount == 0, existingEntry.hold == nil else {
                errorMessage = "この方向には条件や長押しがあります。高度な設定で編集してください。"
                return nil
            }
            if !existingEntry.onRelease.isEmpty && !replacingOutput {
                errorMessage = "元の入力を変更する前に確認してください。"
                return nil
            }
        }

        let key = String(describing: direction).lowercased()
        let rect: ProfileV3Rect
        switch direction {
        case .northWest: rect = ProfileV3Rect(x: -3, y: -3, width: 2, height: 2)
        case .north: rect = ProfileV3Rect(x: -1, y: -3, width: 2, height: 2)
        case .northEast: rect = ProfileV3Rect(x: 1, y: -3, width: 2, height: 2)
        case .west: rect = ProfileV3Rect(x: -3, y: -1, width: 2, height: 2)
        case .east: rect = ProfileV3Rect(x: 1, y: -1, width: 2, height: 2)
        case .southWest: rect = ProfileV3Rect(x: -3, y: 1, width: 2, height: 2)
        case .south: rect = ProfileV3Rect(x: -1, y: 1, width: 2, height: 2)
        case .southEast: rect = ProfileV3Rect(x: 1, y: 1, width: 2, height: 2)
        }

        guard let target = try? document.v3UniqueBoardID(
            base: "\(parentBoardID).\(key).next"
        ) else { return nil }
        let entryID: String
        if let existingEntry {
            entryID = existingEntry.id
        } else {
            guard let id = try? document.v3UniqueEntryID(
                boardID: parentBoardID,
                base: "\(parentBoardID).\(key)"
            ) else { return nil }
            entryID = id
        }

        mutate { working in
            try working.v3CreateBoard(id: target)
            try working.v3CreateEntry(
                boardID: target,
                id: "\(target).center",
                rect: ProfileV3Rect(x: -1, y: -1, width: 2, height: 2)
            )
            if existingEntry == nil {
                try working.v3CreateEntry(
                    boardID: parentBoardID,
                    id: entryID,
                    rect: rect
                )
            } else {
                try working.v3SetEntryDefaultActions(
                    boardID: parentBoardID,
                    entryID: entryID,
                    actions: []
                )
            }
            try working.v3SetEntryDefaultTransition(
                boardID: parentBoardID,
                entryID: entryID,
                transition: ProfileV3TransitionDraft(
                    targetBoardID: target,
                    lifetime: .transient
                )
            )
        }
        return boards.contains(where: { $0.id == target }) ? target : nil
    }

    /// Creates a new flick Board with a center key and makes it the selected
    /// entry's 次の段階.
    func createNextStageForSelected() {
        guard let boardID = currentBoardID, let entry = selectedEntry else { return }
        mutate { document in
            let target = try document.v3UniqueBoardID(base: "\(entry.id).flick")
            try document.v3CreateBoard(id: target)
            try document.v3CreateEntry(
                boardID: target,
                id: "\(target).center",
                rect: ProfileV3Rect(x: -1, y: -1, width: 2, height: 2)
            )
            // An empty source must create a truly blank new stage.
            // Never inject a visible "・" just to fill an editor slot.
            if let center = entry.presentationText, !center.isEmpty {
                try document.v3SetSimpleTextOutput(
                    boardID: target,
                    entryID: "\(target).center",
                    text: center
                )
            }

            // All eight empty direction fields are supplied by the fixed
            // editor grid. Their entries are created only when authored;
            // absent directions must remain unassigned for runtime rollback.
            try document.v3SetEntryDefaultActions(boardID: boardID, entryID: entry.id, actions: [])
            try document.v3SetEntryDefaultTransition(
                boardID: boardID,
                entryID: entry.id,
                transition: ProfileV3TransitionDraft(targetBoardID: target, lifetime: .transient)
            )
        }
    }

    func setSelectedTransitionLifetime(_ lifetime: ProfileV3TransitionLifetime) {
        guard let boardID = currentBoardID,
              let entry = selectedEntry,
              let transition = entry.transition else { return }
        mutate {
            try $0.v3SetEntryDefaultTransition(
                boardID: boardID,
                entryID: entry.id,
                transition: ProfileV3TransitionDraft(
                    targetBoardID: transition.targetBoardID,
                    lifetime: lifetime
                )
            )
        }
    }

    // MARK: - #74 guide overrides / Theme

    func setGuideLabel(targetEntryID: String, label: String) {
        guard let boardID = currentBoardID, let entryID = selectedEntryID else { return }
        mutate {
            try $0.v3SetGuideLabelOverride(
                boardID: boardID,
                entryID: entryID,
                targetEntryID: targetEntryID,
                label: label
            )
        }
    }

    func setThemeToken(_ key: String, value: JSONNode?) {
        mutate { try $0.v3SetThemeToken(key, value: value) }
    }

    func exportThemeURL() -> URL? {
        do {
            let data = try ProfileV3ThemeTransfer.export(theme: themeTokens)
            let safeProfileID = profileID.replacingOccurrences(of: "/", with: "-")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(safeProfileID)-theme.json")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func applyThemeTransfer(_ data: Data) {
        do {
            let theme = try ProfileV3ThemeTransfer.parse(data)
            try mutateThrowing {
                try $0.v3ReplaceThemeTokens(theme)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var keyboardTheme: IOSKeyboardTheme {
        IOSKeyboardTheme(themeObject: themeTokens.mapValues(\.foundationValue))
    }

    var persistedKeyboardTheme: IOSKeyboardTheme? {
        guard
            let persistedDocumentData,
            let document = try? ProfileDocument(data: persistedDocumentData),
            let tokens = try? document.v3ThemeTokens()
        else {
            return nil
        }
        return IOSKeyboardTheme(
            themeObject: tokens.mapValues(\.foundationValue)
        )
    }

    func currentDesignPreviewSurface() -> FfiProfileV3BoardSurface? {
        guard let json = encodedProfileJSON(pretty: false) else {
            return nil
        }
        return designPreviewSurface(profileJSON: json)
    }

    func persistedDesignPreviewSurface() -> FfiProfileV3BoardSurface? {
        guard
            let persistedDocumentData,
            let json = String(
                data: persistedDocumentData,
                encoding: .utf8
            )
        else {
            return nil
        }
        return designPreviewSurface(profileJSON: json)
    }

    private func designPreviewSurface(
        profileJSON: String
    ) -> FfiProfileV3BoardSurface? {
        guard let runtime = try? IOSProfileV3RuntimeAdapter(
            profileJSON: profileJSON
        ) else {
            return nil
        }

        if !selectedLayerID.isEmpty,
           let active = try? runtime.activeLayerID(),
           active != selectedLayerID {
            _ = try? runtime.setLayer(selectedLayerID)
        }

        if let currentBoardID {
            return try? runtime.previewSurface(
                boardID: currentBoardID
            )
        }
        return try? runtime.directSurface()
    }

    /// #91: the actual initial Board as the shared runtime compiles it from
    /// the edited Profile (same surface the keyboard renders).
    func previewSurface() -> FfiProfileV3BoardSurface? {
        guard let json = encodedProfileJSON(pretty: false),
              let runtime = try? IOSProfileV3RuntimeAdapter(profileJSON: json) else { return nil }
        return try? runtime.directSurface()
    }

    // MARK: - #157 U4 State authoring

    @discardableResult
    func createBooleanState(
        id: String,
        defaultValue: Bool
    ) -> Bool {
        do {
            try mutateThrowing {
                try $0.v3UpsertBooleanState(
                    id: id,
                    defaultValue: defaultValue
                )
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createBooleanState(defaultValue: Bool) -> String? {
        do {
            guard let document = history?.document else {
                throw ProfileAuthoringError.invalidJSON(
                    "Editor document is unavailable"
                )
            }
            let id = try document.v3NewStateID()
            return createBooleanState(
                id: id,
                defaultValue: defaultValue
            ) ? id : nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func createEnumState(
        id: String,
        initialValue: String
    ) -> Bool {
        do {
            if let error =
                ProfileV3StateAuthoringPolicy.enumValidationError(
                    values: [initialValue],
                    defaultValue: initialValue
                ) {
                throw ProfileAuthoringError.invalidJSON(error)
            }

            try mutateThrowing {
                try $0.v3UpsertEnumState(
                    id: id,
                    values: [initialValue],
                    defaultValue: initialValue
                )
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createEnumState(
        initialValue: String
    ) -> String? {
        do {
            guard let document = history?.document else {
                throw ProfileAuthoringError.invalidJSON(
                    "Editor document is unavailable"
                )
            }
            let id = try document.v3NewStateID()
            return createEnumState(
                id: id,
                initialValue: initialValue
            ) ? id : nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func updateBooleanState(
        id: String,
        defaultValue: Bool
    ) -> Bool {
        do {
            try mutateThrowing {
                try $0.v3UpsertBooleanState(
                    id: id,
                    defaultValue: defaultValue
                )
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func updateEnumState(
        id: String,
        values: [String],
        defaultValue: String
    ) -> Bool {
        do {
            try mutateThrowing {
                try $0.v3UpsertEnumState(
                    id: id,
                    values: values,
                    defaultValue: defaultValue
                )
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func duplicateState(
        id: String,
        newID: String
    ) -> Bool {
        do {
            try mutateThrowing {
                try $0.v3DuplicateState(
                    sourceID: id,
                    newID: newID
                )
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func duplicateState(id: String) -> String? {
        do {
            guard let document = history?.document else {
                throw ProfileAuthoringError.invalidJSON(
                    "Editor document is unavailable"
                )
            }
            let newID = try document.v3NewStateID()
            return duplicateState(
                id: id,
                newID: newID
            ) ? newID : nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func deleteState(id: String) -> Bool {
        do {
            try mutateThrowing {
                try $0.v3DeleteState(id: id)
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - #157 U6 Macro authoring

    @discardableResult
    func createMacro(id: String) -> Bool {
        do {
            try mutateThrowing {
                try $0.v3UpsertMacro(
                    id: id,
                    actions: []
                )
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func createMacro() -> String? {
        do {
            guard let document = history?.document else {
                throw ProfileAuthoringError.invalidJSON(
                    "Editor document is unavailable"
                )
            }
            let id = try document.v3NewMacroID()
            return createMacro(id: id) ? id : nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func updateMacro(
        id: String,
        actions: [ProfileActionDraft]
    ) -> Bool {
        do {
            try mutateThrowing {
                try $0.v3UpsertMacro(
                    id: id,
                    actions: actions
                )
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func duplicateMacro(
        id: String,
        newID: String
    ) -> Bool {
        do {
            try mutateThrowing {
                try $0.v3DuplicateMacro(
                    sourceID: id,
                    newID: newID
                )
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func duplicateMacro(id: String) -> String? {
        do {
            guard let document = history?.document else {
                throw ProfileAuthoringError.invalidJSON(
                    "Editor document is unavailable"
                )
            }
            let newID = try document.v3NewMacroID()
            return duplicateMacro(
                id: id,
                newID: newID
            ) ? newID : nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func deleteMacro(id: String) -> Bool {
        do {
            try mutateThrowing {
                try $0.v3DeleteMacro(id: id)
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - #79 Transform authoring

    func newTransformTableID() throws -> String {
        guard let document = history?.document else {
            throw ProfileAuthoringError.invalidJSON("Editor document is unavailable")
        }
        return try document.v3NewTransformTableID()
    }

    func createTransformTable(
        title: String
    ) -> String? {
        do {
            let id = try newTransformTableID()
            let cleanTitle = title.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let table = ProfileV3TransformTableRows(
                id: id,
                title: cleanTitle.isEmpty ? nil : cleanTitle,
                rows: []
            )
            guard setTransformTable(table) else { return nil }
            return id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func duplicateTransformTable(
        id: String
    ) -> String? {
        do {
            guard let source = transformRows.first(
                where: { $0.id == id }
            ) else {
                throw ProfileAuthoringError.missingReference(id)
            }
            let newID = try newTransformTableID()
            let rows = source.rows.map {
                ProfileV3TransformRow(
                    from: $0.from,
                    to: $0.to,
                    groupPath: $0.groupPath,
                    reverse: $0.reverse
                )
            }
            let copy = ProfileV3TransformTableRows(
                id: newID,
                title: source.displayTitle + " のコピー",
                reverseAll: source.reverseAll,
                groups: source.groups,
                rows: rows
            )
            guard setTransformTable(copy) else { return nil }
            return newID
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func deleteTransformTable(
        id: String
    ) -> Bool {
        do {
            try mutateThrowing {
                try $0.v3DeleteTransformTable(id: id)
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func setTransformTable(_ table: ProfileV3TransformTableRows) -> Bool {
        do {
            try mutateThrowing {
                try $0.v3SetTransformTableRows(table)
            }
            if let index = transformRows.firstIndex(
                where: { $0.id == table.id }
            ) {
                transformRows[index] = transformRows[index]
                    .preservingEditorIDs(from: table)
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func applyTransformCSV(_ text: String) {
        do {
            let tables = try ProfileV3TransformCSV.parse(text)
            try mutateThrowing {
                try $0.v3ApplyTransformCSV(tables)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportTransformCSV() -> URL? {
        let csv = ProfileV3TransformCSV.export(transformRows)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(profileID)-transforms.csv")
        do {
            try Data(csv.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    func createLayer(fromPreset preset: ProfileV3Preset) {
        guard let document = history?.document else { return }
        let existing = Set((try? document.v3LayerSummaries().map(\.id)) ?? [])
        var layerID = "layer.\(preset.rawValue)"
        var index = 2
        while existing.contains(layerID) {
            layerID = "layer.\(preset.rawValue)-\(index)"
            index += 1
        }
        let id = layerID
        mutate {
            try $0.v3CreateLayer(
                fromPreset: preset,
                layerID: id,
                name: ProfileV3DisplayCatalog.title(preset.displayKey)
            )
        }
        if layers.contains(where: { $0.id == id }) {
            selectLayer(id)
        }
    }

    private func refreshSelectionDerived() {
        guard let document = history?.document,
              let boardID = currentBoardID,
              let entry = selectedEntry else {
            selectedOverride = nil
            selectedGuideOverrides = [:]
            selectedSimpleText = nil
            selectedTapText = nil
            selectedDirectionSlots = []
            return
        }
        selectedOverride = try? document.v3EntryPolicyOverride(boardID: boardID, entryID: entry.id)
        selectedGuideOverrides = (try? document.v3GuideLabelOverrides(boardID: boardID, entryID: entry.id)) ?? [:]
        selectedSimpleText = try? document.v3SimpleTextOutput(boardID: boardID, entryID: entry.id)
        if let target = selectedFlickEditBoardID {
            selectedDirectionSlots = (try? document.v3ImmediateDirectionSlots(boardID: target)) ?? []
            if let origin = try? document.v3BoardEntries(boardID: target)
                .first(where: { $0.rect.containsOrigin }) {
                selectedTapText = try? document.v3SimpleTextOutput(boardID: target, entryID: origin.id)
            } else {
                selectedTapText = nil
            }
        } else {
            selectedDirectionSlots = []
            selectedTapText = selectedSimpleText
        }
    }

    func createEntry(rect: ProfileV3Rect) {
        guard let boardID = currentBoardID else { return }
        let id = nextEntryID()
        mutate {
            try $0.v3CreateEntry(boardID: boardID, id: id, rect: rect)
        }
        if entries.contains(where: { $0.id == id }) {
            selectedEntryID = id
        }
    }

    func duplicateSelectedEntry(rect: ProfileV3Rect) {
        guard let boardID = currentBoardID,
              let selectedEntryID else { return }
        let id = nextEntryID()
        mutate {
            try $0.v3DuplicateEntry(
                boardID: boardID,
                sourceEntryID: selectedEntryID,
                newEntryID: id,
                newRect: rect
            )
        }
        if entries.contains(where: { $0.id == id }) {
            self.selectedEntryID = id
        }
    }

    func copySelectedEntry() {
        guard let boardID = currentBoardID,
              let selectedEntryID else { return }
        entryClipboard = EntryClipboard(
            boardID: boardID,
            entryID: selectedEntryID
        )
        hasCopiedEntry = true
        copiedEntryRect = entries.first { $0.id == selectedEntryID }?.rect
    }

    func pasteCopiedEntry(rect: ProfileV3Rect) {
        guard let source = entryClipboard,
              let targetBoardID = currentBoardID else { return }
        let id = nextEntryID()
        mutate {
            try $0.v3CopyEntry(
                sourceBoardID: source.boardID,
                sourceEntryID: source.entryID,
                targetBoardID: targetBoardID,
                newEntryID: id,
                newRect: rect
            )
        }
        if entries.contains(where: { $0.id == id }) {
            selectedEntryID = id
        }
    }

    func setEntryRect(_ entryID: String, rect: ProfileV3Rect) {
        guard let boardID = currentBoardID,
              entries.contains(where: { $0.id == entryID }) else { return }
        mutate {
            try $0.v3SetEntryRect(
                boardID: boardID,
                entryID: entryID,
                rect: rect
            )
        }
    }

    func setSelectedEntryRect(_ rect: ProfileV3Rect) {
        guard let entryID = selectedEntryID else { return }
        setEntryRect(entryID, rect: rect)
    }

    func deleteSelectedEntry() {
        guard let boardID = currentBoardID,
              let entryID = selectedEntryID else { return }
        mutate {
            try $0.v3DeleteEntry(
                boardID: boardID,
                entryID: entryID
            )
        }
        selectedEntryID = nil
    }

    func canPlaceEntry(_ entryID: String, rect: ProfileV3Rect) -> Bool {
        guard let document = history?.document,
              let boardID = currentBoardID,
              entries.contains(where: { $0.id == entryID }) else {
            return false
        }
        var candidate = document
        do {
            try candidate.v3SetEntryRect(
                boardID: boardID,
                entryID: entryID,
                rect: rect
            )
            return try library.validate(candidate).valid
        } catch {
            return false
        }
    }

    func canPlaceSelectedEntry(_ rect: ProfileV3Rect) -> Bool {
        guard let entryID = selectedEntryID else { return false }
        return canPlaceEntry(entryID, rect: rect)
    }

    func canCreateEntry(_ rect: ProfileV3Rect) -> Bool {
        guard let document = history?.document,
              let boardID = currentBoardID else {
            return false
        }
        var candidate = document
        do {
            try candidate.v3CreateEntry(
                boardID: boardID,
                id: nextEntryID(),
                rect: rect
            )
            return try library.validate(candidate).valid
        } catch {
            return false
        }
    }

    func selectedResolverJSON() -> String? {
        guard let document = history?.document,
              let boardID = currentBoardID,
              let entryID = selectedEntryID,
              let resolver = try? document.v3EntryResolver(
                boardID: boardID,
                entryID: entryID
              ),
              let data = try? JSONSerialization.data(
                withJSONObject: resolver.foundationValue,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func setSelectedResolverJSON(_ text: String) -> Bool {
        guard let boardID = currentBoardID,
              let entryID = selectedEntryID,
              let data = text.data(using: .utf8) else {
            return false
        }

        do {
            let object = try JSONSerialization.jsonObject(with: data)
            let node = try JSONNode(foundation: object)
            try mutateThrowing {
                try $0.v3SetEntryResolver(
                    boardID: boardID,
                    entryID: entryID,
                    resolver: node
                )
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func semanticSectionJSON(_ section: ProfileV3SemanticSection) -> String? {
        guard let document = history?.document,
              let node = try? document.v3SemanticSectionNode(section),
              let data = try? JSONSerialization.data(
                withJSONObject: node.foundationValue,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func setSemanticSectionJSON(
        _ section: ProfileV3SemanticSection,
        text: String
    ) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            let node = try JSONNode(foundation: object)
            try mutateThrowing {
                try $0.v3SetSemanticSectionNode(section, node: node)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func previewRuntime() throws -> IOSProfileV3RuntimeAdapter {
        guard let json = encodedProfileJSON(pretty: false) else {
            throw ProfileAuthoringError.invalidJSON("Profile is not UTF-8")
        }
        let runtime = try IOSProfileV3RuntimeAdapter(profileJSON: json)
        if !selectedLayerID.isEmpty,
           try runtime.activeLayerID() != selectedLayerID {
            _ = try runtime.setLayer(selectedLayerID)
        }
        return runtime
    }

    func previewSurface() throws -> FfiProfileV3BoardSurface {
        let runtime = try previewRuntime()
        if let currentBoardID {
            return try runtime.previewSurface(boardID: currentBoardID)
        }
        return try runtime.directSurface()
    }

    private func mutate(
        _ mutation: @escaping (inout ProfileDocument) throws -> Void
    ) {
        do {
            try mutateThrowing(mutation)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func mutateThrowing(
        _ mutation: (inout ProfileDocument) throws -> Void
    ) throws {
        guard var history else {
            throw ProfileAuthoringError.invalidJSON("Editor document is unavailable")
        }

        var candidate = history.document
        try mutation(&candidate)

        let result = try library.validate(candidate)
        guard result.valid else {
            throw ProfileAuthoringError.validationFailed(
                code: result.errorCode,
                detail: result.detail
            )
        }

        try history.mutate { document in
            document = candidate
        }
        self.history = history
        try refreshDerived(resetNavigation: false)
    }

    private func refreshDerived(resetNavigation: Bool) throws {
        guard let document = history?.document else { return }

        name = document.summary.name
        policy = try document.gesturePolicy()
        policyValues = try document.v3GesturePolicyValues()
        themeTokens = try document.v3ThemeTokens()
        layers = try document.v3LayerSummaries()
        boards = try document.v3BoardSummaries()
        states = try document.v3StateSummaries()
        transformTables = try document.v3TransformTableSummaries()
        let previousTransformRows = transformRows
        transformRows = try document.v3TransformTableRows().map { loaded in
            guard let previous = previousTransformRows.first(where: { $0.id == loaded.id }) else {
                return loaded
            }
            return loaded.preservingEditorIDs(from: previous)
        }
        macros = try document.v3MacroSummaries()
        validation = try library.validate(document)

        if !layers.contains(where: { $0.id == selectedLayerID }) {
            selectedLayerID = layers.first(where: { $0.isInitial })?.id
                ?? layers.first?.id
                ?? ""
        }

        if resetNavigation
            || boardPath.isEmpty
            || !boards.contains(where: { $0.id == boardPath.last }) {
            if let layer = layers.first(where: { $0.id == selectedLayerID }) {
                boardPath = [layer.rootBoardID]
            } else {
                boardPath = []
            }
        }

        try refreshBoardDerived()
        refreshPersistenceState()
        objectWillChange.send()
    }

    private func refreshPersistenceState() {
        guard let document = history?.document,
              let current = try? document.encoded(pretty: false),
              let persistedDocumentData else {
            persistenceState = .dirty
            return
        }
        persistenceState = current == persistedDocumentData
            ? lastPersistedState
            : .dirty
    }

    private func refreshBoardDerived() throws {
        guard let document = history?.document,
              let boardID = currentBoardID else {
            entries = []
            inboundReferences = []
            return
        }
        entries = try document.v3BoardEntries(boardID: boardID)
        inboundReferences = try document.v3InboundReferences(to: boardID)
        if let selectedEntryID,
           !entries.contains(where: { $0.id == selectedEntryID }) {
            self.selectedEntryID = nil
        }
        refreshSelectionDerived()
    }

    private func nextEntryID() -> String {
        let used = Set(entries.map(\.id))
        if !used.contains("entry.new") {
            return "entry.new"
        }
        var index = 2
        while used.contains("entry.new.\(index)") {
            index += 1
        }
        return "entry.new.\(index)"
    }
}

import Foundation
import Combine
import GestureIMEProfileAuthoring

@MainActor
final class ProfileEditorModel: ObservableObject {
    @Published var name: String = ""
    @Published var selectedLayerID: String = "base"
    @Published private(set) var layerIDs: [String] = []
    @Published private(set) var keys: [ProfileKeySummary] = []
    @Published private(set) var boards: [ProfileBoardSummary] = []
    @Published private(set) var isBoardGraphV2 = false
    @Published private(set) var validation: ProfileValidation = .validResult
    @Published var errorMessage: String?

    let profileID: String
    private let library: ProfileLibraryModel
    private var document: ProfileDocument?

    init(library: ProfileLibraryModel, profileID: String) {
        self.library = library
        self.profileID = profileID
        reload()
    }

    func reload() {
        do {
            let document = try library.document(id: profileID)
            self.document = document
            name = document.summary.name
            isBoardGraphV2 = document.isBoardGraphV2
            layerIDs = try document.layerIDs()
            if !layerIDs.contains(selectedLayerID) {
                selectedLayerID = layerIDs.first ?? "base"
            }
            keys = try document.keys(layerID: selectedLayerID)
            boards = try document.boardSummaries()
            validation = try library.validate(document)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func migrateToV2() {
        library.migrateToV2(profileID: profileID)
        reload()
    }

    func selectLayer(_ layerID: String) {
        selectedLayerID = layerID
        refreshKeys()
    }

    func rename(_ value: String) {
        guard var document else { return }
        do {
            try document.rename(value)
            self.document = document
            name = value
            refreshValidation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func policy() -> ProfileGesturePolicy? {
        try? document?.gesturePolicy()
    }

    func updatePolicy(_ policy: ProfileGesturePolicy) {
        guard var document else { return }
        do {
            var normalized = policy
            normalized.deadZone = min(max(normalized.deadZone, 0), 2)
            normalized.stage1CommitDistance = min(
                max(normalized.stage1CommitDistance, max(normalized.deadZone, 0.01)),
                4
            )
            normalized.stage2CommitDistance = min(
                max(normalized.stage2CommitDistance, max(normalized.deadZone, 0.01)),
                4
            )
            normalized.angularHysteresisDegrees = min(
                max(normalized.angularHysteresisDegrees, 0),
                44
            )
            normalized.maxDirectionalStages = isBoardGraphV2 ? 16 : 2

            try document.setGesturePolicy(normalized)
            self.document = document
            objectWillChange.send()
            refreshValidation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateKey(
        keyID: String,
        title: String,
        row: Int,
        column: Int,
        width: Double,
        height: Double
    ) {
        guard var document else { return }
        do {
            try document.setKeyPresentation(keyID: keyID, text: title)
            try document.setPlacement(
                layerID: selectedLayerID,
                keyID: keyID,
                row: row,
                column: column,
                width: width,
                height: height
            )
            self.document = document
            refreshKeys()
            refreshValidation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Profile v1 compatibility editor

    func bindings(keyID: String) -> [ProfileBindingSummary] {
        guard !isBoardGraphV2 else { return [] }
        return (try? document?.bindings(layerID: selectedLayerID, keyID: keyID)) ?? []
    }

    func upsertBinding(
        keyID: String,
        originalPath: [ProfileDirection]?,
        path: [ProfileDirection],
        presentationText: String?,
        action: ProfileActionDraft
    ) {
        guard !isBoardGraphV2, var document else { return }
        do {
            if let originalPath, originalPath != path {
                try document.removeBinding(
                    layerID: selectedLayerID,
                    keyID: keyID,
                    path: originalPath
                )
            }
            try document.upsertBinding(
                layerID: selectedLayerID,
                keyID: keyID,
                path: path,
                presentationText: presentationText,
                actions: [action]
            )
            self.document = document
            objectWillChange.send()
            refreshValidation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeBinding(keyID: String, path: [ProfileDirection]) {
        guard !isBoardGraphV2, var document else { return }
        do {
            try document.removeBinding(
                layerID: selectedLayerID,
                keyID: keyID,
                path: path
            )
            self.document = document
            objectWillChange.send()
            refreshValidation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Profile v2 Board editor

    func entryPoint(keyID: String) -> ProfileBoardEntryPointSummary? {
        guard isBoardGraphV2 else { return nil }
        return try? document?.entryPoint(layerID: selectedLayerID, keyID: keyID)
    }

    func setEntryPointBoard(keyID: String, boardID: String) {
        guard isBoardGraphV2, var document else { return }
        do {
            try document.setEntryPointBoard(
                layerID: selectedLayerID,
                keyID: keyID,
                boardID: boardID
            )
            self.document = document
            refreshBoardState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createBoard(id: String) {
        guard isBoardGraphV2, var document else { return }
        do {
            try document.createBoard(id: id)
            self.document = document
            refreshBoardState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func boardEntries(boardID: String) -> [ProfileBoardEntrySummary] {
        guard isBoardGraphV2 else { return [] }
        return (try? document?.boardEntries(boardID: boardID)) ?? []
    }

    func boardHoldTrigger(boardID: String) -> ProfileBoardTriggerSummary? {
        guard isBoardGraphV2 else { return nil }
        return try? document?.boardHoldTrigger(boardID: boardID)
    }

    func upsertBoardEntry(
        boardID: String,
        originalCoordinate: ProfileBoardCoordinate?,
        coordinate: ProfileBoardCoordinate,
        presentationText: String?,
        action: ProfileActionDraft?,
        transition: ProfileBoardTransitionDraft?
    ) {
        guard isBoardGraphV2, var document else { return }
        do {
            try document.upsertBoardEntry(
                boardID: boardID,
                originalCoordinate: originalCoordinate,
                coordinate: coordinate,
                presentationText: presentationText,
                actions: action.map { [$0] } ?? [],
                transition: transition
            )
            self.document = document
            refreshBoardState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeBoardEntry(boardID: String, coordinate: ProfileBoardCoordinate) {
        guard isBoardGraphV2, var document else { return }
        do {
            try document.removeBoardEntry(boardID: boardID, coordinate: coordinate)
            self.document = document
            refreshBoardState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setBoardHoldTransition(
        boardID: String,
        delayMs: Int,
        transition: ProfileBoardTransitionDraft?
    ) {
        guard isBoardGraphV2, var document else { return }
        do {
            try document.setBoardHoldTransition(
                boardID: boardID,
                delayMs: delayMs,
                transition: transition
            )
            self.document = document
            refreshBoardState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() {
        guard let document else { return }
        do {
            try library.save(document)
            validation = try library.validate(document)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshKeys() {
        guard let document else { return }
        do {
            keys = try document.keys(layerID: selectedLayerID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshBoardState() {
        guard let document else { return }
        do {
            boards = try document.boardSummaries()
            refreshValidation()
            objectWillChange.send()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshValidation() {
        guard let document else { return }
        do {
            validation = try library.validate(document)
        } catch {
            validation = ProfileValidation(
                valid: false,
                errorCode: "VALIDATION",
                detail: error.localizedDescription
            )
        }
    }
}

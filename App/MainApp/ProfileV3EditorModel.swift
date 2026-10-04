import Foundation
import Combine
import GestureIMEProfileAuthoring

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
    @Published private(set) var boardPath: [String] = []
    @Published var selectedLayerID = ""
    @Published var selectedEntryID: String?
    @Published private(set) var hasCopiedEntry = false
    @Published var errorMessage: String?

    let profileID: String

    private struct EntryClipboard {
        let boardID: String
        let entryID: String
    }

    private let library: ProfileLibraryModel
    private var history: ProfileDocumentHistory?
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
            try library.save(document)
            validation = result
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setActive() {
        library.setActive(profileID: profileID)
    }

    func exportURL() -> URL? {
        library.exportURL(profileID: profileID)
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
        layers = try document.v3LayerSummaries()
        boards = try document.v3BoardSummaries()
        states = try document.v3StateSummaries()
        transformTables = try document.v3TransformTableSummaries()
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
        objectWillChange.send()
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

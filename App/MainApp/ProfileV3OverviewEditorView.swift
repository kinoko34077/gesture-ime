import SwiftUI
import GestureIMEProfileAuthoring

struct ProfileV3OverviewEditorView: View {
    @StateObject private var editor: ProfileV3EditorModel
    @State private var sheet: ProfileV3EditorSheet?

    private let library: ProfileLibraryModel

    init(library: ProfileLibraryModel, profileID: String) {
        self.library = library
        _editor = StateObject(
            wrappedValue: ProfileV3EditorModel(
                library: library,
                profileID: profileID
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                profileHeader
                layerBar
                boardHeader

                ProfileV3BoardCanvas(
                    entries: editor.entries,
                    selectedEntryID: editor.selectedEntryID,
                    canCreate: editor.canCreateEntry,
                    canMoveSelected: editor.canPlaceSelectedEntry,
                    onCreate: editor.createEntry,
                    onSelect: editor.selectEntry,
                    onMoveSelected: editor.setSelectedEntryRect
                )
                .frame(minHeight: 360, idealHeight: 440, maxHeight: 520)

                if let entry = selectedEntry {
                    ProfileV3EntryInspector(
                        entry: entry,
                        hasCopiedEntry: editor.hasCopiedEntry,
                        onChangeRect: editor.setSelectedEntryRect,
                        onOpenResolver: { sheet = .resolver },
                        onNavigateTransition: { boardID in
                            editor.navigate(to: boardID)
                        },
                        onCopy: editor.copySelectedEntry,
                        onPaste: {
                            editor.pasteCopiedEntry(
                                rect: ProfileV3Rect(
                                    x: entry.rect.x + entry.rect.width,
                                    y: entry.rect.y,
                                    width: entry.rect.width,
                                    height: entry.rect.height
                                )
                            )
                        },
                        onDuplicate: {
                            editor.duplicateSelectedEntry(
                                rect: ProfileV3Rect(
                                    x: entry.rect.x + entry.rect.width,
                                    y: entry.rect.y,
                                    width: entry.rect.width,
                                    height: entry.rect.height
                                )
                            )
                        },
                        onDelete: editor.deleteSelectedEntry
                    )
                }

                inboundReferenceSection
                semanticSection
                policySection
            }
            .padding()
        }
        .navigationTitle(editor.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(item: $sheet) { item in
            sheetContent(item)
        }
        .alert(
            "Profile error",
            isPresented: Binding(
                get: { editor.errorMessage != nil },
                set: { if !$0 { editor.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editor.errorMessage ?? "")
        }
    }

    private var selectedEntry: ProfileV3BoardEntrySummary? {
        guard let id = editor.selectedEntryID else { return nil }
        return editor.entries.first(where: { $0.id == id })
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(editor.name)
                        .font(.headline)
                    Text(editor.profileID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if editor.validation.valid {
                    Label("Valid", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label(
                        editor.validation.errorCode ?? "Invalid",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.red)
                }
            }

            if !editor.validation.valid,
               let detail = editor.validation.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Rename") { sheet = .renameProfile }

                Button("Use as app-local active") {
                    editor.setActive()
                }

                if let url = editor.exportURL() {
                    ShareLink(item: url) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var layerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Layer")
                    .font(.headline)

                Picker(
                    "Layer",
                    selection: Binding(
                        get: { editor.selectedLayerID },
                        set: { editor.selectLayer($0) }
                    )
                ) {
                    ForEach(editor.layers) { layer in
                        Text(
                            (layer.name?.isEmpty == false ? layer.name! : layer.id)
                                + (layer.isInitial ? " ★" : "")
                        )
                        .tag(layer.id)
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                Menu {
                    Button("Create Layer") { sheet = .createLayer }
                    Button("Duplicate Layer") { sheet = .duplicateLayer }
                    Button("Rename Layer") { sheet = .renameLayer }
                    Button("Set as initial Layer") {
                        editor.setSelectedLayerInitial()
                    }
                    Divider()
                    Button("Delete Layer", role: .destructive) {
                        editor.deleteSelectedLayer()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }

            if let layer = editor.layers.first(where: { $0.id == editor.selectedLayerID }) {
                Text("rootBoardRef: \(layer.rootBoardID)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var boardHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    editor.navigateBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(editor.boardPath.count <= 1)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(editor.boardPath.enumerated()), id: \.offset) { index, boardID in
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Button(boardID) {
                                while editor.boardPath.count > index + 1 {
                                    editor.navigateBack()
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.caption.monospaced())
                        }
                    }
                }

                Spacer()

                Menu {
                    Button("Create Board") { sheet = .createBoard }
                    Button("Duplicate current Board") { sheet = .duplicateBoard }
                    Button("Open Board…") { sheet = .openBoard }
                    Divider()
                    Button("Delete current Board", role: .destructive) {
                        editor.deleteCurrentBoard()
                    }
                } label: {
                    Image(systemName: "square.grid.3x3")
                }
            }

            Text("\(editor.entries.count) authored entries · empty cells are not semantic keys")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var inboundReferenceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Inbound references")
                .font(.headline)

            if editor.inboundReferences.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(editor.inboundReferences) { reference in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reference.kind.rawValue)
                            .font(.caption.bold())
                        Text(reference.path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var semanticSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profile semantics")
                .font(.headline)

            HStack {
                semanticButton(
                    "States",
                    count: editor.states.count,
                    sheet: .states
                )
                semanticButton(
                    "Transform tables",
                    count: editor.transformTables.count,
                    sheet: .transformTables
                )
                semanticButton(
                    "Macros",
                    count: editor.macros.count,
                    sheet: .macros
                )
            }

            Text("Complex condition/action trees use canonical JSON fragments with immediate shared-runtime validation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func semanticButton(
        _ title: String,
        count: Int,
        sheet target: ProfileV3EditorSheet
    ) -> some View {
        Button {
            sheet = target
        } label: {
            VStack {
                Text("\(count)")
                    .font(.title3.monospacedDigit())
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var policySection: some View {
        if let policy = editor.policy {
            ProfileV3GesturePolicyEditor(
                policy: policy,
                onChange: editor.updatePolicy
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                editor.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!editor.canUndo)

            Button {
                editor.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!editor.canRedo)

            Button {
                sheet = .preview
            } label: {
                Image(systemName: "play.rectangle")
            }

            Button("Save") {
                editor.save()
            }
            .disabled(!editor.validation.valid)
        }
    }

    @ViewBuilder
    private func sheetContent(_ item: ProfileV3EditorSheet) -> some View {
        switch item {
        case .renameProfile:
            ProfileV3SingleTextSheet(
                title: "Rename Profile",
                label: "Name",
                initialValue: editor.name
            ) { value in
                editor.renameProfile(value)
                return true
            }

        case .createLayer:
            ProfileV3CreateLayerSheet(editor: editor, duplicate: false)

        case .duplicateLayer:
            ProfileV3CreateLayerSheet(editor: editor, duplicate: true)

        case .renameLayer:
            let initial = editor.layers
                .first(where: { $0.id == editor.selectedLayerID })?
                .name ?? ""
            ProfileV3SingleTextSheet(
                title: "Rename Layer",
                label: "Name",
                initialValue: initial
            ) { value in
                editor.renameSelectedLayer(value)
                return true
            }

        case .createBoard:
            ProfileV3SingleTextSheet(
                title: "Create Board",
                label: "Board ID",
                initialValue: "board.new"
            ) { value in
                editor.createBoard(id: value)
                return true
            }

        case .duplicateBoard:
            ProfileV3SingleTextSheet(
                title: "Duplicate Board",
                label: "New Board ID",
                initialValue: (editor.currentBoardID ?? "board") + ".copy"
            ) { value in
                editor.duplicateCurrentBoard(newBoardID: value)
                return true
            }

        case .openBoard:
            ProfileV3BoardPickerSheet(editor: editor)

        case .resolver:
            ProfileV3JSONEditorSheet(
                title: "Entry Resolver",
                initialJSON: editor.selectedResolverJSON() ?? "{}"
            ) { text in
                editor.setSelectedResolverJSON(text)
            }

        case .states:
            semanticEditor(.states, title: "States")

        case .transformTables:
            semanticEditor(.transformTables, title: "Transform Tables")

        case .macros:
            semanticEditor(.macros, title: "Macros")

        case .preview:
            ProfileV3RuntimePreviewSheet(editor: editor)
        }
    }

    private func semanticEditor(
        _ section: ProfileV3SemanticSection,
        title: String
    ) -> some View {
        ProfileV3JSONEditorSheet(
            title: title,
            initialJSON: editor.semanticSectionJSON(section) ?? "[]"
        ) { text in
            editor.setSemanticSectionJSON(section, text: text)
        }
    }
}

private enum ProfileV3EditorSheet: String, Identifiable {
    case renameProfile
    case createLayer
    case duplicateLayer
    case renameLayer
    case createBoard
    case duplicateBoard
    case openBoard
    case resolver
    case states
    case transformTables
    case macros
    case preview

    var id: String { rawValue }
}

private struct ProfileV3GesturePolicyEditor: View {
    @State private var value: ProfileGesturePolicy
    let onChange: (ProfileGesturePolicy) -> Void

    init(
        policy: ProfileGesturePolicy,
        onChange: @escaping (ProfileGesturePolicy) -> Void
    ) {
        _value = State(initialValue: policy)
        self.onChange = onChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gesture policy")
                .font(.headline)

            policySlider(
                "Dead zone",
                binding: $value.deadZone,
                range: 0...2
            )
            policySlider(
                "Initial cell",
                binding: $value.stage1CommitDistance,
                range: 0.01...4
            )
            policySlider(
                "Subsequent cell",
                binding: $value.stage2CommitDistance,
                range: 0.01...4
            )
            policySlider(
                "Angular hysteresis",
                binding: $value.angularHysteresisDegrees,
                range: 0...44
            )
        }
        .onChange(of: value) { _, next in
            onChange(next)
        }
    }

    private func policySlider(
        _ title: String,
        binding: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                Text(String(format: "%.2f", binding.wrappedValue))
                    .font(.caption.monospacedDigit())
            }
            Slider(value: binding, in: range)
        }
    }
}

private struct ProfileV3BoardCanvas: View {
    let entries: [ProfileV3BoardEntrySummary]
    let selectedEntryID: String?
    let canCreate: (ProfileV3Rect) -> Bool
    let canMoveSelected: (ProfileV3Rect) -> Bool
    let onCreate: (ProfileV3Rect) -> Void
    let onSelect: (String?) -> Void
    let onMoveSelected: (ProfileV3Rect) -> Void

    @State private var creationStart: (x: Int, y: Int)?
    @State private var creationRect: ProfileV3Rect?

    var body: some View {
        GeometryReader { proxy in
            let viewport = ProfileV3AtomicViewport(entries: entries)
            let geometry = ProfileV3CanvasGeometry(
                size: proxy.size,
                viewport: viewport
            )

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.quaternary)
                    )

                ProfileV3AtomicGrid(geometry: geometry)

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let cell = geometry.cell(at: value.location) else {
                                    return
                                }
                                if creationStart == nil {
                                    creationStart = cell
                                }
                                if let start = creationStart {
                                    creationRect = Self.rect(from: start, to: cell)
                                }
                            }
                            .onEnded { value in
                                defer {
                                    creationStart = nil
                                    creationRect = nil
                                }
                                guard let end = geometry.cell(at: value.location),
                                      let start = creationStart else {
                                    return
                                }
                                let rect = Self.rect(from: start, to: end)
                                if canCreate(rect) {
                                    onCreate(rect)
                                }
                            }
                    )

                if let creationRect {
                    let frame = geometry.frame(for: creationRect)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            canCreate(creationRect)
                                ? Color.accentColor.opacity(0.18)
                                : Color.red.opacity(0.18)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    canCreate(creationRect)
                                        ? Color.accentColor
                                        : Color.red,
                                    style: StrokeStyle(
                                        lineWidth: 2,
                                        dash: [5, 4]
                                    )
                                )
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(false)
                }

                ForEach(entries) { entry in
                    ProfileV3CanvasEntry(
                        entry: entry,
                        geometry: geometry,
                        selected: entry.id == selectedEntryID,
                        canPlace: canMoveSelected,
                        onSelect: { onSelect(entry.id) },
                        onCommitRect: { rect in
                            onSelect(entry.id)
                            onMoveSelected(rect)
                        }
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("Profile v3 Board canvas")
        }
    }

    private static func rect(
        from start: (x: Int, y: Int),
        to end: (x: Int, y: Int)
    ) -> ProfileV3Rect {
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        return ProfileV3Rect(
            x: minX,
            y: minY,
            width: abs(end.x - start.x) + 1,
            height: abs(end.y - start.y) + 1
        )
    }
}

private struct ProfileV3CanvasEntry: View {
    let entry: ProfileV3BoardEntrySummary
    let geometry: ProfileV3CanvasGeometry
    let selected: Bool
    let canPlace: (ProfileV3Rect) -> Bool
    let onSelect: () -> Void
    let onCommitRect: (ProfileV3Rect) -> Void

    @GestureState private var moveTranslation: CGSize = .zero
    @GestureState private var resizeTranslation: CGSize = .zero

    var body: some View {
        let baseFrame = geometry.frame(for: entry.rect)
        let moveCandidate = movedRect
        let resizeCandidate = resizedRect
        let moving = moveTranslation != .zero
        let resizing = resizeTranslation != .zero
        let candidate = resizing ? resizeCandidate : (moving ? moveCandidate : entry.rect)
        let valid = candidate == entry.rect || canPlace(candidate)
        let frame = geometry.frame(for: candidate)

        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    valid
                        ? (selected ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.08))
                        : Color.red.opacity(0.25)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            valid ? (selected ? Color.accentColor : Color.secondary) : Color.red,
                            lineWidth: selected ? 2 : 1
                        )
                )

            VStack(spacing: 2) {
                Text(entry.presentationText ?? entry.id)
                    .lineLimit(2)
                    .minimumScaleFactor(0.45)
                if selected {
                    Text("\(entry.rect.x),\(entry.rect.y) · \(entry.rect.width)×\(entry.rect.height)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)

            if selected {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 18, height: 18)
                    .padding(2)
                    .gesture(resizeGesture)
                    .accessibilityLabel("Resize entry")
            }
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .gesture(moveGesture)
        .animation(.snappy(duration: 0.12), value: selected)
        .accessibilityLabel(
            entry.accessibilityLabel
                ?? entry.presentationText
                ?? entry.id
        )
    }

    private var movedRect: ProfileV3Rect {
        ProfileV3Rect(
            x: entry.rect.x + geometry.atomicDeltaX(moveTranslation.width),
            y: entry.rect.y + geometry.atomicDeltaY(moveTranslation.height),
            width: entry.rect.width,
            height: entry.rect.height
        )
    }

    private var resizedRect: ProfileV3Rect {
        ProfileV3Rect(
            x: entry.rect.x,
            y: entry.rect.y,
            width: max(
                1,
                entry.rect.width
                    + geometry.atomicDeltaX(resizeTranslation.width)
            ),
            height: max(
                1,
                entry.rect.height
                    + geometry.atomicDeltaY(resizeTranslation.height)
            )
        )
    }

    private var moveGesture: some Gesture {
        DragGesture()
            .updating($moveTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let rect = ProfileV3Rect(
                    x: entry.rect.x
                        + geometry.atomicDeltaX(value.translation.width),
                    y: entry.rect.y
                        + geometry.atomicDeltaY(value.translation.height),
                    width: entry.rect.width,
                    height: entry.rect.height
                )
                if canPlace(rect) {
                    onCommitRect(rect)
                }
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture()
            .updating($resizeTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let rect = ProfileV3Rect(
                    x: entry.rect.x,
                    y: entry.rect.y,
                    width: max(
                        1,
                        entry.rect.width
                            + geometry.atomicDeltaX(value.translation.width)
                    ),
                    height: max(
                        1,
                        entry.rect.height
                            + geometry.atomicDeltaY(value.translation.height)
                    )
                )
                if canPlace(rect) {
                    onCommitRect(rect)
                }
            }
    }
}

private struct ProfileV3AtomicGrid: View {
    let geometry: ProfileV3CanvasGeometry

    var body: some View {
        Canvas { context, _ in
            var path = Path()

            for column in 0...20 {
                let x = geometry.originX + CGFloat(column) * geometry.atomicSize
                path.move(to: CGPoint(x: x, y: geometry.originY))
                path.addLine(
                    to: CGPoint(
                        x: x,
                        y: geometry.originY + 20 * geometry.atomicSize
                    )
                )
            }

            for row in 0...20 {
                let y = geometry.originY + CGFloat(row) * geometry.atomicSize
                path.move(to: CGPoint(x: geometry.originX, y: y))
                path.addLine(
                    to: CGPoint(
                        x: geometry.originX + 20 * geometry.atomicSize,
                        y: y
                    )
                )
            }

            context.stroke(
                path,
                with: .color(.secondary.opacity(0.18)),
                lineWidth: 0.5
            )

            let originX = geometry.originX
                + CGFloat(-geometry.viewport.minX) * geometry.atomicSize
            let originY = geometry.originY
                + CGFloat(-geometry.viewport.minY) * geometry.atomicSize

            if originX >= geometry.originX,
               originX <= geometry.originX + 20 * geometry.atomicSize {
                var origin = Path()
                origin.move(to: CGPoint(x: originX, y: geometry.originY))
                origin.addLine(
                    to: CGPoint(
                        x: originX,
                        y: geometry.originY + 20 * geometry.atomicSize
                    )
                )
                context.stroke(
                    origin,
                    with: .color(.secondary.opacity(0.55)),
                    lineWidth: 1.2
                )
            }

            if originY >= geometry.originY,
               originY <= geometry.originY + 20 * geometry.atomicSize {
                var origin = Path()
                origin.move(to: CGPoint(x: geometry.originX, y: originY))
                origin.addLine(
                    to: CGPoint(
                        x: geometry.originX + 20 * geometry.atomicSize,
                        y: originY
                    )
                )
                context.stroke(
                    origin,
                    with: .color(.secondary.opacity(0.55)),
                    lineWidth: 1.2
                )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ProfileV3AtomicViewport {
    let minX: Int
    let minY: Int

    init(entries: [ProfileV3BoardEntrySummary]) {
        if entries.isEmpty {
            minX = -10
            minY = -10
            return
        }

        let xMin = entries.map(\.rect.x).min() ?? -10
        let xMax = entries.map(\.rect.maxX).max() ?? 10
        let yMin = entries.map(\.rect.y).min() ?? -10
        let yMax = entries.map(\.rect.maxY).max() ?? 10

        minX = Self.windowStart(minimum: xMin, maximum: xMax)
        minY = Self.windowStart(minimum: yMin, maximum: yMax)
    }

    private static func windowStart(
        minimum: Int,
        maximum: Int
    ) -> Int {
        let center = Double(minimum + maximum) / 2
        var start = Int(floor(center - 10))
        start = min(max(start, -20), 0)
        if minimum < start {
            start = minimum
        }
        if maximum > start + 20 {
            start = maximum - 20
        }
        return min(max(start, -20), 0)
    }
}

private struct ProfileV3CanvasGeometry {
    let viewport: ProfileV3AtomicViewport
    let atomicSize: CGFloat
    let originX: CGFloat
    let originY: CGFloat

    init(
        size: CGSize,
        viewport: ProfileV3AtomicViewport
    ) {
        self.viewport = viewport
        atomicSize = max(1, min(size.width, size.height) / 20)
        let side = atomicSize * 20
        originX = (size.width - side) / 2
        originY = (size.height - side) / 2
    }

    func frame(for rect: ProfileV3Rect) -> CGRect {
        CGRect(
            x: originX + CGFloat(rect.x - viewport.minX) * atomicSize,
            y: originY + CGFloat(rect.y - viewport.minY) * atomicSize,
            width: CGFloat(rect.width) * atomicSize,
            height: CGFloat(rect.height) * atomicSize
        )
    }

    func cell(at point: CGPoint) -> (x: Int, y: Int)? {
        let localX = point.x - originX
        let localY = point.y - originY
        guard localX >= 0,
              localY >= 0,
              localX < 20 * atomicSize,
              localY < 20 * atomicSize else {
            return nil
        }

        return (
            x: viewport.minX + Int(floor(localX / atomicSize)),
            y: viewport.minY + Int(floor(localY / atomicSize))
        )
    }

    func atomicDeltaX(_ points: CGFloat) -> Int {
        Int((points / atomicSize).rounded())
    }

    func atomicDeltaY(_ points: CGFloat) -> Int {
        Int((points / atomicSize).rounded())
    }
}

private struct ProfileV3EntryInspector: View {
    let entry: ProfileV3BoardEntrySummary
    let hasCopiedEntry: Bool
    let onChangeRect: (ProfileV3Rect) -> Void
    let onOpenResolver: () -> Void
    let onNavigateTransition: (String) -> Void
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text(entry.presentationText ?? entry.id)
                        .font(.headline)
                    Text(entry.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(
                    "x\(entry.rect.x) y\(entry.rect.y) "
                        + "\(entry.rect.width)×\(entry.rect.height)"
                )
                .font(.caption.monospaced())
            }

            HStack {
                compactStepper(
                    "X",
                    value: entry.rect.x,
                    decrement: {
                        var rect = entry.rect
                        rect.x -= 1
                        onChangeRect(rect)
                    },
                    increment: {
                        var rect = entry.rect
                        rect.x += 1
                        onChangeRect(rect)
                    }
                )
                compactStepper(
                    "Y",
                    value: entry.rect.y,
                    decrement: {
                        var rect = entry.rect
                        rect.y -= 1
                        onChangeRect(rect)
                    },
                    increment: {
                        var rect = entry.rect
                        rect.y += 1
                        onChangeRect(rect)
                    }
                )
            }

            HStack {
                compactStepper(
                    "W",
                    value: entry.rect.width,
                    decrement: {
                        var rect = entry.rect
                        rect.width -= 1
                        onChangeRect(rect)
                    },
                    increment: {
                        var rect = entry.rect
                        rect.width += 1
                        onChangeRect(rect)
                    }
                )
                compactStepper(
                    "H",
                    value: entry.rect.height,
                    decrement: {
                        var rect = entry.rect
                        rect.height -= 1
                        onChangeRect(rect)
                    },
                    increment: {
                        var rect = entry.rect
                        rect.height += 1
                        onChangeRect(rect)
                    }
                )
            }

            HStack {
                Button("Resolver / Actions / Conditions") {
                    onOpenResolver()
                }
                .buttonStyle(.borderedProminent)

                Button("Copy", action: onCopy)
                    .buttonStyle(.bordered)

                Button("Paste", action: onPaste)
                    .buttonStyle(.bordered)
                    .disabled(!hasCopiedEntry)

                Button("Duplicate", action: onDuplicate)
                    .buttonStyle(.bordered)
            }

            if let transition = entry.transition {
                Button {
                    onNavigateTransition(transition.targetBoardID)
                } label: {
                    Label(
                        "Open \(transition.targetBoardID) · \(transition.lifetime.rawValue)",
                        systemImage: "arrow.turn.down.right"
                    )
                }
            }

            if let holdTarget = entry.hold?.transition?.targetBoardID {
                Button {
                    onNavigateTransition(holdTarget)
                } label: {
                    Label(
                        "Open Hold target \(holdTarget)",
                        systemImage: "hand.tap"
                    )
                }
            }

            Button("Delete Entry", role: .destructive, action: onDelete)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func compactStepper(
        _ title: String,
        value: Int,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Text("\(title) \(value)")
                .font(.caption.monospaced())
            Button(action: decrement) {
                Image(systemName: "minus")
            }
            Button(action: increment) {
                Image(systemName: "plus")
            }
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }
}

private struct ProfileV3SingleTextSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let label: String
    let onSave: (String) -> Bool

    @State private var value: String

    init(
        title: String,
        label: String,
        initialValue: String,
        onSave: @escaping (String) -> Bool
    ) {
        self.title = title
        self.label = label
        self.onSave = onSave
        _value = State(initialValue: initialValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(label, text: $value)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if onSave(value) {
                            dismiss()
                        }
                    }
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct ProfileV3CreateLayerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var editor: ProfileV3EditorModel
    let duplicate: Bool

    @State private var layerID = "layer.new"
    @State private var name = ""
    @State private var boardID = "board.layer.new"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Layer ID", text: $layerID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Name", text: $name)
                if duplicate {
                    TextField("New root Board ID", text: $boardID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(duplicate ? "Duplicate Layer" : "Create Layer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(duplicate ? "Duplicate" : "Create") {
                        if duplicate {
                            editor.duplicateSelectedLayer(
                                newLayerID: layerID,
                                name: name.isEmpty ? nil : name,
                                newRootBoardID: boardID
                            )
                        } else {
                            editor.createLayer(
                                id: layerID,
                                name: name.isEmpty ? nil : name
                            )
                        }
                        dismiss()
                    }
                    .disabled(
                        layerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || (duplicate
                                && boardID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    )
                }
            }
        }
    }
}

private struct ProfileV3BoardPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var editor: ProfileV3EditorModel

    var body: some View {
        NavigationStack {
            List(editor.boards) { board in
                Button {
                    editor.navigate(to: board.id)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(board.id)
                            Text("\(board.entryCount) entries")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if board.id == editor.currentBoardID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            .navigationTitle("Open Board")
        }
    }
}

private struct ProfileV3JSONEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let onSave: (String) -> Bool

    @State private var text: String

    init(
        title: String,
        initialJSON: String,
        onSave: @escaping (String) -> Bool
    ) {
        self.title = title
        self.onSave = onSave
        _text = State(initialValue: initialJSON)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(8)
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Validate & Apply") {
                            if onSave(text) {
                                dismiss()
                            }
                        }
                    }
                }
        }
    }
}

private struct ProfileV3RuntimePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var editor: ProfileV3EditorModel

    @State private var surface: FfiProfileV3BoardSurface?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let surface {
                    if surface.entries.isEmpty {
                        ContentUnavailableView(
                            "Empty Board",
                            systemImage: "square.grid.3x3"
                        )
                    } else {
                        GeometryReader { proxy in
                            if let mapping = IOSProfileV3BoardGeometryMapping(
                                surface: surface,
                                width: Double(proxy.size.width),
                                height: Double(proxy.size.height)
                            ) {
                                ZStack {
                                    ForEach(surface.entries, id: \.id) { entry in
                                        let frame = mapping.frame(for: entry.rect)
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.primary.opacity(0.08))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(.secondary)
                                            )
                                            .overlay {
                                                Text(entry.text ?? entry.id)
                                                    .minimumScaleFactor(0.4)
                                                    .lineLimit(2)
                                                    .padding(3)
                                            }
                                            .frame(
                                                width: CGFloat(frame.width),
                                                height: CGFloat(frame.height)
                                            )
                                            .position(
                                                x: CGFloat(frame.midX),
                                                y: CGFloat(frame.midY)
                                            )
                                    }
                                }
                            } else {
                                ContentUnavailableView(
                                    "Board has no renderable bounds",
                                    systemImage: "rectangle.slash"
                                )
                            }
                        }
                        .padding()
                    }
                } else if let error {
                    ContentUnavailableView(
                        "Preview unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Shared Runtime Preview")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                load()
            }
        }
    }

    private func load() {
        do {
            let runtime = try editor.previewRuntime()
            surface = try runtime.directSurface()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

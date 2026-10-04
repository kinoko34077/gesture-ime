import SwiftUI
import GestureIMEProfileAuthoring

private typealias Catalog = ProfileV3DisplayCatalog

/// #73 / #69 §8: Board canvas stays visible (sticky) while the selected-key
/// inspector scrolls independently below it; regular width uses two panes.
struct ProfileV3OverviewEditorView: View {
    @StateObject private var editor: ProfileV3EditorModel
    @State private var sheet: ProfileV3EditorSheet?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
        Group {
            if horizontalSizeClass == .regular {
                HStack(spacing: 0) {
                    VStack(spacing: 8) {
                        contextBar
                        canvas
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    Divider()
                    inspectorScroll
                        .frame(width: 380)
                }
            } else {
                VStack(spacing: 6) {
                    contextBar
                        .padding(.horizontal)
                    canvas
                        .frame(height: 300)
                        .padding(.horizontal)
                    Divider()
                    inspectorScroll
                }
            }
        }
        .navigationTitle(editor.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(item: $sheet) { item in
            sheetContent(item)
        }
        .alert(
            Catalog.title(.statusInvalid),
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

    // MARK: Sticky upper region

    private var contextBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker(
                    Catalog.title(.conceptLayer),
                    selection: Binding(
                        get: { editor.selectedLayerID },
                        set: { editor.selectLayer($0) }
                    )
                ) {
                    ForEach(editor.layers) { layer in
                        Text(layerTitle(layer)).tag(layer.id)
                    }
                }
                .pickerStyle(.menu)

                Button {
                    editor.navigateBack()
                } label: {
                    Label(Catalog.text(.actionBack).shortLabel, systemImage: "chevron.left")
                }
                .disabled(editor.boardPath.count <= 1)
                .accessibilityHint(Catalog.help(.actionBack))

                Spacer()

                validationBadge
            }

            HStack(spacing: 8) {
                Text(boardPathTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Picker(Catalog.title(.modeSelect), selection: $editor.tool) {
                    ForEach(ProfileV3CanvasTool.allCases) { tool in
                        Text(Catalog.text(tool.displayKey).shortLabel).tag(tool)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }
        }
    }

    private var validationBadge: some View {
        Group {
            if editor.validation.valid {
                Label(Catalog.title(.statusValid), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label(Catalog.title(.statusInvalid), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
    }

    private var boardPathTitle: String {
        let depth = editor.boardPath.count
        if depth <= 1 {
            return Catalog.title(.conceptBoard) + "（最初の段階）"
        }
        return Catalog.title(.conceptBoard) + "（\(depth)段階目）"
    }

    private func layerTitle(_ layer: ProfileV3LayerSummary) -> String {
        let base = (layer.name?.isEmpty == false ? layer.name : nil) ?? Catalog.title(.conceptLayer)
        return layer.isInitial ? base + " ★" : base
    }

    private var canvas: some View {
        ProfileV3BoardCanvas(editor: editor)
            .id(editor.currentBoardID ?? "")
    }

    // MARK: Scrollable lower region

    private var inspectorScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let entry = editor.selectedEntry {
                    ProfileV3EntryInspector(
                        editor: editor,
                        entry: entry,
                        onOpenResolver: { sheet = .resolver }
                    )
                    .id(entry.id)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Catalog.title(.inspectorNoSelection))
                            .font(.headline)
                        Text(Catalog.help(.inspectorNoSelection))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }

                profileSection
                advancedProfileSection
            }
            .padding()
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                ProfileV3InputSettingsView(editor: editor)
            } label: {
                Label(Catalog.title(.sectionInputSettings), systemImage: "hand.draw")
            }
            .accessibilityHint(Catalog.help(.sectionInputSettings))

            Menu {
                ForEach(ProfileV3Preset.allCases) { preset in
                    Button(Catalog.title(preset.displayKey)) {
                        editor.createLayer(fromPreset: preset)
                    }
                }
            } label: {
                Label(Catalog.title(.presetSection), systemImage: "square.grid.3x3.square")
            }
            Text(Catalog.help(.presetSection))
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                Button(Catalog.title(.actionRename)) { sheet = .renameLayer }
                Button(Catalog.title(.conceptInitialLayer)) { editor.setSelectedLayerInitial() }
                Button(Catalog.title(.actionDuplicate)) { sheet = .duplicateLayer }
                Button("空のキーボード面を追加") { sheet = .createLayer }
                Divider()
                Button(Catalog.title(.actionDelete), role: .destructive) {
                    editor.deleteSelectedLayer()
                }
            } label: {
                Label(Catalog.title(.conceptLayer), systemImage: "square.3.layers.3d")
            }

            HStack {
                Button(Catalog.title(.actionRename)) { sheet = .renameProfile }
                Button(Catalog.title(.actionUseAsActive)) { editor.setActive() }
                if let url = editor.exportURL() {
                    ShareLink(item: url) {
                        Label(Catalog.title(.actionExport), systemImage: "square.and.arrow.up")
                    }
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var advancedProfileSection: some View {
        DisclosureGroup("▶︎ " + Catalog.title(.sectionAdvanced)) {
            VStack(alignment: .leading, spacing: 10) {
                if !editor.validation.valid {
                    Text(Catalog.validationMessage(code: editor.validation.errorCode))
                        .font(.caption)
                        .foregroundStyle(.red)
                    if let detail = editor.validation.detail {
                        Text(detail)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent(Catalog.title(.advancedInternalID)) {
                    Text(editor.profileID).font(.caption.monospaced())
                }
                if let boardID = editor.currentBoardID {
                    LabeledContent(Catalog.title(.conceptBoard)) {
                        Text(boardID).font(.caption.monospaced())
                    }
                }

                Menu {
                    Button("入力面を追加") { sheet = .createBoard }
                    Button("この入力面を複製") { sheet = .duplicateBoard }
                    Button("入力面を開く…") { sheet = .openBoard }
                    Divider()
                    Button("この入力面を削除", role: .destructive) {
                        editor.deleteCurrentBoard()
                    }
                } label: {
                    Label(Catalog.title(.conceptBoard), systemImage: "square.grid.3x3")
                }

                Text(Catalog.title(.advancedInboundReferences))
                    .font(.subheadline.bold())
                if editor.inboundReferences.isEmpty {
                    Text("なし")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(editor.inboundReferences) { reference in
                        Button {
                            editor.openInboundReference(reference)
                        } label: {
                            Text(reference.path)
                                .font(.caption2.monospaced())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(Catalog.title(.advancedProfileSemantics))
                    .font(.subheadline.bold())
                HStack {
                    semanticButton("状態", count: editor.states.count, sheet: .states)
                    semanticButton("変換表", count: editor.transformTables.count, sheet: .transformTables)
                    semanticButton("マクロ", count: editor.macros.count, sheet: .macros)
                }
            }
            .padding(.top, 6)
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                editor.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!editor.canUndo)
            .accessibilityLabel(Catalog.title(.actionUndo))

            Button {
                editor.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!editor.canRedo)
            .accessibilityLabel(Catalog.title(.actionRedo))

            Button {
                sheet = .preview
            } label: {
                Image(systemName: "play.rectangle")
            }
            .accessibilityLabel(Catalog.title(.actionPreview))

            Button(Catalog.title(.actionSave)) {
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
                title: Catalog.title(.actionRename),
                label: "名前",
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
                title: Catalog.title(.actionRename),
                label: "名前",
                initialValue: initial
            ) { value in
                editor.renameSelectedLayer(value)
                return true
            }

        case .createBoard:
            ProfileV3SingleTextSheet(
                title: "入力面を追加",
                label: Catalog.title(.advancedInternalID),
                initialValue: "board.new"
            ) { value in
                editor.createBoard(id: value)
                return true
            }

        case .duplicateBoard:
            ProfileV3SingleTextSheet(
                title: "この入力面を複製",
                label: Catalog.title(.advancedInternalID),
                initialValue: (editor.currentBoardID ?? "board") + ".copy"
            ) { value in
                editor.duplicateCurrentBoard(newBoardID: value)
                return true
            }

        case .openBoard:
            ProfileV3BoardPickerSheet(editor: editor)

        case .resolver:
            ProfileV3JSONEditorSheet(
                title: Catalog.title(.advancedConditions),
                initialJSON: editor.selectedResolverJSON() ?? "{}"
            ) { text in
                editor.setSelectedResolverJSON(text)
            }

        case .states:
            semanticEditor(.states, title: "状態")

        case .transformTables:
            semanticEditor(.transformTables, title: "変換表")

        case .macros:
            semanticEditor(.macros, title: "マクロ")

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

// MARK: - 入力設定 (one common GesturePolicy surface, #69 §9)

struct ProfileV3InputSettingsView: View {
    @ObservedObject var editor: ProfileV3EditorModel

    var body: some View {
        Form {
            if let values = editor.policyValues {
                Section {
                    ForEach(ProfileV3GesturePolicyField.allCases) { field in
                        ProfileV3PolicySlider(
                            field: field,
                            value: values.value(field)
                        ) { next in
                            var updated = values
                            updated.set(field, next)
                            if updated.isValid {
                                editor.updatePolicyValues(updated)
                            }
                        }
                    }
                } footer: {
                    Text("ここでの設定はすべてのキーに共通です。特定のキーだけ変える場合は、キーを選んで「詳細設定」から上書きします。")
                }
            }
        }
        .navigationTitle(Catalog.title(.sectionInputSettings))
    }
}

/// Slider whose value is committed on release so one drag is one undo step.
struct ProfileV3PolicySlider: View {
    let field: ProfileV3GesturePolicyField
    let value: Double
    let onCommit: (Double) -> Void

    @State private var draft: Double?

    var body: some View {
        let text = Catalog.text(field.displayKey)
        let shown = draft ?? value
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(text.title)
                Spacer()
                Text(formatted(shown) + (text.unit.map { " " + $0 } ?? ""))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { draft ?? value },
                    set: { draft = $0 }
                ),
                in: field.range,
                step: field.step
            ) { editing in
                if !editing, let draft {
                    onCommit(draft)
                    self.draft = nil
                }
            }
            .accessibilityLabel(text.title)
            Text(text.help)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func formatted(_ value: Double) -> String {
        field == .stageBacktrackDwellMs || field == .angularHysteresisDegrees
            ? String(Int(value.rounded()))
            : String(format: "%.2f", value)
    }
}

// MARK: - Canvas (single interaction owner, stable viewport, #69 §8.2–8.3)

private struct ProfileV3BoardCanvas: View {
    @ObservedObject var editor: ProfileV3EditorModel

    @State private var viewport: ProfileV3CanvasViewport?
    @State private var interaction: ProfileV3CanvasInteraction?
    @State private var candidate: ProfileV3Rect?
    @State private var liveViewport: ProfileV3CanvasViewport?
    @State private var pinchBase: ProfileV3CanvasViewport?

    private var items: [(id: String, rect: ProfileV3Rect)] {
        editor.entries.map { (id: $0.id, rect: $0.rect) }
    }

    var body: some View {
        GeometryReader { proxy in
            let current = liveViewport ?? viewport ?? fitted(proxy.size)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.background)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))

                ProfileV3AtomicGrid(viewport: current, size: proxy.size)

                ForEach(editor.entries) { entry in
                    entryView(entry, viewport: current)
                }

                if let candidate, interaction?.targetEntryID == nil {
                    let frame = current.frame(for: candidate)
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            editor.canCreateEntry(candidate) ? Color.accentColor : Color.red,
                            style: StrokeStyle(lineWidth: 2, dash: [5, 4])
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }

            }
            .contentShape(Rectangle())
            .gesture(dragGesture(size: proxy.size))
            .simultaneousGesture(pinchGesture(size: proxy.size))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            // Controls sit outside the canvas gesture owner.
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    canvasButton("minus.magnifyingglass", key: .actionZoomOut) {
                        zoom(by: 1 / 1.25, size: proxy.size)
                    }
                    canvasButton("plus.magnifyingglass", key: .actionZoomIn) {
                        zoom(by: 1.25, size: proxy.size)
                    }
                    Button(Catalog.title(.actionFitAll)) {
                        viewport = fitted(proxy.size)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .accessibilityHint(Catalog.help(.actionFitAll))
                }
                .padding(6)
            }
            .onAppear {
                // Auto-fit only when a Board is opened (#69 §8.3).
                if viewport == nil { viewport = fitted(proxy.size) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Catalog.title(.conceptBoard))
        }
    }

    private func fitted(_ size: CGSize) -> ProfileV3CanvasViewport {
        ProfileV3CanvasViewport.fitting(
            rects: editor.entries.map(\.rect),
            width: Double(size.width),
            height: Double(size.height)
        )
    }

    private func zoom(by scale: Double, size: CGSize) {
        var next = viewport ?? fitted(size)
        next.zoom(by: scale, anchorX: Double(size.width / 2), anchorY: Double(size.height / 2))
        viewport = next
    }

    private func canvasButton(
        _ systemImage: String,
        key: ProfileV3DisplayKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(Catalog.title(key))
    }

    @ViewBuilder
    private func entryView(
        _ entry: ProfileV3BoardEntrySummary,
        viewport: ProfileV3CanvasViewport
    ) -> some View {
        let selected = entry.id == editor.selectedEntryID
        let dragging = interaction?.targetEntryID == entry.id
        let rect = dragging ? (candidate ?? entry.rect) : entry.rect
        let valid = !dragging || rect == entry.rect || editor.canPlaceEntry(entry.id, rect: rect)
        let frame = viewport.frame(for: rect)

        ZStack {
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
                            lineWidth: selected ? 3 : 1
                        )
                )
            Text(entry.presentationText ?? "・")
                .lineLimit(2)
                .minimumScaleFactor(0.4)
                .padding(2)
            if entry.transition != nil {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(3)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(entry.accessibilityLabel ?? entry.presentationText ?? Catalog.title(.conceptEntry))
        .accessibilityAddTraits(selected ? .isSelected : [])

        if selected && !dragging {
            let handle = ProfileV3CanvasHitTester.resizeHandleFrame(for: entry.rect, viewport: viewport)
            Circle()
                .fill(Color.accentColor)
                .frame(width: 22, height: 22)
                .overlay(Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white))
                .position(x: handle.midX, y: handle.midY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let base = viewport ?? fitted(size)
                if interaction == nil {
                    let hit = ProfileV3CanvasHitTester.hit(
                        x: Double(value.startLocation.x),
                        y: Double(value.startLocation.y),
                        entries: items,
                        selectedEntryID: editor.selectedEntryID,
                        viewport: base
                    )
                    let started = ProfileV3CanvasInteraction.begin(
                        hit: hit,
                        tool: editor.tool,
                        entries: items,
                        viewport: base
                    )
                    interaction = started
                    if let target = started.targetEntryID {
                        editor.selectEntry(target)
                    }
                }
                guard let interaction else { return }
                if let panned = interaction.pannedViewport(
                    translationX: Double(value.translation.width),
                    translationY: Double(value.translation.height)
                ) {
                    liveViewport = panned
                    return
                }
                candidate = interaction.candidateRect(
                    translationX: Double(value.translation.width),
                    translationY: Double(value.translation.height),
                    currentX: Double(value.location.x),
                    currentY: Double(value.location.y),
                    viewport: base
                )
            }
            .onEnded { value in
                defer {
                    interaction = nil
                    candidate = nil
                }
                guard let interaction else { return }
                let moved = hypot(value.translation.width, value.translation.height) >= 4

                switch interaction.operation {
                case .pan:
                    if let liveViewport { viewport = liveViewport }
                    liveViewport = nil
                case .move(let id, let start), .resize(let id, let start):
                    if moved, let candidate, candidate != start,
                       editor.canPlaceEntry(id, rect: candidate) {
                        editor.setEntryRect(id, rect: candidate)
                    }
                case .create:
                    if let candidate, editor.canCreateEntry(candidate) {
                        editor.createEntry(rect: candidate)
                    }
                case .none:
                    if !moved { editor.selectEntry(nil) }
                }
            }
    }

    private func pinchGesture(size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = pinchBase ?? viewport ?? fitted(size)
                if pinchBase == nil { pinchBase = base }
                var next = base
                next.zoom(
                    by: Double(value.magnification),
                    anchorX: Double(value.startLocation.x),
                    anchorY: Double(value.startLocation.y)
                )
                liveViewport = next
            }
            .onEnded { _ in
                if let liveViewport { viewport = liveViewport }
                liveViewport = nil
                pinchBase = nil
                interaction = nil
                candidate = nil
            }
    }
}

private struct ProfileV3AtomicGrid: View {
    let viewport: ProfileV3CanvasViewport
    let size: CGSize

    var body: some View {
        Canvas { context, _ in
            let step = CGFloat(viewport.atomicSize) * 2
            guard step >= 6 else { return }
            var path = Path()
            let startX = CGFloat(viewport.originX).truncatingRemainder(dividingBy: step)
            let startY = CGFloat(viewport.originY).truncatingRemainder(dividingBy: step)
            var x = startX
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y = startY
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(path, with: .color(.secondary.opacity(0.18)), lineWidth: 0.5)

            var origin = Path()
            origin.move(to: CGPoint(x: CGFloat(viewport.originX), y: 0))
            origin.addLine(to: CGPoint(x: CGFloat(viewport.originX), y: size.height))
            origin.move(to: CGPoint(x: 0, y: CGFloat(viewport.originY)))
            origin.addLine(to: CGPoint(x: size.width, y: CGFloat(viewport.originY)))
            context.stroke(origin, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Inspector (easy view + ▶︎ 詳細設定, #69 §8.4–8.5)

private struct ProfileV3EntryInspector: View {
    @ObservedObject var editor: ProfileV3EditorModel
    let entry: ProfileV3BoardEntrySummary
    let onOpenResolver: () -> Void

    @State private var displayText = ""
    @State private var tapText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(entry.presentationText ?? Catalog.title(.conceptEntry))
                    .font(.title3.bold())
                Spacer()
                Button(role: .destructive, action: editor.deleteSelectedEntry) {
                    Label(Catalog.title(.actionDelete), systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }

            labeledField(.inspectorDisplayText, text: $displayText) {
                editor.setSelectedDisplayText(displayText)
            }

            if entry.caseCount > 0 || (editor.selectedTapText == nil && !isSimpleCandidate) {
                Text(Catalog.help(.inspectorComplexEntry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            labeledField(.inspectorTap, text: $tapText) {
                editor.setSelectedTapText(tapText)
            }

            directionSection
            nextStageSection
            holdSection
            geometrySection

            DisclosureGroup("▶︎ " + Catalog.title(.advancedSection)) {
                ProfileV3EntryAdvancedSection(
                    editor: editor,
                    entry: entry,
                    onOpenResolver: onOpenResolver
                )
                .padding(.top, 6)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onAppear(perform: syncDrafts)
        .onChange(of: entry) { _, _ in syncDrafts() }
        .onChange(of: editor.selectedTapText) { _, _ in syncDrafts() }
    }

    private var isSimpleCandidate: Bool {
        entry.onRelease.isEmpty && entry.transition == nil && entry.hold == nil
    }

    private func syncDrafts() {
        displayText = entry.presentationText ?? ""
        tapText = editor.selectedTapText ?? ""
    }

    private func labeledField(
        _ key: ProfileV3DisplayKey,
        text: Binding<String>,
        onSubmit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Catalog.title(key)).font(.subheadline.bold())
            TextField(Catalog.help(key), text: text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onSubmit)
                .submitLabel(.done)
        }
    }

    @ViewBuilder
    private var directionSection: some View {
        if editor.selectedNextStageBoardID != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text(Catalog.title(.inspectorDirections)).font(.subheadline.bold())
                Text(Catalog.help(.inspectorDirections))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProfileV3DirectionGrid(editor: editor)
            }
        }
    }

    @ViewBuilder
    private var nextStageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Catalog.title(.inspectorNextStage)).font(.subheadline.bold())
            if let target = entry.transition?.targetBoardID {
                Button {
                    editor.navigate(to: target)
                } label: {
                    Label("次の段階を編集", systemImage: "arrow.turn.down.right")
                }
            } else {
                Button {
                    editor.createNextStageForSelected()
                } label: {
                    Label("フリック先を追加", systemImage: "plus.circle")
                }
                Text(Catalog.help(.inspectorNextStage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var holdSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Catalog.title(.inspectorHold)).font(.subheadline.bold())
            if let hold = entry.hold {
                Text("\(hold.delayMs)ミリ秒 · " + hold.onStart.map { Catalog.actionTitle($0.actionID) }.joined(separator: "・"))
                    .font(.caption)
                if let target = hold.transition?.targetBoardID {
                    Button {
                        editor.navigate(to: target)
                    } label: {
                        Label("長押しの次の段階を編集", systemImage: "hand.tap")
                    }
                }
            } else {
                Text("なし（詳細設定で追加できます）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var geometrySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Catalog.title(.inspectorPosition) + "・" + Catalog.title(.inspectorSize))
                .font(.subheadline.bold())
            HStack {
                stepper("横", value: entry.rect.x) { delta in
                    var rect = entry.rect; rect.x += delta; editor.setSelectedEntryRect(rect)
                }
                stepper("縦", value: entry.rect.y) { delta in
                    var rect = entry.rect; rect.y += delta; editor.setSelectedEntryRect(rect)
                }
            }
            HStack {
                stepper("幅", value: entry.rect.width) { delta in
                    var rect = entry.rect; rect.width += delta; editor.setSelectedEntryRect(rect)
                }
                stepper("高さ", value: entry.rect.height) { delta in
                    var rect = entry.rect; rect.height += delta; editor.setSelectedEntryRect(rect)
                }
            }
            HStack {
                Button(Catalog.title(.actionDuplicate)) {
                    editor.duplicateSelectedEntry(rect: neighbourRect)
                }
                Button(Catalog.title(.actionCopy), action: editor.copySelectedEntry)
                Button(Catalog.title(.actionPaste)) {
                    editor.pasteCopiedEntry(rect: neighbourRect)
                }
                .disabled(!editor.hasCopiedEntry)
            }
            .buttonStyle(.bordered)
        }
    }

    private var neighbourRect: ProfileV3Rect {
        ProfileV3Rect(
            x: entry.rect.x + entry.rect.width,
            y: entry.rect.y,
            width: entry.rect.width,
            height: entry.rect.height
        )
    }

    private func stepper(
        _ title: String,
        value: Int,
        change: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Text("\(title) \(value)")
                .font(.caption.monospacedDigit())
                .frame(minWidth: 52, alignment: .leading)
            Button { change(-1) } label: {
                Image(systemName: "minus").frame(width: 28, height: 28)
            }
            .accessibilityLabel("\(title)を減らす")
            Button { change(1) } label: {
                Image(systemName: "plus").frame(width: 28, height: 28)
            }
            .accessibilityLabel("\(title)を増やす")
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProfileV3DirectionGrid: View {
    @ObservedObject var editor: ProfileV3EditorModel

    private let layout: [[ProfileV3Direction?]] = [
        [.northWest, .north, .northEast],
        [.west, nil, .east],
        [.southWest, .south, .southEast]
    ]

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        if let direction = layout[row][column] {
                            ProfileV3DirectionField(
                                direction: direction,
                                initial: text(for: direction)
                            ) { value in
                                editor.setDirectionText(direction, text: value)
                            }
                        } else {
                            Text(editor.selectedTapText ?? "")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                .accessibilityLabel(Catalog.title(.directionCenter))
                        }
                    }
                }
            }
        }
    }

    private func text(for direction: ProfileV3Direction) -> String {
        editor.selectedDirectionSlots.first { $0.direction == direction }?
            .entry?.presentationText ?? ""
    }
}

private struct ProfileV3DirectionField: View {
    let direction: ProfileV3Direction
    let initial: String
    let onCommit: (String) -> Void

    @State private var text = ""

    var body: some View {
        VStack(spacing: 2) {
            Text(Catalog.title(direction.displayKey))
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("", text: $text)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 44)
                .onSubmit { onCommit(text) }
                .accessibilityLabel(Catalog.title(direction.displayKey))
        }
        .onAppear { text = initial }
        .onChange(of: initial) { _, next in text = next }
    }
}

private struct ProfileV3EntryAdvancedSection: View {
    @ObservedObject var editor: ProfileV3EditorModel
    let entry: ProfileV3BoardEntrySummary
    let onOpenResolver: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent(Catalog.title(.advancedInternalID)) {
                Text(entry.id).font(.caption.monospaced())
            }

            if let transition = entry.transition {
                Picker(
                    Catalog.title(.advancedTransitionLifetime),
                    selection: Binding(
                        get: { transition.lifetime },
                        set: { editor.setSelectedTransitionLifetime($0) }
                    )
                ) {
                    Text(Catalog.title(.lifetimeTransient)).tag(ProfileV3TransitionLifetime.transient)
                    Text(Catalog.title(.lifetimePersistent)).tag(ProfileV3TransitionLifetime.persistent)
                }
                Text(Catalog.help(.advancedTransitionLifetime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            overrideSection

            Button(Catalog.title(.advancedConditions), action: onOpenResolver)
                .buttonStyle(.borderedProminent)
            Text(Catalog.help(.advancedConditions))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var overrideSection: some View {
        let enabled = editor.selectedOverride != nil
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                Catalog.title(.advancedPolicyOverride),
                isOn: Binding(
                    get: { enabled },
                    set: { on in
                        if on {
                            // Opt-in starts from the inherited dwell so the
                            // stored override is minimal and visibly partial.
                            let dwell = editor.policyValues?.stageBacktrackDwellMs
                                ?? ProfileV3GesturePolicyValues.defaultStageBacktrackDwellMs
                            editor.setSelectedOverride(
                                ProfileV3GesturePolicyOverride(stageBacktrackDwellMs: dwell)
                            )
                        } else {
                            editor.setSelectedOverride(nil)
                        }
                    }
                )
            )
            Text(Catalog.help(.advancedPolicyOverride))
                .font(.caption)
                .foregroundStyle(.secondary)

            if enabled, let common = editor.policyValues {
                ForEach(ProfileV3GesturePolicyField.allCases) { field in
                    overrideRow(field, common: common)
                }
            }
        }
    }

    @ViewBuilder
    private func overrideRow(
        _ field: ProfileV3GesturePolicyField,
        common: ProfileV3GesturePolicyValues
    ) -> some View {
        let current = editor.selectedOverride?.value(field)
        VStack(alignment: .leading, spacing: 4) {
            Toggle(
                Catalog.title(field.displayKey),
                isOn: Binding(
                    get: { current != nil },
                    set: { on in
                        var next = editor.selectedOverride ?? ProfileV3GesturePolicyOverride()
                        next.set(field, on ? common.value(field) : nil)
                        editor.setSelectedOverride(next)
                    }
                )
            )
            if current != nil {
                ProfileV3PolicySlider(field: field, value: current ?? common.value(field)) { value in
                    var next = editor.selectedOverride ?? ProfileV3GesturePolicyOverride()
                    next.set(field, value)
                    editor.setSelectedOverride(next)
                }
            } else {
                Text(Catalog.title(.advancedInherited) + "（\(inheritedText(field, common: common))）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func inheritedText(
        _ field: ProfileV3GesturePolicyField,
        common: ProfileV3GesturePolicyValues
    ) -> String {
        let value = common.value(field)
        let unit = Catalog.text(field.displayKey).unit.map { " " + $0 } ?? ""
        if field == .stageBacktrackDwellMs || field == .angularHysteresisDegrees {
            return String(Int(value.rounded())) + unit
        }
        return String(format: "%.2f", value) + unit
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
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
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
                TextField("内部ID", text: $layerID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("名前", text: $name)
                if duplicate {
                    TextField("新しい入力面の内部ID", text: $boardID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(duplicate ? "キーボード面を複製" : "キーボード面を追加")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(duplicate ? "複製" : "追加") {
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
                            Text("キー \(board.entryCount)個")
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
            .navigationTitle("入力面を開く")
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
                        Button("キャンセル") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("検証して適用") {
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
                            "空の入力面",
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
                                    "表示できるキーがありません",
                                    systemImage: "rectangle.slash"
                                )
                            }
                        }
                        .padding()
                    }
                } else if let error {
                    ContentUnavailableView(
                        "プレビューできません",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(ProfileV3DisplayCatalog.title(.actionPreview))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            .task {
                load()
            }
        }
    }

    private func load() {
        do {
            surface = try editor.previewSurface()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

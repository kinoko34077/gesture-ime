//
// Product keyboard surface adapted from azooKey's MIT-licensed SwiftUI keyboard
// architecture (FlickKeyboardView / FlickKeyView / KeyboardBar concepts).
// Copyright (c) 2020-2023 Keita Miwa (ensan).
// See THIRD_PARTY_NOTICES.md.
//
// Gesture recognition is intentionally NOT ported from azooKey: all gesture
// semantics come from GestureIMECoreShared through IOSSharedGestureRuntimeAdapter.
//

import Foundation
import SwiftUI
import AzooKeyUtils
import KeyboardViews

enum ProductUtilityPanel: String, Identifiable {
    case tuning
    case phrase
    case emoji
    case emoticon

    var id: String { rawValue }
}

@MainActor
final class ProductGestureCoordinator {
    struct Token: Equatable {
        let touchID: UUID
        let generation: UInt64
    }

    private var activeTouches: Set<UUID> = []
    private var generation: UInt64 = 0
    private var blockedByMultitouch = false

    var onBecameIdle: (() -> Void)?

    var hasActiveTouches: Bool {
        !activeTouches.isEmpty
    }

    func begin(touchID: UUID) -> Token? {
        guard !activeTouches.contains(touchID) else { return nil }

        activeTouches.insert(touchID)
        if blockedByMultitouch || activeTouches.count > 1 {
            if !blockedByMultitouch {
                generation &+= 1
            }
            blockedByMultitouch = true
            return nil
        }

        return Token(touchID: touchID, generation: generation)
    }

    func isValid(_ token: Token) -> Bool {
        !blockedByMultitouch
            && token.generation == generation
            && activeTouches.count == 1
            && activeTouches.contains(token.touchID)
    }

    func end(touchID: UUID) {
        activeTouches.remove(touchID)
        if activeTouches.isEmpty {
            blockedByMultitouch = false
            onBecameIdle?()
        }
    }
}

@MainActor
final class ProductKeyboardViewModel: ObservableObject {
    @Published private(set) var layout: KeyboardLayoutRuntime
    @Published private(set) var candidates: [CompositionCandidateSnapshot] = []
    @Published var panel: ProductUtilityPanel?

    let policyStore: GesturePolicyStore
    let composition: AzooKeyCompositionBridge
    let gestureCoordinator = ProductGestureCoordinator()

    private let sharedRuntime: IOSSharedGestureRuntimeAdapter
    private(set) var layerStack: [String]
    private let onNextKeyboard: () -> Void
    private let onDismissKeyboard: () -> Void

    init(
        initialLayout: KeyboardLayoutRuntime,
        policyStore: GesturePolicyStore,
        composition: AzooKeyCompositionBridge,
        onNextKeyboard: @escaping () -> Void,
        onDismissKeyboard: @escaping () -> Void
    ) {
        self.layout = initialLayout
        self.policyStore = policyStore
        self.composition = composition
        self.sharedRuntime = initialLayout.sharedRuntime
        self.layerStack = [initialLayout.layerID]
        self.onNextKeyboard = onNextKeyboard
        self.onDismissKeyboard = onDismissKeyboard

        composition.onCandidatesChanged = { [weak self] snapshots in
            self?.candidates = snapshots
        }
    }

    func dispatch(_ actions: [FfiActionInvocation]) {
        for action in actions {
            dispatch(action)
        }
    }

    func selectCandidate(_ index: Int) {
        composition.selectCandidate(at: index)
    }

    func openTuning() {
        panel = .tuning
    }

    func nextKeyboard() {
        composition.commitSelectionOrRaw()
        onNextKeyboard()
    }

    func insertUtilityText(_ text: String) {
        composition.directInsert(text)
        panel = nil
    }

    func refreshLayoutFromRuntime() {
        guard let layerID = layerStack.last else { return }
        do {
            layout = try KeyboardLayoutRuntime.compile(
                sharedRuntime: sharedRuntime,
                layerID: layerID
            )
        } catch {
            return
        }
    }

    private func dispatch(_ action: FfiActionInvocation) {
        let arguments = Self.decodeArguments(action.argumentsJson)

        switch action.actionId {
        case "text.insert":
            if let text = arguments["text"] as? String {
                composition.insert(text)
            }

        case "text.directInsert":
            if let text = arguments["text"] as? String {
                composition.directInsert(text)
            }

        case "edit.delete":
            if let count = Self.intArgument(arguments["count"]), count != 0 {
                if count > 0 {
                    composition.deleteBackward(count: count)
                } else {
                    composition.deleteForward(count: -count)
                }
            }

        case "cursor.move":
            if let offset = Self.intArgument(arguments["offset"]) {
                composition.moveCursor(offset)
            }

        case "layer.set":
            if let layer = arguments["layer"] as? String {
                setLayer(layer)
            }

        case "layer.push":
            if let layer = arguments["layer"] as? String {
                pushLayer(layer)
            }

        case "layer.pop":
            popLayer()

        case "conversion.commit":
            composition.commitSelectionOrRaw()

        case "conversion.selectCandidate":
            if let index = Self.intArgument(arguments["index"]) {
                composition.selectCandidate(at: index)
            }

        case "system.nextKeyboard":
            nextKeyboard()

        case "system.dismissKeyboard":
            composition.commitSelectionOrRaw()
            onDismissKeyboard()

        case "panel.open":
            guard let panelID = arguments["panel"] as? String else { return }
            switch panelID {
            case "tuning": panel = .tuning
            case "phrase": panel = .phrase
            case "emoji": panel = .emoji
            case "emoticon": panel = .emoticon
            default: break
            }

        default:
            break
        }
    }

    private func setLayer(_ layerID: String) {
        do {
            let next = try KeyboardLayoutRuntime.compile(
                sharedRuntime: sharedRuntime,
                layerID: layerID
            )
            layerStack = [layerID]
            layout = next
            panel = nil
        } catch {
            return
        }
    }

    private func pushLayer(_ layerID: String) {
        guard layerStack.count < 16 else { return }
        do {
            let next = try KeyboardLayoutRuntime.compile(
                sharedRuntime: sharedRuntime,
                layerID: layerID
            )
            layerStack.append(layerID)
            layout = next
            panel = nil
        } catch {
            return
        }
    }

    private func popLayer() {
        guard layerStack.count > 1 else { return }
        let previous = layerStack[layerStack.count - 2]
        do {
            let next = try KeyboardLayoutRuntime.compile(
                sharedRuntime: sharedRuntime,
                layerID: previous
            )
            layerStack.removeLast()
            layout = next
            panel = nil
        } catch {
            return
        }
    }

    private static func decodeArguments(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    private static func intArgument(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}

@MainActor
struct AzooKeyProductKeyboardRoot: View {
    @ObservedObject var model: ProductKeyboardViewModel

    private let theme: AzooKeyTheme = .base

    var body: some View {
        ZStack {
            theme.backgroundColor.color
                .ignoresSafeArea()

            VStack(spacing: 4) {
                productBar
                    .frame(height: 44)

                ProductFlickGrid(
                    layout: model.layout,
                    policyStore: model.policyStore,
                    gestureCoordinator: model.gestureCoordinator,
                    theme: theme,
                    onActions: model.dispatch,
                    onSemanticStateChanged: model.refreshLayoutFromRuntime
                )
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)

            if let panel = model.panel {
                ProductUtilityPanelView(
                    panel: panel,
                    store: model.policyStore,
                    theme: theme,
                    onInsert: model.insertUtilityText,
                    onClose: { model.panel = nil }
                )
            }
        }
    }

    private var productBar: some View {
        HStack(spacing: 6) {
            Button(action: model.openTuning) {
                Image(systemName: "gearshape")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    if model.candidates.isEmpty {
                        Text(" ")
                            .frame(minWidth: 24)
                    } else {
                        ForEach(model.candidates, id: \.index) { candidate in
                            Button(candidate.text) {
                                model.selectCandidate(candidate.index)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                candidate.selected
                                    ? theme.pushedKeyFillColor.color
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                        }
                    }
                }
            }

            Button(action: model.nextKeyboard) {
                Image(systemName: "globe")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(theme.resultTextColor.color)
        .background(theme.resultBackgroundColor.color)
    }
}

@MainActor
private struct ProductFlickGrid: View {
    let layout: KeyboardLayoutRuntime
    let policyStore: GesturePolicyStore
    let gestureCoordinator: ProductGestureCoordinator
    let theme: AzooKeyTheme
    let onActions: ([FfiActionInvocation]) -> Void
    let onSemanticStateChanged: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let columnCount = max(1, layout.columnCount)
            let rowCount = max(1, layout.rowCount)
            let horizontalSpacing: CGFloat = max(3, geometry.size.width / 100)
            let verticalSpacing: CGFloat = max(4, geometry.size.width / 70)
            let unitWidth = max(
                0,
                (geometry.size.width - CGFloat(columnCount - 1) * horizontalSpacing)
                    / CGFloat(columnCount)
            )
            let unitHeight = max(
                0,
                (geometry.size.height - CGFloat(rowCount - 1) * verticalSpacing)
                    / CGFloat(rowCount)
            )

            ZStack(alignment: .topLeading) {
                ForEach(layout.keys) { key in
                    SharedGestureFlickKey(
                        runtime: key,
                        sharedRuntime: layout.sharedRuntime,
                        profileRevision: layout.profileRevision,
                        policyStore: policyStore,
                        gestureCoordinator: gestureCoordinator,
                        theme: theme,
                        onActions: onActions,
                        onSemanticStateChanged: onSemanticStateChanged
                    )
                    .frame(
                        width: CGFloat(key.width) * unitWidth
                            + CGFloat(max(0, key.width - 1)) * horizontalSpacing,
                        height: CGFloat(key.height) * unitHeight
                            + CGFloat(max(0, key.height - 1)) * verticalSpacing
                    )
                    .offset(
                        x: CGFloat(key.column) * (unitWidth + horizontalSpacing),
                        y: CGFloat(key.row) * (unitHeight + verticalSpacing)
                    )
                }
            }
        }
    }
}

@MainActor
private struct SharedGestureFlickKey: View {
    let runtime: KeyboardKeyRuntime
    let sharedRuntime: IOSSharedGestureRuntimeAdapter
    let profileRevision: String
    let policyStore: GesturePolicyStore
    let gestureCoordinator: ProductGestureCoordinator
    let theme: AzooKeyTheme
    let onActions: ([FfiActionInvocation]) -> Void
    let onSemanticStateChanged: () -> Void

    @State private var session: IOSSharedGestureSessionAdapter?
    @State private var semanticClockTask: Task<Void, Never>?
    @State private var startedAt: TimeInterval?
    @State private var dispatchedActionCount = 0
    @State private var pressed = false
    @State private var registeredTouch = false
    @State private var gestureToken: ProductGestureCoordinator.Token?
    @State private var nativeTouchID = UUID()

    private var fill: Color {
        if pressed {
            return theme.pushedKeyFillColor.color
        }
        return runtime.role == "control"
            ? theme.specialKeyFillColor.color
            : theme.normalKeyFillColor.color
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(theme.borderColor.color, lineWidth: CGFloat(theme.borderWidth))
                    )
                    .shadow(color: .black.opacity(0.12), radius: 0.5, x: 0, y: 0.75)

                Text(runtime.title)
                    .font(.system(size: runtime.role == "control" ? 17 : 25))
                    .foregroundStyle(theme.textColor.color)
                    .minimumScaleFactor(0.55)

                directionHints
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        updateGesture(
                            value: value,
                            size: geometry.size
                        )
                    }
                    .onEnded { value in
                        endGesture(
                            value: value,
                            size: geometry.size
                        )
                    }
            )
            .accessibilityLabel(runtime.title)
            .onDisappear {
                finishNativeTouch()
            }
        }
    }

    @ViewBuilder
    private var directionHints: some View {
        let hint = runtime.firstStagePresentation

        Group {
            hintText(hint["nw"]).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            hintText(hint["n"]).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            hintText(hint["ne"]).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            hintText(hint["w"]).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            hintText(hint["e"]).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            hintText(hint["sw"]).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            hintText(hint["s"]).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            hintText(hint["se"]).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .padding(4)
        .allowsHitTesting(false)
    }

    private func hintText(_ text: String?) -> some View {
        Text(text ?? "")
            .font(.system(size: 10))
            .foregroundStyle(theme.textColor.color.opacity(0.55))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    private func updateGesture(value: DragGesture.Value, size: CGSize) {
        if !registeredTouch {
            registeredTouch = true
            gestureToken = gestureCoordinator.begin(touchID: nativeTouchID)
        }

        guard let gestureToken else {
            cancelSemanticSession()
            return
        }

        guard gestureCoordinator.isValid(gestureToken) else {
            cancelSemanticSession()
            return
        }

        if session == nil {
            startedAt = ProcessInfo.processInfo.systemUptime
            do {
                session = try sharedRuntime.beginSession(
                    layerID: runtime.layerID,
                    keyID: runtime.id,
                    keyWidth: Double(size.width),
                    keyHeight: Double(size.height),
                    touchX: Double(value.startLocation.x),
                    touchY: Double(value.startLocation.y),
                    atMs: 0,
                    policyOverride: policyStore.policy
                )
                dispatchedActionCount = 0
                pressed = true
                startSemanticClock()
            } catch {
                cancelSemanticSession()
                return
            }
        }

        guard let session else { return }
        do {
            let result = try session.move(
                x: Double(value.location.x),
                y: Double(value.location.y),
                atMs: elapsedMs()
            )
            consumeNewActions(from: result)
        } catch {
            cancelSemanticSession()
        }
    }

    private func endGesture(value: DragGesture.Value, size: CGSize) {
        defer { finishNativeTouch() }

        guard let gestureToken,
              gestureCoordinator.isValid(gestureToken),
              let session else {
            cancelSemanticSession()
            return
        }

        let atMs = elapsedMs()
        do {
            let moved = try session.move(
                x: Double(value.location.x),
                y: Double(value.location.y),
                atMs: atMs
            )
            consumeNewActions(from: moved)
            let result = try session.touchUp(atMs: atMs)
            consumeNewActions(from: result)
            onSemanticStateChanged()
        } catch {
            _ = try? session.cancel(atMs: atMs)
        }
        resetSemanticSession()
    }

    private func elapsedMs() -> Int64 {
        guard let startedAt else { return 0 }
        return max(
            0,
            Int64((ProcessInfo.processInfo.systemUptime - startedAt) * 1000)
        )
    }

    private func startSemanticClock() {
        semanticClockTask?.cancel()
        semanticClockTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled, let session else { return }
                do {
                    let result = try session.advanceTime(toMs: elapsedMs())
                    consumeNewActions(from: result)
                } catch {
                    cancelSemanticSession()
                    return
                }
            }
        }
    }

    private func consumeNewActions(from snapshot: FfiSessionSnapshot) {
        let actions = snapshot.dispatchedActions
        if actions.count < dispatchedActionCount {
            dispatchedActionCount = 0
        }
        guard actions.count > dispatchedActionCount else { return }

        let newActions = Array(actions.dropFirst(dispatchedActionCount))
        dispatchedActionCount = actions.count
        onActions(newActions)
    }

    private func cancelSemanticSession() {
        if let session {
            _ = try? session.cancel(atMs: elapsedMs())
        }
        resetSemanticSession()
    }

    private func resetSemanticSession() {
        semanticClockTask?.cancel()
        semanticClockTask = nil
        session = nil
        startedAt = nil
        dispatchedActionCount = 0
        pressed = false
    }

    private func finishNativeTouch() {
        if registeredTouch {
            gestureCoordinator.end(touchID: nativeTouchID)
        }
        registeredTouch = false
        gestureToken = nil
        resetSemanticSession()
    }
}

@MainActor
private struct ProductUtilityPanelView: View {
    let panel: ProductUtilityPanel
    let store: GesturePolicyStore
    let theme: AzooKeyTheme
    let onInsert: (String) -> Void
    let onClose: () -> Void

    @State private var deadZone: Double
    @State private var stage1: Double
    @State private var stage2: Double
    @State private var hysteresis: Double

    init(
        panel: ProductUtilityPanel,
        store: GesturePolicyStore,
        theme: AzooKeyTheme,
        onInsert: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.panel = panel
        self.store = store
        self.theme = theme
        self.onInsert = onInsert
        self.onClose = onClose
        _deadZone = State(initialValue: store.deadZone)
        _stage1 = State(initialValue: store.stage1)
        _stage2 = State(initialValue: store.stage2)
        _hysteresis = State(initialValue: store.hysteresis)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("閉じる", action: onClose)
            }

            switch panel {
            case .tuning:
                tuningContent
            case .phrase:
                utilityButtons(["ありがとう", "よろしくお願いします", "了解", "お疲れさま"])
            case .emoji:
                utilityButtons(["😀", "😂", "🥺", "👍", "🙏", "❤️", "✨", "🎉"])
            case .emoticon:
                utilityButtons(["(・ω・)", "(｀・ω・´)", "＼(^o^)／", "( ˘ω˘ )", "m(_ _)m"])
            }
        }
        .padding(12)
        .foregroundStyle(theme.textColor.color)
        .background(theme.backgroundColor.color)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.borderColor.color, lineWidth: CGFloat(max(0.5, theme.borderWidth)))
        )
        .padding(8)
    }

    private var title: String {
        switch panel {
        case .tuning: "Gesture tuning"
        case .phrase: "定型文"
        case .emoji: "絵文字"
        case .emoticon: "顔文字"
        }
    }

    private var tuningContent: some View {
        VStack {
            tuningSlider("Dead zone", value: $deadZone, range: 0.02...0.60) {
                store.setDeadZone($0)
            }
            tuningSlider("Stage 1", value: $stage1, range: 0.10...1.50) {
                store.setStage1($0)
            }
            tuningSlider("Stage 2", value: $stage2, range: 0.10...1.80) {
                store.setStage2($0)
            }
            tuningSlider("Hysteresis", value: $hysteresis, range: 0...30) {
                store.setHysteresis($0)
            }

            Button("初期値へ戻す") {
                store.resetToProfileDefaults()
                deadZone = store.deadZone
                stage1 = store.stage1
                stage2 = store.stage2
                hysteresis = store.hysteresis
            }
        }
    }

    private func tuningSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        apply: @escaping (Double) -> Void
    ) -> some View {
        VStack(spacing: 1) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
                .onChange(of: value.wrappedValue) { _, newValue in
                    apply(newValue)
                }
        }
    }

    private func utilityButtons(_ values: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74))], spacing: 8) {
            ForEach(values, id: \.self) { value in
                Button(value) {
                    onInsert(value)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(
                    theme.normalKeyFillColor.color,
                    in: RoundedRectangle(cornerRadius: 7)
                )
            }
        }
    }
}

import Foundation
import SwiftUI
import AzooKeyUtils
import GestureIMEProductSettings
import KeyboardViews

@MainActor
final class ProfileV3ProductKeyboardViewModel: ObservableObject {
    @Published private(set) var surface: FfiProfileV3BoardSurface
    @Published private(set) var interactionSnapshot: FfiProfileV3SessionSnapshot?
    @Published private(set) var candidates: [CompositionCandidateSnapshot] = []
    @Published var panel: ProductUtilityPanel?

    let runtime: IOSProfileV3RuntimeAdapter
    let composition: AzooKeyCompositionBridge
    let gestureCoordinator = ProductGestureCoordinator()
    let defaultPolicy: FfiProfileV3GesturePolicy
    let productSettings: ProductSettingsValues

    private let hapticFeedback: ProductHapticFeedback
    private let onNextKeyboard: () -> Void
    private let onDismissKeyboard: () -> Void

    init(
        runtime: IOSProfileV3RuntimeAdapter,
        composition: AzooKeyCompositionBridge,
        productSettings: ProductSettingsValues,
        onNextKeyboard: @escaping () -> Void,
        onDismissKeyboard: @escaping () -> Void
    ) throws {
        self.runtime = runtime
        self.composition = composition
        self.defaultPolicy = runtime.defaultPolicy()
        self.productSettings = productSettings
        self.hapticFeedback = ProductHapticFeedback(settings: productSettings)
        self.onNextKeyboard = onNextKeyboard
        self.onDismissKeyboard = onDismissKeyboard

        try runtime.updateSemanticContext(
            composition: composition.semanticComposition,
            conversionActive: composition.semanticConversionActive,
            conversionHasCandidates: composition.semanticConversionHasCandidates
        )
        self.surface = try runtime.directSurface()

        composition.onCandidatesChanged = { [weak self] snapshots in
            guard let self else { return }
            self.candidates = snapshots
            self.syncSemanticContext()
            if self.interactionSnapshot == nil {
                self.refreshDirectSurface()
            }
        }
    }

    func syncSemanticContext() {
        try? runtime.updateSemanticContext(
            composition: composition.semanticComposition,
            conversionActive: composition.semanticConversionActive,
            conversionHasCandidates: composition.semanticConversionHasCandidates
        )
    }

    func refreshDirectSurface() {
        syncSemanticContext()
        if let next = try? runtime.directSurface() {
            surface = next
        }
    }

    func beginInteraction(_ snapshot: FfiProfileV3SessionSnapshot) {
        interactionSnapshot = snapshot
    }

    func updateInteraction(_ snapshot: FfiProfileV3SessionSnapshot) {
        interactionSnapshot = snapshot
    }

    func endInteraction() {
        interactionSnapshot = nil
        refreshDirectSurface()
    }

    func dispatchNewRuntimeEffects(
        from snapshot: FfiProfileV3SessionSnapshot,
        consumedCount: inout Int
    ) {
        let all = snapshot.runtimeDispatches
        if all.count < consumedCount {
            consumedCount = 0
        }
        guard all.count > consumedCount else { return }

        let suffix = all.dropFirst(consumedCount)
        consumedCount = all.count

        for dispatch in suffix {
            apply(dispatch)
        }

        // Product composition/candidate facts may have changed, but one already
        // resolved Rust dispatch batch is never re-resolved here.
        syncSemanticContext()
    }

    func selectCandidate(_ index: Int) {
        composition.selectCandidate(at: index)
        syncSemanticContext()
        if interactionSnapshot == nil {
            refreshDirectSurface()
        }
    }

    func nextKeyboard() {
        composition.commitSelectionOrRaw()
        syncSemanticContext()
        onNextKeyboard()
    }

    func emitSelectionHaptic() {
        hapticFeedback.emitCommittedSelection()
    }

    func insertUtilityText(_ text: String) {
        composition.directInsert(text)
        panel = nil
        refreshDirectSurface()
    }

    func closePanel() {
        panel = nil
    }

    private func apply(_ dispatch: FfiProfileV3RuntimeDispatch) {
        if let actionID = dispatch.actionId,
           let argumentsJSON = dispatch.argumentsJson {
            applyAction(actionID: actionID, argumentsJSON: argumentsJSON)
            return
        }

        guard let matchedSource = dispatch.matchedSource,
              let replacement = dispatch.replacement else {
            return
        }

        _ = composition.replaceCompositionTail(
            matchedSource: matchedSource,
            replacement: replacement
        )
    }

    private func applyAction(actionID: String, argumentsJSON: String) {
        let arguments = Self.decodeArguments(argumentsJSON)

        switch actionID {
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
            guard let layerID = arguments["layer"] as? String,
                  let next = try? runtime.setLayer(layerID) else {
                return
            }
            surface = next

        case "layer.push":
            guard let layerID = arguments["layer"] as? String,
                  let next = try? runtime.pushLayer(layerID) else {
                return
            }
            surface = next

        case "layer.pop":
            if let next = try? runtime.popLayer() {
                surface = next
            }

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
            syncSemanticContext()
            onDismissKeyboard()

        case "panel.open":
            guard let panelID = arguments["panel"] as? String,
                  let panel = ProductUtilityPanel(rawValue: panelID) else {
                return
            }
            // A5 moves phrase/emoji/emoticon product content to authored Layers.
            // This compatibility surface exists only so the retained generic
            // panel.open Action is not silently reinterpreted as NoOp in A3.
            self.panel = panel

        default:
            // state.set is consumed in Rust A2 and profile.switch is rejected at
            // activation. Unknown platform Actions fail closed.
            break
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
struct ProfileV3ProductKeyboardRoot: View {
    @ObservedObject var model: ProfileV3ProductKeyboardViewModel

    private let theme: AzooKeyTheme = .base
    private let boardCoordinateSpace = "GestureIME.ProfileV3Board"

    var body: some View {
        VStack(spacing: 4) {
            productBar
                .frame(height: 44)

            GeometryReader { geometry in
                if let mapping = ProfileV3DirectBoardMapping(
                    surface: model.surface,
                    size: geometry.size
                ) {
                    ZStack(alignment: .topLeading) {
                        directBoard(mapping: mapping)

                        if let snapshot = model.interactionSnapshot,
                           snapshot.context == .relative {
                            relativeOverlay(
                                snapshot: snapshot,
                                mapping: mapping
                            )
                            .allowsHitTesting(false)
                        }
                    }
                    .coordinateSpace(name: boardCoordinateSpace)
                }
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .foregroundStyle(theme.textColor.color)
        .background(theme.backgroundColor.color)
        .overlay {
            if let panel = model.panel {
                ProfileV3PanelCompatibilityView(
                    panel: panel,
                    policy: model.defaultPolicy,
                    theme: theme,
                    onInsert: model.insertUtilityText,
                    onClose: model.closePanel
                )
            }
        }
    }

    private var productBar: some View {
        HStack(spacing: 6) {
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

    @ViewBuilder
    private func directBoard(mapping: ProfileV3DirectBoardMapping) -> some View {
        ForEach(model.surface.entries, id: \.id) { entry in
            let frame = mapping.frame(for: entry.rect)

            ProfileV3DirectEntryView(
                entry: entry,
                runtime: model.runtime,
                model: model,
                logicalCellSize: mapping.logicalCellSize,
                coordinateSpaceName: boardCoordinateSpace,
                theme: theme
            )
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
        }
    }

    @ViewBuilder
    private func relativeOverlay(
        snapshot: FfiProfileV3SessionSnapshot,
        mapping: ProfileV3DirectBoardMapping
    ) -> some View {
        let candidateID = snapshot.candidateEntryId

        ForEach(snapshot.surface.entries, id: \.id) { entry in
            let frame = mapping.relativeFrame(
                for: entry.rect,
                anchor: CGPoint(
                    x: snapshot.anchor.x,
                    y: snapshot.anchor.y
                )
            )
            let isCandidate = entry.id == candidateID
            let isEndpoint = entry.id == snapshot.currentEndpointEntryId

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isCandidate
                            ? theme.pushedKeyFillColor.color.opacity(0.95)
                            : theme.normalKeyFillColor.color.opacity(
                                isEndpoint ? 0.88 : 0.72
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                theme.borderColor.color.opacity(0.9),
                                lineWidth: isCandidate ? 2 : 1
                            )
                    )

                Text(entry.text ?? "")
                    .font(.system(size: 16, weight: isCandidate ? .bold : .regular))
                    .foregroundStyle(theme.textColor.color)
                    .minimumScaleFactor(0.45)
                    .lineLimit(2)
                    .padding(2)
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .accessibilityLabel(entry.accessibilityLabel ?? entry.text ?? entry.id)
        }
    }
}

private struct ProfileV3DirectBoardMapping {
    private let shared: IOSProfileV3BoardGeometryMapping

    init?(surface: FfiProfileV3BoardSurface, size: CGSize) {
        guard let shared = IOSProfileV3BoardGeometryMapping(
            surface: surface,
            width: Double(size.width),
            height: Double(size.height)
        ) else {
            return nil
        }
        self.shared = shared
    }

    var logicalCellSize: CGSize {
        CGSize(
            width: CGFloat(shared.logicalCellWidth),
            height: CGFloat(shared.logicalCellHeight)
        )
    }

    func frame(for rect: FfiProfileV3Rect) -> CGRect {
        let mapped = shared.frame(for: rect)
        return CGRect(
            x: CGFloat(mapped.x),
            y: CGFloat(mapped.y),
            width: CGFloat(mapped.width),
            height: CGFloat(mapped.height)
        )
    }

    func relativeFrame(
        for rect: FfiProfileV3Rect,
        anchor: CGPoint
    ) -> CGRect {
        let mapped = shared.relativeFrame(
            for: rect,
            anchorX: Double(anchor.x),
            anchorY: Double(anchor.y)
        )
        return CGRect(
            x: CGFloat(mapped.x),
            y: CGFloat(mapped.y),
            width: CGFloat(mapped.width),
            height: CGFloat(mapped.height)
        )
    }
}

@MainActor
private struct ProfileV3DirectEntryView: View {
    let entry: FfiProfileV3SurfaceEntry
    let runtime: IOSProfileV3RuntimeAdapter
    @ObservedObject var model: ProfileV3ProductKeyboardViewModel
    let logicalCellSize: CGSize
    let coordinateSpaceName: String
    let theme: AzooKeyTheme

    @State private var session: IOSProfileV3SessionAdapter?
    @State private var semanticClockTask: Task<Void, Never>?
    @State private var startedAt: TimeInterval?
    @State private var consumedDispatchCount = 0
    @State private var pressed = false
    @State private var registeredTouch = false
    @State private var gestureToken: ProductGestureCoordinator.Token?
    @State private var nativeTouchID = UUID()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    pressed
                        ? theme.pushedKeyFillColor.color
                        : theme.normalKeyFillColor.color
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            theme.borderColor.color,
                            lineWidth: CGFloat(theme.borderWidth)
                        )
                )
                .shadow(
                    color: .black.opacity(0.12),
                    radius: 0.5,
                    x: 0,
                    y: 0.75
                )

            Text(entry.text ?? "")
                .font(.system(size: 23))
                .foregroundStyle(theme.textColor.color)
                .minimumScaleFactor(0.45)
                .lineLimit(2)
                .padding(2)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(
                minimumDistance: 0,
                coordinateSpace: .named(coordinateSpaceName)
            )
            .onChanged(updateGesture)
            .onEnded(endGesture)
        )
        .accessibilityLabel(entry.accessibilityLabel ?? entry.text ?? entry.id)
        .onDisappear {
            cancelSemanticSession()
            finishNativeTouch()
        }
    }

    private func updateGesture(_ value: DragGesture.Value) {
        if !registeredTouch {
            registeredTouch = true
            gestureToken = model.gestureCoordinator.begin(touchID: nativeTouchID)
        }

        guard let gestureToken else {
            cancelSemanticSession()
            return
        }

        guard model.gestureCoordinator.isValid(gestureToken) else {
            cancelSemanticSession()
            return
        }

        if session == nil {
            startedAt = ProcessInfo.processInfo.systemUptime
            model.syncSemanticContext()

            do {
                let created = try runtime.beginSession(
                    entryID: entry.id,
                    logicalCellWidth: Double(logicalCellSize.width),
                    logicalCellHeight: Double(logicalCellSize.height),
                    touchX: Double(value.startLocation.x),
                    touchY: Double(value.startLocation.y),
                    atMs: 0
                )
                session = created
                consumedDispatchCount = 0
                pressed = true

                let initial = try created.snapshot()
                model.emitSelectionHaptic()
                model.beginInteraction(initial)
                model.dispatchNewRuntimeEffects(
                    from: initial,
                    consumedCount: &consumedDispatchCount
                )
                startSemanticClock()
            } catch {
                cancelSemanticSession()
                return
            }
        }

        guard let session else { return }

        do {
            let previous = model.interactionSnapshot
            let result = try session.move(
                x: Double(value.location.x),
                y: Double(value.location.y),
                atMs: elapsedMs()
            )
            emitSpatialCommitHapticIfNeeded(from: previous, to: result)
            model.updateInteraction(result)
            model.dispatchNewRuntimeEffects(
                from: result,
                consumedCount: &consumedDispatchCount
            )
        } catch {
            cancelSemanticSession()
        }
    }

    private func endGesture(_ value: DragGesture.Value) {
        defer { finishNativeTouch() }

        guard let gestureToken,
              model.gestureCoordinator.isValid(gestureToken),
              let session else {
            cancelSemanticSession()
            return
        }

        let atMs = elapsedMs()

        do {
            let previous = model.interactionSnapshot
            let moved = try session.move(
                x: Double(value.location.x),
                y: Double(value.location.y),
                atMs: atMs
            )
            emitSpatialCommitHapticIfNeeded(from: previous, to: moved)
            model.updateInteraction(moved)
            model.dispatchNewRuntimeEffects(
                from: moved,
                consumedCount: &consumedDispatchCount
            )

            let result = try session.touchUp(atMs: atMs)
            model.updateInteraction(result)
            model.dispatchNewRuntimeEffects(
                from: result,
                consumedCount: &consumedDispatchCount
            )
        } catch {
            _ = try? session.cancel(atMs: atMs)
        }

        resetSemanticSession()
        model.endInteraction()
    }

    private func emitSpatialCommitHapticIfNeeded(
        from previous: FfiProfileV3SessionSnapshot?,
        to next: FfiProfileV3SessionSnapshot
    ) {
        guard let previous else { return }

        let committedIdentityChanged =
            previous.currentBoardId != next.currentBoardId
            || previous.currentEndpointEntryId != next.currentEndpointEntryId

        if committedIdentityChanged {
            model.emitSelectionHaptic()
        }
    }

    private func elapsedMs() -> Int64 {
        guard let startedAt else { return 0 }
        return max(
            0,
            Int64(
                (ProcessInfo.processInfo.systemUptime - startedAt) * 1000
            )
        )
    }

    private func startSemanticClock() {
        semanticClockTask?.cancel()
        semanticClockTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled, let session else { return }
                guard let gestureToken,
                      model.gestureCoordinator.isValid(gestureToken) else {
                    cancelSemanticSession()
                    return
                }

                do {
                    let result = try session.advanceTime(toMs: elapsedMs())
                    model.updateInteraction(result)
                    model.dispatchNewRuntimeEffects(
                        from: result,
                        consumedCount: &consumedDispatchCount
                    )
                } catch {
                    cancelSemanticSession()
                    return
                }
            }
        }
    }

    private func cancelSemanticSession() {
        if let session {
            if let cancelled = try? session.cancel(atMs: elapsedMs()) {
                model.updateInteraction(cancelled)
                model.dispatchNewRuntimeEffects(
                    from: cancelled,
                    consumedCount: &consumedDispatchCount
                )
            }
        }
        resetSemanticSession()
        model.endInteraction()
    }

    private func resetSemanticSession() {
        semanticClockTask?.cancel()
        semanticClockTask = nil
        session = nil
        startedAt = nil
        consumedDispatchCount = 0
        pressed = false
    }

    private func finishNativeTouch() {
        if registeredTouch {
            model.gestureCoordinator.end(touchID: nativeTouchID)
        }
        registeredTouch = false
        gestureToken = nil
        resetSemanticSession()

        // A Layer control-plane Action can remove this direct key while a Hold
        // session is still live. onDisappear must clear the shared overlay state
        // as well as the local session so a stale relative surface cannot remain.
        if model.interactionSnapshot != nil {
            model.endInteraction()
        }
    }
}

@MainActor
private struct ProfileV3PanelCompatibilityView: View {
    let panel: ProductUtilityPanel
    let policy: FfiProfileV3GesturePolicy
    let theme: AzooKeyTheme
    let onInsert: (String) -> Void
    let onClose: () -> Void

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
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profile gesture policy")
                    Text(String(format: "Dead zone %.2f", policy.deadZone))
                    Text(String(
                        format: "Initial %.2f / Subsequent %.2f",
                        policy.initialCellCommitDistance,
                        policy.subsequentCellCommitDistance
                    ))
                    Text(String(
                        format: "Hysteresis %.2f°",
                        policy.angularHysteresisDegrees
                    ))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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
                .stroke(
                    theme.borderColor.color,
                    lineWidth: CGFloat(max(0.5, theme.borderWidth))
                )
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

    private func utilityButtons(_ values: [String]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 74))],
            spacing: 8
        ) {
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

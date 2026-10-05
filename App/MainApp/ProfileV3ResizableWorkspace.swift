import SwiftUI
import UIKit
import GestureIMEProfileAuthoring

/// #100 / frozen #95 §F5: one shared workspace primitive for the Board editor
/// and the Design editor. Layout comes only from actual usable geometry; the
/// divider changes presentation state only (never Profile/Board/settings).
struct ProfileV3ResizableWorkspace<Primary: View, Secondary: View>: View {
    /// Distinguishes persisted split ratios ("board", "design").
    let storageKey: String
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let secondary: () -> Secondary

    @SceneStorage("workspace.ratio.vertical") private var verticalStore = ""
    @SceneStorage("workspace.ratio.horizontal") private var horizontalStore = ""
    @State private var dragStartPrimary: Double?
    @State private var liveRatio: Double?

    @State private var keyboardOverlap: CGFloat = 0

    var body: some View {
        // The reader ignores the software keyboard so showing it never flips
        // the axis (§F5.1 rule 3); the measured keyboard overlap reduces only
        // the available extent so the primary pane shrinks first (rule 6).
        GeometryReader { layout in
            let available = CGSize(
                width: layout.size.width,
                height: max(0, layout.size.height - keyboardOverlap)
            )
            let axis = ProfileV3WorkspaceLayout.axis(
                layoutWidth: Double(layout.size.width),
                layoutHeight: Double(layout.size.height)
            )
            let split = ProfileV3WorkspaceLayout.resolve(
                layoutWidth: Double(layout.size.width),
                layoutHeight: Double(layout.size.height),
                availableWidth: Double(available.width),
                availableHeight: Double(available.height),
                storedRatio: liveRatio ?? storedRatio(for: axis)
            )
            VStack(spacing: 0) {
                content(split: split, size: available)
                Spacer(minLength: 0)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            ) { note in
                guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                let containerBottom = layout.frame(in: .global).maxY
                keyboardOverlap = max(0, containerBottom - frame.minY)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            ) { _ in
                keyboardOverlap = 0
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    @ViewBuilder
    private func content(split: ProfileV3WorkspaceSplit, size: CGSize) -> some View {
        if split.axis == .vertical {
            VStack(spacing: 0) {
                primary()
                    .frame(width: size.width, height: CGFloat(split.primary))
                    .clipped()
                divider(split: split, size: size)
                secondary()
                    .frame(width: size.width, height: CGFloat(split.secondary))
            }
        } else {
            HStack(spacing: 0) {
                primary()
                    .frame(width: CGFloat(split.primary), height: size.height)
                    .clipped()
                divider(split: split, size: size)
                secondary()
                    .frame(width: CGFloat(split.secondary), height: size.height)
            }
        }
    }

    private func divider(split: ProfileV3WorkspaceSplit, size: CGSize) -> some View {
        let vertical = split.axis == .vertical
        let total = split.primary + split.secondary
        return ZStack {
            Rectangle().fill(Color(.separator)).frame(
                width: vertical ? nil : 1,
                height: vertical ? 1 : nil
            )
            Capsule()
                .fill(Color.secondary.opacity(0.6))
                .frame(width: vertical ? 36 : 5, height: vertical ? 5 : 36)
        }
        .frame(
            width: vertical ? size.width : 12,
            height: vertical ? 12 : size.height
        )
        // ≥44 pt hit target without consuming layout space.
        .contentShape(Rectangle().inset(by: -16))
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let start = dragStartPrimary ?? split.primary
                    if dragStartPrimary == nil { dragStartPrimary = start }
                    let delta = Double(vertical ? value.translation.height : value.translation.width)
                    guard total > 0 else { return }
                    liveRatio = min(max((start + delta) / total, 0.01), 0.99)
                }
                .onEnded { _ in
                    if let liveRatio { store(liveRatio, axis: split.axis) }
                    liveRatio = nil
                    dragStartPrimary = nil
                }
        )
        .accessibilityElement()
        .accessibilityLabel("表示領域の大きさ")
        .accessibilityValue("\(Int((split.ratio * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.05 : -0.05
            store(min(max(split.ratio + step, 0.01), 0.99), axis: split.axis)
        }
    }

    // Per-workspace ratios are packed into one SceneStorage string per axis
    // ("board=0.40;design=0.55") — editor UI state only.
    private func storedRatio(for axis: ProfileV3WorkspaceAxis) -> Double? {
        let raw = axis == .vertical ? verticalStore : horizontalStore
        for part in raw.split(separator: ";") {
            let pair = part.split(separator: "=")
            if pair.count == 2, pair[0] == storageKey { return Double(pair[1]) }
        }
        return nil
    }

    private func store(_ ratio: Double, axis: ProfileV3WorkspaceAxis) {
        let raw = axis == .vertical ? verticalStore : horizontalStore
        var parts = raw.split(separator: ";").map(String.init).filter { !$0.hasPrefix(storageKey + "=") }
        parts.append("\(storageKey)=\(String(format: "%.3f", ratio))")
        if axis == .vertical { verticalStore = parts.joined(separator: ";") } else { horizontalStore = parts.joined(separator: ";") }
    }
}

/// #95 §F2 compact geometry control: one ≥44 pt adjustable target per value.
/// Upper half increments, lower half decrements; VoiceOver uses adjustable actions.
struct ProfileV3CompactAdjuster: View {
    let title: String
    let value: Int
    let onChange: (Int) -> Void

    private let touchExtent: CGFloat = 44

    var body: some View {
        HStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(value)").font(.callout.monospacedDigit()).frame(minWidth: 22, alignment: .trailing)
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 30, height: touchExtent)
                VStack(spacing: 0) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 30, height: touchExtent / 2)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 30, height: touchExtent / 2)
                }
            }
            .frame(width: touchExtent, height: touchExtent)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        onChange(value.location.y < touchExtent / 2 ? 1 : -1)
                    }
            )
            .accessibilityHidden(true)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: touchExtent, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            onChange(direction == .increment ? 1 : -1)
        }
    }
}

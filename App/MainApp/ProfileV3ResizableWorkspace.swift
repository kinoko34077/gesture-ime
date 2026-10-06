import SwiftUI
import UIKit
import GestureIMEProfileAuthoring


struct ProfileV3PriorityWorkspace<Primary: View, Secondary: View>: View {
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let secondary: () -> Secondary

    @SceneStorage("workspace.board.priority")
    private var storedPriorityRaw = ProfileV3WorkspacePriority.canvas.rawValue
    @State private var keyboardOverlap: CGFloat = 0

    private var userPriority: ProfileV3WorkspacePriority {
        ProfileV3WorkspacePriority(rawValue: storedPriorityRaw) ?? .canvas
    }

    private var effectivePriority: ProfileV3WorkspacePriority {
        keyboardOverlap > 0 ? .inspector : userPriority
    }

    var body: some View {
        GeometryReader { layout in
            let available = CGSize(
                width: layout.size.width,
                height: max(0, layout.size.height - keyboardOverlap)
            )
            let split = ProfileV3PriorityWorkspaceLayout.resolve(
                availableWidth: Double(available.width),
                availableHeight: Double(available.height),
                priority: effectivePriority
            )

            workspace(split: split, size: available)
                .frame(
                    width: available.width,
                    height: available.height,
                    alignment: .topLeading
                )
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIResponder.keyboardWillChangeFrameNotification
                    )
                ) { note in
                    guard let frame =
                            note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                    else { return }
                    let containerBottom = layout.frame(in: .global).maxY
                    keyboardOverlap = max(0, containerBottom - frame.minY)
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIResponder.keyboardWillHideNotification
                    )
                ) { _ in
                    keyboardOverlap = 0
                }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    @ViewBuilder
    private func workspace(
        split: ProfileV3PriorityWorkspaceSplit,
        size: CGSize
    ) -> some View {
        switch split.mode {
        case .sideBySide:
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    primary()
                        .frame(
                            width: CGFloat(split.canvas),
                            height: size.height
                        )
                        .clipped()

                    secondary()
                        .frame(
                            width: CGFloat(split.inspector),
                            height: size.height
                        )
                }

                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 1, height: size.height)
                    .offset(x: CGFloat(split.canvas))
                    .accessibilityHidden(true)
            }

        case .stacked:
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    primary()
                        .frame(
                            width: size.width,
                            height: CGFloat(split.canvas)
                        )
                        .clipped()

                    secondary()
                        .frame(
                            width: size.width,
                            height: CGFloat(split.inspector)
                        )
                }

                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: size.width, height: 1)
                    .offset(y: CGFloat(split.canvas))
                    .accessibilityHidden(true)

                priorityToggle(size: size, boundaryY: CGFloat(split.canvas))
            }
        }
    }

    private func priorityToggle(size: CGSize, boundaryY: CGFloat) -> some View {
        let next: ProfileV3WorkspacePriority =
            userPriority == .canvas ? .inspector : .canvas
        let label =
            next == .inspector ? "インスペクタを広げる" : "キャンバスを広げる"
        let icon =
            next == .inspector ? "chevron.up" : "chevron.down"
        let x = max(22, size.width - 26)
        let y = min(
            max(22, boundaryY),
            max(22, size.height - 22)
        )

        return Button {
            storedPriorityRaw = next.rawValue
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 32, height: 28)
                .background(
                    .thinMaterial,
                    in: Capsule()
                )
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .position(x: x, y: y)
        .accessibilityLabel(label)
        .accessibilityValue(
            userPriority == .canvas ? "キャンバス優先" : "インスペクタ優先"
        )
    }
}

/// Legacy free-split workspace retained for Design until U7 removes its
/// divider. U2 no longer uses this primitive for the Board/Edit workspace.
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
        // #95 §F5.1: axis selection and split resolution both consume the
        // actual usable geometry after software-keyboard occlusion, so the
        // axis may change when the remaining W/H crosses the frozen threshold.
        GeometryReader { layout in
            let available = CGSize(
                width: layout.size.width,
                height: max(0, layout.size.height - keyboardOverlap)
            )
            let axis = ProfileV3WorkspaceLayout.axis(
                layoutWidth: Double(available.width),
                layoutHeight: Double(available.height)
            )
            let split = ProfileV3WorkspaceLayout.resolve(
                layoutWidth: Double(available.width),
                layoutHeight: Double(available.height),
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
                SpatialTapGesture()
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

import SwiftUI
import GestureIMEProfileAuthoring

/// Shared hierarchy presentation only. Semantic ownership stays with each
/// concrete editor; this view draws the P13 rail/connector grammar and reserves
/// the corresponding indentation.
struct ProfileV3HierarchyRow<Content: View>: View {
    let depth: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        let safeDepth = max(0, depth)
        let indentation = CGFloat(
            ProfileV3StructuredAuthoringLayout.indentation(depth: safeDepth)
        )

        HStack(spacing: 0) {
            if safeDepth > 0 {
                Color.clear
                    .frame(width: indentation)
                    .accessibilityHidden(true)
            }

            content()
        }
        .frame(
            minHeight: CGFloat(
                ProfileV3StructuredAuthoringLayout.minimumTouchExtent
            )
        )
        .overlay(alignment: .leading) {
            if safeDepth > 0 {
                GeometryReader { proxy in
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<safeDepth, id: \.self) { level in
                            Rectangle()
                                .fill(Color.secondary.opacity(0.28))
                                .frame(
                                    width: CGFloat(
                                        ProfileV3StructuredAuthoringLayout.railWidth
                                    ),
                                    height: proxy.size.height
                                )
                                .offset(
                                    x: CGFloat(level)
                                        * CGFloat(ProfileV3StructuredAuthoringLayout.depthStep)
                                        + CGFloat(ProfileV3StructuredAuthoringLayout.depthStep / 2)
                                )
                        }

                        Rectangle()
                            .fill(Color.secondary.opacity(0.28))
                            .frame(
                                width: CGFloat(
                                    ProfileV3StructuredAuthoringLayout.connectorLength
                                ),
                                height: CGFloat(
                                    ProfileV3StructuredAuthoringLayout.railWidth
                                )
                            )
                            .offset(
                                x: CGFloat(safeDepth - 1)
                                    * CGFloat(ProfileV3StructuredAuthoringLayout.depthStep)
                                    + CGFloat(ProfileV3StructuredAuthoringLayout.depthStep / 2),
                                y: proxy.size.height / 2
                            )
                    }
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                }
            }
        }
    }
}

/// Shared accessible alternative for reorderable collections.
///
/// The concrete editor retains semantic move validation and drag/drop behavior;
/// this helper only standardizes the expected Move Up / Move Down menu items.
@ViewBuilder
func profileV3MoveMenuItems(
    canMoveUp: Bool,
    canMoveDown: Bool,
    onMoveUp: @escaping () -> Void,
    onMoveDown: @escaping () -> Void
) -> some View {
    Button("上へ", action: onMoveUp)
        .disabled(!canMoveUp)

    Button("下へ", action: onMoveDown)
        .disabled(!canMoveDown)
}


struct ProfileV3InlineAuthoringError: View {
    let message: String
    let correctionHint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.primary)

            Text(correctionHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .accessibilityElement(children: .combine)
    }
}

import SwiftUI
import UIKit

// #91 / #95 §F9: the one keyboard renderer compiled into both the keyboard
// extension and the Main App Design preview. Views draw only from
// `IOSKeyboardPresentation`; Board geometry and semantic text come from the
// shared runtime surface and are never altered here.

extension IOSKeyboardPresentation {
    public func swiftUIColor(_ role: IOSKeyboardColorRole) -> Color {
        switch color(role) {
        case .token(let value):
            return Color(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
        case .system(let role):
            return Color(uiColor: Self.productDefault(role))
        }
    }

    public var keyFont: Font {
        .system(size: CGFloat(keyFontSize), weight: Self.weight(keyFontWeight))
    }

    public var guideFont: Font {
        .system(size: CGFloat(guideFontSize))
    }

    static func weight(_ name: String) -> Font.Weight {
        switch name {
        case "light": .light
        case "medium": .medium
        case "semibold": .semibold
        case "bold": .bold
        default: .regular
        }
    }

    /// Product defaults (system-keyboard-like, light/dark adaptive).
    static func productDefault(_ role: IOSKeyboardColorRole) -> UIColor {
        func dynamic(_ light: UInt32, _ dark: UInt32) -> UIColor {
            UIColor { traits in
                let value = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(
                    red: CGFloat((value >> 16) & 0xFF) / 255,
                    green: CGFloat((value >> 8) & 0xFF) / 255,
                    blue: CGFloat(value & 0xFF) / 255,
                    alpha: 1
                )
            }
        }
        switch role {
        case .keyboardBackground: return dynamic(0xD1D3D9, 0x2B2B2D)
        case .keyFill: return dynamic(0xFFFFFF, 0x6B6B6D)
        case .keyPressedFill, .candidateSelection: return dynamic(0xAEB3BE, 0x47474A)
        case .border: return UIColor.separator
        case .text, .guideText, .candidateText: return UIColor.label
        case .candidateBackground: return dynamic(0xD1D3D9, 0x2B2B2D)
        case .overlayFill: return dynamic(0xF4F5F7, 0x58585B)
        }
    }
}

/// A direct-Board key: fill, border, label and immediate flick guides.
public struct IOSKeyboardKeyCap: View {
    let text: String
    let guides: [FfiProfileV3GuideLabel]
    let pressed: Bool
    let presentation: IOSKeyboardPresentation

    public init(
        text: String,
        guides: [FfiProfileV3GuideLabel],
        pressed: Bool,
        presentation: IOSKeyboardPresentation
    ) {
        self.text = text
        self.guides = guides
        self.pressed = pressed
        self.presentation = presentation
    }

    public var body: some View {
        let radius = CGFloat(presentation.cornerRadius)
        ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(presentation.swiftUIColor(pressed ? .keyPressedFill : .keyFill))
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .stroke(presentation.swiftUIColor(.border), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 0.5, x: 0, y: 0.75)

            Text(text)
                .font(presentation.keyFont)
                .foregroundStyle(
                    presentation.swiftUIColor(.text)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .allowsTightening(true)
                .truncationMode(.tail)
                .padding(2)

            // #69 §6.4: guide positions come from target entry geometry.
            if !guides.isEmpty {
                GeometryReader { proxy in
                    let reach = max(abs(guides.map(\.centerX).max() ?? 1), 1)
                    ForEach(guides, id: \.targetEntryId) { guide in
                        Text(guide.label)
                            .font(presentation.guideFont)
                            .foregroundStyle(presentation.swiftUIColor(.guideText))
                            .opacity(presentation.guideOpacity)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .position(
                                x: proxy.size.width / 2
                                    + CGFloat(guide.centerX / reach) * proxy.size.width * 0.36,
                                y: proxy.size.height / 2
                                    + CGFloat(guide.centerY / reach) * proxy.size.height * 0.36
                            )
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(text)
    }
}

/// One cell of the active relative-Board overlay.
public struct IOSKeyboardOverlayCell: View {
    let text: String
    let isCandidate: Bool
    let isEndpoint: Bool
    let presentation: IOSKeyboardPresentation

    public init(text: String, isCandidate: Bool, isEndpoint: Bool, presentation: IOSKeyboardPresentation) {
        self.text = text
        self.isCandidate = isCandidate
        self.isEndpoint = isEndpoint
        self.presentation = presentation
    }

    public var body: some View {
        let radius = CGFloat(presentation.cornerRadius + 2)
        ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(
                    isCandidate
                        ? presentation.swiftUIColor(.keyPressedFill).opacity(0.95)
                        : presentation.swiftUIColor(.overlayFill).opacity(isEndpoint ? 0.95 : 0.85)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .stroke(presentation.swiftUIColor(.border).opacity(0.9), lineWidth: isCandidate ? 2 : 1)
                )
            Text(text)
                .font(
                    .system(
                        size: 16,
                        weight:
                            isCandidate
                            ? .bold
                            : IOSKeyboardPresentation
                                .weight(
                                    presentation
                                        .keyFontWeight
                                )
                    )
                )
                .foregroundStyle(
                    presentation.swiftUIColor(.text)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .allowsTightening(true)
                .truncationMode(.tail)
                .padding(2)
        }
        .accessibilityLabel(text)
    }
}

/// A conversion candidate in the compact bar or the expanded grid.
public struct IOSKeyboardCandidateChip: View {
    let text: String
    let selected: Bool
    let expanded: Bool
    let presentation: IOSKeyboardPresentation
    let action: () -> Void

    public init(
        text: String,
        selected: Bool,
        expanded: Bool,
        presentation: IOSKeyboardPresentation,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.selected = selected
        self.expanded = expanded
        self.presentation = presentation
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(
                            .system(
                                size: 10,
                                weight: .bold
                            )
                        )
                        .accessibilityHidden(true)
                }

                Text(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.60)
                    .allowsTightening(true)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 8)
            .frame(
                maxWidth:
                    expanded
                    ? .infinity
                    : 160,
                minHeight: 44,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            presentation.swiftUIColor(.candidateText)
        )
        .fontWeight(selected ? .semibold : .regular)
        .overlay(alignment: .bottom) {
            if expanded {
                Rectangle()
                    .fill(
                        presentation
                            .swiftUIColor(.border)
                            .opacity(0.32)
                    )
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(text)
        .accessibilityValue(
            selected ? "選択中" : ""
        )
        .accessibilityAddTraits(
            selected ? .isSelected : []
        )
    }
}

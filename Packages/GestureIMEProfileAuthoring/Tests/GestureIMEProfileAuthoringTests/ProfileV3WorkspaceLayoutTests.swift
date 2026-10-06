import Foundation
import Testing
@testable import GestureIMEProfileAuthoring

// #100 — §F5.1 invariants across representative usable sizes.

private let widths: [Double] = [320, 375, 390, 430, 568, 667, 844, 932, 1024]
private let heights: [Double] = [320, 375, 390, 430, 568, 667, 844, 932, 1024]

@Test
func axisFollowsAspectAndShortHeightOnly() {
    #expect(ProfileV3WorkspaceLayout.axis(layoutWidth: 390, layoutHeight: 760) == .vertical)
    #expect(ProfileV3WorkspaceLayout.axis(layoutWidth: 844, layoutHeight: 360) == .horizontal)
    #expect(ProfileV3WorkspaceLayout.axis(layoutWidth: 500, layoutHeight: 500) == .horizontal, "short height")
    #expect(ProfileV3WorkspaceLayout.axis(layoutWidth: 1024, layoutHeight: 1300) == .vertical)
}

@Test
func panesAlwaysFitAndRespectMinimumsOrSecondaryWins() {
    let t = ProfileV3WorkspaceLayout.Tuning()
    for w in widths {
        for h in heights {
            for stored in [nil, 0.05, 0.5, 0.95] as [Double?] {
                let s = ProfileV3WorkspaceLayout.resolve(
                    layoutWidth: w, layoutHeight: h, availableWidth: w, availableHeight: h, storedRatio: stored
                )
                let extent = s.axis == .vertical ? h : w
                #expect(abs(s.primary + s.secondary + t.dividerThickness - extent) < 0.001 || extent < t.dividerThickness)
                #expect(s.primary >= 0 && s.secondary >= 0)
                let (pMin, sMin) = s.axis == .vertical
                    ? (t.verticalPrimaryMin, t.verticalSecondaryMin)
                    : (t.horizontalPrimaryMin, t.horizontalSecondaryMin)
                let total = extent - t.dividerThickness
                if total >= pMin + sMin {
                    #expect(s.primary >= pMin - 0.001 && s.secondary >= sMin - 0.001)
                } else {
                    #expect(s.secondary >= min(sMin, total) - 0.001, "secondary wins at \(w)x\(h)")
                }
            }
        }
    }
}

@Test
func portraitDefaultUsesClampedFraction() {
    let s = ProfileV3WorkspaceLayout.resolve(
        layoutWidth: 390, layoutHeight: 760, availableWidth: 390, availableHeight: 760, storedRatio: nil
    )
    #expect(s.axis == .vertical)
    #expect(abs(s.primary - 0.36 * 748) < 0.001)
    let tall = ProfileV3WorkspaceLayout.resolve(
        layoutWidth: 1024, layoutHeight: 1300, availableWidth: 1024, availableHeight: 1300, storedRatio: nil
    )
    #expect(tall.primary == 280)
}

@Test
func softwareKeyboardOcclusionCanFlipAxisFromUsableGeometry() {
    let open = ProfileV3WorkspaceLayout.resolve(
        layoutWidth: 390, layoutHeight: 760, availableWidth: 390, availableHeight: 760, storedRatio: 0.4
    )
    let keyboard = ProfileV3WorkspaceLayout.resolve(
        layoutWidth: 390, layoutHeight: 430, availableWidth: 390, availableHeight: 430, storedRatio: 0.4
    )
    #expect(open.axis == .vertical)
    #expect(keyboard.axis == .horizontal)
    let tuning = ProfileV3WorkspaceLayout.Tuning()
    #expect(abs(keyboard.primary + keyboard.secondary + tuning.dividerThickness - 390) < 0.001)
}

@Test
func storedRatioRoundTripsAndIsClamped() {
    let s = ProfileV3WorkspaceLayout.resolve(
        layoutWidth: 390, layoutHeight: 760, availableWidth: 390, availableHeight: 760, storedRatio: 0.5
    )
    #expect(abs(s.ratio - 0.5) < 0.001)
    let clamped = ProfileV3WorkspaceLayout.resolve(
        layoutWidth: 390, layoutHeight: 760, availableWidth: 390, availableHeight: 760, storedRatio: 0.99
    )
    #expect(clamped.secondary >= 200 - 0.001)
}


@Test
func priorityWorkspaceUsesExactlyTwoStackedPhoneStates() {
    let canvas = ProfileV3PriorityWorkspaceLayout.resolve(
        availableWidth: 390,
        availableHeight: 760,
        priority: .canvas
    )
    #expect(canvas.mode == .stacked)
    #expect(canvas.priority == .canvas)
    #expect(abs(canvas.inspector - min(max(0.34 * 760, 176), 240)) < 0.001)
    #expect(abs(canvas.canvas + canvas.inspector - 760) < 0.001)

    let inspector = ProfileV3PriorityWorkspaceLayout.resolve(
        availableWidth: 390,
        availableHeight: 760,
        priority: .inspector
    )
    #expect(inspector.mode == .stacked)
    #expect(inspector.priority == .inspector)
    #expect(abs(inspector.canvas - min(max(0.28 * 760, 144), 220)) < 0.001)
    #expect(abs(inspector.canvas + inspector.inspector - 760) < 0.001)

    #expect(canvas != inspector)
}

@Test
func priorityWorkspaceWideModeRequiresBothWorkingWidths() {
    let narrow = ProfileV3PriorityWorkspaceLayout.resolve(
        availableWidth: 640,
        availableHeight: 430,
        priority: .canvas
    )
    #expect(narrow.mode == .stacked)

    let wide = ProfileV3PriorityWorkspaceLayout.resolve(
        availableWidth: 700,
        availableHeight: 430,
        priority: .inspector
    )
    #expect(wide.mode == .sideBySide)
    #expect(wide.canvas >= 360)
    #expect(wide.inspector >= 280)
    #expect(abs(wide.canvas + wide.inspector - 700) < 0.001)
}

@Test
func priorityWorkspaceWideInspectorUsesBoundedP13Width() {
    let medium = ProfileV3PriorityWorkspaceLayout.resolve(
        availableWidth: 900,
        availableHeight: 430,
        priority: .canvas
    )
    #expect(medium.mode == .sideBySide)
    #expect(abs(medium.inspector - 306) < 0.001)

    let veryWide = ProfileV3PriorityWorkspaceLayout.resolve(
        availableWidth: 1400,
        availableHeight: 900,
        priority: .inspector
    )
    #expect(veryWide.inspector == 360)
    #expect(veryWide.canvas == 1040)
}

@Test
func priorityWorkspaceHasNoRatioInputOrRatioPersistenceContract() {
    let canvas = ProfileV3PriorityWorkspaceLayout.resolve(
        availableWidth: 390,
        availableHeight: 760,
        priority: .canvas
    )
    let inspector = ProfileV3PriorityWorkspaceLayout.resolve(
        availableWidth: 390,
        availableHeight: 760,
        priority: .inspector
    )

    #expect(canvas.priority == .canvas)
    #expect(inspector.priority == .inspector)
    #expect(canvas.canvas > inspector.canvas)
    #expect(canvas.inspector < inspector.inspector)
}

@Test
func longPressNeedsDurationAndStillness() {
    #expect(ProfileV3LongPress.isLongPress(elapsed: 0.5, movement: 3))
    #expect(!ProfileV3LongPress.isLongPress(elapsed: 0.3, movement: 0))
    #expect(!ProfileV3LongPress.isLongPress(elapsed: 1.0, movement: 15))
    #expect(ProfileV3LongPress.pasteRect(copied: ProfileV3Rect(x: 9, y: 9, width: 2, height: 3), atX: -1, y: 0)
        == ProfileV3Rect(x: -1, y: 0, width: 2, height: 3))
}

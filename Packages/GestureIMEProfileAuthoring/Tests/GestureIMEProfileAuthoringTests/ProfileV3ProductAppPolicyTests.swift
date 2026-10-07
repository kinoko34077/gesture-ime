import Testing
@testable import GestureIMEProfileAuthoring

@Test
func productEditPhoneLayoutKeepsCanvasAndInspectorUsable() {
    let regular = ProfileV3ProductEditLayoutPolicy.resolve(
        width: 390,
        height: 760
    )
    #expect(regular.mode == .stacked)
    #expect(regular.canvasExtent == 280)
    #expect(regular.inspectorExtent == 480)

    let short = ProfileV3ProductEditLayoutPolicy.resolve(
        width: 390,
        height: 430
    )
    #expect(short.mode == .stacked)
    #expect(short.canvasExtent >= 112)
    #expect(short.canvasExtent <= 160)
    #expect(short.canvasExtent + short.inspectorExtent == 430)
}

@Test
func productEditWideLayoutUsesBoundedInspectorWidth() {
    let wide = ProfileV3ProductEditLayoutPolicy.resolve(
        width: 900,
        height: 600
    )
    #expect(wide.mode == .sideBySide)
    #expect(wide.inspectorExtent >= 300)
    #expect(wide.inspectorExtent <= 360)
    #expect(wide.canvasExtent + wide.inspectorExtent == 900)
}

@Test
func editNavigationFrameRestoresSourceIdentity() {
    var state = ProfileV3EditNavigationState()
    state.push(
        sourceBoardID: "board.root",
        sourceEntryID: "key.a",
        destinationBoardID: "board.a.flick"
    )
    state.push(
        sourceBoardID: "board.a.flick",
        sourceEntryID: "key.i",
        destinationBoardID: "board.i.flick"
    )

    #expect(state.depth == 3)
    #expect(state.pop() == ProfileV3EditNavigationFrame(
        sourceBoardID: "board.a.flick",
        sourceEntryID: "key.i",
        destinationBoardID: "board.i.flick"
    ))
    #expect(state.pop()?.sourceEntryID == "key.a")
    #expect(!state.canGoBack)
}

@Test
func editNavigationResetDropsOnlyTransientFrames() {
    var state = ProfileV3EditNavigationState()
    state.push(
        sourceBoardID: "board.root",
        sourceEntryID: "key.a",
        destinationBoardID: "board.a.flick"
    )
    state.reset()
    #expect(state.depth == 1)
    #expect(state.frames.isEmpty)
}

@Test
func canvasFitIsDeterministicForSameGeometry() {
    let rects = [
        ProfileV3Rect(x: -1, y: -1, width: 2, height: 2),
        ProfileV3Rect(x: 1, y: -1, width: 2, height: 2)
    ]
    let first = ProfileV3CanvasViewport.fitting(
        rects: rects,
        width: 390,
        height: 240
    )
    let explicitFit = ProfileV3CanvasViewport.fitting(
        rects: rects,
        width: 390,
        height: 240
    )
    #expect(first == explicitFit)
}

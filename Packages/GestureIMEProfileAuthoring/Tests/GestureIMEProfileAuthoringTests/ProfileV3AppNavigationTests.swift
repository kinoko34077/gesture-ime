import Testing
@testable import GestureIMEProfileAuthoring

// #92 / #95 §F7
@Test
func fourTabsCoverEveryCategoryOnceWithinOneTap() {
    #expect(ProfileV3AppTab.allCases.map(\.title) == ["編集", "入力", "デザイン", "設定"])
    let placed = ProfileV3AppTab.allCases.flatMap(\.categories)
    #expect(placed.count == ProfileV3AppCategory.allCases.count)
    #expect(Set(placed) == Set(ProfileV3AppCategory.allCases))
    for category in ProfileV3AppCategory.allCases {
        let taps = ProfileV3AppTab.taps(to: category)
        #expect(taps != nil && taps! <= 1)
    }
}

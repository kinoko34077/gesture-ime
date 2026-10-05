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


private final class ProfileV3SessionProbe {}

@Test
func editorSessionCacheReusesOneMutableSessionPerProfile() {
    let cache = ProfileV3EditorSessionCache<ProfileV3SessionProbe>()
    let first = cache.session(for: "profile.a") { ProfileV3SessionProbe() }
    let second = cache.session(for: "profile.a") { ProfileV3SessionProbe() }
    let other = cache.session(for: "profile.b") { ProfileV3SessionProbe() }

    #expect(first === second)
    #expect(first !== other)

    cache.remove(profileID: "profile.a")
    let replacement = cache.session(for: "profile.a") { ProfileV3SessionProbe() }
    #expect(replacement !== first)
}

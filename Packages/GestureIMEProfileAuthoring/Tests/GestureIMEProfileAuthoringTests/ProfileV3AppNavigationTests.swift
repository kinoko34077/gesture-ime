import Testing
@testable import GestureIMEProfileAuthoring

// #157 U1 / P13: four task-domain tabs; Profile is global scope rather than a tab.
@Test
func fourTabsCoverEveryCanonicalCategoryOnceWithinOneTap() {
    #expect(ProfileV3AppTab.allCases.map(\.title) == ["編集", "入力", "デザイン", "設定"])
    let placed = ProfileV3AppTab.allCases.flatMap(\.categories)
    #expect(placed.count == ProfileV3AppCategory.allCases.count)
    #expect(Set(placed) == Set(ProfileV3AppCategory.allCases))
    for category in ProfileV3AppCategory.allCases {
        let taps = ProfileV3AppTab.taps(to: category)
        #expect(taps != nil && taps! <= 1)
    }
}

@Test
func inputTabOwnsTheCanonicalSemanticAuthoringDestinations() {
    #expect(
        ProfileV3AppTab.input.categories == [
            .inputSettings,
            .transformTables,
            .states,
            .macros,
            .conversionDictionary,
        ]
    )
    #expect(ProfileV3AppCategory.inputSettings.title == "ジェスチャー設定")
    #expect(ProfileV3AppCategory.transformTables.title == "文字変換表")
    #expect(ProfileV3AppCategory.states.title == "状態")
    #expect(ProfileV3AppCategory.macros.title == "マクロ")
    #expect(ProfileV3AppCategory.conversionDictionary.title == "変換・辞書の状態")
}

@Test
func developerIsTheCanonicalInternalSurface() {
    #expect(ProfileV3AppTab.settings.categories.contains(.advanced))
    #expect(ProfileV3AppCategory.advanced.title == "開発者")
    #expect(!ProfileV3AppTab.edit.categories.contains(.advanced))
    #expect(!ProfileV3AppTab.input.categories.contains(.advanced))
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

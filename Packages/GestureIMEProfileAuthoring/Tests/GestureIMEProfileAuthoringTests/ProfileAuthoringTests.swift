import Foundation
import Testing
@testable import GestureIMEProfileAuthoring

private let validProfile = """
{
  "schema":"gesture-ime.profile.v1",
  "id":"test.profile",
  "name":"Test",
  "version":1,
  "gesturePolicy":{
    "deadZone":0.1,
    "stage1CommitDistance":0.3,
    "stage2CommitDistance":0.4,
    "angularHysteresisDegrees":8,
    "maxDirectionalStages":2,
    "futurePolicyField":"keep"
  },
  "keyDefinitions":[
    {"id":"key.a","presentation":{"text":"あ","futurePresentation":"keep"},"role":"text"}
  ],
  "layouts":[
    {"id":"layout.base","placements":[{"keyID":"key.a","row":0,"column":0,"width":1,"height":1,"futurePlacement":"keep"}]}
  ],
  "bindingSets":[
    {"id":"bindings.base","bindings":[
      {"keyID":"key.a","path":[],"behavior":{
        "presentation":{"text":"あ"},
        "onRelease":[{"actionID":"text.insert","arguments":{"text":"あ"}}],
        "futureBehavior":"keep"
      }}
    ]}
  ],
  "layers":[{"id":"base","layoutRef":"layout.base","bindingSetRef":"bindings.base"}],
  "macros":[],
  "futureTopLevel":{"keep":true}
}
"""

private func acceptingValidator(_ data: Data) -> ProfileValidation {
    (try? JSONSerialization.jsonObject(with: data)) == nil
        ? ProfileValidation(valid: false, errorCode: "JSON", detail: "invalid")
        : .validResult
}

@Test
func unknownFieldsSurviveEditsAndTwoStageBinding() throws {
    var document = try ProfileDocument(jsonString: validProfile)
    try document.rename("Renamed")
    try document.setKeyPresentation(keyID: "key.a", text: "A")
    try document.setPlacement(layerID: "base", keyID: "key.a", row: 1, column: 2, width: 2, height: 1)
    try document.upsertBinding(
        layerID: "base",
        keyID: "key.a",
        path: [.nw, .se],
        presentationText: "two",
        actions: [
            ProfileActionDraft(actionID: "cursor.move", arguments: ["offset": .integer(2)])
        ]
    )

    let data = try document.encoded(pretty: false)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect((object["futureTopLevel"] as? [String: Any])?["keep"] as? Bool == true)

    let policy = try #require(object["gesturePolicy"] as? [String: Any])
    #expect(policy["futurePolicyField"] as? String == "keep")

    let definitions = try #require(object["keyDefinitions"] as? [[String: Any]])
    let presentation = try #require(definitions.first?["presentation"] as? [String: Any])
    #expect(presentation["futurePresentation"] as? String == "keep")

    let bindings = try document.bindings(layerID: "base", keyID: "key.a")
    let twoStage = try #require(bindings.first(where: { $0.path == [.nw, .se] }))
    #expect(twoStage.actions.first?.actionID == "cursor.move")
    #expect(twoStage.actions.first?.arguments["offset"]?.intValue == 2)
}

@Test
func invalidSaveDoesNotReplaceLastKnownGood() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("gesture-ime-profile-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let store = try ProfileStore(
        rootURL: root,
        validator: { data in
            let text = String(decoding: data, as: UTF8.self)
            return text.contains("\"name\" : \"Reject\"") || text.contains("\"name\":\"Reject\"")
                ? ProfileValidation(valid: false, errorCode: "REJECT", detail: "test")
                : .validResult
        }
    )

    var document = try ProfileDocument(jsonString: validProfile)
    try store.save(document)
    let goodData = try Data(contentsOf: store.fileURL(for: "test.profile"))

    try document.rename("Reject")
    #expect(throws: ProfileAuthoringError.self) {
        try store.save(document)
    }

    let after = try Data(contentsOf: store.fileURL(for: "test.profile"))
    #expect(after == goodData)
}

@Test
func cloneAndActiveProfileMetadataRoundTrip() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("gesture-ime-profile-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let store = try ProfileStore(rootURL: root, validator: acceptingValidator)
    let source = try ProfileDocument(jsonString: validProfile)
    let cloned = try store.clone(source: source, id: "user.clone", name: "Clone")
    #expect(cloned.id == "user.clone")
    #expect(cloned.name == "Clone")
    #expect(cloned.version == 1)

    try store.setActiveProfileID("user.clone")
    #expect(try store.activeProfileID() == "user.clone")

    try store.delete(id: "user.clone")
    #expect(try store.activeProfileID() == nil)
}

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


private let validV2Profile = """
{
  "schema":"gesture-ime.profile.v2",
  "id":"test.v2",
  "name":"V2",
  "version":1,
  "gesturePolicy":{
    "deadZone":0.1,
    "initialCellCommitDistance":0.3,
    "subsequentCellCommitDistance":0.4,
    "angularHysteresisDegrees":8,
    "futurePolicyField":"keep"
  },
  "keyDefinitions":[
    {"id":"key.a","presentation":{"text":"あ"},"futureKey":"keep"}
  ],
  "layouts":[
    {"id":"layout.base","placements":[{"keyID":"key.a","row":0,"column":0}]}
  ],
  "layers":[{"id":"base","layoutRef":"layout.base"}],
  "boards":[
    {
      "id":"board.root",
      "selectionPolicy":{"kind":"relativeCoordinate"},
      "entries":[
        {"coordinate":{"x":0,"y":0},"presentation":{"text":"あ"},"onRelease":[{"actionID":"text.insert","arguments":{"text":"あ"}}],"futureEntry":"keep"}
      ],
      "futureBoard":"keep"
    },
    {
      "id":"board.next",
      "selectionPolicy":{"kind":"relativeCoordinate"},
      "entries":[]
    }
  ],
  "entryPoints":[
    {"id":"entry.base.a","layerID":"base","keyID":"key.a","trigger":"press","boardRef":"board.root"}
  ],
  "macros":[],
  "futureTopLevel":{"keep":true}
}
"""

@Test
func v2BoardEditingPreservesUnknownFieldsAndSupportsTransitions() throws {
    var document = try ProfileDocument(jsonString: validV2Profile)
    #expect(document.isBoardGraphV2)

    let policy = try document.gesturePolicy()
    #expect(policy.stage1CommitDistance == 0.3)
    #expect(policy.stage2CommitDistance == 0.4)

    let entryPointValue = try document.entryPoint(layerID: "base", keyID: "key.a")
    let entryPoint = try #require(entryPointValue)
    #expect(entryPoint.boardID == "board.root")

    try document.upsertBoardEntry(
        boardID: "board.root",
        originalCoordinate: nil,
        coordinate: ProfileBoardCoordinate(x: 1, y: 0),
        presentationText: "E",
        actions: [],
        transition: ProfileBoardTransitionDraft(
            targetBoardID: "board.next",
            lifetime: .transient
        )
    )
    try document.setBoardHoldTransition(
        boardID: "board.root",
        delayMs: 350,
        transition: ProfileBoardTransitionDraft(
            targetBoardID: "board.next",
            lifetime: .persistent
        )
    )

    let entries = try document.boardEntries(boardID: "board.root")
    let east = try #require(entries.first(where: { $0.coordinate == .init(x: 1, y: 0) }))
    #expect(east.transition?.targetBoardID == "board.next")
    #expect(east.transition?.lifetime == .transient)

    let holdValue = try document.boardHoldTrigger(boardID: "board.root")
    let hold = try #require(holdValue)
    #expect(hold.delayMs == 350)
    #expect(hold.transition.lifetime == .persistent)

    let data = try document.encoded(pretty: false)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect((object["futureTopLevel"] as? [String: Any])?["keep"] as? Bool == true)
    let boards = try #require(object["boards"] as? [[String: Any]])
    let root = try #require(boards.first(where: { $0["id"] as? String == "board.root" }))
    #expect(root["futureBoard"] as? String == "keep")
    let encodedEntries = try #require(root["entries"] as? [[String: Any]])
    let center = try #require(encodedEntries.first(where: {
        let coordinate = $0["coordinate"] as? [String: Any]
        return coordinate?["x"] as? Int == 0 && coordinate?["y"] as? Int == 0
    }))
    #expect(center["futureEntry"] as? String == "keep")
}

@Test
func v2KeyLayoutAndPolicyUseSharedDocumentPath() throws {
    var document = try ProfileDocument(jsonString: validV2Profile)
    let keys = try document.keys(layerID: "base")
    #expect(keys.map(\.id) == ["key.a"])

    try document.setPlacement(
        layerID: "base",
        keyID: "key.a",
        row: 2,
        column: 3,
        width: 1.5,
        height: 2
    )
    let movedKeys = try document.keys(layerID: "base")
    let moved = try #require(movedKeys.first)
    #expect(moved.row == 2)
    #expect(moved.column == 3)
    #expect(moved.width == 1.5)
    #expect(moved.height == 2)

    try document.setGesturePolicy(
        ProfileGesturePolicy(
            deadZone: 0.2,
            stage1CommitDistance: 0.5,
            stage2CommitDistance: 0.6,
            angularHysteresisDegrees: 9,
            maxDirectionalStages: 16
        )
    )
    let updated = try document.gesturePolicy()
    #expect(updated.deadZone == 0.2)
    #expect(updated.stage1CommitDistance == 0.5)
    #expect(updated.stage2CommitDistance == 0.6)

    let data = try document.encoded(pretty: false)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let policy = try #require(object["gesturePolicy"] as? [String: Any])
    #expect(policy["initialCellCommitDistance"] as? Double == 0.5)
    #expect(policy["subsequentCellCommitDistance"] as? Double == 0.6)
    #expect(policy["maxDirectionalStages"] == nil)
    #expect(policy["futurePolicyField"] as? String == "keep")
}


@Test
func activeProfileSnapshotPublishAndReadRoundTrip() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("gesture-ime-active-snapshot-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let store = try ActiveProfileSnapshotStore(
        rootURL: root,
        validator: acceptingValidator
    )
    let data = Data(validProfile.utf8)

    let manifest = try store.publish(data)
    #expect(manifest.profileID == "test.profile")
    #expect(manifest.schema == "gesture-ime.profile.v1")
    #expect(manifest.generation == 1)
    #expect(manifest.digest.count == 64)

    let snapshot = try #require(store.readActive())
    #expect(snapshot.manifest == manifest)
    #expect(snapshot.data == data)
    #expect(FileManager.default.fileExists(atPath: try store.snapshotURL(for: manifest).path))
}

@Test
func invalidSnapshotPublishDoesNotReplaceActiveManifest() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("gesture-ime-active-snapshot-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let store = try ActiveProfileSnapshotStore(
        rootURL: root,
        validator: { data in
            let text = String(decoding: data, as: UTF8.self)
            return text.contains("\"name\":\"Reject\"")
                ? ProfileValidation(valid: false, errorCode: "REJECT", detail: "test")
                : acceptingValidator(data)
        }
    )

    let accepted = try store.publish(Data(validProfile.utf8))
    let rejectedText = validProfile.replacingOccurrences(
        of: "\"name\":\"Test\"",
        with: "\"name\":\"Reject\""
    )

    #expect(throws: ActiveProfileSnapshotStoreError.self) {
        try store.publish(Data(rejectedText.utf8))
    }

    #expect(try store.activeManifest() == accepted)
    let snapshotsURL = root.appendingPathComponent(
        ActiveProfileSnapshotStore.snapshotsDirectoryName,
        isDirectory: true
    )
    let snapshotFiles = try FileManager.default.contentsOfDirectory(
        at: snapshotsURL,
        includingPropertiesForKeys: nil
    )
    #expect(snapshotFiles.count == 1)
}

@Test
func activeSnapshotDigestMismatchFailsClosed() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("gesture-ime-active-snapshot-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let store = try ActiveProfileSnapshotStore(
        rootURL: root,
        validator: acceptingValidator
    )
    let manifest = try store.publish(Data(validProfile.utf8))
    let snapshotURL = try store.snapshotURL(for: manifest)

    try Data("tampered".utf8).write(to: snapshotURL, options: .atomic)

    #expect(throws: ActiveProfileSnapshotStoreError.self) {
        try store.readActive()
    }
    #expect(try store.activeManifest() == manifest)
}

@Test
func activeSnapshotGenerationRemainsMonotonicWhenManifestIsMissing() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("gesture-ime-active-snapshot-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let store = try ActiveProfileSnapshotStore(
        rootURL: root,
        validator: acceptingValidator
    )
    let first = try store.publish(Data(validProfile.utf8))
    #expect(first.generation == 1)

    try FileManager.default.removeItem(
        at: root.appendingPathComponent(ActiveProfileSnapshotStore.manifestFileName)
    )

    let secondText = validProfile.replacingOccurrences(
        of: "\"name\":\"Test\"",
        with: "\"name\":\"Second\""
    )
    let second = try store.publish(Data(secondText.utf8))
    #expect(second.generation == 2)
}

import Foundation
import Testing
@testable import GestureIMECore

private enum FixtureSupport {
    static let repositoryRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }()

    static let conformanceRoot = repositoryRoot.appendingPathComponent("spec/conformance", isDirectory: true)

    static func data(_ relative: String) throws -> Data {
        try Data(contentsOf: conformanceRoot.appendingPathComponent(relative))
    }

    static func decode<T: Decodable>(_ type: T.Type, _ relative: String) throws -> T {
        try JSONDecoder().decode(type, from: data(relative))
    }
}

private struct Manifest: Decodable {
    struct Entry: Decodable {
        var file: String
        var kind: String
        var expect: String
        var error: String?
    }
    var fixtures: [Entry]
}

private struct TraceFixture: Decodable {
    struct Sample: Decodable {
        var event: String
        var point: [Double]
    }
    struct Expected: Decodable {
        var path: GesturePath
        var commitAnchors: [[Double]]
        var terminal: String
    }
    var id: String
    var policy: GesturePolicy
    var keySize: [Double]
    var paths: [GesturePath]
    var samples: [Sample]
    var expected: Expected
}

private struct LifecycleFixture: Decodable {
    struct Event: Decodable {
        var type: String
        var atMs: Int?
        var toMs: Int?
        var profileRevision: String?
        var newRevision: String?
    }
    struct Expected: Decodable {
        var terminal: String
        var dispatchedActions: [ActionInvocation]
        var nextSessionProfileRevision: String?
    }
    var id: String
    var endpointBehavior: BindingBehavior
    var events: [Event]
    var expected: Expected
}

@Test("Profile fixture validation matches manifest")
func profileFixtureValidationMatchesManifest() throws {
    let manifest = try FixtureSupport.decode(Manifest.self, "manifest.json")
    for entry in manifest.fixtures where entry.kind == "profile" {
        let data = try FixtureSupport.data(entry.file)
        if entry.expect == "valid" {
            _ = try ProfileCodec.decodeAndValidate(data)
        } else {
            do {
                _ = try ProfileCodec.decodeAndValidate(data)
                Issue.record("Expected invalid fixture: \(entry.file)")
            } catch let error as ProfileValidationError {
                #expect(error.code.rawValue == entry.error)
            }
        }
    }
}

@Test("Default Japanese A root exposes exactly cardinal directions")
func defaultJapaneseCardinalOnly() throws {
    let profile = try ProfileCodec.decodeAndValidate(FixtureSupport.data("fixtures/profile-default-ja-a.valid.json"))
    let set = try #require(profile.bindingSets.first)
    let trie = try BindingTrieCompiler.compile(set, keyID: "kana.a")
    #expect(trie.root.eligibleDirections == Set([.w, .n, .e, .s]))
    #expect(!trie.root.eligibleDirections.contains(.ne))
}

@Test("Diagonal and second-stage paths come only from bindings")
func diagonalAndSecondStagePaths() throws {
    let profile = try ProfileCodec.decodeAndValidate(FixtureSupport.data("fixtures/profile-diagonal-two-stage.valid.json"))
    let set = try #require(profile.bindingSets.first)
    let trie = try BindingTrieCompiler.compile(set, keyID: "kana.a")
    #expect(trie.root.eligibleDirections.contains(.ne))
    #expect(trie.node(for: GesturePath([GestureToken(direction: .ne), GestureToken(direction: .n)])) != nil)
    #expect(trie.node(for: GesturePath([GestureToken(direction: .e), GestureToken(direction: .e)])) != nil)
}

@Test("Shared gesture trace fixtures conform")
func gestureTraceFixturesConform() throws {
    let manifest = try FixtureSupport.decode(Manifest.self, "manifest.json")
    for entry in manifest.fixtures where entry.kind == "gesture-trace" {
        let fixture = try FixtureSupport.decode(TraceFixture.self, entry.file)
        let bindings = fixture.paths.map { path in
            Binding(keyID: "fixture.key", path: path, behavior: BindingBehavior(presentation: nil, onRelease: [], hold: nil))
        }
        let trie = try BindingTrieCompiler.compile(BindingSet(id: "fixture", bindings: bindings), keyID: "fixture.key")
        let down = try #require(fixture.samples.first)
        var session = GestureSession(
            keyID: "fixture.key",
            profileRevision: "fixture",
            trie: trie,
            policy: fixture.policy,
            keySize: GestureSize(width: fixture.keySize[0], height: fixture.keySize[1]),
            touchDown: GesturePoint(x: down.point[0], y: down.point[1])
        )
        var result: GestureSessionResult?
        for sample in fixture.samples.dropFirst() {
            let point = GesturePoint(x: sample.point[0], y: sample.point[1])
            switch sample.event {
            case "move": session.move(to: point)
            case "up": result = session.touchUp()
            default: break
            }
        }
        let final = try #require(result)
        #expect(final.path == fixture.expected.path)
        #expect(final.terminal.rawValue == fixture.expected.terminal)
        #expect(session.commitAnchors == fixture.expected.commitAnchors.map { GesturePoint(x: $0[0], y: $0[1]) })
    }
}

@Test("Lifecycle cancel and profile reload fixtures conform")
func lifecycleFixturesConform() throws {
    let manifest = try FixtureSupport.decode(Manifest.self, "manifest.json")
    for entry in manifest.fixtures where entry.kind == "lifecycle" {
        let fixture = try FixtureSupport.decode(LifecycleFixture.self, entry.file)
        let root = BindingTrieNode(behavior: fixture.endpointBehavior)
        let trie = BindingTrie(root: root)
        var session: GestureSession?
        var result: GestureSessionResult?
        var nextRevision: String?
        for event in fixture.events {
            switch event.type {
            case "touchDown":
                session = GestureSession(
                    keyID: "fixture.key",
                    profileRevision: event.profileRevision ?? "r1",
                    trie: trie,
                    policy: GesturePolicy(deadZone: 0.1, stage1CommitDistance: 0.4, stage2CommitDistance: 0.4, angularHysteresisDegrees: 8, maxDirectionalStages: 2),
                    keySize: GestureSize(width: 100, height: 100),
                    touchDown: GesturePoint(x: 0, y: 0),
                    atMs: event.atMs ?? 0
                )
            case "advanceTime":
                session?.advanceTime(toMs: event.toMs ?? 0)
            case "cancel":
                result = session?.cancel(atMs: event.atMs)
            case "profileReload":
                result = session?.invalidate(atMs: event.atMs)
                nextRevision = event.newRevision
            case "touchUp":
                result = session?.touchUp(atMs: event.atMs)
            default: break
            }
        }
        let final = try #require(result)
        #expect(final.terminal.rawValue == fixture.expected.terminal)
        #expect(final.dispatchedActions == fixture.expected.dispatchedActions)
        #expect(nextRevision == fixture.expected.nextSessionProfileRevision)
    }
}

@Test("Remapping a path changes action without recognizer changes")
func remappingChangesActionOnly() throws {
    var profile = try ProfileCodec.decodeAndValidate(FixtureSupport.data("fixtures/profile-default-ja-a.valid.json"))
    var set = try #require(profile.bindingSets.first)
    let eastIndex = try #require(set.bindings.firstIndex { $0.path == GesturePath([GestureToken(direction: .e)]) })
    set.bindings[eastIndex].behavior.onRelease = [ActionInvocation(actionID: "cursor.move", arguments: ["offset": .integer(1)])]
    profile.bindingSets[0] = set
    try ProfileValidator.validate(profile)
    let trie = try BindingTrieCompiler.compile(set, keyID: "kana.a")
    var session = GestureSession(
        keyID: "kana.a", profileRevision: "remap", trie: trie, policy: profile.gesturePolicy,
        keySize: GestureSize(width: 100, height: 100), touchDown: GesturePoint(x: 0, y: 0)
    )
    session.move(to: GesturePoint(x: 40, y: 0))
    let result = session.touchUp()
    #expect(result.path == GesturePath([GestureToken(direction: .e)]))
    #expect(result.dispatchedActions == [ActionInvocation(actionID: "cursor.move", arguments: ["offset": .integer(1)])])
}

@Test("Hold locks endpoint and suppresses release when configured")
func holdLocksEndpoint() throws {
    let hold = HoldBehavior(
        delayMs: 100,
        onStart: [ActionInvocation(actionID: "text.insert", arguments: ["text": .string("H")])],
        repeatBehavior: nil,
        suppressOnReleaseAfterStart: true
    )
    let root = BindingTrieNode(
        behavior: BindingBehavior(presentation: nil, onRelease: [ActionInvocation(actionID: "text.insert", arguments: ["text": .string("R")])], hold: hold),
        children: [.e: BindingTrieNode(behavior: BindingBehavior(presentation: nil, onRelease: [ActionInvocation(actionID: "text.insert", arguments: ["text": .string("E")])], hold: nil))]
    )
    var session = GestureSession(
        keyID: "k", profileRevision: "r", trie: BindingTrie(root: root),
        policy: GesturePolicy(deadZone: 0.1, stage1CommitDistance: 0.4, stage2CommitDistance: 0.4, angularHysteresisDegrees: 8, maxDirectionalStages: 2),
        keySize: GestureSize(width: 100, height: 100), touchDown: GesturePoint(x: 0, y: 0)
    )
    session.advanceTime(toMs: 100)
    session.move(to: GesturePoint(x: 60, y: 0), atMs: 120)
    let result = session.touchUp(atMs: 130)
    #expect(result.path.tokens.isEmpty)
    #expect(result.dispatchedActions == [ActionInvocation(actionID: "text.insert", arguments: ["text": .string("H")])])
}

@Test("Extreme integer action arguments fail validation without trapping")
func extremeIntegerArgumentsFailSafely() throws {
    var profile = try ProfileCodec.decodeAndValidate(FixtureSupport.data("fixtures/profile-default-ja-a.valid.json"))
    var set = try #require(profile.bindingSets.first)
    set.bindings[0].behavior.onRelease = [ActionInvocation(actionID: "cursor.move", arguments: ["offset": .integer(.min)])]
    profile.bindingSets[0] = set
    do {
        try ProfileValidator.validate(profile)
        Issue.record("Expected invalid extreme integer argument")
    } catch let error as ProfileValidationError {
        #expect(error.code == .invalidActionArguments)
    }
}

@Test("Profile name length follows schema scalar limit")
func profileNameScalarLimit() throws {
    var profile = try ProfileCodec.decodeAndValidate(FixtureSupport.data("fixtures/profile-default-ja-a.valid.json"))
    profile.name = String(repeating: "e\u{301}", count: 65)
    do {
        try ProfileValidator.validate(profile)
        Issue.record("Expected profile name with over 128 Unicode scalars to fail")
    } catch let error as ProfileValidationError {
        #expect(error.code == .unsupportedSchema)
    }
}

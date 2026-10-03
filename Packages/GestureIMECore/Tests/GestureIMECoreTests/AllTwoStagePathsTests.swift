import XCTest
@testable import GestureIMECore

final class AllTwoStagePathsTests: XCTestCase {
    func testEveryDirectionPairCanBeRecognized() throws {
        let keyID = "test.all-two-stage"
        var bindings: [GestureIMECore.Binding] = []

        for first in Direction8.canonicalOrder {
            bindings.append(binding(keyID: keyID, directions: [first]))
            for second in Direction8.canonicalOrder {
                bindings.append(binding(keyID: keyID, directions: [first, second]))
            }
        }

        let trie = try BindingTrieCompiler.compile(
            BindingSet(id: "bindings.all-two-stage", bindings: bindings),
            keyID: keyID
        )

        XCTAssertEqual(trie.root.eligibleDirections, Set(Direction8.canonicalOrder))
        for first in Direction8.canonicalOrder {
            let firstNode = try XCTUnwrap(
                trie.node(for: GesturePath([GestureToken(direction: first)]))
            )
            XCTAssertEqual(firstNode.eligibleDirections, Set(Direction8.canonicalOrder), first.rawValue)
        }

        let policy = GesturePolicy(
            deadZone: 0.05,
            stage1CommitDistance: 0.20,
            stage2CommitDistance: 0.20,
            angularHysteresisDegrees: 4,
            maxDirectionalStages: 2
        )

        for first in Direction8.canonicalOrder {
            for second in Direction8.canonicalOrder {
                let start = GesturePoint(x: 50, y: 50)
                var session = GestureSession(
                    keyID: keyID,
                    profileRevision: "test",
                    trie: trie,
                    policy: policy,
                    keySize: GestureSize(width: 100, height: 100),
                    touchDown: start
                )

                let stage1 = point(from: start, direction: first, distance: 30)
                session.move(to: stage1)

                let stage2 = point(from: stage1, direction: second, distance: 30)
                session.move(to: stage2)

                let result = session.touchUp()
                XCTAssertEqual(
                    result.path,
                    GesturePath([
                        GestureToken(direction: first),
                        GestureToken(direction: second)
                    ]),
                    "\(first.rawValue),\(second.rawValue)"
                )
            }
        }
    }

    private func binding(keyID: String, directions: [Direction8]) -> GestureIMECore.Binding {
        GestureIMECore.Binding(
            keyID: keyID,
            path: GesturePath(directions.map { GestureToken(direction: $0) }),
            behavior: BindingBehavior(
                onRelease: [ActionInvocation(actionID: "noop", arguments: [:])]
            )
        )
    }

    private func point(from anchor: GesturePoint, direction: Direction8, distance: Double) -> GesturePoint {
        let radians = direction.centerDegrees * .pi / 180
        return GesturePoint(
            x: anchor.x + cos(radians) * distance,
            y: anchor.y + sin(radians) * distance
        )
    }
}

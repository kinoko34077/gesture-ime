import Foundation
import XCTest
@testable import GestureIMEProductSettings

final class RuntimeSigningDiagnosticsTests: XCTestCase {
    private let configured = "group.net.kinotch.gestureime"

    func testMissingSignedAppGroupEntitlementIsClassified() {
        let snapshot = AppGroupRuntimeDiagnosticsProbe.makeSnapshot(
            bundleIdentifier: "net.kinotch.gestureime",
            configuredGroupIdentifier: configured,
            effectiveApplicationGroups: [],
            applicationIdentifier: "TEAM.net.kinotch.gestureime",
            teamIdentifier: "TEAM",
            signingIdentifier: "net.kinotch.gestureime",
            entitlementQueryAvailable: true,
            containerURL: { _ in nil }
        )

        XCTAssertEqual(snapshot.classification, .appGroupEntitlementMissing)
        XCTAssertTrue(snapshot.report.contains("effectiveApplicationGroups=(none)"))
    }

    func testConfiguredSignedGroupThatCannotResolveIsClassified() {
        let snapshot = AppGroupRuntimeDiagnosticsProbe.makeSnapshot(
            configuredGroupIdentifier: configured,
            effectiveApplicationGroups: [configured],
            applicationIdentifier: nil,
            teamIdentifier: nil,
            signingIdentifier: nil,
            entitlementQueryAvailable: true,
            containerURL: { _ in nil }
        )

        XCTAssertEqual(
            snapshot.classification,
            .configuredGroupEntitledButContainerUnavailable
        )
        XCTAssertFalse(snapshot.configuredContainerAvailable)
    }

    func testSignerRewrittenGroupThatResolvesIsDistinguishedFromConfiguredID() {
        let rewritten = configured + ".TEAM123"
        let snapshot = AppGroupRuntimeDiagnosticsProbe.makeSnapshot(
            configuredGroupIdentifier: configured,
            effectiveApplicationGroups: [rewritten],
            applicationIdentifier: nil,
            teamIdentifier: "TEAM123",
            signingIdentifier: nil,
            entitlementQueryAvailable: true,
            containerURL: { group in
                group == rewritten
                    ? URL(fileURLWithPath: "/tmp/rewritten-group")
                    : nil
            }
        )

        XCTAssertEqual(
            snapshot.classification,
            .effectiveGroupDiffersAndResolves
        )
        XCTAssertFalse(snapshot.configuredContainerAvailable)
        XCTAssertEqual(snapshot.groupContainerAvailability[rewritten], true)
        XCTAssertTrue(snapshot.report.contains("container[\(rewritten)]=YES"))
    }

    func testMatchingSignedGroupThatResolvesIsHealthy() {
        let snapshot = AppGroupRuntimeDiagnosticsProbe.makeSnapshot(
            configuredGroupIdentifier: configured,
            effectiveApplicationGroups: [configured],
            applicationIdentifier: nil,
            teamIdentifier: nil,
            signingIdentifier: nil,
            entitlementQueryAvailable: true,
            containerURL: { group in
                group == self.configured
                    ? URL(fileURLWithPath: "/tmp/configured-group")
                    : nil
            }
        )

        XCTAssertEqual(snapshot.classification, .configuredGroupResolved)
        XCTAssertTrue(snapshot.configuredContainerAvailable)
    }

    func testUnavailableEntitlementQueryDoesNotMasqueradeAsStrippedEntitlement() {
        let snapshot = AppGroupRuntimeDiagnosticsProbe.makeSnapshot(
            configuredGroupIdentifier: configured,
            effectiveApplicationGroups: [],
            applicationIdentifier: nil,
            teamIdentifier: nil,
            signingIdentifier: nil,
            entitlementQueryAvailable: false,
            containerURL: { _ in nil }
        )

        XCTAssertEqual(snapshot.classification, .entitlementQueryUnavailable)
    }
}

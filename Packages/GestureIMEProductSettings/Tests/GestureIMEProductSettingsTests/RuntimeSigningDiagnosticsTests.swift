import Foundation
import XCTest
@testable import GestureIMEProductSettings

final class RuntimeSigningDiagnosticsTests: XCTestCase {
    private let configured = "group.net.kinotch.gestureime"

    func testMissingSignedAppGroupEntitlementIsClassified() {
        let snapshot = AppGroupRuntimeDiagnosticsProbe.makeSnapshot(
            bundleIdentifier: "net.kinotch.gestureime",
            configuredGroupIdentifier: configured,
            signedEntitlements: [
                "application-identifier": "TEAM.net.kinotch.gestureime"
            ],
            provisionedEntitlements: [
                "com.apple.security.application-groups": [configured]
            ],
            containerURL: { _ in nil }
        )

        XCTAssertEqual(
            snapshot.classification,
            .signedAppGroupEntitlementMissing
        )
        XCTAssertTrue(snapshot.report.contains("signedApplicationGroups=(none)"))
    }

    func testConfiguredSignedGroupThatCannotResolveIsClassified() {
        let entitlements: [String: Any] = [
            "com.apple.security.application-groups": [configured]
        ]
        let snapshot = AppGroupRuntimeDiagnosticsProbe.makeSnapshot(
            configuredGroupIdentifier: configured,
            signedEntitlements: entitlements,
            provisionedEntitlements: entitlements,
            containerURL: { _ in nil }
        )

        XCTAssertEqual(
            snapshot.classification,
            .configuredGroupSignedButContainerUnavailable
        )
        XCTAssertFalse(snapshot.configuredContainerAvailable)
    }

    func testSignerRewrittenGroupThatResolvesIsDistinguishedFromConfiguredID() {
        let rewritten = configured + ".TEAM123"
        let entitlements: [String: Any] = [
            "com.apple.security.application-groups": [rewritten],
            "com.apple.developer.team-identifier": "TEAM123"
        ]
        let snapshot = AppGroupRuntimeDiagnosticsProbe.makeSnapshot(
            configuredGroupIdentifier: configured,
            signedEntitlements: entitlements,
            provisionedEntitlements: entitlements,
            containerURL: { group in
                group == rewritten
                    ? URL(fileURLWithPath: "/tmp/rewritten-group")
                    : nil
            }
        )

        XCTAssertEqual(
            snapshot.classification,
            .signedGroupDiffersAndResolves
        )
        XCTAssertFalse(snapshot.configuredContainerAvailable)
        XCTAssertEqual(snapshot.groupContainerAvailability[rewritten], true)
        XCTAssertTrue(snapshot.report.contains("container[\(rewritten)]=YES"))
    }

    func testMatchingSignedGroupThatResolvesIsHealthy() {
        let entitlements: [String: Any] = [
            "com.apple.security.application-groups": [configured]
        ]
        let snapshot = AppGroupRuntimeDiagnosticsProbe.makeSnapshot(
            configuredGroupIdentifier: configured,
            signedEntitlements: entitlements,
            provisionedEntitlements: entitlements,
            containerURL: { group in
                group == self.configured
                    ? URL(fileURLWithPath: "/tmp/configured-group")
                    : nil
            }
        )

        XCTAssertEqual(snapshot.classification, .configuredGroupResolved)
        XCTAssertTrue(snapshot.configuredContainerAvailable)
    }

    func testProvisioningEvidenceIsUsedWhenSignedEntitlementsCannotBeRead() {
        let snapshot = AppGroupRuntimeDiagnosticsProbe.makeSnapshot(
            configuredGroupIdentifier: configured,
            signedEntitlements: nil,
            provisionedEntitlements: [
                "com.apple.security.application-groups": [configured]
            ],
            containerURL: { _ in nil }
        )

        XCTAssertEqual(
            snapshot.classification,
            .configuredGroupProvisionedButContainerUnavailable
        )
    }

    func testCodeSignatureParserReadsXMLAppGroupEntitlements() throws {
        let entitlements: [String: Any] = [
            "application-identifier": "TEAM.net.kinotch.gestureime",
            "com.apple.developer.team-identifier": "TEAM",
            "com.apple.security.application-groups": [configured]
        ]
        let executable = try syntheticMachO(entitlements: entitlements)

        let parsed = try XCTUnwrap(
            RuntimeSigningEvidenceParser.codeSignatureEntitlements(
                executableData: executable
            )
        )
        XCTAssertEqual(
            parsed["application-identifier"] as? String,
            "TEAM.net.kinotch.gestureime"
        )
        XCTAssertEqual(
            parsed["com.apple.security.application-groups"] as? [String],
            [configured]
        )
    }

    func testProvisioningParserReadsEntitlementsFromCMSPayloadBytes() throws {
        let root: [String: Any] = [
            "Name": "Synthetic",
            "Entitlements": [
                "application-identifier": "TEAM.net.kinotch.gestureime",
                "com.apple.security.application-groups": [configured]
            ]
        ]
        let xml = try PropertyListSerialization.data(
            fromPropertyList: root,
            format: .xml,
            options: 0
        )
        var profile = Data([0x30, 0x82, 0x01, 0x00])
        profile.append(xml)
        profile.append(contentsOf: [0x00, 0xff, 0x00])

        let parsed = try XCTUnwrap(
            RuntimeSigningEvidenceParser.provisioningEntitlements(
                profileData: profile
            )
        )
        XCTAssertEqual(
            parsed["com.apple.security.application-groups"] as? [String],
            [configured]
        )
    }

    private func syntheticMachO(
        entitlements: [String: Any]
    ) throws -> Data {
        let plist = try PropertyListSerialization.data(
            fromPropertyList: entitlements,
            format: .xml,
            options: 0
        )

        var entitlementBlob = Data()
        appendUInt32BE(0xfade7171, to: &entitlementBlob)
        appendUInt32BE(UInt32(8 + plist.count), to: &entitlementBlob)
        entitlementBlob.append(plist)

        var superBlob = Data()
        let superLength = 20 + entitlementBlob.count
        appendUInt32BE(0xfade0cc0, to: &superBlob)
        appendUInt32BE(UInt32(superLength), to: &superBlob)
        appendUInt32BE(1, to: &superBlob)
        appendUInt32BE(5, to: &superBlob)
        appendUInt32BE(20, to: &superBlob)
        superBlob.append(entitlementBlob)

        var macho = Data(repeating: 0, count: 32)
        writeUInt32LE(0xfeedfacf, to: &macho, at: 0)
        writeUInt32LE(1, to: &macho, at: 16)
        writeUInt32LE(16, to: &macho, at: 20)

        var command = Data()
        appendUInt32LE(0x1d, to: &command)
        appendUInt32LE(16, to: &command)
        appendUInt32LE(48, to: &command)
        appendUInt32LE(UInt32(superBlob.count), to: &command)

        macho.append(command)
        macho.append(superBlob)
        return macho
    }

    private func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 24) & 0xff))
    }

    private func appendUInt32BE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }

    private func writeUInt32LE(
        _ value: UInt32,
        to data: inout Data,
        at offset: Int
    ) {
        data[offset] = UInt8(value & 0xff)
        data[offset + 1] = UInt8((value >> 8) & 0xff)
        data[offset + 2] = UInt8((value >> 16) & 0xff)
        data[offset + 3] = UInt8((value >> 24) & 0xff)
    }
}

import Foundation
import XCTest
@testable import GestureIMEProductSettings

final class ProductSettingsTests: XCTestCase {
    func testDefaultsPreserveCurrentNoHapticBehaviorAndReferenceHeight() throws {
        let values = ProductSettingsValues.defaults
        XCTAssertEqual(values.hapticStrength, 0.0)
        XCTAssertFalse(values.hapticsEnabled)
        XCTAssertEqual(values.keyboardHeightScale, 1.0)
        XCTAssertEqual(
            try values.scaledKeyboardHeight(baseHeight: 344),
            344,
            accuracy: 0.000_001
        )
    }

    func testValidationAllowsHapticBoundariesWithoutInventingHeightMax() throws {
        XCTAssertNoThrow(
            try ProductSettingsValues(
                hapticStrength: 0,
                keyboardHeightScale: 0.01
            )
        )
        XCTAssertNoThrow(
            try ProductSettingsValues(
                hapticStrength: 1,
                keyboardHeightScale: 100
            )
        )

        XCTAssertThrowsError(
            try ProductSettingsValues(
                hapticStrength: -0.001,
                keyboardHeightScale: 1
            )
        )
        XCTAssertThrowsError(
            try ProductSettingsValues(
                hapticStrength: 1.001,
                keyboardHeightScale: 1
            )
        )
        XCTAssertThrowsError(
            try ProductSettingsValues(
                hapticStrength: .nan,
                keyboardHeightScale: 1
            )
        )
        XCTAssertThrowsError(
            try ProductSettingsValues(
                hapticStrength: 0.5,
                keyboardHeightScale: 0
            )
        )
        XCTAssertThrowsError(
            try ProductSettingsValues(
                hapticStrength: 0.5,
                keyboardHeightScale: .infinity
            )
        )
    }

    // #93 / #95 §F8
    func testKeySoundDefaultsOnAndLegacyRecordsDecodeAsOn() throws {
        XCTAssertTrue(ProductSettingsValues.defaults.keySoundEnabled)
        let legacy = Data(
            """
            {
              "schema": "gesture-ime.product-settings.v1",
              "generation": 3,
              "hapticStrength": 0.5,
              "keyboardHeightScale": 1.0
            }
            """.utf8
        )
        let decoded = try JSONDecoder().decode(ProductSettingsRecord.self, from: legacy)
        XCTAssertTrue(try decoded.validatedValues().keySoundEnabled)
    }

    func testKeySoundOffRoundTripsThroughStore() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try ProductSettingsStore(rootURL: root)
        let values = try ProductSettingsValues(
            hapticStrength: 0.3,
            keyboardHeightScale: 1.0,
            keySoundEnabled: false
        )
        _ = try store.publish(values)
        XCTAssertEqual(try store.readActive()?.values, values)
        XCTAssertEqual(try store.readActive()?.values.keySoundEnabled, false)
    }

    func testMalformedAndOutOfRangeDecodedRecordsFailClosed() throws {
        let malformed = Data(
            """
            {
              "schema": "gesture-ime.product-settings.v1",
              "generation": 1,
              "hapticStrength": 0.5
            }
            """.utf8
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(ProductSettingsRecord.self, from: malformed)
        )

        let outOfRange = Data(
            """
            {
              "schema": "gesture-ime.product-settings.v1",
              "generation": 1,
              "hapticStrength": 2.0,
              "keyboardHeightScale": 1.0
            }
            """.utf8
        )
        let decoded = try JSONDecoder().decode(
            ProductSettingsRecord.self,
            from: outOfRange
        )
        XCTAssertThrowsError(try decoded.validatedValues())
    }

    func testPublishReadRoundTripAndGenerationAreAtomicRecords() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try ProductSettingsStore(rootURL: root)
        let firstValues = try ProductSettingsValues(
            hapticStrength: 0.25,
            keyboardHeightScale: 1.1
        )
        let first = try store.publish(firstValues)
        XCTAssertEqual(first.generation, 1)

        let firstSnapshot = try XCTUnwrap(store.readActive())
        XCTAssertEqual(firstSnapshot.values, firstValues)
        XCTAssertEqual(
            firstSnapshot.record.schema,
            ProductSettingsRecord.schemaIdentifier
        )

        let secondValues = try ProductSettingsValues(
            hapticStrength: 0.75,
            keyboardHeightScale: 1.25
        )
        let second = try store.publish(secondValues)
        XCTAssertEqual(second.generation, 2)
        XCTAssertEqual(try store.readActive()?.values, secondValues)
    }

    func testCorruptActiveSnapshotFallsBackToPreviousPublishedGeneration() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try ProductSettingsStore(rootURL: root)
        let firstValues = try ProductSettingsValues(
            hapticStrength: 0.2,
            keyboardHeightScale: 0.9
        )
        let first = try store.publish(firstValues)

        let secondValues = try ProductSettingsValues(
            hapticStrength: 0.8,
            keyboardHeightScale: 1.2
        )
        let second = try store.publish(secondValues)
        try Data("corrupt".utf8).write(
            to: try store.snapshotURL(for: second),
            options: .atomic
        )

        XCTAssertThrowsError(try store.readActive())
        let recovered = try XCTUnwrap(store.readLastKnownGood())
        XCTAssertEqual(recovered.manifest, first)
        XCTAssertEqual(recovered.values, firstValues)
    }

    func testTamperedManifestFailsClosed() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try ProductSettingsStore(rootURL: root)
        _ = try store.publish(.defaults)

        let manifestURL = root.appendingPathComponent(
            ProductSettingsStore.manifestFileName
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: manifestURL)
            ) as? [String: Any]
        )
        object["generation"] = 999
        try JSONSerialization.data(withJSONObject: object).write(
            to: manifestURL,
            options: .atomic
        )

        XCTAssertThrowsError(try store.readActive())
    }

    func testGenerationDoesNotReuseOrphanSnapshotNumber() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try ProductSettingsStore(rootURL: root)
        let first = try store.publish(.defaults)
        XCTAssertEqual(first.generation, 1)

        try FileManager.default.removeItem(
            at: root.appendingPathComponent(ProductSettingsStore.manifestFileName)
        )

        let second = try store.publish(
            ProductSettingsValues(
                hapticStrength: 0.5,
                keyboardHeightScale: 1.05
            )
        )
        XCTAssertEqual(second.generation, 2)
    }

    func testPhysicalHeightScalingDoesNotChangeSemanticReference() throws {
        let values = try ProductSettingsValues(
            hapticStrength: 0,
            keyboardHeightScale: 1.25
        )
        XCTAssertEqual(
            try values.scaledKeyboardHeight(baseHeight: 344),
            430,
            accuracy: 0.000_001
        )
        XCTAssertThrowsError(
            try values.scaledKeyboardHeight(baseHeight: 0)
        )
    }

    func testCapabilityTruthIsExplicit() {
        XCTAssertTrue(
            ProductSettingsDeliveryCapability.sharedContainer
                .crossProcessAvailable
        )
        XCTAssertFalse(
            ProductSettingsDeliveryCapability.appLocalOnly
                .crossProcessAvailable
        )
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "gesture-ime-product-settings-tests-\(UUID().uuidString)",
                isDirectory: true
            )
    }
}


// MARK: - #75 capability truth

final class ProductSettingsCapabilityProbeTests: XCTestCase {
    func testProbeIsTruthfulWithoutGuessingAnAppGroup() {
        let none = ProductSettingsCapabilityProbe.probe(appGroupIdentifier: nil) { _ in
            XCTFail("must not query a container without a configured group")
            return nil
        }
        XCTAssertEqual(none, .unavailable(.appGroupNotConfigured))
        XCTAssertEqual(none.capability, .appLocalOnly)
        XCTAssertNil(none.rootURL)

        XCTAssertEqual(
            ProductSettingsCapabilityProbe.probe(appGroupIdentifier: "  ") { _ in nil },
            .unavailable(.appGroupNotConfigured)
        )

        let missing = ProductSettingsCapabilityProbe.probe(appGroupIdentifier: "group.example") { _ in nil }
        XCTAssertEqual(missing, .unavailable(.containerUnavailable("group.example")))
        XCTAssertFalse(missing.capability.crossProcessAvailable)

        let base = URL(fileURLWithPath: "/tmp/group")
        let ok = ProductSettingsCapabilityProbe.probe(appGroupIdentifier: "group.example") { _ in base }
        XCTAssertEqual(ok.capability, .sharedContainer)
        XCTAssertEqual(ok.rootURL, base.appendingPathComponent("ProductSettings", isDirectory: true))
        XCTAssertTrue(ProductSettingsCapabilityProbe.Unavailable.appGroupNotConfigured.japaneseReason.contains("App Group"))
    }
}

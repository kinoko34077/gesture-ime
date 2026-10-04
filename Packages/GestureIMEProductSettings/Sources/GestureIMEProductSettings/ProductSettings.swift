import Foundation

public enum ProductSettingsValidationError: Error, Equatable, Sendable {
    case hapticStrengthOutOfRange
    case keyboardHeightScaleMustBeFiniteAndPositive
    case baseKeyboardHeightMustBeFiniteAndPositive
    case scaledKeyboardHeightInvalid
}

public struct ProductSettingsValues: Equatable, Sendable {
    public static let defaults = ProductSettingsValues(
        uncheckedHapticStrength: 0.0,
        keyboardHeightScale: 1.0
    )

    public let hapticStrength: Double
    public let keyboardHeightScale: Double

    public init(
        hapticStrength: Double,
        keyboardHeightScale: Double
    ) throws {
        guard hapticStrength.isFinite,
              (0.0...1.0).contains(hapticStrength) else {
            throw ProductSettingsValidationError.hapticStrengthOutOfRange
        }
        guard keyboardHeightScale.isFinite,
              keyboardHeightScale > 0 else {
            throw ProductSettingsValidationError.keyboardHeightScaleMustBeFiniteAndPositive
        }
        self.hapticStrength = hapticStrength
        self.keyboardHeightScale = keyboardHeightScale
    }

    public var hapticsEnabled: Bool {
        hapticStrength > 0
    }

    public func scaledKeyboardHeight(baseHeight: Double) throws -> Double {
        guard baseHeight.isFinite, baseHeight > 0 else {
            throw ProductSettingsValidationError.baseKeyboardHeightMustBeFiniteAndPositive
        }
        let scaled = baseHeight * keyboardHeightScale
        guard scaled.isFinite, scaled > 0 else {
            throw ProductSettingsValidationError.scaledKeyboardHeightInvalid
        }
        return scaled
    }

    private init(
        uncheckedHapticStrength hapticStrength: Double,
        keyboardHeightScale: Double
    ) {
        self.hapticStrength = hapticStrength
        self.keyboardHeightScale = keyboardHeightScale
    }
}

public struct ProductSettingsRecord: Codable, Equatable, Sendable {
    public static let schemaIdentifier = "gesture-ime.product-settings.v1"

    public let schema: String
    public let generation: UInt64
    public let hapticStrength: Double
    public let keyboardHeightScale: Double

    fileprivate init(generation: UInt64, values: ProductSettingsValues) {
        self.schema = Self.schemaIdentifier
        self.generation = generation
        self.hapticStrength = values.hapticStrength
        self.keyboardHeightScale = values.keyboardHeightScale
    }

    public func validatedValues() throws -> ProductSettingsValues {
        guard schema == Self.schemaIdentifier, generation > 0 else {
            throw ProductSettingsStoreError.invalidRecord
        }
        do {
            return try ProductSettingsValues(
                hapticStrength: hapticStrength,
                keyboardHeightScale: keyboardHeightScale
            )
        } catch {
            throw ProductSettingsStoreError.invalidRecord
        }
    }
}

public struct ProductSettingsManifest: Codable, Equatable, Sendable {
    public static let schemaIdentifier = "gesture-ime.product-settings-manifest.v1"

    public let schema: String
    public let generation: UInt64
    public let checksum: String
    public let snapshotFile: String

    fileprivate init(
        generation: UInt64,
        checksum: String,
        snapshotFile: String
    ) {
        self.schema = Self.schemaIdentifier
        self.generation = generation
        self.checksum = checksum
        self.snapshotFile = snapshotFile
    }
}

public struct ProductSettingsSnapshot: Equatable, Sendable {
    public let manifest: ProductSettingsManifest
    public let record: ProductSettingsRecord
    public let values: ProductSettingsValues

    public init(
        manifest: ProductSettingsManifest,
        record: ProductSettingsRecord,
        values: ProductSettingsValues
    ) {
        self.manifest = manifest
        self.record = record
        self.values = values
    }
}

public enum ProductSettingsStoreError: Error, Equatable, Sendable {
    case invalidManifest
    case invalidRecord
    case generationOverflow
    case snapshotAlreadyExists(String)
    case snapshotMissing(String)
    case checksumMismatch
}

public enum ProductSettingsDeliveryCapability: Equatable, Sendable {
    case sharedContainer
    case appLocalOnly

    public var crossProcessAvailable: Bool {
        switch self {
        case .sharedContainer:
            true
        case .appLocalOnly:
            false
        }
    }
}

public final class ProductSettingsStore: @unchecked Sendable {
    public static let manifestFileName = "active-product-settings-manifest.json"
    public static let fallbackManifestFileName = "last-known-good-product-settings-manifest.json"
    public static let snapshotsDirectoryName = "product-settings-snapshots"

    public let rootURL: URL

    private let fileManager: FileManager
    private let manifestURL: URL
    private let fallbackManifestURL: URL
    private let snapshotsURL: URL

    public init(
        rootURL: URL,
        fileManager: FileManager = .default
    ) throws {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.manifestURL = rootURL.appendingPathComponent(Self.manifestFileName)
        self.fallbackManifestURL = rootURL.appendingPathComponent(Self.fallbackManifestFileName)
        self.snapshotsURL = rootURL.appendingPathComponent(
            Self.snapshotsDirectoryName,
            isDirectory: true
        )

        try fileManager.createDirectory(
            at: snapshotsURL,
            withIntermediateDirectories: true
        )
    }

    @discardableResult
    public func publish(_ values: ProductSettingsValues) throws -> ProductSettingsManifest {
        let generation = try nextGeneration()
        let record = ProductSettingsRecord(
            generation: generation,
            values: values
        )
        let data = try Self.encode(record)
        let checksum = ProductSettingsChecksum.fnv1a64Hex(data)
        let snapshotFile = Self.snapshotFileName(
            generation: generation,
            checksum: checksum
        )
        let snapshotURL = snapshotsURL.appendingPathComponent(snapshotFile)

        guard !fileManager.fileExists(atPath: snapshotURL.path) else {
            throw ProductSettingsStoreError.snapshotAlreadyExists(snapshotFile)
        }

        try data.write(to: snapshotURL, options: .atomic)

        let manifest = ProductSettingsManifest(
            generation: generation,
            checksum: checksum,
            snapshotFile: snapshotFile
        )

        var currentForFallback: ProductSettingsManifest?
        do {
            if let current = try activeManifest() {
                _ = try validatedSnapshot(for: current)
                currentForFallback = current
            }
        } catch {
            currentForFallback = nil
        }

        if let currentForFallback {
            try writeManifest(currentForFallback, to: fallbackManifestURL)
        }

        try writeManifest(manifest, to: manifestURL)
        return manifest
    }

    public func activeManifest() throws -> ProductSettingsManifest? {
        try readManifest(at: manifestURL)
    }

    public func readActive() throws -> ProductSettingsSnapshot? {
        guard let manifest = try activeManifest() else {
            return nil
        }
        return try validatedSnapshot(for: manifest)
    }

    public func readLastKnownGood() throws -> ProductSettingsSnapshot? {
        var activeFailure: Error?

        do {
            if let active = try activeManifest() {
                return try validatedSnapshot(for: active)
            }
        } catch {
            activeFailure = error
        }

        do {
            if let fallback = try readManifest(at: fallbackManifestURL) {
                return try validatedSnapshot(for: fallback)
            }
        } catch {
            if activeFailure == nil {
                activeFailure = error
            }
        }

        if let activeFailure {
            throw activeFailure
        }
        return nil
    }

    public func snapshotURL(for manifest: ProductSettingsManifest) throws -> URL {
        try Self.validateManifestShape(manifest)
        return snapshotsURL.appendingPathComponent(manifest.snapshotFile)
    }

    private func validatedSnapshot(
        for manifest: ProductSettingsManifest
    ) throws -> ProductSettingsSnapshot {
        try Self.validateManifestShape(manifest)

        let url = snapshotsURL.appendingPathComponent(manifest.snapshotFile)
        guard fileManager.fileExists(atPath: url.path) else {
            throw ProductSettingsStoreError.snapshotMissing(manifest.snapshotFile)
        }

        let data = try Data(contentsOf: url)
        guard ProductSettingsChecksum.fnv1a64Hex(data) == manifest.checksum else {
            throw ProductSettingsStoreError.checksumMismatch
        }

        let record: ProductSettingsRecord
        do {
            record = try JSONDecoder().decode(ProductSettingsRecord.self, from: data)
        } catch {
            throw ProductSettingsStoreError.invalidRecord
        }

        guard record.generation == manifest.generation else {
            throw ProductSettingsStoreError.invalidRecord
        }
        let values = try record.validatedValues()

        return ProductSettingsSnapshot(
            manifest: manifest,
            record: record,
            values: values
        )
    }

    private func readManifest(at url: URL) throws -> ProductSettingsManifest? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let manifest: ProductSettingsManifest
        do {
            manifest = try JSONDecoder().decode(
                ProductSettingsManifest.self,
                from: Data(contentsOf: url)
            )
        } catch {
            throw ProductSettingsStoreError.invalidManifest
        }
        try Self.validateManifestShape(manifest)
        return manifest
    }

    private func writeManifest(
        _ manifest: ProductSettingsManifest,
        to url: URL
    ) throws {
        try Self.validateManifestShape(manifest)
        try Self.encode(manifest).write(to: url, options: .atomic)
    }

    private func nextGeneration() throws -> UInt64 {
        var greatest: UInt64 = 0

        let files = try fileManager.contentsOfDirectory(
            at: snapshotsURL,
            includingPropertiesForKeys: nil
        )
        for file in files {
            guard let generation = Self.generation(fromSnapshotFileName: file.lastPathComponent) else {
                continue
            }
            greatest = max(greatest, generation)
        }

        guard greatest < UInt64.max else {
            throw ProductSettingsStoreError.generationOverflow
        }
        return greatest + 1
    }

    private static func validateManifestShape(
        _ manifest: ProductSettingsManifest
    ) throws {
        guard manifest.schema == ProductSettingsManifest.schemaIdentifier,
              manifest.generation > 0,
              manifest.checksum.count == 16,
              manifest.checksum.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
              manifest.snapshotFile == snapshotFileName(
                generation: manifest.generation,
                checksum: manifest.checksum
              ) else {
            throw ProductSettingsStoreError.invalidManifest
        }
    }

    private static func snapshotFileName(
        generation: UInt64,
        checksum: String
    ) -> String {
        "settings-\(generation)-\(checksum).json"
    }

    private static func generation(fromSnapshotFileName name: String) -> UInt64? {
        guard name.hasPrefix("settings-"), name.hasSuffix(".json") else {
            return nil
        }
        let withoutSuffix = String(name.dropLast(5))
        let parts = withoutSuffix.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "settings" else {
            return nil
        }
        return UInt64(parts[1])
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}

enum ProductSettingsChecksum {
    static func fnv1a64Hex(_ data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let raw = String(hash, radix: 16)
        return String(repeating: "0", count: max(0, 16 - raw.count)) + raw
    }
}

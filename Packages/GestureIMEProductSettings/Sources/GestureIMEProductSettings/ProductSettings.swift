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
    /// #93 / #95 §F8: system input click on accepted key events.
    public let keySoundEnabled: Bool

    public init(
        hapticStrength: Double,
        keyboardHeightScale: Double,
        keySoundEnabled: Bool = true
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
        self.keySoundEnabled = keySoundEnabled
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
        self.keySoundEnabled = true
    }
}

public struct ProductSettingsRecord: Codable, Equatable, Sendable {
    public static let schemaIdentifier = "gesture-ime.product-settings.v1"

    public let schema: String
    public let generation: UInt64
    public let hapticStrength: Double
    public let keyboardHeightScale: Double
    /// Optional so records written before #93 still decode (absent = true).
    public let keySoundEnabled: Bool?

    fileprivate init(generation: UInt64, values: ProductSettingsValues) {
        self.schema = Self.schemaIdentifier
        self.generation = generation
        self.hapticStrength = values.hapticStrength
        self.keyboardHeightScale = values.keyboardHeightScale
        self.keySoundEnabled = values.keySoundEnabled
    }

    public func validatedValues() throws -> ProductSettingsValues {
        guard schema == Self.schemaIdentifier, generation > 0 else {
            throw ProductSettingsStoreError.invalidRecord
        }
        do {
            return try ProductSettingsValues(
                hapticStrength: hapticStrength,
                keyboardHeightScale: keyboardHeightScale,
                keySoundEnabled: keySoundEnabled ?? true
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

public enum ProductKeySoundCapability: Equatable, Sendable {
    case available
    case unavailableRequiresFullAccess

    public init(hasFullAccess: Bool) {
        self = hasFullAccess ? .available : .unavailableRequiresFullAccess
    }

    public var isAvailable: Bool {
        self == .available
    }

    public func effectiveEnabled(storedEnabled: Bool) -> Bool {
        isAvailable && storedEnabled
    }

    public var japaneseReason: String {
        switch self {
        case .available:
            "キー音を利用できます。"
        case .unavailableRequiresFullAccess:
            "フルアクセスを要求しない設定のため、キー音は利用できません。触覚フィードバックは利用できます。"
        }
    }
}

public struct GestureIMEAppGroupPaths: Equatable, Sendable {
    public let groupIdentifier: String
    public let containerURL: URL
    public let rootURL: URL
    public let profileDeliveryRootURL: URL
    public let productSettingsRootURL: URL

    public init(
        groupIdentifier: String,
        containerURL: URL,
        rootURL: URL,
        profileDeliveryRootURL: URL,
        productSettingsRootURL: URL
    ) {
        self.groupIdentifier = groupIdentifier
        self.containerURL = containerURL
        self.rootURL = rootURL
        self.profileDeliveryRootURL = profileDeliveryRootURL
        self.productSettingsRootURL = productSettingsRootURL
    }
}

/// #128: one App Group resolver shared by Profile delivery and ProductSettings.
/// Resolving paths never creates directories; writers own filesystem mutation.
public enum GestureIMEAppGroupResolver {
    public static let appGroupInfoKey = "GestureIMEAppGroupIdentifier"
    public static let rootDirectoryName = "GestureIME"
    public static let profileDeliverySubdirectory = "ProfileDelivery"
    public static let productSettingsSubdirectory = "ProductSettings"

    public enum Unavailable: Equatable, Sendable {
        case appGroupNotConfigured
        case containerUnavailable(String)

        public var japaneseReason: String {
            switch self {
            case .appGroupNotConfigured:
                "アプリとキーボードの共有領域（App Group）が設定されていないため、キーボード本体へ反映できません。"
            case .containerUnavailable(let group):
                "共有領域（\(group)）を利用できません。App Group の登録・署名・プロビジョニングを確認してください。"
            }
        }
    }

    public enum Result: Equatable, Sendable {
        case available(GestureIMEAppGroupPaths)
        case unavailable(Unavailable)

        public var paths: GestureIMEAppGroupPaths? {
            if case .available(let paths) = self { return paths }
            return nil
        }
    }

    public static func resolve(
        appGroupIdentifier: String?,
        containerURL: (String) -> URL?
    ) -> Result {
        guard let group = appGroupIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !group.isEmpty else {
            return .unavailable(.appGroupNotConfigured)
        }
        guard let container = containerURL(group) else {
            return .unavailable(.containerUnavailable(group))
        }

        let root = container.appendingPathComponent(rootDirectoryName, isDirectory: true)
        return .available(
            GestureIMEAppGroupPaths(
                groupIdentifier: group,
                containerURL: container,
                rootURL: root,
                profileDeliveryRootURL: root.appendingPathComponent(
                    profileDeliverySubdirectory,
                    isDirectory: true
                ),
                productSettingsRootURL: root.appendingPathComponent(
                    productSettingsSubdirectory,
                    isDirectory: true
                )
            )
        )
    }

    public static func resolveMainBundle() -> Result {
        resolve(
            appGroupIdentifier: Bundle.main.object(
                forInfoDictionaryKey: appGroupInfoKey
            ) as? String,
            containerURL: { group in
                #if os(iOS) || os(macOS)
                FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: group
                )
                #else
                nil
                #endif
            }
        )
    }
}

/// #75 compatibility adapter. New code should use GestureIMEAppGroupResolver
/// when it needs both ProfileDelivery and ProductSettings roots.
public enum ProductSettingsCapabilityProbe {
    public static let appGroupInfoKey = GestureIMEAppGroupResolver.appGroupInfoKey
    public static let settingsSubdirectory = GestureIMEAppGroupResolver.productSettingsSubdirectory

    public typealias Unavailable = GestureIMEAppGroupResolver.Unavailable

    public enum Result: Equatable, Sendable {
        case available(rootURL: URL)
        case unavailable(Unavailable)

        public var capability: ProductSettingsDeliveryCapability {
            if case .available = self { return .sharedContainer }
            return .appLocalOnly
        }

        public var rootURL: URL? {
            if case .available(let url) = self { return url }
            return nil
        }
    }

    public static func probe(
        appGroupIdentifier: String?,
        containerURL: (String) -> URL?
    ) -> Result {
        switch GestureIMEAppGroupResolver.resolve(
            appGroupIdentifier: appGroupIdentifier,
            containerURL: containerURL
        ) {
        case .available(let paths):
            return .available(rootURL: paths.productSettingsRootURL)
        case .unavailable(let reason):
            return .unavailable(reason)
        }
    }

    public static func probeMainBundle() -> Result {
        switch GestureIMEAppGroupResolver.resolveMainBundle() {
        case .available(let paths):
            return .available(rootURL: paths.productSettingsRootURL)
        case .unavailable(let reason):
            return .unavailable(reason)
        }
    }
}

public final class ProductSettingsStore {
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
        fileManager: FileManager = .default,
        createDirectories: Bool = true
    ) throws {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.manifestURL = rootURL.appendingPathComponent(Self.manifestFileName)
        self.fallbackManifestURL = rootURL.appendingPathComponent(Self.fallbackManifestFileName)
        self.snapshotsURL = rootURL.appendingPathComponent(
            Self.snapshotsDirectoryName,
            isDirectory: true
        )

        if createDirectories {
            try fileManager.createDirectory(
                at: snapshotsURL,
                withIntermediateDirectories: true
            )
        }
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

        // Retention is post-commit and best-effort. A pruning failure must never
        // turn an already committed publication into a false failure.
        pruneOrphanSnapshotsBestEffort()
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

    private func pruneOrphanSnapshotsBestEffort() {
        let active: ProductSettingsManifest
        let fallback: ProductSettingsManifest?
        do {
            guard let committedActive = try readManifest(at: manifestURL) else {
                return
            }
            active = committedActive
            fallback = try readManifest(at: fallbackManifestURL)
        } catch {
            // If committed manifest state cannot be read safely, retain every
            // snapshot rather than risk deleting recovery evidence.
            return
        }

        var retained = Set([active.snapshotFile])
        if let fallback {
            retained.insert(fallback.snapshotFile)
        }

        guard let files = try? fileManager.contentsOfDirectory(
            at: snapshotsURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for file in files {
            let name = file.lastPathComponent
            guard Self.generation(fromSnapshotFileName: name) != nil,
                  !retained.contains(name) else {
                continue
            }
            try? fileManager.removeItem(at: file)
        }
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

/// Read-only settings transport for the Keyboard Extension.
/// Construction performs no filesystem mutation.
public final class ProductSettingsReader {
    private let store: ProductSettingsStore

    public init(
        rootURL: URL,
        fileManager: FileManager = .default
    ) throws {
        store = try ProductSettingsStore(
            rootURL: rootURL,
            fileManager: fileManager,
            createDirectories: false
        )
    }

    public func activeManifest() throws -> ProductSettingsManifest? {
        try store.activeManifest()
    }

    public func readActive() throws -> ProductSettingsSnapshot? {
        try store.readActive()
    }

    public func readLastKnownGood() throws -> ProductSettingsSnapshot? {
        try store.readLastKnownGood()
    }
}

/// Main-App-only publisher surface.
public final class ProductSettingsWriter {
    private let store: ProductSettingsStore

    public init(
        rootURL: URL,
        fileManager: FileManager = .default
    ) throws {
        store = try ProductSettingsStore(
            rootURL: rootURL,
            fileManager: fileManager,
            createDirectories: true
        )
    }

    @discardableResult
    public func publish(_ values: ProductSettingsValues) throws -> ProductSettingsManifest {
        try store.publish(values)
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

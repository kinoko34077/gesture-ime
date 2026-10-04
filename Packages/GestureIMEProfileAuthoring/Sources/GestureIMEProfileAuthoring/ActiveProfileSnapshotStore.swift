import CryptoKit
import Foundation

public struct ActiveProfileManifest: Codable, Equatable, Sendable {
    public let profileID: String
    public let schema: String
    public let generation: UInt64
    public let digest: String
    public let snapshotFile: String

    public init(
        profileID: String,
        schema: String,
        generation: UInt64,
        digest: String,
        snapshotFile: String
    ) {
        self.profileID = profileID
        self.schema = schema
        self.generation = generation
        self.digest = digest
        self.snapshotFile = snapshotFile
    }
}

public struct ActiveProfileSnapshot: Equatable, Sendable {
    public let manifest: ActiveProfileManifest
    public let data: Data

    public init(manifest: ActiveProfileManifest, data: Data) {
        self.manifest = manifest
        self.data = data
    }
}

public enum ActiveProfileSnapshotStoreError: Error, Equatable, Sendable {
    case validationFailed(code: String?, detail: String?)
    case invalidProfileIdentity
    case generationOverflow
    case snapshotAlreadyExists(String)
    case invalidManifest
    case snapshotMissing(String)
    case digestMismatch
    case identityMismatch
}

public final class ActiveProfileSnapshotStore {
    public static let manifestFileName = "active-profile-manifest.json"
    public static let snapshotsDirectoryName = "snapshots"

    public let rootURL: URL

    private let validator: ProfileValidator
    private let fileManager: FileManager
    private let manifestURL: URL
    private let snapshotsURL: URL

    public init(
        rootURL: URL,
        validator: @escaping ProfileValidator,
        fileManager: FileManager = .default
    ) throws {
        self.rootURL = rootURL
        self.validator = validator
        self.fileManager = fileManager
        self.manifestURL = rootURL.appendingPathComponent(Self.manifestFileName)
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
    public func publish(_ data: Data) throws -> ActiveProfileManifest {
        let validation = validator(data)
        guard validation.valid else {
            throw ActiveProfileSnapshotStoreError.validationFailed(
                code: validation.errorCode,
                detail: validation.detail
            )
        }

        let identity = try Self.profileIdentity(in: data)
        let generation = try nextGeneration()
        let digest = Self.sha256Hex(data)
        let snapshotFile = "profile-\(generation)-\(digest).json"
        let snapshotURL = snapshotsURL.appendingPathComponent(snapshotFile)

        guard !fileManager.fileExists(atPath: snapshotURL.path) else {
            throw ActiveProfileSnapshotStoreError.snapshotAlreadyExists(snapshotFile)
        }

        try data.write(to: snapshotURL, options: .atomic)

        let manifest = ActiveProfileManifest(
            profileID: identity.id,
            schema: identity.schema,
            generation: generation,
            digest: digest,
            snapshotFile: snapshotFile
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        return manifest
    }

    public func activeManifest() throws -> ActiveProfileManifest? {
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: manifestURL)
        do {
            return try JSONDecoder().decode(ActiveProfileManifest.self, from: data)
        } catch {
            throw ActiveProfileSnapshotStoreError.invalidManifest
        }
    }

    public func readActive() throws -> ActiveProfileSnapshot? {
        guard let manifest = try activeManifest() else {
            return nil
        }

        guard Self.isSafeSnapshotFileName(manifest.snapshotFile) else {
            throw ActiveProfileSnapshotStoreError.invalidManifest
        }

        let snapshotURL = snapshotsURL.appendingPathComponent(manifest.snapshotFile)
        guard fileManager.fileExists(atPath: snapshotURL.path) else {
            throw ActiveProfileSnapshotStoreError.snapshotMissing(manifest.snapshotFile)
        }

        let data = try Data(contentsOf: snapshotURL)
        guard Self.sha256Hex(data) == manifest.digest else {
            throw ActiveProfileSnapshotStoreError.digestMismatch
        }

        let validation = validator(data)
        guard validation.valid else {
            throw ActiveProfileSnapshotStoreError.validationFailed(
                code: validation.errorCode,
                detail: validation.detail
            )
        }

        let identity = try Self.profileIdentity(in: data)
        guard identity.id == manifest.profileID, identity.schema == manifest.schema else {
            throw ActiveProfileSnapshotStoreError.identityMismatch
        }

        return ActiveProfileSnapshot(manifest: manifest, data: data)
    }

    public func snapshotURL(for manifest: ActiveProfileManifest) throws -> URL {
        guard Self.isSafeSnapshotFileName(manifest.snapshotFile) else {
            throw ActiveProfileSnapshotStoreError.invalidManifest
        }
        return snapshotsURL.appendingPathComponent(manifest.snapshotFile)
    }

    private func nextGeneration() throws -> UInt64 {
        var greatest = try activeManifest()?.generation ?? 0

        let snapshotFiles = try fileManager.contentsOfDirectory(
            at: snapshotsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for url in snapshotFiles {
            let name = url.lastPathComponent
            guard name.hasPrefix("profile-"), name.hasSuffix(".json") else {
                continue
            }
            let withoutPrefix = name.dropFirst("profile-".count)
            guard let separator = withoutPrefix.firstIndex(of: "-") else {
                continue
            }
            let generationText = withoutPrefix[..<separator]
            if let value = UInt64(generationText) {
                greatest = max(greatest, value)
            }
        }

        guard greatest < UInt64.max else {
            throw ActiveProfileSnapshotStoreError.generationOverflow
        }
        return greatest + 1
    }

    private static func profileIdentity(in data: Data) throws -> (id: String, schema: String) {
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = object["id"] as? String,
            !id.isEmpty,
            let schema = object["schema"] as? String,
            !schema.isEmpty
        else {
            throw ActiveProfileSnapshotStoreError.invalidProfileIdentity
        }
        return (id, schema)
    }

    private static func isSafeSnapshotFileName(_ value: String) -> Bool {
        guard !value.isEmpty, value == URL(fileURLWithPath: value).lastPathComponent else {
            return false
        }
        return value.hasPrefix("profile-") && value.hasSuffix(".json")
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

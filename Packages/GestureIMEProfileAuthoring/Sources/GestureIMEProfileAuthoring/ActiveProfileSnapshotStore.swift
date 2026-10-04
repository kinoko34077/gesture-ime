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
    public static let fallbackManifestFileName = "last-known-good-profile-manifest.json"
    public static let snapshotsDirectoryName = "snapshots"

    public let rootURL: URL

    private let validator: ProfileValidator
    private let fileManager: FileManager
    private let manifestURL: URL
    private let fallbackManifestURL: URL
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
        let digest = ProfileSnapshotDigest.sha256Hex(data)
        let snapshotFile = Self.snapshotFileName(generation: generation, digest: digest)
        let snapshotURL = snapshotsURL.appendingPathComponent(snapshotFile)

        guard !fileManager.fileExists(atPath: snapshotURL.path) else {
            throw ActiveProfileSnapshotStoreError.snapshotAlreadyExists(snapshotFile)
        }

        // Candidate bytes are immutable and durable before they become active.
        try data.write(to: snapshotURL, options: .atomic)

        let manifest = ActiveProfileManifest(
            profileID: identity.id,
            schema: identity.schema,
            generation: generation,
            digest: digest,
            snapshotFile: snapshotFile
        )

        // Preserve only a previously published manifest whose referenced snapshot
        // still passes the complete reader checks. Never promote an uncommitted
        // candidate merely because its snapshot file exists.
        var currentForFallback: ActiveProfileManifest?
        do {
            if let currentManifest = try activeManifest() {
                _ = try validatedSnapshot(for: currentManifest)
                currentForFallback = currentManifest
            }
        } catch {
            // A corrupt current active generation must not overwrite an older
            // valid fallback. The new fully validated candidate may still publish.
            currentForFallback = nil
        }

        if let currentForFallback {
            // If preserving a known-good fallback fails at the storage layer,
            // do not advance the active manifest.
            try writeManifest(currentForFallback, to: fallbackManifestURL)
        }

        // Publishing this small record is the final commit point.
        try writeManifest(manifest, to: manifestURL)
        return manifest
    }

    public func activeManifest() throws -> ActiveProfileManifest? {
        try readManifest(at: manifestURL)
    }

    public func readActive() throws -> ActiveProfileSnapshot? {
        guard let manifest = try activeManifest() else {
            return nil
        }
        return try validatedSnapshot(for: manifest)
    }

    public func readLastKnownGood() throws -> ActiveProfileSnapshot? {
        var activeFailure: Error?

        do {
            if let manifest = try activeManifest() {
                return try validatedSnapshot(for: manifest)
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

    public func snapshotURL(for manifest: ActiveProfileManifest) throws -> URL {
        try Self.validateManifestShape(manifest)
        return snapshotsURL.appendingPathComponent(manifest.snapshotFile)
    }

    private func validatedSnapshot(
        for manifest: ActiveProfileManifest
    ) throws -> ActiveProfileSnapshot {
        try Self.validateManifestShape(manifest)

        let snapshotURL = snapshotsURL.appendingPathComponent(manifest.snapshotFile)
        guard fileManager.fileExists(atPath: snapshotURL.path) else {
            throw ActiveProfileSnapshotStoreError.snapshotMissing(manifest.snapshotFile)
        }

        let data = try Data(contentsOf: snapshotURL)
        guard ProfileSnapshotDigest.sha256Hex(data) == manifest.digest else {
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

    private func readManifest(at url: URL) throws -> ActiveProfileManifest? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let manifest: ActiveProfileManifest
        do {
            manifest = try JSONDecoder().decode(ActiveProfileManifest.self, from: data)
        } catch {
            throw ActiveProfileSnapshotStoreError.invalidManifest
        }

        try Self.validateManifestShape(manifest)
        return manifest
    }

    private func writeManifest(_ manifest: ActiveProfileManifest, to url: URL) throws {
        try Self.validateManifestShape(manifest)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: url, options: .atomic)
    }

    private func nextGeneration() throws -> UInt64 {
        var greatest: UInt64 = 0

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

    private static func validateManifestShape(_ manifest: ActiveProfileManifest) throws {
        guard
            !manifest.profileID.isEmpty,
            !manifest.schema.isEmpty,
            manifest.generation > 0,
            isLowercaseSHA256(manifest.digest),
            manifest.snapshotFile
                == snapshotFileName(generation: manifest.generation, digest: manifest.digest)
        else {
            throw ActiveProfileSnapshotStoreError.invalidManifest
        }
    }

    private static func snapshotFileName(generation: UInt64, digest: String) -> String {
        "profile-\(generation)-\(digest).json"
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        guard value.utf8.count == 64 else {
            return false
        }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}

enum ProfileSnapshotDigest {
    private static let initialHash: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ]

    private static let constants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    static func sha256Hex(_ data: Data) -> String {
        let digest = hash(data)
        let alphabet = Array("0123456789abcdef".utf8)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(digest.count * 2)

        for byte in digest {
            bytes.append(alphabet[Int(byte >> 4)])
            bytes.append(alphabet[Int(byte & 0x0f)])
        }

        return String(decoding: bytes, as: UTF8.self)
    }

    private static func hash(_ data: Data) -> [UInt8] {
        var message = Array(data)
        let bitLength = UInt64(message.count) * 8

        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0)
        }

        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }

        var hash = initialHash

        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            var words = [UInt32](repeating: 0, count: 64)

            for index in 0..<16 {
                let offset = chunkStart + index * 4
                words[index] =
                    (UInt32(message[offset]) << 24)
                    | (UInt32(message[offset + 1]) << 16)
                    | (UInt32(message[offset + 2]) << 8)
                    | UInt32(message[offset + 3])
            }

            for index in 16..<64 {
                let s0 =
                    rotateRight(words[index - 15], by: 7)
                    ^ rotateRight(words[index - 15], by: 18)
                    ^ (words[index - 15] >> 3)
                let s1 =
                    rotateRight(words[index - 2], by: 17)
                    ^ rotateRight(words[index - 2], by: 19)
                    ^ (words[index - 2] >> 10)

                words[index] =
                    words[index - 16]
                    &+ s0
                    &+ words[index - 7]
                    &+ s1
            }

            var a = hash[0]
            var b = hash[1]
            var c = hash[2]
            var d = hash[3]
            var e = hash[4]
            var f = hash[5]
            var g = hash[6]
            var h = hash[7]

            for index in 0..<64 {
                let sum1 =
                    rotateRight(e, by: 6)
                    ^ rotateRight(e, by: 11)
                    ^ rotateRight(e, by: 25)
                let choose = (e & f) ^ ((~e) & g)
                let temp1 = h &+ sum1 &+ choose &+ constants[index] &+ words[index]
                let sum0 =
                    rotateRight(a, by: 2)
                    ^ rotateRight(a, by: 13)
                    ^ rotateRight(a, by: 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = sum0 &+ majority

                h = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }

            hash[0] = hash[0] &+ a
            hash[1] = hash[1] &+ b
            hash[2] = hash[2] &+ c
            hash[3] = hash[3] &+ d
            hash[4] = hash[4] &+ e
            hash[5] = hash[5] &+ f
            hash[6] = hash[6] &+ g
            hash[7] = hash[7] &+ h
        }

        return hash.flatMap { word in
            [
                UInt8((word >> 24) & 0xff),
                UInt8((word >> 16) & 0xff),
                UInt8((word >> 8) & 0xff),
                UInt8(word & 0xff)
            ]
        }
    }

    private static func rotateRight(_ value: UInt32, by amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }
}

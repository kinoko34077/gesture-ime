import Foundation

public final class ProfileStore {
    private struct Manifest: Codable {
        var activeProfileID: String?
    }

    public let rootURL: URL
    private let validator: ProfileValidator
    private let fileManager: FileManager
    private let manifestURL: URL

    public init(
        rootURL: URL,
        validator: @escaping ProfileValidator,
        fileManager: FileManager = .default
    ) throws {
        self.rootURL = rootURL
        self.validator = validator
        self.fileManager = fileManager
        self.manifestURL = rootURL.appendingPathComponent("manifest.json")
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    public func list() throws -> [ProfileSummary] {
        let urls = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return try urls
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "manifest.json" }
            .compactMap { url -> ProfileSummary? in
                let data = try Data(contentsOf: url)
                return try ProfileDocument(data: data).summary
            }
            .sorted { lhs, rhs in lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
    }

    public func load(id: String) throws -> ProfileDocument {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw ProfileAuthoringError.profileNotFound(id)
        }
        return try ProfileDocument(data: Data(contentsOf: url))
    }

    @discardableResult
    public func importProfile(_ data: Data, replaceExisting: Bool = false) throws -> ProfileSummary {
        let validation = validator(data)
        guard validation.valid else {
            throw ProfileAuthoringError.validationFailed(
                code: validation.errorCode,
                detail: validation.detail
            )
        }

        let document = try ProfileDocument(data: data)
        let summary = document.summary
        guard !summary.id.isEmpty else { throw ProfileAuthoringError.missingField("id") }

        let url = fileURL(for: summary.id)
        if fileManager.fileExists(atPath: url.path) && !replaceExisting {
            throw ProfileAuthoringError.duplicateProfile(summary.id)
        }

        try document.encoded(pretty: true).write(to: url, options: .atomic)
        return summary
    }

    @discardableResult
    public func save(_ document: ProfileDocument) throws -> ProfileSummary {
        let data = try document.encoded(pretty: true)
        let validation = validator(data)
        guard validation.valid else {
            throw ProfileAuthoringError.validationFailed(
                code: validation.errorCode,
                detail: validation.detail
            )
        }

        let summary = document.summary
        guard !summary.id.isEmpty else { throw ProfileAuthoringError.missingField("id") }
        try data.write(to: fileURL(for: summary.id), options: .atomic)
        return summary
    }

    public func clone(
        source: ProfileDocument,
        id: String,
        name: String
    ) throws -> ProfileSummary {
        var copy = source
        try copy.cloneIdentity(id: id, name: name)
        return try save(copy)
    }

    public func delete(id: String) throws {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
        if try activeProfileID() == id {
            try setActiveProfileID(nil)
        }
    }

    public func validate(_ document: ProfileDocument) throws -> ProfileValidation {
        validator(try document.encoded(pretty: false))
    }

    public func fileURL(for id: String) -> URL {
        rootURL.appendingPathComponent(Self.safeFileName(id)).appendingPathExtension("json")
    }

    public func activeProfileID() throws -> String? {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }
        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder().decode(Manifest.self, from: data).activeProfileID
    }

    public func setActiveProfileID(_ id: String?) throws {
        if let id {
            guard fileManager.fileExists(atPath: fileURL(for: id).path) else {
                throw ProfileAuthoringError.profileNotFound(id)
            }
        }
        let data = try JSONEncoder().encode(Manifest(activeProfileID: id))
        try data.write(to: manifestURL, options: .atomic)
    }

    private static func safeFileName(_ id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return id.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
            .reduce(into: "") { $0.append($1) }
    }
}

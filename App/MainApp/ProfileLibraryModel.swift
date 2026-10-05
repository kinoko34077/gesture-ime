import Foundation
import Combine
import GestureIMEProfileAuthoring
import GestureIMEProductSettings

@MainActor
final class ProfileLibraryModel: ObservableObject {
    @Published private(set) var profiles: [ProfileSummary] = []
    @Published private(set) var activeProfileID: String?
    @Published var errorMessage: String?

    private(set) var store: ProfileStore?
    private(set) var builtInProfile: ProfileDocument?
    @Published private(set) var profileDeliveryStatus =
        "App Group の共有領域を確認しています。"

    private var sharedProfileReader: ActiveProfileSnapshotReader?
    private var sharedProfileWriter: ActiveProfileSnapshotWriter?

    init() {
        do {
            let fileManager = FileManager.default
            let base = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let root = base
                .appendingPathComponent("GestureIME", isDirectory: true)
                .appendingPathComponent("Profiles", isDirectory: true)

            store = try ProfileStore(
                rootURL: root,
                validator: SharedRuntimeProfileValidator.validate
            )

            guard let builtInURL = Bundle.main.url(forResource: "default-ja", withExtension: "json") else {
                throw ProfileAuthoringError.missingReference("default-ja.json")
            }
            builtInProfile = try ProfileDocument(data: Data(contentsOf: builtInURL))
            try bootstrapIfNeeded()
            try reload()
            configureSharedProfileDelivery()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() throws {
        guard let store else { return }
        profiles = try store.list()
        activeProfileID = try store.activeProfileID()
    }

    func createFromBuiltIn() {
        guard let store, let builtInProfile else { return }
        do {
            let suffix = Int(Date().timeIntervalSince1970)
            _ = try store.clone(
                source: builtInProfile,
                id: "user.profile.\(suffix)",
                name: "新しいプロファイル"
            )
            try reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createEmptyV3() {
        guard let store else { return }
        do {
            let suffix = Int(Date().timeIntervalSince1970 * 1000)
            let document = try ProfileDocument.emptyV3(
                id: "user.v3.\(suffix)",
                name: "新しいv3プロファイル"
            )
            _ = try store.save(document)
            try reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func isProfileV3(profileID: String) -> Bool {
        (try? document(id: profileID).isProfileV3) == true
    }

    func clone(profileID: String) {
        guard let store else { return }
        do {
            let source = try store.load(id: profileID)
            let suffix = Int(Date().timeIntervalSince1970)
            _ = try store.clone(
                source: source,
                id: "user.clone.\(suffix)",
                name: source.summary.name + " のコピー"
            )
            try reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(profileID: String) {
        guard let store else { return }
        do {
            try store.delete(id: profileID)
            try reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setActive(profileID: String) {
        guard let store else { return }
        do {
            let document = try store.load(id: profileID)
            try publishSharedProfile(document, requireAvailable: true)
            try store.setActiveProfileID(profileID)
            try reload()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importProfile(from url: URL) {
        guard let store else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            _ = try store.importProfile(data)
            try reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }


    func migrateToV2(profileID: String) {
        guard let store else { return }
        do {
            let source = try store.load(id: profileID)
            let sourceData = try source.encoded(pretty: true)
            let migrated = try SharedRuntimeProfileValidator.migrateToV2(sourceData)
            _ = try store.importProfile(migrated, replaceExisting: true)
            try reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func document(id: String) throws -> ProfileDocument {
        guard let store else {
            throw ProfileAuthoringError.profileNotFound(id)
        }
        return try store.load(id: id)
    }

    func save(_ document: ProfileDocument) throws {
        guard let store else { return }
        let summary = try store.save(document)
        try reload()

        guard activeProfileID == summary.id else { return }
        do {
            try publishSharedProfile(document, requireAvailable: true)
        } catch {
            throw ProfileLibraryDeliveryError.localSaveSucceededButDeliveryFailed(
                error.localizedDescription
            )
        }
    }

    func validate(_ document: ProfileDocument) throws -> ProfileValidation {
        guard let store else {
            return ProfileValidation(valid: false, errorCode: "STORE", detail: "Store unavailable")
        }
        return try store.validate(document)
    }

    func exportURL(profileID: String) -> URL? {
        store?.fileURL(for: profileID)
    }

    private func configureSharedProfileDelivery() {
        switch GestureIMEAppGroupResolver.resolveMainBundle() {
        case .available(let paths):
            do {
                sharedProfileReader = try ActiveProfileSnapshotReader(
                    rootURL: paths.profileDeliveryRootURL,
                    validator: SharedRuntimeProfileValidator.validate
                )
                sharedProfileWriter = try ActiveProfileSnapshotWriter(
                    rootURL: paths.profileDeliveryRootURL,
                    validator: SharedRuntimeProfileValidator.validate
                )
                try synchronizeActiveProfileIfNeeded()
                profileDeliveryStatus = "使用中のキーボードは共有領域を通じてキーボード本体へ反映されます。"
            } catch {
                sharedProfileReader = nil
                sharedProfileWriter = nil
                profileDeliveryStatus = "共有領域の初期化に失敗しました: \(error.localizedDescription)"
            }
        case .unavailable(let reason):
            sharedProfileReader = nil
            sharedProfileWriter = nil
            profileDeliveryStatus = reason.japaneseReason
        }
    }

    private func synchronizeActiveProfileIfNeeded() throws {
        guard let store,
              let profileID = activeProfileID,
              let writer = sharedProfileWriter else {
            return
        }

        let document = try store.load(id: profileID)
        let data = try document.encoded(pretty: false)

        if let reader = sharedProfileReader {
            let current: ActiveProfileSnapshot?
            do {
                current = try reader.readLastKnownGood()
            } catch {
                current = nil
            }
            if let current,
               current.manifest.profileID == profileID,
               current.data == data {
                return
            }
        }

        _ = try writer.publish(data)
    }

    private func publishSharedProfile(
        _ document: ProfileDocument,
        requireAvailable: Bool
    ) throws {
        guard let writer = sharedProfileWriter else {
            if requireAvailable {
                throw ProfileLibraryDeliveryError.sharedContainerUnavailable(
                    profileDeliveryStatus
                )
            }
            return
        }
        _ = try writer.publish(try document.encoded(pretty: false))
    }

    private func bootstrapIfNeeded() throws {
        guard let store, let builtInProfile, try store.list().isEmpty else { return }
        _ = try store.clone(
            source: builtInProfile,
            id: "user.default",
            name: "標準プロファイル"
        )
        try store.setActiveProfileID("user.default")
    }
}


private enum ProfileLibraryDeliveryError: LocalizedError {
    case sharedContainerUnavailable(String)
    case localSaveSucceededButDeliveryFailed(String)

    var errorDescription: String? {
        switch self {
        case .sharedContainerUnavailable(let reason):
            return "キーボード本体へ反映できません。\(reason)"
        case .localSaveSucceededButDeliveryFailed(let detail):
            return "プロファイルはアプリ内に保存されましたが、キーボード本体への反映に失敗しました。\(detail)"
        }
    }
}

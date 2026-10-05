import Foundation

public struct AppGroupRuntimeDiagnostics: Equatable, Sendable {
    public enum Classification: String, Equatable, Sendable {
        case appGroupNotConfigured
        case signingEvidenceUnreadable
        case signedAppGroupEntitlementMissing
        case provisionedAppGroupEntitlementMissing
        case signedProvisioningMismatch
        case configuredGroupResolved
        case configuredGroupSignedButContainerUnavailable
        case configuredGroupProvisionedButContainerUnavailable
        case signedGroupDiffersAndResolves
        case signedGroupDiffersAndUnavailable
        case provisionedGroupDiffersAndResolves
        case provisionedGroupDiffersAndUnavailable
    }

    public let bundleIdentifier: String?
    public let configuredGroupIdentifier: String?
    public let signedEntitlementsReadable: Bool
    public let provisionedEntitlementsReadable: Bool
    public let signedApplicationGroups: [String]
    public let provisionedApplicationGroups: [String]
    public let signedApplicationIdentifier: String?
    public let provisionedApplicationIdentifier: String?
    public let signedTeamIdentifier: String?
    public let provisionedTeamIdentifier: String?
    public let groupContainerAvailability: [String: Bool]

    public init(
        bundleIdentifier: String?,
        configuredGroupIdentifier: String?,
        signedEntitlementsReadable: Bool,
        provisionedEntitlementsReadable: Bool,
        signedApplicationGroups: [String],
        provisionedApplicationGroups: [String],
        signedApplicationIdentifier: String?,
        provisionedApplicationIdentifier: String?,
        signedTeamIdentifier: String?,
        provisionedTeamIdentifier: String?,
        groupContainerAvailability: [String: Bool]
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.configuredGroupIdentifier = configuredGroupIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.signedEntitlementsReadable = signedEntitlementsReadable
        self.provisionedEntitlementsReadable = provisionedEntitlementsReadable
        self.signedApplicationGroups = Self.normalized(signedApplicationGroups)
        self.provisionedApplicationGroups = Self.normalized(
            provisionedApplicationGroups
        )
        self.signedApplicationIdentifier = signedApplicationIdentifier
        self.provisionedApplicationIdentifier = provisionedApplicationIdentifier
        self.signedTeamIdentifier = signedTeamIdentifier
        self.provisionedTeamIdentifier = provisionedTeamIdentifier
        self.groupContainerAvailability = groupContainerAvailability
    }

    public var classification: Classification {
        guard let configuredGroupIdentifier,
              !configuredGroupIdentifier.isEmpty else {
            return .appGroupNotConfigured
        }

        if groupContainerAvailability[configuredGroupIdentifier] == true {
            return .configuredGroupResolved
        }

        if signedEntitlementsReadable {
            if signedApplicationGroups.contains(configuredGroupIdentifier) {
                if provisionedEntitlementsReadable,
                   !provisionedApplicationGroups.contains(configuredGroupIdentifier) {
                    return .signedProvisioningMismatch
                }
                return .configuredGroupSignedButContainerUnavailable
            }

            if signedApplicationGroups.isEmpty {
                return .signedAppGroupEntitlementMissing
            }

            if signedApplicationGroups.contains(where: {
                groupContainerAvailability[$0] == true
            }) {
                return .signedGroupDiffersAndResolves
            }
            return .signedGroupDiffersAndUnavailable
        }

        if provisionedEntitlementsReadable {
            if provisionedApplicationGroups.contains(configuredGroupIdentifier) {
                return .configuredGroupProvisionedButContainerUnavailable
            }

            if provisionedApplicationGroups.isEmpty {
                return .provisionedAppGroupEntitlementMissing
            }

            if provisionedApplicationGroups.contains(where: {
                groupContainerAvailability[$0] == true
            }) {
                return .provisionedGroupDiffersAndResolves
            }
            return .provisionedGroupDiffersAndUnavailable
        }

        return .signingEvidenceUnreadable
    }

    public var configuredContainerAvailable: Bool {
        guard let configuredGroupIdentifier else { return false }
        return groupContainerAvailability[configuredGroupIdentifier] == true
    }

    public var japaneseDiagnosis: String {
        switch classification {
        case .appGroupNotConfigured:
            return "Info.plist に App Group ID が設定されていません。"
        case .signingEvidenceUnreadable:
            return "実行ファイルの署名 entitlement と provisioning profile を読み取れません。"
        case .signedAppGroupEntitlementMissing:
            return "最終署名の application-groups entitlement がありません。再署名時に削除された可能性があります。"
        case .provisionedAppGroupEntitlementMissing:
            return "provisioning profile に application-groups entitlement がありません。"
        case .signedProvisioningMismatch:
            return "最終署名には設定App Groupがありますが、provisioning profile側の許可と一致しません。"
        case .configuredGroupResolved:
            return "設定IDと共有コンテナ解決が一致しています。"
        case .configuredGroupSignedButContainerUnavailable:
            return "設定IDは最終署名 entitlement に存在しますが、共有コンテナを解決できません。"
        case .configuredGroupProvisionedButContainerUnavailable:
            return "設定IDは provisioning profile に存在しますが、共有コンテナを解決できません。最終署名 entitlement は読み取れませんでした。"
        case .signedGroupDiffersAndResolves:
            return "最終署名の App Group ID が設定IDと異なり、その実効Groupは解決できます。再署名時のID書換え候補です。"
        case .signedGroupDiffersAndUnavailable:
            return "最終署名の App Group ID が設定IDと異なり、確認できた署名Groupも解決できません。"
        case .provisionedGroupDiffersAndResolves:
            return "provisioning profile の App Group ID が設定IDと異なり、そのGroupは解決できます。再署名時のID書換え候補です。"
        case .provisionedGroupDiffersAndUnavailable:
            return "provisioning profile の App Group ID が設定IDと異なり、確認できたGroupも解決できません。"
        }
    }

    public var report: String {
        let signedGroups = signedApplicationGroups.isEmpty
            ? "(none)"
            : signedApplicationGroups.joined(separator: ", ")
        let provisionedGroups = provisionedApplicationGroups.isEmpty
            ? "(none)"
            : provisionedApplicationGroups.joined(separator: ", ")

        var lines = [
            "classification=\(classification.rawValue)",
            "diagnosis=\(japaneseDiagnosis)",
            "bundleIdentifier=\(bundleIdentifier ?? "(nil)")",
            "configuredGroup=\(configuredGroupIdentifier ?? "(nil)")",
            "signedEntitlementsReadable=\(signedEntitlementsReadable ? "YES" : "NO")",
            "signedApplicationGroups=\(signedGroups)",
            "provisionedEntitlementsReadable=\(provisionedEntitlementsReadable ? "YES" : "NO")",
            "provisionedApplicationGroups=\(provisionedGroups)",
            "configuredContainerAvailable=\(configuredContainerAvailable ? "YES" : "NO")",
            "signedApplicationIdentifier=\(signedApplicationIdentifier ?? "(nil)")",
            "provisionedApplicationIdentifier=\(provisionedApplicationIdentifier ?? "(nil)")",
            "signedTeamIdentifier=\(signedTeamIdentifier ?? "(nil)")",
            "provisionedTeamIdentifier=\(provisionedTeamIdentifier ?? "(nil)")"
        ]

        for group in groupContainerAvailability.keys.sorted() {
            lines.append(
                "container[\(group)]=\(groupContainerAvailability[group] == true ? "YES" : "NO")"
            )
        }
        return lines.joined(separator: "\n")
    }

    private static func normalized(_ values: [String]) -> [String] {
        Array(Set(values.filter { !$0.isEmpty })).sorted()
    }
}

public enum AppGroupRuntimeDiagnosticsProbe {
    private static let cachedMainBundleDiagnostics: AppGroupRuntimeDiagnostics = {
        capture(bundle: .main)
    }()

    public static func captureMainBundle() -> AppGroupRuntimeDiagnostics {
        cachedMainBundleDiagnostics
    }

    private static func capture(
        bundle: Bundle
    ) -> AppGroupRuntimeDiagnostics {
        let configured = bundle.object(
            forInfoDictionaryKey: GestureIMEAppGroupResolver.appGroupInfoKey
        ) as? String

        let signedEntitlements: [String: Any]? = bundle.executableURL
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { RuntimeSigningEvidenceParser.codeSignatureEntitlements(
                executableData: $0
            ) }

        let profileURL = bundle.bundleURL.appendingPathComponent(
            "embedded.mobileprovision",
            isDirectory: false
        )
        let provisionedEntitlements: [String: Any]? =
            (try? Data(contentsOf: profileURL))
                .flatMap { RuntimeSigningEvidenceParser.provisioningEntitlements(
                    profileData: $0
                ) }

        return makeSnapshot(
            bundleIdentifier: bundle.bundleIdentifier,
            configuredGroupIdentifier: configured,
            signedEntitlements: signedEntitlements,
            provisionedEntitlements: provisionedEntitlements
        )
    }

    public static func makeSnapshot(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        configuredGroupIdentifier: String?,
        signedEntitlements: [String: Any]?,
        provisionedEntitlements: [String: Any]?,
        containerURL: (String) -> URL? = { group in
            #if os(iOS) || os(macOS)
            FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: group
            )
            #else
            nil
            #endif
        }
    ) -> AppGroupRuntimeDiagnostics {
        let configured = configuredGroupIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let signedGroups = stringArray(
            signedEntitlements?["com.apple.security.application-groups"]
        )
        let provisionedGroups = stringArray(
            provisionedEntitlements?["com.apple.security.application-groups"]
        )

        var candidates = Set(signedGroups + provisionedGroups)
        if let configured, !configured.isEmpty {
            candidates.insert(configured)
        }

        let availability = Dictionary(
            uniqueKeysWithValues: candidates.sorted().map {
                ($0, containerURL($0) != nil)
            }
        )

        return AppGroupRuntimeDiagnostics(
            bundleIdentifier: bundleIdentifier,
            configuredGroupIdentifier: configured,
            signedEntitlementsReadable: signedEntitlements != nil,
            provisionedEntitlementsReadable: provisionedEntitlements != nil,
            signedApplicationGroups: signedGroups,
            provisionedApplicationGroups: provisionedGroups,
            signedApplicationIdentifier:
                stringValue(signedEntitlements?["application-identifier"])
                ?? stringValue(
                    signedEntitlements?["com.apple.application-identifier"]
                ),
            provisionedApplicationIdentifier:
                stringValue(provisionedEntitlements?["application-identifier"])
                ?? stringValue(
                    provisionedEntitlements?["com.apple.application-identifier"]
                ),
            signedTeamIdentifier: stringValue(
                signedEntitlements?["com.apple.developer.team-identifier"]
            ),
            provisionedTeamIdentifier: stringValue(
                provisionedEntitlements?["com.apple.developer.team-identifier"]
            ),
            groupContainerAvailability: availability
        )
    }

    private static func stringArray(_ value: Any?) -> [String] {
        if let strings = value as? [String] {
            return strings
        }
        if let array = value as? NSArray {
            return array.compactMap { $0 as? String }
        }
        return []
    }

    private static func stringValue(_ value: Any?) -> String? {
        value as? String
    }
}

enum RuntimeSigningEvidenceParser {
    private static let mhMagic = UInt32(0xfeedface)
    private static let mhMagic64 = UInt32(0xfeedfacf)
    private static let fatMagic = UInt32(0xcafebabe)
    private static let fatMagic64 = UInt32(0xcafebabf)
    private static let lcCodeSignature = UInt32(0x1d)
    private static let csMagicEmbeddedSignature = UInt32(0xfade0cc0)
    private static let csMagicEntitlements = UInt32(0xfade7171)
    private static let csSlotEntitlements = UInt32(5)

    static func codeSignatureEntitlements(
        executableData data: Data
    ) -> [String: Any]? {
        for sliceBase in machoSliceBases(data) {
            guard let signatureOffset = codeSignatureOffset(
                data,
                sliceBase: sliceBase
            ) else {
                continue
            }
            if let entitlements = entitlementsFromSuperBlob(
                data,
                signatureOffset: signatureOffset
            ) {
                return entitlements
            }
        }
        return nil
    }

    static func provisioningEntitlements(
        profileData data: Data
    ) -> [String: Any]? {
        let xmlStartMarker = Data("<?xml".utf8)
        let plistEndMarker = Data("</plist>".utf8)
        guard let start = data.range(of: xmlStartMarker)?.lowerBound else {
            return nil
        }
        let tail = data[start..<data.endIndex]
        guard let relativeEnd = tail.range(of: plistEndMarker) else {
            return nil
        }
        let xml = Data(data[start..<relativeEnd.upperBound])
        guard let object = try? PropertyListSerialization.propertyList(
            from: xml,
            options: [],
            format: nil
        ),
              let root = object as? [String: Any],
              let entitlements = root["Entitlements"] as? [String: Any] else {
            return nil
        }
        return entitlements
    }

    private static func machoSliceBases(_ data: Data) -> [Int] {
        guard data.count >= 4 else { return [] }
        let magicBE = readUInt32BE(data, at: 0)

        if magicBE == fatMagic {
            guard let countValue = readUInt32BE(data, at: 4) else { return [] }
            let count = Int(countValue)
            guard count >= 0, count <= 64 else { return [] }

            var bases: [Int] = []
            for index in 0..<count {
                let arch = 8 + index * 20
                guard let offset = readUInt32BE(data, at: arch + 8) else {
                    return []
                }
                let base = Int(offset)
                if base >= 0, base + 4 <= data.count {
                    bases.append(base)
                }
            }
            return bases
        }

        if magicBE == fatMagic64 {
            guard let countValue = readUInt32BE(data, at: 4) else { return [] }
            let count = Int(countValue)
            guard count >= 0, count <= 64 else { return [] }

            var bases: [Int] = []
            for index in 0..<count {
                let arch = 8 + index * 32
                guard let offset = readUInt64BE(data, at: arch + 8),
                      offset <= UInt64(Int.max) else {
                    return []
                }
                let base = Int(offset)
                if base >= 0, base + 4 <= data.count {
                    bases.append(base)
                }
            }
            return bases
        }

        return [0]
    }

    private static func codeSignatureOffset(
        _ data: Data,
        sliceBase: Int
    ) -> Int? {
        guard let magic = readUInt32LE(data, at: sliceBase) else {
            return nil
        }

        let headerSize: Int
        switch magic {
        case mhMagic:
            headerSize = 28
        case mhMagic64:
            headerSize = 32
        default:
            return nil
        }

        guard let commandCountValue = readUInt32LE(
            data,
            at: sliceBase + 16
        ) else {
            return nil
        }
        let commandCount = Int(commandCountValue)
        guard commandCount >= 0, commandCount <= 65_536 else {
            return nil
        }

        var cursor = sliceBase + headerSize
        for _ in 0..<commandCount {
            guard let command = readUInt32LE(data, at: cursor),
                  let commandSizeValue = readUInt32LE(data, at: cursor + 4) else {
                return nil
            }
            let commandSize = Int(commandSizeValue)
            guard commandSize >= 8,
                  cursor <= data.count - commandSize else {
                return nil
            }

            if command == lcCodeSignature {
                guard commandSize >= 16,
                      let dataOffsetValue = readUInt32LE(data, at: cursor + 8),
                      let dataSizeValue = readUInt32LE(data, at: cursor + 12) else {
                    return nil
                }
                let dataOffset = Int(dataOffsetValue)
                let dataSize = Int(dataSizeValue)

                for candidate in [sliceBase + dataOffset, dataOffset] {
                    guard candidate >= 0,
                          dataSize >= 12,
                          candidate <= data.count - dataSize,
                          readUInt32BE(data, at: candidate)
                            == csMagicEmbeddedSignature else {
                        continue
                    }
                    return candidate
                }
                return nil
            }

            cursor += commandSize
        }
        return nil
    }

    private static func entitlementsFromSuperBlob(
        _ data: Data,
        signatureOffset: Int
    ) -> [String: Any]? {
        guard readUInt32BE(data, at: signatureOffset)
                == csMagicEmbeddedSignature,
              let totalLengthValue = readUInt32BE(
                data,
                at: signatureOffset + 4
              ),
              let countValue = readUInt32BE(
                data,
                at: signatureOffset + 8
              ) else {
            return nil
        }

        let totalLength = Int(totalLengthValue)
        let count = Int(countValue)
        guard totalLength >= 12,
              signatureOffset <= data.count - totalLength,
              count >= 0,
              count <= 1024,
              12 + count * 8 <= totalLength else {
            return nil
        }

        for index in 0..<count {
            let entry = signatureOffset + 12 + index * 8
            guard let slot = readUInt32BE(data, at: entry),
                  let relativeOffsetValue = readUInt32BE(
                    data,
                    at: entry + 4
                  ) else {
                return nil
            }
            guard slot == csSlotEntitlements else { continue }

            let blobOffset = signatureOffset + Int(relativeOffsetValue)
            guard blobOffset >= signatureOffset,
                  blobOffset + 8 <= signatureOffset + totalLength,
                  readUInt32BE(data, at: blobOffset) == csMagicEntitlements,
                  let blobLengthValue = readUInt32BE(
                    data,
                    at: blobOffset + 4
                  ) else {
                return nil
            }

            let blobLength = Int(blobLengthValue)
            guard blobLength >= 8,
                  blobOffset <= data.count - blobLength,
                  blobOffset + blobLength <= signatureOffset + totalLength else {
                return nil
            }

            var payload = Data(
                data[(blobOffset + 8)..<(blobOffset + blobLength)]
            )
            while payload.last == 0 {
                payload.removeLast()
            }

            guard let object = try? PropertyListSerialization.propertyList(
                from: payload,
                options: [],
                format: nil
            ) else {
                return nil
            }
            return object as? [String: Any]
        }

        return nil
    }

    private static func readUInt32LE(
        _ data: Data,
        at offset: Int
    ) -> UInt32? {
        guard offset >= 0, offset <= data.count - 4 else { return nil }
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }

    private static func readUInt32BE(
        _ data: Data,
        at offset: Int
    ) -> UInt32? {
        guard offset >= 0, offset <= data.count - 4 else { return nil }
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }

    private static func readUInt64BE(
        _ data: Data,
        at offset: Int
    ) -> UInt64? {
        guard offset >= 0, offset <= data.count - 8 else { return nil }
        var value: UInt64 = 0
        for index in 0..<8 {
            value = (value << 8) | UInt64(data[offset + index])
        }
        return value
    }
}

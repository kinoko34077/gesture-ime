import Foundation

#if canImport(Security)
import Security
#endif

public struct AppGroupRuntimeDiagnostics: Equatable, Sendable {
    public enum Classification: String, Equatable, Sendable {
        case appGroupNotConfigured
        case entitlementQueryUnavailable
        case appGroupEntitlementMissing
        case configuredGroupResolved
        case configuredGroupEntitledButContainerUnavailable
        case effectiveGroupDiffersAndResolves
        case effectiveGroupDiffersAndUnavailable
    }

    public let bundleIdentifier: String?
    public let configuredGroupIdentifier: String?
    public let effectiveApplicationGroups: [String]
    public let applicationIdentifier: String?
    public let teamIdentifier: String?
    public let signingIdentifier: String?
    public let entitlementQueryAvailable: Bool
    public let groupContainerAvailability: [String: Bool]

    public init(
        bundleIdentifier: String?,
        configuredGroupIdentifier: String?,
        effectiveApplicationGroups: [String],
        applicationIdentifier: String?,
        teamIdentifier: String?,
        signingIdentifier: String?,
        entitlementQueryAvailable: Bool,
        groupContainerAvailability: [String: Bool]
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.configuredGroupIdentifier = configuredGroupIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.effectiveApplicationGroups = Array(
            Set(effectiveApplicationGroups.filter { !$0.isEmpty })
        ).sorted()
        self.applicationIdentifier = applicationIdentifier
        self.teamIdentifier = teamIdentifier
        self.signingIdentifier = signingIdentifier
        self.entitlementQueryAvailable = entitlementQueryAvailable
        self.groupContainerAvailability = groupContainerAvailability
    }

    public var classification: Classification {
        guard let configuredGroupIdentifier,
              !configuredGroupIdentifier.isEmpty else {
            return .appGroupNotConfigured
        }
        guard entitlementQueryAvailable else {
            return .entitlementQueryUnavailable
        }
        guard !effectiveApplicationGroups.isEmpty else {
            return .appGroupEntitlementMissing
        }

        if effectiveApplicationGroups.contains(configuredGroupIdentifier) {
            return groupContainerAvailability[configuredGroupIdentifier] == true
                ? .configuredGroupResolved
                : .configuredGroupEntitledButContainerUnavailable
        }

        if effectiveApplicationGroups.contains(where: {
            groupContainerAvailability[$0] == true
        }) {
            return .effectiveGroupDiffersAndResolves
        }
        return .effectiveGroupDiffersAndUnavailable
    }

    public var configuredContainerAvailable: Bool {
        guard let configuredGroupIdentifier else { return false }
        return groupContainerAvailability[configuredGroupIdentifier] == true
    }

    public var japaneseDiagnosis: String {
        switch classification {
        case .appGroupNotConfigured:
            return "Info.plist に App Group ID が設定されていません。"
        case .entitlementQueryUnavailable:
            return "実行中プロセスの署名 entitlement を取得できません。"
        case .appGroupEntitlementMissing:
            return "署名後の application-groups entitlement がありません。"
        case .configuredGroupResolved:
            return "設定ID・署名 entitlement・共有コンテナ解決が一致しています。"
        case .configuredGroupEntitledButContainerUnavailable:
            return "設定IDは署名 entitlement に存在しますが、共有コンテナを解決できません。"
        case .effectiveGroupDiffersAndResolves:
            return "署名後の App Group ID が設定IDと異なり、別の実効Groupは解決できます。再署名時のID書換え候補です。"
        case .effectiveGroupDiffersAndUnavailable:
            return "署名後の App Group ID が設定IDと異なり、確認できた実効Groupも解決できません。"
        }
    }

    public var report: String {
        let groups = effectiveApplicationGroups.isEmpty
            ? "(none)"
            : effectiveApplicationGroups.joined(separator: ", ")
        var lines = [
            "classification=\(classification.rawValue)",
            "diagnosis=\(japaneseDiagnosis)",
            "bundleIdentifier=\(bundleIdentifier ?? "(nil)")",
            "configuredGroup=\(configuredGroupIdentifier ?? "(nil)")",
            "effectiveApplicationGroups=\(groups)",
            "configuredContainerAvailable=\(configuredContainerAvailable ? "YES" : "NO")",
            "applicationIdentifier=\(applicationIdentifier ?? "(nil)")",
            "teamIdentifier=\(teamIdentifier ?? "(nil)")",
            "signingIdentifier=\(signingIdentifier ?? "(nil)")",
            "entitlementQueryAvailable=\(entitlementQueryAvailable ? "YES" : "NO")"
        ]
        for group in groupContainerAvailability.keys.sorted() {
            lines.append(
                "container[\(group)]=\(groupContainerAvailability[group] == true ? "YES" : "NO")"
            )
        }
        return lines.joined(separator: "\n")
    }
}

public enum AppGroupRuntimeDiagnosticsProbe {
    public static func captureMainBundle() -> AppGroupRuntimeDiagnostics {
        let configured = Bundle.main.object(
            forInfoDictionaryKey: GestureIMEAppGroupResolver.appGroupInfoKey
        ) as? String

        #if canImport(Security)
        if let task = SecTaskCreateFromSelf(nil) {
            let groups = entitlementStrings(
                "com.apple.security.application-groups",
                task: task
            )
            let applicationIdentifier =
                entitlementString("application-identifier", task: task)
                ?? entitlementString("com.apple.application-identifier", task: task)
            let teamIdentifier = entitlementString(
                "com.apple.developer.team-identifier",
                task: task
            )
            let signingIdentifier = SecTaskCopySigningIdentifier(task, nil) as String?

            return makeSnapshot(
                configuredGroupIdentifier: configured,
                effectiveApplicationGroups: groups,
                applicationIdentifier: applicationIdentifier,
                teamIdentifier: teamIdentifier,
                signingIdentifier: signingIdentifier,
                entitlementQueryAvailable: true
            )
        }
        #endif

        return makeSnapshot(
            configuredGroupIdentifier: configured,
            effectiveApplicationGroups: [],
            applicationIdentifier: nil,
            teamIdentifier: nil,
            signingIdentifier: nil,
            entitlementQueryAvailable: false
        )
    }

    public static func makeSnapshot(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        configuredGroupIdentifier: String?,
        effectiveApplicationGroups: [String],
        applicationIdentifier: String?,
        teamIdentifier: String?,
        signingIdentifier: String?,
        entitlementQueryAvailable: Bool,
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
        var candidates = Set(effectiveApplicationGroups)
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
            effectiveApplicationGroups: effectiveApplicationGroups,
            applicationIdentifier: applicationIdentifier,
            teamIdentifier: teamIdentifier,
            signingIdentifier: signingIdentifier,
            entitlementQueryAvailable: entitlementQueryAvailable,
            groupContainerAvailability: availability
        )
    }

    #if canImport(Security)
    private static func entitlementStrings(
        _ key: String,
        task: SecTask
    ) -> [String] {
        guard let value = SecTaskCopyValueForEntitlement(
            task,
            key as CFString,
            nil
        ) else {
            return []
        }
        if let strings = value as? [String] {
            return strings
        }
        if let array = value as? NSArray {
            return array.compactMap { $0 as? String }
        }
        return []
    }

    private static func entitlementString(
        _ key: String,
        task: SecTask
    ) -> String? {
        guard let value = SecTaskCopyValueForEntitlement(
            task,
            key as CFString,
            nil
        ) else {
            return nil
        }
        return value as? String
    }
    #endif
}

import Foundation

/// #157 U4 ordinary authoring policy for Profile v3 State.
///
/// This type describes editor-only decisions. Runtime/Profile semantics remain
/// owned by ProfileDocumentV3 and the shared validator.
public enum ProfileV3StateAuthoringPolicy {
    public struct EnumDeletion: Equatable, Sendable {
        public let values: [String]
        public let defaultValue: String

        public init(values: [String], defaultValue: String) {
            self.values = values
            self.defaultValue = defaultValue
        }
    }

    public static func nextStateID(existingIDs: [String]) -> String {
        let existing = Set(existingIDs)
        var index = 1
        while existing.contains("state.state-(index)") {
            index += 1
        }
        return "state.state-(index)"
    }

    public static func isValidEnum(
        values: [String],
        defaultValue: String
    ) -> Bool {
        !values.isEmpty
            && values.count <= 32
            && Set(values).count == values.count
            && values.contains(defaultValue)
    }

    /// Deletes one Enum value without ever leaving the State with an invalid
    /// default. Deleting the current default requires an explicit replacement.
    public static func deletingEnumValue(
        at index: Int,
        values: [String],
        defaultValue: String,
        replacementDefault: String?
    ) -> EnumDeletion? {
        guard values.indices.contains(index), values.count > 1 else {
            return nil
        }

        let removed = values[index]
        var next = values
        next.remove(at: index)

        if removed != defaultValue {
            guard next.contains(defaultValue) else { return nil }
            return EnumDeletion(values: next, defaultValue: defaultValue)
        }

        guard let replacementDefault,
              next.contains(replacementDefault) else {
            return nil
        }
        return EnumDeletion(
            values: next,
            defaultValue: replacementDefault
        )
    }
}

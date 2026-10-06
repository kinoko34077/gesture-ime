import Foundation

public struct ProfileV3EnumDeletionResult: Equatable, Sendable {
    public let values: [String]
    public let defaultValue: String

    public init(values: [String], defaultValue: String) {
        self.values = values
        self.defaultValue = defaultValue
    }
}

/// #157 U4: deterministic draft-only helpers for ordinary State authoring.
///
/// This policy does not mutate ProfileDocument. It exists so invalid/incomplete
/// UI edits can remain local until the user commits a valid State definition.
public enum ProfileV3StateAuthoringPolicy {
    public static func enumValidationError(
        values: [String],
        defaultValue: String
    ) -> String? {
        guard !values.isEmpty else {
            return "列挙型には1つ以上の値が必要です。"
        }
        guard values.count <= 32 else {
            return "列挙型の値は32個までです。"
        }
        guard values.allSatisfy({ !$0.isEmpty }) else {
            return "空の値は登録できません。"
        }
        guard Set(values).count == values.count else {
            return "同じ値を複数登録できません。"
        }
        guard values.contains(defaultValue) else {
            return "初期値を登録済みの値から選んでください。"
        }
        return nil
    }

    public static func movedValues(
        _ values: [String],
        from index: Int,
        by offset: Int
    ) -> [String]? {
        let destination = index + offset
        guard values.indices.contains(index),
              values.indices.contains(destination),
              index != destination else {
            return nil
        }
        var copy = values
        let value = copy.remove(at: index)
        copy.insert(value, at: destination)
        return copy
    }

    public static func deletingValue(
        at index: Int,
        from values: [String],
        defaultValue: String,
        replacementDefault: String?
    ) -> ProfileV3EnumDeletionResult? {
        guard values.indices.contains(index), values.count > 1 else {
            return nil
        }

        let deleting = values[index]
        var next = values
        next.remove(at: index)

        if deleting == defaultValue {
            guard let replacementDefault,
                  next.contains(replacementDefault) else {
                return nil
            }
            return ProfileV3EnumDeletionResult(
                values: next,
                defaultValue: replacementDefault
            )
        }

        return ProfileV3EnumDeletionResult(
            values: next,
            defaultValue: defaultValue
        )
    }
}

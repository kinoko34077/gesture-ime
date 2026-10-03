import Foundation
import GestureIMECore

struct KeyboardKeySpec: Identifiable, Sendable {
    let id: String
    let title: String
    let bindingSet: BindingSet
}

enum BuiltInJapaneseProfile {
    static let kanaRows: [[KeyboardKeySpec]] = [
        [
            kana("kana.a", ["あ", "い", "う", "え", "お"], experimental: true),
            kana("kana.ka", ["か", "き", "く", "け", "こ"]),
            kana("kana.sa", ["さ", "し", "す", "せ", "そ"])
        ],
        [
            kana("kana.ta", ["た", "ち", "つ", "て", "と"]),
            kana("kana.na", ["な", "に", "ぬ", "ね", "の"]),
            kana("kana.ha", ["は", "ひ", "ふ", "へ", "ほ"])
        ],
        [
            kana("kana.ma", ["ま", "み", "む", "め", "も"]),
            kana("kana.ra", ["ら", "り", "る", "れ", "ろ"]),
            control("space", title: "空白", action: ActionInvocation(actionID: "text.insert", arguments: ["text": .string(" ")]))
        ],
        [
            control("next", title: "🌐", action: ActionInvocation(actionID: "system.nextKeyboard", arguments: [:])),
            control("enter", title: "改行", action: ActionInvocation(actionID: "text.insert", arguments: ["text": .string("\n")])),
            control("delete", title: "⌫", action: ActionInvocation(actionID: "edit.delete", arguments: ["count": .number(1)]))
        ]
    ]

    private static func kana(_ id: String, _ values: [String], experimental: Bool = false) -> KeyboardKeySpec {
        precondition(values.count == 5)
        var bindings = [
            binding(id, [], values[0]),
            binding(id, [.w], values[1]),
            binding(id, [.n], values[2]),
            binding(id, [.e], values[3]),
            binding(id, [.s], values[4])
        ]
        if experimental {
            bindings += [
                binding(id, [.ne], "↗︎"),
                binding(id, [.e, .n], "☆")
            ]
        }
        return KeyboardKeySpec(
            id: id,
            title: values[0],
            bindingSet: BindingSet(id: "bindings.\(id)", bindings: bindings)
        )
    }

    private static func control(_ id: String, title: String, action: ActionInvocation) -> KeyboardKeySpec {
        KeyboardKeySpec(
            id: id,
            title: title,
            bindingSet: BindingSet(
                id: "bindings.\(id)",
                bindings: [
                    GestureIMECore.Binding(
                        keyID: id,
                        path: GesturePath(),
                        behavior: BindingBehavior(
                            presentation: BindingPresentation(text: title, accessibilityLabel: title),
                            onRelease: [action]
                        )
                    )
                ]
            )
        )
    }

    private static func binding(_ keyID: String, _ path: [Direction8], _ output: String) -> GestureIMECore.Binding {
        GestureIMECore.Binding(
            keyID: keyID,
            path: GesturePath(path.map { GestureToken(direction: $0) }),
            behavior: BindingBehavior(
                presentation: BindingPresentation(text: output, accessibilityLabel: output),
                onRelease: [
                    ActionInvocation(actionID: "text.insert", arguments: ["text": .string(output)])
                ]
            )
        )
    }
}

# Gesture IME Common Action Registry v1

Status: Platform-common ActionInvocation contract

An ActionInvocation is serialized as:

```json
{
  "actionID": "text.insert",
  "arguments": {"text": "あ"}
}
```

The common registry defines semantic command intents. It does not define UIKit/Android APIs or converter-vendor calls.

## Common IDs

| actionID | Arguments | Canonical intent |
|---|---|---|
| `noop` | `{}` | Emit no command. |
| `text.insert` | `{"text": string}` | Emit `TextCommand.insert(text)` into the product input/composition pipeline. |
| `text.directInsert` | `{"text": string}` | Emit `TextCommand.directInsert(text)`; concrete host/composition flushing is adapter responsibility. |
| `edit.delete` | `{"count": integer}` | Emit `TextCommand.delete(count)`; positive deletes backward, negative deletes forward. Non-zero, absolute value <= 64. |
| `cursor.move` | `{"offset": integer}` | Emit `TextCommand.moveCursor(offset)`. Non-zero, absolute value <= 64. |
| `layer.set` | `{"layer": string}` | Replace the current layer with the referenced layer. |
| `layer.push` | `{"layer": string}` | Push the referenced layer, subject to the v1 layer-stack limit. |
| `layer.pop` | `{}` | Pop one pushed layer; at base layer this is a NoOp command result, not an error. |
| `profile.switch` | `{"profile": string}` | Request activation of another already-available profile. Active-gesture invalidation follows PLATFORM_COMMON. |
| `conversion.commit` | `{}` | Emit `CompositionCommand.commit`. |
| `conversion.selectCandidate` | `{"index": integer}` | Emit candidate selection by zero-based visible candidate index; index >= 0. |
| `panel.open` | `{"panel": string}` | Emit `RuntimeCommand.openPanel(panel)`. |
| `macro.run` | `{"macro": string}` | Expand the referenced v1 macro once. Forbidden inside macro bodies in v1. |
| `system.nextKeyboard` | `{}` | Emit `SystemCommand.nextKeyboard`. |
| `system.dismissKeyboard` | `{}` | Emit `SystemCommand.dismissKeyboard`. |

Space and enter do not require privileged gesture semantics; profiles may use `text.insert` with a space or newline when intended.

## Argument rules

- `arguments` must be a JSON object.
- Unknown object members for a known common action are invalid in v1 (`E_INVALID_ACTION_ARGUMENTS`).
- String payloads are UTF-8 and subject to the 4096-byte per-string limit.
- Encoded `arguments` is subject to the 16384-byte per-invocation limit.
- Referenced layer/macro IDs resolve during activation when local to the loaded ProfileBundle.

## Macro expansion

`macro.run` used by a binding resolves one named macro and replaces that invocation with the macro body's ordered ordinary ActionInvocations.

V1 rejects a macro body containing `macro.run`. Runtime expansion is non-recursive.

The originating dispatch batch is derived from the gesture's immutable profile snapshot. A layer/profile-changing command must not cause remaining invocations from that same dispatch to be reinterpreted against a different binding/profile.

## Extension namespaces

A future/platform-specific action must not impersonate a common ID.

Reserved extension forms:

```text
platform.<platform>.<name>
extension.<reverse-dns-or-project-id>.<name>
```

Activation requires an explicitly registered action schema/capability for the exact ID. Without it, validation fails with `E_UNKNOWN_ACTION`. Portable common profiles should use common IDs only.

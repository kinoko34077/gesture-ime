# Phase 3 iOS Keyboard Extension

Issue: #13

## Purpose

Phase 3 moves GestureIMECore from a standalone measurement harness into a real iOS custom keyboard extension.

The extension is deliberately conversion-free in this phase. Text actions go directly through `textDocumentProxy`.

## Built-in development layout

```text
あ   か   さ   ⌫
た   な   は   空白
ま   や   ら   改行
🌐  わ   ◇   ⚙︎
```

Ordinary kana keys keep the conventional v0 cardinal mapping from the common specification.

The `◇` key is experimental:
- tap -> ◇
- NE -> ↗︎
- E -> →
- E then N -> →↑

This demonstrates diagonal and two-stage bindings without reducing the 4-way tolerance of normal kana keys.

## Gesture tuning

The `⚙︎` key opens an extension-local tuning panel for:
- dead zone;
- stage-1 commit distance;
- stage-2 commit distance;
- angular hysteresis.

Values are stored in the Keyboard Extension's own `UserDefaults` and apply to newly started gestures. No recognizer code change is required.

App Group synchronization is intentionally deferred to Phase 5.

## Install/test route

```text
GitHub Actions macOS/Xcode
→ unsigned containing-app IPA with GestureKeyboard.appex
→ Windows re-sign/sideload
→ iPhone Settings
→ General
→ Keyboard
→ Keyboards
→ Add New Keyboard
→ GestureIME
```

After enabling GestureIME, select it from the globe key in a normal text field.

Phase 3 does not require Full Access.

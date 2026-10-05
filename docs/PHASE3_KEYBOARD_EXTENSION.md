# Phase 3 iOS Keyboard Extension

Issue: #13

> **Historical Phase 3 record.** This document describes the v1-era extension milestone and is preserved for implementation history. It is not the current product/Profile specification. Current authority is Profile v3 #43, as revised by #69 and frozen R95 #95; the bundled `default-ja.json` is now `gesture-ime.profile.v3`.

## Purpose

Phase 3 moves GestureIMECore into a real iOS custom keyboard extension while preserving the platform-common semantic boundary.

The extension owns:
- UIInputViewController lifecycle;
- touch adaptation;
- textDocumentProxy/system effects;
- extension-local gesture tuning UI.

Gesture meaning remains in the bundled `gesture-ime.profile.v1` data and GestureIMECore.

## Built-in development profile

Canonical bundled data:

`App/KeyboardExtension/Resources/default-ja.json`

The UI is compiled from the profile's active layer, layout placements, key definitions and binding set. Kana mappings are not duplicated in Swift source.

Historical Phase 3 development layout:

```text
あ   か   さ   ⌫
た   な   は   空白
ま   や   ら   改行
🌐  わ   ◇   ⚙︎
```

Ordinary kana keys remain cardinal-only. The dedicated `◇` key carries experimental diagonal/two-stage bindings:
- tap -> ◇
- [NE] -> ↗︎
- [E] -> →
- [E,N] -> →↑

## Gesture tuning — historical Phase 3 behavior

At the Phase 3 milestone, the `⚙︎` key dispatched the common `panel.open` action and opened an extension-local panel for:
- dead zone;
- stage-1 commit distance;
- stage-2 commit distance;
- angular hysteresis.

Values persist in the Keyboard Extension's own UserDefaults and apply to newly started GestureSessions. Reset restores the bundled profile's GesturePolicy defaults.

No App Group is required in Phase 3.

## Multitouch boundary

The platform adapter enforces the v0 unsupported-multitouch rule across keys:
- a second concurrent key touch cancels active gesture sessions;
- no semantic action is dispatched while the conflicting touch set is active;
- new input becomes eligible again after all conflicting touches end.

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
→ Gesture IME
```

Full Access is not required.

Historical milestone note: at Phase 3, Kana/Kanji conversion and candidate UI were deferred to Phase 4. They are not deferred in the current Profile v3 product.

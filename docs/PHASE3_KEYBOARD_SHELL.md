# Phase 3 iOS Keyboard Shell

Issue: #13

## Purpose

Phase 3 proves the product-owned gesture/profile runtime inside a real iOS Keyboard Extension.

The extension owns only platform composition and effects:
- UIInputViewController lifecycle;
- touch UI;
- textDocumentProxy effects;
- next-keyboard/dismiss system effects;
- extension-local development tuning UI.

Gesture semantics remain in GestureIMECore and profile/binding data.

## Built-in development layout

The first keyboard intentionally uses a bounded direct-hiragana layout rather than Kana/Kanji conversion.

Kana rows with full five-way bindings:
- あ / い / う / え / お
- か / き / く / け / こ
- さ / し / す / せ / そ
- た / ち / つ / て / と
- な / に / ぬ / ね / の
- は / ひ / ふ / へ / ほ
- ま / み / む / め / も
- ら / り / る / れ / ろ

The A key also has explicit development bindings:
- [NE] -> ↗︎
- [E,N] -> ☆

These are test bindings, not universal gesture meanings.

## Gesture tuning

The ⚙︎ panel stores these in the Keyboard Extension's own UserDefaults:
- dead zone;
- stage-1 commit distance;
- stage-2 commit distance;
- angular hysteresis.

These remain runtime inputs. Phase 3 does not freeze final product defaults.

App Group/shared configuration is deferred to Phase 5.

## CI / sideload

GitHub Actions builds the containing app and embedded Keyboard Extension with signing disabled.

The artifact is:

`GestureIME-keyboard-unsigned.ipa`

The Windows sideload client re-signs the containing app and extension for the physical device.

After installation, enable the keyboard from iOS Settings and select it from the globe key in a compatible text field.

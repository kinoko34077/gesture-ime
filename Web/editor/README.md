# Gesture IME Studio (Web shell — M3a)

This is a **production-directed shared UI shell**, not an independent gesture simulator. Its built-in Profile and geometry come from the native canonical Rust `inspect_profile` compiled to WebAssembly. Tap/flick/long-press replays use canonical Rust `trace_profile` as accepted at #208/PR #209. The trace currently uses DefaultBoardSemanticsV3 and does **not** evaluate advanced host/conditional semantics, conversion candidates, native text insertion, App Group or IME height/haptics.

## Build and local serving

GitHub Actions `.github/workflows/web-preview-pages.yml` packages `Web/editor/` with the wasm-pack **web** target and public `default-ja.json` into a static website artifact. The app expects `./wasm/gesture_ime_core_web.js` and `./default-ja.json` relative to its own URL and thus supports GitHub Pages subpaths and WebView packaged offline assets.

Only a user-selected local JSON file is read in-browser using File API. It is kept **in memory**, never uploaded or committed. Export returns the unchanged source JSON. No analytics, remote backend or privileged native bridge is used. SW caches only public/versioned static URLs; the CI build replaces `__BUILD_SHA__` for cache invalidation.

## UX/acceptance limit

This slice proves the first browser-accessible Board layout and gesture trace against the exact Rust engine. Its key labels are explicitly **authored base labels** (no conditional resolution). Editing now uses the accepted shared Rust `WebProfileEditor` from #212/PR #214: `renameProfile`, `setEntryDefaultText`, Undo and Redo; browser-only IndexedDB saving and JSON import/export remain HostPort operations. This is the minimal command slice, not a full macro/condition/Theme editor or real iOS/Android keyboard acceptance.

Public Pages publishing needs repository owner to select **Settings → Pages → Build and deployment → Source: GitHub Actions** once. `configure-pages` cannot enable Pages from default ephemeral `GITHUB_TOKEN` alone, and no elevated token/permission alteration is bundled.

## Browser smoke and persistence

The `Shared Web Editor Preview` workflow runs a real headless Chromium mobile-viewport end-to-end test after generating Rust Wasm: load demo Profile, select kana key, update default text, Undo, Redo, rename Profile, save to IndexedDB, reload and recover the current Profile, run canonical Rust gesture trace, reject invalid JSON. Screenshot artifact is attached when available. Browser CI does **not** certify physical iPhone Safari touch/OS IME behavior.

Locally saved Profiles never go to GitHub or a server. They are not synchronized across devices and can be erased by clearing browser storage; use **JSONを書き出す** to keep a separate backup. Browser save never means native IME activation. The service worker cache is restricted to public static assets only.

## Flick guide rendering (M3c)

The Wasm `inspect_profile` response now includes direct-entry presentation text and immediate flick labels plus logical guide center coordinates from **the exact same** native Rust `ProfileV3PlatformRuntime::direct_surface()` contract used by iOS/Android adapters. The browser positions those returned labels around each key and does not guess Profile transitions or conditional cases in JavaScript. Touch hit targets remain the underlying original keys. The native surface is resolved against **default simulated host facts**, not real iOS text-field attributes or conversion state, and deeper Board/Stage overlays remain later UI scope.

## Layer / Board authoring slice (M3d)

The Layer selector and Board selector use the validated Profile v3 inventory emitted by the **canonical Rust** `inspect_profile` / `inspect_board` API. Nonroot Boards, including existing flick, Stage and Hold Boards, can be opened and the selected Key's default presentation text edited using the accepted Rust `WebProfileEditor` with Undo/Redo, local Save and JSON Export. The semantic preview of an arbitrary Board is created by `ProfileV3PlatformRuntime::set_layer` and `preview_surface`, not JS-derived conditions. The selector does not create or delete Boards, rewrite transitions or simulate custom host facts.

**Any selected Layer's root Board** now supports genuine canonical Rust browser gesture replay. The bounded Web Rust trace adapter accepts optional `layerId` and calls `ProfileV3BoardRuntime::new_frame` with the validated Layer; omitting it retains original initial-Layer semantics for old callers. Arbitrary internal Boards remain **編集専用プレビュー**, because beginning replay at an arbitrary internal Board would require a separate canonical Rust API. Selected Board is transient UI state; Profile and authored edits persist only through explicit browser Save/export.

## Default Board transition editing (M3f)

For any selected authored Key in any existing Board, `遷移先Board` lists **only** validated Board IDs exposed by the common Rust inspector, plus `なし`. `遷移種別` selects the canonical lifetime `transient` or `persistent` only when a target exists. Form initialization reads the authored default transition from the validated Profile, but **all writes** go through the same revisioned Rust `WebProfileEditor.apply_command({type:"setEntryDefaultTransition",...})`, never through direct JavaScript Profile mutation.

Changing an existing target, Undo, Redo and explicit removal update the Rust semantic preview immediately; save/export and local reload use the existing browser HostPort. Removal passes **both explicit JSON nulls**, so accidentally omitted fields cannot delete an existing transition. Invalid target/lifetime is a Rust rejection and must not mutate the Profile. The UI does not edit conditional cases, Hold transitions, or create/delete Boards; selecting internal Boards remains edit-only and is **not** an OS IME Stage/Hold simulation.


## M3h — user-facing Macro authoring (Core #235 / Web #237)

The Macro panel lists validated Profile v3 Macros by optional human name, and provides name-based creation, rename and typed ordered `text.insert` / `noop` action editing, addition and explicit removal. All authoring mutates **only** by the revisioned canonical Rust `WebProfileEditor.apply_command` commands `createMacro`, `renameMacro`, `setMacroActions`; Rust generates stable internal IDs and validates the whole Profile. The JavaScript form is a command payload builder, never a Macro runtime or duplicate validator.

An editable sample greeting Macro is created **only** by the user's explicit button. It is not auto-injected, never silently overwrites another Macro, and remains browser-local until explicitly saved/exported. Existing advanced Macro action IDs are shown read-only and retained untouched during unrelated edits. Existing `text.insert` conditional transforms and additional metadata are preserved when changing base text. The app explicitly labels **Key→Macro invocation and OS keyboard delivery as not yet implemented**; a sample action being authored does not prove it is attached to a key or executed. A later bounded canonical Core binding command and Web UI/physical gate own invocation acceptance.

Real mobile Chromium/WebAssembly end-to-end exercises name uniqueness rejection, editing, Undo/Redo, local Save/Reload, advanced action preservation and the previously accepted service-worker offline recovery; physical iPhone Safari remains a separate #216 acceptance gate.


## User-first verification workflow (#259)

The default screen is now **試す** rather than the technical authoring console: choose a keyboard kind from Rust-validated Layer labels, tap/flick its actual root keys, and immediately read the simulated text directly beneath the keyboard. The visible log appends **only concrete `text.insert` / `text.directInsert` base-text actions actually dispatched by the canonical Rust BoardSession**. The reset button clears only that local simulated log; non-text actions, cancel and no-op do not pretend to modify an operating-system text field. The simulator does not interpret real host conditions, platform candidate conversion, iOS/Android keyboard activation, sound or haptics.

**編集する** switches to the existing Profile/Board/Stage/Macro authoring and browser Save/Undo workflow. This is a view change, not a new Profile or save operation: switching modes does not silently discard a draft. The UI follows the actually read shared [利用者起点 UI/UX 設計原則](https://drive.google.com/file/d/1hgeGtmtML7YjuO18CfeYiJ_lhWKWTHMB/view), in particular UX-04/06/07/09/11/15. Headless Chrome smoke covers first-view test actions on Kana/Latin/numbers, clearing output, returning to the edit mode, and the existing mobile gesture/offline authoring acceptance. Physical Safari/user testing remains UNVERIFIED.


## Long-press input surface authoring (#254)

In **編集する**, selecting an ordinary root Key reveals **長押しの入力面** without exposing raw Board identifiers. A numeric delay (default 480ms; 50–5000ms) and **作る** button issue the accepted revisioned Rust `createReachableHoldSurface` command. For stock Kana/Latin keys with immediate root transitions, Rust attaches the Hold to the actually reached relative Board origin. The Web UI reads the resulting Hold transition from the validated authored document and opens that actual Board; there are no guessed IDs, eagerly seeded phantom diagonals or duplicate Boards. Existing Hold destinations display **長押しの入力面へ**. Center entry editing, one-button Back, Undo/Redo and explicit Save/Reload/Offline reuse the shared editor infrastructure.

**Important output boundary:** the existing `setEntryDefaultText` command changes *presentation* only; a newly created empty Hold center has no `onRelease text.insert` action. Editing its label does **not** by itself make it type that text or prove Hold output on the system keyboard. Input-action authoring is a separate missing canonical command/UI step, not emulated by JavaScript. The browser gesture replay is still DefaultBoardSemantics under simulated host facts, not physical iOS/Android acceptance.

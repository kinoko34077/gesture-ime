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

Only the **initial Layer + initial root Board** supports the existing browser gesture replay. All other Boards are marked **編集専用プレビュー** and clicking keys only selects them for edit. This is deliberate: the current `trace_profile` begins a new initial Board session and cannot truthfully replay a gesture beginning at an arbitrary internal Board. The first later real Stage/Hold session replay must be a separately verified canonical Rust API, not a fake Web-only gesture trace. Selected Board is transient UI state; the saved Profile and editor content are durable in IndexedDB, whereas selection resets to initial Board on a full reload.

## Default Board transition editing (M3f)

For any selected authored Key in any existing Board, `遷移先Board` lists **only** validated Board IDs exposed by the common Rust inspector, plus `なし`. `遷移種別` selects the canonical lifetime `transient` or `persistent` only when a target exists. Form initialization reads the authored default transition from the validated Profile, but **all writes** go through the same revisioned Rust `WebProfileEditor.apply_command({type:"setEntryDefaultTransition",...})`, never through direct JavaScript Profile mutation.

Changing an existing target, Undo, Redo and explicit removal update the Rust semantic preview immediately; save/export and local reload use the existing browser HostPort. Removal passes **both explicit JSON nulls**, so accidentally omitted fields cannot delete an existing transition. Invalid target/lifetime is a Rust rejection and must not mutate the Profile. The UI does not edit conditional cases, Hold transitions, or create/delete Boards; selecting internal Boards remains edit-only and is **not** an OS IME Stage/Hold simulation.

# Gesture IME Studio (Web shell — M3a)

This is a **production-directed shared UI shell**, not an independent gesture simulator. Its built-in Profile and geometry come from the native canonical Rust `inspect_profile` compiled to WebAssembly. Tap/flick/long-press replays use canonical Rust `trace_profile` as accepted at #208/PR #209. The trace currently uses DefaultBoardSemanticsV3 and does **not** evaluate advanced host/conditional semantics, conversion candidates, native text insertion, App Group or IME height/haptics.

## Build and local serving

GitHub Actions `.github/workflows/web-preview-pages.yml` packages `Web/editor/` with the wasm-pack **web** target and public `default-ja.json` into a static website artifact. The app expects `./wasm/gesture_ime_core_web.js` and `./default-ja.json` relative to its own URL and thus supports GitHub Pages subpaths and WebView packaged offline assets.

Only a user-selected local JSON file is read in-browser using File API. It is kept **in memory**, never uploaded or committed. Export returns the unchanged source JSON. No analytics, remote backend or privileged native bridge is used. SW caches only public/versioned static URLs; the CI build replaces `__BUILD_SHA__` for cache invalidation.

## UX/acceptance limit

This slice proves the first browser-accessible Board layout and gesture trace against the exact Rust engine. Its key labels are explicitly **authored base labels** (no conditional resolution). Editing and Undo attach later to shared Rust ProfileV3Editor once #212/PR #214 reaches accepted main. It must not be called a complete keyboard editor or real iOS/Android keyboard acceptance.

Public Pages publishing needs repository owner to select **Settings → Pages → Build and deployment → Source: GitHub Actions** once. `configure-pages` cannot enable Pages from default ephemeral `GITHUB_TOKEN` alone, and no elevated token/permission alteration is bundled.

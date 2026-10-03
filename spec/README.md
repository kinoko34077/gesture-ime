# gesture-ime specification

This directory contains the implementation-facing platform-common canon.

Read order:

1. `PLATFORM_COMMON.md` — shared gesture/profile/runtime semantics;
2. `profile/gesture-ime.profile.v1.schema.json` — serialized ProfileBundle structure;
3. `actions/action-registry.v1.md` — common ActionInvocation IDs and arguments;
4. `conformance/README.md` + `conformance/manifest.json` — shared fixture contract and corpus.

Repository Issues remain the requirement/design/history authority:

- #1 product concept / architecture requirements;
- #2 v0 external behavior;
- #3 concrete architecture / responsibility boundaries;
- #4 bounded-resource and cancellation hardening;
- #5 implementation roadmap;
- #6 Phase 0 implementation record.

Swift/iOS and Kotlin/Android implementations conform to this common canon. Neither platform implementation is the semantic source of truth.

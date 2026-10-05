# gesture-ime specification

This directory contains the implementation-facing platform-common canon.

## Current product authority

The current product/Profile line is **Profile v3**:

1. repository Issue #43 — Profile v3 baseline;
2. repository Issue #69 — post-A7 frozen revision where it supersedes #43;
3. repository Issue #95 — frozen R95 revision where it supersedes #69;
4. `profile/gesture-ime.profile.v3.schema.json` — implementation-facing v3 schema;
5. shared Rust Profile v3 validation/runtime — executable semantic authority.

Where those authorities conflict, follow the explicit supersession chain above. Older v1/v2 documents remain useful as compatibility/history records only; they do not override accepted v3 product semantics.

## Read order

For current implementation work:

1. `profile/gesture-ime.profile.v3.schema.json`;
2. `PLATFORM_COMMON.md` — shared platform-common foundations plus the v1/v2/v3 authority map;
3. `BOARD_GRAPH_V2.md` — historical v2 Board-graph lineage still referenced by unchanged v3 concepts;
4. `actions/action-registry.v1.md` — common ActionInvocation IDs/arguments where still applicable to v3;
5. `conformance/README.md` + `conformance/manifest.json` — shared fixture contract/corpus.

Historical requirement/design context remains in Issues #1–#6 and the v1/v2 schema/canon. Swift/iOS and Kotlin/Android implementations remain adapters/consumers of shared semantic authority rather than independent sources of truth.

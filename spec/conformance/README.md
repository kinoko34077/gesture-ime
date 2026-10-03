# Platform-Common Conformance Fixtures v1

The fixture corpus verifies semantics shared by Swift/iOS and Kotlin/Android implementations.

`manifest.json` is the index. Fixture files are immutable test inputs for a given schema/spec revision; behavior changes require an intentional spec/fixture update.

## Fixture classes

### Profile fixtures

Files whose kind is `profile` in the manifest are complete ProfileBundle documents.

Manifest expectations:

- `valid` — structural + semantic activation validation succeeds;
- `invalid` — activation fails with the listed isolated canonical error code.

JSON Schema validation is only one validation layer. Duplicate paths, Action registry resolution, macro nesting, aggregate limits, and trie-node limits are semantic validation.

### Gesture-trace fixtures

Gesture fixtures provide explicit GesturePolicy values, legal GesturePaths for one key, normalized key size, ordered touch samples, and expected committed path/anchor events.

A sample with `event: move` uses canonical x-right/y-down coordinates. Implementations adapt native coordinates before running common recognition.

### Lifecycle fixtures

Lifecycle fixtures describe cancellation/invalidation events and expected semantic dispatch. They verify that cancel/invalidate emits no release/hold/repeat actions after the terminal transition.

## Comparison rules

Canonical comparisons cover:

- GesturePath tokens;
- eligible-direction sets;
- virtual-anchor commitment positions;
- validation success/error class;
- semantic action dispatch presence/absence.

Rendering, haptic waveform, native event identity, timer implementation, and OS lifecycle details are not compared here.


## Board-graph v2 fixtures

Profile v2 fixtures are indexed separately by `board-graph-v2.manifest.json` while the v2 runtime is introduced. They cover sparse relative coordinates, chained local-origin resets, Hold transitions, persistent/transient lifetimes, and duplicate-coordinate validation.

After the shared Rust v2 path is active, these fixtures become executable cross-platform conformance evidence. Existing v1 fixtures remain regression requirements and verify compatibility normalization.

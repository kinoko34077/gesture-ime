# Board Graph Input Model v2

Status: platform-common canonical contract for `gesture-ime.profile.v2`.

This document supersedes the durable authoring/runtime role of GesturePath/BindingTrie for Profile v2. Profile v1 remains a supported compatibility input and is normalized into this model before product runtime use.

## 1. Core model

The v2 input pipeline is:

```text
Touch / non-spatial trigger
  -> EntryPoint(layer + key + trigger)
  -> Board
  -> board-local selection
  -> BoardEntry
     -> onRelease Action(s)
     -> and/or BoardTransition
  -> next Board ...
```

A Board is an independent local map. A transition target need not be geometrically adjacent or continuous with its source.

## 2. Entry points

Each entry point has a stable ID and binds:

- `layerID`
- `keyID`
- a trigger
- an initial `boardRef`

For v2 the required initial trigger is `press`.

Persistent board state is scoped to one entry point. At first use its persistent baseline is `boardRef`. A persistent transition changes that entry point's persistent baseline for subsequent interactions. This scope prevents a persistent choice for one key from silently changing unrelated keys.

## 3. Board-local coordinates

Each Board owns a sparse set of entries addressed by local integer coordinates:

```text
BoardCoordinate(x, y) -> BoardEntry
```

The local origin is `(0,0)`.

The ordinary eight-neighbor map is one instance:

```text
(-1,-1)  (0,-1)  (1,-1)
(-1, 0)  (0, 0)  (1, 0)
(-1, 1)  (0, 1)  (1, 1)
```

Coordinates are topology, not global screen positions. Transitioning to another Board establishes a new local origin at the transition commit point.

Coordinates outside the immediate eight-neighbor ring are legal Profile data. The schema therefore does not need revision merely to represent wider or sparse boards.

## 4. Selection policy seam

Board topology and input classification are separate.

Each Board has a `selectionPolicy`. v2 initially standardizes:

```json
{"kind":"relativeCoordinate"}
```

For this policy:

1. native input is adapted into x-right/y-down platform-neutral coordinates;
2. displacement is measured from the current Board anchor;
3. `(0,0)` is the no-spatial-movement / tap entry;
4. non-origin entries are candidates based on their coordinate vector;
5. required radial distance is:
   - `initialCellCommitDistance * max(abs(x),abs(y))` before the first spatial commit;
   - `subsequentCellCommitDistance * max(abs(x),abs(y))` after a Board transition;
6. among reachable candidates, choose the smallest angular distance from the displacement vector; ties prefer the largest reachable Chebyshev radius, then canonical `y,x` ordering;
7. angular candidate changes obey `angularHysteresisDegrees`;
8. a transition resets the anchor to its commit point.

This preserves normal 4-way tolerance when only cardinal entries exist, exposes 8-way behavior when diagonal entries exist, and keeps wider sparse coordinates representable under the same Board abstraction.

A later selection policy may use different hit geometry without changing BoardEntry/BoardTransition semantics.

## 5. Board entries

A BoardEntry contains:

- `coordinate`
- optional `presentation`
- optional `onRelease` Actions
- optional legacy-compatible `hold` behavior (delay/onStart/repeat/suppress-on-release), preserving ordinary held-key behavior such as delete repeat
- optional `transition`

At least one of presentation, release/hold actions, or transition must be meaningful for authored entries; validation may reject semantically empty entries.

### Terminal selection

If a selected entry has no transition, it remains selected until release. Its `onRelease` Actions are dispatched on release.

If no spatial entry is selected, release resolves the center entry `(0,0)`, if present.

If that center entry has both `onRelease` Actions and a transition, the center entry is the release endpoint: its release Actions are resolved from the source Board, then the transition is committed. The same release does not implicitly dispatch the target Board's center Actions.

### Transition selection

If a spatially selected entry has a transition, the transition commits immediately when that coordinate commits. The target Board becomes current and the local origin resets at that touch point.

An entry may also have `onRelease` Actions, but after an immediate transition those actions are not the release endpoint unless the interaction later returns to that same entry through the graph. Authors that need immediate side effects should use ordinary Actions through a later explicit transition/action extension; v2 does not invent implicit action timing.

This keeps text/edit Actions release-based and avoids firing ordinary key semantics before finger-up.

## 6. Transition lifetime

A BoardTransition has:

```json
{
  "targetBoardRef": "board.example",
  "lifetime": "transient"
}
```

Required lifetime values:

- `persistent`
- `transient`

Semantics:

### persistent
- target becomes `currentBoard`;
- target becomes the entry point's `persistentBoard`;
- later transient completion returns to this new baseline;
- later interactions for the same entry point start from this baseline.

### transient
- target becomes `currentBoard`;
- `persistentBoard` is unchanged;
- completion of the interaction returns current state to the persistent baseline;
- a chain of transient Boards returns directly to the persistent baseline, not one Board at a time.

A persistent transition while traversing transient Boards immediately replaces the persistent baseline.

## 7. Non-spatial Board triggers

A Board may define non-spatial `triggers`.

v2 initially standardizes `hold`:

```json
{
  "type": "hold",
  "delayMs": 450,
  "transition": {
    "targetBoardRef": "board.hold",
    "lifetime": "transient"
  }
}
```

Hold itself is not a coordinate. When it fires, it uses the same BoardTransition semantics and resets the local origin at the current touch point.

A hold trigger may be defined on any Board, so Hold can chain into the same graph without a hold-specific Action system.

## 8. Gesture policy v2

Profile v2 uses:

- `deadZone`
- `initialCellCommitDistance`
- `subsequentCellCommitDistance`
- `angularHysteresisDegrees`

There is no `maxDirectionalStages` authoring ceiling.

Safety is enforced by runtime resource limits rather than a semantic two-stage cap.

## 9. Resource and cycle policy

Profile v2 limits:

- encoded Profile: 1 MiB
- key definitions: 256
- layouts: 32
- placements per layout: 256
- layers: 32
- boards: 1024
- entries per Board: 256
- entry points: 1024
- Board triggers per Board: 16
- macros: 128
- endpoint Actions: same limits as v1
- Board transitions committed in one interaction: 16

Graph cycles are legal. Validation checks references and bounded resources but does not reject a Profile merely because a cycle exists. Runtime terminates further Board transitions when the per-interaction transition limit is reached and treats additional transition attempts as no further transition for that interaction.

## 10. Compatibility from Profile v1

A valid v1 Profile is normalized into v2-equivalent Boards before shared product runtime use.

For each `layer + key`:

1. create one stable compatibility EntryPoint;
2. create a root Board for GesturePath prefix `[]`;
3. the v1 binding behavior at a prefix becomes the center `(0,0)` release behavior of that prefix Board;
4. each child Direction8 token becomes a coordinate entry:
   - N = `(0,-1)`
   - NE = `(1,-1)`
   - E = `(1,0)`
   - SE = `(1,1)`
   - S = `(0,1)`
   - SW = `(-1,1)`
   - W = `(-1,0)`
   - NW = `(-1,-1)`;
5. if the child path has further descendants, that coordinate transitions transiently to the child-prefix Board;
6. if the child path is terminal, its v1 behavior becomes that coordinate's release behavior.

Thus a v1 first-stage endpoint that also has a second-stage child is preserved: the first spatial commit enters a child Board whose center carries the first-stage release behavior, while further movement selects the child Board's coordinates.

v1 validation rules remain unchanged for v1 documents. v2 authors are not constrained by v1 path depth.

## 11. Layer/layout relationship

Profile v2 retains `keyDefinitions`, `layouts`, and `layers` for the visible keyboard topology.

A v2 Layer references a Layout. Gesture meaning is supplied by EntryPoints/Boards instead of a BindingSet.

This revision does not require the visible keyboard layout itself to become a Board. Board graph semantics govern the generic per-entry input interaction while preserving the existing product layout boundary. A later revision may unify more presentation topology without changing the BoardEntry/BoardTransition model.

## 12. Validation and fail-closed activation

Validation order is conceptually:

1. encoded byte bound;
2. schema/version decode;
3. resource limits;
4. unique IDs;
5. layout/key/layer reference integrity;
6. Board/EntryPoint/transition reference integrity;
7. coordinate uniqueness within each Board;
8. policy invariants;
9. Action validation;
10. macro rules;
11. only then activate.

Invalid v2 data must not replace a last-known-good Profile.

New canonical validation codes:

- `E_LIMIT_BOARDS`
- `E_LIMIT_BOARD_ENTRIES`
- `E_LIMIT_ENTRY_POINTS`
- `E_LIMIT_BOARD_TRIGGERS`
- `E_LIMIT_BOARD_TRANSITIONS` (runtime interaction bound)
- `E_DUPLICATE_BOARD_COORDINATE`

Existing codes continue where applicable, including `E_MISSING_REFERENCE`, `E_UNKNOWN_ACTION`, `E_INVALID_ACTION_ARGUMENTS`, and `E_INVALID_GESTURE_POLICY`.

## 13. Cross-platform authority

The shared Rust runtime owns:

- v1 -> Board compatibility normalization;
- v2 validation;
- Board selection semantics;
- Board transition lifetime;
- persistent/transient state;
- Hold Board transitions;
- Action endpoint resolution.

Swift and Kotlin adapters transport platform input and consume snapshots. They must not independently reinterpret Board semantics.

## 14. Required conformance

The v2 implementation must prove:

- Japanese tap + cardinal 4-way via Boards;
- 8-direction relative-coordinate selection;
- existing two-stage behavior via transient Board chaining and local-origin reset;
- Hold -> Board transition;
- source/target Boards with unrelated geometry;
- persistent transition survives into the next interaction for the same EntryPoint;
- transient chains return to the persistent baseline;
- persistent transition from a transient Board replaces the baseline;
- v1 accepted profiles normalize to equivalent product behavior;
- unknown-preserving authoring/storage round-trip retains v2 structures.

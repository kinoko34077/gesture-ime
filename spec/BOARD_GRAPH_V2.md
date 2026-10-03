# Gesture IME Board Graph Profile v2

Status: canonical platform-common contract for the #23 board-graph revision.

This document supersedes the v1 `GesturePath`/two-stage model **only for Profile v2**. Profile v1 remains a supported compatibility input and is not redefined.

## 1. Versioning and compatibility

- v1 schema identifier: `gesture-ime.profile.v1`.
- v2 schema identifier: `gesture-ime.profile.v2`.
- A runtime that advertises v2 support MUST continue accepting valid v1 Profiles until an explicit later compatibility decision retires them.
- v1 input is normalized into the board runtime through deterministic compatibility compilation; v1 is not silently rewritten on disk.
- v2 authoring MUST use boards as the durable external input abstraction. `GesturePath` and `BindingTrie` may remain implementation/compatibility structures, but they are not the v2 authoring ceiling.

## 2. Existing keyboard Layer vs Board

The existing `Layer` remains the whole-keyboard layout/mode concept: it selects one `Layout` and maps each placed key to a root Board.

A `Board` is a reusable local selection map entered from a key or another Board entry. Boards are not required to be spatially adjacent to each other and do not inherit coordinates from their source.

Each `Layer` therefore owns:

```text
Layer
  -> layoutRef
  -> keyBoards[]: keyID -> boardRef
```

The same Board MAY be referenced by multiple keys or layers.

## 3. Board-local coordinate space

Each Board has its own local origin `(0, 0)`.

Board entries are a sparse map:

```text
BoardCoordinate(x, y) -> BoardEntry
```

v2 coordinates are signed integers in the range `-127...127` on each axis. A Board is not required to contain all coordinates in a rectangle.

The conventional Direction8 neighborhood is only one instance:

```text
(-1,-1)  (0,-1)  (1,-1)
(-1, 0)  (0, 0)  (1, 0)
(-1, 1)  (0, 1)  (1, 1)
```

Canonical Direction8 compatibility mapping uses x-right/y-down coordinates:

| Direction8 | coordinate |
| --- | --- |
| N | (0,-1) |
| NE | (1,-1) |
| E | (1,0) |
| SE | (1,1) |
| S | (0,1) |
| SW | (-1,1) |
| W | (-1,0) |
| NW | (-1,-1) |

The schema allows coordinates outside this unit neighborhood. Current platform selection adapters are permitted to expose only the coordinates they can physically classify. Unsupported topology is a capability boundary, not a reason to change the Profile schema.

## 4. Topology and physical selection are separate

Coordinates define semantic topology. They do not prescribe radial sectors, hit rectangles, pointer distance, dwell, velocity, or future grid/ring classification.

The initial product adapter maps the existing Direction8 recognizer to the unit-neighborhood coordinates above. Future selection policies may expose wider/sparse coordinates without changing Board/BoardEntry serialization.

Gesture thresholds therefore remain input-policy configuration, not Board meaning.

## 5. BoardEntry

A BoardEntry has:

- one unique coordinate within its Board;
- optional presentation;
- optional `onRelease` ActionInvocation list;
- optional BoardTransition;
- optional `onTransition` ActionInvocation list;
- optional HoldTrigger.

At least one of `onRelease`, `transition`, or `hold` MUST be present.

### 5.1 Terminal entry

An entry without `transition` is a terminal selection endpoint. On touch/pointer release while that entry is selected, its `onRelease` Actions dispatch from the immutable Profile snapshot that began the interaction.

### 5.2 Transition entry

When a non-center spatial entry with a `transition` is committed:

1. `onTransition` Actions, if any, are captured/dispatched from the pre-transition immutable Profile snapshot;
2. the BoardTransition is applied;
3. the target Board becomes `currentBoard`;
4. the physical selection anchor resets to the transition commit point;
5. continued movement may immediately select from the target Board.

The center entry `(0,0)` is already selected when a Board interaction begins. A transition on the center entry is committed on release, after which the target Board remains current according to its transition lifetime for the following Board interaction.

If an entry has both `onRelease` and `transition`, the transition semantics take precedence for spatial commit; `onRelease` is only used when the entry is the terminal selected entry at release and no transition has already been committed for that selection. Profiles SHOULD avoid depending on this overlap; compatibility compilation does not generate it.

## 6. BoardTransition

```json
{
  "targetBoard": "board.example",
  "lifetime": "transient"
}
```

Required lifetimes:

- `persistent`
- `transient`

### persistent

The target becomes both the persistent baseline and current Board for the current Board context.

### transient

The target becomes current while the persistent baseline remains unchanged.

A transient chain does **not** create an unwind stack. When a terminal action completes or the transient chain is explicitly cancelled, `currentBoard` resets directly to the current persistent baseline.

If a persistent transition occurs while traversing transient Boards, the persistent target becomes the new baseline immediately.

## 7. Board context and lifetime

Persistent Board state is scoped by:

```text
(profile revision, layer ID, key ID)
```

Each context starts with the Layer's configured root `boardRef` as both `persistentBoard` and `currentBoard`.

This prevents a persistent selection entered through one physical key from implicitly changing another key's Board graph.

Profile reload, layer replacement, or context invalidation resets Board context according to the same immutable-snapshot/invalidation rules used by the common runtime.

## 8. Hold and other non-spatial triggers

Hold remains a trigger, not a coordinate.

A BoardEntry may define:

```json
{
  "hold": {
    "delayMs": 450,
    "onStart": [],
    "transition": {
      "targetBoard": "board.hold",
      "lifetime": "transient"
    }
  }
}
```

The Hold transition uses the exact same BoardTransition semantics as a spatial transition. Hold therefore does not introduce a separate Board navigation system.

Repeat Actions may remain available for non-transitioning Hold behavior. A HoldTrigger that performs a Board transition MUST NOT also begin a repeat loop in v2.

## 9. Runtime state

The platform-common Board runtime exposes at least the conceptual state:

```text
contextRootBoard
persistentBoard
currentBoard
selectedCoordinate
currentBoardOrigin / physical anchor
transitionCount
terminal/cancel state
```

Exact implementation names are not normative.

A terminal BoardEntry action completes the transient chain and resets `currentBoard` to `persistentBoard`. A persistent transition does not complete the chain by itself.

Cancellation/invalidation dispatches no pending terminal Action and resets any transient current Board to the persistent baseline.

## 10. Resource and cycle policy

v2 bounds:

- encoded Profile: 1 MiB;
- key definitions: 256;
- layouts: 32;
- placements per layout: 256;
- layers: 32;
- key->Board refs per layer: 256;
- Boards: 512;
- entries per Board: 256;
- total Board entries: 16384;
- macros: 128;
- endpoint Actions: 16;
- Board transitions committed within one uninterrupted Board interaction chain: 64;
- coordinate x/y: -127...127.

Board graph cycles are valid. Transitions occur only after explicit spatial/non-spatial input and are never followed automatically merely because a target Board exists. The runtime transition-count limit prevents an interaction from growing without bound.

The validator rejects:

- duplicate Board IDs;
- duplicate coordinates within one Board;
- missing Board references;
- missing key references in Layer keyBoards;
- duplicate key mappings inside one Layer;
- out-of-range coordinates;
- invalid transition lifetime;
- Hold transition + repeat combination;
- aggregate limit violations.

## 11. v1 compatibility compilation

A valid v1 `layer + key + BindingTrie` is normalized to Boards deterministically.

For each trie node that must expose children, create one compatibility Board.

- The trie node endpoint behavior, if any, becomes the Board center `(0,0)` terminal entry.
- Each child Direction8 becomes the corresponding unit coordinate.
- A child with no children becomes a terminal BoardEntry using that child node's behavior.
- A child with children becomes a `transient` transition to the child Board.
- If that child also has endpoint behavior, the target child Board center carries that endpoint behavior.
- Hold/repeat behavior attached to a trie node is carried by that Board's center entry.
- The Layer's key maps to the root compatibility Board.

Thus v1 `[E]`, `[E,N]`, `[E,E]` and ordinary four-way Japanese bindings are expressible without treating "stage 2" as a v2 semantic primitive.

Compatibility Board IDs are internal and deterministic; they are not persisted back into the v1 source document.

## 12. Product migration rule

The built-in product Profile may remain v1 while the compatibility compiler is introduced. Before #23 is accepted, the product path MUST additionally prove native v2 Board execution with:

- ordinary Japanese tap + four cardinal selections;
- an eight-direction Board;
- a chained Board transition reproducing accepted multi-stage behavior;
- a Hold -> Board transition;
- a non-contiguous target Board;
- persistent and transient lifetimes;
- Profile authoring/storage round-trip.

The final accepted product may ship its built-in Profile as v2 once regression equivalence is established.

## 13. Cross-platform authority

The shared Rust runtime owns:

- v1/v2 decode and validation;
- v1 compatibility compilation;
- Board graph/runtime state;
- BoardTransition lifetime semantics;
- canonical coordinate/direction compatibility mapping.

Swift/iOS and Kotlin/Android adapters expose this shared behavior. They may own physical touch/event adaptation and presentation, but they MUST NOT independently reinterpret Board semantics.

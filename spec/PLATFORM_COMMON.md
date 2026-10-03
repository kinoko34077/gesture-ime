# 2026-10-04 Board Graph v2 semantic revision

Profile v1 remains a supported compatibility input. Native Profile v2 board semantics are defined by `spec/BOARD_GRAPH_V2.md` and `spec/profile/gesture-ime.profile.v2.schema.json`.

For v2, Board-local relative coordinates and BoardTransition lifetime semantics supersede any earlier implication that Direction8 or a two-token GesturePath is the durable authoring/runtime ceiling. Direction8 remains the initial physical-selection compatibility vocabulary, not the v2 topology limit.

The shared Rust runtime is the semantic authority for v1/v2 decode, compatibility normalization, Board state and transition semantics. Platform adapters must not independently reinterpret this contract.

---

# Gesture IME Platform-Common Specification v1

Status: Canonical platform-common contract for v0/Phase 0

Authority: repository Issues #1-#6 define the requirements, design history, hardening findings, and implementation roadmap. This document is the implementation-facing platform-common semantic authority produced by #6. When platform code disagrees with this document, platform code is wrong until this document is intentionally revised.

## 1. Scope and responsibility boundary

This specification defines semantics that must be shared by iOS and Android implementations:

- ProfileBundle v1 meaning and activation rules;
- Direction8 and GesturePath meaning;
- binding-trie compilation and eligible-direction behavior;
- GestureSession state transitions;
- virtual-anchor behavior for multi-stage gestures;
- BindingBehavior release/hold semantics;
- ActionInvocation identity and validation boundary;
- common resource limits;
- cancel/invalidate/profile-reload behavior;
- platform-common conformance expectations.

This specification does **not** define:

- UIKit, SwiftUI, Android View, or Compose types;
- UIInputViewController or InputMethodService lifecycle details;
- haptic implementation;
- OS storage primitives or permissions;
- a specific kana-kanji converter;
- final real-device gesture thresholds;
- final candidate/ranking architecture.

The common canon owns **what observable gesture/profile behavior means**. Platform implementations own acquisition of native events, rendering, OS IME APIs, storage mechanisms, haptics, and concrete conversion adapters.

## 2. Platform-neutral vocabulary

### 2.1 Geometry

Canonical logical coordinates use screen orientation:

- x increases to the right;
- y increases downward.

A point is conceptually:

```text
GesturePoint(x: finite number, y: finite number)
```

Distances in GesturePolicy are normalized to the minimum active key dimension unless a later schema version explicitly defines another unit:

```text
normalizedDistance = euclideanDistance / min(keyWidth, keyHeight)
```

Platform-native point/vector types are adapters only and are not canonical types.

### 2.2 Direction8

The canonical directional vocabulary is exactly:

```text
n, ne, e, se, s, sw, w, nw
```

Using x-right/y-down coordinates, direction centers are:

| Direction | Degrees |
|---|---:|
| e | 0 |
| se | 45 |
| s | 90 |
| sw | 135 |
| w | 180 |
| nw | 225 |
| n | 270 |
| ne | 315 |

Angular distance is the shortest circular distance in degrees.

### 2.3 GestureToken and GesturePath

A GesturePath is an ordered sequence of gesture tokens. Profile schema v1 activates only directional tokens:

```json
{"direction":"e"}
```

Tap is the empty path `[]`. Examples are `[e]`, `[ne]`, `[e,n]`, and `[e,e]`.

The token model is intentionally extensible, but non-directional path tokens such as hold are **not active Profile v1 path syntax**. Hold behavior is represented by BindingBehavior in v1.

Active Profile v1 accepts at most two directional tokens per path. Future representations may increase this through a versioned policy/schema change.

## 3. ProfileBundle v1

The serialized contract is defined by `profile/gesture-ime.profile.v1.schema.json`.

The `schema` field selects the serialization contract. The numeric `version` field is profile-local revision metadata; it does not select or upgrade the schema version.

A ProfileBundle composes:

- `gesturePolicy` — recognition parameters only;
- `keyDefinitions` — stable key identity and fallback presentation;
- `layouts` — placement of key identities;
- `bindingSets` — GesturePath to BindingBehavior mappings;
- `layers` — layout/binding-set composition;
- `macros` — named finite ActionInvocation sequences;
- optional presentation/theme extension data.

A ProfileBundle does not own user dictionary, conversion history, learned ranking/personalization, current composition, or the current GestureSession. Profile switching therefore must not inherently reset or fork language/user-learning state.

### 3.1 Unknown fields

Unknown object members are reserved for forward-compatible extension. Import/export tooling that rewrites a profile must preserve unknown members where it can round-trip them losslessly. Runtime v1 must not assign meaning to unknown members.

Unknown Action IDs are different: an ActionInvocation must resolve to a known common action or an explicitly registered capability-gated extension action before activation. Otherwise activation fails with `E_UNKNOWN_ACTION`.

## 4. Resource policy v1

The following are activation safety limits, not performance claims:

| Resource | Maximum |
|---|---:|
| encoded ProfileBundle | 1 MiB |
| key definitions | 256 |
| layouts | 32 |
| placements per layout | 256 |
| layers | 32 |
| binding sets | 64 |
| bindings per key within one binding set | 128 |
| total bindings | 8192 |
| total compiled trie nodes | 16384 |
| active GesturePath tokens | 2 |
| macros | 128 |
| ActionInvocations in one binding endpoint | 16 |
| ActionInvocations in one macro | 32 |
| one string argument payload | 4096 UTF-8 bytes |
| encoded arguments object per ActionInvocation | 16384 bytes |
| runtime layer stack depth | 16 |

Validation must reject an over-limit profile before activation and before construction of the runtime compiled profile/trie. Bounded temporary validation structures are permitted.

`1 MiB` means 1,048,576 bytes of the encoded profile document supplied for activation.

Trie-node count means the sum of each binding-trie root plus each unique token-prefix node across all `(bindingSet, keyID)` tries. Implementations may preflight this count before allocating the final runtime trie.

## 5. Binding-trie semantics

Bindings are compiled separately for each `(bindingSet, keyID)`.

A trie node conceptually has optional `behavior` and token-keyed `children`.

Compilation rules:

1. each binding path starts at one root for its `(bindingSet, keyID)`;
2. each token advances through one child edge;
3. the binding behavior attaches to the terminal node;
4. two bindings with the same `(bindingSet, keyID, GesturePath)` are invalid (`E_DUPLICATE_BINDING_PATH`);
5. path prefixes are valid: `[e]` may have a behavior while `[e,n]` also exists;
6. compiled runtime data must contain no unresolved key/layout/layer/action/macro references.

### 5.1 Eligible directions

The recognizer does not globally expose all eight directions.

At a current trie node, the eligible direction set is exactly the set of **directional child tokens** of that node.

Consequences:

- a default Japanese key with only W/N/E/S children remains a four-direction gesture even though Direction8 exists;
- adding NE to the binding data makes NE eligible without recognizer code changes;
- after `[e]`, if only `[e,n]` and `[e,s]` exist, only N and S are eligible for stage 2.

Bindings constrain the physical grammar by defining legal next tokens, but they do not assign global semantic meaning to directions.

## 6. GesturePolicy semantics

Profile v1 recognition policy contains normalized distances and angular hysteresis. Exact product defaults are not fixed by Phase 0; profiles/fixtures provide explicit values.

Required invariants:

- values are finite;
- `deadZone >= 0`;
- stage commit distances are greater than or equal to `deadZone`;
- `maxDirectionalStages == 2` in Profile v1;
- `angularHysteresisDegrees >= 0` and `< 45`.

### 6.1 Candidate selection

For displacement from the current anchor:

1. below `deadZone`, there is no directional candidate;
2. otherwise consider only eligible directions from the current trie node;
3. without a current candidate, choose the eligible direction whose center has the smallest angular distance; ties resolve by canonical order `n, ne, e, se, s, sw, w, nw`;
4. with a current uncommitted candidate, another direction replaces it only when `angularDistance(new) + angularHysteresisDegrees < angularDistance(current)`;
5. a candidate commits as the next GestureToken only after the stage-specific commit distance is reached;
6. once committed, that stage direction is locked and is not rewritten by later movement.

Hysteresis affects pre-commit candidate switching only. Real-device tuning may revise numeric policy values without changing this semantic rule.

## 7. GestureSession state machine

Conceptual non-terminal phases are `idle`, `pressed`, and `selected`. Terminal outcomes are `committed`, `cancelled`, and `invalidated`.

A session owns at least:

- keyID;
- immutable compiled-profile revision/snapshot identity;
- current GesturePath;
- current trie node;
- current virtual anchor;
- current uncommitted candidate direction, if any;
- committed directional-stage count;
- endpoint hold/repeat state.

### 7.1 Start

On a valid single touch-down over a key:

1. capture the active compiled-profile snapshot/revision;
2. select the binding trie root for the current layer/binding set/key;
3. set the touch position as the initial anchor;
4. set path to `[]` and phase to `pressed`;
5. if the root has hold behavior, schedule it for that root endpoint.

### 7.2 Direction commit and virtual anchor

When a direction commits:

1. cancel pending hold/repeat work owned by the previous endpoint;
2. append the direction token to GesturePath;
3. advance to the matching trie child;
4. increment committed directional-stage count;
5. set the **current touch position at commitment** as the new virtual anchor;
6. clear the uncommitted candidate;
7. make the new trie node the current endpoint;
8. schedule that endpoint's hold behavior if present;
9. expose that node's directional children as the next eligible set.

Therefore movement E then N is `[e,n]`; stage 2 is never recomputed from the original touch-down. `[e,e]` is also valid because the anchor resets after the first E commit.

### 7.3 Touch-up commit

On touch-up, if the session is still valid:

- current path `[]` selects the root endpoint;
- a committed path selects its current trie endpoint;
- if that endpoint has no behavior, commit produces no semantic actions;
- otherwise release behavior follows section 8;
- the session then becomes terminal `committed` and owns no pending timers/tasks.

## 8. BindingBehavior and hold semantics

A BindingBehavior has optional presentation data, `onRelease` actions, and optional hold behavior.

A hold behavior has `delayMs`, `onStart`, optional repeating behavior (`intervalMs` + actions), and `suppressOnReleaseAfterStart`.

Rules:

1. the hold delay starts when that trie node becomes the current endpoint;
2. leaving an endpoint by committing another path token cancels its pending hold/repeat work;
3. when delay elapses on the still-current valid endpoint, `onStart` dispatches once and the endpoint is marked hold-started;
4. after hold starts, that endpoint is **hold-locked** for the remainder of the touch: no further directional token may commit in that session;
5. repeat actions, if configured, dispatch at the configured interval while the same endpoint remains current and session valid;
6. on valid touch-up, `onRelease` dispatches unless hold started and `suppressOnReleaseAfterStart == true`;
7. all pending hold/repeat work is cancelled at every terminal transition.

## 9. Cancellation and invalidation

### 9.1 Cancel

Cancel represents an input interruption that must not produce semantic output, including native touch cancellation/system interruption, conflicting unsupported multitouch in v0, or key/view disappearance where the interaction cannot continue safely.

On cancel:

- dispatch no endpoint `onRelease`;
- dispatch no new hold start or repeat action;
- cancel pending hold/repeat work immediately;
- return terminal `cancelled` with an empty semantic-action result.

The terminal guarantee is prospective: semantic actions already dispatched while the session was valid before the cancel event are not retroactively revoked. From the cancel transition onward, that session may dispatch nothing further. A conformance case expecting zero total dispatch must therefore cancel before any configured hold action could validly fire.

V0 unsupported multitouch rule: if a conflicting second touch arrives while a session is active, cancel the active session and ignore new gesture starts until the interaction returns to zero active touches.

### 9.2 Invalidate

Invalidate is semantically identical to cancel regarding action dispatch, but records that the compiled runtime context ceased to be valid.

Causes include active Profile replacement/reload, active runtime reset that invalidates the session snapshot, or detected compiled-profile revision mismatch.

On invalidation:

- dispatch no endpoint `onRelease`;
- dispatch no new hold start or repeat action;
- cancel pending hold/repeat work;
- return terminal `invalidated` with an empty semantic-action result.

### 9.3 Profile reload

A newly compiled Profile never mutates the semantics of an already-started GestureSession.

If a profile replacement/reload is accepted while a gesture is active:

1. invalidate the active session;
2. install the new compiled profile as the next-session snapshot;
3. do not reinterpret the current finger path under the new profile;
4. accept a new gesture only after the current native touch interaction fully ends.

## 10. Macro semantics v1

A binding endpoint may invoke `macro.run`.

A Profile v1 macro body is a finite sequence of ordinary ActionInvocations. A macro body containing `macro.run` is invalid (`E_MACRO_NESTING`).

Therefore macro expansion depth is exactly one, runtime performs no recursive macro resolution, and cycle discovery is unnecessary for active v1.

## 11. Validation order and fail-closed activation

Recommended logical validation order:

1. encoded byte-size bound;
2. JSON decoding and schema identifier/version;
3. structural JSON Schema validation;
4. resource-count limits not expressible locally in schema;
5. uniqueness and reference integrity;
6. GesturePolicy invariants;
7. duplicate binding-path detection;
8. Action ID and argument validation;
9. macro nesting policy;
10. preflight compiled-trie node count;
11. only then construct/activate the runtime compiled profile.

An invalid new profile must not replace a last-known-good active profile.

Canonical validation codes used by v1 conformance fixtures:

| Code | Meaning |
|---|---|
| `E_PROFILE_TOO_LARGE` | encoded bundle exceeds 1 MiB |
| `E_UNSUPPORTED_SCHEMA` | schema/version unsupported |
| `E_LIMIT_KEYS` | key limit exceeded |
| `E_LIMIT_LAYOUTS` | layout limit exceeded |
| `E_LIMIT_PLACEMENTS` | placement limit exceeded |
| `E_LIMIT_LAYERS` | layer limit exceeded |
| `E_LIMIT_BINDING_SETS` | binding-set limit exceeded |
| `E_LIMIT_BINDINGS_PER_KEY` | per-key binding limit exceeded |
| `E_LIMIT_BINDINGS_TOTAL` | total binding limit exceeded |
| `E_LIMIT_TRIE_NODES` | preflight trie-node limit exceeded |
| `E_PATH_DEPTH` | active v1 path exceeds two tokens |
| `E_LIMIT_MACROS` | macro limit exceeded |
| `E_LIMIT_ACTIONS` | action count limit exceeded |
| `E_ARGUMENT_TOO_LARGE` | argument/string payload limit exceeded |
| `E_LIMIT_LAYER_STACK` | runtime layer-stack push would exceed limit |
| `E_DUPLICATE_ID` | duplicate semantic ID in an array |
| `E_MISSING_REFERENCE` | referenced key/layout/binding/layer/macro missing |
| `E_DUPLICATE_BINDING_PATH` | duplicate key/path within a binding set |
| `E_UNKNOWN_ACTION` | unresolved Action ID |
| `E_INVALID_ACTION_ARGUMENTS` | known Action ID with invalid argument shape/value |
| `E_MACRO_NESTING` | macro body contains macro.run in v1 |
| `E_INVALID_GESTURE_POLICY` | policy invariant violated |

If multiple failures exist, implementations may report more than one, but first/UI ordering is not canonical. Fixtures requiring a specific code isolate that failure.

## 12. Action boundary

Common Action IDs and argument schemas are defined by `actions/action-registry.v1.md`.

Gesture recognition never interprets action arguments. Binding compilation validates ActionInvocations but does not execute them.

Platform/extension actions must be explicitly namespaced and capability-gated; they may not silently reuse a common Action ID with different semantics. A runtime lacking the declared action capability rejects activation instead of treating the action as NoOp.

## 13. Conformance

`conformance/README.md` defines the fixture contract and `conformance/manifest.json` enumerates the initial corpus.

Shared fixtures test common semantics. Platform-only behavior belongs in platform suites and must not redefine common semantics.

A Swift and Kotlin implementation are conformant when, for every applicable common fixture, they produce the fixture's expected path/result/validation class under the same explicit policy input.

Semantic parity does not require identical internal types or line-for-line ports.

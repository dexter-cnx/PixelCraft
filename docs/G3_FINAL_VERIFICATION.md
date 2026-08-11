# G3 Final Verification

## Status

**G3 IMPLEMENTATION COMPLETE THROUGH G3.4 — VERIFICATION IN PROGRESS**

Branch: `feature/editor-gpu-production`
Base: `main`
G2 merge baseline: `85c44761e9a88d4b0b0bdef5b8ea612ff3940ca8`

This document is the accumulating verification record for G3 — Production Rendering Pipeline.

Rust remains authoritative for committed edit semantics, history, checkpoints, session recipe, and full-resolution export. GPU rendering remains an interactive preview path and must fail closed to the valid Rust preview.

---

## G3.0 Baseline and branch setup

- [x] G2 merged into `main` via PR #5.
- [x] Created `feature/editor-gpu-production` from updated `main`.
- [x] Created this verification record before behavior changes.
- [x] Flutter analyzer baseline recorded.
- [x] Flutter state/widget baseline recorded.
- [x] Golden baseline recorded.
- [x] Rust fmt/clippy/tests baseline recorded.
- [x] Film + Creative LUT verification baseline recorded.
- [x] Confirm G2 diagnostics remain available in debug builds.

### Baseline evidence

GitHub Actions `Pixel Craft CI` run #21 for the initial G3 branch commit completed successfully on 2026-08-11. The workflow covered Flutter analyze, state/widget tests, macOS Golden tests, Rust fmt/clippy/tests, generated bridge verification, and GPU LUT verification.

Baseline result: **PASS**.

---

## Branch-level product hardening added during G3

- [x] Android main activity locked to portrait.
- [x] iOS/iPad supported orientations reduced to portrait.
- [x] Flutter runtime requests `DeviceOrientation.portraitUp` before app startup.
- [x] Removed accidental empty root files `__tmp_noop__`, `__tmp_noop2__`, and `__tmp_noop3__`.

---

## G3.1 Multi-adjustment GPU composition

### Architecture

The G3 live-preview path no longer builds a neutral state containing only the currently dragged control. `GpuEditorRenderPlan` reads the active authoritative Rust recipe range:

```text
operations[checkpoint_cursor .. cursor]
```

and builds the complete representable draft. The currently dragged value is then applied as a transient replacement of its Rust semantic slot. If the slot does not yet exist, the transient node is appended, matching the current Rust transaction behavior.

Example:

```text
Rust active draft
Brightness 1.20
Contrast   1.30
Saturation 0.85

Transient drag
Brightness -> 1.25

GPU plan
Brightness 1.25
Contrast   1.30
Saturation 0.85
```

### Implemented

- [x] Complete active Adjust state comes from the Rust session recipe.
- [x] Brightness / Contrast / Saturation / Sharpen / Gaussian Blur are modeled as independent draft slots.
- [x] Existing transient slot is replaced in place.
- [x] New transient slot is appended according to Rust draft insertion semantics.
- [x] Rust commit-on-release path is unchanged.
- [x] Unsupported or unfaithful operation order fails closed to Rust preview.
- [x] Old single-purpose `GpuEditorAdjustmentDraft` parser was removed after the ordered render plan superseded it.
- [x] Unit coverage includes simultaneous B+C+S, checkpoint boundaries, slot insertion, and order mismatch fallback.

### Important order rule

The current iOS Metal renderer has a fixed stage topology. G3 does **not** silently reorder Rust operations. A GPU plan is enabled only when the authoritative Rust order can be represented by the native stages. Otherwise the valid Rust preview remains visible.

Current native stage topology:

```text
optional compute Creative
 -> Gaussian Blur
 -> Sharpen
 -> Brightness
 -> Contrast
 -> Saturation
 -> optional final LUT
```

This is deliberate correctness behavior, not an attempt to claim arbitrary-order GPU equivalence.

### Verification still required for closure

- [ ] G3 multi-adjust deterministic physical-device image parity recorded.
- [ ] Sharpen + Blur order-sensitive physical-device cases recorded.
- [ ] Representative G3 multi-adjust physical-device latency recorded.
- [ ] Existing G2 single-adjust physical-device parity rechecked after final G3 head.

Existing G2 numeric/latency evidence remains a regression baseline but is not relabeled as new G3 device evidence.

---

## G3.2 Cross-tool GPU composition

### Implemented representation

`GpuEditorRenderPlan` parses the complete supported active draft across:

```text
Adjust + Creative + Film
```

Operation order comes from the Rust recipe; the Flutter layer does not infer order from the UI category.

Supported Creative paths:

- `grayscale` / `invert`: verified native compute stage.
- `vintage` / `oceanic` / `lofi` / `dramatic` / `golden` / `pastel_pink`: canonical Rust-generated 33^3 Creative LUT through the native LUT runtime.

### Faithful-or-fallback contract

The current native editor renderer has one final 3D-LUT slot. Therefore:

- [x] Compute Creative + representable Adjust + Film can be planned when Rust order matches native stage order.
- [x] Representable Adjust + canonical Creative LUT can be planned when Film is not active.
- [x] Creative-LUT + Film together explicitly falls back to Rust because both require the same native LUT slot.
- [x] Transform/unknown active nodes explicitly fall back to Rust.
- [x] Any Rust operation order that cannot be reproduced by the fixed native stages explicitly falls back to Rust.
- [x] Host regression tests cover representative cross-tool plans, slot replacement, LUT-slot conflict, transforms, and order mismatches.

This means G3.2 implements the complete **supported** cross-tool planning contract without misrepresenting unsupported combinations. Arbitrary ordered composition would require a different native multi-pass render graph and is not approximated here.

### Verification still required for closure

- [ ] Representative compute-Creative + Adjust + Film physical-device parity recorded.
- [ ] Representative Creative-LUT + Adjust physical-device parity recorded.
- [ ] Physical-device Rust fallback confirmed for Creative-LUT + Film conflict.
- [ ] Representative operation-order fallback cases manually/device validated.

---

## G3.3 Production renderer lifecycle

### Implemented

`EditorScreen` now observes Flutter application lifecycle and memory pressure.

- [x] Background/inactive/hidden/detached states invalidate the GPU presentation state and destroy the renderer.
- [x] Foreground resume leaves the valid Rust preview visible and recreates the renderer lazily on the next eligible gesture.
- [x] Memory pressure drops the renderer and preserves Rust semantics.
- [x] Renderer generation guards reject/destroy stale async renderer creation.
- [x] Activation generation guards reject stale recipe/source/update work.
- [x] Rust checkpoint/source replacement invalidates the active GPU draft.
- [x] Renderer create/update failures fail closed to Rust preview.
- [x] Renderer destruction on editor disposal is idempotent at the Dart presentation layer.
- [x] Platform-view layout continues to use the existing MTKView drawable resize path.
- [x] No lifecycle path mutates Rust semantic state.

### Verification still required for closure

- [ ] Physical device background -> foreground stress recorded.
- [ ] Physical device Editor open/close/reopen loop recorded.
- [ ] Repeated Camera -> Editor transition stress recorded.
- [ ] Native/platform-view recreation stress recorded.
- [ ] Memory-pressure behavior recorded where practically observable.
- [ ] Confirm no stale native overlay after all stress cases.

---

## G3.4 GPU presentation/session state cleanup

### Implemented

G2's scattered `_gpuDraftKind`, `_gpuDraftKey`, `_gpuDraftValue`, activation serial, renderer epoch, and temporary recipe ownership have been replaced by an explicit presentation-only model:

```text
GpuEditorDraftSession
  checkpointGeneration
  rendererGeneration
  activationGeneration
  status
  transient
  authoritative recipe snapshot
  GpuEditorRenderPlan
  fallbackReason
```

- [x] Presentation state is separated from Rust semantic state.
- [x] Activation/checkpoint/renderer generations are centralized.
- [x] Fallback status/reason is centralized.
- [x] Stale-work behavior is unit-testable and covered.
- [x] Ordered supported operations live in `GpuEditorRenderPlan` rather than scattered UI fields.
- [x] Superseded adjustment-only parser/test duplication removed.
- [x] `GPU READY`, `GPU LIVE`, and `Metal live draft` labels are debug-only.
- [x] Home GPU diagnostics entry remains debug-only by default.

The screen still owns native renderer/file resources, while `GpuEditorDraftSession` owns only presentation lifecycle metadata. This keeps native resource ownership explicit without turning the presentation model into a second semantic edit graph.

---

## Host CI status

The last fully verified pre-refactor head passed GitHub Actions. The consolidated G3.1-G3.4 implementation is being revalidated by the PR CI after the ordered-plan/session/lifecycle refactor.

Do not mark the final host closure gate until the latest head has passed both `validate` and macOS Golden jobs.

---

## G3 closure gate

### Host gates

- [ ] Flutter analyzer/test/golden pass on final G3 head.
- [ ] Rust fmt/clippy/tests pass on final G3 head.
- [ ] LUT verification pass on final G3 head.

### Renderer correctness/performance gates

- [ ] Existing G2 single-adjust parity retained on final G3 head.
- [ ] Multi-adjust parity pass on physical iOS device.
- [ ] Representative Adjust + Creative + Film parity pass.
- [ ] Operation-order/fallback cases pass.
- [ ] Reference-device p95 remains within realtime budget.

### Lifecycle gates

- [ ] Background/foreground stress pass.
- [ ] Editor recreate/reopen stress pass.
- [ ] Repeated Camera -> Editor stress pass.
- [ ] Failure fallback returns to valid Rust preview.

### Semantic authority

- [x] Full-resolution export path remains Rust-authoritative by implementation.
- [x] GPU presentation failures do not commit semantic operations.

**G3 may be marked CLOSED / Ready for review only after all required closure gates above are supported by recorded evidence.**

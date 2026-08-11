# G3 Final Verification

## Status

**G3 IMPLEMENTATION COMPLETE THROUGH G3.4 — AUTOMATED DEVICE GATES PASS — MANUAL RUNTIME STRESS REMAINS**

Branch: `feature/editor-gpu-production`
Base: `main`
G2 merge baseline: `85c44761e9a88d4b0b0bdef5b8ea612ff3940ca8`
Physical-device automated verification commit: `8eb6e1ebc8766720b524340a402fa223e5487b75`
Verification date: 2026-08-11

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

`GpuEditorRenderPlan` reads the active authoritative Rust recipe range:

```text
operations[checkpoint_cursor .. cursor]
```

and builds the complete representable draft. The currently dragged value replaces only its semantic slot. If the slot does not yet exist, the transient node is appended, matching the current Rust transaction behavior.

The current iOS Metal renderer has a fixed stage topology:

```text
optional compute Creative
 -> Gaussian Blur
 -> Sharpen
 -> Brightness
 -> Contrast
 -> Saturation
 -> optional final LUT
```

G3 does not silently reorder Rust operations. An unrepresentable authoritative order fails closed to Rust preview.

### Implemented

- [x] Complete active Adjust state comes from Rust session recipe.
- [x] Brightness / Contrast / Saturation / Sharpen / Gaussian Blur are independent draft slots.
- [x] Existing transient slot is replaced in place.
- [x] New transient slot is appended according to Rust draft insertion semantics.
- [x] Rust commit-on-release path is unchanged.
- [x] Unsupported or unfaithful operation order fails closed to Rust preview.
- [x] Host unit coverage includes simultaneous B+C+S, checkpoint boundaries, slot insertion, and order mismatch fallback.

### Physical-device automated evidence

Device GPU reported by native harness: **Apple A13 GPU**.

- [x] Existing native identity LUT parity retained: `maxError=0.0019608139991760254`.
- [x] All six Film Profile Pack v2 LUT parity cases passed.
- [x] Adjustment parity passed: `overallMaxChannelError=0.0019263029098510742`, tolerance `0.00392156862745098`, 9 cases.
- [x] Brightness cases passed.
- [x] Contrast cases passed.
- [x] Saturation cases passed.
- [x] Sharpen cases passed.
- [x] Gaussian Blur parity passed: `overallMaxChannelError=0.0`, tolerance `0.00784313725490196`, 5 cases.
- [x] Adjustment + Film realtime benchmark passed at 1024x1024 / 60 iterations:
  - average `1.020 ms`
  - p50 `1.000 ms`
  - p95 `1.104 ms`
  - p99 `1.821 ms`
  - max `1.821 ms`
  - target `16.67 ms`
- [x] Heavy Gaussian Blur benchmark passed at 1024x1024 / 60 iterations:
  - average `9.787 ms`
  - p95 `11.418 ms`
  - p99 `11.514 ms`
  - max `11.514 ms`
  - target `16.67 ms`

Automated G3.1 device result: **PASS**.

### Manual verification still required

- [ ] Confirm multi-adjust visual continuity while dragging one active slot.
- [ ] Confirm Sharpen + Blur visual continuity and no semantic jump on release.
- [ ] Undo/Redo once after a multi-adjust sequence and confirm no stale Metal overlay.

---

## G3.2 Cross-tool GPU composition

`GpuEditorRenderPlan` parses supported active draft state across Adjust + Creative + Film using authoritative Rust operation order.

Supported Creative paths:

- `grayscale` / `invert`: native compute stage.
- `vintage` / `oceanic` / `lofi` / `dramatic` / `golden` / `pastel_pink`: canonical Rust-generated 33^3 Creative LUT.

### Faithful-or-fallback contract

- [x] Compute Creative + representable Adjust + Film can be planned when Rust order matches native stage order.
- [x] Representable Adjust + canonical Creative LUT can be planned when Film is not active.
- [x] Creative-LUT + Film explicitly falls back because both require the native final LUT slot.
- [x] Transform/unknown active nodes explicitly fall back to Rust.
- [x] Unsupported Rust operation order explicitly falls back to Rust.
- [x] Host regression tests cover representative cross-tool plans, LUT-slot conflict, transforms, slot replacement, and order mismatch.

### Physical-device automated evidence

- [x] Creative compute parity passed: `overallMaxChannelError=0.0`, tolerance `0.00392156862745098`, 6 cases.
- [x] All six Film LUT native parity cases passed.
- [x] Representative adjustment + Film workload meets realtime p95 budget (`1.104 ms <= 16.67 ms`).

Automated G3.2 device result: **PASS for the native primitives used by supported render plans**.

### Manual verification still required

- [ ] Confirm one representable Adjust + grayscale/invert + Film composition visually.
- [ ] Confirm one Adjust + Creative LUT composition visually.
- [ ] Confirm Creative-LUT + Film conflict stays on Rust preview instead of showing a partial Metal result.
- [ ] Confirm one intentionally unsupported operation-order/transform case falls back cleanly.

---

## G3.3 Production renderer lifecycle

### Implemented

- [x] Background/inactive/hidden/detached invalidates GPU presentation state and destroys renderer.
- [x] Foreground resume leaves Rust preview visible and recreates renderer lazily.
- [x] Memory pressure drops renderer and preserves Rust semantics.
- [x] Renderer generation rejects stale async renderer creation.
- [x] Activation generation rejects stale recipe/source/update work.
- [x] Rust checkpoint/source replacement invalidates active GPU draft.
- [x] Renderer create/update failures fail closed to Rust preview.
- [x] Renderer disposal is idempotent at Dart presentation layer.
- [x] No lifecycle path mutates Rust semantic state.

### Physical-device automated evidence

- [x] Renderer destroy/recreate loop passed **12/12 cycles** with unique renderer IDs and no native error.

Automated G3.3 renderer recreation result: **PASS**.

### Manual verification still required

- [ ] Background -> foreground x10.
- [ ] Editor close/reopen x10.
- [ ] Camera -> Editor x5.
- [ ] Confirm no stale image/native overlay after stress.
- [ ] Observe memory-pressure/background recovery where practical.

---

## G3.4 GPU presentation/session state cleanup

G2 scattered draft fields were replaced by `GpuEditorDraftSession` containing presentation-only lifecycle metadata:

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
- [x] Supported ordered operations live in `GpuEditorRenderPlan`.
- [x] Superseded adjustment-only parser duplication removed.
- [x] GPU engineering labels are debug-only.
- [x] Home GPU diagnostics entry is debug-only by default.

### Manual verification still required

- [ ] Original/Before view never leaves Metal overlay above the original image.
- [ ] Checkpoint change cannot reactivate an older async renderer/draft.
- [ ] Native preview failure does not alter Rust history/recipe.
- [ ] Release build does not show GPU engineering labels.

---

## Physical-device automated run summary

The consolidated `flutter drive` verification session completed successfully on physical iOS hardware using isolated verification bundle `dev.cnxdev.pixelcraft.g3verify`.

```text
Native identity LUT parity: PASS
Film Profile Pack v2 LUT parity (6/6): PASS
G3.1 adjustment parity: PASS
G3.1 Gaussian Blur parity: PASS
G3.2 Creative compute parity: PASS
Adjustment + Film p95: 1.104 ms / target 16.67 ms — PASS
Heavy Blur p95: 11.418 ms / target 16.67 ms — PASS
Renderer recreate: 12/12 — PASS
Overall automated device gate: PASS
```

The verification application used a separate bundle ID so the normal development install remained untouched.

---

## G3 closure gate

### Host gates

- [x] G3.1-G3.4 host CI passed before device-harness follow-up changes.
- [ ] Latest final PR head must pass Flutter analyzer/test/golden after this verification-record update.
- [ ] Latest final PR head must pass Rust fmt/clippy/tests and LUT verification after this verification-record update.

### Renderer correctness/performance gates

- [x] Existing native Film/LUT parity retained.
- [x] Core adjustment parity passes on physical iOS device.
- [x] Gaussian Blur parity passes on physical iOS device.
- [x] Creative compute parity passes on physical iOS device.
- [x] Reference-device p95 remains within realtime budget for both representative workloads.
- [ ] Multi-adjust visual semantic continuity manual check.
- [ ] Representative cross-tool visual composition manual check.
- [ ] Unsupported-plan Rust fallback manual check.

### Lifecycle gates

- [x] Native renderer create/destroy recreation 12/12 automated cycles pass.
- [ ] Background/foreground x10.
- [ ] Editor recreate/reopen x10.
- [ ] Camera -> Editor x5.
- [ ] Original/Before and stale-overlay manual checks.

### Semantic authority

- [x] Full-resolution export path remains Rust-authoritative by implementation.
- [x] GPU presentation failures do not commit semantic operations.
- [ ] Full-resolution Rust export smoke after manual stress.

**G3 may be marked CLOSED / Ready for review only after the remaining manual runtime gates and the latest final-head CI are recorded as PASS.**

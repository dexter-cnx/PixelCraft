# G3 Final Verification

## Status

**G3 IN PROGRESS**

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

### Initial gap confirmed

The G2 Editor live-preview path currently constructs a neutral `GpuEditorAdjustmentState` and overrides only the adjustment being dragged. Therefore an active Rust draft such as:

```text
Brightness 1.20
Contrast   1.30
Saturation 0.85
```

cannot yet be represented faithfully while dragging Brightness to 1.25; the GPU path previews only Brightness 1.25 instead of the complete active Adjust draft.

### Required implementation contract

- Build GPU adjustment state from the complete active Rust-backed Adjust control state.
- Override only the transiently dragged value.
- Preserve Rust commit-on-release.
- Do not create a second semantic edit graph in Flutter.
- If active draft state cannot be represented faithfully, keep the Rust preview instead of partially composing it.
- Preserve operation semantics for Sharpen and Gaussian Blur.

### Implementation progress

- [x] Added `GpuEditorAdjustmentDraft` recipe-backed composer.
- [x] Composer reads only active operations between `checkpoint_cursor` and `cursor`.
- [x] Composer keeps the active adjustment operation order for later renderer-order validation.
- [x] Transient slider value overrides only the currently dragged adjustment.
- [x] Unsupported Creative/Film/transform nodes fail closed instead of generating a partial Adjust state.
- [x] Added regression tests for Brightness + Contrast + Saturation, Sharpen + Blur, checkpoint bounds, malformed recipes, and unsupported active nodes.
- [ ] Wire the composer into `EditorScreen` GPU activation/update path.
- [ ] Validate renderer operation ordering against authoritative Rust semantics before widening GPU eligibility beyond the current single-node rule.

### Verification checklist

- [x] Composition-unit regression coverage for simultaneous Adjust slots.
- [ ] Brightness + Contrast + Saturation deterministic image parity.
- [ ] Sharpen + Blur deterministic image parity.
- [ ] Order-sensitive cases recorded where applicable.
- [ ] Representative multi-adjust latency benchmark recorded.
- [ ] Reference-device p95 remains within realtime budget.
- [ ] Existing G2 single-adjust parity remains passing after live-path wiring.

---

## G3.2 Cross-tool GPU composition

- [ ] Authoritative Rust operation order exposed to GPU presentation layer.
- [ ] Adjust + Creative + Film render plan implemented.
- [ ] Unsupported-node fallback is explicit and deterministic.
- [ ] Representative parity and operation-order cases recorded.

---

## G3.3 Production renderer lifecycle

- [ ] Background/foreground stress.
- [ ] Renderer/platform-view recreation.
- [ ] Editor reopen/close loops.
- [ ] Resize/orientation handling.
- [ ] Source/checkpoint replacement.
- [ ] Native creation/update failure fallback.
- [ ] Stale renderer cleanup.
- [ ] Repeated Camera -> Editor transitions.

---

## G3.4 GPU presentation/session state cleanup

- [ ] Consolidate ad-hoc GPU presentation fields without duplicating the Rust graph.
- [ ] Centralize invalidation and fallback reasons.
- [ ] Make stale-work behavior unit-testable.
- [ ] Keep diagnostics debug-only.

---

## G3 closure gate

- [ ] Flutter analyzer/test/golden pass on final G3 head.
- [ ] Rust fmt/clippy/tests pass on final G3 head.
- [ ] LUT verification pass on final G3 head.
- [ ] G2 single-adjust parity retained.
- [ ] Multi-adjust parity pass.
- [ ] Adjust + Creative + Film parity pass.
- [ ] Operation-order cases pass.
- [ ] Reference-device p95 within realtime budget.
- [ ] Background/foreground stress pass.
- [ ] Editor recreate/reopen stress pass.
- [ ] Failure fallback returns to valid Rust preview.
- [ ] Full-resolution export remains Rust-authoritative.

**G3 may be marked CLOSED only after all required gates above are supported by recorded evidence.**

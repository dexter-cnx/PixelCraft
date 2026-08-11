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
- [ ] Flutter analyzer baseline recorded.
- [ ] Flutter state/widget baseline recorded.
- [ ] Golden baseline recorded.
- [ ] Rust fmt/clippy/tests baseline recorded.
- [ ] Film + Creative LUT verification baseline recorded.
- [ ] Confirm G2 diagnostics remain available in debug builds.

### Baseline commands

```bash
flutter analyze
make test
make golden-test
make rust-fmt
make rust-clippy
make rust-test
make gpu-lut-verify
```

No G3 behavior should be changed until the baseline is clean or any pre-existing failure is explicitly recorded here.

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

### Verification checklist

- [ ] State/controller regression coverage for simultaneous Adjust slots.
- [ ] Brightness + Contrast + Saturation deterministic parity.
- [ ] Sharpen + Blur deterministic parity.
- [ ] Order-sensitive cases recorded where applicable.
- [ ] Representative multi-adjust latency benchmark recorded.
- [ ] Reference-device p95 remains within realtime budget.
- [ ] Existing G2 single-adjust parity remains passing.

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

- [ ] Flutter analyzer/test/golden pass.
- [ ] Rust fmt/clippy/tests pass.
- [ ] LUT verification pass.
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

# G4 Product Editor UX Verification

## Status

G4 implementation is **COMPLETE / VERIFICATION IN PROGRESS**.

Branch: `feature/editor-product-ux`

Draft PR: #7 `G4: product editor UX and session workflow`

G3 prerequisite:

- PR #6 merged into `main` on 2026-08-11.
- G3 merge commit: `86b9ca78c54326785133f66225dbf5bfd9108a17`.
- G4 branch was created from updated `main`.

## Architectural invariants

1. Rust remains authoritative for semantic edits, history, checkpoints, recipe and full-resolution export.
2. GPU/compositor state remains preview-only.
3. Tool switching is neither Apply nor Discard.
4. Active draft values remain remembered across tool switching.
5. Unsupported or failed GPU composition falls back to the valid Rust preview.
6. Product UI does not promise history behavior Rust cannot guarantee.
7. Reset rewrites only the active draft and never mutates an already Applied checkpoint.

---

## G4.0 — Clean branch / product baseline

User-reported clean baseline on 2026-08-11 before G4 behavior changes:

```text
flutter analyze      PASS
make test            PASS
make golden-test     PASS
make rust-fmt        PASS
make rust-clippy     PASS
make rust-test       PASS
make gpu-lut-verify  PASS
```

G3 physical/runtime evidence in `docs/G3_FINAL_VERIFICATION.md` remains the native renderer regression baseline.

---

## G4.1 — Tool-state UX — IMPLEMENTED

Implementation:

```text
lib/state/editor_recipe_summary.dart
lib/ui/widgets/editor_tool_panel.dart
lib/ui/screens/editor_screen.dart
```

- [x] Adjust section badge for active draft changes.
- [x] Per-Adjust changed indicator.
- [x] Neutral values surfaced (`1.0`, Gaussian Blur `0.0`).
- [x] Reset current Adjust parameter.
- [x] Reset Adjust section.
- [x] Reset active Creative slot.
- [x] Reset active Film slot.
- [x] Reset affects only operations after `checkpoint_cursor`.
- [x] Reset Adjust preserves Creative and Film draft slots.
- [x] Reset truncates stale redo tail as a new semantic branch.
- [x] Rewritten recipe is restored through Rust.
- [x] Rewritten recipe is persisted for recovery.
- [x] Discard Draft remains Rust checkpoint discard.
- [x] Apply remains Rust checkpoint promotion.

Tests:

```text
test/state/editor_recipe_summary_test.dart
```

---

## G4.2 — Before / After — IMPLEMENTED

- [x] Press-and-hold comparison.
- [x] Product terminology is `Before`.
- [x] Comparison source is the latest Apply checkpoint preview.
- [x] No full-resolution decode is needed for compare.
- [x] Entering Before invalidates the active GPU overlay.

```text
Import -> edit -> Apply checkpoint A -> more draft edits -> hold Before
                                                |
                                                v
                                           checkpoint A
```

---

## G4.3 — History UX — IMPLEMENTED

- [x] History action in Editor app bar.
- [x] Entries derived from authoritative recipe.
- [x] Applied checkpoint and active draft distinguished.
- [x] Human-readable common-operation labels.
- [x] Undo / Redo remain Rust operations.
- [x] No arbitrary jump-to-history-position UI.

Random-access history is intentionally deferred until Rust exposes a verified contract.

---

## G4.4 — Autosave / recovery — HARDENED

Implementation:

```text
lib/core/editor_session_store.dart
lib/ui/screens/home_screen.dart
```

- [x] Generation-based atomic recovery retained.
- [x] Recipe envelope validation before persistence.
- [x] Cursor bounds validation.
- [x] Checkpoint bounds validation.
- [x] Source fingerprint verification during restore.
- [x] Corrupt/mismatched newest generation rejected.
- [x] Older valid generation fallback.
- [x] Valid legacy recovery compatibility.
- [x] Home continues to present Resume / Discard explicitly.

CI-gated tests:

```text
test/state/editor_session_store_g4_test.dart
```

---

## G4.5 — Exit / unsaved-draft policy — IMPLEMENTED

No draft:

```text
Back -> exit
```

Active draft:

```text
Unapplied edits
[Continue Editing]
[Discard]
[Apply & Exit]
```

- [x] Continue Editing keeps draft.
- [x] Discard calls Rust checkpoint discard before exit.
- [x] Apply & Exit calls Rust Apply before exit.
- [x] Processing/export blocks exit until settled.
- [x] Apply and Export remain separate semantics.

---

## G4.6 — Product export UX — IMPLEMENTED

- [x] PNG / JPEG / WEBP format.
- [x] Lossy-quality control where relevant.
- [x] Original-source resolution policy.
- [x] Current-draft inclusion is communicated.
- [x] Full-resolution processing state.
- [x] Gallery-save result.
- [x] App-backup path.
- [x] Share action.
- [x] Metadata policy documented.

Current metadata policy:

> The Rust export path decodes and newly encodes the rendered image. Source EXIF/metadata is not currently re-attached, so metadata preservation is not claimed.

Invariant:

```text
GPU preview pixels are never export input.
```

---

## G4.7 — Product hardening / closure — VERIFYING

Documentation refreshed:

```text
docs/CODE_WALKTHROUGH.md
docs/walkthrough/16_g4_editor_product_ux.md
docs/G4_PRODUCT_UX_VERIFICATION.md
```

The previous main walkthrough was stale and still described G1 iOS as awaiting build/device validation. It has been replaced with the current G1-closed, G2/G3-merged and G4 product architecture.

Draft PR #7 runs repository CI against the actual G4 branch.

### Automated post-change gate

Latest PR-head CI must be green before G4 is marked CLOSED.

```text
Pixel Craft CI    PENDING
```

The pre-change baseline is not used as proof for the post-change implementation.

### Required physical/product smoke before closure

- [ ] Adjust changed indicator / Reset Parameter.
- [ ] Reset Adjust while Creative/Film draft remains active.
- [ ] Tool switching keeps remembered draft values.
- [ ] Apply clears current-draft indicators.
- [ ] Discard restores checkpoint.
- [ ] Before hold after an Apply checkpoint.
- [ ] History applied/draft boundary.
- [ ] Undo / Redo after reset.
- [ ] Background / foreground during draft.
- [ ] Exit -> Continue Editing.
- [ ] Exit -> Discard.
- [ ] Exit -> Apply & Exit.
- [ ] Terminate / Resume last edit.
- [ ] Full-resolution export + share.
- [ ] GPU failure/unrepresentable plan still falls back to valid Rust preview.

---

## Evidence log

### 2026-08-11 — G4 baseline

- PR #6 confirmed merged.
- `feature/editor-product-ux` created from merged `main`.
- User reported all requested Flutter/Rust/golden/LUT baseline gates PASS.

### 2026-08-11 — G4.1-G4.6 implementation

- Added authoritative recipe projection and deterministic draft reset rewriting.
- Added tool/parameter changed indicators and reset controls.
- Productized checkpoint comparison as Before.
- Added recipe-derived History sheet.
- Hardened recovery validation and source identity checking.
- Added unapplied-draft exit policy.
- Improved full-resolution export UX while preserving Rust authority.

### 2026-08-11 — Walkthrough audit

- Confirmed `docs/CODE_WALKTHROUGH.md` was stale relative to G1 closure and G2/G3.
- Rewrote the main walkthrough through G4.
- Added and finalized `docs/walkthrough/16_g4_editor_product_ux.md`.
- Corrected G4 recovery test references to the CI-gated `test/state` path.

### 2026-08-11 — PR verification

- Opened Draft PR #7.
- Latest PR-head CI PASS is not yet recorded; physical/product smoke remains required for full G4 closure.

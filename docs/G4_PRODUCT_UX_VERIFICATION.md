# G4 Product Editor UX Verification

## Status

G4 implementation is **COMPLETE / VERIFICATION IN PROGRESS**.

Branch: `feature/editor-product-ux`

Draft PR: #7 `G4: product editor UX and session workflow`

G3 prerequisite:

- PR #6 `G3: production rendering pipeline` merged into `main` on 2026-08-11.
- Merge commit: `86b9ca78c54326785133f66225dbf5bfd9108a17`.
- G4 branch was created from updated `main` after the merge.

## Architectural invariants

G4 preserves the verified G3 contracts:

1. Rust remains authoritative for semantic edit state, history, checkpoints, recipe and full-resolution export.
2. GPU/compositor state remains preview-only.
3. Tool switching is neither Apply nor Cancel.
4. Existing draft values remain remembered while the draft is active.
5. Unsupported or failed GPU composition falls back to the valid Rust preview.
6. Product UX does not expose history behavior that the Rust session model cannot guarantee.
7. Reset UX rewrites only the active draft range and never mutates an already Applied checkpoint.

---

## G4.0 — Clean branch / product baseline

### Repository transition

- [x] G3 PR #6 merged into `main`.
- [x] `feature/editor-product-ux` created from `main`.
- [x] Flutter analyze baseline reported PASS by the user before G4 implementation.
- [x] Flutter test baseline reported PASS by the user before G4 implementation.
- [x] Golden baseline reported PASS by the user before G4 implementation.
- [x] Rust fmt/clippy/test baseline reported PASS by the user before G4 implementation.
- [x] GPU LUT verification baseline reported PASS by the user before G4 implementation.

### Baseline evidence

User-reported clean G4 baseline on 2026-08-11:

```text
flutter analyze      PASS
make test            PASS
make golden-test     PASS
make rust-fmt        PASS
make rust-clippy     PASS
make rust-test       PASS
make gpu-lut-verify  PASS
```

G3 physical/runtime evidence remains recorded in `docs/G3_FINAL_VERIFICATION.md` and is the native-renderer regression baseline.

---

## G4.1 — Tool-state UX — IMPLEMENTED

Implementation:

```text
lib/state/editor_recipe_summary.dart
lib/ui/widgets/editor_tool_panel.dart
lib/ui/screens/editor_screen.dart
```

Behavior:

- [x] Adjust section badge when active draft contains a changed Adjust operation.
- [x] Per-Adjust changed indicator.
- [x] Correct neutral values surfaced (`1.0` except Gaussian Blur `0.0`).
- [x] Reset current Adjust parameter.
- [x] Reset Adjust section.
- [x] Reset active Creative slot.
- [x] Reset active Film slot.
- [x] Reset operations remove only operations after `checkpoint_cursor`.
- [x] Reset Adjust preserves Creative and Film draft slots.
- [x] Reset restore runs through Rust authoritative session restore.
- [x] Rewritten reset recipe is persisted for recovery.
- [x] Existing Discard Draft remains Rust checkpoint discard.
- [x] Apply remains Rust checkpoint promotion.

G4 does not create a parallel semantic edit state. `EditorRecipeSummary` is presentation-only and is rebuilt from the exported Rust recipe.

Tests:

```text
test/state/editor_recipe_summary_test.dart
```

Coverage includes applied-vs-draft separation, single-parameter reset, Adjust-section reset and checkpoint protection.

---

## G4.2 — Before / After — IMPLEMENTED

- [x] Press-and-hold comparison retained.
- [x] Product terminology changed from `Original` to `Before`.
- [x] Comparison source is the latest Apply checkpoint preview.
- [x] Comparison does not decode the full-resolution source.
- [x] Entering Before invalidates active GPU overlay state.

Contract:

```text
Import -> edit -> Apply checkpoint A -> more draft edits -> hold Before
                                                |
                                                v
                                           checkpoint A
```

---

## G4.3 — History UX — IMPLEMENTED

- [x] History action in Editor app bar.
- [x] History entries derived from authoritative recipe.
- [x] Applied checkpoint and active draft are distinguished.
- [x] Human-readable labels for common operations.
- [x] Undo / Redo remain Rust operations.
- [x] No arbitrary jump-to-history-position UI was added.

The absence of random-access history is intentional until Rust defines a verified contract for it.

---

## G4.4 — Autosave / recovery — HARDENED

Existing generation-based recovery was retained and strengthened.

Implementation:

```text
lib/core/editor_session_store.dart
lib/ui/screens/home_screen.dart
```

Recovery format already used immutable source/recipe payloads with the manifest written last as the generation commit record.

G4 adds:

- [x] Recipe envelope validation before persistence.
- [x] Cursor bounds validation.
- [x] Checkpoint bounds validation.
- [x] Source fingerprint verification during restore.
- [x] Corrupt/mismatched newest generation is rejected.
- [x] Loader can fall back to an older valid generation.
- [x] Legacy recovery layout remains supported when valid.
- [x] Home screen continues to present Resume / Discard explicitly.

Tests:

```text
test/core/editor_session_store_g4_test.dart
```

---

## G4.5 — Exit / unsaved-draft policy — IMPLEMENTED

Editor route now protects an unapplied draft with `PopScope`.

No active draft:

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

- [x] Continue Editing keeps the draft.
- [x] Discard invokes Rust checkpoint discard before exit.
- [x] Apply & Exit invokes Rust Apply before exit.
- [x] Processing/export blocks exit until the operation settles.
- [x] Apply remains distinct from Export.

---

## G4.6 — Product export UX — IMPLEMENTED

Full-resolution output remains Rust authoritative.

Product dialog now communicates:

- [x] PNG / JPEG / WEBP format.
- [x] Lossy-quality control where relevant.
- [x] Original-source resolution policy.
- [x] Whether current draft edits are included.
- [x] Full-resolution processing state.
- [x] Gallery-save result.
- [x] App-backup path.
- [x] Share action.

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

`docs/CODE_WALKTHROUGH.md` was previously G1-centric and contained obsolete iOS text such as `awaiting Xcode build / physical-iPhone validation`. It has been rewritten through the merged G3 architecture and current G4 product workflow.

Draft PR #7 was opened to run the repository CI against the actual branch head.

### Automated post-change gate

Latest PR-head CI must be green before G4 is marked CLOSED.

```text
Pixel Craft CI    PENDING
```

Do not mark this gate PASS from the pre-change baseline; the post-change branch must pass independently.

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
- User reported all requested Flutter/Rust/golden/LUT baseline gates PASS before product behavior changes.

### 2026-08-11 — G4.1-G4.6 implementation

- Added authoritative `EditorRecipeSummary` projection and reset recipe rewriting.
- Added tool/parameter changed indicators and reset controls.
- Productized checkpoint comparison as Before.
- Added authoritative recipe-derived History sheet.
- Hardened session recovery validation and source identity checks.
- Added unapplied-draft exit policy.
- Improved full-resolution export workflow without changing Rust authority.

### 2026-08-11 — Walkthrough audit

- Confirmed previous `docs/CODE_WALKTHROUGH.md` was stale relative to G1 closure and G2/G3.
- Rewrote the main walkthrough through G4.
- Added `docs/walkthrough/16_g4_editor_product_ux.md`.

### 2026-08-11 — PR verification

- Opened Draft PR #7.
- Latest PR-head CI result is not yet recorded as PASS in this document.

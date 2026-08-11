# G4 — Editor Product UX and Session Workflow

This walkthrough describes the G4 product layer added after the verified G3 production rendering pipeline.

G4 does **not** replace the rendering architecture. Rust remains authoritative for semantic edits, history, checkpoints, session recipe and full-resolution export. Native GPU rendering remains an interactive preview path only.

---

## 1. Product-state model

G4 introduces a presentation projection of the authoritative Rust recipe:

```text
Rust session recipe
  operations
  cursor
  checkpoint_cursor
        |
        v
EditorRecipeSummary
        |
        +-- active Adjust values
        +-- active Creative slot
        +-- active Film slot
        +-- applied/draft history labels
        +-- changed indicators
```

Implementation:

```text
lib/state/editor_recipe_summary.dart
```

The summary reads only the active recipe range after the last Apply boundary:

```text
operations[checkpoint_cursor .. cursor]
```

An operation before `checkpoint_cursor` is already part of the applied checkpoint and is therefore not shown as an active tool change.

This distinction is important. A brightness edit that has already been Applied must not leave the Brightness chip marked as an unapplied change.

---

## 2. G4.1 Tool-state UX

`EditorToolPanel` receives `EditorRecipeSummary` and uses it to distinguish:

```text
neutral
selected
changed in current draft
```

Adjust controls show a changed dot when the active draft contains a non-neutral value.

Neutral values remain consistent with engine semantics:

```text
Brightness      1.0
Contrast        1.0
Saturation      1.0
Sharpen         1.0
Gaussian Blur   0.0
```

The panel also exposes:

- Reset current Adjust parameter
- Reset Adjust section
- Reset active Creative filter
- Reset active Film profile
- Discard Draft
- Apply

### Reset semantics

Reset is recipe-based rather than cosmetic.

```text
export authoritative Rust recipe
  -> remove matching operation only inside active draft range
  -> keep operations before checkpoint_cursor untouched
  -> restore rewritten recipe through Rust
  -> persist recovery generation
```

This prevents a UI-only reset where a slider visually returns to neutral but the Rust recipe still contains the old operation.

`Reset Adjust` removes only core Adjust operations from the active draft. Creative and Film slots are preserved.

`Discard Draft` still delegates to the established Rust checkpoint discard path.

---

## 3. G4.2 Before / After

The image canvas supports press-and-hold comparison.

The product label is now **Before** rather than **Original** because the comparison source is the last Apply checkpoint:

```text
Import
  -> Adjust
  -> Apply             checkpoint A
  -> Film draft
  -> hold Before
  -> show checkpoint A
```

The implementation continues to use the cached Rust-authoritative checkpoint preview (`originalPreviewBytes` in the existing presentation state naming).

No full-resolution source decode occurs during comparison.

When Before is entered, G3 GPU preview state is invalidated so a stale native overlay cannot remain above the checkpoint image.

---

## 4. G4.3 History UX

The Editor app bar exposes a History sheet.

History entries are presentation labels derived from the recipe. The sheet distinguishes:

```text
Applied checkpoint operations
-----------------------------
Current draft operations
```

Typical labels include:

- Brightness 1.20
- Contrast 0.90
- Film profile strength
- Crop
- Rotate 90°
- Straighten
- Flip horizontal / vertical
- Resize

Undo and Redo remain the existing Rust operations.

G4 deliberately does **not** implement arbitrary jump-to-history-position. The UI must not promise random-access history semantics until Rust explicitly exposes and verifies that contract.

---

## 5. G4.4 Autosave and recovery

Semantic commits already trigger queued persistence from `EditorController`. G4 keeps the important boundary:

```text
slider frames                no recovery write
semantic commit / release    save
crop / rotate / flip         save
undo / redo                  save
Apply / Discard              save
```

Recovery storage:

```text
lib/core/editor_session_store.dart
```

Each recovery generation contains immutable source/recipe payloads plus a manifest written last as the generation commit record.

G4 validation adds:

1. recipe envelope validation before saving
2. cursor bounds validation
3. checkpoint bounds validation
4. source fingerprint verification on restore
5. invalid/corrupt newest generation fallback to an older valid generation
6. legacy recovery compatibility

The Home screen already presents recovery explicitly:

```text
Resume last edit
[Discard] [Resume]
```

Recovery therefore does not silently replace a newly selected editing session.

---

## 6. G4.5 Exit policy

Leaving Editor with no active draft exits immediately.

Leaving with unapplied edits presents:

```text
Unapplied edits

[Continue Editing]
[Discard]
[Apply & Exit]
```

Semantics:

- Continue Editing: remain in Editor
- Discard: invoke Rust checkpoint discard, then exit
- Apply & Exit: promote the draft to the Rust checkpoint, then exit

Processing/export state blocks exit until the current operation settles.

`Apply` remains distinct from `Export`:

```text
Apply  = editor checkpoint/session operation
Export = full-resolution output render
```

---

## 7. G4.6 Export UX

Export remains authoritative Rust replay:

```text
untouched original source
  -> replay complete active recipe
  -> encode requested format
  -> save/share
```

The product dialog exposes:

- PNG / JPEG / WEBP
- quality control for lossy formats
- original-source resolution policy
- whether an active draft will be included
- full-resolution progress state
- gallery save result
- Share action

GPU preview output is never used as export input.

---

## 8. G4.7 Hardening and verification

G4-specific regression coverage includes:

```text
test/state/editor_recipe_summary_test.dart
test/core/editor_session_store_g4_test.dart
```

The recipe tests verify:

- applied checkpoint vs active draft separation
- Reset Parameter removes only its draft slot
- Reset Adjust preserves Creative and Film
- reset never removes applied operations

Recovery tests verify:

- coherent generation round trip
- invalid recipe bounds rejected
- source fingerprint mismatch rejected with fallback to previous valid generation

The normal repository gates remain authoritative:

```bash
flutter analyze
make test
make golden-test
make rust-fmt
make rust-clippy
make rust-test
make gpu-lut-verify
```

G3 device/runtime behavior remains a regression requirement because G4 changed product orchestration around the same renderer lifecycle.

Recommended G4 physical UX smoke:

```text
Adjust changed indicator / reset
switch tools and confirm remembered draft
Before hold after an Apply checkpoint
History applied/draft boundary
Undo / Redo
background / foreground during draft
exit -> Continue Editing
exit -> Discard
exit -> Apply & Exit
terminate / Resume last edit
full-resolution export + share
GPU unsupported/failure -> valid Rust preview
```

---

## 9. Files introduced or materially changed by G4

```text
lib/state/editor_recipe_summary.dart
lib/ui/widgets/editor_tool_panel.dart
lib/ui/screens/editor_screen.dart
lib/core/editor_session_store.dart

test/state/editor_recipe_summary_test.dart
test/core/editor_session_store_g4_test.dart

docs/G4_PRODUCT_UX_VERIFICATION.md
docs/walkthrough/16_g4_editor_product_ux.md
```

The core architectural contract is unchanged:

> Rust owns semantics and final output. Flutter owns product/presentation orchestration. GPU owns only faithful low-latency preview where representable.

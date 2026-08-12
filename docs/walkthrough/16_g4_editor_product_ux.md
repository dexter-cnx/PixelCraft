# G4 — Editor Product UX and Session Workflow

G4 turns the verified G3 editor/rendering architecture into a coherent product workflow without changing source-of-truth ownership.

```text
Rust   = semantic edits, recipe, history, checkpoint, recovery semantics, full-res export
Flutter = product/presentation orchestration
GPU    = faithful low-latency preview only
```

---

## 1. G4 product-state model

New presentation projection:

```text
lib/state/editor_recipe_summary.dart
```

Flow:

```text
Rust session recipe
  operations
  cursor
  checkpoint_cursor
        ↓
EditorRecipeSummary
        ├─ active Adjust values
        ├─ active Creative slot
        ├─ active Film slot
        ├─ changed indicators
        └─ applied/draft history labels
```

Only `operations[checkpoint_cursor..cursor]` represent current unapplied changes. Operations before the checkpoint are historical/applied state and must not keep tool badges marked as active draft changes.

---

## 2. G4.1 Tool-state UX

`EditorToolPanel` now distinguishes neutral, selected and changed state.

Neutral Adjust values:

```text
Brightness      1.0
Contrast        1.0
Saturation      1.0
Sharpen         1.0
Gaussian Blur   0.0
```

Product controls:

- changed badge on Adjust / Filters / Film sections
- changed dot per Adjust parameter
- Reset current Adjust parameter
- Reset Adjust section
- Reset active Creative filter
- Reset active Film profile
- Discard Draft
- Apply

### Reset contract

Reset is not a UI-only slider change.

```text
export authoritative recipe
 -> inspect active draft range
 -> remove matching semantic operation(s)
 -> preserve operations before checkpoint_cursor
 -> truncate stale redo tail
 -> restore rewritten recipe through Rust
 -> persist recovery generation
```

Truncating the redo tail is intentional: Reset creates a new semantic branch, matching the engine rule for making a new edit after Undo.

`Reset Adjust` preserves Creative and Film draft slots.

---

## 3. G4.2 Before comparison

Press-and-hold on the image shows **Before**.

The comparison target is the latest Apply checkpoint, not always the originally imported pixels:

```text
Import
 -> Adjust
 -> Apply              checkpoint A
 -> Film draft
 -> hold Before
 -> checkpoint A
```

The existing `originalPreviewBytes` presentation field contains this promoted checkpoint after Apply.

Entering Before invalidates the native GPU draft so stale Metal preview pixels cannot remain above the Rust checkpoint preview.

---

## 4. G4.3 History UX

The Editor app bar exposes a History sheet.

History is derived from the authoritative recipe and visually separates:

```text
Applied checkpoint operations
-----------------------------
Current draft operations
```

Common operations receive readable labels for filters, Film, crop, rotations, straighten, flips and resize.

Undo/Redo remain existing Rust operations.

G4 does not expose random jump-to-history-position because Rust does not yet define a separately verified random-access history contract.

---

## 5. G4.4 Autosave and recovery

Persistence:

```text
lib/core/editor_session_store.dart
```

Autosave is semantic-event based:

```text
slider frames                 no save
semantic slider release       save
crop / rotate / flip          save
undo / redo                   save
Apply / Discard               save
```

Recovery already used immutable source/recipe payloads with a manifest published last. G4 hardens it with:

- recipe envelope validation before save
- cursor bounds validation
- checkpoint bounds validation
- source fingerprint validation during restore
- rejection of corrupt/mismatched newest generation
- fallback to an older valid generation
- valid legacy-session compatibility

Home already provides explicit recovery UX:

```text
Resume last edit
[Discard] [Resume]
```

CI-gated recovery tests:

```text
test/state/editor_session_store_g4_test.dart
```

---

## 6. G4.5 Exit policy

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

- Continue Editing keeps the current draft.
- Discard uses the Rust checkpoint-discard path.
- Apply & Exit promotes the draft through Rust Apply before leaving.
- processing/export prevents exit until the operation settles.

Apply and Export remain distinct concepts:

```text
Apply  = accept editor draft as checkpoint
Export = render an output file
```

---

## 7. G4.6 Export UX

Authoritative export path remains:

```text
untouched original
 -> Rust replay of active recipe
 -> new PNG / JPEG / WEBP encoding
 -> gallery/app backup
 -> optional Share
```

The dialog communicates format, lossy quality where relevant, original-source resolution policy and whether unapplied draft edits are included.

### Metadata policy

The current engine decodes and newly encodes output. Source EXIF/metadata is not re-attached by the current export path, so PixelCraft does not claim metadata preservation.

GPU preview pixels are never export input.

---

## 8. G4.7 Hardening and verification

G4-specific automated coverage:

```text
test/state/editor_recipe_summary_test.dart
test/state/editor_session_store_g4_test.dart
```

Recipe tests cover:

- applied checkpoint vs active draft separation
- Reset Parameter removes only the selected draft slot
- Reset Adjust preserves Creative and Film
- reset never removes applied operations

Recovery tests cover:

- coherent generation round trip
- invalid recipe bounds rejected
- source fingerprint mismatch rejected
- fallback to a previous valid generation

Repository gates:

```bash
flutter analyze
make test
make golden-test
make rust-fmt
make rust-clippy
make rust-test
make gpu-lut-verify
```

G3 device evidence remains the native-renderer regression baseline.

Recommended G4 physical/product smoke:

```text
Adjust changed indicator / Reset Parameter
Reset Adjust while Creative/Film remains active
switch tools and confirm remembered draft
Apply and Discard indicator behavior
Before hold after Apply
History checkpoint/draft boundary
Undo / Redo after reset
background / foreground during draft
exit -> Continue Editing
exit -> Discard
exit -> Apply & Exit
terminate / Resume last edit
full-resolution export + share
GPU unavailable/unrepresentable -> valid Rust preview
```

---

## 9. G4 files

```text
lib/state/editor_recipe_summary.dart
lib/ui/widgets/editor_tool_panel.dart
lib/ui/screens/editor_screen.dart
lib/core/editor_session_store.dart

test/state/editor_recipe_summary_test.dart
test/state/editor_session_store_g4_test.dart

docs/G4_PRODUCT_UX_VERIFICATION.md
docs/CODE_WALKTHROUGH.md
docs/walkthrough/16_g4_editor_product_ux.md
```

Core invariant after G4:

> Rust owns semantics and final output. Flutter owns product orchestration. GPU owns only faithful interactive preview where representable.

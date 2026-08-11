# PixelCraft Code Walkthrough

เอกสารนี้อธิบาย architecture ปัจจุบันของ PixelCraft หลัง G3 Production Rendering Pipeline และ G4 Product Editor UX / Session Workflow

สถานะ milestone ณ 2026-08-11:

```text
G1  Camera GPU Preview                          CLOSED
G2  Editor GPU Preview Foundation               CLOSED / MERGED
G3  Production Rendering Pipeline               CLOSED / MERGED
G4  Product Editor UX / Session Workflow        IMPLEMENTED / VERIFYING
G5  Editing Feature Completeness                PLANNED
G6  Reliability / Performance / Device Matrix   PLANNED
G7  Release / Beta / Store Readiness            PLANNED
```

> Rust เป็น authoritative source สำหรับ semantic edits, recipe, history, checkpoint, recovery และ full-resolution export. Flutter เป็น UI/control/presentation plane. Native GPU เป็น faithful low-latency preview path เท่านั้น

---

# 1. Canonical architecture

```text
Camera / imported image
        ↓
clean source image
        ↓
Flutter product / control state
        ↓
interactive GPU preview where faithfully representable
        ↓ gesture release / command
Rust semantic edit graph / recipe
        ↓
authoritative reduced preview + history + checkpoint
        ↓
full-resolution Rust replay/export
```

Hard contracts:

1. Rust owns committed edit semantics.
2. GPU preview never becomes final-render source of truth.
3. Camera Film is preview-only; capture source remains clean.
4. Live camera frames never cross Dart MethodChannel or FRB.
5. Film/Creative LUT data is generated from Rust-owned canonical data.
6. Unsupported GPU order or native failure falls back to valid Rust preview.
7. Flutter presentation state must not become a parallel semantic recipe.

---

# 2. App startup and Home

Entry point:

```text
lib/main.dart
```

Startup flow:

```text
WidgetsFlutterBinding
 -> portrait orientation policy
 -> Flutter/platform error handlers
 -> ProviderScope
 -> RustBootstrapScreen
 -> initializeRustBridge()
 -> HomeScreen
```

`RustBootstrapScreen` has a startup timeout and visible Retry path.

Home:

```text
lib/ui/screens/home_screen.dart
```

Editor entry sources:

- Film Camera
- system camera
- gallery
- bundled sample
- recovered Android image_picker capture
- saved editor recovery session

Recovery is explicit:

```text
Resume last edit
[Discard] [Resume]
```

Resume passes stored source bytes and the authoritative recipe into `EditorScreen`.

---

# 3. Rust image engine and recipe

Flutter adapter:

```text
lib/core/image_engine.dart
```

Rust authority:

```text
rust/src/engine.rs
rust/src/api.rs
```

Heavy synchronous FRB work is dispatched with `Isolate.run()`.

Rust retains:

- untouched source bytes
- reduced editor preview
- Apply checkpoint preview
- complete operation list
- cursor
- checkpoint cursor
- undo/redo state

Recipe model:

```text
operations = [ ... semantic edits ... ]
cursor
checkpoint_cursor
```

Active draft:

```text
operations[checkpoint_cursor .. cursor]
```

Operations before `checkpoint_cursor` are already part of the last Apply checkpoint.

Apply promotes the current reduced preview to checkpoint state without doing a full-resolution render. Full-resolution work is deferred to Export.

---

# 4. EditorController

Primary controller:

```text
lib/state/editor_controller.dart
```

It projects Rust state into Flutter:

- preview bytes
- checkpoint preview bytes
- histogram
- selected tool
- Adjust memories
- Creative selection/intensity
- Film selection/strength
- straighten preview
- processing flags
- cursor / operation count
- undo / redo capability

Typical Adjust transaction:

```text
slider drag
  -> GPU-only draft where eligible

slider release
  -> EditorController.commitFilterValue()
  -> Rust semantic commit/replace
  -> authoritative Rust preview
  -> recovery persistence
```

Tool switching does not Apply or Discard the active draft.

Apply:

```text
Rust applyEdits()
 -> checkpoint_cursor = cursor
 -> checkpoint preview updated
 -> active draft controls reset
 -> recovery persisted
```

Discard Draft:

```text
Rust discard-to-checkpoint
 -> active draft removed
 -> applied checkpoint preserved
 -> recovery persisted
```

---

# 5. G3 GPU Editor production path

Primary files:

```text
lib/gpu/gpu_editor_render_plan.dart
lib/gpu/gpu_editor_draft_session.dart
lib/gpu/gpu_editor_preview_bridge.dart
lib/gpu/ios_gpu_editor_preview.dart
lib/ui/screens/editor_screen.dart
```

`GpuEditorRenderPlan` reads the authoritative active Rust recipe and creates a native plan only when operation order can be represented faithfully.

Current Metal topology:

```text
optional Creative compute
 -> Gaussian Blur
 -> Sharpen
 -> Brightness
 -> Contrast
 -> Saturation
 -> optional final LUT
```

Fallback cases include unsupported transforms/order, Creative-LUT + Film LUT-slot conflict, and renderer create/update failure.

Fallback always means:

```text
invalidate/hide native draft
 -> show valid Rust preview
```

It never means silently reordering semantic operations.

`GpuEditorDraftSession` tracks presentation-only generations for checkpoint, renderer and activation lifecycle. Backgrounding, memory pressure and native failures invalidate the GPU path without corrupting Rust session state.

G3 closure evidence:

```text
docs/G3_FINAL_VERIFICATION.md
docs/G3_DEVICE_VERIFICATION.md
```

---

# 6. G4 presentation projection

G4 adds:

```text
lib/state/editor_recipe_summary.dart
```

`EditorRecipeSummary` is derived from the Rust recipe and owns no semantic edit state.

It derives:

- active Adjust values
- active Creative slot
- active Film slot
- changed indicators
- applied-vs-draft history labels

Example:

```text
0 Brightness 1.20   <- Applied
1 Contrast   1.10   <- active draft
2 Velvia      80%   <- active draft

checkpoint_cursor = 1
cursor            = 3
```

Product state:

```text
Brightness  not changed in current draft
Contrast    changed
Film        changed
```

---

# 7. G4.1 Tool-state UX and Reset

Widget:

```text
lib/ui/widgets/editor_tool_panel.dart
```

Adjust / Filters / Film sections show changed badges. Individual Adjust chips show changed indicators.

Neutral values:

```text
Brightness      1.0
Contrast        1.0
Saturation      1.0
Sharpen         1.0
Gaussian Blur   0.0
```

Reset is recipe-based, not cosmetic:

```text
export Rust recipe
 -> remove matching node only from active draft range
 -> preserve operations before checkpoint_cursor
 -> truncate stale redo tail because Reset creates a new semantic branch
 -> restore rewritten recipe through Rust
 -> persist recovery generation
```

Reset Adjust removes only `coreFilters`; Creative and Film are preserved. Reset Creative and Reset Film remove only their corresponding active draft slots.

---

# 8. G4.2 Before comparison

The Editor canvas supports press-and-hold **Before**.

The existing `originalPreviewBytes` presentation field is the cached Apply checkpoint after Apply succeeds, so product behavior is:

```text
Import
 -> edit
 -> Apply checkpoint A
 -> more draft edits
 -> hold Before
 -> checkpoint A
```

Entering Before invalidates the active GPU overlay, preventing stale native draft pixels from covering the Rust checkpoint preview.

No full-resolution decode is required for comparison.

---

# 9. G4.3 History

Editor app bar exposes History / Undo / Redo / Export.

History entries are generated from the authoritative recipe and distinguish:

```text
Applied checkpoint operations
Current draft operations
```

Undo/Redo remain Rust operations.

G4 deliberately does not expose arbitrary jump-to-history-position because Rust does not currently expose a separate verified random-access history contract.

---

# 10. G4.4 Autosave and recovery

Storage:

```text
lib/core/editor_session_store.dart
```

Current recovery uses generation-based atomic publishing:

```text
source payload
recipe payload
        ↓
generation manifest written last
```

Manifest fields include version, source file, recipe file, source fingerprint and saved timestamp.

G4 validation adds:

- valid recipe envelope before save
- `cursor` bounds validation
- `checkpoint_cursor <= cursor`
- source fingerprint verification on load
- rejection of corrupt/mismatched newest generation
- fallback to an older valid generation
- legacy recovery compatibility when valid

Autosave remains semantic-event based; slider frames are not persisted individually.

CI-gated G4 recovery test:

```text
test/state/editor_session_store_g4_test.dart
```

---

# 11. G4.5 Exit policy

`EditorScreen` uses `PopScope` to protect unapplied work.

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

Processing/export blocks exit until the operation settles.

Product distinction:

```text
Apply  = accept current Editor draft as checkpoint
Export = produce full-resolution output file
```

---

# 12. G4.6 Export

Export remains Rust authoritative:

```text
untouched original source
 -> decode
 -> replay complete active operation recipe
 -> newly encode PNG / JPEG / WEBP
 -> gallery/app backup
 -> optional Share
```

The dialog communicates format, lossy quality where relevant, original-source resolution policy, and whether the current draft is included.

## Metadata policy

The current Rust path decodes and newly encodes the rendered image. PixelCraft does not currently re-attach the source EXIF/metadata to the exported file. Therefore G4 must not claim metadata preservation.

Native GPU preview pixels are never export input.

---

# 13. Camera Film Preview — G1 closed architecture

Runtime selection:

```text
Android eligible
  -> Camera2
  -> SurfaceTexture / GL_TEXTURE_EXTERNAL_OES
  -> GLES canonical Film LUT
  -> TextureView / AndroidView

iOS eligible
  -> AVCaptureVideoDataOutput
  -> CVPixelBuffer
  -> CVMetalTextureCache
  -> Metal canonical 33^3 Film LUT
  -> MTKView / UiKitView

native unavailable/failure
  -> Flutter camera plugin fallback
```

Capture remains clean in every path. Film profile ID and strength are carried separately into Editor, where Rust applies authoritative Film semantics.

No camera frame buffer crosses Dart MethodChannel or FRB.

Detailed camera walkthroughs:

```text
docs/walkthrough/14_g1_android_camera_oes.md
docs/walkthrough/15_g1_ios_camera_metal.md
```

G1 is closed; obsolete “awaiting Xcode / physical validation” wording has been removed from this walkthrough.

---

# 14. Canonical Film / Creative LUT architecture

Rust-owned Film authoring data:

```text
rust/film_profiles/*/look.json
```

Build flow:

```text
look.json
 -> rust/build.rs
 -> canonical 33^3 LUT
      -> Rust renderer
      -> generated native GPU assets
```

Current Film IDs:

```text
provia_inspired
velvia_inspired
astia_inspired
e100_inspired
ektar_inspired
chrome64_inspired
```

Creative LUT presets also use Rust/photon-rs generated canonical data. Grayscale and invert use verified compute semantics.

---

# 15. Verification layers

Host / Flutter:

```bash
flutter analyze
make test
make golden-test
```

Rust:

```bash
make rust-fmt
make rust-clippy
make rust-test
```

GPU LUT:

```bash
make gpu-lut-verify
```

G4-specific CI-gated tests:

```text
test/state/editor_recipe_summary_test.dart
test/state/editor_session_store_g4_test.dart
```

G3 physical evidence remains the native renderer parity/lifecycle/performance baseline.

G4 physical smoke focuses on product orchestration:

- changed indicators and Reset
- tool switching without implicit Apply/Discard
- Before hold
- History boundary
- Undo/Redo
- background/foreground
- exit policy
- recovery after termination
- full-resolution export/share
- GPU failure -> valid Rust preview

---

# 16. Important files

```text
Flutter startup
  lib/main.dart

Home/source/recovery UX
  lib/ui/screens/home_screen.dart

Editor product shell
  lib/ui/screens/editor_screen.dart
  lib/ui/widgets/editor_tool_panel.dart

Editor presentation
  lib/state/editor_controller.dart
  lib/state/editor_recipe_summary.dart

Recovery persistence
  lib/core/editor_session_store.dart

Rust adapter
  lib/core/image_engine.dart

GPU planning/lifecycle
  lib/gpu/gpu_editor_render_plan.dart
  lib/gpu/gpu_editor_draft_session.dart
  lib/gpu/gpu_editor_preview_bridge.dart
  lib/gpu/ios_gpu_editor_preview.dart

Rust authority
  rust/src/engine.rs
  rust/src/api.rs
```

Detailed G4 walkthrough:

```text
docs/walkthrough/16_g4_editor_product_ux.md
```

Verification record:

```text
docs/G4_PRODUCT_UX_VERIFICATION.md
```

For current milestone status and next action, `docs/PROJECT_HANDOFF.md` remains the primary handoff document.

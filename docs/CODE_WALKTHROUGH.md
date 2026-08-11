# PixelCraft Code Walkthrough

เอกสารนี้อธิบาย architecture **ปัจจุบัน** ของ PixelCraft หลัง G3 Production Rendering Pipeline และ G4 Product Editor UX / Session Workflow

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

> หลักการสำคัญ: Rust เป็น authoritative source สำหรับ semantic edit, recipe, history, checkpoint, session recovery และ full-resolution export ส่วน Flutter เป็น UI/control/presentation plane และ native GPU เป็น low-latency preview path เท่านั้น

---

# 1. Architecture summary

## Canonical editor flow

```text
Camera / imported image
        ↓
clean source image
        ↓
Flutter Editor product state
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
2. GPU preview cannot become final-render source of truth.
3. Camera Film remains preview-only; capture source stays clean.
4. Live camera frame buffers never cross Dart MethodChannel or FRB.
5. Canonical Film / Creative LUT data is generated from Rust-owned authoring data.
6. Unsupported GPU operation order fails closed to valid Rust preview.
7. Flutter presentation state must not silently create a parallel semantic recipe.

---

# 2. Flutter application startup

Entry point:

```text
lib/main.dart
```

Startup:

```text
WidgetsFlutterBinding.ensureInitialized()
  -> portrait orientation policy
  -> install Flutter / platform error handlers
  -> ProviderScope
  -> PixelCraftApp
  -> RustBootstrapScreen
  -> initializeRustBridge()
  -> HomeScreen
```

Rust initialization has a timeout and a visible retry path rather than leaving the app on an indefinite loading screen.

Production launches `HomeScreen`; the GPU editor lab is debug/build-flag gated.

---

# 3. Home / source acquisition / recovery

Primary screen:

```text
lib/ui/screens/home_screen.dart
```

The user can enter Editor from:

```text
Film Camera
system camera
image gallery
bundled sample image
recovered Android image_picker capture
saved editor recovery session
```

## Recovery entry

`HomeScreen` loads `EditorSessionStore` and explicitly surfaces an existing session:

```text
Resume last edit
[Discard] [Resume]
```

Resume passes both source bytes and recipe into `EditorScreen`:

```text
EditorScreen(
  imageBytes: session.originalBytes,
  recoveryRecipe: session.recipeJson,
)
```

Recovery is therefore explicit rather than silently replacing a new session.

---

# 4. Rust image engine and session recipe

Flutter adapter:

```text
lib/core/image_engine.dart
```

Rust implementation:

```text
rust/src/engine.rs
rust/src/api.rs
```

Heavy synchronous FRB calls are dispatched with `Isolate.run()` by `RustImageEngine`.

The Rust engine retains:

- untouched source bytes
- reduced editor preview
- Apply checkpoint preview
- complete semantic operation list
- cursor
- checkpoint cursor
- undo/redo state

Conceptually:

```text
operations = [ ... semantic edits ... ]
cursor
checkpoint_cursor
```

The active draft is:

```text
operations[checkpoint_cursor .. cursor]
```

Operations before `checkpoint_cursor` belong to the latest accepted Apply checkpoint.

---

# 5. EditorController

Primary presentation controller:

```text
lib/state/editor_controller.dart
```

`EditorController` projects Rust state into Flutter:

- current reduced preview bytes
- checkpoint preview bytes
- histogram
- selected tool
- selected Adjust parameter and remembered values
- Creative selection/intensity
- Film profile/strength
- straighten preview state
- processing flags
- cursor / operation count
- undo / redo capability

## Semantic commit policy

Typical Adjust gesture:

```text
slider drag
  -> native GPU draft when eligible

slider release
  -> EditorController.commitFilterValue()
  -> Rust commit/replace semantics
  -> authoritative preview
  -> persist recovery generation
```

Creative and Film are exclusive semantic slots inside the active draft. Controller recipe replacement preserves the rest of the active draft rather than rebuilding an independent Flutter edit stack.

## Apply / Discard

```text
Apply
  -> Rust applyEdits()
  -> checkpoint_cursor = cursor
  -> checkpoint preview updated
  -> active tool memories reset
  -> thumbnails regenerated
  -> recovery persisted

Discard Draft
  -> Rust discard-to-checkpoint semantics
  -> current active draft removed
  -> applied checkpoint preserved
  -> recovery persisted
```

---

# 6. G3 GPU Editor production pipeline

Primary files:

```text
lib/gpu/gpu_editor_render_plan.dart
lib/gpu/gpu_editor_draft_session.dart
lib/gpu/gpu_editor_preview_bridge.dart
lib/gpu/ios_gpu_editor_preview.dart
lib/ui/screens/editor_screen.dart
```

`GpuEditorRenderPlan` reads the authoritative active Rust recipe and only produces a native plan if semantic order can be represented faithfully.

Supported topology on iOS Metal:

```text
optional Creative compute
 -> Gaussian Blur
 -> Sharpen
 -> Brightness
 -> Contrast
 -> Saturation
 -> optional final LUT
```

Representable composition includes multiple Adjust slots and supported Adjust + Creative + Film combinations.

Explicit fallback cases include:

- transform/unknown operation in unsupported location
- unrepresentable Rust operation order
- Creative LUT + Film when both require the one native final-LUT slot
- native renderer creation/update failure

Fallback means:

```text
hide/drop native draft
  -> continue showing valid Rust preview
```

It never means reordering or approximating the semantic recipe.

## Renderer lifecycle

`GpuEditorDraftSession` tracks presentation-only generations:

```text
checkpointGeneration
rendererGeneration
activationGeneration
status
transient edit
recipe snapshot
render plan
fallback reason
```

Lifecycle rules:

```text
background/inactive/hidden/detached
  -> invalidate active GPU draft
  -> destroy renderer

foreground
  -> keep Rust preview
  -> lazily recreate GPU renderer on next eligible gesture

memory pressure
  -> drop renderer
  -> preserve Rust session state
```

Engineering GPU indicators are debug-only.

Detailed closure evidence:

```text
docs/G3_FINAL_VERIFICATION.md
docs/G3_DEVICE_VERIFICATION.md
```

---

# 7. G4 product-state projection

G4 adds:

```text
lib/state/editor_recipe_summary.dart
```

`EditorRecipeSummary` is a presentation projection of the Rust recipe. It does not own semantic edit state.

It derives:

- changed Adjust parameters
- active Creative slot
- active Film slot
- current draft vs applied checkpoint
- human-readable History entries

Only operations after `checkpoint_cursor` are marked as active changes.

Example:

```text
operations
0 Brightness 1.20   <- already Applied
1 Contrast   1.10   <- current draft
2 Velvia      80%   <- current draft

checkpoint_cursor = 1
cursor            = 3
```

Product projection:

```text
Brightness  unchanged in current draft
Contrast    changed
Film        changed
```

---

# 8. G4.1 Tool-state UX and Reset semantics

Widget:

```text
lib/ui/widgets/editor_tool_panel.dart
```

Adjust / Filters / Film tool icons show a badge when that section has an active draft change.

Adjust chips show a per-parameter changed indicator.

Neutral/default values:

```text
Brightness      1.0
Contrast        1.0
Saturation      1.0
Sharpen         1.0
Gaussian Blur   0.0
```

## Reset current parameter

Reset is authoritative recipe rewriting:

```text
export Rust recipe
  -> remove matching operation only from draft range
  -> preserve operations before checkpoint_cursor
  -> restore rewritten recipe through Rust
  -> persist session
```

## Reset Adjust

Removes only draft operations whose names belong to `coreFilters`.

Creative and Film draft slots are preserved.

## Reset Creative / Film

Remove only the corresponding active draft semantic slot.

The UI therefore does not fake reset by changing a slider while leaving stale Rust operations behind.

---

# 9. G4.2 Before comparison

`EditorScreen` supports press-and-hold comparison on the canvas.

Although the existing state field is named `showOriginal`, its product meaning after Apply is the **last Apply checkpoint**, because `originalPreviewBytes` is promoted when Apply succeeds.

Example:

```text
Import
 -> Brightness
 -> Apply           checkpoint A
 -> Film draft
 -> hold Before
 -> checkpoint A
```

Entering Before invalidates the active GPU overlay so the native draft cannot remain visible above the Rust checkpoint preview.

No full-resolution decode is performed for comparison.

---

# 10. G4.3 History UX

Editor app bar:

```text
History
Undo
Redo
Export
```

History sheet is generated from the authoritative recipe summary.

It distinguishes:

```text
Applied checkpoint operations
Current draft operations
```

Undo/Redo still call Rust through `EditorController`.

G4 intentionally does not expose arbitrary jump-to-position because Rust has not defined a separate random-access history contract for product UI.

Detailed walkthrough:

```text
docs/walkthrough/16_g4_editor_product_ux.md
```

---

# 11. G4.4 Autosave and recovery hardening

Storage:

```text
lib/core/editor_session_store.dart
```

Current format uses generation-based atomic publishing.

A generation manifest records:

```text
version
sourceFile
recipeFile
sourceFingerprint
savedAt
```

The source and recipe payloads are written first. Manifest rename is the generation commit point.

G4 validation now verifies:

- valid JSON recipe envelope before save
- `cursor` within operation bounds
- `checkpoint_cursor <= cursor`
- source bytes still match manifest fingerprint on load
- corrupt/incomplete newest generation is skipped
- older valid generation can be recovered
- legacy recovery layout remains readable when valid

Autosave remains semantic-event based rather than frame based.

---

# 12. G4.5 Exit policy

`EditorScreen` uses `PopScope` to protect an unapplied draft.

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

Processing/export blocks exit until the current operation settles.

Product semantics remain explicit:

```text
Apply  != Export
```

Apply changes the Editor checkpoint. Export renders an output image.

---

# 13. G4.6 Full-resolution export

Export remains Rust authoritative:

```text
untouched original
  -> replay complete active recipe
  -> encode PNG / JPEG / WEBP
  -> save to gallery/app backup
  -> optional Share
```

The dialog communicates:

- format
- lossy quality where relevant
- original-source resolution policy
- whether current draft edits will be included

Native GPU preview pixels are never export input.

---

# 14. Camera Film Preview — G1 closed architecture

Shared screen:

```text
lib/ui/screens/camera_film_preview_screen.dart
lib/ui/screens/camera_film_preview_screen_g1.dart
```

Runtime selection:

```text
probe native GPU capability

Android eligible
  -> Camera2
  -> SurfaceTexture
  -> GL_TEXTURE_EXTERNAL_OES
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

Capture always stays clean:

```text
native/fallback capture
  -> clean JPEG/source
  -> carry Film profile ID + strength separately
  -> Editor
  -> Rust authoritative Film semantics
```

There is no per-frame Dart callback and no camera frame buffer crosses MethodChannel/FRB.

Detailed camera walkthroughs:

```text
docs/walkthrough/14_g1_android_camera_oes.md
docs/walkthrough/15_g1_ios_camera_metal.md
```

G1 is no longer awaiting initial physical validation; closure evidence is recorded in the project handoff and G1 verification records.

---

# 15. Canonical Film / Creative LUT architecture

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

Current canonical Film IDs:

```text
provia_inspired
velvia_inspired
astia_inspired
e100_inspired
ektar_inspired
chrome64_inspired
```

Creative LUT presets also use Rust/photon-rs generated canonical data rather than independent Metal look algorithms.

Compute Creative operations currently include grayscale and invert where exact native semantics are defined.

---

# 16. Testing and verification layers

## Flutter / host

```bash
flutter analyze
make test
make golden-test
```

## Rust

```bash
make rust-fmt
make rust-clippy
make rust-test
```

## LUT / GPU

```bash
make gpu-lut-verify
```

## G4-specific tests

```text
test/state/editor_recipe_summary_test.dart
test/core/editor_session_store_g4_test.dart
```

## Physical-device regression

G3 physical evidence remains the baseline for native renderer parity/lifecycle/performance.

G4 physical smoke focuses on product orchestration:

- changed indicators
- Reset Parameter / Reset section
- tool switching without implicit Apply/Discard
- Before hold
- History boundary
- Undo/Redo
- background/foreground
- exit policy
- recovery after termination
- full-resolution export/share
- GPU failure -> valid Rust preview

G4 verification record:

```text
docs/G4_PRODUCT_UX_VERIFICATION.md
```

---

# 17. Important files by responsibility

```text
Flutter app/bootstrap
  lib/main.dart

Home/source/recovery UX
  lib/ui/screens/home_screen.dart

Editor product shell
  lib/ui/screens/editor_screen.dart
  lib/ui/widgets/editor_tool_panel.dart

Editor presentation controller
  lib/state/editor_controller.dart
  lib/state/editor_recipe_summary.dart

Recovery persistence
  lib/core/editor_session_store.dart

Rust adapter
  lib/core/image_engine.dart

GPU editor planning/lifecycle
  lib/gpu/gpu_editor_render_plan.dart
  lib/gpu/gpu_editor_draft_session.dart
  lib/gpu/gpu_editor_preview_bridge.dart
  lib/gpu/ios_gpu_editor_preview.dart

Rust authority
  rust/src/engine.rs
  rust/src/api.rs
```

---

# 18. Current continuation point

For milestone status, verified evidence and the exact next action, always treat this file as secondary to:

```text
docs/PROJECT_HANDOFF.md
```

For G4 details:

```text
docs/G4_PRODUCT_UX_VERIFICATION.md
docs/walkthrough/16_g4_editor_product_ux.md
```

Do not infer future G5 feature scope from G4 product UX code. New editing algorithms belong to G5 unless an explicit architecture decision changes the roadmap.

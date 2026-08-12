# PixelCraft Code Walkthrough

เอกสารนี้อธิบาย architecture ปัจจุบันของ PixelCraft หลัง G5 Editing Feature Completeness ปิด verification แล้ว

สถานะ milestone ณ 2026-08-12:

```text
G1  Camera GPU Preview                          CLOSED
G2  Editor GPU Preview Foundation               CLOSED / MERGED
G3  Production Rendering Pipeline               CLOSED / MERGED
G4  Product Editor UX / Session Workflow        CLOSED / MERGED
G5  Editing Feature Completeness                CLOSED / VERIFIED
G6  Reliability / Performance / Device Matrix   NEXT
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
8. Film Profiles are reusable configuration data, not Editor session state or captured GPU pixels.
9. New effects are defined in Rust first; GPU support is enabled only when semantics can be represented faithfully.

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

Home:

```text
lib/ui/screens/home_screen.dart
```

Editor entry sources include Film Camera, system camera, gallery, bundled sample and saved recovery sessions.

G5 also exposes Film Profile management / My Films from product navigation.

Recovery remains explicit:

```text
Resume last edit
[Discard] [Resume]
```

Resume passes stored source bytes plus the authoritative recipe into `EditorScreen`.

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
rust/src/filters.rs
rust/src/advanced_filters.rs
```

Heavy synchronous FRB work is dispatched away from the UI isolate.

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

Operations before `checkpoint_cursor` belong to the last Apply checkpoint.

Apply promotes the current reduced preview/checkpoint state. Full-resolution replay is deferred to Export.

---

# 4. Editor adjustment catalog — G5

Central metadata:

```text
lib/state/editor_adjustment_catalog.dart
```

G5 removes the old assumption that every Adjust slider is `0...2` with neutral `1.0`.

`EditorAdjustmentSpec` defines:

```text
id
label
min
max
neutral
group
unit
gpuPreview
```

Current Editor controls:

```text
Exposure        -2 ... +2 EV   neutral 0
Brightness       0 ... 2       neutral 1   GPU preview
Contrast         0 ... 2       neutral 1   GPU preview
Highlights      -1 ... +1      neutral 0
Shadows         -1 ... +1      neutral 0
Saturation       0 ... 2       neutral 1   GPU preview
Temperature     -1 ... +1      neutral 0
Tint            -1 ... +1      neutral 0
Vibrance        -1 ... +1      neutral 0
Vignette        -1 ... +1      neutral 0
Grain            0 ... 1       neutral 0
Sharpness        0 ... 2       neutral 0   GPU preview
Gaussian Blur    0 ... 2       neutral 0   GPU preview
```

The `gpuPreview` flag is intentional: controls without a verified faithful native implementation commit through Rust on release rather than using an approximate shader.

---

# 5. EditorController

Primary controller:

```text
lib/state/editor_controller.dart
```

It projects Rust state into Flutter:

- preview/checkpoint bytes
- histogram
- selected tool
- adjustment memories
- Creative selection/intensity
- Film selection/strength
- processing state
- cursor / operation count
- undo / redo capability

Typical Adjust transaction:

```text
slider drag
  -> GPU-only draft when adjustmentSpec.gpuPreview == true

slider release
  -> EditorController.commitFilterValue()
  -> Rust semantic commit/replace
  -> authoritative Rust preview
  -> recovery persistence
```

For G5 controls that are not GPU-enabled, the visible committed result is produced through Rust on release.

Tool switching does not Apply or Discard the active draft.

---

# 6. Rust G5 filter semantics

Basic filters:

```text
rust/src/filters.rs
```

G5.1 adds Rust-authoritative Tone operations:

```text
exposure
highlights
shadows
```

Exposure uses multiplicative `2^EV` semantics. Highlights/Shadows use luminance-selective masks and preserve alpha.

Advanced filters:

```text
rust/src/advanced_filters.rs
```

G5.2 / G5.3 / G5.7 add:

```text
temperature
tint
vibrance
vignette
grain
curve_shadows
curve_midtones
curve_highlights
hsl_<sector>_<component>
```

HSL sectors:

```text
red
yellow
green
cyan
blue
magenta
```

Components:

```text
hue
sat
lum
```

Grain is deterministic. It uses a coordinate-based fixed hash so preview/session replay/export do not depend on hidden RNG state.

G5 Temperature/Tint are image-edit color-bias controls; they are not claims of calibrated camera white balance.

---

# 7. G3 GPU Editor production path

Primary files:

```text
lib/gpu/gpu_editor_render_plan.dart
lib/gpu/gpu_editor_draft_session.dart
lib/gpu/gpu_editor_preview_bridge.dart
lib/gpu/ios_gpu_editor_preview.dart
lib/ui/screens/editor_screen.dart
```

`GpuEditorRenderPlan` reads the authoritative active Rust recipe and creates a native plan only when operation order is faithfully representable.

Current verified Metal topology remains:

```text
optional Creative compute
 -> Gaussian Blur
 -> Sharpen
 -> Brightness
 -> Contrast
 -> Saturation
 -> optional final LUT
```

G5 does not silently extend this topology with approximate Exposure/Highlights/Shadows/Color/Film-Lab shaders.

Unsupported operations/order simply keep the valid Rust preview.

---

# 8. G4 recipe projection / Reset / History

Presentation projection:

```text
lib/state/editor_recipe_summary.dart
```

`EditorRecipeSummary` derives UI state from the Rust recipe and owns no independent semantic recipe.

It derives:

- active Adjust values
- Creative slot
- Film slot
- changed indicators
- applied-vs-draft history labels

Reset remains recipe-based:

```text
export Rust recipe
 -> edit only operations after checkpoint_cursor
 -> truncate stale redo tail
 -> restore rewritten recipe through Rust
 -> persist recovery
```

Before comparison shows the latest Apply checkpoint and invalidates an active native overlay first.

Undo/Redo remain Rust operations.

---

# 9. Recovery / Exit / Export

Recovery:

```text
lib/core/editor_session_store.dart
```

Generation-based atomic publishing stores source + recipe and writes the manifest last. Load validates recipe bounds and source fingerprint, rejects corrupt/mismatched newest data and can fall back to an older valid generation.

Exit policy with an active draft:

```text
Continue Editing
Discard
Apply & Exit
```

Export:

```text
untouched original source
 -> Rust decode
 -> replay complete active recipe
 -> encode PNG / JPEG / WEBP
 -> gallery/app backup
 -> optional Share
```

Native GPU preview pixels are never export input.

Current export path does not re-attach original EXIF/metadata.

---

# 10. FilmProfileV1 — G5.4

Main schema/model:

```text
lib/core/film_profile_v1.dart
```

Schema identifiers:

```text
schema            pixelcraft-film-profile
schemaVersion     1
minEngineVersion  1
```

Profile origin:

```text
builtIn
user
imported
```

`FilmProfileV1` stores:

- id / name / description
- origin
- optional `baseFilmId`
- base Film strength
- normalized parameter map
- tags
- schema/engine compatibility

The profile parameter catalog contains Tone, Color, Texture, Curve and HSL fields. Neutral-valued parameters are normalized out of reusable profile data.

Built-in profiles are treated as immutable; customization should create/duplicate a user profile.

A Film Profile deliberately does **not** contain:

- source image
- crop/rotate state
- Editor history
- checkpoint cursor
- captured GPU pixels

---

# 11. Film Profile → Rust recipe materialization

Materializer:

```text
lib/core/film_profile_recipe.dart
```

Entry:

```text
applyFilmProfileToSessionRecipe(recipeJson, profile)
```

Flow:

```text
current authoritative recipe
 -> preserve operations before checkpoint_cursor
 -> inspect active draft
 -> upsert optional film_profile operation
 -> upsert profile scalar filter operations
 -> discard stale redo tail
 -> encode rewritten recipe
 -> caller restores through Rust engine
```

This is important: loading a custom Film Profile does not bypass Rust or introduce a second renderer. After restore it behaves like normal recipe data and therefore participates in preview, history, Apply/Discard, recovery and export.

---

# 12. Film Profile persistence

Store:

```text
lib/core/film_profile_store.dart
```

The store persists user/imported profiles locally and uses the schema model for serialization/deserialization.

Relevant tests:

```text
test/state/film_profile_v1_test.dart
test/state/film_profile_store_test.dart
```

---

# 13. Film Profile Creator / My Films — G5.5

Screens:

```text
lib/ui/screens/film_profiles_screen.dart
lib/ui/screens/film_profile_creator_screen.dart
```

Product workflow supports:

```text
Create
Edit user profile
Duplicate
Choose base Film
Tune parameters
Save
Load from My Films into Editor
```

Creator sections are driven by the Film Profile parameter metadata rather than a separate processing implementation.

Loading a custom Film eventually materializes the profile into the Editor recipe and restores that recipe through the Rust engine.

---

# 14. Import / Export compatibility — G5.6

`FilmProfileV1` provides versioned PixelCraft JSON serialization.

Generic recipe import records mappings as:

```text
exact
approximated
unsupported
```

The importer never silently discards unsupported settings.

Third-party recipe names can be mapped into PixelCraft semantics, but this does not imply proprietary camera processing is reproduced 1:1.

---

# 15. Advanced Film Lab V1 — G5.7

G5.7 intentionally uses scalar replayable operations rather than introducing a new arbitrary curve graph schema.

Tone-zone controls:

```text
Curve Shadows
Curve Midtones
Curve Highlights
```

HSL Color Mixer:

```text
6 hue sectors × Hue / Saturation / Luminance
```

All operations are serialized as normal filter nodes in the existing Rust recipe, so no parallel Film Lab history/session model is needed.

V1 scope does not claim:

- arbitrary point-curve editing
- masking/local color adjustments
- calibrated color-management pipeline
- halation/bloom simulation

---

# 16. Camera Film Preview

Android eligible path:

```text
Camera2
 -> SurfaceTexture / OES
 -> GLES canonical Film LUT
 -> TextureView / AndroidView
```

iOS eligible path:

```text
AVCaptureVideoDataOutput
 -> CVPixelBuffer
 -> CVMetalTextureCache
 -> Metal canonical Film LUT
 -> MTKView / UiKitView
```

Native unavailable/failure:

```text
Flutter camera plugin fallback
```

Capture remains clean. No live camera frame buffer crosses Dart MethodChannel or FRB.

---

# 17. Canonical Film / Creative LUT architecture

Rust-owned Film data:

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

Current built-in Film IDs:

```text
provia_inspired
velvia_inspired
astia_inspired
e100_inspired
ektar_inspired
chrome64_inspired
```

Creative LUT presets similarly use Rust/photon-rs generated canonical data. Grayscale and invert use verified compute semantics.

---

# 18. Verification layers

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

Important G5 tests include:

```text
test/state/editor_adjustment_catalog_test.dart
test/state/film_profile_v1_test.dart
test/state/film_profile_store_test.dart
test/ui/editor_screen_test.dart
```

Latest recorded G5 PR host CI before closure documentation:

```text
Pixel Craft CI run #109  PASS
```

Physical/product G5 smoke was reported PASS on 2026-08-12.

This physical smoke is functional product evidence. It must not be rewritten as numeric GPU parity evidence for G5 controls that intentionally do not have native GPU implementations yet.

---

# 19. Important files

```text
Startup
  lib/main.dart

Home
  lib/ui/screens/home_screen.dart

Editor
  lib/ui/screens/editor_screen.dart
  lib/ui/widgets/editor_tool_panel.dart

Editor presentation
  lib/state/editor_controller.dart
  lib/state/editor_recipe_summary.dart
  lib/state/editor_adjustment_catalog.dart

Film Profile
  lib/core/film_profile_v1.dart
  lib/core/film_profile_recipe.dart
  lib/core/film_profile_store.dart
  lib/ui/screens/film_profiles_screen.dart
  lib/ui/screens/film_profile_creator_screen.dart

Recovery
  lib/core/editor_session_store.dart

Rust adapter
  lib/core/image_engine.dart

GPU
  lib/gpu/gpu_editor_render_plan.dart
  lib/gpu/gpu_editor_draft_session.dart
  lib/gpu/gpu_editor_preview_bridge.dart
  lib/gpu/ios_gpu_editor_preview.dart

Rust authority
  rust/src/engine.rs
  rust/src/api.rs
  rust/src/filters.rs
  rust/src/advanced_filters.rs
```

Primary milestone documents:

```text
docs/PROJECT_HANDOFF.md
docs/G5_EDITING_FEATURE_COMPLETENESS.md
docs/G5_TONE_CONTROLS.md
```

---

# 20. Current continuation point

G5 is **CLOSED / VERIFIED**.

PR #8 remains the integration PR at this handoff point. After its latest documentation head is green, finish normal review/merge workflow and start G6 from merged `main`.

Recommended next branch:

```text
feature/g6-reliability-matrix
```

First G6 work:

```text
1. create docs/G6_RELIABILITY_MATRIX.md
2. record clean host baseline
3. build image-size matrix (~12/24/48MP where hardware permits)
4. add long-session / lifecycle / Film Profile soak coverage
5. expand iOS + Android device/GPU-family verification
6. add failure-injection coverage
```

For exact milestone status and next action, `docs/PROJECT_HANDOFF.md` is authoritative.
# PixelCraft Project Handoff

## Purpose

This is the single continuation document for PixelCraft.

When opening a new ChatGPT conversation, read this file first, inspect the current branch/HEAD, and continue from **Current next action**. Repository state and recorded verification evidence take precedence over prior chat context.

Recommended prompt:

```text
อ่าน docs/PROJECT_HANDOFF.md ใน repo PixelCraft แล้วทำต่อจาก Current next action
```

---

# 1. Architecture invariants

Repository: `dexter-cnx/PixelCraft`

```text
Flutter        = UI / control / presentation plane
Rust           = authoritative image semantics / recipe / history / checkpoint / export
Metal          = iOS realtime GPU preview
OpenGL ES      = Android realtime camera preview
```

Hard contracts:

1. Rust owns committed edit semantics, history, checkpoints, recovery recipe and full-resolution export.
2. GPU rendering is an interactive preview path, never final-render authority.
3. Camera Film is preview-only; capture remains clean.
4. Live camera frame buffers never cross Dart MethodChannel or Flutter Rust Bridge.
5. Canonical Film/Creative LUT data is Rust-owned.
6. Native/GPU failure must fail closed to a valid Rust preview.
7. Unsupported Rust operation order must fall back; never silently reorder operations to fit the GPU.
8. Film Profiles are reusable configuration data, not captured pixels or per-image Editor sessions.
9. Imported recipe fields must be reported as exact / approximated / unsupported; never silently drop unsupported fields.
10. New effects are defined and tested in Rust first. GPU support is optional and only added when semantics can be reproduced faithfully.

Canonical flow:

```text
Camera / imported image
        ↓
clean source
        ↓
Flutter controls
        ↓
GPU preview where faithful
        ↓ gesture release / command
Rust recipe / semantic edit
        ↓
authoritative preview + history + checkpoint
        ↓
full-resolution Rust replay/export
```

---

# 2. Milestones

```text
G1  Camera GPU Preview                          CLOSED
G2  Editor GPU Preview Foundation               CLOSED / MERGED
G3  Production Rendering Pipeline               CLOSED / MERGED
G4  Product Editor UX / Session Workflow        CLOSED / MERGED
G5  Editing Feature Completeness                CLOSED / VERIFIED
G6  Reliability / Performance / Device Matrix   NEXT
G7  Release / Beta / Store Readiness            PLANNED
```

Branches / PRs:

```text
G2  feature/camera-film-preview
G3  feature/editor-gpu-production      PR #6 merged
G4  feature/editor-product-ux          PR #7 merged
G5  feature/editor-tone-controls       PR #8 open at handoff time
```

---

# 3. G1 — Camera GPU Preview — CLOSED

Android:

```text
Camera2
 -> SurfaceTexture
 -> GL_TEXTURE_EXTERNAL_OES
 -> GLES
 -> canonical Film LUT atlas
 -> TextureView / AndroidView
```

iOS:

```text
AVCaptureSession
 -> AVCaptureVideoDataOutput
 -> CVPixelBuffer
 -> CVMetalTextureCache
 -> Metal
 -> canonical 33^3 Film LUT
 -> MTKView / UiKitView
```

Capture stays clean on both platforms.

Recorded evidence includes Android Film LUT max errors around `0.0017-0.0019`, iOS ~60 FPS preview characterization and Metal command p95 around `1.31 ms`.

See `docs/G1_IOS_VERIFICATION.md`.

---

# 4. G2 — Editor GPU Preview Foundation — CLOSED / MERGED

Primary record: `docs/G2_FINAL_VERIFICATION.md`.

Transaction model:

```text
slider drag    -> GPU-only draft when supported
slider release -> Rust semantic commit
Apply/Discard  -> Rust checkpoint semantics
Undo/Redo      -> Rust history
Export         -> Rust full-resolution replay
```

G2 established:

- Brightness / Contrast / Saturation GPU parity
- Sharpen semantics
- deterministic Gaussian Blur parity
- Creative compute/LUT paths
- crop / straighten / rotate / flip
- renderer generation guards
- stale activation protection
- Rust fallback on native failure

Draft composition:

- independent Adjust slots
- one Creative slot
- one Film slot
- tool switching is not Apply/Discard

See:

```text
docs/G2_5_TRANSFORM_PREVIEW_CONTRACT.md
docs/G2_6_EDITOR_GPU_HARDENING.md
docs/EDITOR_DRAFT_COMPOSITION.md
```

---

# 5. G3 — Production Rendering Pipeline — CLOSED / MERGED

Records:

```text
docs/G3_FINAL_VERIFICATION.md
docs/G3_DEVICE_VERIFICATION.md
```

`GpuEditorRenderPlan` reads:

```text
operations[checkpoint_cursor .. cursor]
```

Current verified Metal topology:

```text
optional Creative compute
 -> Gaussian Blur
 -> Sharpen
 -> Brightness
 -> Contrast
 -> Saturation
 -> optional final LUT
```

Unsupported order/composition falls back to Rust.

Recorded Apple A13 evidence:

```text
Adjustment parity max error     0.0019263029098510742
Gaussian Blur max error         0.0
Creative compute max error      0.0
Adjustment + Film p95           1.104 ms
Heavy Gaussian Blur p95         11.418 ms
Renderer recreate               12/12 PASS
```

---

# 6. G4 — Product Editor UX / Session Workflow — CLOSED / MERGED

Record: `docs/G4_PRODUCT_UX_VERIFICATION.md`.

Implemented:

- recipe-derived changed indicators
- Reset current Adjust
- Reset Adjust / Creative / Film
- Before press-and-hold against latest Apply checkpoint
- recipe-derived History with Applied/Draft distinction
- Rust Undo/Redo
- generation-based atomic recovery
- source fingerprint / recipe bounds validation
- corrupt newest-generation fallback
- Back policy: Continue Editing / Discard / Apply & Exit
- PNG / JPEG / WEBP full-resolution Rust export
- gallery/app backup/share

Current export path does not re-attach original EXIF/metadata; do not claim metadata preservation.

---

# 7. G5 — Editing Feature Completeness — CLOSED / VERIFIED

Branch:

```text
feature/editor-tone-controls
```

PR #8:

```text
G5.1-G5.7: editing completeness and Film Lab
```

Primary docs:

```text
docs/G5_EDITING_FEATURE_COMPLETENESS.md
docs/G5_TONE_CONTROLS.md
```

## G5.1 Tone

Rust-authoritative additions:

```text
Exposure    -2 ... +2 EV   neutral 0
Highlights  -1 ... +1      neutral 0
Shadows     -1 ... +1      neutral 0
```

Exposure uses `2^EV` multiplicative semantics. Highlights/Shadows use luminance-selective masks. Alpha is preserved.

Shared Editor metadata is now in:

```text
lib/state/editor_adjustment_catalog.dart
```

Current catalog also fixes Sharpness neutral to `0.0`.

GPU continuous preview remains enabled only for the already verified faithful controls:

```text
Brightness
Contrast
Saturation
Sharpness
Gaussian Blur
```

New G5 controls remain Rust-on-release until a parity-safe GPU implementation exists.

## G5.2 Color / WB bias

Added:

```text
Temperature  -1 ... +1
Tint         -1 ... +1
Vibrance     -1 ... +1
```

These are image-edit color-bias semantics, not calibrated camera sensor white-balance controls.

## G5.3 Finish / Texture

Added:

```text
Vignette  -1 ... +1
Grain      0 ... 1
```

Grain is deterministic via coordinate-based hashing; replay/export does not depend on hidden RNG state.

## G5.4 Film Profile Foundation

Model:

```text
lib/core/film_profile_v1.dart
```

Schema:

```text
schema            pixelcraft-film-profile
schemaVersion     1
minEngineVersion  1
origin             builtIn / user / imported
```

A reusable profile can contain:

- id / name / description
- base Film ID + strength
- normalized parameter map
- tags
- compatibility versions

It does not contain source image, crop/rotate state, history, checkpoint or captured GPU pixels.

## G5.5 Film Profile Creator V1

UI:

```text
lib/ui/screens/film_profiles_screen.dart
lib/ui/screens/film_profile_creator_screen.dart
```

Workflow:

```text
Create
Edit user profile
Duplicate
Choose base Film
Tune Tone / Color / Texture / Curve / HSL
Save
Load from My Films into Editor
```

Local persistence:

```text
lib/core/film_profile_store.dart
```

## G5.6 Profile import/export

`FilmProfileV1` supports versioned PixelCraft JSON.

Generic recipe importer reports each mapped field as:

```text
exact
approximated
unsupported
```

Do not claim proprietary third-party camera processing is reproduced 1:1 unless separately verified.

## G5.7 Advanced Film Lab V1

Rust implementation:

```text
rust/src/advanced_filters.rs
```

Tone-zone operations:

```text
curve_shadows
curve_midtones
curve_highlights
```

HSL sectors:

```text
red / yellow / green / cyan / blue / magenta
```

Each sector supports:

```text
hue / sat / lum
```

These are replayable scalar recipe operations, not a separate Film Lab session model.

## Film Profile → Editor recipe

Materializer:

```text
lib/core/film_profile_recipe.dart
```

Flow:

```text
FilmProfileV1
 -> preserve operations before checkpoint_cursor
 -> upsert optional film_profile draft operation
 -> upsert scalar filter draft operations
 -> truncate stale redo tail
 -> restore rewritten recipe through Rust
 -> normal history / checkpoint / recovery / export
```

Loading a custom profile therefore does not bypass Rust authority.

## G5 verification

Recorded at closure:

```text
latest host CI                               PASS
Pixel Craft CI run #109                      PASS before closure docs
Flutter analyzer/state/widget/golden gates   PASS
Rust fmt/clippy/tests                        PASS
FRB generated bridge checks                  PASS
GPU LUT verification                         PASS
physical/product G5 smoke                    PASS (reported 2026-08-12)
```

Physical/product smoke is functional evidence. It is not a numeric GPU parity claim for G5 controls that intentionally use Rust on release.

**Decision: G5 CLOSED / VERIFIED.**

---

# 8. Important current files

```text
Startup
  lib/main.dart

Home / source / recovery entry
  lib/ui/screens/home_screen.dart

Editor shell
  lib/ui/screens/editor_screen.dart
  lib/ui/widgets/editor_tool_panel.dart

Editor state / recipe projection
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

Main walkthrough:

```text
docs/CODE_WALKTHROUGH.md
```

---

# 9. G6 — Reliability / Performance / Device Matrix — NEXT

Create:

```text
docs/G6_RELIABILITY_MATRIX.md
```

Recommended branch after PR #8 merge:

```text
feature/g6-reliability-matrix
```

## G6.0 Transition

1. confirm latest PR #8 head after closure docs is green
2. mark PR #8 Ready for review if still Draft
3. review / resolve findings
4. merge PR #8 into `main`
5. update local `main`
6. create G6 branch
7. run a clean baseline

Baseline:

```bash
flutter analyze
make test
make golden-test
make rust-fmt
make rust-clippy
make rust-test
make gpu-lut-verify
```

## G6.1 Image-size matrix

Test where hardware permits:

```text
small fixture
~12 MP
~24 MP
~48 MP
```

Cover portrait/landscape/square, JPEG/PNG/WebP paths, EXIF orientation and alpha where applicable.

Measure where practical:

- Editor startup/decode
- reduced-preview preparation
- operation latency
- Apply latency
- export time
- peak RSS / memory-pressure behavior

## G6.2 Long-session / soak

Stress:

- repeated G5 slider edits
- Curve/HSL
- Apply/Discard
- Undo/Redo
- transforms
- repeated export
- Editor reopen
- Camera→Editor loops
- lifecycle loops
- Film Profile create/edit/duplicate/load/import/export

Watch for memory growth, renderer leaks, stale temp/recovery data, native crashes, recipe/profile corruption and progressive slowdown.

## G6.3 Device matrix

When available:

```text
iOS: A13 reference + newer tier + lower-memory supported tier
Android: materially different Mali + Adreno devices
```

## G6.4 Thermal / sustained workload

Observe long camera/editor/export sessions for throttling and responsiveness degradation. Avoid unnecessary continuous rendering while idle.

## G6.5 Failure injection

Test:

- missing/corrupt LUT
- native renderer failure
- missing source
- corrupt recovery recipe
- corrupt Film Profile JSON
- unsupported imported fields
- export failure
- gallery write failure
- permission denied
- lifecycle interruption during processing

Required behavior remains fail-closed to valid Rust/product state.

---

# 10. G7 — Release / Beta / Store Readiness

Planned areas:

- production build hygiene
- Android ABI/native-lib verification
- iOS signing/build settings
- min/target OS policy
- privacy/permissions
- crash diagnostics without image pixels
- CI/CD release checks
- beta distribution
- store assets/copy/privacy disclosure
- release-candidate real-device smoke

---

# 11. Verification rules

1. Never claim a test/device/benchmark passed unless actually run or reported.
2. Keep recorded numeric evidence unchanged unless superseded by a new measured result.
3. Distinguish numeric parity, functional smoke and characterization.
4. Record device/OS/backend for new performance evidence where possible.
5. Rust remains authoritative even when GPU output looks correct.
6. Unsupported GPU composition fails closed rather than approximating order/semantics.
7. Do not create numeric GPU parity claims for G5 controls that currently use Rust on release.
8. A documentation-only closure commit triggers new CI; merge only when the latest PR head is green.

---

# 12. Current next action

**G5 is CLOSED / VERIFIED as of 2026-08-12.**

Start here:

```text
1. confirm latest PR #8 head after these documentation commits is green
2. mark PR #8 Ready for review if still Draft
3. review / resolve findings
4. merge PR #8 into main
5. update local main
6. create feature/g6-reliability-matrix
7. create docs/G6_RELIABILITY_MATRIX.md
8. run and record clean G6 baseline
9. begin G6.1 image-size matrix + G6.2 long-session soak
```

Suggested commands after PR #8 merge:

```bash
git switch main
git pull
git switch -c feature/g6-reliability-matrix

flutter analyze
make test
make golden-test
make rust-fmt
make rust-clippy
make rust-test
make gpu-lut-verify
```

Do not continue G6 reliability work on `feature/editor-tone-controls` after G5 merge.
# PixelCraft Project Handoff

## Purpose

This is the single handoff / continuation document for PixelCraft.

When opening a new ChatGPT conversation, read this file first, inspect the current Git branch and HEAD, then continue from **Current next action**. Repository state and recorded verification evidence take precedence over prior chat context.

Recommended new-chat prompt:

```text
อ่าน docs/PROJECT_HANDOFF.md ใน repo PixelCraft แล้วทำต่อจาก Current next action
```

---

# 1. Repository and architectural invariants

- Repository: `dexter-cnx/PixelCraft`
- Primary app: Flutter
- Authoritative image engine: Rust
- iOS realtime GPU backend: Metal
- Android realtime camera-preview backend: OpenGL ES
- Flutter/Dart is the UI/control/presentation plane

Milestone branches / PRs:

```text
G2  feature/camera-film-preview        CLOSED / MERGED
G3  feature/editor-gpu-production      CLOSED / MERGED via PR #6
G4  feature/editor-product-ux          CLOSED / MERGED via PR #7
G5  feature/editor-tone-controls       CLOSED / VERIFIED, PR #8 open at handoff time
```

Hard contracts unless an explicit architecture decision changes them:

1. Rust is authoritative for committed edit semantics, history, checkpoints, session recipe and full-resolution export.
2. GPU/compositor rendering is a low-latency interactive preview path, not the final-render source of truth.
3. Camera Film is preview-only; capture source stays clean.
4. Live camera frame buffers must not cross Dart MethodChannel or Flutter Rust Bridge.
5. Creative/Film LUTs should derive from Rust-owned canonical data instead of duplicating creative algorithms in native shaders.
6. Any GPU/native failure must fail closed to a valid Rust preview instead of corrupting editor state.
7. Renderer operation order must follow authoritative Rust recipe semantics. Unsupported order must fall back instead of being silently reordered.
8. Reusable Film Profiles are data/configuration. They are not captured GPU pixels and are not per-image Editor sessions.
9. Import compatibility must report exact / approximated / unsupported mappings; unsupported fields must never be silently discarded.
10. New editing effects are defined and tested in Rust first. GPU implementation is optional and must not approximate semantics silently.

Canonical committed flow:

```text
Camera / imported image
        ↓
clean source image
        ↓
Flutter editor control/presentation state
        ↓
interactive GPU preview where faithfully representable
        ↓ gesture release / command
Rust edit graph / recipe
        ↓
authoritative preview + history + checkpoint
        ↓
full-resolution Rust replay/export
```

Film Profile flow:

```text
Built-in / User-created / Imported profile
        ↓
FilmProfileV1
        ↓ materialize
Film base operation + scalar filter operations
        ↓
Rust session recipe
        ├── Editor authoritative preview
        ├── history / checkpoint / recovery
        └── full-resolution export
```

---

# 2. Milestone map

```text
G1  Camera GPU Preview                          CLOSED
G2  Editor GPU Preview Foundation               CLOSED / MERGED
G3  Production Rendering Pipeline               CLOSED / MERGED
G4  Product Editor UX / Session Workflow        CLOSED / MERGED
G5  Editing Feature Completeness                CLOSED / VERIFIED
G6  Reliability / Performance / Device Matrix   NEXT
G7  Release / Beta / Store Readiness            PLANNED
```

Interpretation:

- G1-G2 proved the native preview architecture and Editor transaction model.
- G3 made the GPU/runtime path production-grade while preserving Rust authority.
- G4 converted the Editor from an engineering surface into a coherent product workflow.
- G5 completed the planned editing capability set, Film Profile foundation, Creator, import/export and Film Lab V1.
- G6 now needs to prove reliability across image sizes, long sessions, device/GPU families, lifecycle stress and failure injection.
- G7 is the release/distribution gate.

---

# 3. G1 — Camera GPU Preview — CLOSED

## Android

```text
Camera2
 -> SurfaceTexture
 -> GL_TEXTURE_EXTERNAL_OES
 -> GLES shader
 -> canonical Film LUT atlas
 -> EGL / TextureView
 -> Flutter AndroidView
```

Film LUT parity passed on physical Android for all six LUTs with recorded max errors around `0.0017-0.0019`, below `2/255`.

## iOS

```text
AVCaptureSession
 -> AVCaptureVideoDataOutput
 -> BGRA CVPixelBuffer
 -> CVMetalTextureCache
 -> Metal
 -> canonical 33^3 Film LUT
 -> MTKView
 -> Flutter UiKitView
```

Capture uses `AVCapturePhotoOutput` and remains clean. Front-camera mirroring is preview-only.

Recorded iOS evidence includes:

- Original preview around 59.74 FPS, p95 ~16.78 ms.
- Velvia preview around 58.57 FPS, p95 ~16.83 ms.
- Metal command completion p95 ~1.31 ms.
- Camera/still color-path characterization source max delta ~0.0113 and Film max delta ~0.0121; characterization, not pixel-perfect parity.

Relevant document: `docs/G1_IOS_VERIFICATION.md`.

---

# 4. G2 — Editor GPU Preview Foundation — CLOSED / MERGED

G2 closed with host and physical-device smoke passing on 2026-08-11.

Primary closure record: `docs/G2_FINAL_VERIFICATION.md`.

Editor transaction model:

```text
slider drag    -> GPU-only draft where eligible
slider release -> Rust semantic commit
Apply/Discard  -> Rust checkpoint semantics
Undo/Redo      -> Rust history
Export         -> Rust full-resolution render
```

Verified primitives include:

- Brightness / Contrast / Saturation numeric parity
- Sharpen Rust 3x3 cross-kernel semantics
- deterministic Gaussian Blur parity
- `grayscale` / `invert` native compute semantics
- Rust/photon-rs generated canonical LUTs for creative presets
- interactive crop / straighten / rotate / flip
- stale renderer/activation guards and Rust fallback

Draft composition contract:

- each Adjust parameter is an independent slot
- multiple Adjust slots may coexist
- one Creative slot may coexist with Adjust
- one Film slot may coexist with Adjust and Creative
- tool switching is not Apply or Discard
- control values are remembered while the draft is active

Relevant documents:

```text
docs/G2_FINAL_VERIFICATION.md
docs/G2_5_TRANSFORM_PREVIEW_CONTRACT.md
docs/G2_6_EDITOR_GPU_HARDENING.md
docs/EDITOR_DRAFT_COMPOSITION.md
```

---

# 5. G3 — Production Rendering Pipeline — CLOSED / MERGED

Primary closure records:

```text
docs/G3_FINAL_VERIFICATION.md
docs/G3_DEVICE_VERIFICATION.md
```

PR #6: `G3: production rendering pipeline`.

`GpuEditorRenderPlan` reads:

```text
operations[checkpoint_cursor .. cursor]
```

and only builds a native plan when Rust operation order can be represented faithfully.

Current iOS Metal topology:

```text
optional Creative compute
 -> Gaussian Blur
 -> Sharpen
 -> Brightness
 -> Contrast
 -> Saturation
 -> optional final LUT
```

Fallback cases include unsupported transforms/order, Creative-LUT + Film LUT-slot conflict and renderer create/update failure.

Recorded Apple A13 evidence:

```text
Adjustment parity max error     0.0019263029098510742
Adjustment tolerance            1/255
Gaussian Blur max error         0.0
Creative compute max error      0.0
Adjustment + Film p95           1.104 ms
Heavy Gaussian Blur p95         11.418 ms
Frame budget target             16.67 ms
Renderer recreate               12/12 PASS
```

Manual runtime checks passed for multi-adjust continuity, cross-tool composition, fallback, lifecycle stress, reopen, Camera→Editor loops, Before overlay invalidation and Rust full-resolution export.

---

# 6. G4 — Product Editor UX / Session Workflow — CLOSED / MERGED

PR #7: `G4: product editor UX and session workflow`.

Primary record:

```text
docs/G4_PRODUCT_UX_VERIFICATION.md
```

G4 product behavior:

## G4.1 Tool state / Reset

- recipe-derived changed indicators
- per-adjust changed indicators
- Reset current parameter
- Reset Adjust / Creative / Film section
- correct active-draft vs applied-checkpoint distinction
- stale redo truncation when Reset creates a new semantic branch
- Reset affects only the active draft after `checkpoint_cursor`

Reset remains recipe-based and is restored through Rust; it is not cosmetic Flutter state.

## G4.2 Before

Press-and-hold Before compares against the latest Apply checkpoint and invalidates active GPU overlay before showing checkpoint pixels.

## G4.3 History

History is derived from the authoritative recipe and distinguishes applied operations from active draft operations. Undo/Redo remain Rust operations. Random-access history jumping is intentionally not exposed without a separate verified Rust contract.

## G4.4 Recovery

Recovery uses generation-based atomic publishing and validates:

- recipe envelope
- cursor/checkpoint bounds
- source fingerprint
- corrupt/mismatched newest generation rejection
- older valid generation fallback
- valid legacy recovery compatibility

## G4.5 Exit policy

Active draft Back policy:

```text
Continue Editing
Discard
Apply & Exit
```

## G4.6 Export

- PNG / JPEG / WEBP
- quality control for lossy formats
- original-source resolution policy
- current active draft included
- gallery save with app backup path
- optional Share
- Rust authoritative full-resolution replay

Current export path newly encodes output and does not re-attach original EXIF/metadata. Do not claim metadata preservation.

G4 physical/product smoke and host gates passed before closure.

---

# 7. G5 — Editing Feature Completeness — CLOSED / VERIFIED

Implementation branch:

```text
feature/editor-tone-controls
```

PR #8:

```text
G5.1-G5.7: editing completeness and Film Lab
```

At this handoff point PR #8 is still open/draft; implementation and verification are complete. The latest recorded PR head before this documentation update had host CI run #109 passing. Physical/product G5 smoke was reported PASS on 2026-08-12.

G5 follows the dependency order:

```text
G5.1 Tone
 -> G5.2 Color / WB bias
 -> G5.3 Finish / Texture
 -> G5.4 Film Profile Foundation
 -> G5.5 Film Profile Creator V1
 -> G5.6 Recipe Import / Export
 -> G5.7 Advanced Film Lab V1
```

Primary G5 contract document:

```text
docs/G5_EDITING_FEATURE_COMPLETENESS.md
```

## G5.1 Tone — CLOSED

Added Rust-authoritative scalar filters:

```text
Exposure    range -2.0 ... +2.0 EV   neutral 0.0
Highlights  range -1.0 ... +1.0      neutral 0.0
Shadows     range -1.0 ... +1.0      neutral 0.0
```

Exposure uses multiplicative `2^EV` semantics. Highlights and Shadows use luminance-selective masks. Alpha is preserved.

The Flutter Editor no longer assumes one universal `0...2` range / `1.0` neutral. Adjustment metadata is centralized so UI, Reset and tests share the same parameter contract.

Existing neutral corrections are also represented in the catalog, including:

```text
Brightness      1.0
Contrast        1.0
Saturation      1.0
Sharpen         0.0
Gaussian Blur   0.0
```

GPU rule: only controls with an existing faithful native implementation use continuous GPU drag. New controls stay on Rust commit/replay until a parity-safe GPU implementation exists.

## G5.2 Color / WB bias — CLOSED

Added:

```text
Temperature  -1.0 ... +1.0  neutral 0.0
Tint         -1.0 ... +1.0  neutral 0.0
Vibrance     -1.0 ... +1.0  neutral 0.0
```

These are image-edit color-bias semantics, not camera sensor white-balance controls. Do not market them as colorimetrically calibrated WB without a future explicit color-space/calibration contract.

## G5.3 Finish / Texture — CLOSED

Added:

```text
Vignette  -1.0 ... +1.0  neutral 0.0
Grain      0.0 ... 1.0   neutral 0.0
```

Grain is deterministic using a fixed coordinate hash so recipe replay, recovery and full-resolution export do not depend on hidden RNG state.

## G5.4 Film Profile Foundation — CLOSED

Main model:

```text
FilmProfileV1
```

Core characteristics:

- vendor-neutral PixelCraft schema
- explicit schema version
- explicit minimum engine version
- origins: built-in / user / imported
- optional base Film ID + strength
- normalized scalar parameters
- tags / name / description
- built-ins treated as immutable; customization uses duplication
- profile data is separate from EditorSession/history/crop/source state

The profile parameter catalog reuses the same semantic IDs/ranges used by the Editor where applicable.

Custom profiles are materialized into normal Rust session operations rather than creating a second rendering engine.

Conceptually:

```text
FilmProfileV1
 -> optional film_profile operation
 -> zero or more filter operations
 -> restore through Rust engine
 -> normal recipe/history/checkpoint/export semantics
```

## G5.5 Film Profile Creator V1 — CLOSED

Implemented user workflow supports:

- create profile
- edit user profile
- duplicate profile
- select optional base Film
- tune Tone
- tune Color
- tune Texture
- tune Curve/HSL parameters exposed by V1
- save to local profile store
- load My Films into Editor

The Creator is configuration authoring. It does not compile shader code and it does not store captured image/session state as part of the reusable profile.

## G5.6 Recipe Import / Export — CLOSED

PixelCraft profile JSON supports schema/versioned export and import.

Generic recipe mapping reports each field as:

```text
exact
approximated
unsupported
```

The importer never silently drops unsupported settings.

Do not claim third-party camera recipe semantics are reproduced 1:1 unless separately verified.

## G5.7 Advanced Film Lab V1 — CLOSED

Implemented V1 advanced controls:

Parametric tonal zones:

```text
curve_shadows
curve_midtones
curve_highlights
```

HSL mixer sectors:

```text
red
yellow
green
cyan
blue
magenta
```

Each sector supports:

```text
Hue
Saturation
Luminance
```

These are scalar, replayable Rust operations so they work with existing recipe/history/checkpoint/recovery/export infrastructure without introducing a new session schema.

G5.7 is a V1 Film Lab, not a claim of a full arbitrary point-curve editor or professional color-managed grading suite.

## G5 verification — CLOSED

Recorded verification at closure:

```text
latest G5 host CI                          PASS
Flutter analyze / state / widget gates     PASS via CI
macOS Golden tests                         PASS via CI
Rust fmt / clippy / tests                  PASS via CI
FRB generation/committed bridge checks     PASS via CI
GPU LUT verification                       PASS via CI
physical/product G5 smoke                  PASS (reported 2026-08-12)
```

The product smoke covered the integrated G5 editing/profile workflow rather than introducing new numeric GPU parity claims for controls that intentionally remain Rust-preview-on-release.

**Decision: G5 CLOSED / VERIFIED.**

---

# 8. G6 — Reliability / Performance / Device Matrix — NEXT

Goal: prove the product survives real-world image sizes, devices, long sessions, lifecycle transitions and controlled failures.

Create early:

```text
docs/G6_RELIABILITY_MATRIX.md
```

Recommended branch after PR #8 merge:

```text
feature/g6-reliability-matrix
```

## G6.0 Transition / baseline

Before G6 implementation:

1. confirm PR #8 latest head CI is green
2. mark PR #8 Ready for review if still Draft
3. merge PR #8 into `main`
4. update local `main`
5. create G6 branch from merged `main`
6. run clean baseline
7. record exact device/build versions used by G6 evidence

Suggested baseline:

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

Test representative source sizes where hardware permits:

```text
small fixture
~12 MP
~24 MP
~48 MP
```

Cover:

- portrait / landscape / square
- JPEG / PNG / WebP where supported by existing paths
- EXIF orientation cases
- alpha where applicable

Measure where practical:

- Editor startup/decode
- reduced-preview preparation
- semantic operation latency
- Apply latency
- full-resolution export time
- peak RSS / memory pressure behavior

## G6.2 Long-session / soak

Stress:

- repeated slider edits
- G5 Tone/Color/Texture controls
- Curve/HSL operations
- Apply / Discard
- Undo / Redo
- crop / straighten / rotate
- repeated export
- Editor close/reopen
- Camera→Editor loops
- lifecycle loops
- Film Profile create/edit/duplicate/load/import/export

Watch for:

- memory growth
- renderer leaks
- stale temp/recovery files
- native crashes
- recipe/profile corruption
- progressive slowdown

## G6.3 iOS matrix

When devices are available, include materially different tiers:

- A13 reference baseline
- newer iPhone tier
- lower-memory/older supported tier

Re-run only the GPU parity/performance tests relevant to changed native code; do not invent new parity evidence when G6 changes only orchestration/reliability.

## G6.4 Android matrix

Cover materially different GPU families when available, preferably both:

```text
Mali
Adreno
```

Verify:

- camera native lifecycle
- Surface/Texture recreation
- LUT shader behavior
- permission/resume paths
- Camera→Editor transfer
- supported API-level spread

## G6.5 Thermal / sustained workload

Observe long continuous editing/export/camera-preview sessions for thermal throttling and responsiveness degradation. Avoid unnecessary continuous rendering while idle.

## G6.6 Failure injection

Explicitly test:

- missing/corrupt LUT
- native renderer creation/update failure
- unavailable source file
- corrupt recovery recipe
- corrupt Film Profile JSON
- unsupported imported fields
- export encode failure
- gallery write failure
- permission denied
- lifecycle interruption during processing

Required contract remains: fail closed to valid Rust/product state, not stale native pixels or corrupt recipe data.

## G6 exit gate

G6 closes only when a documented matrix identifies:

- devices/builds tested
- workloads and image sizes tested
- pass/fail results
- observed performance/memory data where measured
- known limitations
- blockers deferred to G7 or later

---

# 9. G7 — Release / Beta / Store Readiness

## G7.1 Production build hygiene

- compile-gate diagnostics
- verify release native libraries
- verify Android ABI packaging
- verify iOS signing/build settings
- verify min/target OS policy
- verify identifiers/versioning
- remove accidental debug logging

## G7.2 Privacy and permissions

Document Camera and Photos/Gallery purposes, local image-processing behavior, analytics/crash policy and the invariant that image pixels are not sent to telemetry unless a future explicit product decision changes it.

## G7.3 Crash / diagnostic telemetry

If added, collect only necessary app/device/error context; avoid photo pixels and sensitive paths/content.

## G7.4 CI/CD

Automate Flutter analyze/test/golden, Rust fmt/clippy/test, LUT verification, Android release/native-lib checks, iOS build validation where possible and version/tag policy.

## G7.5 Beta distribution

```text
internal developer build
 -> small closed beta
 -> collect crash/performance/UX issues
 -> fix blocker/severe issues
 -> wider beta
 -> store submission candidate
```

## G7.6 Store assets/polish

Finalize app icon, screenshots, onboarding/help, store copy, privacy disclosure, support path, known limitations and release notes.

## G7.7 Release candidate gate

```text
clean checkout
 -> dependency resolution
 -> full host verification
 -> release builds
 -> real-device install
 -> camera/import/edit/export smoke
 -> Film Profile smoke
 -> recovery smoke
 -> permissions smoke
 -> lifecycle smoke
 -> final crash/log review
```

Exit definition: PixelCraft is ready for controlled public distribution.

---

# 10. Future candidates after G7

Not required for the initial product unless reprioritized:

- cloud sync/account system
- cross-device project library
- preset marketplace/community
- RAW/DNG pipeline
- masking/local adjustments
- AI segmentation/object editing
- batch processing
- desktop/web editor
- collaboration
- arbitrary point-curve editor
- advanced halation/bloom/light-leak simulation
- calibrated color-management pipeline

Do not let these expand G6/G7 scope without an explicit product decision.

---

# 11. Verification and evidence rules

1. Never claim a test, benchmark or device result passed unless actually run/reported.
2. Keep recorded numeric evidence unchanged unless a new benchmark supersedes it.
3. Distinguish numeric parity from visual/functional validation.
4. Distinguish characterization from parity.
5. Record device/OS/backend for performance evidence where available.
6. Prefer deterministic fixtures for renderer parity.
7. Keep Rust authoritative even when GPU preview appears visually correct.
8. Unsupported GPU composition must fail closed rather than approximate semantic order.
9. Do not create numeric GPU parity claims for G5 controls that currently use Rust on release.
10. A documentation-only closure commit can trigger CI; merge only after the latest PR head is green.
11. Physical/product smoke reported by a developer is valid functional evidence but must not be rewritten as automated numeric parity evidence.

---

# 12. Important current files

```text
Flutter startup
  lib/main.dart

Home / source / recovery
  lib/ui/screens/home_screen.dart

Editor shell
  lib/ui/screens/editor_screen.dart
  lib/ui/widgets/editor_tool_panel.dart

Editor state / recipe projection
  lib/state/editor_controller.dart
  lib/state/editor_recipe_summary.dart
  lib/state/editor_adjustment_catalog.dart

Film Profile domain / persistence / materialization
  lib/core/film_profile.dart
  lib/core/film_profile_store.dart
  lib/core/film_profile_materializer.dart

Film Profile UI
  lib/ui/screens/film_profiles_screen.dart
  lib/ui/screens/film_profile_editor_screen.dart

Recovery
  lib/core/editor_session_store.dart

Rust adapter
  lib/core/image_engine.dart

GPU planning / lifecycle
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

Primary current walkthrough:

```text
docs/CODE_WALKTHROUGH.md
```

---

# 13. Current next action

**G5 is CLOSED / VERIFIED as of 2026-08-12.**

Recorded closure evidence:

```text
G5.1 Tone semantics                          PASS
G5.2 Color / WB-bias semantics               PASS
G5.3 deterministic Finish / Texture          PASS
G5.4 FilmProfileV1 foundation                PASS
G5.5 Creator / My Films workflow             PASS
G5.6 import/export compatibility             PASS
G5.7 Curve + 6-sector HSL Film Lab V1        PASS
latest host CI                               PASS (run #109 before closure docs)
physical/product G5 smoke                    PASS (reported 2026-08-12)
```

PR #8 is the G5 integration PR.

Start here:

```text
1. confirm the latest PR #8 head after closure docs is green
2. mark PR #8 Ready for review if it is still Draft
3. review / resolve findings
4. merge PR #8 into main
5. update local main
6. create feature/g6-reliability-matrix
7. create docs/G6_RELIABILITY_MATRIX.md
8. run and record a clean G6 baseline
9. begin G6.1 image-size matrix and G6.2 long-session soak
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

The highest-value next implementation is **G6.1 + G6.2**: establish the source-image/device reliability matrix and long-session soak harness before release-oriented G7 work.
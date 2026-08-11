# PixelCraft Project Handoff

## Purpose

This is the single handoff / continuation document for PixelCraft.

When opening a new ChatGPT conversation, read this file first, inspect the current Git branch and HEAD, and continue from the first unfinished gate. Do not rely on previous chat context if it conflicts with the repository.

Recommended new-chat prompt:

```text
อ่าน docs/PROJECT_HANDOFF.md ใน repo PixelCraft แล้วทำต่อจาก Current next action
```

---

# 1. Repository and architectural invariants

- Repository: `dexter-cnx/PixelCraft`
- G2 working branch: `feature/camera-film-preview`
- Primary app: Flutter
- Authoritative image engine: Rust
- iOS realtime GPU backend: Metal
- Android realtime camera-preview backend: OpenGL ES
- Flutter/Dart is the UI/control plane.

These are hard contracts unless an explicit architecture decision changes them:

1. Rust is authoritative for committed edit semantics, history, checkpoints, session recipe and full-resolution export.
2. GPU/compositor rendering is a low-latency interactive preview path, not the final-render source of truth.
3. Camera Film is preview-only; capture source stays clean.
4. Live camera frame buffers must not cross Dart MethodChannel or Flutter Rust Bridge.
5. Do not duplicate Photon creative-preset algorithms in Metal when a Rust-generated canonical LUT can preserve one source of truth.
6. Any GPU/native failure must fail closed to a valid Rust preview instead of corrupting editor state.

Canonical committed flow:

```text
Camera / imported image
        ↓
clean source image
        ↓
Flutter editor control state
        ↓
interactive GPU/compositor preview
        ↓ gesture release / command
Rust edit graph / recipe
        ↓
authoritative preview + history
        ↓
full-resolution Rust export
```

---

# 2. Milestone map

```text
G1  Camera GPU Preview                          CLOSED
G2  Editor GPU Preview Foundation               CLOSING / merge gate
G3  Production Rendering Pipeline               NEXT
G4  Product Editor UX / Session Workflow        PLANNED
G5  Editing Feature Completeness                PLANNED
G6  Reliability / Performance / Device Matrix   PLANNED
G7  Release / Beta / Store Readiness            PLANNED
```

Interpretation:

- G1-G2 prove the rendering architecture and interaction model.
- G3 makes the rendering/editor runtime production-grade.
- G4 makes the editor behave like a coherent product rather than an engineering surface.
- G5 fills the editing capability set required for the intended product scope.
- G6 proves reliability on real devices, large images and long sessions.
- G7 turns the verified application into a distributable beta/store release.

A reasonable MVP-product gate is after G4 plus the selected MVP subset of G5 and the minimum G6 reliability gate. G7 is the release/distribution gate.

---

# 3. G1 — Camera GPU Preview — CLOSED

Camera preview architecture is established on Android and iOS.

## Android

Pipeline:

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

Pipeline:

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

Recorded iOS physical-device evidence includes:

- Original preview around 59.74 FPS, p95 ~16.78 ms.
- Velvia preview around 58.57 FPS, p95 ~16.83 ms.
- Metal command completion p95 ~1.31 ms in the recorded pipeline run.
- Camera/still color-path characterization recorded source max delta ~0.0113 and Film max delta ~0.0121; this is characterization, not pixel-perfect parity.

Relevant document:

- `docs/G1_IOS_VERIFICATION.md`

---

# 4. G2 — Editor GPU Preview Foundation — CLOSING

G2 implementation is functionally complete. The branch should not receive new product scope after the final gate.

## G2.0 Editor Metal lab

Static image -> Metal editor rendering path established.

## G2.1 Editor integration

Realtime iOS Metal draft integrated into the actual Editor.

Supported live paths include:

- Brightness
- Contrast
- Saturation
- Film strength
- later Sharpen / Gaussian Blur / Creative support

Transaction rule:

```text
slider drag    -> GPU-only draft
slider release -> Rust semantic commit
Apply/Cancel   -> Rust checkpoint semantics
Undo/Redo      -> Rust history
Export         -> Rust full-resolution render
```

Recorded adjustment + Film benchmark on Apple A13:

- average ~1.228 ms
- p50 ~1.121 ms
- p95 ~1.930 ms
- p99/max ~2.560 ms

Target p95 <= 16.67 ms: PASS.

Adjustment numeric parity passed with overall max delta approximately `0.00192630` under tolerance `1/255`.

## G2.2 Sharpen

Rust semantics:

```text
0, -s, 0
-s, 1 + 4s, -s
0, -s, 0
```

Physical-device parity cases passed:

- 0.5 -> max delta `0.00000012`
- 1.0 -> max delta `0.00000024`
- 1.5 -> max delta `0.00000048`

## G2.3 Gaussian Blur

Rust uses `imageproc 0.23` Gaussian semantics. Important compatibility detail: parity must follow the exact dependency behavior, including its historical unnormalized 1D Gaussian kernel semantics and u8 intermediate quantization.

Deterministic fixture parity passed with overall max delta `0.00000000` for values `.25, .5, 1, 1.5, 2`.

Realtime benchmark on A13, 1024^2, blur value 2 / sigma 5:

- avg 7.778 ms
- p50 7.856 ms
- p95 9.007 ms
- p99/max 9.776 ms

Target p95 <= 16.67 ms: PASS.

## G2.4 Creative Filters

Creative filters:

- grayscale
- invert
- vintage
- oceanic
- lofi
- dramatic
- golden
- pastel_pink

`grayscale` and `invert` use verified native Metal compute semantics.

The other six presets use Rust/photon-rs generated canonical 33^3 LUTs and reuse the already-verified Metal 3D LUT runtime.

Do not claim a direct Rust-Photon-vs-interpolated-33^3-LUT numeric max delta; that explicit measurement was not performed. G2.4 was closed by verification composition of the canonical LUT generation, deterministic atlas verification, verified 3D LUT sampler and physical-device functional validation.

Relevant document:

- `docs/G2_4_CREATIVE_LUT_CONTRACT.md`

## G2.5 Transform Preview

Implemented:

- realtime Straighten via Flutter compositor during drag
- Rust authoritative `RotateDegrees` commit on release
- interactive crop overlay
- move + corner resize
- Free / 1:1 / 4:3 / 3:4 / 16:9 / 9:16
- exact BoxFit.contain mapping
- crop aspect locking in source-pixel space
- duplicate crop preset controls removed
- crop geometry regression tests

Critical crop formula:

```text
pixelCropAspect
  = (normalizedWidth / normalizedHeight)
    * sourceImageAspect
```

Therefore:

```text
normalizedRatio = targetPixelAspect / sourceImageAspect
```

Relevant document:

- `docs/G2_5_TRANSFORM_PREVIEW_CONTRACT.md`

## G2.6 GPU/session hardening

Implemented:

- stale GPU activation cancellation
- renderer generation/epoch guard
- renderer recreation after native failure
- centralized GPU invalidation
- rapid tool-switch protection
- Original-view invalidation
- stale checkpoint protection
- async native error capture and Rust fallback

Physical-device stress validation passed for rapid tool switching, slider use, Original view, Apply/Undo/Redo/Crop/Straighten and repeated live GPU activation. No stale Metal overlay or reported unhandled MethodChannel/Future error remained during the validated run.

Relevant document:

- `docs/G2_6_EDITOR_GPU_HARDENING.md`

## Draft composition contract

Before editor-level Apply:

- each core Adjust parameter is an independent slot
- multiple Adjust slots may coexist
- one Creative slot may coexist with Adjust
- one Film slot may coexist with Adjust and Creative
- changing tool is not Apply and not Cancel
- control values are remembered while still in the active draft

Example:

```text
Brightness 1.20
Contrast   1.30
Saturation 0.85
Vintage    0.60
Velvia     0.70
```

Revisiting Brightness must still show 1.20 until Apply/Cancel/history semantics change the draft.

Relevant document:

- `docs/EDITOR_DRAFT_COMPOSITION.md`

---

# 5. G2 final closure gate

Primary closure record:

- `docs/G2_FINAL_VERIFICATION.md`

Host gate:

```bash
git pull
bash tool/verify_g2.sh
```

Expected ending:

```text
[Pixel Craft] G2 HOST GATE: PASS
```

The gate covers analyzer, Dart unit/widget tests, Golden tests, Rust fmt/clippy/tests and GPU LUT verification.

Final physical-device smoke sequence:

```text
Camera Film preview
 -> capture clean image
 -> Adjust several controls without Apply
 -> revisit controls and verify remembered values
 -> Creative
 -> Film
 -> Sharpen
 -> Gaussian Blur
 -> Crop
 -> Straighten
 -> Rotate / Flip
 -> Undo / Redo
 -> Cancel
 -> create edits again
 -> Apply
 -> Export
```

Acceptance conditions:

- host gate passes on latest HEAD
- no stale GPU overlay
- Adjust control memory works before Apply
- Apply/Cancel semantics remain correct
- Undo/Redo remain Rust-recipe authoritative
- Camera Film stays preview-only
- Export comes from Rust full-resolution render

When these conditions are met, mark G2 CLOSED and merge `feature/camera-film-preview`.

Do not add G3 scope to the G2 branch after closure.

---

# 6. G3 — Production Rendering Pipeline

Suggested branch after G2 merge:

```text
feature/editor-gpu-production
```

Goal: convert the proven Editor GPU preview path into a production rendering/runtime architecture.

## G3.0 Baseline and branch setup

Tasks:

1. Merge verified G2 into `main`.
2. Create `feature/editor-gpu-production` from updated `main`.
3. Record analyzer/test/golden/Rust baseline.
4. Preserve G2 diagnostics in debug builds.
5. Do not alter Rust edit semantics during branch setup.

Exit gate: clean G3 branch with verified G2 behavior.

## G3.1 Multi-adjustment GPU composition — highest priority

Problem: Rust draft semantics allow multiple Adjust nodes to coexist. GPU preview must represent the full active Adjust state, not only the currently dragged slider.

Target:

```text
Editor draft controls
 |- brightness
 |- contrast
 |- saturation
 |- sharpen
 `- gaussian blur
       ↓
GpuEditorAdjustmentState
       ↓
Metal composed realtime preview
```

Example:

```text
Brightness 1.20
Contrast   1.30
Saturation 0.85
```

Dragging Brightness from 1.20 -> 1.25 must preview:

```text
Brightness 1.25 + Contrast 1.30 + Saturation 0.85
```

Tasks:

- expose the complete active Adjust state from controller/presentation state
- build `GpuEditorAdjustmentState` from all active Adjust values
- override only the currently dragged value transiently
- preserve Rust commit-on-release
- add controller/state regression coverage
- add deterministic multi-adjust parity cases against Rust
- benchmark representative multi-adjust combinations

Exit gate: GPU live preview matches Rust semantics for simultaneous Adjust slots within agreed parity and latency gates.

## G3.2 Cross-tool GPU composition

Goal: compose supported active draft state across Adjust + Creative + Film.

Example:

```text
Brightness 1.20
+ Contrast 1.30
+ Vintage 0.60
+ Velvia 0.70
```

Important: renderer order must follow authoritative Rust recipe order. Do not assume a fixed order without inspecting Rust session/edit-graph semantics.

Tasks:

- define GPU draft representation for the complete supported draft
- define authoritative operation-order mapping from Rust recipe
- update native renderer state atomically where practical
- support creative compute and creative-LUT paths
- support Film LUT in the same composed draft
- implement explicit fallback when any active node cannot be represented by GPU preview
- add parity cases for representative combinations

Exit gate: supported cross-tool compositions match authoritative Rust draft behavior.

## G3.3 Production renderer lifecycle

Cover:

- app background -> foreground
- platform view / renderer recreation
- editor reopen/close loops
- orientation/layout resize
- source/checkpoint replacement
- native renderer failure
- memory pressure where observable
- stale renderer cleanup
- deterministic Rust fallback

Debug `GPU READY` / `GPU LIVE` indicators should be debug-only or removed from product UI after lifecycle stabilization.

Exit gate: renderer lifecycle is transparent to normal editing and cannot corrupt semantic state.

## G3.4 GPU presentation/session state cleanup

G2 grew incrementally. Consolidate ad-hoc GPU fields into an explicit presentation model without duplicating the Rust graph.

Possible model:

```text
GpuEditorDraftState
  checkpointGeneration
  adjustments
  creative
  film
  activationGeneration
  rendererGeneration
  status
```

Goals:

- reduce `_gpuDraftKind/_gpuDraftKey/_gpuDraftValue` style state
- centralize invalidation/fallback rules
- make stale-work behavior unit-testable
- retain Rust as semantic source of truth

## G3.5 G3 verification / closure

Required gates:

- Flutter analyzer/test/golden pass
- Rust fmt/clippy/tests pass
- LUT verification passes
- existing G2 single-adjust parity remains passing
- multi-adjust parity passes
- representative Adjust + Creative + Film parity passes
- reference-device p95 remains within realtime budget
- background/foreground and editor reopen stress pass
- no stale native overlay/error across repeated sessions
- export remains Rust-authoritative

Create:

- `docs/G3_FINAL_VERIFICATION.md`

Exit definition: Editor GPU runtime is production-grade, though the overall application is not yet product-complete.

---

# 7. G4 — Product Editor UX and Session Workflow

Goal: turn the technically correct editor into a coherent user-facing product workflow.

## G4.1 Tool-state UX

Implement clear visual state for edited parameters:

- changed/active indicator on each Adjust control
- one-tap Reset for current parameter
- Reset section/tool
- optionally Reset All Draft
- correct neutral/default markers
- preserve remembered values across tool switching
- clearly distinguish active draft from applied checkpoint

Acceptance:

- user can tell what has been changed without manually opening every slider
- Reset operations produce deterministic Rust recipe changes

## G4.2 Before/After comparison

Improve current Original comparison:

- press-and-hold Before/After
- optional split view or compare gesture if UX justifies it
- compare against current checkpoint/source using Rust-authoritative state
- no stale GPU overlay when entering comparison

Acceptance: comparison is immediate, stable and semantically unambiguous.

## G4.3 History UX

Current Undo/Redo mechanics exist, but product UX should expose understandable edit history.

Potential scope:

- history sheet/list
- operation names + values
- checkpoint boundary visibility
- jump-to-history-position if Rust recipe/session supports it safely
- preserve existing Undo/Redo as baseline

Do not build UI that suggests history behavior Rust cannot guarantee.

## G4.4 Session recovery / autosave

Strengthen existing session persistence:

- autosave after authoritative semantic changes
- restore after app termination/relaunch
- source-image identity/version validation
- stale/corrupt recipe handling
- safe migration when recipe schema changes
- recovery UX when a previous session exists

Acceptance: interrupted editing does not silently lose or corrupt the session.

## G4.5 Exit / unsaved-draft policy

Define behavior when leaving Editor with unapplied draft:

- Apply / Discard / Continue Editing decision when necessary
- avoid accidental data loss
- distinguish editor-level Apply from Export

## G4.6 Product export UX

Improve export surface:

- format and quality
- output dimensions / resolution summary
- file size estimate if cheap and useful
- Save to Photos/Gallery
- Share
- clear export success/failure messaging
- preserve metadata policy explicitly
- no product UI leakage of internal temp-file paths unless debug build

## G4.7 Remove engineering-only UI

Production UI must not expose diagnostic labels such as `GPU READY`, `GPU LIVE`, internal renderer IDs or parity tooling.

Keep diagnostic screens accessible only in debug/developer builds.

## G4 final gate

Create `docs/G4_PRODUCT_UX_VERIFICATION.md` and verify at minimum:

- complete edit session from import/camera to export without debug concepts
- parameter state is understandable
- Apply/Cancel/Undo/Redo behavior is understandable
- app restart session recovery works
- navigation cannot silently lose an active draft
- export UX succeeds on both platforms

Exit definition: editor workflow feels like an actual product rather than an engineering prototype.

---

# 8. G5 — Editing Feature Completeness

Goal: select and implement the editing capability set needed for PixelCraft MVP/product positioning.

Do not implement every possible photo-editor feature blindly. Prioritize according to product scope and measurable user value.

## G5.0 Feature-priority decision

Before coding, define MVP vs post-MVP.

Recommended MVP candidate set beyond existing capabilities:

- Exposure
- Highlights
- Shadows
- Temperature
- Tint
- Vignette
- Grain
- improved crop/rotate/straighten controls

Candidates for a richer v1/post-MVP:

- Curves
- HSL / Color Mixer
- selective color
- denoise
- clarity / texture
- custom Film-profile creation
- saved user presets/recipes

For every new effect:

1. define Rust semantics first
2. add authoritative Rust test
3. decide whether realtime GPU implementation is justified
4. add parity/latency gate for GPU path if implemented
5. keep export Rust-authoritative

## G5.1 Tone controls

Candidate controls:

- Exposure
- Highlights
- Shadows
- Blacks/Whites if product scope needs them

Define ranges, neutral values and operation ordering explicitly.

## G5.2 White balance / color controls

Candidate controls:

- Temperature
- Tint
- optional Vibrance distinct from Saturation

Need color-space contract before claiming professional color accuracy.

## G5.3 Finish / texture controls

Candidate controls:

- Vignette
- Grain
- optional clarity/texture

Film Grain should be deterministic for recipe/export reproducibility; store/generate a stable seed if stochastic behavior is used.

## G5.4 Curves / HSL — optional richer v1

If included:

- Curves need compact serializable control points and stable interpolation semantics.
- HSL/Color Mixer needs explicit hue-sector definitions and parity tests.

These should not block MVP unless they are core product positioning.

## G5.5 Custom presets / Film recipes

Potential product feature:

- save current edit recipe as user preset
- apply preset to another image
- share/import preset later if desired

A preset should reference semantic Rust operations, not captured GPU output.

Exit definition: agreed MVP editing feature set is implemented, tested and documented.

---

# 9. G6 — Reliability, Performance and Device Matrix

Goal: prove the product survives real-world device/image/session conditions.

This is mandatory before broad release because PixelCraft spans Flutter, Rust and platform GPU APIs.

## G6.1 Image-size matrix

Test representative sources such as:

- small web image
- ~12 MP phone image
- ~24 MP image
- ~48 MP image where supported
- portrait / landscape / square
- JPEG / PNG / supported WebP path
- images with EXIF orientation
- alpha images where applicable

Measure:

- editor startup time
- preview memory
- operation latency
- Apply latency
- export time
- peak RSS where practical

## G6.2 Long-session / soak testing

Stress scenarios:

- repeated slider edits
- repeated Apply/Cancel
- many Undo/Redo operations
- repeated crop/straighten
- multiple exports
- open/close Editor repeatedly
- camera -> editor -> camera loops
- background/foreground loops

Watch for:

- memory growth
- renderer leaks
- stale temp files
- native crashes
- recipe corruption
- progressive slowdown

## G6.3 iOS matrix

At minimum cover multiple performance tiers when devices are available:

- reference A13 device
- newer Apple Silicon iPhone tier
- lower-memory/older supported tier if product minimum supports it

Verify Metal feature assumptions and memory behavior.

## G6.4 Android GPU/vendor matrix

Test across materially different GPU/device families when possible:

- Mali
- Adreno
- different Android API levels within supported range

Pay attention to:

- OpenGL shader behavior
- texture formats
- camera lifecycle
- surface recreation
- vendor-specific driver issues

## G6.5 Thermal / sustained workload

For long editing sessions and repeated blur/export:

- observe thermal throttling behavior
- ensure responsiveness degrades gracefully
- avoid runaway frame rendering when UI is idle

## G6.6 Failure injection

Test graceful failure for:

- missing/corrupt LUT asset
- renderer creation failure
- source file unavailable
- corrupt recovery recipe
- export write failure
- gallery permission/write failure
- camera permission denied
- app lifecycle interruption during async processing

## G6 final gate

Create `docs/G6_RELIABILITY_MATRIX.md` containing tested devices, OS versions, image matrix, metrics and known limitations.

Exit definition: no known blocker-class crash/data-corruption issue; supported device classes meet agreed responsiveness and memory budgets.

---

# 10. G7 — Release / Beta / Store Readiness

Goal: package the verified product for real users.

## G7.1 Production build hygiene

- remove or compile-gate diagnostics
- verify release mode native libraries
- verify Android ABI packaging
- verify iOS signing/build settings
- verify min/target OS policy
- verify app identifiers/versioning
- strip accidental debug logging where appropriate

## G7.2 Privacy and permissions

Document and validate:

- Camera permission purpose
- Photos/Gallery permission behavior
- image processing location (device-local unless later architecture changes)
- analytics/crash-reporting data policy
- no image pixels sent to telemetry unless an explicit future product decision changes that contract

Prepare privacy-policy text appropriate for distribution requirements.

## G7.3 Crash and diagnostic telemetry

If telemetry is added:

- collect app/version/device/OS/error context
- do not collect photo pixels or private image content
- redact file paths/user-sensitive data where possible
- separate debug diagnostic data from production analytics

## G7.4 CI/CD and release gates

Automate as much as practical:

- Flutter analyze/test/golden
- Rust fmt/clippy/test
- LUT generation/verification
- Android release build + native library verification
- iOS build validation where signing environment allows
- version/tag generation policy

## G7.5 Beta distribution

Suggested sequence:

1. internal developer build
2. small closed beta
3. collect crash/performance/UX issues
4. fix blocker/severe issues
5. wider beta
6. store submission candidate

Platforms may use TestFlight / appropriate Android beta distribution when account/configuration is ready.

## G7.6 Store assets and product polish

- app icon final
- screenshots
- onboarding/help
- store description
- privacy disclosure
- support/contact path
- known limitations
- release notes

## G7.7 Release candidate gate

Run a clean RC checklist on the exact release commit/tag:

```text
clean checkout
 -> dependency resolution
 -> full host verification
 -> release builds
 -> install on real devices
 -> camera/import/edit/export smoke
 -> recovery smoke
 -> permissions smoke
 -> background/foreground smoke
 -> final crash/log review
```

Exit definition: PixelCraft is ready for controlled public distribution.

---

# 11. Product scope after G7 / future candidates

These are intentionally not required for the initial product unless prioritized later:

- cloud sync
- account system
- cross-device project library
- preset marketplace/sharing
- RAW/DNG development pipeline
- masking/local adjustments
- AI segmentation/object editing
- batch processing
- desktop/web editor
- collaboration

Do not let these expand MVP scope before G3-G7 gates are completed.

---

# 12. Verification and evidence rules

When continuing development:

1. Never claim a test, benchmark or device result passed unless it was actually run and reported.
2. Keep recorded numeric evidence unchanged unless a new benchmark intentionally supersedes it.
3. Distinguish numeric parity from visual/functional validation.
4. Distinguish characterization from parity.
5. Record device/OS/backend for performance results.
6. Prefer deterministic fixtures for renderer parity.
7. Keep Rust authoritative even when GPU preview appears visually correct.

Important known evidence limitation:

- No direct numeric Photon-preset vs interpolated creative-33^3-LUT maximum error was measured in G2. Do not invent one.

---

# 13. Current next action

At the time this handoff was created, G2 implementation and physical-device functional/stress validation had been completed, but the final consolidated host gate still needed to be run on the latest HEAD before declaring the branch fully CLOSED/MERGED.

Start here:

```bash
git status
git pull
bash tool/verify_g2.sh
```

If that passes, perform the final physical-device smoke from Section 5.

Then:

```text
mark G2 CLOSED
 -> merge feature/camera-film-preview
 -> update main
 -> create feature/editor-gpu-production
 -> start G3.0
 -> then G3.1 Multi-adjustment GPU composition
```

Do not begin G4/G5 product-scope additions until G3 production-rendering architecture is stable.

The highest-value implementation after G2 merge is **G3.1 Multi-adjustment GPU composition**.

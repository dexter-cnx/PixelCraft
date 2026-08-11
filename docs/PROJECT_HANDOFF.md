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
- Completed G2 branch: `feature/camera-film-preview`
- Planned G3 branch: `feature/editor-gpu-production`
- Primary app: Flutter
- Authoritative image engine: Rust
- iOS realtime GPU backend: Metal
- Android realtime camera-preview backend: OpenGL ES
- Flutter/Dart is the UI/control plane.

Hard contracts unless an explicit architecture decision changes them:

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
G2  Editor GPU Preview Foundation               CLOSED / MERGE-READY
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

Recorded iOS physical-device evidence includes:

- Original preview around 59.74 FPS, p95 ~16.78 ms.
- Velvia preview around 58.57 FPS, p95 ~16.83 ms.
- Metal command completion p95 ~1.31 ms.
- Camera/still color-path characterization source max delta ~0.0113 and Film max delta ~0.0121; characterization, not pixel-perfect parity.

Relevant document: `docs/G1_IOS_VERIFICATION.md`.

---

# 4. G2 — Editor GPU Preview Foundation — CLOSED / MERGE-READY

G2 is fully closed. Final consolidated host gate and final physical-device smoke both passed on 2026-08-11.

Primary closure record: `docs/G2_FINAL_VERIFICATION.md`.

## G2.0 Editor Metal lab

Static image -> Metal editor rendering path established.

## G2.1 Editor integration

Realtime iOS Metal draft integrated into the actual Editor.

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
- target p95 <= 16.67 ms: PASS
- adjustment numeric parity overall max delta ~`0.00192630` under `1/255` tolerance

## G2.2 Sharpen

Rust 3x3 cross-kernel semantics remain authoritative. Physical-device parity passed at strengths `0.5`, `1.0`, `1.5` with recorded max deltas below tolerance.

## G2.3 Gaussian Blur

Deterministic parity passed at values `.25, .5, 1, 1.5, 2` with overall max delta `0.00000000`.

A13 1024^2 blur value 2 / sigma 5:

- avg 7.778 ms
- p50 7.856 ms
- p95 9.007 ms
- p99/max 9.776 ms
- target p95 <= 16.67 ms: PASS

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

`grayscale` and `invert` use verified Metal compute semantics. The other six use Rust/photon-rs generated canonical 33^3 LUTs and the verified Metal LUT runtime.

Do not claim a direct Rust-Photon-vs-interpolated-33^3-LUT numeric max delta; that explicit measurement was not performed.

Relevant document: `docs/G2_4_CREATIVE_LUT_CONTRACT.md`.

## G2.5 Transform Preview

Implemented and device-validated:

- realtime Straighten via Flutter compositor during drag
- Rust authoritative `RotateDegrees` on release
- interactive crop overlay
- move + corner resize
- Free / 1:1 / 4:3 / 3:4 / 16:9 / 9:16
- exact BoxFit.contain mapping
- aspect locking in source-pixel space
- rotate-90 and flips as discrete Rust operations

Critical crop formula:

```text
pixelCropAspect
  = (normalizedWidth / normalizedHeight)
    * sourceImageAspect
```

Relevant document: `docs/G2_5_TRANSFORM_PREVIEW_CONTRACT.md`.

## G2.6 GPU/session hardening

Implemented and stress-validated:

- stale GPU activation cancellation
- renderer generation/epoch guard
- renderer recreation after native failure
- centralized GPU invalidation
- rapid tool-switch protection
- Original-view invalidation
- stale checkpoint protection
- async native error capture and Rust fallback

Relevant document: `docs/G2_6_EDITOR_GPU_HARDENING.md`.

## Draft composition contract

Before editor-level Apply:

- each core Adjust parameter is an independent slot
- multiple Adjust slots may coexist
- one Creative slot may coexist with Adjust
- one Film slot may coexist with Adjust and Creative
- changing tool is neither Apply nor Cancel
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

Relevant document: `docs/EDITOR_DRAFT_COMPOSITION.md`.

## G2 final closure evidence

```text
recorded device parity/latency gates  PASS
G2.5 transform device validation      PASS
G2.6 stress validation                PASS
draft-control memory validation       PASS
bash tool/verify_g2.sh                 PASS on 2026-08-11
final manual smoke                     PASS on 2026-08-11
```

Final host gate covered analyzer, Dart unit/widget tests, Golden tests, Rust fmt/clippy/tests, and Film + Creative LUT verification. Final device smoke covered Camera Film -> clean capture -> multi-adjust -> Creative -> Film -> Sharpen/Blur -> Crop/Straighten/Rotate/Flip -> Undo/Redo -> Cancel -> edit again -> Apply -> full-resolution export.

**Decision: G2 CLOSED / MERGE-READY.** Do not add G3 scope to the G2 branch.

---

# 5. Immediate post-G2 transition

Perform the repository transition before G3 coding:

```bash
git status
git pull
```

Confirm there are no local uncommitted changes that must be preserved. Then merge `feature/camera-film-preview` into `main` using the project's normal Git/PR workflow.

After merge:

```bash
git switch main
git pull
git switch -c feature/editor-gpu-production
```

Run a clean baseline on the new G3 branch before changing behavior:

```bash
flutter analyze
make test
make golden-test
make rust-fmt
make rust-clippy
make rust-test
make gpu-lut-verify
```

The first implementation target after baseline is **G3.1 Multi-adjustment GPU composition**.

---

# 6. G3 — Production Rendering Pipeline

Goal: convert the proven Editor GPU preview path into a production rendering/runtime architecture.

## G3.0 Baseline and branch setup

Tasks:

1. Merge verified G2 into `main`.
2. Create `feature/editor-gpu-production` from updated `main`.
3. Record analyzer/test/golden/Rust baseline.
4. Preserve G2 diagnostics in debug builds.
5. Do not alter Rust edit semantics during branch setup.
6. Create `docs/G3_FINAL_VERIFICATION.md` early and append evidence as work progresses.

Exit gate: clean G3 branch with verified G2 behavior.

## G3.1 Multi-adjustment GPU composition — highest priority

Problem: Rust draft semantics allow multiple Adjust nodes to coexist, but GPU live preview must represent the full active Adjust state rather than only the currently dragged control.

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

Example active Rust draft:

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

- inspect current `EditorState`/controller and expose complete active Adjust state without creating a second semantic graph
- build `GpuEditorAdjustmentState` from all active Adjust values
- override only the currently dragged value transiently
- preserve Rust commit-on-release
- keep unsupported state on Rust preview instead of partially lying about composition
- add state/controller regression coverage
- add deterministic multi-adjust parity cases against Rust
- test order-sensitive combinations
- benchmark representative multi-adjust combinations
- verify Sharpen + Blur composition remains within realtime budget

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

Critical rule: renderer order must follow authoritative Rust recipe order. Do not hard-code an order based only on UI categories.

Tasks:

- define GPU draft representation for the complete supported draft
- obtain authoritative operation order from Rust recipe/edit graph
- map supported operations into one ordered native render plan
- update renderer state atomically where practical
- support Creative compute and Creative-LUT paths
- support Film LUT in the same composed draft
- handle multiple Adjust + Creative + Film together
- implement explicit fallback when any active node cannot be represented faithfully
- add parity cases for representative combinations and operation orders
- preserve Rust full-resolution export as authority

Exit gate: supported cross-tool compositions match authoritative Rust draft behavior.

## G3.3 Production renderer lifecycle

Cover:

- app background -> foreground
- platform view / renderer recreation
- editor reopen/close loops
- orientation/layout resize
- source/checkpoint replacement
- renderer creation/update failure
- memory pressure where observable
- stale renderer cleanup
- repeated Camera -> Editor transitions
- deterministic Rust fallback

Requirements:

- stale renderer must never become visible after a newer checkpoint/source
- renderer failure must not mutate Rust semantic state
- returning from background must either restore a valid GPU renderer or show Rust preview
- renderer destruction/recreation must be idempotent

Debug `GPU READY` / `GPU LIVE` indicators should remain debug-only and eventually disappear from product UI.

Exit gate: renderer lifecycle is transparent to normal editing and cannot corrupt semantic state.

## G3.4 GPU presentation/session state cleanup

G2 grew incrementally. Consolidate ad-hoc GPU fields into an explicit presentation model without duplicating the Rust graph.

Candidate model:

```text
GpuEditorDraftState
  checkpointGeneration
  rendererGeneration
  activationGeneration
  orderedSupportedOperations
  adjustments
  creative
  film
  status
  fallbackReason
```

Goals:

- reduce `_gpuDraftKind/_gpuDraftKey/_gpuDraftValue` style state
- centralize invalidation/fallback rules
- separate semantic state from presentation state
- make stale-work behavior unit-testable
- keep Rust as semantic source of truth
- make diagnostics consume the model instead of scattered fields

## G3.5 G3 verification / closure

Required gates:

- Flutter analyzer/test/golden pass
- Rust fmt/clippy/tests pass
- LUT verification passes
- existing G2 single-adjust parity remains passing
- multi-adjust parity passes
- representative Adjust + Creative + Film parity passes
- operation-order cases pass
- reference-device p95 remains within realtime budget
- background/foreground stress passes
- editor reopen/recreate stress passes
- no stale native overlay/error across repeated sessions
- failure fallback returns to valid Rust preview
- export remains Rust-authoritative

Create/maintain: `docs/G3_FINAL_VERIFICATION.md`.

Exit definition: Editor GPU runtime is production-grade, though the overall application is not yet product-complete.

---

# 7. G4 — Product Editor UX and Session Workflow

Goal: turn the technically correct editor into a coherent user-facing product workflow.

## G4.1 Tool-state UX

Implement:

- changed/active indicator on each Adjust control
- Reset current parameter
- Reset section/tool
- optional Reset All Draft
- correct neutral/default markers
- preserve remembered values across tool switching
- clearly distinguish active draft from applied checkpoint

Acceptance: user can tell what changed without opening every slider, and Reset operations produce deterministic Rust recipe changes.

## G4.2 Before/After comparison

Improve current Original comparison:

- press-and-hold Before/After
- optional split view if justified
- compare against current checkpoint/source using Rust-authoritative state
- no stale GPU overlay during compare

## G4.3 History UX

Potential scope:

- history sheet/list
- operation names + values
- checkpoint boundary visibility
- jump-to-history-position only if Rust semantics support it safely
- preserve Undo/Redo as baseline

Do not create UI that promises history behavior Rust cannot guarantee.

## G4.4 Session recovery / autosave

Strengthen:

- autosave after authoritative semantic changes
- restore after app termination/relaunch
- source-image identity/version validation
- corrupt/stale recipe handling
- schema migration
- recovery UX when a previous session exists

Acceptance: interrupted editing does not silently lose or corrupt the session.

## G4.5 Exit / unsaved-draft policy

Define behavior when leaving Editor with unapplied draft:

- Apply / Discard / Continue Editing where needed
- avoid accidental data loss
- distinguish editor-level Apply from Export

## G4.6 Product export UX

Improve:

- format and quality
- dimensions/resolution summary
- file size estimate if useful
- Save to Photos/Gallery
- Share
- clear success/failure messaging
- explicit metadata policy
- hide internal temp paths outside debug builds

## G4.7 Remove engineering-only UI

Production UI must not expose `GPU READY`, `GPU LIVE`, renderer IDs, parity tooling, or other engineering labels. Keep diagnostic screens debug/developer-only.

## G4 final gate

Create `docs/G4_PRODUCT_UX_VERIFICATION.md` and verify:

- complete camera/import -> edit -> export flow without debug concepts
- parameter state is understandable
- Apply/Cancel/Undo/Redo are understandable
- app restart recovery works
- navigation cannot silently lose active draft
- export UX works on both platforms

Exit definition: editor workflow feels like a product rather than an engineering prototype.

---

# 8. G5 — Editing Feature Completeness

Goal: implement the agreed MVP editing set and user-created Film Profiles on top of stable semantics.

Recommended dependency order:

```text
G5.1 Tone controls
 -> G5.2 White balance / color controls
 -> G5.3 Finish / texture controls
 -> G5.4 Film Profile system foundation
 -> G5.5 Film Profile Creator V1
 -> G5.6 Recipe import/export compatibility
 -> G5.7 Advanced Film Lab / Curves / HSL
```

Do not start with Film Profile Creator UI before tone/color/texture semantics and the Film Profile schema are stable.

## G5.0 MVP boundary

Recommended MVP candidates beyond current features:

- Exposure
- Highlights
- Shadows
- Temperature
- Tint
- Vignette
- Grain
- improved crop/rotate/straighten UX
- Film Profile foundation
- Film Profile Creator V1 if customization is part of MVP positioning

Post-MVP candidates:

- Curves
- HSL / Color Mixer
- selective color
- denoise
- clarity / texture
- advanced grain response
- halation / bloom
- recipe text import
- QR/share-link transfer
- community profiles / marketplace

For every new effect:

1. define Rust semantics first
2. add authoritative Rust tests
3. decide whether realtime GPU implementation is justified
4. add parity/latency gates if GPU path exists
5. keep export Rust-authoritative

## G5.1 Tone controls

Candidates: Exposure, Highlights, Shadows, optional Blacks/Whites. Define ranges, neutral values and operation ordering explicitly.

## G5.2 White balance / color controls

Candidates: Temperature, Tint, optional Vibrance, optional Color Density.

Need an explicit color-space contract before claiming professional color accuracy. Distinguish input/camera white balance from Film Profile color bias.

## G5.3 Finish / texture controls

Candidates: Vignette, Grain, optional clarity/texture. Grain must be deterministic for recipe/export reproducibility; persist a stable seed if stochastic behavior is used.

## G5.4 Film Profile system foundation

A Film Profile is reusable creative-look data, not captured GPU pixels and not the same thing as per-image session state.

One model should support:

```text
Built-in Profile
User-created Profile
Imported Profile
Future Community Profile
        ↓
      FilmProfile
        ├── Camera Preview
        ├── Editor Preview
        └── Rust Full-resolution Export
```

Core invariants:

- Rust semantic operations are authoritative
- GPU previews profile semantics but is not source of truth
- built-ins are immutable; edit by duplication
- user profiles are data/configuration, not compiled shader code
- crop/rotation/capture state do not belong in a reusable Film Profile by default
- schema is vendor-neutral
- schema version and engine compatibility are explicit

Reserve metadata for ID, name, description, author, source, timestamps, tags/favorites, schema version, minimum/compatible engine version.

Exit gate: stable profile schema resolves deterministically to Rust operations and supports migration/version checks.

## G5.5 Film Profile Creator V1

Entry points:

```text
Create Film Profile
 |- Blank Profile
 |- Duplicate Existing Profile
 `- Film Recipe style setup
```

Recommended Simple controls:

- Base Look
- Profile Strength
- Contrast
- Highlights
- Shadows
- Saturation/Color
- Temperature bias
- Tint bias
- Grain amount/size
- Sharpness

Recipe mode may expose a discrete camera-recipe-like workflow but storage must remain PixelCraft/vendor-neutral. Do not claim proprietary third-party camera processing is reproduced 1:1 unless verified.

Creator UX:

- realtime production GPU preview where supported
- deterministic Rust final path
- Before/After
- Reset parameter/section
- Save / Save as Copy
- Duplicate
- delete user profiles only
- Favorites
- global Profile Strength
- changed-from-base indicators

Camera integration after Creator stabilizes:

```text
Camera
 -> quick Film Profile selector
 -> Built-in + Favorites + My Profiles
 -> realtime profile preview
 -> clean capture remains unchanged
```

## G5.6 Film Recipe import/export compatibility

Potential inputs: `.pixelcraftprofile`, structured JSON/package, pasted recipe text, QR/share link later.

Importer must show fields mapped exactly, approximated or unsupported; never silently discard unsupported settings.

## G5.7 Curves / HSL / Advanced Film Lab

Curves require stable interpolation/control-point semantics. HSL requires explicit hue-sector definitions. Toe/shoulder/highlight roll-off/color density need operation-order contracts. Halation and bloom remain separate effects.

## G5 final gate

Verify all selected MVP effects have Rust semantics/tests, GPU paths have appropriate parity/latency evidence, Film Profiles serialize/restore deterministically, ownership rules are enforced, Camera capture remains clean, and Editor/export resolve the same profile semantics.

---

# 9. G6 — Reliability, Performance and Device Matrix

Goal: prove the product survives real-world devices, image sizes and long sessions.

## G6.1 Image-size matrix

Test small image, ~12MP, ~24MP, ~48MP where supported, portrait/landscape/square, JPEG/PNG/WebP path, EXIF orientation, alpha where applicable.

Measure editor startup, preview memory, operation latency, Apply latency, export time and peak RSS where practical.

## G6.2 Long-session / soak

Stress repeated slider edits, Apply/Cancel, Undo/Redo, crop/straighten, exports, editor reopen, camera-editor loops, lifecycle loops and Film Profile edit/save cycles if included.

Watch for memory growth, renderer leaks, stale temp files, native crashes, recipe/profile corruption and progressive slowdown.

## G6.3 iOS matrix

Cover multiple performance tiers when available: A13 reference device, newer iPhone tier, lower-memory/older supported tier.

## G6.4 Android matrix

Cover materially different GPU families such as Mali and Adreno plus supported API-level spread. Verify shader behavior, texture formats, camera lifecycle and surface recreation.

## G6.5 Thermal / sustained workload

Observe thermal throttling and ensure responsiveness degrades gracefully. Avoid unnecessary continuous rendering while idle.

## G6.6 Failure injection

Test missing/corrupt LUT, renderer failure, unavailable source file, corrupt recovery recipe/profile, export failure, gallery write failure, permission denied and lifecycle interruption.

## G6 final gate

Create `docs/G6_RELIABILITY_MATRIX.md` with devices, OS versions, image matrix, metrics and known limitations.

Exit definition: no blocker-class crash/data-corruption issue and supported device classes meet agreed responsiveness/memory budgets.

---

# 10. G7 — Release / Beta / Store Readiness

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

## G7.3 Crash/diagnostic telemetry

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
 -> recovery smoke
 -> permissions smoke
 -> lifecycle smoke
 -> final crash/log review
```

Exit definition: PixelCraft is ready for controlled public distribution.

---

# 11. Future candidates after G7

Not required for initial product unless reprioritized:

- cloud sync/account system
- cross-device project library
- preset marketplace/community
- RAW/DNG pipeline
- masking/local adjustments
- AI segmentation/object editing
- batch processing
- desktop/web editor
- collaboration

Do not let these expand MVP scope before G3-G7 gates are completed.

---

# 12. Verification and evidence rules

1. Never claim a test, benchmark or device result passed unless actually run/reported.
2. Keep recorded numeric evidence unchanged unless a new benchmark supersedes it.
3. Distinguish numeric parity from visual/functional validation.
4. Distinguish characterization from parity.
5. Record device/OS/backend for performance evidence.
6. Prefer deterministic fixtures for renderer parity.
7. Keep Rust authoritative even when GPU preview appears visually correct.

Known evidence limitation: no direct numeric Photon-preset vs interpolated creative-33^3-LUT maximum error was measured in G2. Do not invent one.

---

# 13. Current next action

**G2 is CLOSED / MERGE-READY as of 2026-08-11.** Both final gates passed:

```text
bash tool/verify_g2.sh   PASS
physical-device smoke   PASS
```

Do not continue feature work on `feature/camera-film-preview`.

Start here:

```text
1. inspect git status / confirm all desired local work is committed
2. merge feature/camera-film-preview into main using normal project workflow
3. update local main
4. create feature/editor-gpu-production from updated main
5. run clean G3 baseline
6. start G3.1 Multi-adjustment GPU composition
```

Suggested commands after the merge is complete:

```bash
git switch main
git pull
git switch -c feature/editor-gpu-production

flutter analyze
make test
make golden-test
make rust-fmt
make rust-clippy
make rust-test
make gpu-lut-verify
```

After the baseline is green, inspect the current Editor/GPU integration and implement G3.1 so live GPU rendering composes **all active Adjust slots** while Rust remains authoritative on release/history/export.

Do not begin G4/G5 product-scope additions until G3 production-rendering architecture is stable.

When G5 begins, establish tone/color/texture semantics and the Film Profile schema/contract before exposing user-created Film Profile UI.

The highest-value implementation now is **G3.1 Multi-adjustment GPU composition**.
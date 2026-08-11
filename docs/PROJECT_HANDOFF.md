# PixelCraft Project Handoff

## Purpose

This is the single handoff / continuation document for PixelCraft.

When opening a new ChatGPT conversation, read this file first, inspect the current Git branch and HEAD, and continue from **Current next action**. Repository state and recorded verification evidence take precedence over prior chat context.

Recommended new-chat prompt:

```text
อ่าน docs/PROJECT_HANDOFF.md ใน repo PixelCraft แล้วทำต่อจาก Current next action
```

---

# 1. Repository and architectural invariants

- Repository: `dexter-cnx/PixelCraft`
- G2 branch: `feature/camera-film-preview` — merged/closed
- G3 branch: `feature/editor-gpu-production` — implementation and verification closed; PR #6 pending final review/merge workflow
- Primary app: Flutter
- Authoritative image engine: Rust
- iOS realtime GPU backend: Metal
- Android realtime camera-preview backend: OpenGL ES
- Flutter/Dart is the UI/control plane

Hard contracts unless an explicit architecture decision changes them:

1. Rust is authoritative for committed edit semantics, history, checkpoints, session recipe and full-resolution export.
2. GPU/compositor rendering is a low-latency interactive preview path, not the final-render source of truth.
3. Camera Film is preview-only; capture source stays clean.
4. Live camera frame buffers must not cross Dart MethodChannel or Flutter Rust Bridge.
5. Do not duplicate Photon creative-preset algorithms in Metal when a Rust-generated canonical LUT can preserve one source of truth.
6. Any GPU/native failure must fail closed to a valid Rust preview instead of corrupting editor state.
7. Renderer operation order must follow authoritative Rust recipe semantics. Unsupported order must fall back instead of being silently reordered.

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
G2  Editor GPU Preview Foundation               CLOSED / MERGED
G3  Production Rendering Pipeline               CLOSED / READY FOR REVIEW
G4  Product Editor UX / Session Workflow        NEXT
G5  Editing Feature Completeness                PLANNED
G6  Reliability / Performance / Device Matrix   PLANNED
G7  Release / Beta / Store Readiness            PLANNED
```

Interpretation:

- G1-G2 proved the rendering architecture and interaction model.
- G3 made the Editor GPU/runtime architecture production-grade while preserving Rust authority.
- G4 makes the editor behave like a coherent product rather than an engineering surface.
- G5 fills the editing capability set required for the intended product scope.
- G6 proves reliability on real devices, large images and long sessions.
- G7 is the release/distribution gate.

A reasonable MVP-product gate is after G4 plus the selected MVP subset of G5 and the minimum G6 reliability gate.

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

G2 closed with final host and physical-device smoke passing on 2026-08-11.

Primary closure record: `docs/G2_FINAL_VERIFICATION.md`.

## G2.1 Editor transaction model

```text
slider drag    -> GPU-only draft
slider release -> Rust semantic commit
Apply/Cancel   -> Rust checkpoint semantics
Undo/Redo      -> Rust history
Export         -> Rust full-resolution render
```

## G2.2–G2.4 verified primitives

- Brightness / Contrast / Saturation numeric parity verified.
- Sharpen Rust 3x3 cross-kernel semantics verified at strengths `0.5`, `1.0`, `1.5`.
- Gaussian Blur deterministic parity verified at `.25, .5, 1, 1.5, 2`.
- `grayscale` / `invert` use verified Metal compute semantics.
- `vintage`, `oceanic`, `lofi`, `dramatic`, `golden`, `pastel_pink` use Rust/photon-rs generated canonical 33^3 LUTs.

Known evidence limitation: no direct numeric Photon-preset-vs-interpolated-33^3-LUT max error was measured. Do not invent one.

## G2.5 Transform preview

Implemented and device-validated:

- realtime Straighten preview
- Rust authoritative `RotateDegrees` on release
- interactive crop overlay
- crop move + corner resize
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

Relevant document: `docs/EDITOR_DRAFT_COMPOSITION.md`.

---

# 5. G3 — Production Rendering Pipeline — CLOSED / READY FOR REVIEW

Primary closure record: `docs/G3_FINAL_VERIFICATION.md`.
Physical-device checklist: `docs/G3_DEVICE_VERIFICATION.md`.
PR: #6 `G3: production rendering pipeline`.

G3 was implemented on `feature/editor-gpu-production` from the merged G2 baseline.

## G3.0 Baseline

- G2 merged into `main` through PR #5.
- G3 branch created from updated `main`.
- Initial G3 CI baseline run #21 passed.
- G2 diagnostics retained in debug builds.

## G3.1 Multi-adjustment GPU composition — CLOSED

`GpuEditorRenderPlan` reads the active authoritative Rust recipe range:

```text
operations[checkpoint_cursor .. cursor]
```

and builds a complete GPU draft. A dragged value replaces only its semantic slot; existing Adjust values remain active.

Example:

```text
Rust draft
Brightness 1.20
Contrast   1.30
Saturation 0.85

Transient drag
Brightness -> 1.25

GPU plan
Brightness 1.25
Contrast   1.30
Saturation 0.85
```

The current iOS Metal stage topology is:

```text
optional compute Creative
 -> Gaussian Blur
 -> Sharpen
 -> Brightness
 -> Contrast
 -> Saturation
 -> optional final LUT
```

G3 never silently reorders Rust operations. If the active Rust order cannot be represented by this topology, the editor stays on the valid Rust preview.

Implemented:

- complete active Adjust state from Rust session recipe
- Brightness / Contrast / Saturation / Sharpen / Gaussian Blur as independent draft slots
- transient replacement of the current slot only
- Rust commit-on-release unchanged
- unsupported/unfaithful order fails closed
- ordered-plan host regression tests

## G3.2 Cross-tool composition — CLOSED

Supported planning covers active draft state across:

```text
Adjust + Creative + Film
```

Creative paths:

- `grayscale` / `invert` -> native compute stage
- `vintage` / `oceanic` / `lofi` / `dramatic` / `golden` / `pastel_pink` -> canonical Creative LUT

Faithful-or-fallback contract:

- Compute Creative + representable Adjust + Film is supported when Rust order matches native stages.
- Adjust + canonical Creative LUT is supported when Film is not active.
- Creative-LUT + Film explicitly falls back because both require the native final LUT slot.
- transform/unknown nodes fall back.
- unsupported Rust order falls back.

## G3.3 Production renderer lifecycle — CLOSED

`EditorScreen` now handles lifecycle and resource invalidation explicitly:

- background/inactive/hidden/detached -> invalidate GPU state and destroy renderer
- foreground -> keep Rust preview and lazily recreate GPU renderer on the next eligible interaction
- memory pressure -> drop renderer while preserving Rust semantics
- renderer generation guards stale creation
- activation generation guards stale recipe/source/update work
- checkpoint/source replacement invalidates stale GPU draft
- native create/update failure falls back to Rust
- renderer cleanup on dispose

## G3.4 Presentation/session state cleanup — CLOSED

G2's scattered draft fields were replaced by presentation-only state:

```text
GpuEditorDraftSession
  checkpointGeneration
  rendererGeneration
  activationGeneration
  status
  transient
  authoritative recipe snapshot
  GpuEditorRenderPlan
  fallbackReason
```

This model owns presentation lifecycle metadata only. Rust still owns semantic edit state.

Engineering indicators such as `GPU READY`, `GPU LIVE`, and `Metal live draft` are debug-only.

## G3 product hardening included

- Android main activity locked to portrait.
- iOS/iPad supported orientations reduced to portrait.
- Flutter runtime requests `DeviceOrientation.portraitUp`.
- accidental root files `__tmp_noop__`, `__tmp_noop2__`, `__tmp_noop3__` removed.

## G3 automated physical-device evidence

Physical iOS verification used an isolated verification bundle:

```text
dev.cnxdev.pixelcraft.g3verify
```

so the normal development install `dev.cnxdev.pixelcraft` remains separate.

The consolidated `flutter drive` device gate passed on Apple A13 GPU.

Recorded results:

```text
Native identity LUT parity                PASS
Film Profile Pack v2 LUT parity           PASS 6/6
G3.1 adjustment parity                    PASS
G3.1 Gaussian Blur parity                 PASS
G3.2 Creative compute parity              PASS
Renderer destroy/recreate                 PASS 12/12
Overall automated device gate             PASS
```

Adjustment parity:

- overall max error `0.0019263029098510742`
- tolerance `0.00392156862745098`
- 9 cases

Gaussian Blur parity:

- overall max error `0.0`
- tolerance `0.00784313725490196`

Creative compute parity:

- overall max error `0.0`
- tolerance `0.00392156862745098`

Adjustment + Film benchmark, Apple A13 GPU, 1024x1024, 60 iterations:

- avg `1.020 ms`
- p50 `1.000 ms`
- p95 `1.104 ms`
- p99/max `1.821 ms`
- target `16.67 ms`
- PASS

Heavy Gaussian Blur benchmark, Apple A13 GPU, 1024x1024, 60 iterations:

- avg `9.787 ms`
- p95 `11.418 ms`
- p99/max `11.514 ms`
- target `16.67 ms`
- PASS

Device command:

```bash
DEVICE=<ios-device-id> make g3-device-verify
```

The runner temporarily uses the isolated bundle id, runs one consolidated `flutter drive` session, and restores the Xcode project configuration through a shell trap.

## G3 manual runtime evidence

Manual physical-device checks were completed and reported PASS on 2026-08-11:

- multi-adjust visual continuity
- Sharpen + Blur continuity
- Undo/Redo without stale overlay
- representable cross-tool composition
- Creative-LUT + Film faithful Rust fallback
- unsupported-plan/order fallback
- background/foreground stress
- Editor close/reopen stress
- Camera -> Editor repeated flow
- Original/Before overlay invalidation
- full-resolution Rust export smoke
- no observed stale native overlay/crash/corrupted semantic state

## G3 final CI

- CI run #55 for pre-closure documentation head completed `success`.
- Host gate covers Flutter analyze, state/widget/GPU tests, macOS Golden tests, Rust fmt/clippy/tests, FRB generated bridge checks and GPU LUT verification.
- A documentation-only closure commit may trigger one final PR CI run; do not merge until the latest PR head is green.

**Decision: G3 CLOSED / READY FOR REVIEW.**

---

# 6. Transition from G3 to G4

Do not begin G4 work on the G3 branch before PR #6 is reviewed and merged.

Repository transition:

```text
feature/editor-gpu-production
        ↓ PR #6 Ready for review
review / final CI
        ↓
merge into main
        ↓
update local main
        ↓
create G4 feature branch
```

Suggested branch name:

```text
feature/editor-product-ux
```

Suggested commands after PR #6 merge:

```bash
git switch main
git pull
git switch -c feature/editor-product-ux

flutter analyze
make test
make golden-test
make rust-fmt
make rust-clippy
make rust-test
make gpu-lut-verify
```

Record a clean baseline before changing G4 behavior.

---

# 7. G4 — Product Editor UX and Session Workflow — NEXT

Goal: turn the technically correct editor into a coherent user-facing product workflow.

Create `docs/G4_PRODUCT_UX_VERIFICATION.md` early and append evidence throughout the milestone.

## G4.0 Clean branch / product baseline

Tasks:

1. Merge verified G3 PR #6 into `main`.
2. Create `feature/editor-product-ux` from updated `main`.
3. Run clean Flutter/Rust/golden/LUT baseline.
4. Confirm G3 device/runtime behavior is unchanged before UX refactors.
5. Keep engineering diagnostics debug-only.

Exit gate: clean G4 branch with verified G3 runtime.

## G4.1 Tool-state UX — first implementation target

Implement:

- changed/active indicator on each Adjust control
- Reset current parameter
- Reset section/tool
- optional Reset All Draft
- correct neutral/default markers
- preserve remembered values across tool switching
- clearly distinguish active draft from applied checkpoint

Acceptance:

- user can tell what changed without opening every slider
- Reset operations produce deterministic Rust recipe changes
- changing tools never silently Apply/Cancel the draft

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

Production UI must not expose GPU readiness labels, renderer IDs, parity tooling or other engineering concepts. Keep diagnostic screens debug/developer-only.

## G4 final gate

Verify:

- complete camera/import -> edit -> export flow without debug concepts
- parameter state is understandable
- Apply/Cancel/Undo/Redo are understandable
- app restart recovery works
- navigation cannot silently lose active draft
- export UX works on both platforms
- G3 Rust/GPU authority/fallback contracts remain intact

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

## G5.6 Film Recipe import/export compatibility

Potential inputs: `.pixelcraftprofile`, structured JSON/package, pasted recipe text, QR/share link later.

Importer must show fields mapped exactly, approximated or unsupported; never silently discard unsupported settings.

## G5.7 Curves / HSL / Advanced Film Lab

Curves require stable interpolation/control-point semantics. HSL requires explicit hue-sector definitions. Toe/shoulder/highlight roll-off/color density need operation-order contracts. Halation and bloom remain separate effects.

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

Create `docs/G6_RELIABILITY_MATRIX.md` during this milestone.

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

Do not let these expand MVP scope before G4-G7 gates are completed.

---

# 12. Verification and evidence rules

1. Never claim a test, benchmark or device result passed unless actually run/reported.
2. Keep recorded numeric evidence unchanged unless a new benchmark supersedes it.
3. Distinguish numeric parity from visual/functional validation.
4. Distinguish characterization from parity.
5. Record device/OS/backend for performance evidence where available.
6. Prefer deterministic fixtures for renderer parity.
7. Keep Rust authoritative even when GPU preview appears visually correct.
8. Unsupported GPU composition must fail closed rather than approximate semantic order.
9. A documentation-only closure commit can trigger CI; merge only after the latest PR head is green.

---

# 13. Current next action

**G3 is CLOSED / READY FOR REVIEW as of 2026-08-11.**

Recorded closure evidence:

```text
G3.1-G3.4 implementation                     PASS
host analyzer/state/widget/GPU/golden gates  PASS
Rust fmt/clippy/tests                         PASS
Film + Creative LUT verification              PASS
physical iOS parity                           PASS
physical iOS latency                          PASS
renderer recreate 12/12                       PASS
manual multi-adjust/cross-tool checks         PASS
manual lifecycle/reopen/camera-editor stress  PASS
manual Original/Before overlay check          PASS
manual Rust full-resolution export smoke      PASS
```

PR #6 remains the G3 integration PR.

Start here:

```text
1. confirm the latest PR #6 head CI is green
2. mark PR #6 Ready for review
3. review the PR / resolve any review findings
4. merge PR #6 into main using the project's normal workflow
5. update local main
6. create feature/editor-product-ux
7. run a clean G4 baseline
8. create docs/G4_PRODUCT_UX_VERIFICATION.md
9. start G4.1 Tool-state UX
```

Suggested commands after PR #6 is merged:

```bash
git switch main
git pull
git switch -c feature/editor-product-ux

flutter analyze
make test
make golden-test
make rust-fmt
make rust-clippy
make rust-test
make gpu-lut-verify
```

Do not continue product-scope G4/G5 work on `feature/editor-gpu-production` after G3 merge.

The highest-value implementation after the G3 merge is **G4.1 Tool-state UX**: changed/active indicators, deterministic Reset behavior and a clear distinction between active draft and applied checkpoint.

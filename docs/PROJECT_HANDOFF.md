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
6. Native/GPU failure must fail closed to a valid Rust preview/product state.
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
G5  Editing Feature Completeness                CLOSED / VERIFIED / MERGED
G6  Reliability / Performance / Device Matrix   CLOSED / VERIFIED / MERGED
G7  Release / Beta / Store Readiness            IN PROGRESS
```

Branches / PRs:

```text
G2  feature/camera-film-preview
G3  feature/editor-gpu-production      PR #6 merged
G4  feature/editor-product-ux          PR #7 merged
G5  feature/editor-tone-controls       PR #8 merged
G6  feature/g6-reliability-matrix      PR #9 merged
G7  feature/g7-release-readiness       current
```

G6 merge commit:

```text
9106b15adbd78760ecfdac2041eed4fdfd98ff87
```

---

# 3. Closed milestone records

## G1 — Camera GPU Preview

Android uses Camera2 -> SurfaceTexture -> GLES and canonical Film LUT assets. iOS uses AVCaptureVideoDataOutput -> CVPixelBuffer -> Metal. Capture remains clean.

See:

```text
docs/G1_IOS_VERIFICATION.md
```

## G2 — Editor GPU Preview Foundation

Transaction contract:

```text
slider drag    -> GPU-only draft when supported
slider release -> Rust semantic commit
Apply/Discard  -> Rust checkpoint semantics
Undo/Redo      -> Rust history
Export         -> Rust full-resolution replay
```

See:

```text
docs/G2_FINAL_VERIFICATION.md
docs/G2_5_TRANSFORM_PREVIEW_CONTRACT.md
docs/G2_6_EDITOR_GPU_HARDENING.md
docs/EDITOR_DRAFT_COMPOSITION.md
```

## G3 — Production Rendering Pipeline

Unsupported operation order/composition falls back to Rust. Recorded Apple A13 evidence remains authoritative.

See:

```text
docs/G3_FINAL_VERIFICATION.md
docs/G3_DEVICE_VERIFICATION.md
```

## G4 — Product Editor UX / Session Workflow

Implemented recipe-derived state, Apply/Discard, Before, History, Undo/Redo, atomic recovery, back policy, and Rust full-resolution PNG/JPEG/WEBP export.

Current export does not re-attach original EXIF/metadata; do not claim metadata preservation.

See:

```text
docs/G4_PRODUCT_UX_VERIFICATION.md
```

## G5 — Editing Feature Completeness

Rust-authoritative additions include Tone, Color/WB bias, Vignette, deterministic Grain, Film Profile V1, profile creator/import/export, tone-zone curves and six-sector HSL.

GPU continuous preview remains enabled only for controls with verified faithful parity. Newer G5 controls remain Rust-on-release unless a parity-safe GPU path is separately verified.

See:

```text
docs/G5_EDITING_FEATURE_COMPLETENESS.md
docs/G5_TONE_CONTROLS.md
```

## G6 — Reliability / Performance / Device Matrix

Status: **CLOSED / VERIFIED / MERGED**.

Primary record:

```text
docs/G6_RELIABILITY_MATRIX.md
```

Recorded evidence includes:

- clean host baseline
- 12/24/48 MP host characterization
- 10/50/100-cycle physical soak on iPhone 11
- 15-minute / 420-cycle sustained workload
- deterministic failure injection
- physical/manual product and failure checks
- isolated verifier app/worktree that preserves the installed main app
- final G6 PR head CI green before merge

Do not invent unavailable Android/device-tier evidence beyond what G6 recorded.

---

# 4. Important current files

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

# 5. G7 — Release / Beta / Store Readiness — IN PROGRESS

Primary record:

```text
docs/G7_RELEASE_READINESS.md
```

Branch:

```text
feature/g7-release-readiness
```

G7 scope:

```text
G7.0 release baseline
G7.1 Android production build/signing/native packaging
G7.2 iOS production build/signing
G7.3 privacy/permissions/diagnostics
G7.4 CI/CD release gates
G7.5 internal beta distribution
G7.6 store metadata/readiness
G7.7 release-candidate physical smoke
```

Initial audit found Android `release` was signed with the debug keystore. G7 removes that behavior. Release builds are unsigned unless an explicit ignored `android/key.properties` supplies production signing material.

Current package version remains:

```text
0.1.0+1
```

Do not finalize v1.0.0 until signed internal-beta artifacts and RC smoke are verified.

---

# 6. Verification rules

1. Never claim a test/device/build/benchmark passed unless actually run or reported.
2. Keep recorded numeric evidence unchanged unless superseded by a new measured result.
3. Distinguish numeric parity, functional smoke, characterization, unsigned release build, signed beta build and store readiness.
4. Record device/OS/backend for new physical evidence where possible.
5. Rust remains authoritative even when GPU output looks correct.
6. Unsupported GPU composition fails closed rather than approximating order/semantics.
7. Do not create numeric GPU parity claims for G5 controls that currently use Rust on release.
8. Never treat debug signing as production signing.
9. Never commit signing keys/passwords/provisioning secrets.
10. Release diagnostics must not contain photo pixels or user image content.

---

# 7. Current next action

**G6 is merged. G7 is now the active milestone.**

Start here:

```text
1. continue on feature/g7-release-readiness
2. let CI validate the new Android release and iOS no-codesign release jobs
3. fix release-only compile/link/package failures without weakening architecture invariants
4. inspect Android APK native ABI contents and resolved SDK levels
5. verify iOS release bundle, deployment target and signing configuration
6. document secure Android/iOS signed-build procedures
7. audit privacy/permission manifests and store disclosures
8. produce signed Internal Testing / TestFlight builds
9. run G7.7 release-candidate physical smoke
```

Do not add unrelated editing features during G7 unless they are required to resolve a release blocker.

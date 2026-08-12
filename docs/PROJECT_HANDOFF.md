# PixelCraft Project Handoff

## Purpose

This is the canonical continuation document for PixelCraft.

When starting a new work session:

1. read this file first;
2. inspect `main`, the active PR, and its latest CI run;
3. continue from **Current next action**;
4. treat repository state and recorded CI/device evidence as authoritative over older chat history.

Recommended continuation prompt:

```text
อ่าน docs/PROJECT_HANDOFF.md ใน repo PixelCraft แล้วทำต่อจาก Current next action
```

Last architecture refresh in this document: **2026-08-12, during P3 / PR #17**.

---

# 1. Architecture invariants

Repository:

```text
dexter-cnx/PixelCraft
```

Runtime authority:

```text
Flutter        = UI / control / presentation plane
Rust           = authoritative image semantics / recipe / history / checkpoint / export
Metal          = iOS realtime GPU preview
OpenGL ES      = Android realtime camera preview
```

Hard contracts:

1. Rust owns committed edit semantics, history, checkpoints, recovery recipe, and full-resolution export.
2. GPU rendering is an interactive preview path only; it is never final-render authority.
3. Camera Film is preview-only; capture remains clean.
4. Live camera frame buffers never cross Dart MethodChannel or Flutter Rust Bridge.
5. Canonical Film/Creative LUT data is Rust-owned.
6. Native/GPU failure must fail closed to a valid Rust/product state.
7. Unsupported Rust operation order must fall back; never silently reorder operations to fit a GPU backend.
8. Film Profiles are reusable configuration data, not pixels or per-image Editor sessions.
9. Imported recipe fields must report exact / approximated / unsupported mappings; unsupported fields are not silently discarded.
10. New effects are defined and tested in Rust first. GPU support is optional and only added when semantics can be reproduced faithfully.

Canonical image flow:

```text
Camera / imported image
        ↓
clean source
        ↓
Flutter controls
        ↓
GPU preview where faithful
        ↓ gesture release / command
Rust semantic recipe/edit
        ↓
authoritative preview + history + checkpoint
        ↓
full-resolution Rust replay/export
```

---

# 2. Product milestone status

```text
G1  Camera GPU Preview                          CLOSED
G2  Editor GPU Preview Foundation               CLOSED / MERGED
G3  Production Rendering Pipeline               CLOSED / MERGED
G4  Product Editor UX / Session Workflow        CLOSED / MERGED
G5  Editing Feature Completeness                CLOSED / VERIFIED
G6  Reliability / Performance / Device Matrix   CLOSED / VERIFIED
G7  Release / Beta / Store Readiness            DEFERRED UNTIL PACKAGE EXTRACTION COMPLETES
```

G6 recorded both automated and physical-device validation. Manual physical checks were reported complete on 2026-08-12.

Existing G7 work is preserved in PR #10 (`feature/g7-release-readiness`) but was created before the package-architecture refactor. Do not merge it unchanged; rebase/recreate it after package extraction is complete and resolve moved paths.

---

# 3. Package architecture program

Target monorepo:

```text
PixelCraft/
├── lib/                         # app shell, UI, platform adapters, compatibility exports
├── rust/                        # authoritative Rust image engine
├── packages/
│   ├── pixelcraft_engine/       # Flutter/FRB/CargoKit integration for rust/
│   ├── pixelcraft_gpu/          # preview-only GPU/native runtime
│   ├── pixelcraft_editing/      # pure-Dart editing/configuration contracts
│   └── pixelcraft_film/         # pure-Dart Film Profile product orchestration
├── docs/
└── tool/
```

Current dependency direction:

```text
PixelCraft App
 ├── pixelcraft_film
 ├── pixelcraft_gpu
 ├── pixelcraft_editing
 └── pixelcraft_engine

pixelcraft_film
 └── pixelcraft_editing

pixelcraft_gpu
 └── pixelcraft_editing

pixelcraft_editing
 └── Dart SDK only

pixelcraft_engine
 └── repository rust/ crate through build integration
```

Rules:

- internal packages must never import `package:pixelcraft/...` app source;
- internal packages must not use relative imports escaping back into root `lib/`;
- `pixelcraft_editing` remains pure Dart and cannot depend on Flutter/Riverpod/GPU;
- `pixelcraft_film` remains pure Dart and cannot depend on Flutter, `dart:io`, `path_provider`, GPU, engine, or app source;
- `pixelcraft_gpu` may depend on `pixelcraft_editing`, never the reverse;
- package extraction must not create a second image-processing authority beside Rust.

CI enforcement lives in:

```text
tool/check_package_boundaries.sh
```

---

# 4. P0 — pixelcraft_engine — MERGED

PR:

```text
#11
branch: agent/p0-pixelcraft-engine-package
merged commit: dfcedc041a1809058be237b4363ee7e51b8a4794
```

P0 moved the Flutter Rust Bridge / CargoKit Flutter plugin integration from the former root `rust_builder/` layout into:

```text
packages/pixelcraft_engine/
```

The authoritative Rust crate remains:

```text
rust/
```

`pixelcraft_engine` owns build/integration glue, not image semantics.

Key docs:

```text
packages/pixelcraft_engine/README.md
packages/pixelcraft_engine/CODE_WALKTHROUGH.md
```

P0 CI included Flutter, Rust, GPU, golden, Android native packaging, and iOS native packaging validation.

---

# 5. P1 — pixelcraft_gpu — MERGED

PR:

```text
#12
branch: refactor/p1-pixelcraft-gpu-package
merged commit: b229af9e7281105e1b5f0809a01fda13e7266702
```

Package:

```text
packages/pixelcraft_gpu/
```

P1 moved app-independent GPU control/runtime code plus native preview implementation into the package.

Platform scope:

```text
Android
  Camera2 + OpenGL ES camera preview
  camera preview/control runtime
  no native editor GPU path today

iOS
  AVFoundation + Metal camera preview
  Metal editor GPU preview path
```

Do not claim Android editor GPU parity/path exists. Android Editor continues to use the valid Rust/product path until an Android editor backend is implemented and parity-verified.

LUT ownership remains split deliberately:

```text
LUT semantic/canonical authority = Rust
LUT asset packaging              = app build integration today
LUT runtime consumer             = pixelcraft_gpu
```

P1 physical smoke was reported PASS on both iOS and Android.

Key docs:

```text
packages/pixelcraft_gpu/README.md
packages/pixelcraft_gpu/CODE_WALKTHROUGH.md
```

---

# 6. P2 — pixelcraft_editing — MERGED

PR:

```text
#16
branch: refactor/p2-pixelcraft-editing-package
merged commit: 9b2444f4cfe81e6bb1bb34790b93f10d9ac45dbb
```

Package:

```text
packages/pixelcraft_editing/
```

Purpose: extract reusable pure-Dart editing/configuration contracts without moving pixel authority out of Rust.

Moved/shared domains include:

```text
EditGraphDocument
EditGraphNode
EditNodeType
EditMask
EditOverlay

EditorAdjustmentSpec semantic catalog
ranges / groups / units / neutral values / coreFilters

FilmProfileV1
FilmProfileOrigin
FilmProfileParameterSpec
FilmProfile import mapping report
applyFilmProfileToSessionRecipe()
```

Important policy split:

```text
pixelcraft_editing = adjustment semantics
app/GPU layer      = GPU preview capability policy
```

`gpuPreview` is intentionally not part of the pure semantic adjustment model.

Root compatibility files remain where needed so app call sites can migrate incrementally.

Key docs:

```text
packages/pixelcraft_editing/README.md
packages/pixelcraft_editing/CODE_WALKTHROUGH.md
```

P2 latest pre-merge CI was green, including package tests, root Flutter suites, Rust suites, GPU suites, golden tests, and native packaging.

---

# 7. P3 — pixelcraft_film — ACTIVE

PR:

```text
#17  P3: extract pixelcraft_film package
branch: refactor/p3-pixelcraft-film-package
base: main @ 9b2444f4cfe81e6bb1bb34790b93f10d9ac45dbb
```

Package:

```text
packages/pixelcraft_film/
```

Purpose: move reusable Film Profile product/domain orchestration out of Flutter screens while keeping Film/image semantics in `pixelcraft_editing` + Rust.

Current P3 package ownership:

```text
FilmProfileRepository
FilmProfileLibrary
FilmProfileImportService
FilmProfileImportResult
FilmProfileDraft
```

Current responsibilities:

```text
library load/save/delete/duplicate orchestration
PixelCraft profile JSON vs generic recipe classification
import result transport + mapping report propagation
creator draft initialization/default/reset/build behavior
```

Current app-owned adapters/UI intentionally remain:

```text
lib/core/film_profile_store.dart
  -> path_provider / dart:io filesystem adapter
  -> implements FilmProfileRepository

lib/ui/screens/film_profiles_screen.dart
lib/ui/screens/film_profile_creator_screen.dart
  -> Flutter presentation/navigation/dialog/clipboard concerns
```

The creator now delegates reusable draft behavior to `FilmProfileDraft` while UI retains text controllers, widgets, and ID generation.

Do not move the canonical base-Film/LUT inventory into `pixelcraft_film`. Canonical LUT data remains Rust-owned. A future Film catalog API should be sourced from the authoritative engine rather than duplicating LUT inventory in Dart.

Key docs:

```text
packages/pixelcraft_film/README.md
packages/pixelcraft_film/CODE_WALKTHROUGH.md
```

## P3 validation baseline

CI run #194 (`31596707857`) was reported and verified green before the FilmProfileDraft slice.

Run #194 passed:

```text
package dependency boundaries
FRB regeneration/committed bridge checks
Rust fmt / clippy / tests
G6 12 MP characterization
GPU LUT parity
pixelcraft_editing analyze + tests
pixelcraft_film analyze + tests
pixelcraft_gpu analyze + tests
root Flutter analyze
state tests
gpu plan/session tests
widget tests
Android native packaging smoke
Golden tests on macOS
iOS debug --no-codesign packaging smoke
wgpu core on Linux / macOS / Windows
```

The FilmProfileDraft/docs slice was added after run #194 and therefore requires a fresh green CI before P3 can be considered ready.

---

# 8. Film Profile authority chain

Film Profiles are reusable configuration, not rendered pixels.

Creation/import path:

```text
Flutter UI
   ↓
pixelcraft_film product orchestration
   ↓
pixelcraft_editing FilmProfileV1 / semantic mapping
```

Applying to an editor session:

```text
FilmProfileV1
   ↓
pixelcraft_editing deterministic recipe materializer
   ↓
restore rewritten recipe through Rust
   ↓
Rust-authoritative preview/history/checkpoint/recovery/export
```

Generic imported recipes must continue reporting:

```text
exact
approximated
unsupported
```

Never claim proprietary third-party processing is reproduced 1:1 unless independently verified.

---

# 9. Important current files

```text
App entry
  lib/main.dart

Editor shell
  lib/ui/screens/editor_screen.dart
  lib/ui/widgets/editor_tool_panel.dart

Editing compatibility/app policy
  lib/state/editor_controller.dart
  lib/state/editor_recipe_summary.dart
  lib/state/editor_adjustment_catalog.dart

Film app adapter/UI
  lib/core/film_profile_store.dart
  lib/ui/screens/film_profiles_screen.dart
  lib/ui/screens/film_profile_creator_screen.dart

Editing package
  packages/pixelcraft_editing/lib/pixelcraft_editing.dart
  packages/pixelcraft_editing/lib/src/edit_graph.dart
  packages/pixelcraft_editing/lib/src/editor_adjustment_catalog.dart
  packages/pixelcraft_editing/lib/src/film_profile_v1.dart
  packages/pixelcraft_editing/lib/src/film_profile_recipe.dart

Film package
  packages/pixelcraft_film/lib/pixelcraft_film.dart
  packages/pixelcraft_film/lib/src/film_profile_repository.dart
  packages/pixelcraft_film/lib/src/film_profile_library.dart
  packages/pixelcraft_film/lib/src/film_profile_import_service.dart
  packages/pixelcraft_film/lib/src/film_profile_draft.dart

GPU package
  packages/pixelcraft_gpu/

Engine integration package
  packages/pixelcraft_engine/

Rust authority
  rust/src/engine.rs
  rust/src/api.rs
  rust/src/filters.rs
  rust/src/advanced_filters.rs
  rust/src/film_profiles.rs
```

---

# 10. Verification rules

1. Never claim a CI/test/device/benchmark passed unless it was actually run or explicitly reported.
2. Keep historical numeric evidence unchanged unless superseded by a new measured result.
3. Distinguish numeric parity, functional smoke, packaging smoke, and characterization.
4. Rust remains authoritative even when GPU output appears correct.
5. Unsupported GPU composition fails closed rather than approximating operation order/semantics.
6. Package extraction must preserve behavior first; compatibility exports/adapters may remain temporarily.
7. Pure-Dart packages must stay independent of Flutter/platform APIs unless architecture is deliberately changed and documented.
8. Every new P3 code/docs slice requires CI on the latest PR head before marking the PR ready or merging.
9. Physical-device smoke is required when native/runtime behavior changes. Pure-Dart package-only changes do not automatically require a new physical smoke cycle.

---

# 11. Current next action

**P3 is ACTIVE in PR #17. P0/P1/P2 are merged. G6 is closed.**

Continue from the latest head of:

```text
refactor/p3-pixelcraft-film-package
```

Next steps:

```text
1. wait for / inspect CI triggered by the FilmProfileDraft + docs/handoff slice
2. fix any analyzer/test/package-boundary regression without weakening package boundaries
3. review remaining Film app code for reusable pure-Dart orchestration only
4. do not move Flutter UI, dart:io/path_provider storage, GPU behavior, or Rust LUT authority into pixelcraft_film
5. update PR #17 summary if the final P3 scope changes
6. when latest head is fully green, inspect review threads and resolve findings
7. mark PR #17 Ready for Review
8. merge PR #17 into main using the latest expected head SHA
9. after P3 merge, refresh root README/status if still stale and verify all package docs from main
10. then return to G7 release-readiness work by rebasing/recreating PR #10 over the post-P3 main and resolving moved paths
```

Expected post-P3 package graph:

```text
App
 ├── pixelcraft_film
 ├── pixelcraft_gpu
 ├── pixelcraft_editing
 └── pixelcraft_engine

pixelcraft_film -> pixelcraft_editing
pixelcraft_gpu  -> pixelcraft_editing
```

Do not start release-readiness integration from the old G7 branch until P3 is merged.

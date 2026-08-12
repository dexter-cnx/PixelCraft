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

Last architecture refresh: **2026-08-12, P3 finalization / PR #17**.

---

# 1. Architecture invariants

Repository:

```text
dexter-cnx/PixelCraft
```

Runtime authority:

```text
Flutter        = UI / control / presentation plane
Rust           = authoritative image semantics / recipe / history / checkpoint / recovery / export
Metal          = iOS realtime GPU preview
OpenGL ES      = Android realtime camera preview
```

Hard contracts:

1. Rust owns committed edit semantics, history, checkpoints, recovery recipe, and full-resolution export.
2. GPU rendering is interactive preview only; never final-render authority.
3. Camera Film is preview-only; capture remains clean.
4. Live camera frame buffers never cross Dart MethodChannel or Flutter Rust Bridge.
5. Canonical Film/Creative LUT data is Rust-owned.
6. Native/GPU failure fails closed to a valid Rust/product state.
7. Unsupported Rust operation order falls back; never silently reorder operations for a GPU backend.
8. Film Profiles are reusable configuration data, not pixels or per-image Editor sessions.
9. Imported recipe fields report exact / approximated / unsupported mappings; unsupported fields are not silently discarded.
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

# 2. Milestone status

```text
G1  Camera GPU Preview                          CLOSED
G2  Editor GPU Preview Foundation               CLOSED / MERGED
G3  Production Rendering Pipeline               CLOSED / MERGED
G4  Product Editor UX / Session Workflow        CLOSED / MERGED
G5  Editing Feature Completeness                CLOSED / VERIFIED
G6  Reliability / Performance / Device Matrix   CLOSED / VERIFIED

P0  pixelcraft_engine extraction                MERGED
P1  pixelcraft_gpu extraction                   MERGED
P2  pixelcraft_editing extraction               MERGED
P3  pixelcraft_film extraction                  ACTIVE — PR #17, implementation green

G7  Release / Beta / Store Readiness            DEFERRED UNTIL P3 MERGES
```

G6 recorded automated and physical-device validation. Manual physical checks were reported complete on 2026-08-12.

Existing G7 work remains preserved in PR #10 (`feature/g7-release-readiness`) but predates the package refactor. Do not merge it unchanged. Rebase/recreate it after P3 lands and resolve moved paths.

---

# 3. Package architecture

Current monorepo:

```text
PixelCraft/
├── lib/                         # app shell, UI, platform adapters, compatibility exports
├── rust/                        # authoritative Rust image engine
├── packages/
│   ├── pixelcraft_engine/       # FRB/CargoKit integration for rust/
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

pixelcraft_film -> pixelcraft_editing
pixelcraft_gpu  -> pixelcraft_editing

pixelcraft_editing -> Dart SDK only
pixelcraft_engine  -> repository rust/ crate through build integration
```

Rules:

- internal packages never import `package:pixelcraft/...` app source;
- internal packages never escape back into root `lib/` by relative import;
- `pixelcraft_editing` remains pure Dart and independent of Flutter/Riverpod/GPU/Film;
- `pixelcraft_film` remains pure Dart and independent of Flutter, `dart:io`, `path_provider`, GPU, engine, and app source;
- `pixelcraft_gpu` may depend on `pixelcraft_editing`, never the reverse;
- package extraction must not create a second image-processing authority beside Rust.

CI enforcement:

```text
tool/check_package_boundaries.sh
```

---

# 4. P0 — pixelcraft_engine — MERGED

```text
PR #11
branch: agent/p0-pixelcraft-engine-package
merge commit: dfcedc041a1809058be237b4363ee7e51b8a4794
```

Package:

```text
packages/pixelcraft_engine/
```

P0 moved Flutter Rust Bridge / CargoKit integration out of the former root `rust_builder/` layout. The authoritative Rust crate remains:

```text
rust/
```

`pixelcraft_engine` owns integration/build glue, not image semantics.

Docs:

```text
packages/pixelcraft_engine/README.md
packages/pixelcraft_engine/CODE_WALKTHROUGH.md
```

---

# 5. P1 — pixelcraft_gpu — MERGED

```text
PR #12
branch: refactor/p1-pixelcraft-gpu-package
merge commit: b229af9e7281105e1b5f0809a01fda13e7266702
```

Package:

```text
packages/pixelcraft_gpu/
```

Platform scope:

```text
Android
  Camera2 + OpenGL ES camera preview
  no native Editor GPU channel/view today

iOS
  AVFoundation + Metal camera preview
  Metal Editor GPU preview
```

Do not claim Android Editor GPU parity exists.

LUT ownership:

```text
canonical LUT semantics = Rust
asset packaging         = app build integration
runtime consumer        = pixelcraft_gpu
```

P1 physical smoke was reported PASS on both iOS and Android.

Docs:

```text
packages/pixelcraft_gpu/README.md
packages/pixelcraft_gpu/CODE_WALKTHROUGH.md
```

---

# 6. P2 — pixelcraft_editing — MERGED

```text
PR #16
branch: refactor/p2-pixelcraft-editing-package
merge commit: 9b2444f4cfe81e6bb1bb34790b93f10d9ac45dbb
```

Package:

```text
packages/pixelcraft_editing/
```

Reusable pure-Dart domains include:

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
FilmProfileImportReport
applyFilmProfileToSessionRecipe()
```

Policy split:

```text
pixelcraft_editing = adjustment/profile configuration semantics
app/GPU layer      = backend capability policy
Rust               = committed image authority
```

`gpuPreview` is intentionally not part of the pure semantic adjustment model.

Docs:

```text
packages/pixelcraft_editing/README.md
packages/pixelcraft_editing/CODE_WALKTHROUGH.md
```

---

# 7. P3 — pixelcraft_film — ACTIVE / FINALIZATION

```text
PR #17  P3: extract pixelcraft_film package
branch: refactor/p3-pixelcraft-film-package
base main at P2 merge commit: 9b2444f4cfe81e6bb1bb34790b93f10d9ac45dbb
```

Package:

```text
packages/pixelcraft_film/
```

Purpose: move reusable Film Profile product/domain orchestration out of Flutter screens without moving LUT or pixel authority out of Rust.

Current package ownership:

```text
FilmProfileRepository
FilmProfileLibrary
FilmProfileImportService
FilmProfileImportResult
FilmProfileDraft
```

Responsibilities:

```text
library load/save/delete/duplicate orchestration
PixelCraft profile JSON vs generic recipe classification
import result transport + mapping report propagation
creator defaults / neutral initialization / clamp / reset
name/description/tag normalization
deterministic FilmProfileV1 composition
```

App-owned concerns intentionally remain:

```text
lib/core/film_profile_store.dart
  -> dart:io + path_provider filesystem adapter
  -> implements FilmProfileRepository

lib/ui/screens/film_profiles_screen.dart
lib/ui/screens/film_profile_creator_screen.dart
  -> Flutter widgets/navigation/dialog/clipboard/controllers
  -> time-based ID generation
```

Do not move canonical built-in Film/LUT inventory into `pixelcraft_film`. The source of truth remains Rust.

Docs:

```text
packages/pixelcraft_film/README.md
packages/pixelcraft_film/CODE_WALKTHROUGH.md
```

---

# 8. P3 verification state

Latest fully verified implementation HEAD before final documentation-only commits:

```text
HEAD: cbd70e509018eed1842c162e85b463662e0905f4
CI run #202
GitHub Actions run id: 31598466536
conclusion: SUCCESS
```

Run #202 is the current evidence that P3 code is green before documentation finalization.

Full CI coverage includes:

```text
package dependency boundaries
FRB regeneration / committed bridge checks
Rust fmt / clippy / tests
G6 12 MP characterization
GPU LUT parity
pixelcraft_editing analyze + tests
pixelcraft_film analyze + tests
pixelcraft_gpu analyze + tests
root Flutter analyze
state tests
GPU plan/session tests
widget tests
Android native packaging smoke
Golden tests on macOS
iOS debug --no-codesign packaging smoke
wgpu core Linux / macOS / Windows
```

The final documentation commits after `cbd70e5...` must receive a fresh green CI before PR #17 is marked Ready or merged.

No new physical-device smoke is required solely for these pure-Dart/docs P3 finalization changes because native runtime behavior did not change.

---

# 9. Film Profile authority chain

Creation/import:

```text
Flutter UI
   ↓
pixelcraft_film product orchestration
   ↓
pixelcraft_editing FilmProfileV1 / mapping semantics
```

Applying to an Editor session:

```text
FilmProfileV1
   ↓
pixelcraft_editing deterministic recipe materializer
   ↓
restore rewritten recipe through Rust
   ↓
Rust-authoritative preview/history/checkpoint/recovery/export
```

Generic imported recipes continue reporting:

```text
exact
approximated
unsupported
```

Never claim proprietary third-party processing is reproduced 1:1 unless separately verified.

---

# 10. Important current files

```text
App entry
  lib/main.dart

Editor
  lib/ui/screens/editor_screen.dart
  lib/ui/widgets/editor_tool_panel.dart
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
  rust/src/api.rs
  rust/src/engine.rs
  rust/src/filters.rs
  rust/src/advanced_filters.rs
  rust/src/film_profiles.rs
```

---

# 11. Verification rules

1. Never claim a CI/test/device/benchmark passed unless actually run or explicitly reported.
2. Distinguish numeric parity, functional smoke, packaging smoke, and characterization.
3. Rust remains authoritative even when GPU output appears correct.
4. Unsupported GPU composition fails closed rather than approximating operation order/semantics.
5. Package extraction preserves behavior first; compatibility exports/adapters may remain temporarily.
6. Pure-Dart packages stay independent of Flutter/platform APIs unless the architecture is deliberately changed and documented.
7. Every new P3 code/docs slice requires CI on the latest PR head before Ready/merge.
8. Physical-device smoke is required when native/runtime behavior changes; pure-Dart/docs-only changes do not automatically require a new device cycle.
9. Merge PRs using the current expected head SHA.

---

# 12. Current next action

**P3 implementation is green and is in final documentation/review state.**

Current branch / PR:

```text
refactor/p3-pixelcraft-film-package
PR #17
```

Next steps:

```text
1. wait for the full CI run triggered by the final README / CODE_WALKTHROUGH / PROJECT_HANDOFF commits
2. if green, inspect PR #17 review threads and review submissions
3. fix any review finding without weakening package boundaries or Rust authority
4. mark PR #17 Ready for Review
5. merge PR #17 using the latest expected head SHA
6. verify post-merge main contains the P0/P1/P2/P3 package graph and current docs
7. then return to G7 release readiness
8. rebase/recreate preserved PR #10 work over post-P3 main; do not merge the old branch unchanged
```

Expected post-P3 graph:

```text
App
 ├── pixelcraft_film
 ├── pixelcraft_gpu
 ├── pixelcraft_editing
 └── pixelcraft_engine

pixelcraft_film -> pixelcraft_editing
pixelcraft_gpu  -> pixelcraft_editing
```

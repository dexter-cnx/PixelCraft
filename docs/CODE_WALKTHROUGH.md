# PixelCraft Code Walkthrough

เอกสารนี้อธิบาย architecture ปัจจุบันของ PixelCraft หลัง G6 และ package extraction P0–P3

สถานะ ณ 2026-08-12:

```text
G1  Camera GPU Preview                          CLOSED
G2  Editor GPU Preview Foundation               CLOSED / MERGED
G3  Production Rendering Pipeline               CLOSED / MERGED
G4  Product Editor UX / Session Workflow        CLOSED / MERGED
G5  Editing Feature Completeness                CLOSED / VERIFIED
G6  Reliability / Performance / Device Matrix   CLOSED / VERIFIED

P0  pixelcraft_engine package extraction        MERGED
P1  pixelcraft_gpu package extraction           MERGED
P2  pixelcraft_editing package extraction       MERGED
P3  pixelcraft_film package extraction          FINALIZATION — PR #17
G7  Release / Beta / Store Readiness            DEFERRED UNTIL P3 MERGES
```

Latest verified P3 implementation baseline before final documentation commits:

```text
HEAD: cbd70e509018eed1842c162e85b463662e0905f4
CI run #202
GitHub Actions run id: 31598466536
conclusion: SUCCESS
```

> Rust เป็น authoritative source สำหรับ committed semantic edits, recipe, history, checkpoint, recovery และ full-resolution export. Flutter เป็น product/control/presentation plane. Native GPU เป็น faithful low-latency preview path เท่านั้น

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
Rust semantic edit / recipe
        ↓
authoritative reduced preview + history + checkpoint
        ↓
full-resolution Rust replay/export
```

Hard contracts:

1. Rust owns committed edit semantics, history, checkpoints, recovery recipe, and export.
2. GPU preview never becomes final-render source of truth.
3. Camera Film is preview-only; capture source remains clean.
4. Live camera frames never cross Dart MethodChannel or Flutter Rust Bridge.
5. Canonical Film/Creative LUT data remains Rust-owned.
6. Unsupported GPU order or native failure falls back to valid Rust/product state.
7. Flutter presentation state must not become a parallel semantic recipe.
8. Film Profiles are reusable configuration, not Editor session state or captured pixels.
9. Imported recipe fields report exact / approximated / unsupported mappings explicitly.
10. New effects are defined and tested in Rust first; GPU support is optional and only enabled when faithful.

---

# 2. Package graph after P3

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

Repository layout:

```text
PixelCraft/
├── lib/                          # app UI / state / adapters / compatibility exports
├── rust/                         # authoritative image engine
├── packages/
│   ├── pixelcraft_engine/
│   ├── pixelcraft_gpu/
│   ├── pixelcraft_editing/
│   └── pixelcraft_film/
├── android/
├── ios/
├── test/
├── tool/
└── docs/
```

Forbidden package directions are enforced by:

```text
tool/check_package_boundaries.sh
```

Key rules:

```text
packages/* must not import package:pixelcraft/...
pixelcraft_editing must remain pure Dart
pixelcraft_film must remain pure Dart
pixelcraft_film must not import Flutter / dart:io / path_provider / GPU / engine
pixelcraft_editing must not depend on pixelcraft_film
```

---

# 3. App startup

Entry point:

```text
lib/main.dart
```

Conceptual flow:

```text
WidgetsFlutterBinding
 -> platform/orientation/error setup
 -> ProviderScope
 -> RustBootstrapScreen
 -> initializeRustBridge()
 -> HomeScreen
```

Home:

```text
lib/ui/screens/home_screen.dart
```

Editor can start from camera, gallery, bundled sample, or saved recovery state.

---

# 4. Rust authority and pixelcraft_engine

`packages/pixelcraft_engine` is the Flutter FFI/build integration package around the root Rust crate.

```text
Flutter app
   ↓
pixelcraft_engine
   ↓ FRB / CargoKit
rust/
```

Important Rust files:

```text
rust/src/api.rs
rust/src/engine.rs
rust/src/filters.rs
rust/src/advanced_filters.rs
rust/src/film_profiles.rs
```

Rust retains the authoritative state for:

```text
untouched source
reduced preview
Apply checkpoint preview
semantic operations
cursor
checkpoint_cursor
undo / redo
recovery recipe
full-resolution replay/export
```

Recipe concept:

```text
operations = [ ... semantic edits ... ]
cursor
checkpoint_cursor
```

Active draft:

```text
operations[checkpoint_cursor .. cursor]
```

P0 moved FRB/CargoKit integration under `packages/pixelcraft_engine/`; the authoritative engine remains `rust/`.

---

# 5. FRB / CargoKit flow

```text
rust/src/api.rs
   ↓
flutter_rust_bridge_codegen
   ↓
generated Dart + Rust bridge
   ↓
pixelcraft_engine
   ↓
CargoKit
   ↓
platform-native Rust artifact
```

Useful commands:

```bash
make codegen
make integrate
make repair
make verify-native
```

---

# 6. pixelcraft_editing after P2

Package:

```text
packages/pixelcraft_editing/
```

Reusable pure-Dart contracts include:

```text
EditGraphDocument
EditGraphNode
EditNodeType
EditMask
EditOverlay

EditorAdjustmentSpec
semantic ranges / groups / units / neutral values
coreFilters

FilmProfileV1
FilmProfileOrigin
FilmProfileParameterSpec
FilmProfileImportReport
applyFilmProfileToSessionRecipe()
```

Responsibility split:

```text
pixelcraft_editing = editing/profile configuration semantics
app/GPU layer      = backend capability policy
Rust               = committed image authority
```

`gpuPreview` is intentionally not part of the pure semantic adjustment model.

App-side capability adapter:

```text
lib/state/editor_adjustment_catalog.dart
```

---

# 7. EditorController transaction

Primary controller:

```text
lib/state/editor_controller.dart
```

Typical adjustment flow:

```text
slider drag
  -> temporary GPU preview when faithfully supported

slider release
  -> semantic commit/replace
  -> Rust authoritative preview
  -> recovery persistence
```

Tool switching does not implicitly Apply or Discard the active draft.

---

# 8. pixelcraft_gpu after P1/P2

Package:

```text
packages/pixelcraft_gpu/
```

Owns preview-only infrastructure:

- Dart GPU transport/session/render-plan code
- native camera control bridges
- Android Camera2/OpenGL ES camera runtime
- iOS AVFoundation/Metal camera runtime
- iOS native Editor GPU path
- plugin registration
- diagnostics/frame pacing

It does not own committed semantics or export pixels.

Platform scope:

```text
Android
  Camera2/OpenGL ES camera preview
  no native Editor GPU channel/view today

iOS
  AVFoundation/Metal camera preview
  Metal Editor GPU preview
```

Unsupported render plans fail closed to the valid Rust preview. No silent semantic reordering is allowed.

---

# 9. Native GPU paths

Android camera:

```text
Camera2
 -> SurfaceTexture / external OES texture
 -> OpenGL ES Film LUT
 -> Flutter PlatformView
```

iOS camera:

```text
AVCaptureVideoDataOutput
 -> CVPixelBuffer
 -> CVMetalTextureCache
 -> Metal Film LUT
 -> Flutter PlatformView
```

Live processed frame buffers stay native. Capture remains clean.

---

# 10. LUT authority

Canonical Film data remains Rust-owned:

```text
rust/film_profiles/*/look.json
```

Build/runtime relationship:

```text
Rust canonical data
 -> canonical 33^3 LUT
      ├── Rust renderer
      └── generated native GPU assets
             ↓
        pixelcraft_gpu runtime consumer
```

Ownership:

```text
LUT semantic/canonical authority = Rust
LUT asset packaging              = app build integration
LUT runtime consumer             = pixelcraft_gpu
```

Do not create a second canonical built-in Film inventory in `pixelcraft_film`.

---

# 11. FilmProfileV1

Owned by `pixelcraft_editing`:

```text
packages/pixelcraft_editing/lib/src/film_profile_v1.dart
```

A Film Profile contains reusable configuration:

- id / name / description
- origin
- optional base Film id
- base strength
- normalized parameter map
- tags
- schema / engine compatibility

It does not contain source pixels, crop/rotate state, Editor history, checkpoint state, or captured GPU output.

---

# 12. pixelcraft_film after P3

Package:

```text
packages/pixelcraft_film/
```

This is a pure-Dart Film Profile product/domain orchestration package above `pixelcraft_editing`.

It owns:

```text
FilmProfileRepository
FilmProfileLibrary
FilmProfileImportService
FilmProfileImportResult
FilmProfileDraft
```

It does not own:

```text
canonical LUT data
pixel processing
Rust filter semantics
GPU preview
Flutter widgets/navigation
filesystem/path_provider implementation
Editor history/checkpoints
```

---

# 13. Film library flow

```text
Flutter UI pasted source
   ↓
FilmProfileLibrary.importSource
   ↓
FilmProfileImportService.parse
   ├─ PixelCraft schema -> FilmProfileV1.decode -> imported origin
   └─ generic object    -> pixelcraft_editing.importRecipeMap
                           -> profile + mapping report
   ↓
FilmProfileRepository.save
   ↓
UI refreshes + renders optional report
```

Import mapping remains explicit:

```text
exact
approximated
unsupported
```

Unsupported source fields are not silently discarded.

---

# 14. Film creator flow

`FilmProfileCreatorScreen` remains Flutter presentation while reusable creator semantics live in `FilmProfileDraft`.

Actual draft API:

```text
FilmProfileDraft.fromProfile(profile?)
parameterValue(id)
withParameter(id, value)
resetParameter(id)
copyWith(...)
toProfile(newId: ...)
FilmProfileDraft.parseTags(source)
```

Conceptual flow:

```text
FilmProfileV1? initial profile
        ↓
FilmProfileDraft.fromProfile
        ↓
all Film parameter slots populated
missing parameter -> semantic neutral
        ↓
slider change -> withParameter(id, value) -> clamp via pixelcraft_editing spec
reset         -> resetParameter(id)       -> semantic neutral
        ↓
UI metadata -> copyWith(name / description / tags / base Film / strength)
        ↓
toProfile(newId: generatedByApp)
        ↓
FilmProfileLibrary.save
        ↓
FilmProfileRepository
```

The app generates IDs so package behavior stays deterministic in tests.

---

# 15. Film persistence adapter

Current platform storage remains app-owned:

```text
lib/core/film_profile_store.dart
```

It implements `FilmProfileRepository` and uses:

```text
dart:io
path_provider
atomic temp-file replacement
```

This keeps `pixelcraft_film` pure Dart and leaves storage replaceable.

---

# 16. Film authority chain

Creation/import:

```text
Flutter UI
   ↓
pixelcraft_film product orchestration
   ↓
pixelcraft_editing configuration/mapping semantics
```

Applying a profile:

```text
FilmProfileV1
   ↓
pixelcraft_editing recipe materializer
   ↓
restore rewritten recipe through Rust
   ↓
Rust-authoritative preview/history/checkpoint/recovery/export
```

Third-party recipe imports may be approximated; do not claim vendor processing is reproduced 1:1 unless separately verified.

---

# 17. Recovery and export

Recovery implementation:

```text
lib/core/editor_session_store.dart
```

Exit with active draft remains explicit:

```text
Continue Editing
Discard
Apply & Exit
```

Export always starts from the untouched original and Rust recipe replay:

```text
untouched source
 -> Rust decode
 -> replay active recipe
 -> encode output
 -> gallery / backup / share
```

GPU preview pixels are never export input.

---

# 18. Verification

Package boundary:

```bash
bash tool/check_package_boundaries.sh
```

Editing package:

```bash
cd packages/pixelcraft_editing
dart pub get
dart analyze
dart test
```

Film package:

```bash
cd packages/pixelcraft_film
dart pub get
dart analyze
dart test
```

GPU package:

```bash
cd packages/pixelcraft_gpu
flutter pub get
flutter analyze
flutter test
```

Rust:

```bash
cargo fmt --manifest-path rust/Cargo.toml --all -- --check
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
```

Other gates:

```bash
make gpu-lut-verify
make verify-native
flutter analyze
flutter test
```

CI covers:

```text
package boundaries
FRB regeneration / generated bridge checks
Rust fmt / clippy / tests
G6 12 MP characterization
GPU LUT parity
editing package analyze/tests
film package analyze/tests
GPU package analyze/tests
root Flutter analyze/state/GPU/widget tests
Android native packaging smoke
Golden tests
iOS no-codesign packaging smoke
wgpu core Linux/macOS/Windows
```

Latest verified implementation baseline before final docs:

```text
run #202 / 31598466536 — SUCCESS
```

Pure-Dart/docs-only P3 finalization does not require a new physical-device smoke cycle because native runtime behavior did not change.

---

# 19. Important files

```text
App
  lib/main.dart
  lib/ui/screens/home_screen.dart

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

Engine package
  packages/pixelcraft_engine/

Rust authority
  rust/src/api.rs
  rust/src/engine.rs
  rust/src/filters.rs
  rust/src/advanced_filters.rs
  rust/src/film_profiles.rs
```

---

# 20. Continuation point

P0/P1/P2 are merged. P3 is in finalization on PR #17.

After the final README / walkthrough / handoff commits:

```text
1. require fresh green CI on latest PR #17 HEAD
2. inspect review threads/submissions
3. resolve findings without weakening package boundaries or Rust authority
4. mark PR #17 Ready for Review
5. merge with latest expected head SHA
6. verify post-merge main
7. return to G7 by rebasing/recreating preserved PR #10 work over post-P3 main
```

Do not merge the old pre-refactor G7 branch unchanged.

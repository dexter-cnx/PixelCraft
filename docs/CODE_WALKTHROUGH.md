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
P3  pixelcraft_film package extraction          ACTIVE — PR #17, implementation green
G7  Release / Beta / Store Readiness            DEFERRED UNTIL P3 MERGES
```

Latest verified P3 implementation baseline before this documentation-only finalization:

```text
CI run #202
GitHub Actions run: 31598466536
HEAD: cbd70e509018eed1842c162e85b463662e0905f4
conclusion: success
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

# 2. Monorepo package boundary after P3

```text
PixelCraft/
├── lib/                          # app UI / state / adapters / compatibility exports
├── rust/                         # authoritative image engine
├── packages/
│   ├── pixelcraft_engine/        # FRB/CargoKit integration for rust/
│   ├── pixelcraft_gpu/           # preview-only GPU/native runtime
│   ├── pixelcraft_editing/       # pure-Dart editing/configuration contracts
│   └── pixelcraft_film/          # pure-Dart Film Profile product orchestration
├── android/
├── ios/
├── test/
├── tool/
└── docs/
```

Dependency direction:

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

Forbidden directions:

```text
packages/* -> package:pixelcraft/...
pixelcraft_editing -> Flutter / Riverpod / GPU / Film
pixelcraft_film -> Flutter / dart:io / path_provider / GPU / engine / app
pixelcraft_editing -> pixelcraft_film
```

The guard is enforced by:

```text
tool/check_package_boundaries.sh
```

Detailed package walkthroughs:

```text
packages/pixelcraft_engine/CODE_WALKTHROUGH.md
packages/pixelcraft_gpu/CODE_WALKTHROUGH.md
packages/pixelcraft_editing/CODE_WALKTHROUGH.md
packages/pixelcraft_film/CODE_WALKTHROUGH.md
```

---

# 3. App startup and Home

Entry point:

```text
lib/main.dart
```

Startup flow:

```text
WidgetsFlutterBinding
 -> orientation / platform setup
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

Editor entry sources include Film Camera, system camera, gallery, bundled sample, and saved recovery sessions.

Recovery remains explicit:

```text
Resume last edit
[Discard] [Resume]
```

Resume passes stored source plus the authoritative recipe into `EditorScreen`.

---

# 4. pixelcraft_engine and Rust authority

`packages/pixelcraft_engine` is the Flutter FFI/build integration package around the root Rust crate. It is not a second semantic engine.

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

Rust retains:

- untouched source bytes
- reduced Editor preview
- Apply checkpoint preview
- complete semantic operation list
- cursor
- checkpoint cursor
- undo/redo state
- authoritative replay/export semantics

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

Full-resolution replay is deferred to export.

P0 moved Flutter/FRB/CargoKit integration under:

```text
packages/pixelcraft_engine/
```

while the authoritative crate intentionally remains:

```text
rust/
```

---

# 5. FRB / CargoKit flow

Conceptual flow:

```text
rust/src/api.rs
   ↓
flutter_rust_bridge_codegen
   ↓
generated Dart bridge + generated Rust bridge
   ↓
pixelcraft_engine native build integration
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

FRB can regenerate a conventional root `rust_builder/`. PixelCraft normalizes it back into `packages/pixelcraft_engine` using repository tooling.

---

# 6. pixelcraft_editing after P2

P2 moved reusable editing/configuration semantics into:

```text
packages/pixelcraft_editing/
```

The package is pure Dart and owns reusable contracts such as:

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

Important split:

```text
pixelcraft_editing = semantic adjustment/profile configuration
app/GPU layer      = renderer/backend capability policy
Rust               = committed pixel/edit authority
```

`gpuPreview` is therefore intentionally not part of the pure semantic `EditorAdjustmentSpec`.

The app compatibility/policy adapter remains:

```text
lib/state/editor_adjustment_catalog.dart
```

It can combine semantic metadata with current GPU rollout/capability information without polluting the package contract.

---

# 7. EditorController

Primary controller:

```text
lib/state/editor_controller.dart
```

It projects Rust state into Flutter presentation state:

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
  -> GPU-only draft preview when faithfully representable

slider release
  -> EditorController commits semantic value
  -> Rust commit/replace
  -> authoritative Rust preview
  -> recovery persistence
```

Tool switching does not Apply or Discard the active draft implicitly.

---

# 8. pixelcraft_gpu after P1/P2

`packages/pixelcraft_gpu` owns app-independent preview runtime and now consumes pure edit graph/configuration contracts from `pixelcraft_editing` where required.

It contains:

- Dart GPU transport/session/render-plan infrastructure
- native camera control bridges
- Android Camera2/OpenGL ES camera runtime
- iOS AVFoundation/Metal camera runtime
- iOS native Editor GPU path
- plugin registration
- diagnostics / frame pacing

It does not own committed edit semantics or export pixels.

Conceptual dependency:

```text
Flutter app
   ↓ preview intent
pixelcraft_gpu
   ↓
Metal / OpenGL ES

Flutter app
   ↓ semantic commit
Rust
```

Platform scope remains intentionally asymmetric:

```text
Android
  Camera2/OpenGL ES camera preview
  no native Editor GPU channel/view today

iOS
  AVFoundation/Metal camera preview
  Metal Editor GPU preview
```

Do not claim Android Editor GPU parity until an Android implementation exists and is parity-verified.

---

# 9. Editor GPU render plan

Primary package concepts include:

```text
GpuEditorRenderPlan
GpuEditorDraftSession
GpuPreviewRenderer
GpuPreviewCapabilities
native preview bridge
renderer/session generation
```

A render plan is accepted only when operation order can be represented faithfully.

If an operation or ordering cannot be represented safely:

```text
GPU path rejected
   ↓
keep valid Rust preview
```

No silent semantic reordering is allowed.

---

# 10. GPU session lifecycle and invalidation

A preview session must not allow stale native work to override newer editor state.

Typical lifecycle:

```text
activate GPU draft
 -> native renderer active
 -> newer Editor state arrives
 -> generation advances
 -> stale work ignored
```

Important invalidation reasons include:

```text
Rust checkpoint changed
Editor entered busy state
active tool changed
renderer dropped
new activation superseded old activation
```

After gesture release, the authoritative Rust commit replaces temporary GPU-only visual state.

---

# 11. Android camera GPU path

Eligible path:

```text
Camera2
 -> SurfaceTexture / external OES texture
 -> OpenGL ES canonical Film LUT
 -> Flutter PlatformView
```

P1 moved production registration out of `MainActivity` and into `PixelcraftGpuPlugin`.

Camera capture remains clean. Dart receives a clean file path/control metadata, not live processed frame buffers.

---

# 12. iOS camera/editor GPU path

Eligible camera path:

```text
AVCaptureVideoDataOutput
 -> CVPixelBuffer
 -> CVMetalTextureCache
 -> Metal canonical Film LUT
 -> Flutter PlatformView
```

Production native GPU sources live under:

```text
packages/pixelcraft_gpu/ios/Classes/
```

P1 moved production GPU registration out of `AppDelegate` into the plugin registrar.

Runner compatibility stubs, where still required by the existing Xcode project references, are compatibility-only and must not contain production GPU implementation.

---

# 13. Canonical Film / Creative LUT architecture

Canonical Film data remains Rust-owned:

```text
rust/film_profiles/*/look.json
```

Build flow:

```text
Rust canonical data
 -> canonical 33^3 LUT
      ├── Rust renderer
      └── generated native GPU assets
             ↓
        pixelcraft_gpu runtime consumer
```

Ownership split:

```text
LUT semantic/canonical authority = Rust
LUT asset packaging              = app build integration
LUT runtime consumer             = pixelcraft_gpu
```

Current built-in Film IDs include:

```text
provia_inspired
velvia_inspired
astia_inspired
e100_inspired
ektar_inspired
chrome64_inspired
```

Do not duplicate this canonical inventory into `pixelcraft_film` as an independent source of truth.

---

# 14. FilmProfileV1 semantics

The canonical reusable Dart profile schema is owned by `pixelcraft_editing`:

```text
packages/pixelcraft_editing/lib/src/film_profile_v1.dart
```

Root compatibility export remains available where app migration still needs it.

A Film Profile stores reusable configuration such as:

- id / name / description
- origin
- optional base Film id
- base strength
- normalized parameter map
- tags
- schema / engine compatibility

It deliberately does not contain:

- source image
- crop/rotate state
- Editor history
- checkpoint cursor
- captured GPU pixels

Loading a Film Profile materializes normal semantic recipe operations and restores them through Rust.

---

# 15. pixelcraft_film after P3

P3 introduces:

```text
packages/pixelcraft_film/
```

This is a pure-Dart Film Profile product/domain orchestration package sitting above `pixelcraft_editing`.

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
LUT pixels
Rust filter semantics
final rendering/export
GPU preview
Flutter widgets/navigation
filesystem/path_provider implementation
Editor history/checkpoints
canonical built-in Film inventory
```

---

# 16. Film library flow

Before P3, `FilmProfilesScreen` decoded and classified imports itself.

After P3:

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
UI refreshes + renders optional mapping report
```

Mapping semantics remain:

```text
exact
approximated
unsupported
```

Unsupported source fields are retained in the report and are never silently discarded.

---

# 17. Film creator flow

`FilmProfileCreatorScreen` remains Flutter presentation, but reusable draft semantics moved into `FilmProfileDraft`.

Conceptual flow:

```text
initial FilmProfileV1?
   ↓
FilmProfileDraft.fromProfile / FilmProfileDraft.fresh
   ↓
semantic defaults from pixelcraft_editing
   ↓ user edits
setParameter / resetParameter / metadata changes
   ↓ Save
FilmProfileDraft.build(profileId)
   ↓
FilmProfileLibrary.save
   ↓
FilmProfileRepository
```

`FilmProfileDraft` owns reusable behavior such as:

- neutral-value initialization
- parameter clamping
- reset semantics
- name fallback/trim
- description trim
- comma-separated tag normalization
- deterministic `FilmProfileV1` composition

Flutter keeps:

- `TextEditingController`
- widgets
- navigation/dialogs
- save-progress state
- time-based ID generation

Keeping ID generation outside the package makes package tests deterministic.

---

# 18. Film persistence adapter

Current persistence implementation remains app-owned:

```text
lib/core/film_profile_store.dart
```

It implements:

```text
FilmProfileRepository
```

and uses:

```text
dart:io
path_provider
atomic temp-file replacement
```

This is intentionally outside `pixelcraft_film`, preserving a pure-Dart package and a replaceable platform-storage seam.

---

# 19. Film authority chain

Creation/import does not make Dart the pixel authority.

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

Third-party recipe imports may be semantically approximated; do not claim vendor processing is reproduced 1:1 unless separately verified.

---

# 20. Recovery / Exit / Export

Recovery:

```text
lib/core/editor_session_store.dart
```

Generation-based publishing stores source + recipe and writes the manifest last. Load validates coherence and can fall back from a corrupt newest generation to an older valid one.

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
 -> encode output
 -> gallery/app backup/share
```

Native GPU preview pixels are never export input.

---

# 21. Failure / fallback model

Native GPU is optional for correctness.

Fallback can happen for:

```text
protocol mismatch
backend unavailable
missing native assets
shader self-test failure
unsupported LUT capability
blacklisted GPU
renderer init failure
runtime renderer failure
unsupported edit order
```

All such cases fail closed to valid Rust/product state.

Rust/native engine packaging failures are build/integration failures and must fail CI visibly rather than silently changing semantic implementation.

---

# 22. Verification layers

Root / Flutter:

```bash
flutter analyze
flutter test
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

GPU LUT:

```bash
make gpu-lut-verify
```

Native packaging:

```bash
make verify-native
flutter build ios --debug --no-codesign
```

CI currently covers:

```text
package dependency boundaries
FRB regeneration + committed bridge checks
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
Golden tests
 iOS no-codesign packaging smoke
wgpu core Linux / macOS / Windows
```

Latest verified P3 implementation run before this docs finalization:

```text
#202 / 31598466536 — SUCCESS
```

Physical-device smoke is required when native/runtime behavior changes. Pure-Dart/docs-only P3 changes do not automatically require a new device smoke cycle.

---

# 23. Important current files

```text
Startup
  lib/main.dart

Home
  lib/ui/screens/home_screen.dart

Editor
  lib/ui/screens/editor_screen.dart
  lib/ui/widgets/editor_tool_panel.dart

Editor presentation/policy
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

Engine package
  packages/pixelcraft_engine/

GPU package
  packages/pixelcraft_gpu/

Rust authority
  rust/src/api.rs
  rust/src/engine.rs
  rust/src/filters.rs
  rust/src/advanced_filters.rs
  rust/src/film_profiles.rs
```

---

# 24. Current continuation point

G6 is **CLOSED / VERIFIED**.

P0, P1, and P2 are **MERGED**.

P3 implementation is complete enough for final review and its latest pre-final-doc implementation HEAD passed full CI in run #202.

Current branch / PR:

```text
refactor/p3-pixelcraft-film-package
PR #17
```

After this documentation finalization:

```text
1. require a fresh green CI on the latest docs head
2. inspect review threads
3. resolve any findings without weakening boundaries
4. mark PR #17 Ready for Review
5. merge using the latest expected head SHA
6. verify post-merge main documentation/package graph
7. return to G7 by rebasing/recreating the preserved PR #10 work over post-P3 main
```

Do not merge the old pre-refactor G7 branch unchanged.

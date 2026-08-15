# PixelCraft / Dextryx Pixels Code Walkthrough

เอกสารนี้อธิบาย architecture และ execution model ปัจจุบันของ repository **PixelCraft** ซึ่งเป็น source repository ของ product **Dextryx Pixels**.

สถานะ ณ **2026-08-15**:

```text
G1  Camera GPU Preview                          CLOSED
G2  Editor GPU Preview Foundation               CLOSED / MERGED
G3  Production Rendering Pipeline               CLOSED / MERGED
G4  Product Editor UX / Session Workflow        CLOSED / MERGED
G5  Editing Feature Completeness                CLOSED / VERIFIED
G6  Reliability / Performance / Device Matrix   CLOSED / VERIFIED

P0–P3 package extraction                        MERGED
G7A Release Engineering / Store Preparation     MERGED
G7B Store Account Integration / Beta Upload     DEFERRED INDEFINITELY / NOT SCHEDULED

Post-G7A Product / Editor UX                     ACTIVE
Dextryx Pixels user-facing identity              COMPLETE ON PR #29 BRANCH
PKG-01 dxtr_pixs_* package namespace             ACTIVE / PR #30 DRAFT
Dart 3.13 RecordUse optimization                 ROADMAP / PR #31
```

> Rust เป็น authoritative source สำหรับ committed semantic edits, recipe, history, checkpoint, recovery และ full-resolution export. Flutter เป็น product/control/presentation plane. Native GPU เป็น faithful low-latency preview path เท่านั้น

---

# 1. Product identity vs technical identity

Product identity:

```text
master brand: Dextryx
product: Dextryx Pixels
installed label: Dxtr Pixs
repository: PixelCraft
```

Current technical release identity remains:

```text
Android applicationId: dev.cnxdev.pixelcraft
iOS bundle id:        dev.cnxdev.pixelcraft
```

These are intentionally separate concerns.

Branding cleanup may update user-visible strings, but it must not casually rename:

```text
Rust crate names
native binary names
native channels/protocol IDs
persisted storage/schema names
applicationId / bundle id
historical evidence
repository name
```

---

# 2. Canonical architecture

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
6. Unsupported GPU order/native failure falls back to valid Rust/product state.
7. Flutter presentation state must not become a parallel semantic recipe.
8. Film Profiles are reusable configuration, not Editor session state or captured pixels.
9. Imported recipe fields report exact / approximated / unsupported mappings explicitly.
10. New effects are defined/tested in Rust first; GPU support is optional and only enabled when faithful.

---

# 3. Package graph

## Current package graph before PKG-01

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
├── lib/                          # app UI / state / adapters
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

`tool/check_package_boundaries.sh` enforces forbidden dependency directions.

## PKG-01 target

PR #30 is migrating the reusable Dart/Flutter package namespace to:

```text
pixelcraft_editing -> dxtr_pixs_editing
pixelcraft_engine  -> dxtr_pixs_engine
pixelcraft_film    -> dxtr_pixs_film
pixelcraft_gpu     -> dxtr_pixs_gpu
```

The migration applies to package directories, pubspec names, path dependencies, Dart imports, package tests, CI paths, and package-distribution metadata.

It deliberately does **not** imply native ABI migration. These remain unchanged unless separately approved:

```text
Rust crate pixelcraft_engine
libpixelcraft_engine.*
libpixelcraft_gpu_native.*
native channel/protocol identifiers
applicationId / bundle id
persisted storage/schema identifiers
```

---

# 4. App startup / product shell

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

The user-facing product title is **Dextryx Pixels** while the installed launcher label is **Dxtr Pixs**.

Editor can start from camera, gallery, bundled sample, or saved recovery state.

---

# 5. Rust authority / engine package

```text
Flutter app
   ↓
pixelcraft_engine / future dxtr_pixs_engine package boundary
   ↓ FRB / CargoKit
rust/
```

Rust owns:

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

Package extraction moved build/FFI integration into a reusable package boundary; semantic authority stayed in `rust/`.

Useful commands:

```bash
make codegen
make integrate
make repair
make verify-native
```

---

# 6. Editing contracts package

Current package: `pixelcraft_editing`

PKG-01 target: `dxtr_pixs_editing`

Pure-Dart reusable contracts include:

```text
EditGraphDocument / EditGraphNode / masks / overlays
EditorAdjustmentSpec + ranges/groups/units/neutrals
FilmProfileV1 / FilmProfileOrigin
FilmProfileImportReport
applyFilmProfileToSessionRecipe()
```

Responsibility split:

```text
editing package    = editing/profile configuration semantics
app/GPU layer      = backend capability policy
Rust               = committed image authority
```

---

# 7. Editor transaction model

Primary controller:

```text
lib/state/editor_controller.dart
```

Typical adjustment flow:

```text
slider drag
  -> temporary GPU preview when faithfully supported

slider release / exact numeric apply
  -> semantic commit/replace
  -> Rust authoritative preview
  -> recovery persistence
```

Post-G7A editor UX additions reuse this model rather than inventing new semantic paths.

Examples already merged:

```text
Before / After Compare
Zoom / Fit controls
precise numeric slider entry
histogram channel inspection
precise straighten angle entry
```

GPU failure or unsupported render order does not mutate semantic order; the UI falls back to Rust/product preview.

---

# 8. GPU package / native preview

Current package:

```text
packages/pixelcraft_gpu/
```

PKG-01 target:

```text
packages/dxtr_pixs_gpu/
```

Responsibilities:

- Dart GPU transport/session/render-plan code
- native camera control bridges
- Android Camera2/OpenGL ES camera runtime
- iOS AVFoundation/Metal camera runtime
- iOS native Editor GPU preview
- diagnostics/frame pacing

Platform scope:

```text
Android
  Camera2/OpenGL ES camera preview
  no native Editor GPU channel/view today

iOS
  AVFoundation/Metal camera preview
  Metal Editor GPU preview
```

Live frame buffers stay native.

---

# 9. LUT authority

Canonical Film data remains Rust-owned:

```text
rust/film_profiles/*/look.json
```

Flow:

```text
Rust canonical data
 -> canonical 33^3 LUT
      ├── Rust renderer
      └── generated native GPU assets
             ↓
        GPU package runtime consumer
```

Do not create a second canonical built-in Film inventory in the Film package.

---

# 10. Film package / Film Profile flow

Current package: `pixelcraft_film`

PKG-01 target: `dxtr_pixs_film`

This is a pure-Dart product/domain orchestration package above the editing package.

It owns:

```text
FilmProfileRepository
FilmProfileLibrary
FilmProfileImportService
FilmProfileImportResult
FilmProfileDraft
```

It does not own canonical LUT data, pixel processing, Rust filter semantics, GPU preview, Flutter widgets/navigation, platform filesystem implementation, or Editor history/checkpoints.

Import flow:

```text
Flutter UI source
   ↓
FilmProfileLibrary.importSource
   ↓
FilmProfileImportService.parse
   ├─ PixelCraft schema -> FilmProfileV1
   └─ generic object    -> editing importRecipeMap
                           -> profile + mapping report
   ↓
FilmProfileRepository.save
```

Mapping remains explicit:

```text
exact
approximated
unsupported
```

Creator flow:

```text
FilmProfileV1? initial
 -> FilmProfileDraft.fromProfile
 -> withParameter / resetParameter / copyWith
 -> toProfile(newId: generatedByApp)
 -> FilmProfileLibrary.save
 -> FilmProfileRepository
```

App filesystem adapter:

```text
lib/core/film_profile_store.dart
```

---

# 11. Recovery flow

Implementation:

```text
lib/core/editor_session_store.dart
```

Current persistence model:

```text
app-support/pixelcraft-session/
  source.<fingerprint>.bin
  recipe.<generation>.json
  generation.<generation>.json
```

This storage name is technical persisted state and is not changed by user-facing branding or PKG-01.

Generation manifest is the commit point pairing source + recipe. The store:

- retains at most 3 coherent generations;
- falls back to the previous coherent generation when the newest one is incomplete;
- prunes old unreferenced source/recipe payloads;
- removes abandoned `.tmp` files during load/save;
- `clear()` removes the entire recovery directory.

The recovery source bytes are local application state for resume, not telemetry or exported output.

---

# 12. Export / share flow

Implementation:

```text
lib/core/export_file_service.dart
```

Canonical export:

```text
untouched source
 -> Rust recipe replay
 -> encoded output bytes
 -> app documents
 -> gallery save when requested by product flow
 -> system share sheet only after explicit Share
```

User-facing share copy is now:

```text
Edited with Dextryx Pixels
```

`SharePlus` receives only the exported file and user-facing share text. GPU preview pixels are never the export input.

---

# 13. Diagnostics / privacy boundary

Current diagnostic UI is debug-oriented and reports renderer/profile/sample/error metrics. It does not log source image bytes or live camera frame buffers.

Current app dependency set has no analytics, advertising, or remote crash-reporting SDK. Therefore the audited app-owned flow has no automatic developer-operated image/telemetry upload path.

Privacy/store working evidence:

```text
docs/G7A_PRIVACY_STORE_DRAFTS.md
```

---

# 14. G7A Android release path

Config:

```text
android/app/build.gradle.kts
```

Release policy:

```text
no debug signing
optional ignored android/key.properties release keystore
first RC keeps current non-minified/no-R8 policy
```

Current release identity:

```text
applicationId: dev.cnxdev.pixelcraft
version: 0.1.0+1
minSdk: 24
targetSdk: 36
compileSdk: 36
ABIs: arm64-v8a / armeabi-v7a / x86_64
```

Permission intent:

```text
CAMERA
WRITE_EXTERNAL_STORAGE only through API 28
```

`RECORD_AUDIO` is removed because the Flutter fallback camera uses `enableAudio: false`.

---

# 15. G7A iOS release path

CI validates:

```bash
flutter build ios --release --no-codesign
```

Current identity:

```text
bundle id: dev.cnxdev.pixelcraft
deployment target: iOS 13.0
version/build: FLUTTER_BUILD_NAME / FLUTTER_BUILD_NUMBER
```

Usage descriptions cover Camera, Photo Library read/select, and Photo Library add/save.

Dependency Privacy Manifests are present in the release bundle. Do not invent app-owned required-reason declarations without evidence; re-audit the final signed archive if G7B is resumed.

---

# 16. CI / release gates

Release jobs sit alongside semantic/native validation:

```text
android-release
  -> flutter pub get
  -> FRB codegen
  -> flutter build apk --release
  -> verify native Rust library
  -> assert no debug signing
  -> upload APK

ios-release
  -> flutter pub get
  -> FRB codegen
  -> flutter build ios --release --no-codesign
  -> verify Runner.app/native output
  -> upload app bundle
```

The full matrix includes:

```text
package boundaries
Rust fmt/clippy/tests
editing package analyze/tests
film package analyze/tests
GPU package analyze/tests
Flutter analyze/state/GPU/widget tests
golden + iOS native packaging
Android release artifact
iOS release no-codesign
wgpu Linux/macOS/Windows
```

Unsigned/no-codesign output is packaging evidence only, not signed-store evidence.

---

# 17. Release identity / version policy

```text
brand/product: Dextryx / Dextryx Pixels
installed label: Dxtr Pixs
marketing version: 0.1.0 while pre-1.0 beta/RC work continues
current build number: 1
future signed external build numbers: monotonically increment every distributed build
Android applicationId: dev.cnxdev.pixelcraft
iOS bundle id: dev.cnxdev.pixelcraft
```

A Dextryx-specific application/bundle identifier migration is a separate future release migration, not part of branding or package namespace work.

---

# 18. G7A vs G7B

G7A account-independent release engineering is merged.

G7B is **deferred indefinitely / not scheduled**. It is not an active blocker.

If explicitly resumed, G7B owns:

```text
production signing
Play App Signing
signed AAB upload
Play Internal Testing
signed iOS archive upload
TestFlight
actual Data Safety/App Privacy submissions
store review/submission
signed RC physical-device smoke
```

---

# 19. UX modernization architecture guardrails

The next product direction is a modernized photography UX inspired by high-quality direct-manipulation interaction patterns, without changing image-authority rules.

Target qualities:

```text
image-first
precise
tactile
direct manipulation
continuous feedback
professional density
predictable gestures
fast perceived latency
```

Key surfaces:

```text
Camera
Film selector
Editor
precision parameter controls
Before / After
Film library
Film Profile detail
Create Film Profile
Save / export
```

Implementation rules:

1. prefer small reviewable slices over a full UI rewrite;
2. reuse existing `EditorController` and Rust commit paths;
3. keep UX-only work presentation-side unless semantics genuinely change;
4. continuous preview must preserve latest-value-wins and stale-result protection;
5. no new RAW/image-processing behavior should be smuggled into UX PRs;
6. focused interaction tests are required before merge.

---

# 20. Dart 3.13 RecordUse / native tree-shaking

PR #31 records a future optimization track for Dart 3.13 recorded native usage / `RecordUse`.

This is **not yet an implementation dependency**.

Planned validation sequence:

```text
confirm compatible Dart/Flutter toolchain
 -> capture native binary-size baseline
 -> PoC on GPU native library
 -> verify retained native symbols/runtime behavior
 -> measure release artifact delta
 -> expand only if benefit is real
```

Do not migrate away from Flutter Rust Bridge merely to adopt RecordUse. Any binding/runtime migration needs a separate technical justification.

---

# 21. Verification commands

```bash
bash tool/check_package_boundaries.sh
make gpu-lut-verify
make verify-native
flutter analyze
flutter test
```

Package-specific analyze/tests, Rust fmt/clippy/tests, native packaging, release packaging, and wgpu Linux/macOS/Windows remain mandatory CI gates where currently configured.

---

# 22. Important files

```text
Architecture / handoff
  README.md
  docs/PROJECT_HANDOFF.md
  docs/CODE_WALKTHROUGH.md

App/editor
  lib/main.dart
  lib/state/editor_controller.dart
  lib/ui/screens/home_screen.dart
  lib/ui/screens/editor_screen.dart
  lib/ui/widgets/editor_tool_panel.dart
  lib/ui/widgets/straighten_control.dart
  lib/ui/widgets/histogram_widget.dart

Recovery/export/privacy
  lib/core/editor_session_store.dart
  lib/core/export_file_service.dart
  lib/ui/screens/gpu_diagnostics_screen.dart

Packages
  packages/pixelcraft_engine/      # current before PKG-01 merge
  packages/pixelcraft_gpu/
  packages/pixelcraft_editing/
  packages/pixelcraft_film/

Rust authority
  rust/

Release
  docs/G7A_RELEASE_READINESS.md
  docs/G7A_ANDROID_SIGNING.md
  docs/G7A_PRIVACY_STORE_DRAFTS.md
  .github/workflows/ci.yml
  android/app/build.gradle.kts
  ios/Runner/Info.plist
```

---

# 23. Continuation point

The immediate continuation is not G7B and not new image-processing semantics.

Order of work:

```text
PR #29 branding cleanup
 -> make green and merge
 -> PR #30 PKG-01 retarget/rebase onto main
 -> make package/native matrix green and merge
 -> PR #31 roadmap docs merge when conflict-free/green
 -> resume small UX modernization slices
 -> later evaluate Dart 3.13 RecordUse using measured binary evidence
```

Always consult `docs/PROJECT_HANDOFF.md` for the exact current next action because it is the canonical execution queue; this walkthrough explains how the codebase is structured and which boundaries must remain intact.

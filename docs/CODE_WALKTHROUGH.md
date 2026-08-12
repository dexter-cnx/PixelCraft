# PixelCraft Code Walkthrough

เอกสารนี้อธิบาย architecture ปัจจุบันของ PixelCraft หลัง G6, package extraction P0–P3 และ G7A release engineering.

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
P3  pixelcraft_film package extraction          MERGED

G7A Release Engineering / Store Preparation     ACTIVE — FINALIZATION / PR #18
G7B Store Account Integration / Beta Upload     BLOCKED BY EXTERNAL ACCOUNTS
```

Latest verified implementation baseline before final documentation commits:

```text
HEAD: af94739cf546a518bcea1fb917c42cf9df2b6d23
CI run #216
GitHub Actions run id: 31609170884
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
6. Unsupported GPU order/native failure falls back to valid Rust/product state.
7. Flutter presentation state must not become a parallel semantic recipe.
8. Film Profiles are reusable configuration, not Editor session state or captured pixels.
9. Imported recipe fields report exact / approximated / unsupported mappings explicitly.
10. New effects are defined/tested in Rust first; GPU support is optional and only enabled when faithful.

---

# 2. Package graph

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

---

# 3. App startup / product shell

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

Editor can start from camera, gallery, bundled sample, or saved recovery state.

---

# 4. Rust authority / pixelcraft_engine

```text
Flutter app
   ↓
pixelcraft_engine
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

P0 moved build/FFI integration into `packages/pixelcraft_engine`; semantic authority stayed in `rust/`.

Useful commands:

```bash
make codegen
make integrate
make repair
make verify-native
```

---

# 5. pixelcraft_editing

Pure-Dart reusable contracts:

```text
EditGraphDocument / EditGraphNode / masks / overlays
EditorAdjustmentSpec + ranges/groups/units/neutrals
FilmProfileV1 / FilmProfileOrigin
FilmProfileImportReport
applyFilmProfileToSessionRecipe()
```

Responsibility split:

```text
pixelcraft_editing = editing/profile configuration semantics
app/GPU layer      = backend capability policy
Rust               = committed image authority
```

---

# 6. Editor transaction model

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

GPU failure or unsupported render order does not mutate semantic order; the UI falls back to Rust/product preview.

---

# 7. pixelcraft_gpu / native preview

Package:

```text
packages/pixelcraft_gpu/
```

Owns preview-only infrastructure:

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

# 8. LUT authority

Canonical Film data remains Rust-owned:

```text
rust/film_profiles/*/look.json
```

```text
Rust canonical data
 -> canonical 33^3 LUT
      ├── Rust renderer
      └── generated native GPU assets
             ↓
        pixelcraft_gpu runtime consumer
```

Do not create a second canonical built-in Film inventory in `pixelcraft_film`.

---

# 9. pixelcraft_film / Film Profile flow

`pixelcraft_film` is a pure-Dart product/domain orchestration package above `pixelcraft_editing`.

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
   └─ generic object    -> pixelcraft_editing.importRecipeMap
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

# 10. Recovery flow

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

Generation manifest is the commit point pairing source + recipe. The store:

- retains at most 3 coherent generations;
- falls back to the previous coherent generation when the newest one is incomplete;
- prunes old unreferenced source/recipe payloads;
- removes abandoned `.tmp` files during load/save;
- `clear()` removes the entire recovery directory.

The recovery source bytes are local application state for resume, not telemetry or exported output.

---

# 11. Export / share flow

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

`SharePlus` receives only the exported file and user-facing share text. GPU preview pixels are never the export input.

---

# 12. Diagnostics / privacy boundary

Current diagnostic UI is debug-oriented and reports renderer/profile/sample/error metrics. It does not log source image bytes or live camera frame buffers.

Current app dependency set has no analytics, advertising, or remote crash-reporting SDK. Therefore the audited app-owned flow has no automatic developer-operated image/telemetry upload path.

Privacy/store working evidence:

```text
docs/G7A_PRIVACY_STORE_DRAFTS.md
```

---

# 13. G7A Android release path

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

Current resolved release identity:

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

`RECORD_AUDIO` is removed from the merged app manifest because the Flutter fallback camera uses `enableAudio: false`. The run #214 APK verified the microphone permission is absent after the change.

---

# 14. G7A iOS release path

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

Dependency Privacy Manifests are present in the release bundle. PixelCraft currently has no app-owned `PrivacyInfo.xcprivacy`; G7A does not invent one without app-owned required-reason evidence. Re-audit the final signed archive in G7B.

---

# 15. G7A CI release gates

Current CI adds release jobs to existing semantic/native validation:

```text
android-release
  -> flutter pub get
  -> FRB codegen
  -> flutter build apk --release
  -> verify libpixelcraft_engine.so
  -> assert no debug signing
  -> upload APK

ios-release
  -> flutter pub get
  -> FRB codegen
  -> flutter build ios --release --no-codesign
  -> verify Runner.app/native output
  -> upload app bundle
```

Run #216 passed all jobs at:

```text
HEAD: af94739cf546a518bcea1fb917c42cf9df2b6d23
run id: 31609170884
```

Unsigned/no-codesign output is packaging evidence only, not signed-store evidence.

---

# 16. Release identity / version policy

```text
marketing version: 0.1.0 while pre-1.0 beta/RC work continues
current build number: 1
future signed external build numbers: monotonically increment every distributed build
Android applicationId: dev.cnxdev.pixelcraft
iOS bundle id: dev.cnxdev.pixelcraft
```

Actual signed distribution begins in G7B.

---

# 17. G7A vs G7B

G7A owns account-independent release engineering and preparation.

G7B is blocked until Apple Developer/App Store Connect and Google Play Console accounts exist. G7B will own:

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

# 18. PR #10 handling

Old PR #10 predates P0–P3 and is not the active G7 line.

After PR #18 merges:

```text
1. audit PR #10 file-by-file against post-G7A main
2. migrate any genuinely missing work
3. close PR #10 as superseded
4. keep branch feature/g7-release-readiness as historical reference
5. delete that branch only if the user explicitly asks
```

Do not merge/rebase PR #10 unchanged.

---

# 19. Verification commands

```bash
bash tool/check_package_boundaries.sh
make gpu-lut-verify
make verify-native
flutter analyze
flutter test
```

Package-specific analyze/tests remain part of CI for `pixelcraft_editing`, `pixelcraft_film`, and `pixelcraft_gpu`; Rust fmt/clippy/tests and wgpu Linux/macOS/Windows remain mandatory gates.

---

# 20. Important files

```text
Architecture / handoff
  README.md
  docs/PROJECT_HANDOFF.md
  docs/CODE_WALKTHROUGH.md

G7A
  docs/G7A_RELEASE_READINESS.md
  docs/G7A_ANDROID_SIGNING.md
  docs/G7A_PRIVACY_STORE_DRAFTS.md
  .github/workflows/ci.yml
  android/app/build.gradle.kts
  android/app/src/main/AndroidManifest.xml
  ios/Runner/Info.plist
  ios/Runner.xcodeproj/project.pbxproj

Recovery/export/privacy
  lib/core/editor_session_store.dart
  lib/core/export_file_service.dart
  lib/ui/screens/gpu_diagnostics_screen.dart

Packages
  packages/pixelcraft_engine/
  packages/pixelcraft_gpu/
  packages/pixelcraft_editing/
  packages/pixelcraft_film/

Rust authority
  rust/
```

---

# 21. Continuation point

P0–P3 are merged. G7A is in finalization on PR #18.

```text
1. require fresh green CI on the final documentation HEAD
2. inspect PR #18 review threads/submissions
3. if clear, mark PR #18 Ready for Review
4. merge with the latest expected head SHA when approved
5. verify post-merge main
6. audit PR #10 as described above
7. keep G7B blocked until Apple/Google accounts exist
```

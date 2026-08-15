# PixelCraft Project Handoff

## Purpose

This is the canonical continuation document for the PixelCraft repository and the **Dextryx Pixels** product.

When starting a new work session:

1. read this file first;
2. inspect `main`, active PRs, and latest CI runs;
3. continue from **Current next action**;
4. treat repository state and recorded CI/device evidence as authoritative over older chat history.

Recommended continuation prompt:

```text
อ่าน docs/PROJECT_HANDOFF.md ใน repo PixelCraft แล้วทำต่อจาก Current next action
```

Last refresh: **2026-08-15 — branding cleanup complete on PR #29 branch; package namespace migration and Dart 3.13 roadmap are active follow-up tracks; G7B deferred indefinitely.**

---

# 1. Product identity — USER-FACING MIGRATION COMPLETE

Identity decision frozen on 2026-08-15:

```text
master brand: Dextryx
product name: Dextryx Pixels
installed app label: Dxtr Pixs
short visual mark: DXTR PIXS or DXTR + pixel/film symbol
technical reusable-package namespace target: dxtr_pixs_*
repository name: PixelCraft (unchanged)
```

Migration rules:

1. Product-facing copy uses **Dextryx Pixels**.
2. Android/iOS launcher or home-screen display labels use **Dxtr Pixs**.
3. Privacy/permission copy uses **Dextryx Pixels**.
4. Historical evidence may retain `PixelCraft` / `Pixel Craft` when that was the literal build/product name at that time.
5. Android applicationId and iOS bundle id remain `dev.cnxdev.pixelcraft` until a deliberate identifier migration is approved and validated.
6. Do not rename the GitHub repository as part of branding.
7. Native ABI/runtime names, persisted storage/schema names, channels, Rust crate names, and binary names are separate technical migrations and must not be changed casually.

Primary identity PR:

```text
PR #27: Rename product identity to Dextryx Pixels
CI: run #267 / 31853404031 — SUCCESS
merge commit: 5f4ea1e3ba0b2e7e9983eb096109742ead0b1ea9
```

Focused user-facing cleanup on PR #29:

```text
lib/ui/screens/home_screen.dart
  AppBar title: "Dextryx Pixels"

lib/core/export_file_service.dart
  share text: "Edited with Dextryx Pixels"

lib/ui/screens/editor_screen.dart
  gallery-error copy: "Dextryx Pixels could not add it to the device gallery."
```

PR #29 intentionally does not change package names, native identifiers, bundle/application identifiers, or image semantics.

---

# 2. Architecture invariants

```text
Flutter   = UI / control / presentation plane
Rust      = authoritative image semantics / recipe / history / checkpoint / recovery / export
Metal     = iOS realtime GPU preview
OpenGL ES = Android realtime camera preview
```

Hard contracts:

1. Rust owns committed edit semantics, history, checkpoints, recovery recipe, and full-resolution export.
2. GPU rendering is interactive preview only; never final-render authority.
3. Camera Film is preview-only; capture remains clean.
4. Live camera buffers never cross Dart MethodChannel or Flutter Rust Bridge.
5. Canonical Film/Creative LUT data is Rust-owned.
6. Native/GPU failure fails closed to valid Rust/product state.
7. Unsupported Rust operation order falls back; never silently reorder operations for GPU.
8. Film Profiles are reusable configuration, not pixels or per-image sessions.
9. Imported recipe fields report exact / approximated / unsupported mappings.
10. New effects are defined/tested in Rust first; GPU support is enabled only when faithful.
11. UX modernization must reuse existing semantic commit paths unless a deliberate Rust-first semantic change is separately approved.

---

# 3. Milestone status

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
P3  pixelcraft_film extraction                  MERGED

G7A Release Engineering / Store Preparation     MERGED
G7B Store Account Integration / Beta Upload     DEFERRED INDEFINITELY / NOT SCHEDULED

Post-G7A Product / Editor UX                     ACTIVE
Dextryx Pixels user-facing identity              COMPLETE ON PR #29 BRANCH
PKG-01 dxtr_pixs_* package namespace             ACTIVE / PR #30 DRAFT
O1 Dart 3.13 RecordUse native tree-shaking       ROADMAP / PR #31
UX modernization / 60fps-inspired interaction   PLANNED NEXT PRODUCT TRACK
```

Historical G7 PR #10 is closed/superseded. Do not reopen or merge it.

---

# 4. Post-G7A product/editor work

Merged slices:

```text
PR #20  Editor: discoverable Before/After Compare UX
PR #21  Film library: search and origin filters
PR #22  Fix Compare session state and wide-layout placement
PR #23  Editor: discoverable Zoom / Fit controls
PR #24  Editor: precise numeric value entry for adjustment sliders
PR #25  Editor: histogram channel inspector
PR #26  Editor: precise straighten angle entry
PR #27  Product identity: Dextryx Pixels / Dxtr Pixs primary pass
PR #28  Refresh post-identity product handoff
```

PR #29 completes the remaining current user-facing legacy branding strings.

These slices are presentation/product workflow improvements. They do not transfer committed image authority away from Rust and do not make GPU preview authoritative.

---

# 5. Package graph — CURRENT AND TARGET

Current graph on `main` before PKG-01:

```text
PixelCraft repository app
 ├── pixelcraft_film
 ├── pixelcraft_gpu
 ├── pixelcraft_editing
 └── pixelcraft_engine

pixelcraft_film -> pixelcraft_editing
pixelcraft_gpu  -> pixelcraft_editing
pixelcraft_editing -> Dart SDK only
pixelcraft_engine  -> repository rust/ crate through build integration
```

PKG-01 target in PR #30:

```text
pixelcraft_editing -> dxtr_pixs_editing
pixelcraft_engine  -> dxtr_pixs_engine
pixelcraft_film    -> dxtr_pixs_film
pixelcraft_gpu     -> dxtr_pixs_gpu
```

PKG-01 covers package directories/pubspec names, Dart imports, path dependencies, package tests, CI paths, package-boundary rules, and native packaging paths where they are package-distribution metadata.

PKG-01 deliberately does **not** rename:

```text
Rust crate pixelcraft_engine
libpixelcraft_engine.*
libpixelcraft_gpu_native.*
native channels/protocol identifiers
applicationId / bundle id
persisted storage/schema names
```

Future reusable imaging package family should use the `dxtr_pixs_*` namespace from day one:

```text
dxtr_pixs_segment  — local segmentation / MobileSAM-class workflows
dxtr_pixs_restore  — restoration such as face enhance / denoise / super-resolution
dxtr_pixs_raw      — only if a future real RAW pipeline proves a clean reusable boundary
```

CI package guard:

```text
tool/check_package_boundaries.sh
```

---

# 6. UX modernization direction

The current UX modernization target is to move the product away from a test-app feel and toward a professional photography instrument while preserving architecture contracts.

Interaction references may be informed by 60fps.design principles, but implementation must not visually copy other products.

Core UX principles:

```text
Image first
Direct manipulation
Continuous feedback
Spatial continuity
Progressive disclosure
Tactile precision controls
Professional information density
One-handed camera usability
Predictable gestures
Fast perceived response
```

Priority surfaces:

```text
Camera
Camera Film selector
Photo Editor
Precision adjustment controls
Before / After comparison
Film library
Film Profile detail
Create Film Profile
Save / export interactions
```

Recommended implementation strategy:

1. small reviewable UX slices;
2. reuse existing controller/semantic paths;
3. presentation-only changes stay outside Rust semantics;
4. real-time preview work must preserve latest-value-wins/stale-render safety;
5. do not mix new RAW/image-processing semantics into UX-only PRs;
6. add focused widget/state tests per interaction;
7. run full CI before merge.

---

# 7. Dart 3.13 native tree-shaking roadmap — O1

PR #31 records a future optimization track for Dart 3.13 recorded native usage / `RecordUse`.

Order:

```text
branding cleanup
 -> PKG-01 package namespace stabilization
 -> active UX modernization slice
 -> O1 native tree-shaking PoC
```

O1 must be evidence-driven:

1. confirm the repository/toolchain is actually on a compatible Dart/Flutter version;
2. capture native binary-size baselines before changes;
3. start with `dxtr_pixs_gpu` / current `pixelcraft_gpu` equivalent as the first PoC;
4. verify required native symbols are retained and runtime behavior remains correct;
5. measure release artifact size benefit;
6. expand to engine integration only when benefit is demonstrated;
7. keep existing Flutter Rust Bridge integration unless a separate migration is justified.

Do not treat Dart 3.13 adoption or RecordUse as a blocker for current product work.

---

# 8. G7A / G7B split

G7A is complete and merged. It covered account-independent release work: signing architecture, unsigned/no-codesign packaging, native Rust/LUT verification, version/build identity audit, privacy/permission audit, store metadata/privacy drafts, release notes/RC QA preparation, and CI release artifact generation.

G7B remains **deferred indefinitely and not scheduled**. It is not an active blocker.

G7B scope, when explicitly resumed:

```text
Google Play Console / Play App Signing / Internal Testing
Apple Developer / App Store Connect / distribution signing / TestFlight
actual Data Safety / App Privacy submissions
actual store review/submission
signed store-delivered RC physical-device smoke
```

Resume G7B only after an explicit project decision.

---

# 9. Release engineering baseline

Android:

```text
applicationId: dev.cnxdev.pixelcraft
versionName/versionCode: 0.1.0 / 1
compileSdk: 36
targetSdk: 36
minSdk: 24
Rust ABIs: arm64-v8a, armeabi-v7a, x86_64
release debug-signing guard: PASS
RECORD_AUDIO: ABSENT
```

iOS:

```text
bundle id: dev.cnxdev.pixelcraft
deployment target: 13.0
pixelcraft_engine.framework: present
Film/Creative GPU LUT assets: present
release --no-codesign: PASS
```

Release safeguards:

- release must not use debug signing;
- signing secrets remain outside git;
- first-RC policy keeps minification/R8 off;
- recovery data stays in private app-support storage;
- export is user initiated;
- Share explicitly passes only the exported file to the system share sheet;
- diagnostics contain renderer/profile/sample/error metrics only and no user image bytes/live frames;
- no analytics, advertising, or remote crash-reporting SDK is currently in the app dependency set.

Historical evidence names are not rewritten during branding/package migrations.

---

# 10. Verified evidence

Final G7A validation:

```text
GitHub Actions run: #221
run id: 31611799174
HEAD: d5e0aab14a0ae9a5b8124a0b37fef78249cbbeb5
conclusion: SUCCESS
```

Recent merged evidence:

```text
PR #26: run #266 / 31853058185 — SUCCESS
PR #27: run #267 / 31853404031 — SUCCESS
```

Current open-work evidence observed on 2026-08-15:

```text
PR #29 branding cleanup             OPEN
PR #30 dxtr_pixs package namespace  DRAFT
PR #31 Dart 3.13 roadmap            OPEN
```

CI status must always be checked from GitHub before merge; this document must not be used to claim a later run passed.

---

# 11. Verification rules

1. Never claim CI/test/device/build/store validation passed unless actually run or explicitly reported.
2. Never commit keystores, passwords, private certificates, provisioning profiles, or store credentials.
3. Never ship Android production artifacts with debug signing.
4. Unsigned Android / no-codesign iOS artifacts are packaging evidence only.
5. Release engineering must not weaken Rust authority, GPU fail-closed behavior, or package boundaries.
6. Native release changes require CI packaging evidence; signed RCs later require physical-device smoke.
7. G7B is deferred indefinitely and must not be resumed without an explicit project decision.
8. Product renaming must not rewrite historical evidence as if old builds used the new identity.
9. Bundle/application identifier changes require an explicit migration decision separate from display-name branding.
10. Package namespace changes must not silently become native ABI/runtime identifier migrations.
11. Product/editor UX additions must reuse existing semantic commit paths unless a deliberate Rust-first semantic change is being made.
12. RecordUse/native tree-shaking changes require before/after release-size evidence and runtime symbol-retention validation.

---

# 12. Important files

```text
.github/workflows/ci.yml
android/app/build.gradle.kts
android/app/src/main/AndroidManifest.xml
ios/Runner/Info.plist
ios/Runner.xcodeproj/project.pbxproj
lib/main.dart
lib/state/editor_controller.dart
lib/core/editor_session_store.dart
lib/core/export_file_service.dart
lib/ui/screens/home_screen.dart
lib/ui/screens/editor_screen.dart
lib/ui/widgets/editor_tool_panel.dart
lib/ui/widgets/straighten_control.dart
lib/ui/widgets/histogram_widget.dart
tool/check_package_boundaries.sh
docs/G7A_ANDROID_SIGNING.md
docs/G7A_RELEASE_READINESS.md
docs/G7A_PRIVACY_STORE_DRAFTS.md
docs/PROJECT_HANDOFF.md
docs/CODE_WALKTHROUGH.md
README.md
```

---

# 13. Current next action

**Finish and merge the active identity/package foundation cleanly, then return to the UX modernization track. G7B remains deferred indefinitely.**

Recommended sequence:

```text
1. PR #29
   - keep the focused branding-cleanup diff narrow
   - make CI green
   - merge

2. PR #30 / PKG-01
   - retarget/rebase from main after #29 merges
   - complete dxtr_pixs_* package namespace migration
   - preserve Rust/native ABI/runtime identifiers listed above
   - run the complete CI/package/native matrix
   - merge only when green and review findings are resolved

3. PR #31 / O1 docs roadmap
   - keep as roadmap-only unless explicitly promoted to implementation
   - merge when conflict-free and green

4. UX modernization
   - inspect Camera, Editor, Film/Profile current surfaces
   - choose the smallest high-value interaction gap
   - prioritize direct manipulation, precision controls, discoverability, and image-first layout
   - avoid broad visual rewrites

5. Dart 3.13 RecordUse implementation
   - only after package namespace/toolchain stabilization and an active UX slice
   - baseline binary sizes first
   - PoC on GPU native library first
```

Do not resume G7B and do not change `dev.cnxdev.pixelcraft` identifiers unless explicitly approved as separate work.

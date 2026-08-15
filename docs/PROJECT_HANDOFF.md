# PixelCraft Project Handoff

## Purpose

This is the canonical continuation document for the PixelCraft repository and the **Dextryx Pixels** product.

When starting a new work session:

1. read this file first;
2. inspect `main`, the active PR, and its latest CI run;
3. continue from **Current next action**;
4. treat repository state and recorded CI/device evidence as authoritative over older chat history.

Recommended continuation prompt:

```text
อ่าน docs/PROJECT_HANDOFF.md ใน repo PixelCraft แล้วทำต่อจาก Current next action
```

Last refresh: **2026-08-15, after PR #26 and PR #27 merged; G7B deferred indefinitely; Dart 3.13 native tree-shaking optimization track added to roadmap**.

---

# 1. Product identity — PRIMARY MIGRATION MERGED / COPY CLEANUP PENDING

Identity decision frozen on 2026-08-15:

```text
master brand: Dextryx
product name: Dextryx Pixels
installed app label: Dxtr Pixs
short visual mark: DXTR PIXS or DXTR + pixel/film symbol
technical package/module naming target: dextryx_pixels where a new identifier is needed
repository name: PixelCraft (unchanged)
```

Migration rules:

1. Product-facing copy should use **Dextryx Pixels**.
2. Android/iOS launcher or home-screen display labels use **Dxtr Pixs**.
3. Privacy/permission copy uses **Dextryx Pixels**.
4. Do not cosmetically mass-rename Rust/Dart package names, native channel names, historical evidence, test fixtures, or repository paths.
5. Historical evidence may retain `PixelCraft` / `Pixel Craft` when that was the literal build/product name at that time.
6. Android applicationId and iOS bundle id remain `dev.cnxdev.pixelcraft` until a deliberate identifier migration is approved and validated.
7. Do not rename the GitHub repository as part of the identity migration.
8. PR #27 completed the primary app identity migration, but a focused follow-up must replace remaining current user-facing legacy branding copy before the identity workstream is considered fully closed.

Identity PR:

```text
PR #27: Rename product identity to Dextryx Pixels
branch: feature/dextryx-pixels-identity
HEAD: 494649b7bea9c12a9b6141cdb3d810596bd67bff
CI: run #267 / 31853404031 — SUCCESS
merge commit: 5f4ea1e3ba0b2e7e9983eb096109742ead0b1ea9
```

Known current branding cleanup targets confirmed on `main` after PR #27:

```text
lib/ui/screens/home_screen.dart
  AppBar title: "Pixel Craft"

lib/core/export_file_service.dart
  share text: "Edited with PixelCraft"

lib/ui/screens/editor_screen.dart
  gallery-error copy: "Pixel Craft could not add it to the device gallery."
```

These are current product-facing strings, not historical evidence, and should move to **Dextryx Pixels** in a focused follow-up slice.

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
Dextryx Pixels primary identity                  MERGED
Dextryx Pixels user-facing copy cleanup          PENDING

O1  Dart 3.13 native tree-shaking / RecordUse   PLANNED / GATED
```

Historical G7 PR #10 is closed/superseded. Do not reopen or merge it.

---

# 4. Post-G7A product/editor work

Product/editor development resumed after G7A without changing Rust/GPU authority.

Merged slices:

```text
PR #20  Editor: discoverable Before/After Compare UX
PR #21  Film library: search and origin filters
PR #22  Fix Compare session state and wide-layout placement
PR #23  Editor: discoverable Zoom / Fit controls
PR #24  Editor: precise numeric value entry for adjustment sliders
PR #25  Editor: histogram channel inspector
PR #26  Editor: precise straighten angle entry
PR #27  Product identity: Dextryx Pixels / Dxtr Pixs (primary pass)
```

PR #26 final evidence:

```text
branch: feature/editor-precise-straighten
HEAD: 46abb1807890faf5863a3cf3851cdd53b1cafe52
CI: run #266 / 31853058185 — SUCCESS
merge commit: 5b85f567d58e5efaf14588fb34757f195b8911a2
```

PR #26 review findings were addressed before merge:

- exact straighten values below the commit threshold are normalized to zero before preview/commit so UI and Rust/export state cannot diverge;
- decimal comma input such as `2,5` is accepted by the exact-value parser;
- regression tests cover both behaviors.

These post-G7A slices are presentation/product workflow improvements. They do not transfer committed image authority away from Rust and do not make GPU preview authoritative.

---

# 5. Package graph

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

CI package guard:

```text
tool/check_package_boundaries.sh
```

Package names remain unchanged unless there is a concrete technical migration reason.

---

# 5A. O1 — Dart 3.13 native tree-shaking / RecordUse optimization track

This track is now part of the roadmap, but it must not interrupt the active product/UX workstream or destabilize the existing Flutter Rust Bridge/native build path.

Primary goal:

```text
reduce shipped native binary footprint by allowing the Dart AOT/link pipeline to retain only native symbols that are actually used by the application, and where possible omit an unused native library entirely.
```

Relevant Dart mechanism:

- Dart 3.13 introduces recorded-usage native tree-shaking through link hooks.
- packages with native assets built through `hook/build.dart` can add `hook/link.dart`.
- the compiler records referenced `@Native` symbols and exposes them through `LinkInput.recordedUses`.
- generated or handwritten Dart-to-native method identifiers must be mapped to the actual native symbols retained by the linker.
- `symbolsToKeep == null` means tree-shaking is disabled / all symbols are preserved.
- `symbolsToKeep == []` means the application references no symbols from that native asset; supported link tooling may skip compiling/bundling that dynamic library entirely.

Official reference:

```text
https://dart.dev/tools/hooks
https://dart.dev/blog/announcing-dart-3-13#tree-shaking-native-libraries-with-recorduse-and-package-record_use
```

Current repository baseline relevant to O1:

```text
root Dart SDK constraint: >=3.12.0 <4.0.0
root Flutter constraint: >=3.44.0
flutter_rust_bridge: ^2.12.0
native/Rust-heavy packages include pixelcraft_engine and pixelcraft_gpu
pixelcraft_gpu already has isolated Rust + Android/iOS/macOS/Linux/Windows package structure
```

O1 ordering and gates:

```text
O1.0  Toolchain gate
      Confirm the selected stable Flutter SDK actually ships the Dart 3.13 APIs needed by hooks/link hooks/record_use.
      Do not raise the SDK floor only from roadmap assumptions.

O1.1  Native size baseline
      Measure release binary/native contribution before any migration:
      - Android APK/AAB per ABI where practical
      - iOS app/framework or archive contribution
      - macOS/Linux/Windows release artifacts when available
      Record reproducible commands and artifact sizes.

O1.2  API/build audit
      Inventory native entry points in pixelcraft_gpu and pixelcraft_engine.
      Identify which bindings are currently generated/owned by flutter_rust_bridge and which could participate safely in Code Assets/build hooks.
      Do not rewrite image semantics or GPU ownership.

O1.3  pixelcraft_gpu PoC first
      Use pixelcraft_gpu as the first RecordUse/native-link-tree-shaking experiment because it is already isolated as a plugin/package and its native footprint can be measured independently.
      Add the minimum build/link hook surface required for the experiment.
      Establish deterministic Dart-method -> native-symbol mapping.

O1.4  Linker/LTO verification
      Ensure Rust/native artifacts are built in a form where unused symbols can actually be eliminated by the final linker.
      Verify section GC/LTO/export visibility behavior rather than assuming RecordUse alone reduces size.

O1.5  Before/after evidence
      Compare:
      - shipped binary size
      - native library size
      - release build time
      - startup/load behavior
      - runtime correctness
      - CI reproducibility

O1.6  Decision gate
      Expand to pixelcraft_engine only if the PoC produces a material, measurable benefit without making the native build/release pipeline disproportionately complex.
      Otherwise retain the current flutter_rust_bridge/native integration and document the experiment result.

O1.7  Engine expansion if approved
      Apply the proven pattern to pixelcraft_engine incrementally.
      Never combine this work with image-processing semantic changes, UX changes, or bundle/application identifier migration.
```

O1 acceptance criteria:

1. Existing Rust authority and GPU fail-closed contracts remain unchanged.
2. Release builds pass existing package/native verification.
3. No native symbol required at runtime is accidentally removed.
4. Size improvements are recorded with before/after artifacts, not estimated.
5. CI can reproduce the link process on supported platforms.
6. A rollback to the existing native integration remains straightforward during the PoC.
7. `flutter_rust_bridge` is not removed merely to adopt RecordUse; any binding migration requires independent technical justification.

Scheduling policy:

**Do not start O1 implementation before the current Dextryx Pixels branding cleanup and the active UX modernization slice are stabilized.** After that, O1 should run before another broad release-hardening/binary-size optimization pass, so its measurements can influence the next release baseline. G7B remains unrelated and deferred indefinitely.

---

# 6. G7A / G7B split

G7A is complete and merged. It covered account-independent release work: signing architecture, unsigned/no-codesign packaging, native Rust/LUT verification, version/build identity audit, privacy/permission audit, store metadata/privacy drafts, release notes/RC QA preparation, and CI release artifact generation.

G7B remains defined but is **deferred indefinitely and not scheduled**. Do not treat G7B as an active blocker for product/editor development, and do not pause current work waiting for store accounts.

G7B scope, when explicitly resumed in the future:

```text
Google Play Console / Play App Signing / Internal Testing
Apple Developer / App Store Connect / distribution signing / TestFlight
actual Data Safety / App Privacy submissions
actual store review/submission
signed store-delivered RC physical-device smoke
```

Current policy:

1. Do not schedule or start G7B automatically when accounts become available.
2. Resume G7B only after an explicit project decision.
3. Until then, continue product/editor work from current `main` while preserving release readiness and signing/privacy safeguards already established by G7A.

---

# 7. Release engineering baseline

Android release rules:

- release must not use debug signing;
- optional ignored `android/key.properties` release signing;
- signing secrets remain outside git;
- first-RC policy keeps minification/R8 off;
- CAMERA remains;
- WRITE_EXTERNAL_STORAGE is limited through API 28;
- dependency RECORD_AUDIO is explicitly removed;
- fallback Flutter camera is still-photo only with `enableAudio: false`.

CI release jobs build Android release APK and iOS release `--no-codesign`, verify Rust/native artifacts and Film/Creative LUT assets, and upload artifacts.

Privacy hardening already merged:

- recovery data stays in private app-support storage;
- export is user initiated;
- Share explicitly passes only the exported file to the system share sheet;
- diagnostics contain renderer/profile/sample/error metrics only and no user image bytes/live frames;
- no analytics, advertising, or remote crash-reporting SDK is currently in the app dependency set.

---

# 8. Verified release evidence

Final G7A PR validation:

```text
GitHub Actions run: #221
run id: 31611799174
HEAD: d5e0aab14a0ae9a5b8124a0b37fef78249cbbeb5
conclusion: SUCCESS
```

Post-G7A latest green PR evidence:

```text
PR #26: run #266 / 31853058185 — SUCCESS
PR #27: run #267 / 31853404031 — SUCCESS
```

Android release baseline:

```text
package: dev.cnxdev.pixelcraft
versionName/versionCode: 0.1.0 / 1
compileSdk: 36
targetSdk: 36
minSdk: 24
Rust ABIs: arm64-v8a, armeabi-v7a, x86_64
release debug-signing guard: PASS
RECORD_AUDIO: ABSENT
```

iOS release baseline:

```text
bundle id: dev.cnxdev.pixelcraft
deployment target: 13.0
pixelcraft_engine.framework: present
Film/Creative GPU LUT assets: present
release --no-codesign: PASS
```

Historical evidence names are not rewritten during branding migration.

---

# 9. Release identity / RC policy

Current identity:

```text
brand: Dextryx
product: Dextryx Pixels
app display label: Dxtr Pixs
marketing version: 0.1.0 while pre-1.0 beta/RC work continues
current build: 1
Android applicationId: dev.cnxdev.pixelcraft
iOS bundle id: dev.cnxdev.pixelcraft
iOS deployment target: 13.0
Android min/target/compile SDK: 24 / 36 / 36
```

Build numbers for future externally distributed signed builds must increase monotonically when external distribution resumes.

A later bundle/application identifier migration may target a Dextryx-specific identifier, but it must be handled as a deliberate release migration and must not be mixed casually into display-name/product work.

---

# 10. Verification rules

1. Never claim CI/test/device/build/store validation passed unless actually run or explicitly reported.
2. Never commit keystores, passwords, private certificates, provisioning profiles, or store credentials.
3. Never ship Android production artifacts with debug signing.
4. Unsigned Android / no-codesign iOS artifacts are packaging evidence only.
5. Release engineering must not weaken Rust authority, GPU fail-closed behavior, or package boundaries.
6. Native release changes require CI packaging evidence; signed RCs later require physical-device smoke.
7. G7B is deferred indefinitely and must not be resumed without an explicit project decision.
8. Product renaming must not rewrite historical evidence as if old builds used the new identity.
9. Bundle/application identifier changes require an explicit migration decision and validation separate from display-name branding.
10. Product/editor UX additions must reuse existing semantic commit paths unless a deliberate Rust-first semantic change is being made.
11. RecordUse/native tree-shaking work must be evidence-driven: preserve all symbols when recorded usage is unavailable, measure before/after release artifacts, and never trade runtime correctness for binary-size reduction.

---

# 11. Important files

```text
.github/workflows/ci.yml
android/app/build.gradle.kts
android/app/src/main/AndroidManifest.xml
ios/Runner/Info.plist
ios/Runner.xcodeproj/project.pbxproj
lib/main.dart
lib/core/editor_session_store.dart
lib/core/export_file_service.dart
lib/ui/screens/home_screen.dart
lib/ui/screens/editor_screen.dart
lib/ui/widgets/editor_tool_panel.dart
lib/ui/widgets/straighten_control.dart
lib/ui/widgets/histogram_widget.dart
packages/pixelcraft_gpu/pubspec.yaml
packages/pixelcraft_gpu/rust/
packages/pixelcraft_engine/pubspec.yaml
docs/G7A_ANDROID_SIGNING.md
docs/G7A_RELEASE_READINESS.md
docs/G7A_PRIVACY_STORE_DRAFTS.md
docs/PROJECT_HANDOFF.md
docs/CODE_WALKTHROUGH.md
README.md
```

---

# 12. Current next action

**PR #26 and PR #27 are merged. G7B is deferred indefinitely / not scheduled. Before broader work, finish the remaining Dextryx Pixels user-facing copy cleanup; then continue the active UX modernization work. O1 Dart 3.13 native tree-shaking follows only after that UX slice is stabilized.**

Continue from current `main` and preserve all architecture/release invariants.

Recommended next sequence:

```text
1. finish remaining current user-facing legacy branding strings:
   - Home AppBar: Pixel Craft -> Dextryx Pixels
   - Share text: Edited with PixelCraft -> Edited with Dextryx Pixels
   - Editor gallery-error copy: Pixel Craft -> Dextryx Pixels
2. search current runtime/user-facing surfaces for any additional non-historical PixelCraft / Pixel Craft branding
3. add/update focused tests where branding strings are covered, run CI, and merge the branding cleanup
4. continue the active UX modernization work as small reviewable slices; preserve existing Rust/GPU semantic boundaries
5. stabilize the UX slice and package-facing APIs before touching the native build pipeline
6. start O1.0/O1.1 only then:
   - confirm stable Flutter/Dart 3.13 toolchain support
   - capture native/release binary-size baseline
7. perform O1.2 native API/build audit
8. implement O1.3 pixelcraft_gpu RecordUse/link-hook PoC first
9. verify linker/LTO behavior and collect before/after size/build/runtime evidence
10. expand RecordUse/native tree-shaking to pixelcraft_engine only if the PoC demonstrates material benefit with acceptable complexity
11. do not remove flutter_rust_bridge merely to adopt RecordUse
12. do not change dev.cnxdev.pixelcraft identifiers unless an explicit identifier-migration task is approved
13. do not resume G7B unless an explicit project decision brings it back into scope
```

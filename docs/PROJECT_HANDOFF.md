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

Last refresh: **2026-08-15, after PR #26 and PR #27 merged; G7B deferred indefinitely**.

---

# 1. Product identity — MERGED

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

1. Product-facing copy uses **Dextryx Pixels**.
2. Android/iOS launcher or home-screen display labels use **Dxtr Pixs**.
3. Privacy/permission copy uses **Dextryx Pixels**.
4. Do not cosmetically mass-rename Rust/Dart package names, native channel names, historical evidence, test fixtures, or repository paths.
5. Historical evidence may retain `PixelCraft` / `Pixel Craft` when that was the literal build/product name at that time.
6. Android applicationId and iOS bundle id remain `dev.cnxdev.pixelcraft` until a deliberate identifier migration is approved and validated.
7. Do not rename the GitHub repository as part of the identity migration.

Identity PR:

```text
PR #27: Rename product identity to Dextryx Pixels
branch: feature/dextryx-pixels-identity
HEAD: 494649b7bea9c12a9b6141cdb3d810596bd67bff
CI: run #267 / 31853404031 — SUCCESS
merge commit: 5f4ea1e3ba0b2e7e9983eb096109742ead0b1ea9
```

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
Dextryx Pixels identity                         MERGED
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
PR #27  Product identity: Dextryx Pixels / Dxtr Pixs
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
lib/ui/widgets/editor_tool_panel.dart
lib/ui/widgets/straighten_control.dart
lib/ui/widgets/histogram_widget.dart
docs/G7A_ANDROID_SIGNING.md
docs/G7A_RELEASE_READINESS.md
docs/G7A_PRIVACY_STORE_DRAFTS.md
docs/PROJECT_HANDOFF.md
docs/CODE_WALKTHROUGH.md
README.md
```

---

# 12. Current next action

**PR #26 and PR #27 are merged. G7B is deferred indefinitely / not scheduled. The active workstream is post-G7A Product / Editor UX.**

Continue from current `main` and preserve all architecture/release invariants.

Recommended next sequence:

```text
1. keep main green after the PR #26 + #27 merge sequence
2. continue product/editor UX as small reviewable slices rather than a broad rewrite
3. prioritize discoverability, precision, direct manipulation, responsive layout, and Film/Profile workflow polish
4. reuse existing EditorController / Rust-authoritative commit paths for presentation-only UX
5. do not begin new RAW/image-processing semantics as part of UX-only slices
6. do not change dev.cnxdev.pixelcraft identifiers unless an explicit identifier-migration task is approved
7. for every slice: add focused tests, run full CI, resolve review findings, then merge
8. do not resume G7B unless an explicit project decision brings it back into scope
```

Before starting the next implementation slice, inspect the current Editor and Film/Profile surfaces on `main` and choose the smallest high-value UX gap that does not require new image semantics.

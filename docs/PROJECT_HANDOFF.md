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

Last refresh: **2026-08-12, post-G7A merge**.

---

# 1. Architecture invariants

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
P3  pixelcraft_film extraction                  MERGED

G7A Release Engineering / Store Preparation     MERGED
G7B Store Account Integration / Beta Upload     BLOCKED BY EXTERNAL ACCOUNTS
```

P3 merge commit:

```text
fb5c05493478eedea7223d8bbf790ea63e175729
```

G7A merge:

```text
PR: #18
branch: feature/g7a-release-engineering
merge commit: 507875b2e1187e2bc2f0a6d0535b77dc0455b69f
final PR HEAD: d5e0aab14a0ae9a5b8124a0b37fef78249cbbeb5
final PR CI: run #221 / 31611799174 — SUCCESS
```

Historical G7 PR:

```text
PR #10: CLOSED / SUPERSEDED
branch: feature/g7-release-readiness
```

PR #10 was audited file-by-file after G7A merged. Its five changed files were either recreated or superseded by PR #18; no missing implementation needed migration. Do not reopen or merge PR #10.

---

# 3. Package graph

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

CI package guard:

```text
tool/check_package_boundaries.sh
```

---

# 4. G7A / G7B split

G7A is complete and merged. It covered account-independent release work:

```text
release signing architecture
unsigned/no-codesign production packaging
native Rust/LUT artifact verification
version/build identity audit
privacy/permission audit
offline store metadata/privacy drafts
release notes + RC QA preparation
CI release artifact generation
```

G7B requires external accounts and is currently blocked:

```text
Google Play Console / Play App Signing / Internal Testing
Apple Developer / App Store Connect / distribution signing / TestFlight
actual Data Safety / App Privacy submissions
actual store review/submission
```

The absence of Apple/Google accounts is an external G7B blocker, not a code or architecture failure.

---

# 5. Merged G7A release engineering

Android:

```text
android/app/build.gradle.kts
  - release no longer uses debug signing
  - optional ignored android/key.properties release signing
  - signing secrets remain outside git
  - current first-RC policy keeps minification/R8 off

android/app/src/main/AndroidManifest.xml
  - CAMERA remains
  - WRITE_EXTERNAL_STORAGE limited through API 28
  - dependency RECORD_AUDIO is explicitly removed
```

The fallback Flutter camera is still-photo only:

```dart
enableAudio: false
```

CI release jobs:

```text
android-release
  -> flutter pub get
  -> FRB codegen
  -> flutter build apk --release
  -> Rust native library check
  -> no-debug-signing check
  -> artifact upload

ios-release
  -> flutter pub get
  -> FRB codegen
  -> flutter build ios --release --no-codesign
  -> Runner.app/native check
  -> artifact upload
```

Privacy hardening:

```text
EditorSessionStore
  - private app-support recovery storage
  - max 3 coherent generations
  - obsolete generation pruning
  - abandoned .tmp cleanup during load/save
  - Discard removes recovery directory

ExportFileService
  - export is user initiated
  - local app-documents/gallery persistence
  - Share is explicit and passes only the exported file to the system share sheet

Diagnostics
  - renderer/profile/sample/error metrics only
  - no user image bytes or live frame buffers in Dart diagnostics
```

Current app dependency set contains no analytics, advertising, or remote crash-reporting SDK.

---

# 6. Verified release evidence

Final G7A PR validation:

```text
GitHub Actions run: #221
run id: 31611799174
HEAD: d5e0aab14a0ae9a5b8124a0b37fef78249cbbeb5
conclusion: SUCCESS
```

Verified implementation baseline including recovery temp cleanup:

```text
GitHub Actions run: #216
run id: 31609170884
HEAD: af94739cf546a518bcea1fb917c42cf9df2b6d23
conclusion: SUCCESS
```

Run #216 passed:

```text
validate
Golden tests + iOS debug packaging
wgpu Linux / macOS / Windows
Android release artifact
iOS release no-codesign
```

Android release evidence:

```text
package: dev.cnxdev.pixelcraft
versionName/versionCode: 0.1.0 / 1
compileSdk: 36
targetSdk: 36
minSdk: 24
APK size: ~81.5 MB
Rust ABIs: arm64-v8a, armeabi-v7a, x86_64
Film/Creative GPU LUT assets: present
release debug-signing guard: PASS
RECORD_AUDIO in packaged release manifest: ABSENT
```

iOS release evidence:

```text
bundle id: dev.cnxdev.pixelcraft
deployment target: 13.0
Runner.app: ~37.7 MB
pixelcraft_engine.framework: present
Film/Creative GPU LUT assets: present
release --no-codesign: PASS
```

Dependency Privacy Manifests are present for Flutter/multiple plugins in the release bundle. PixelCraft currently has no app-owned `PrivacyInfo.xcprivacy`; do not invent one without final app-owned required-reason evidence. Re-audit the final signed Xcode archive in G7B.

Evidence categories remain distinct:

```text
semantic/unit tests
package-boundary tests
native packaging smoke
unsigned/no-codesign release build
physical-device RC smoke
store upload/beta validation
```

Never promote one category as proof of another.

---

# 7. Release identity / RC policy

```text
app display name: Pixel Craft
marketing version: 0.1.0 while pre-1.0 beta/RC work continues
current build: 1
Android applicationId: dev.cnxdev.pixelcraft
iOS bundle id: dev.cnxdev.pixelcraft
iOS deployment target: 13.0
Android min/target/compile SDK: 24 / 36 / 36
```

Build-number policy for future externally distributed signed builds: monotonically increment each distributed build. Actual enforcement starts in G7B when signing/accounts exist.

---

# 8. G7B blockers

Current external blockers:

```text
Apple Developer / App Store Connect account: unavailable
Google Play Console account: unavailable
```

Therefore these remain pending, not failed:

```text
production iOS certificate/provisioning
signed iOS archive / TestFlight upload
Google Play App Signing enrollment
signed Android AAB upload
Play Internal Testing
App Store Connect App Privacy submission
Play Console Data Safety submission
actual store review/submission
signed-store-delivered RC physical-device smoke
```

When accounts become available, start G7B from current `main`; do not resurrect PR #10.

---

# 9. Known non-blocking tooling debt

```text
pixelcraft_engine + pixelcraft_gpu still rely on CocoaPods and lack Swift Package Manager support
future Flutter/Kotlin integration warnings may require migration work later
```

Do not confuse future-tooling warnings with current build correctness; G7A release CI completed successfully on Flutter 3.44.7.

---

# 10. Verification rules

1. Never claim CI/test/device/build/store validation passed unless actually run or explicitly reported.
2. Never commit keystores, passwords, private certificates, provisioning profiles, or store credentials.
3. Never ship Android production artifacts with debug signing.
4. Unsigned Android / no-codesign iOS artifacts are packaging evidence only.
5. Release engineering must not weaken Rust authority, GPU fail-closed behavior, or package boundaries.
6. Native release changes require CI packaging evidence; signed RCs later require physical-device smoke.
7. Store-account-dependent items remain BLOCKED until accounts exist.
8. PR #10 is closed/superseded and must not become the active G7 line again.

---

# 11. Important files

```text
.github/workflows/ci.yml
android/app/build.gradle.kts
android/app/src/main/AndroidManifest.xml
ios/Runner/Info.plist
ios/Runner.xcodeproj/project.pbxproj
lib/core/editor_session_store.dart
lib/core/export_file_service.dart
docs/G7A_ANDROID_SIGNING.md
docs/G7A_RELEASE_READINESS.md
docs/G7A_PRIVACY_STORE_DRAFTS.md
docs/PROJECT_HANDOFF.md
docs/CODE_WALKTHROUGH.md
README.md
```

---

# 12. Current next action

**P0–P3 and G7A are merged. G7B is externally blocked until Apple/Google store accounts exist.**

Until those accounts are available:

```text
1. keep main green; do not weaken release/package/semantic gates
2. treat docs/G7A_RELEASE_READINESS.md and docs/G7A_PRIVACY_STORE_DRAFTS.md as the prepared G7B input
3. increment version/build only when an actual externally distributed signed build is prepared
4. if product/editor work continues before G7B, branch from current main and preserve Rust/GPU/package invariants
5. when Apple Developer/App Store Connect becomes available, start iOS G7B signing + TestFlight
6. when Google Play Console becomes available, start Android G7B Play App Signing + Internal Testing
7. re-audit final signed artifacts for permissions/privacy manifests before store form submission
8. execute signed RC physical-device smoke before beta/store readiness is claimed
```

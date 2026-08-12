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

Last refresh: **2026-08-12, G7A / PR #18 after release CI run #211**.

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

G7A Release Engineering / Store Preparation     ACTIVE — PR #18
G7B Store Account Integration / Beta Upload     BLOCKED BY EXTERNAL ACCOUNTS
```

P3 merge commit:

```text
fb5c05493478eedea7223d8bbf790ea63e175729
```

G7A:

```text
branch: feature/g7a-release-engineering
PR: #18
base: post-P3 main @ fb5c05493478eedea7223d8bbf790ea63e175729
```

Old PR #10 is historical/preserved only. Do not merge it unchanged.

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

G7A can be completed without store accounts:

```text
release signing architecture
unsigned/no-codesign production packaging
native Rust/LUT artifact verification
version/build identity audit
privacy/permission audit
store metadata/asset preparation
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

Absence of the accounts is an external G7B blocker, not a G7A code blocker.

---

# 5. Current G7A implementation

Android:

```text
android/app/build.gradle.kts
  - release no longer uses debug signing
  - optional android/key.properties explicit release signing
  - secrets remain outside git

android/app/src/main/AndroidManifest.xml
  - CAMERA remains
  - legacy WRITE_EXTERNAL_STORAGE limited through API 28
  - unused RECORD_AUDIO is now explicitly removed from dependency merge
```

The Flutter fallback camera uses:

```dart
enableAudio: false
```

so microphone permission is not part of the intended still-photo product flow.

CI:

```text
android-release
  -> FRB codegen
  -> flutter build apk --release
  -> Rust native library check
  -> no-debug-signing check
  -> artifact upload

ios-release
  -> FRB codegen
  -> flutter build ios --release --no-codesign
  -> Runner.app/native check
  -> artifact upload
```

Docs:

```text
docs/G7A_RELEASE_READINESS.md
docs/G7A_ANDROID_SIGNING.md
docs/PROJECT_HANDOFF.md
```

---

# 6. Verified release evidence — run #211

```text
GitHub Actions run: #211
run id: 31604232738
HEAD: 043cc3700aedf10cec3f58c22cb0977ce195408b
conclusion: SUCCESS
```

All jobs passed:

```text
validate
Golden tests + iOS debug packaging
wgpu Linux / macOS / Windows
Android release artifact
iOS release no-codesign
```

Android release evidence from the produced APK:

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
```

Android artifact:

```text
zip size: 35,998,416 bytes
SHA-256: 7d426470d48fd4ead710ee642dcede7fbe9b562478e52634edc4d430f662a56e
```

iOS release evidence:

```text
bundle id: dev.cnxdev.pixelcraft
deployment target: 13.0
Runner.app: 37.7 MB
pixelcraft_engine.framework: present
Film/Creative GPU LUT assets: present
release --no-codesign: PASS
```

iOS artifact:

```text
zip size: 16,679,854 bytes
SHA-256: 501ab348ecdad488fd294c76493da7c1a61e282e0c8b88169b7175977997cd66
```

Dependency Privacy Manifests were observed in the release app for Flutter and multiple iOS plugins. App-owned required-reason API / Privacy Manifest audit is still open.

---

# 7. Known release/tooling debt

Non-blocking for current G7A builds:

```text
pixelcraft_engine + pixelcraft_gpu still rely on CocoaPods and lack Swift Package Manager support
pixelcraft_gpu + share_plus currently apply Kotlin Gradle Plugin; Flutter warns future releases will require Built-in Kotlin compatibility
```

Do not mix these warnings with current release-build correctness: run #211 is green on Flutter 3.44.7.

---

# 8. Verification rules

1. Never claim CI/test/device/build/store validation passed unless actually run or explicitly reported.
2. Never commit keystores, passwords, private certificates, provisioning profiles, or store credentials.
3. Never ship Android production artifacts with debug signing.
4. Unsigned Android / no-codesign iOS artifacts are packaging evidence only.
5. Release engineering must not weaken Rust authority, GPU fail-closed behavior, or package boundaries.
6. Native release changes require CI packaging evidence; signed RCs later require physical-device smoke.
7. Store-account-dependent items remain BLOCKED until accounts exist.

---

# 9. Important files

```text
.github/workflows/ci.yml
android/app/build.gradle.kts
android/app/src/main/AndroidManifest.xml
ios/Runner/Info.plist
ios/Runner.xcodeproj/project.pbxproj
docs/G7A_ANDROID_SIGNING.md
docs/G7A_RELEASE_READINESS.md
docs/PROJECT_HANDOFF.md
docs/CODE_WALKTHROUGH.md
README.md
```

---

# 10. Current next action

**G7A is ACTIVE in PR #18. Run #211 is the verified pre-permission-cleanup release baseline.**

Current latest work after that baseline removes the unused Android `RECORD_AUDIO` permission.

Continue with:

```text
1. wait for fresh CI on the RECORD_AUDIO removal
2. inspect the new release APK merged manifest and verify RECORD_AUDIO is absent
3. if green, continue privacy audit: recovery/temp retention, share/export, diagnostics/log payloads
4. decide first-RC version/build-number policy
5. prepare store metadata/assets/release-notes drafts without accounts
6. refresh root README and docs/CODE_WALKTHROUGH with stable G7A evidence
7. inspect PR #18 review threads
8. keep PR #18 draft until G7A account-independent readiness is materially complete
9. do not start G7B upload/signing claims until Apple/Google accounts exist
```

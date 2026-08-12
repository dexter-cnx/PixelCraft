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

Last refresh: **2026-08-12, G7A release-engineering start after P3 merge**.

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

# 2. Current milestone status

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

G7A Release Engineering / Store Preparation     ACTIVE
G7B Store Account Integration / Beta Upload     BLOCKED BY EXTERNAL ACCOUNTS
```

P3 merged through PR #17 at merge commit:

```text
fb5c05493478eedea7223d8bbf790ea63e175729
```

G7A branch:

```text
feature/g7a-release-engineering
base: main @ fb5c05493478eedea7223d8bbf790ea63e175729
```

The user currently does not have Apple Developer / App Store Connect or Google Play Console accounts. This blocks G7B store integration only; it does **not** block release engineering, unsigned/no-codesign packaging validation, signing architecture, privacy audit, metadata preparation, or release QA preparation.

Old PR #10 (`feature/g7-release-readiness`) remains historical/preserved. Do not merge it unchanged. Its useful release-signing/build ideas are being recreated on the post-P3 architecture in G7A.

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

Package-boundary enforcement:

```text
tool/check_package_boundaries.sh
```

---

# 4. G7A scope — can be completed without store accounts

G7A owns release preparation and evidence that does not require Apple/Google store ownership:

```text
Android release signing architecture
Android unsigned release packaging validation
Android native Rust packaging verification
iOS release --no-codesign validation
iOS native/Rust bundle verification
version/build-number policy
bundle/application identifier audit
privacy/permission audit
Privacy Manifest dependency audit
release logging/crash-data policy
app icon/splash/store screenshot preparation
store metadata drafts
privacy-policy/support-URL checklist
release notes template
RC QA checklist
CI release artifact generation
```

G7A must not claim TestFlight, Play Internal Testing, store-signing, or actual submission success.

---

# 5. G7B scope — blocked until accounts exist

```text
Google Play Console app creation
Play App Signing / upload key enrollment
signed AAB upload
Play Internal Testing
Data Safety submission in Console

Apple Developer / App Store Connect app creation
Distribution certificate / provisioning profile
signed archive / IPA upload
TestFlight Internal Testing
App Privacy submission in App Store Connect
actual store review/submission
```

Treat these as external-account blockers, not code blockers.

---

# 6. Current G7A implementation

Recreated from useful PR #10 ideas on post-P3 main:

```text
android/app/build.gradle.kts
  - removes release debug signing
  - optional android/key.properties release signing
  - no signing secret committed

.github/workflows/ci.yml
  - android-release job
      flutter build apk --release
      verify libpixelcraft_engine.so packaged
      verify release config does not use debug signing
      upload release APK artifact
  - ios-release job
      flutter build ios --release --no-codesign
      verify Runner.app/native output
      upload unsigned app bundle
```

Release-only packaging must preserve existing package boundary, Rust, GPU, golden, and native-smoke gates.

---

# 7. Verification evidence

P3 implementation baseline was green before merge. Do not reuse that as evidence for G7A release jobs.

G7A requires a fresh CI run from `feature/g7a-release-engineering` covering the new Android/iOS release jobs.

Evidence categories must remain distinct:

```text
semantic/unit tests
package boundary tests
native packaging smoke
unsigned/no-codesign release build
physical-device release smoke
store upload/beta validation
```

Never promote one category as proof of another.

---

# 8. Important files

```text
Release CI
  .github/workflows/ci.yml

Android release config
  android/app/build.gradle.kts
  docs/G7A_ANDROID_SIGNING.md

G7A checklist
  docs/G7A_RELEASE_READINESS.md

Canonical handoff
  docs/PROJECT_HANDOFF.md

Architecture walkthrough
  docs/CODE_WALKTHROUGH.md

App/package architecture
  README.md
  packages/pixelcraft_engine/
  packages/pixelcraft_gpu/
  packages/pixelcraft_editing/
  packages/pixelcraft_film/

Rust authority
  rust/
```

---

# 9. Verification rules

1. Never claim CI/test/device/build/store validation passed unless actually run or explicitly reported.
2. Never commit keystores, signing passwords, private certificates, provisioning profiles, or store credentials.
3. Never ship Android release artifacts signed with the debug keystore.
4. Unsigned Android / no-codesign iOS builds are packaging evidence only, not store-ready signed artifacts.
5. Release engineering must not weaken Rust-authoritative image semantics or GPU fail-closed behavior.
6. Native release configuration changes require CI packaging evidence and later physical-device RC smoke when signed installable artifacts exist.
7. Store-account-dependent tasks remain explicitly BLOCKED until accounts are available.

---

# 10. Current next action

**G7A is ACTIVE on `feature/g7a-release-engineering`.**

Next steps:

```text
1. add/refresh G7A release-readiness and Android signing docs
2. open a new G7A draft PR from post-P3 main
3. let full CI validate android-release and ios-release jobs
4. fix release-only build/link/package regressions without weakening architecture invariants
5. inspect produced release artifacts and record verified ABI/native bundle evidence
6. audit resolved Android SDK/version configuration and iOS deployment/bundle settings
7. begin privacy/permission/Privacy Manifest audit
8. prepare versioning, release notes, store metadata, privacy-policy/support checklist
9. keep G7B tasks marked BLOCKED BY EXTERNAL ACCOUNTS
10. when G7A gates are green, update README/CODE_WALKTHROUGH/handoff with measured evidence before merge
```

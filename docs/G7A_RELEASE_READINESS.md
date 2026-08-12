# G7A Release Engineering / Store Preparation

Status: **ACTIVE**

Branch:

```text
feature/g7a-release-engineering
```

Base:

```text
main @ fb5c05493478eedea7223d8bbf790ea63e175729
```

G7A covers release engineering and store-preparation work that does not require Apple Developer/App Store Connect or Google Play Console accounts.

G7B contains account-dependent signing, beta-distribution, and actual store-submission work and is explicitly blocked until those accounts exist.

## Non-negotiable architecture rules

- Rust remains authoritative for committed edits, recipe/history/checkpoint/recovery, and full-resolution export.
- GPU remains preview-only and fail-closed.
- Release packaging must not change image semantics merely to make a build pass.
- No signing secrets or private credentials enter source control.
- Unsigned/no-codesign output is packaging evidence, not store-readiness evidence.

---

## G7A.0 Baseline

Post-P3 package graph:

```text
App
 ├── pixelcraft_film
 ├── pixelcraft_gpu
 ├── pixelcraft_editing
 └── pixelcraft_engine

pixelcraft_film -> pixelcraft_editing
pixelcraft_gpu  -> pixelcraft_editing
```

Old PR #10 is not mergeable against the current architecture and must not be merged unchanged. G7A recreates only useful release-engineering changes on the post-P3 `main`.

---

## G7A.1 Android production packaging

Current policy:

1. Release build must never use debug signing.
2. `android/key.properties` may configure an explicit release keystore outside git.
3. CI without secrets validates release packaging only.
4. Release APK must contain the Rust native engine.
5. Generated canonical GPU LUT assets must continue to be packaged by the existing build pipeline.

Checklist:

```text
[ ] android-release CI job green
[ ] flutter build apk --release succeeds
[ ] libpixelcraft_engine.so found in release artifact
[ ] Gradle release block does not reference debug signing
[ ] resolved minSdk recorded
[ ] resolved targetSdk recorded
[ ] resolved compileSdk recorded
[ ] packaged ABI set recorded
[ ] release minification/R8 policy reviewed
[ ] versionName/versionCode policy documented
```

Account-dependent items moved to G7B:

```text
[BLOCKED] Play App Signing enrollment
[BLOCKED] signed AAB upload
[BLOCKED] Play Internal Testing
```

---

## G7A.2 iOS production packaging

G7A validates compilation/link/package integrity without production signing:

```bash
flutter build ios --release --no-codesign
```

Checklist:

```text
[ ] ios-release CI job green
[ ] release Runner.app created
[ ] native/Rust integration present
[ ] bundle identifier recorded
[ ] iOS deployment target recorded
[ ] camera/photo usage descriptions audited
[ ] Privacy Manifest / required-reason API audit completed
[ ] version/build policy documented
```

Account-dependent items moved to G7B:

```text
[BLOCKED] distribution certificate/profile
[BLOCKED] signed archive upload
[BLOCKED] TestFlight Internal Testing
```

---

## G7A.3 Privacy / permission / diagnostics audit

Required policy:

```text
No photo pixels in crash diagnostics.
No hidden source/export upload.
No user image content in telemetry.
No signing/store credential in logs or artifacts.
```

Audit:

```text
[ ] Android manifest permissions
[ ] iOS usage descriptions
[ ] dependency Privacy Manifest / required-reason APIs
[ ] recovery/temp-file retention
[ ] share/export path
[ ] diagnostics/log payloads
[ ] privacy policy requirements documented
[ ] Data Safety draft prepared offline
[ ] App Privacy draft prepared offline
```

Submitting Data Safety/App Privacy forms remains G7B because the store accounts do not yet exist.

---

## G7A.4 CI release gates

New jobs:

```text
android-release
  -> flutter build apk --release
  -> inspect libpixelcraft_engine.so
  -> assert no debug signing configuration
  -> upload APK artifact

ios-release
  -> flutter build ios --release --no-codesign
  -> verify Runner.app/native output
  -> upload unsigned app bundle
```

These run alongside existing semantic/package/GPU/golden/native validation and do not replace it.

---

## G7A.5 Versioning and release identity

Prepare and verify:

```text
[ ] current pubspec version recorded
[ ] release version policy decided
[ ] Android applicationId confirmed
[ ] iOS bundle identifier confirmed
[ ] user-facing app name confirmed
[ ] About/Diagnostics version display audited
```

Do not change identifiers casually after store records exist; G7A is the right time to decide them.

---

## G7A.6 Store asset preparation

Can be prepared without accounts:

```text
[ ] app icon final audit
[ ] splash/launch presentation audit
[ ] Android screenshot set plan
[ ] iPhone screenshot set plan
[ ] optional iPad screenshot set plan
[ ] Play feature-graphic source prepared
[ ] short description draft
[ ] full description draft
[ ] keywords/subtitle draft where applicable
[ ] support URL requirement
[ ] privacy policy URL requirement
[ ] release notes template
[ ] content/age-rating answer draft
```

Store copy must not claim unsupported properties such as original EXIF preservation or proprietary third-party film processing reproduced 1:1.

---

## G7A.7 Release candidate QA preparation

Prepare the RC smoke plan now; execute signed-store-delivered portions in G7B.

```text
clean install
launch
permission flows
camera preview
Film switching
capture clean source
Camera -> Editor
representative adjustments
Curve/HSL
Film Profile create/load
Undo/Redo
Apply/Discard
recovery/reopen
JPEG/PNG/WebP export
gallery save
share
background/foreground
terminate/reopen
```

---

## G7B external blockers

Current external dependency:

```text
Apple Developer / App Store Connect account: unavailable
Google Play Console account: unavailable
```

Therefore the following are not G7A completion criteria:

```text
actual TestFlight upload
actual Play Internal Testing upload
production certificate/provisioning validation
Play App Signing enrollment
App Store Connect App Privacy submission
Play Console Data Safety submission
actual store review
```

---

## Current next action

```text
1. open G7A draft PR
2. wait for fresh CI on the release jobs
3. fix any release packaging failures
4. record measured Android SDK/ABI and iOS bundle/deployment evidence
5. start privacy/permission audit
6. update README/CODE_WALKTHROUGH/PROJECT_HANDOFF when G7A evidence is verified
```

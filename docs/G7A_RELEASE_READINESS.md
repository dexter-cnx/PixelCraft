# G7A Release Engineering / Store Preparation

Status: **ACTIVE**

Branch:

```text
feature/g7a-release-engineering
```

Base:

```text
post-P3 main @ fb5c05493478eedea7223d8bbf790ea63e175729
```

G7A covers release engineering and store-preparation work that does not require Apple Developer/App Store Connect or Google Play Console accounts.

G7B contains account-dependent signing, beta-distribution, and store-submission work and is explicitly blocked until those accounts exist.

## Non-negotiable architecture rules

- Rust remains authoritative for committed edits, recipe/history/checkpoint/recovery, and full-resolution export.
- GPU remains preview-only and fail-closed.
- Release packaging must not change image semantics merely to make a build pass.
- No signing secrets or private credentials enter source control.
- Unsigned/no-codesign output is packaging evidence, not store-readiness evidence.

---

## G7A.0 Verified CI baseline

Latest verified release-engineering baseline:

```text
CI run: #211
GitHub Actions run id: 31604232738
HEAD: 043cc3700aedf10cec3f58c22cb0977ce195408b
conclusion: SUCCESS
```

Run #211 passed:

```text
validate
Golden tests + iOS debug packaging smoke
wgpu core Linux / macOS / Windows
Android release artifact
iOS release --no-codesign
```

The release jobs regenerate the Flutter Rust Bridge Dart bindings before building, so clean CI checkouts exercise the same generated-code prerequisite as the normal validation path.

---

## G7A.1 Android production packaging

### Verified release artifact

Run #211 produced:

```text
artifact: pixelcraft-android-release-*
APK: app-release.apk
APK size: ~81.5 MB
artifact zip size: 35,998,416 bytes
artifact SHA-256: 7d426470d48fd4ead710ee642dcede7fbe9b562478e52634edc4d430f662a56e
```

Decoded release-manifest evidence from that APK:

```text
applicationId/package: dev.cnxdev.pixelcraft
versionName: 0.1.0
versionCode: 1
compileSdkVersion: 36
targetSdkVersion: 36
minSdkVersion: 24
```

Packaged Rust ABIs verified in the APK:

```text
arm64-v8a   -> libpixelcraft_engine.so
armeabi-v7a -> libpixelcraft_engine.so
x86_64      -> libpixelcraft_engine.so
```

The release APK also contains the generated Film/Creative GPU LUT assets and parity manifests.

### Signing policy

1. Release builds must never use the Android debug keystore.
2. `android/key.properties` may configure an explicit release keystore outside git.
3. CI without secrets validates release packaging only.
4. Store upload/signing remains G7B.

Run #211 verified that the release Gradle configuration does not reference debug signing.

### Permission audit

App-owned manifest requirements:

```text
CAMERA
WRITE_EXTERNAL_STORAGE only through API 28
camera hardware required=false
```

The camera dependency also contributed `RECORD_AUDIO` to the merged release manifest. PixelCraft's fallback `CameraController` explicitly uses `enableAudio: false`, so G7A now removes that unused permission through the manifest merger. The post-change CI/release artifact must verify it stays absent.

`WRITE_EXTERNAL_STORAGE` is retained only for legacy API <= 28 compatibility and must be reviewed against the gallery-save implementation before any future removal.

### Remaining Android checklist

```text
[x] android-release CI job green
[x] flutter build apk --release succeeds
[x] libpixelcraft_engine.so found in release artifact
[x] Gradle release block does not reference debug signing
[x] resolved minSdk recorded: 24
[x] resolved targetSdk recorded: 36
[x] resolved compileSdk recorded: 36
[x] packaged ABI set recorded
[x] current versionName/versionCode recorded: 0.1.0 / 1
[ ] verify RECORD_AUDIO absent from the new merged release artifact
[ ] release minification/R8 policy reviewed
[ ] final RC versionName/versionCode policy decided
```

Account-dependent items moved to G7B:

```text
[BLOCKED] Play App Signing enrollment
[BLOCKED] signed AAB upload
[BLOCKED] Play Internal Testing
```

---

## G7A.2 iOS production packaging

Run #211 successfully executed:

```bash
flutter build ios --release --no-codesign
```

Verified output:

```text
bundle identifier: dev.cnxdev.pixelcraft
deployment target: iOS 13.0
Runner.app size: 37.7 MB
pixelcraft_engine.framework: present
Film/Creative GPU LUT assets: present
unsigned artifact zip size: 16,679,854 bytes
artifact SHA-256: 501ab348ecdad488fd294c76493da7c1a61e282e0c8b88169b7175977997cd66
```

Current version/build values flow from Flutter:

```text
CFBundleShortVersionString = FLUTTER_BUILD_NAME
CFBundleVersion            = FLUTTER_BUILD_NUMBER
pubspec                    = 0.1.0+1
```

Usage descriptions are present for:

```text
Camera
Photo Library read/select
Photo Library add/save
```

Run #211 also observed dependency Privacy Manifests in the built app for Flutter and several plugins including camera_avfoundation, image_picker_ios, saver_gallery, and share_plus.

Current app source does not yet contain an app-owned `PrivacyInfo.xcprivacy`; G7A must finish the required-reason/API audit before deciding whether one is required for PixelCraft itself.

Known release-tooling debt:

```text
pixelcraft_engine and pixelcraft_gpu still rely on CocoaPods and do not yet support Swift Package Manager.
```

This is not a current release-build blocker, but Flutter reports that lack of SPM support may become an error in a future Flutter release.

### Remaining iOS checklist

```text
[x] ios-release CI job green
[x] release Runner.app created
[x] native/Rust integration present
[x] bundle identifier recorded: dev.cnxdev.pixelcraft
[x] iOS deployment target recorded: 13.0
[x] camera/photo usage descriptions audited
[x] dependency Privacy Manifest presence sampled from built release bundle
[ ] app-owned required-reason API / Privacy Manifest audit completed
[ ] final RC version/build policy decided
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

Current audit state:

```text
[x] Android app manifest inspected
[x] Android merged release manifest inspected
[x] unused RECORD_AUDIO identified and removal committed
[x] iOS usage-description strings inspected
[x] dependency Privacy Manifests observed in release bundle
[ ] verify post-change Android merged manifest
[ ] app-owned iOS required-reason API audit
[ ] recovery/temp-file retention audit
[ ] share/export path audit
[ ] diagnostics/log payload audit
[ ] privacy policy requirements documented
[ ] Data Safety draft prepared offline
[ ] App Privacy draft prepared offline
```

Submitting Data Safety/App Privacy forms remains G7B because the store accounts do not yet exist.

---

## G7A.4 CI release gates

Current jobs:

```text
android-release
  -> flutter pub get
  -> regenerate FRB Dart bridge
  -> flutter build apk --release
  -> inspect libpixelcraft_engine.so
  -> assert no debug signing configuration
  -> upload APK artifact

ios-release
  -> flutter pub get
  -> regenerate FRB Dart bridge
  -> flutter build ios --release --no-codesign
  -> verify Runner.app/native output
  -> upload unsigned app bundle
```

These run alongside semantic/package/GPU/golden/native validation and do not replace it.

---

## G7A.5 Versioning and release identity

Current identity:

```text
app display name: Pixel Craft
pubspec version: 0.1.0+1
Android applicationId: dev.cnxdev.pixelcraft
iOS bundle identifier: dev.cnxdev.pixelcraft
iOS deployment target: 13.0
Android min/target/compile SDK: 24 / 36 / 36
```

Remaining decisions:

```text
[ ] decide first RC marketing version
[ ] decide build-number increment policy
[ ] audit About/Diagnostics version display
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

```text
Apple Developer / App Store Connect account: unavailable
Google Play Console account: unavailable
```

Therefore these are not G7A completion criteria:

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
1. let CI validate the RECORD_AUDIO removal on a fresh release APK
2. inspect the new merged Android manifest and confirm microphone permission is absent
3. continue app/privacy diagnostics + recovery/share/export audit
4. decide version/build-number policy for the first RC
5. prepare store metadata/assets/checklists that do not require accounts
6. refresh README / CODE_WALKTHROUGH / PROJECT_HANDOFF as G7A evidence stabilizes
7. keep PR #18 draft until the G7A checklist is materially complete and latest CI is green
```

# G7A Release Engineering / Store Preparation

Status: **ACTIVE — FINALIZATION**

Branch:

```text
feature/g7a-release-engineering
```

Base:

```text
post-P3 main @ fb5c05493478eedea7223d8bbf790ea63e175729
```

G7A covers release engineering and store-preparation work that does not require Apple Developer/App Store Connect or Google Play Console accounts. G7B contains account-dependent signing, beta distribution, and actual store submission.

## Non-negotiable architecture rules

- Rust remains authoritative for committed edits, recipe/history/checkpoint/recovery, and full-resolution export.
- GPU remains preview-only and fail-closed.
- Release packaging must not change image semantics merely to make a build pass.
- No signing secrets or private credentials enter source control.
- Unsigned/no-codesign output is packaging evidence, not signed-store evidence.

---

## G7A.0 Verified CI baseline

Latest verified implementation baseline before final documentation commits:

```text
CI run: #216
GitHub Actions run id: 31609170884
HEAD: af94739cf546a518bcea1fb917c42cf9df2b6d23
conclusion: SUCCESS
```

Run #216 passed all current jobs:

```text
validate
Golden tests + iOS debug packaging smoke
wgpu core Linux / macOS / Windows
Android release artifact
iOS release --no-codesign
```

It includes the recovery `.tmp` cleanup regression test. A later documentation-only HEAD still requires a fresh green CI before PR #18 is considered merge-ready.

---

## G7A.1 Android production packaging

Verified release identity/evidence:

```text
applicationId/package: dev.cnxdev.pixelcraft
versionName: 0.1.0
versionCode: 1
compileSdkVersion: 36
targetSdkVersion: 36
minSdkVersion: 24
APK size: ~81.5 MB
```

Packaged Rust ABIs:

```text
arm64-v8a   -> libpixelcraft_engine.so
armeabi-v7a -> libpixelcraft_engine.so
x86_64      -> libpixelcraft_engine.so
```

The release APK also contains generated Film/Creative GPU LUT assets and parity manifests.

Signing policy:

1. release builds never use the Android debug keystore;
2. ignored `android/key.properties` may configure an explicit local release keystore;
3. CI without secrets validates unsigned release packaging only;
4. Play App Signing/upload remains G7B.

Permission audit:

```text
CAMERA
WRITE_EXTERNAL_STORAGE only through API 28
camera hardware required=false
```

The camera dependency originally contributed `RECORD_AUDIO`, but PixelCraft's still-camera fallback initializes `CameraController` with `enableAudio: false`. G7A removes that unused permission with a manifest-merger override. The run #214 release artifact was inspected and `RECORD_AUDIO` was absent from the packaged manifest.

Current release Gradle config has no explicit `isMinifyEnabled = true` or resource shrinking. G7A therefore keeps the first RC on the current non-minified policy rather than introducing R8 risk during release hardening. Optimization can be a separately measured follow-up.

Checklist:

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
[x] RECORD_AUDIO absent from post-change release artifact
[x] release minification/R8 policy reviewed: keep current non-minified first-RC policy
```

G7B blockers:

```text
[BLOCKED] Play App Signing enrollment
[BLOCKED] signed AAB upload
[BLOCKED] Play Internal Testing
```

---

## G7A.2 iOS production packaging

Verified command:

```bash
flutter build ios --release --no-codesign
```

Verified output:

```text
bundle identifier: dev.cnxdev.pixelcraft
deployment target: iOS 13.0
Runner.app size: ~37.7 MB
pixelcraft_engine.framework: present
Film/Creative GPU LUT assets: present
```

Version/build values flow from Flutter:

```text
CFBundleShortVersionString = FLUTTER_BUILD_NAME
CFBundleVersion            = FLUTTER_BUILD_NUMBER
pubspec                    = 0.1.0+1
```

Usage descriptions are present for Camera, Photo Library read/select, and Photo Library add/save.

Dependency Privacy Manifests were observed in the built app for Flutter and multiple plugins. PixelCraft source does not currently contain an app-owned `PrivacyInfo.xcprivacy`. G7A deliberately does not invent one without app-owned required-reason evidence; G7B must re-audit the final signed Xcode archive and add an app manifest only when the final archive/API evidence requires it.

Known tooling debt remains that `pixelcraft_engine` and `pixelcraft_gpu` use CocoaPods rather than Swift Package Manager. This is not a current no-codesign release-build blocker.

Checklist:

```text
[x] ios-release CI job green
[x] release Runner.app created
[x] native/Rust integration present
[x] bundle identifier recorded: dev.cnxdev.pixelcraft
[x] iOS deployment target recorded: 13.0
[x] camera/photo usage descriptions audited
[x] dependency Privacy Manifest presence sampled from release bundle
[x] app-owned Privacy Manifest decision recorded: no speculative manifest; re-audit final archive in G7B
```

G7B blockers:

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

Verified repository behavior:

- recovery source bytes + Rust recipe are stored in app-support storage for resume;
- at most three coherent recovery generations are retained;
- obsolete generations are pruned;
- abandoned `.tmp` recovery files are cleaned during load/save;
- Discard removes the recovery directory;
- exported files are created only after explicit export and persist in app documents/gallery as user output;
- sharing is explicit and passes only the exported file to the platform share sheet;
- diagnostics log renderer/profile/sample/error metrics, not user image bytes or live frame buffers;
- current app dependencies contain no analytics, advertising, or remote crash-reporting SDK;
- no app-owned hidden upload path was found in the audited recovery/export/share/diagnostic flow.

Detailed offline store/privacy drafts are in:

```text
docs/G7A_PRIVACY_STORE_DRAFTS.md
```

Audit state:

```text
[x] Android app manifest inspected
[x] Android merged release manifest inspected
[x] unused RECORD_AUDIO removed and verified absent from release APK
[x] iOS usage-description strings inspected
[x] dependency Privacy Manifests observed in release bundle
[x] app-owned Privacy Manifest decision documented
[x] recovery/temp-file retention audit
[x] recovery abandoned-temp cleanup implemented + tested
[x] share/export path audit
[x] diagnostics/log payload audit
[x] privacy policy requirements documented
[x] Data Safety working draft prepared offline
[x] App Privacy working draft prepared offline
```

Submitting store forms remains G7B.

---

## G7A.4 CI release gates

Current release jobs:

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

These supplement rather than replace semantic/package/GPU/golden/native validation.

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

First-RC policy:

```text
marketing version: keep 0.1.0 while pre-1.0 beta/RC work continues
build number: monotonically increment for every externally distributed signed build
store identity: keep dev.cnxdev.pixelcraft unless explicitly changed before store records are created
```

Actual store-distributed build numbers start being enforced in G7B when signing/accounts exist.

---

## G7A.6 Store asset / metadata preparation

Account-independent work still suitable for a follow-up release-content slice:

```text
[ ] app icon final visual audit
[ ] splash/launch presentation audit
[ ] Android screenshot set plan
[ ] iPhone screenshot set plan
[ ] optional iPad screenshot set plan
[ ] Play feature-graphic source
[ ] short description draft
[ ] full description draft
[ ] keywords/subtitle draft where applicable
[ ] support URL
[ ] public privacy policy URL
[ ] release notes template
[ ] content/age-rating answer draft
```

These are content/operational deliverables, not code blockers for merging the G7A release-engineering foundation.

Store copy must not claim unsupported behavior such as original EXIF preservation or proprietary third-party film processing reproduced 1:1.

---

## G7A.7 Release candidate QA preparation

RC smoke plan:

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

Signed/store-delivered execution belongs to G7B. Existing G6 physical-device evidence remains historical reliability evidence and is not promoted as signed-RC evidence.

---

## G7B external blockers

```text
Apple Developer / App Store Connect account: unavailable
Google Play Console account: unavailable
```

Not G7A completion criteria:

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
1. refresh PROJECT_HANDOFF / README / CODE_WALKTHROUGH for G7A finalization
2. update PR #18 summary with run #216 + privacy evidence
3. wait for fresh CI on the final documentation HEAD
4. if latest CI is green and review threads are clear, mark PR #18 Ready for Review
5. merge G7A when approved
6. after merge, audit PR #10 file-by-file; migrate any genuinely missing work, then close PR #10 as superseded while keeping its branch unless explicitly asked to delete it
7. G7B remains blocked until Apple/Google store accounts exist
```

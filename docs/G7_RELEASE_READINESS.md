# G7 Release / Beta / Store Readiness

Status: **IN PROGRESS**
Branch: `feature/g7-release-readiness`
Base: `main` after merged G6 PR #9 (`9106b15adbd78760ecfdac2041eed4fdfd98ff87`)

G7 is a release-hardening milestone. It must not change PixelCraft image semantics merely to make packaging easier. Rust remains authoritative for committed edit semantics, recipe/history/checkpoints/recovery and full-resolution export. GPU paths remain preview accelerators and must fail closed to valid Rust/product state.

## Evidence rules

- Record only builds, tests and device/store checks that were actually run.
- Distinguish buildability, signing readiness, beta readiness and store readiness.
- Never treat a debug-signed artifact as production-ready.
- Never commit signing keys, passwords, provisioning profiles or private certificates.
- Do not claim metadata preservation; current export does not re-attach original EXIF/metadata.
- Crash diagnostics and telemetry must not contain image pixels or user photo content.

---

## G7.0 Transition / release baseline

G6 is merged and closed. G7 starts from merged `main` after PR #9.

Baseline gates remain:

```text
flutter analyze
make test
make golden-test
make rust-fmt
make rust-clippy
make rust-test
make gpu-lut-verify
```

Production build gates added in G7:

```text
flutter build apk --release
flutter build ios --release --no-codesign
```

Current package version from `pubspec.yaml`:

```text
0.1.0+1
```

This is acceptable for G7 development, but release versioning must be finalized before RC/store submission.

### Initial release audit

| Area | Current state | G7 action |
|---|---|---|
| Android application id | `dev.cnxdev.pixelcraft` | keep unless product decision changes |
| Android release signing | previously used debug signing | **fixed in G7 foundation**; release is unsigned unless explicit `android/key.properties` exists |
| Android keystore hygiene | `key.properties`, `*.keystore`, `*.jks` ignored | keep secrets outside git |
| Android native packaging | Rust engine required | CI release artifact inspection added |
| iOS bundle id | `dev.cnxdev.pixelcraft` | verify archive/TestFlight ownership |
| iOS deployment target | 13.0 in Xcode project | verify supported-OS product policy |
| iOS permissions | camera + photo library descriptions present | review wording/store privacy answers |
| App category | Photography | verify App Store metadata |
| CI | analyzer/tests/GPU/G6 characterization/goldens | release build jobs added in G7 |

---

## G7.1 Android production build

### Required behavior

1. Production release artifacts must never use the Android debug keystore.
2. Local/CI release builds may remain unsigned when release secrets are unavailable.
3. Store signing must use an explicit upload/release keystore supplied outside git.
4. The packaged artifact must contain the Rust engine native library for supported ABIs.
5. Canonical GPU LUT assets must still be generated during release packaging.

### Signing contract

Optional local signing file:

```text
android/key.properties
```

Expected keys:

```properties
storePassword=...
keyPassword=...
keyAlias=...
storeFile=...
```

The file and keystore are ignored by git. When `key.properties` is absent, G7 CI builds an unsigned release artifact for packaging verification only.

### Android checks

```text
[ ] flutter build apk --release succeeds in CI
[ ] release APK contains libpixelcraft_engine.so
[ ] release Gradle config does not reference debug signing
[ ] verify minSdk / targetSdk / compileSdk resolved values
[ ] verify Play-supported ABI policy
[ ] verify R8/minification policy before store RC
[ ] create Play upload key / configure secure CI secret path
[ ] build signed AAB for Internal Testing
[ ] install/test release build on physical Android device
```

---

## G7.2 iOS production build

Current inspected project settings include:

```text
PRODUCT_BUNDLE_IDENTIFIER = dev.cnxdev.pixelcraft
IPHONEOS_DEPLOYMENT_TARGET = 13.0
DEVELOPMENT_TEAM = ZTM9BCJPY9
INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.photography
```

Current permission descriptions cover:

- Camera
- Photo Library read
- Photo Library add/save

### iOS checks

```text
[ ] flutter build ios --release --no-codesign succeeds in CI
[ ] Runner.app contains expected native/Rust integration
[ ] archive succeeds with production signing locally/Xcode Cloud/CI signing environment
[ ] App Store distribution certificate/profile is valid
[ ] Bundle ID belongs to the intended App Store Connect app
[ ] deployment target policy is finalized
[ ] Privacy Manifest requirements are audited for app + dependencies
[ ] TestFlight internal build installs and launches on physical device
```

---

## G7.3 Privacy / permissions / diagnostics

PixelCraft edits images locally and uses camera/photo-library access. Store disclosures must match actual behavior.

Required policy:

```text
No photo pixels in crash diagnostics.
No user image content in telemetry.
No hidden upload of source or exported photos.
No recipe/profile content in diagnostics unless explicitly required and documented.
```

Audit:

```text
[ ] Android permissions and Data Safety answers
[ ] iOS usage-description wording
[ ] App Privacy answers
[ ] Privacy Manifest / required-reason APIs from dependencies
[ ] temp/recovery file retention behavior
[ ] share/export data flow
[ ] crash logging payloads
```

---

## G7.4 CI/CD release gates

Existing CI remains authoritative for semantic correctness and regression coverage.

G7 adds:

```text
android-release
  -> flutter build apk --release
  -> inspect packaged native Rust library
  -> verify no debug signing configuration

ios-release
  -> flutter build ios --release --no-codesign
  -> verify generated Runner.app/native output
```

Later store-signing jobs must consume encrypted CI secrets and must never commit credentials.

---

## G7.5 Beta distribution

Target channels:

```text
Android -> Google Play Internal Testing
iOS     -> TestFlight Internal Testing
```

Before first beta:

```text
[ ] finalize version/build numbering policy
[ ] surface app version/build in About/Diagnostics if not already available
[ ] signed Android AAB
[ ] signed iOS archive/IPA
[ ] release notes
[ ] beta tester installation smoke
```

---

## G7.6 Store readiness

Prepare and verify:

```text
[ ] app name / subtitle / short description
[ ] full store description
[ ] app icon
[ ] screenshots
[ ] promotional/feature graphic where required
[ ] privacy policy URL
[ ] support URL
[ ] Data Safety / App Privacy disclosures
[ ] age/content rating
[ ] permission explanations
[ ] release notes
```

Store copy must not claim unsupported behavior such as original EXIF preservation or proprietary third-party film processing reproduced 1:1.

---

## G7.7 Release candidate physical smoke

Create an RC only after production build/signing gates are green.

Recommended RC journey:

```text
clean install
-> launch
-> permission flows
-> camera preview
-> film preview switching
-> capture clean source
-> Camera -> Editor
-> representative G5 adjustments
-> Curve/HSL
-> Film Profile create/load
-> Undo/Redo
-> Apply/Discard
-> recovery/reopen
-> JPEG/PNG/WebP export
-> gallery save
-> share
-> background/foreground
-> terminate/reopen
```

RC smoke is a release-product gate. It does not replace G6 soak/performance evidence unless a regression requires repeating G6 characterization.

---

## Current next action

1. Let CI validate the new Android/iOS release-build jobs on the G7 PR head.
2. Fix any release-only compile/link/package failures without weakening architecture invariants.
3. Record resolved Android min/target/compile SDK and ABI contents from the built release artifact.
4. Verify the iOS no-codesign release bundle and deployment/signing settings.
5. Add secure signed-build instructions for Android and iOS.
6. Begin privacy/permission manifest audit.

G7 is **not** closed until signed internal-beta artifacts and release-candidate physical smoke are verified.

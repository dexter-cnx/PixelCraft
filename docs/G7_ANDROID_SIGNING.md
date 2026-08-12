# G7 Android Release Signing

PixelCraft must never use the Android debug keystore for a production artifact.

## Local signing

Create an upload/release keystore outside the repository and create:

```text
android/key.properties
```

with:

```properties
storePassword=<store password>
keyPassword=<key password>
keyAlias=<alias>
storeFile=<absolute or android-relative path to keystore>
```

`android/key.properties`, `*.keystore` and `*.jks` are ignored by git.

When `android/key.properties` is present, `android/app/build.gradle.kts` configures the release signing config from it. When it is absent, release builds are intentionally unsigned for CI/package verification.

## Store artifact

For Google Play Internal Testing / production, prefer an Android App Bundle:

```bash
flutter clean
flutter pub get
flutter build appbundle --release
```

Before upload, verify:

```text
- expected application id: dev.cnxdev.pixelcraft
- expected versionName/versionCode
- release signing certificate is the intended upload certificate
- Rust native library is packaged for the supported ABI policy
- generated GPU LUT assets are present
```

Do not place passwords, keystores, base64-encoded private keys or `key.properties` in source control.

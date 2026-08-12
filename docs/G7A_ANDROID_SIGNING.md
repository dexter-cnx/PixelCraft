# G7A Android Release Signing

PixelCraft must never use the Android debug keystore for a production artifact.

## Current G7A policy

- source control contains no release keystore or password;
- `android/key.properties` is optional local/CI input;
- without it, release packaging validation may build an unsigned artifact;
- with it, Gradle configures the explicit release signing config;
- Google Play App Signing enrollment belongs to G7B and is blocked until a Play Console account exists.

## Local signing file

Create the keystore outside source control, then create:

```text
android/key.properties
```

Example:

```properties
storePassword=<store password>
keyPassword=<key password>
keyAlias=<alias>
storeFile=<absolute or android-relative path to keystore>
```

Never commit `key.properties`, `*.jks`, `*.keystore`, passwords, or base64 private keys.

## Release artifacts

G7A CI validates unsigned release packaging with:

```bash
flutter build apk --release
```

This is packaging evidence only. It is not evidence of Play readiness or production signing.

Once G7B is unblocked, the intended Play artifact is:

```bash
flutter build appbundle --release
```

Before any store upload verify:

```text
applicationId = dev.cnxdev.pixelcraft
expected versionName / versionCode
intended upload certificate
supported ABI policy
libpixelcraft_engine.so packaged
generated GPU LUT assets packaged
no debug signing configuration
```

## Account-dependent G7B steps

Blocked until Google Play Console exists:

```text
create Play app
create/enroll upload key
configure Play App Signing
secure CI signing secret path
build signed AAB
upload to Internal Testing
install and smoke-test Play-delivered build
```

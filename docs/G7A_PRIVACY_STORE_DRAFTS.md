# G7A Privacy / Store Form Drafts

Status: **PREPARED OFFLINE — NOT SUBMITTED**

This document captures PixelCraft privacy/store-answer evidence that can be prepared before Apple Developer / App Store Connect and Google Play Console accounts exist.

It is not a substitute for the final store forms. G7B must re-check these answers against the exact signed release candidate and the store wording shown at submission time.

## Product data-flow baseline

PixelCraft is designed as an offline-first image editor.

Current app-owned behavior:

- imported/captured source images are processed locally;
- Rust owns committed edit semantics and full-resolution export;
- GPU paths are preview-only;
- recovery state is stored locally in app-support storage;
- exports are written only after an explicit export action;
- gallery save is explicit product behavior;
- sharing is initiated by the user and passes the selected exported file to the platform share sheet;
- no analytics, advertising, telemetry, or remote crash-reporting SDK is declared in the app dependency set;
- diagnostics expose renderer/profile/sample/error metrics only; no image bytes or live camera frame buffers are logged or sent through Dart diagnostics.

## Recovery / temporary data

`EditorSessionStore` stores the original image bytes plus Rust recipe data in the app-support directory so an interrupted editing session can be resumed.

Retention policy in the current implementation:

- at most three coherent recovery generations are retained;
- old unreferenced source/recipe generations are pruned;
- abandoned `.tmp` files are cleaned during recovery load/save;
- user-triggered Discard calls `clear()` and removes the entire recovery directory.

Recovery files are internal application state, not user-facing exports.

## Export / share

`ExportFileService` writes a user-requested export under the app documents directory and, on mobile platforms, attempts to save the same rendered bytes to the gallery.

The export remains local until the user explicitly invokes platform sharing. The share action passes only that exported file plus the text `Edited with PixelCraft` to the system share sheet.

There is no hidden source-image upload or automatic background sharing path in the current app code.

## Android permission draft

Current release permission intent:

```text
CAMERA
WRITE_EXTERNAL_STORAGE only through API 28
```

`RECORD_AUDIO` is explicitly removed from the merged app manifest because PixelCraft's still-camera fallback initializes `CameraController` with `enableAudio: false`.

The camera hardware feature is optional (`required=false`).

Before G7B submission, validate the signed AAB's final merged manifest again.

## iOS usage-description draft

Current user-visible permissions:

- Camera: capture a photo for local editing.
- Photo Library read/select: choose an existing image for editing.
- Photo Library add/save: save an exported image.

Dependency Privacy Manifests are present in the unsigned release bundle for Flutter and multiple plugins. PixelCraft does not currently ship an app-owned `PrivacyInfo.xcprivacy`; do not invent one. Re-evaluate app-owned required-reason API usage from the final Xcode archive before G7B submission.

## Google Play Data Safety working draft

Based only on the current repository behavior:

- PixelCraft does not intentionally transmit user photos to a PixelCraft-operated server.
- No advertising SDK is present.
- No analytics SDK is present.
- No remote crash-reporting SDK is present.
- Photo/media access is used to import/save user-selected image content.
- Camera access is used for capture/live preview.
- User-initiated sharing is handled by the operating-system share sheet and the destination chosen by the user.

G7B must map this evidence to the exact Play Console questions and definitions; do not mechanically answer store fields from this draft.

## App Store App Privacy working draft

Based only on the current repository behavior, PixelCraft does not intentionally collect image content for developer analytics, advertising, tracking, or developer-operated cloud processing.

Photo/camera content is processed locally and may leave the device only through an explicit user-directed export/share destination.

G7B must re-check third-party SDK manifests and Apple's exact definitions against the signed archive before submitting App Privacy answers.

## Privacy policy requirements

The public privacy policy prepared for store submission should state at minimum:

1. PixelCraft's primary image processing occurs locally on the device.
2. The app needs Camera and Photo Library access only for capture/import/save features.
3. Recovery copies of source bytes and edit recipes may be retained in private app storage so an interrupted edit can be resumed.
4. Recovery data is removed when the user discards the recoverable session and is pruned by the app's retention logic.
5. Exported files persist in app documents/gallery until removed by the user or operating system.
6. Sharing occurs only when the user invokes Share and is then handled by the selected platform destination.
7. The current release does not include PixelCraft-operated analytics, advertising, or remote crash-reporting collection.
8. Store form answers may be updated if future SDKs or cloud features change the data flow.

## G7B re-verification checklist

```text
[ ] inspect final signed Android AAB merged permissions
[ ] inspect final signed iOS archive Privacy Manifests
[ ] confirm no new analytics/crash/ads/network SDK was introduced
[ ] confirm recovery/export/share behavior is unchanged
[ ] map evidence to current Play Data Safety wording
[ ] map evidence to current App Store App Privacy wording
[ ] publish privacy policy URL
[ ] submit store forms only after the checks above
```

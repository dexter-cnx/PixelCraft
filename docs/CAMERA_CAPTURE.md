# Camera Capture

`feature/camera-capture` adds photo capture as an input path into the existing Pixel Craft editor.

## Scope

The first camera-capture iteration deliberately uses the platform camera UI exposed by `image_picker` rather than embedding a live camera preview inside Flutter. This keeps capture isolated from the Rust editing pipeline and preserves the existing editor/session model.

```text
Home
  -> Add Photo
      -> Take a photo
          -> platform camera UI
          -> XFile bytes
          -> EditorScreen
          -> reduced editor preview + Rust edit recipe
          -> full-resolution replay on export
      -> Choose from gallery
          -> existing gallery import path
```

The rear camera is preferred when the platform camera UI supports that hint. Captured bytes are passed directly to `EditorScreen`; Pixel Craft does not upload the captured image.

## Platform configuration

- Android: `image_picker` uses the platform capture activity; no additional camera manifest permission is added by Pixel Craft for this flow.
- iOS: `NSCameraUsageDescription` is declared in `ios/Runner/Info.plist`.

## Validation

Run the host-side checks:

```bash
flutter analyze
flutter test test/state
flutter test test/ui --exclude-tags=golden
make golden-update
make golden-test
```

Then validate capture on a physical device:

```bash
flutter run -d <device-id>
```

From Home, choose **Add Photo -> Take a photo**, capture an image, accept it, confirm the editor opens, make an edit, export, then return Home and confirm session recovery still works.

The Home golden is expected to change because the primary action is now `Add Photo` and the introduction copy mentions capture.

## Future camera work

An in-app live camera surface with real-time Film Profile preview is intentionally out of scope for this iteration. That would require a dedicated camera pipeline, frame throttling/backpressure, lifecycle handling, orientation mapping, and likely GPU-backed LUT rendering rather than the still-image capture path implemented here.

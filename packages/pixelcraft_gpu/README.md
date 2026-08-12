# pixelcraft_gpu

`pixelcraft_gpu` is PixelCraft's internal Flutter plugin for **preview-only GPU acceleration**.

It provides the Dart control plane plus native Android/iOS runtime used by camera and editor preview paths. It does **not** own committed edit semantics and it must never become the final-render source of truth.

## Core contract

```text
Rust = authoritative semantics / recipe / history / checkpoint / export
GPU  = interactive preview only
Flutter = UI / control / presentation
```

If an operation graph cannot be represented faithfully on the GPU, PixelCraft must fall back to a valid Rust/product path rather than silently reordering or approximating edits.

## Package responsibilities

The package contains:

- native GPU capability/control bridges
- camera preview bridges
- editor preview bridges
- GPU editor render-plan representation
- GPU draft-session lifecycle support
- diagnostics / parity / frame-pacing bridges
- Android OpenGL ES + Camera2 runtime
- iOS Metal + AVFoundation runtime

The package is internal to the monorepo:

```yaml
publish_to: none
```

## Dart layer

Public package exports include the reusable preview/control-plane APIs such as:

```text
android_gpu_camera_bridge.dart
android_gpu_camera_preview.dart
gpu_editor_diagnostics_bridge.dart
gpu_editor_draft_session.dart
gpu_editor_preview_bridge.dart
gpu_editor_render_plan.dart
gpu_frame_pacing_bridge.dart
ios_gpu_camera_preview.dart
ios_gpu_editor_preview.dart
native_gpu_camera_bridge.dart
```

Protocol constants remain internal unless they are intentionally part of the package API.

Root `lib/gpu` compatibility exports may remain temporarily while the monorepo migration continues.

## Android runtime

The Android implementation lives under:

```text
packages/pixelcraft_gpu/android/src/main/kotlin/
```

The plugin owns registration for:

- GPU preview method channels
- Camera2 permission handling
- renderer session registry
- Android PlatformView registration
- OpenGL ES preview runtime

Eligible camera path:

```text
Camera2
 -> SurfaceTexture / OES
 -> OpenGL ES Film/Creative preview
 -> Android PlatformView
```

The plugin uses its own Android namespace (`dev.pixelcraft.gpu`) so it does not collide with the application namespace.

## iOS runtime

The iOS implementation lives under:

```text
packages/pixelcraft_gpu/ios/Classes/
```

The plugin registers:

- camera preview runtime
- editor preview runtime
- frame-pacing diagnostics
- editor verification/parity diagnostics

Eligible camera path:

```text
AVCaptureVideoDataOutput
 -> CVPixelBuffer
 -> CVMetalTextureCache
 -> Metal Film/Creative preview
 -> UIKit PlatformView
```

The app's `AppDelegate` should remain an app shell; native GPU runtime registration belongs to this plugin.

## Camera safety invariant

Live camera buffers must remain native:

```text
Camera frame
  X MethodChannel
  X Flutter Rust Bridge
  ✓ native Camera2/AVFoundation -> GPU renderer
```

Dart transports only small control/state messages such as renderer IDs, lens identifiers, profile IDs, strength, viewport state and capture file paths.

Capture remains clean; the active Film preview is not baked into the captured source by the GPU path.

## Editor preview semantics

`GpuEditorRenderPlan` represents only the active draft operations that can be reproduced faithfully by the native renderer.

Typical verified native stages include combinations of:

```text
Creative compute/LUT
Gaussian Blur
Sharpen
Brightness
Contrast
Saturation
Film LUT
```

A plan must fail closed when:

- Rust operation order differs from GPU stage order
- the native runtime cannot represent an operation
- LUT slot requirements conflict
- transform/state rules make the draft unsafe to reproduce
- native renderer initialization/runtime fails

The valid Rust preview remains available in those cases.

## Canonical LUT ownership

Film/Creative LUT assets consumed by native GPU code are generated from Rust-owned canonical data.

```text
Rust canonical Film/Creative data
        ↓
33^3 LUT / generated atlas
   ↙             ↘
Rust renderer    native GPU preview
```

This prevents native platforms from defining independent color semantics.

## App-side adapters still remaining

P1 deliberately did not move app-owned editing-domain models into this package.

For example, renderer/capability adapters that consume `EditGraphDocument` / `EditNodeType` remain app-side until P2 extracts those pure models into `packages/pixelcraft_editing`.

Do **not** solve this by importing root app source from `pixelcraft_gpu`.

Forbidden direction:

```text
packages/pixelcraft_gpu -> lib/...
```

Target direction after P2:

```text
App
 ├── pixelcraft_editing
 └── pixelcraft_gpu
          ↓
   pixelcraft_engine
```

## Validation

Relevant automated gates include:

```bash
flutter analyze
flutter test test/gpu
make gpu-lut-verify
make verify-native
```

CI additionally performs:

- GPU plan/session tests
- Android native packaging smoke
- iOS native packaging smoke
- golden/widget regression checks

P1 was closed after CI passed and physical smoke testing passed on both iOS and Android.

## Failure policy

Native preview failure must never corrupt product state.

Expected behavior:

```text
GPU unavailable / unsupported / failed
        ↓
drop native preview session
        ↓
keep or restore valid Rust/product preview
        ↓
continue editing safely
```

## Status

P1 package extraction is complete and merged. `pixelcraft_gpu` is now the canonical home for reusable Dart GPU control-plane code and Android/iOS native preview runtimes.

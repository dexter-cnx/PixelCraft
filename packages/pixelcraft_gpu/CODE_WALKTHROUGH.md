# pixelcraft_gpu Code Walkthrough

`pixelcraft_gpu` is PixelCraft's preview-only Flutter plugin for native GPU preview infrastructure.

Its purpose is low-latency interaction. It is never the authoritative source for committed edit semantics or exported pixels.

## 1. Responsibility boundary

Canonical ownership:

```text
Flutter app
   ↓ control/session intent
pixelcraft_gpu
   ├── Android: Camera2 / OpenGL ES camera preview
   └── iOS: AVFoundation / Metal camera + editor preview

Rust engine
   ↑ authoritative semantic commit
Flutter app
```

`pixelcraft_gpu` owns:

- app-independent Dart GPU transport/session infrastructure
- GPU editor render-plan transport contracts
- native camera control bridges
- Android Camera2/OpenGL ES camera runtime
- iOS AVFoundation/Metal camera and editor runtime
- plugin registration
- diagnostics and frame-pacing bridges

`pixelcraft_gpu` does not own:

- committed edit semantics
- Rust recipe/history/checkpoint state
- recovery policy
- full-resolution export
- final image pixels
- app navigation/product state
- current app-level LUT asset generation/packaging

## 2. Core architectural invariant

The package follows one hard rule:

```text
GPU = interactive preview
Rust = authority
```

A successful GPU preview does not replace a Rust commit. A native GPU failure must not create a new semantic state.

## 3. Package layout

Conceptually:

```text
packages/pixelcraft_gpu/
├── lib/
├── android/
│   └── src/main/kotlin/
├── ios/
│   └── Classes/
├── pubspec.yaml
├── README.md
└── CODE_WALKTHROUGH.md
```

The package is internal to the PixelCraft monorepo:

```yaml
publish_to: none
```

## 4. Dart control plane

The Dart layer transports small control/session messages and preview state.

Typical responsibilities include:

```text
camera permission request
available lens identifiers
camera switching
clean capture path
GPU capability/protocol probe
editor render-plan transport
preview session generation
renderer lifecycle
frame pacing / diagnostics
```

Large live frame buffers do not travel through Dart MethodChannel or Flutter Rust Bridge.

That is intentional: MethodChannel is a control plane, not the video pipeline.

## 5. Editor GPU render plan

`GpuEditorRenderPlan` represents a native editor preview plan only when the requested operations are faithfully representable.

Current execution scope matters:

```text
authoritative recipe / active draft
   ↓ app-side adapter
GpuEditorRenderPlan
   ↓
pixelcraft_gpu editor transport
   ↓
iOS Metal editor preview
```

At present, the implemented native editor channel/view exists on **iOS Metal only**.

Android's plugin currently registers `GpuPreviewChannel` and the camera PlatformView/runtime. It does **not** implement the iOS-equivalent `gpu_editor_preview_v1` / `GpuEditorPreviewPlugin` editor channel/view.

Therefore do not describe `GpuEditorRenderPlan` as executing through Android OpenGL ES today.

The app-side adapter remains important because some editing-domain types are still app-owned until P2 extracts them.

`pixelcraft_gpu` must not import PixelCraft app source merely to understand those types.

If an operation graph cannot be represented faithfully, or if a native editor backend is unavailable:

```text
native GPU plan = rejected / unavailable
        ↓
keep valid Rust preview
```

Never silently reorder semantic operations just to make a shader pipeline fit.

## 6. Editor preview lifecycle

On a platform with a verified native editor preview implementation, a typical editor interaction looks like:

```text
slider drag starts
   ↓
create/activate GPU draft session
   ↓
render low-latency native preview
   ↓
slider release
   ↓
Flutter commits semantic value to Rust
   ↓
Rust produces authoritative preview/recipe state
   ↓
GPU overlay/session is updated or invalidated
```

On Android today, absence of the editor-native path means the product remains on the valid Rust/editor path rather than attempting a nonexistent OpenGL ES editor renderer.

GPU session generations exist to prevent stale async/native work from winning over newer editor state.

Important invalidation events include:

```text
Rust checkpoint changed
editor entered busy state
active tool changed
renderer dropped
new activation superseded older activation
```

## 7. Android native path

The current Android native GPU path is camera-focused:

```text
Camera2
   ↓
SurfaceTexture / external OES texture
   ↓
OpenGL ES renderer
   ↓
canonical Film LUT / verified camera shader stages
   ↓
Flutter PlatformView
```

The plugin owns Android registration rather than `MainActivity`.

Conceptually:

```text
GeneratedPluginRegistrant
   ↓
PixelcraftGpuPlugin
   ↓ FlutterPlugin + ActivityAware
GpuPreviewChannel / camera PlatformView registration
   ↓
Camera2 + GLES runtime
```

`ActivityAware` is required because camera permission/activity lifecycle belongs to the native plugin integration.

The Android plugin uses its own Gradle namespace:

```text
dev.pixelcraft.gpu
```

It must not reuse the app namespace.

### Important limitation

Android currently has **no native editor GPU channel/view implementation** corresponding to the iOS Metal editor path.

That limitation is intentional to document explicitly so future work does not mistake camera OpenGL ES support for editor OpenGL ES support.

## 8. Android capture contract

Camera preview may be GPU-processed, but capture remains clean.

Control flow:

```text
Dart requests capture
   ↓ small MethodChannel message
native camera captures source JPEG
   ↓
Dart receives only file path / small metadata
```

The filtered preview frame itself is not passed back as capture data.

## 9. iOS native path

Eligible camera preview path:

```text
AVCaptureVideoDataOutput
   ↓
CVPixelBuffer
   ↓
CVMetalTextureCache
   ↓
Metal renderer
   ↓
canonical Film LUT / verified stages
   ↓
Flutter PlatformView
```

The implemented native editor GPU preview path also lives on iOS Metal.

Production Metal/AVFoundation implementation lives in:

```text
packages/pixelcraft_gpu/ios/Classes/
```

The Runner `AppDelegate` should remain an app shell and must not become the owner of GPU production classes.

## 10. iOS plugin registration

Conceptually:

```text
GeneratedPluginRegistrant
   ↓
pixelcraft_gpu registrar
   ↓
camera preview channels/platform views
editor preview channel/plugin
Metal renderer registry
diagnostics
```

P1 moved production registration out of `AppDelegate` into the plugin.

Any temporary app-project compatibility stubs exist only to satisfy stale Xcode file references and must not contain production GPU implementation.

## 11. Canonical LUT semantics vs packaging ownership

Film/Creative LUT semantics originate from Rust-owned canonical data.

Conceptual semantic flow:

```text
Rust canonical Film/Creative data
   ↓
materialized 33^3 LUT
   ├── Rust renderer
   └── generated native GPU assets
```

However, current native asset **generation and packaging remain app-owned**:

```text
Android app build
  android/app/build.gradle.kts
  GenerateGpuLutAssetsTask
        ↓
  generated LUT assets consumed by plugin runtime

Runner / Xcode build phase
        ↓
  generated/copy LUT assets consumed by iOS plugin runtime
```

`packages/pixelcraft_gpu/android/build.gradle` and `packages/pixelcraft_gpu/ios/pixelcraft_gpu.podspec` do not yet provide equivalent self-contained generated LUT resource packaging.

Therefore the correct ownership statement today is:

```text
LUT semantic authority = Rust
LUT asset packaging    = app build integration
LUT runtime consumer   = pixelcraft_gpu
```

Do not describe generated native LUT assets as package-owned until their generation/resource packaging is actually moved into `pixelcraft_gpu`.

## 12. Capability and fallback model

GPU availability is a product optimization, not a correctness requirement.

Examples of fallback reasons:

```text
protocol mismatch
backend unavailable
missing native asset
shader self-test failure
unsupported LUT capability
blacklisted GPU
renderer init failure
runtime renderer failure
unsupported edit order
platform has no native editor backend
```

All of these should fail closed to the valid Rust/product path.

The user should never receive an incorrectly reordered or partially interpreted edit merely because GPU preview was unavailable.

## 13. Diagnostics

The package includes diagnostics used to verify native preview behavior, such as:

```text
renderer identity/runtime error forwarding
frame pacing
Metal reference/parity harness
latency/verification hooks
GPU LUT parity support
```

Diagnostics are evidence for preview correctness/performance; they do not redefine editing semantics.

## 14. Tests

Important host-side coverage includes GPU plan/session and bridge tests.

Examples:

```text
test/gpu/gpu_editor_render_plan_test.dart
test/gpu/gpu_editor_draft_session_test.dart
test/state/native_gpu_preview_bridge_test.dart
test/state/native_gpu_camera_bridge_test.dart
test/state/android_gpu_camera_bridge_test.dart
```

Coverage checks:

- stale activation protection
- deterministic fallback
- protocol parsing
- small camera control messages
- clean capture-path contract
- faithful operation ordering
- LUT-slot conflicts
- renderer/runtime error forwarding

These host-side editor plan/session tests do not imply that every platform has a native editor renderer implementation.

## 15. Native validation

P1 is not considered valid based on Dart tests alone.

Required gates include:

```text
Flutter analyze
GPU plan/session tests
state/widget tests
GPU LUT parity
Android full-app/plugin packaging smoke
iOS full-app/plugin packaging smoke
physical-device smoke on Android
physical-device smoke on iOS
```

P1 passed these gates before merge.

The Android physical/device evidence validates the Android camera/plugin extraction and native packaging topology. It is not evidence of an Android editor GPU channel/view.

## 16. How to extend GPU support safely

For every new edit effect or backend:

### Step 1 — define semantics in Rust

Specify and test the authoritative operation first.

### Step 2 — determine native representability

Ask whether the target backend can reproduce the operation faithfully and in the correct order.

For Android editor GPU support specifically, this means first implementing an actual editor channel/view/backend; the existing camera GLES path is not sufficient.

### Step 3 — add parity evidence

Do not enable the GPU path merely because a visually similar shader exists.

### Step 4 — fail closed

If unsupported, keep Rust preview behavior instead of approximating silently.

## 17. What should not move into this package

Do not move code here merely because it mentions “GPU”.

Keep these outside unless their dependencies are made app-independent:

```text
app navigation
EditorController
product state
app-owned EditGraph types
Film Profile persistence
recovery/session store
Rust semantic recipe ownership
export pipeline
```

P1 intentionally left GPU renderer/capability adapters app-side where they still depend on app-owned edit-domain types.

P2 is the appropriate stage to extract those pure editing contracts.

## 18. Architectural invariant

The most important invariant is:

```text
pixelcraft_gpu = low-latency native preview implementation
Rust           = committed image authority
```

Platform support must be stated precisely:

```text
Android = native GPU camera preview
 iOS    = native GPU camera + editor preview
```

If a future change makes `pixelcraft_gpu` the only place where an edit's meaning exists, the architecture has regressed.

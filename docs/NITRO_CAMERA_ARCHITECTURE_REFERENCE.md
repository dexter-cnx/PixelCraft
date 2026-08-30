# Nitro Camera Architecture Reference

Status: **FUTURE / REFERENCE ONLY / DO NOT ADD DEPENDENCY YET**

Reference package: `nitro_camera` on pub.dev.

This document records architectural ideas worth applying to PixelCraft without replacing the current camera implementation or weakening existing PixelCraft invariants.

## Why this matters

PixelCraft's product direction depends on a responsive camera experience, continuous realtime Film/Filter/Adjust preview, and a low-latency path between camera capture, GPU preview, and authoritative Rust rendering.

The useful lesson from `nitro_camera` is not "replace PixelCraft camera with this package". The useful lesson is to formalize camera-session, capability, frame-delivery, lens-selection, diagnostics, and low-copy boundaries so PixelCraft can improve performance without coupling product architecture to a young third-party package.

## Existing PixelCraft invariants remain authoritative

The following rules are unchanged:

1. Rust owns committed edits and full-resolution render/export.
2. GPU rendering is preview-only.
3. Camera preview never replaces the clean capture source.
4. Live camera buffers must not cross MethodChannel/FRB as a continuous stream.
5. Canonical Film/Creative LUT data remains Rust-owned.
6. Native/GPU failure fails closed to a valid product state.
7. Do not casually replace the current mobile Metal/OpenGL ES runtime with wgpu.

Any experiment inspired by Nitro Camera must fit these contracts rather than bypass them.

---

# A. Architecture ideas to adopt

## A1. Explicit 60 FPS preview target

Treat 60 FPS as a first-class camera-preview capability rather than an incidental device behavior.

The camera layer should negotiate and expose the actual resolved preview configuration, including:

- selected camera device / physical lens;
- preview resolution;
- pixel format;
- requested FPS;
- resolved FPS / FPS range;
- stabilization mode;
- HDR / low-light capability where applicable.

60 FPS is a target, not a promise on every device. Unsupported combinations must downgrade deterministically and expose the resolved result for diagnostics.

## A2. Live controls must avoid camera-session restart when possible

Operations such as these should use the cheapest supported live update path:

- zoom;
- focus;
- exposure compensation;
- ISO/exposure controls when the platform permits live mutation;
- white balance;
- flash/torch state;
- stabilization;
- other sensor/session parameters that do not require full reconfiguration.

Design rule:

```text
If a control can be changed without rebuilding the camera session,
do not rebuild the camera session.
```

This reduces preview flicker, latency spikes, dropped frames, and visible camera interruption during tactile slider/dial interaction.

## A3. Latest-frame processing / backpressure

Realtime preview processing should favor the newest available frame rather than accumulating a FIFO backlog.

Preferred mental model:

```text
Camera producer
    ↓
latest-frame slot
    ↓
GPU/native processor
    ↓
preview surface
```

Avoid an unbounded or latency-growing model:

```text
Camera producer
    ↓
Queue<Frame>
    ↓
process every historical frame
```

When the processor cannot keep up with the producer, stale preview frames should be dropped according to an explicit policy. Realtime editing needs the freshest visual result more than it needs every intermediate camera frame.

Metrics should distinguish:

- produced frames;
- processed frames;
- presented frames;
- dropped/stale frames;
- end-to-end preview latency.

## A4. Low-copy / zero-copy boundary as a performance goal

Avoid pipelines that repeatedly materialize full camera buffers through Dart and then copy again into Rust/native/GPU memory.

Target architecture:

```text
Camera native buffer
    ↓
normalized native/GPU frame handle
    ↓
Film / Filter / Adjust preview pipeline
    ↓
preview surface
```

The exact implementation can differ by platform, but ownership and lifetime must be explicit.

Do not introduce a continuous high-bandwidth `Camera frame -> MethodChannel/FRB -> Dart -> Rust` transport merely to achieve this goal; that would violate an existing PixelCraft invariant.

## A5. Camera capability model

Introduce/retain an internal camera capability model independent of UI widgets and independent of any one camera package.

Conceptual model:

```text
PixelCameraDevice
 ├─ stable device identity
 ├─ logical / physical camera relationship
 ├─ lens class
 ├─ zoom range
 ├─ focus capabilities
 ├─ exposure capabilities
 ├─ supported preview formats
 ├─ supported capture formats
 ├─ FPS ranges
 ├─ stabilization modes
 ├─ HDR / low-light capabilities
 └─ RAW capability identity (without activating RAW development)
```

Camera selection and format negotiation belong in the camera/backend layer, not scattered through Flutter UI code.

## A6. Physical-lens-aware selection

Represent physical camera choices such as:

```text
Ultra-wide
Wide
Telephoto
```

separately from arbitrary digital zoom.

UI may present familiar controls such as:

```text
0.5x   1x   2x/3x
```

but the camera backend should know whether the requested transition is:

- a physical lens switch;
- logical multi-camera behavior provided by the OS;
- digital crop/zoom.

Do not model the entire camera system as one anonymous `0.5x..10x` slider.

## A7. Resolved configuration diagnostics

Expose the actual resolved camera configuration after platform negotiation.

A debug/performance overlay should eventually be able to show data such as:

```text
Camera: Wide
Capture: 4032x3024 JPEG
Preview: 1920x1080 @ 60
Format: YUV420 / platform equivalent
GPU preview: 59.8 fps
Processing: 4.2 ms
Dropped: 1.8%
```

This is particularly useful for physical calibration evidence, device-specific debugging, and G6-style reliability/performance validation.

## A8. Preview-surface abstraction

Keep the camera/session contract separate from the Flutter/native preview presentation mechanism.

Conceptually:

```text
PreviewSurface
 ├─ Flutter texture path
 ├─ native/platform surface path
 └─ GPU/Impeller-compatible path where justified
```

The exact supported backends should remain evidence-driven. Do not add backends merely for abstraction purity.

## A9. Declarative lifecycle + imperative low-latency controls

A useful API shape is to separate:

- declarative camera lifecycle/configuration; and
- imperative latency-sensitive operations.

Conceptually:

```dart
PixelCameraView(
  configuration: config,
  isActive: true,
  onReady: ...,
)
```

with operations such as:

```dart
controller.setExposure(...);
controller.setZoom(...);
controller.focus(...);
controller.capture(...);
```

Do not make the widget tree itself the canonical camera/session state machine.

## A10. One parameter model for preview and final render

Realtime preview and authoritative export must use the same semantic Film/Filter/Adjust parameter set even when the render implementations differ.

Conceptual flow:

```text
Camera Frame
    ↓
Normalized Preview Frame
    ↓
Film / Filter / Adjust parameters
    ↓
GPU preview implementation
```

while capture remains:

```text
Clean captured source
    + same semantic recipe
    ↓
Rust authoritative full-resolution render
```

This protects PixelCraft from `preview != export` drift while preserving the rule that preview pixels are never the final authoritative output.

---

# B. Execution phases

## Phase A — architecture hardening, no new dependency

Can be done when it aligns with an active camera/performance milestone:

- formalize latest-frame/backpressure policy;
- make 60 FPS an explicit negotiation target where supported;
- strengthen camera capability/device/format model;
- expose resolved camera configuration;
- keep live control changes from restarting the session when native APIs allow it;
- distinguish physical lens selection from digital zoom;
- add useful camera/GPU diagnostics and dropped-frame/latency metrics.

**Phase A must not add `nitro_camera` as a runtime dependency.**

## Phase B — isolated performance prototype

Only after Phase A is sufficiently understood:

- prototype low-copy or zero-copy native/GPU frame boundaries;
- benchmark current PixelCraft path against candidate alternatives;
- evaluate texture/native/GPU preview surfaces where technically justified;
- measure frame production, processing, presentation, drops, and latency;
- validate on physical Android and iPhone hardware.

The prototype must preserve clean-capture authority and Rust final-render authority.

## Phase C — optional Nitro Camera spike

Create a dedicated isolated spike branch only if the package/API is mature enough to justify evaluation.

The spike should answer measurable questions rather than attempt a product migration:

- Does it materially improve preview FPS stability?
- Does it reduce camera-control latency?
- Does it reduce frame copies or CPU overhead?
- Does it improve physical lens/format handling?
- Does it preserve PixelCraft capture semantics and GPU/Rust boundaries?
- Is lifecycle behavior stable on PixelCraft's supported Android/iOS device matrix?

Only consider an adapter/backend after benchmark and device evidence shows a clear benefit.

**Do not replace the current camera implementation merely because the spike works.**

---

# C. Explicit non-goals

This reference does not activate:

- a `nitro_camera` dependency;
- camera implementation replacement;
- QR/barcode features;
- ML Kit face detection;
- pharmacode features;
- real RAW development;
- MobileSAM;
- generic plugin runtime;
- external-edit transport;
- Dart 3.13 RecordUse/native tree-shaking;
- a switch from PixelCraft's current Metal/OpenGL ES strategy to wgpu.

---

# D. Priority

Highest-value ideas for PixelCraft:

1. **latest-frame/backpressure policy**;
2. **live control updates without unnecessary session restart**;
3. **low-copy camera -> GPU boundary**;
4. **explicit 60 FPS capability/negotiation**;
5. **resolved configuration + latency/drop diagnostics**;
6. **physical-lens-aware camera model**.

These should be treated as camera/GPU architecture guidance and folded into future implementation work when they improve an already-approved milestone rather than creating a parallel rewrite.
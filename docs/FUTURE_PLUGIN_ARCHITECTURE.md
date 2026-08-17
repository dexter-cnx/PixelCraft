# PixelCraft Future Plugin Architecture

Status: **FUTURE / DEFERRED / DO NOT START NOW**

This document records a future plugin direction for PixelCraft / Dextryx Pixels. It is intentionally architectural planning only. It must not interrupt PF2, PF3, PF4, release stabilization, or current physical-device validation.

## 1. Goal

Introduce a capability-based plugin architecture that can isolate optional image-processing, AI, input, output, beauty/retouch, geometry, and content extensions from PixelCraft core behavior.

The first reference implementation should be **MobileSAM ONNX segmentation** because it has a clear boundary:

```text
image / preview source
      -> segmentation capability
      -> mask result
```

The editor/camera must depend on a segmentation capability contract, not on MobileSAM-specific implementation details.

The architecture must also remain broad enough for later capabilities such as face landmarks, face parsing, skin retouch, face reshape, depth-aware effects, denoise, enhancement, and other ideas that are not yet known when the first plugin API is implemented.

## 2. Architectural rule

Use a **capability-based plugin system**, not an unrestricted plugin model that can reach arbitrary app internals.

Target dependency direction:

```text
Plugin implementation
       ↓
PixelCraft Plugin API
       ↓
PixelCraft core/application contracts
```

Never invert this so PixelCraft core imports or depends directly on MobileSAM or any specific beauty/AI provider.

A future package topology may look like:

```text
packages/
├─ dxtr_pixs_plugin_api/
├─ dxtr_pixs_imaging/
├─ dxtr_pixs_gpu/
└─ plugins/
   ├─ dxtr_pixs_mobilesam/
   └─ future optional capability plugins/
```

Exact package names and extraction timing remain subject to a later ownership audit.

## 3. Plugin categories

The API should be designed so these capability families can exist without requiring all of them to be implemented immediately:

```text
AI
├─ segmentation
├─ face detection
├─ face landmarks
├─ face parsing
├─ object detection
├─ depth
├─ denoise
└─ enhancement

Image Processing
├─ filter
├─ film
├─ adjustment
├─ effect
├─ retouch
└─ geometry / reshape

Beauty / Portrait
├─ skin smoothing
├─ blemish reduction
├─ texture preservation
├─ face slimming
├─ jaw reshape
├─ chin reshape
└─ future portrait-local operations

Input
├─ camera
├─ importer
└─ external source

Output
├─ exporter
└─ share target

Content
├─ film pack
├─ LUT pack
├─ recipe pack
├─ AI model pack
└─ capability/model configuration pack
```

Film/Filter are currently core product behavior and must **not** be moved to plugins merely because the future API can represent them. That migration would require a separate justified plan.

The category list is intentionally extensible. New future ideas should normally be introduced as new capability contracts or versions rather than by exposing unrestricted access to PixelCraft internals.

## 4. Plugin types

Distinguish two classes of extension:

### Native/code plugin

Compiled and shipped with the application build.

Examples:

- MobileSAM runtime integration
- platform-native AI backend
- face landmark/face parsing provider
- skin-retouch or face-reshape engine
- native exporter
- future optional image-processing engine

On mobile, do not assume arbitrary downloadable executable/native code is an acceptable plugin mechanism.

### Content/model plugin

Potentially downloadable after installation when product/platform policy permits.

Examples:

- ONNX model package
- face/portrait model package
- Film pack
- LUT pack
- Film Recipe pack
- metadata/configuration pack

The code/runtime that loads these packages remains part of the shipped application.

## 5. Runtime contracts

A future base plugin contract should provide at least:

```text
stable plugin id
human-readable name
plugin version
plugin API version
supported platforms
capabilities
initialize(context)
dispose()
```

A central Plugin Registry / Capability Registry resolves plugins by capability rather than implementation name.

Example conceptual lookup:

```text
request: subject segmentation
registry -> best available compatible segmentation provider

request: face landmarks
registry -> best available compatible face-landmark provider

request: skin smoothing
registry -> best available compatible retouch provider
```

The editor should never require the implementation name `MobileSAM`, a particular face model, or a particular runtime to perform a capability.

## 6. MobileSAM ONNX reference plugin

MobileSAM should be the first real reference plugin after the plugin foundation is intentionally activated.

Candidate capabilities:

```text
ai.segmentation.subject
ai.segmentation.point
ai.segmentation.box
```

Conceptual flow:

```text
Editor / Mask tool
      ↓
Segmentation capability
      ↓
Plugin Registry
      ↓
MobileSAM plugin
      ↓
platform backend / ONNX execution provider
      ↓
MaskHandle + confidence/metadata
```

The plugin must remain optional. Missing/unsupported MobileSAM must degrade to a valid product state rather than break the editor.

MobileSAM is a reference implementation for the plugin architecture, not the definition of the architecture itself.

## 7. Face / Beauty / Geometry future capabilities

The plugin architecture must explicitly support portrait-oriented operations without requiring those features to be part of PixelCraft core.

Candidate capability names may include:

```text
ai.face_detection
ai.face_landmarks
ai.face_parsing

beauty.skin_smooth
beauty.blemish_reduction
beauty.texture_preservation
beauty.face_reshape

geometry.face_slim
geometry.jaw_reshape
geometry.chin_reshape
```

These names are planning-level examples. Final capability naming and contracts must be frozen only when PLUG-P0 is activated.

### Skin retouch concept

A future skin-retouch plugin may combine:

```text
face detection / landmarks
        ↓
face parsing / skin mask
        ↓
edge-aware skin smoothing
blemish reduction
texture preservation
        ↓
localized non-destructive result
```

The implementation should preserve eyes, eyebrows, lips, hair boundaries, and important texture rather than applying whole-image blur.

### Face reshape concept

A future face-reshape plugin may combine:

```text
face detection
      ↓
face landmarks / mesh
      ↓
localized geometry warp
      ↓
face slim / jaw / chin controls
```

The geometry stage does not have to be a neural-network operation. ML may locate landmarks while the actual deformation can be performed by deterministic native/GPU mesh or warp code.

Background geometry should remain stable wherever practical; face reshape must not casually bend unrelated image regions.

### Processing authority

Beauty and geometry plugins remain optional processing capabilities. They must not bypass PixelCraft's normal non-destructive edit semantics.

Conceptually:

```text
plugin preview result
      ↓
user commits parameter/configuration
      ↓
PixelCraft authoritative recipe/edit state
      ↓
full-resolution final render
```

A plugin may provide detection data, masks, landmarks, deformation fields, or an operation implementation, but committed edit state and final-render policy remain governed by PixelCraft's authoritative processing architecture.

### Realtime camera direction

Editor support should be easier to validate first. Realtime Camera use may be added later only after performance is demonstrated.

A future camera path may use:

```text
periodic face/landmark detection
        +
tracking/coalescing between detections
        +
lightweight GPU/native retouch or warp
        ↓
interactive preview
```

Do not require expensive full model inference on every raw camera frame merely to claim realtime support.

Final capture/export must still render from the authoritative source and committed settings rather than baking camera-preview pixels.

## 8. Image, mask, landmark, and geometry boundary

Do not design the API around repeatedly copying full-resolution images through Dart `Uint8List` or MethodChannel boundaries.

Future contracts should prefer opaque resource abstractions such as:

```text
ImageHandle
MaskHandle
PreviewHandle
LandmarkHandle / LandmarkSet
GeometryFieldHandle / MeshHandle
```

The implementation may later map these to native buffers, textures, files, shared memory, compact typed data, or other platform-appropriate resources.

Requirements:

1. avoid unnecessary large-image copies;
2. preserve PixelCraft's existing rule that camera pixel buffers do not cross MethodChannel/FRB casually;
3. make cancellation possible;
4. support latest-request-wins behavior for interactive segmentation, retouch, and reshape;
5. prevent stale inference/landmark results from replacing newer state;
6. keep AI output non-authoritative until explicitly committed through normal PixelCraft edit semantics;
7. allow preview-quality and final-render-quality execution to differ without changing the semantic parameter contract;
8. allow plugins to share reusable detection results where safe, so multiple portrait capabilities do not needlessly re-detect the same face.

## 9. UI extension points

Plugin engine capability and plugin UI contribution should be separate concepts.

Potential extension points may include:

```text
editor.mask_tools
editor.effects
editor.retouch_tools
editor.geometry_tools
camera.secondary_tools
camera.beauty_tools
import.sources
export.targets
settings.plugins
```

A plugin contribution must not be allowed to arbitrarily mutate unrelated application state.

Examples:

```text
Mask
├─ Brush
├─ Gradient
└─ Subject AI      # appears only if capability exists

Retouch
├─ Skin Smooth
├─ Blemish
└─ Texture

Face
├─ Slim
├─ Jaw
└─ Chin
```

If a plugin or required capability is unavailable, its contribution disappears or becomes explicitly unavailable without destabilizing the editor/camera.

## 10. Platform targets

The plugin framework should target all primary PixelCraft platforms while allowing each plugin to declare its own support matrix.

Planned framework targets:

| Platform | Plugin framework | Native/AI plugin | Content/model plugin |
|---|---|---|---|
| Android | first-class | yes | yes |
| iOS | first-class | yes | yes |
| macOS | first-class | yes | yes |
| Windows | first-class | yes | yes |
| Linux | first-class | yes | yes |
| Web | optional/subset | backend-dependent | yes where feasible |

Policy:

- Android, iOS, macOS, Windows, and Linux are first-class plugin-framework targets.
- Web is an optional capability target and must not reduce native functionality to the lowest common denominator.
- A plugin may support only a subset of platforms.
- Unsupported platforms must fail capability discovery cleanly.
- Capability availability may also depend on device performance, memory, accelerator support, or model availability, not only operating system.

## 11. Backend direction

Do not freeze a specific execution provider in the generic plugin API.

MobileSAM, face-analysis, retouch, or enhancement implementations may select platform-appropriate execution providers internally.

For MobileSAM, an example direction remains:

```text
Android
ONNX Runtime
  -> accelerator/provider when validated
  -> CPU fallback

iOS / macOS
ONNX Runtime / native integration
  -> validated accelerator/provider
  -> CPU fallback

Windows
ONNX Runtime
  -> validated GPU/provider
  -> CPU fallback

Linux
ONNX Runtime
  -> validated GPU/provider where available
  -> CPU fallback

Web
optional WASM/WebGPU-compatible backend
```

Other plugins may use a different validated implementation such as a platform-native vision API, another portable inference runtime, or deterministic GPU/native processing behind the same capability contract.

Exact providers must be benchmarked and validated when implementation begins; this document does not freeze provider choices.

## 12. Versioning

Plugin compatibility must be explicit.

At minimum maintain separate concepts for:

```text
plugin implementation version
plugin API version
capability contract version where necessary
model/content package version
```

Major incompatible API changes must not silently load incompatible plugins.

New future capabilities should not force unrelated existing plugins to update unless the shared base contract actually changes.

## 13. Resource lifecycle

The future host should define ownership for:

```text
model loading/unloading
native session lifetime
GPU/accelerator resources
shared face/landmark analysis cache
memory pressure handling
background/foreground transitions
cancellation
timeouts
error reporting
plugin disposal
```

Large AI models must not become permanently resident merely because a plugin exists. Resource policy should allow lazy initialization and eviction where appropriate.

Multiple plugins should be able to reuse compatible analysis results where practical, while cache identity/versioning must prevent stale landmarks, masks, or geometry from being applied to a changed source/frame.

## 14. Proposed future phases

Do not schedule these phases until explicitly activated.

```text
PLUG-P0  Plugin API / Registry / lifecycle / versioning
PLUG-P1  MobileSAM ONNX reference plugin
PLUG-P2  Editor Mask integration and capability fallback
PLUG-P3  Diagnostics, resource lifecycle, cancellation, stale-result protection
PLUG-P4  Cross-platform desktop validation
PLUG-P5  Optional Web feasibility investigation
PLUG-P6  Content/model plugin experiment, e.g. Film/LUT/model pack
PLUG-P7  Face-analysis capability experiment: detection/landmarks/parsing
PLUG-P8  Editor portrait retouch experiment: skin smoothing/blemish/texture
PLUG-P9  Editor geometry experiment: face slim/jaw/chin reshape
PLUG-P10 Realtime Camera beauty feasibility only after editor quality/performance gates pass
```

PLUG-P7 through PLUG-P10 are future experiments, not committed product milestones.

Third-party downloadable executable plugins, a marketplace, arbitrary scripting, or unrestricted plugin access are **not** part of the initial plan.

## 15. Extensibility guardrails

The plugin architecture should be future-friendly without becoming an unrestricted framework.

Rules:

1. resolve by capability, not plugin class/name;
2. allow multiple providers for one capability;
3. allow one plugin to provide multiple related capabilities;
4. keep execution backend private to the plugin;
5. keep UI contribution separate from engine capability;
6. keep authoritative edit semantics outside arbitrary plugin UI code;
7. version contracts explicitly;
8. fail unavailable capabilities cleanly;
9. do not freeze the API around MobileSAM-specific request/response types;
10. do not freeze the API around current beauty ideas either;
11. prefer small composable contracts over one giant `ImagePlugin` interface;
12. do not pre-build speculative capabilities before a real use case exists.

The goal is to make future ideas addable through bounded contracts, not to predict every possible plugin today.

## 16. Activation gates

Before PLUG-P0 starts, confirm:

1. current PF camera/editor flow is stable;
2. plugin work does not block PF2/PF3/PF4;
3. package ownership boundaries have been reviewed;
4. image/mask/landmark/geometry handle contracts avoid unnecessary copies;
5. MobileSAM model/runtime licensing and redistribution terms are verified;
6. any later face/beauty model licenses and redistribution terms are separately verified before those capabilities are activated;
7. supported execution providers are benchmarked on representative physical devices;
8. memory and thermal budgets are defined;
9. failure/fallback behavior is documented;
10. plugin API versioning policy is agreed;
11. non-destructive recipe semantics for geometry/retouch are defined before those plugins can commit edits;
12. preview-vs-final quality contracts are explicit;
13. realtime Camera beauty work has separate frame-time/thermal gates;
14. the work is explicitly activated in `docs/PROJECT_HANDOFF.md`.

## 17. Current decision

```text
Plugin architecture: FUTURE / DEFERRED
MobileSAM ONNX: reference plugin candidate
Face / Beauty / Geometry capabilities: FUTURE CANDIDATES
Skin smoothing / face slimming: PLANNING ONLY
Implementation: DO NOT START NOW
Current priority: continue active PF roadmap and physical-device validation
```

This document preserves the architecture direction without changing current runtime behavior or current milestone priority.

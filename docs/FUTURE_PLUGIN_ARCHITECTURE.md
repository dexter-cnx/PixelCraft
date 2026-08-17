# PixelCraft Future Plugin Architecture

Status: **FUTURE / DEFERRED / DO NOT START NOW**

This document records a future plugin direction for PixelCraft / Dextryx Pixels. It is intentionally architectural planning only. It must not interrupt PF2, PF3, PF4, release stabilization, or current physical-device validation.

## 1. Goal

Introduce a capability-based plugin architecture that can isolate optional image-processing, AI, input, output, and content extensions from PixelCraft core behavior.

The first reference implementation should be **MobileSAM ONNX segmentation** because it has a clear boundary:

```text
image / preview source
      -> segmentation capability
      -> mask result
```

The editor/camera must depend on a segmentation capability contract, not on MobileSAM-specific implementation details.

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

Never invert this so PixelCraft core imports or depends directly on MobileSAM.

A future package topology may look like:

```text
packages/
├─ dxtr_pixs_plugin_api/
├─ dxtr_pixs_imaging/
├─ dxtr_pixs_gpu/
└─ plugins/
   └─ dxtr_pixs_mobilesam/
```

Exact package names and extraction timing remain subject to a later ownership audit.

## 3. Plugin categories

The API should be designed so these capability families can exist without requiring all of them to be implemented immediately:

```text
AI
├─ segmentation
├─ object detection
├─ depth
├─ denoise
└─ enhancement

Image Processing
├─ filter
├─ film
├─ adjustment
└─ effect

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
└─ AI model pack
```

Film/Filter are currently core product behavior and must **not** be moved to plugins merely because the future API can represent them. That migration would require a separate justified plan.

## 4. Plugin types

Distinguish two classes of extension:

### Native/code plugin

Compiled and shipped with the application build.

Examples:

- MobileSAM runtime integration
- platform-native AI backend
- native exporter
- future optional image-processing engine

On mobile, do not assume arbitrary downloadable executable/native code is an acceptable plugin mechanism.

### Content/model plugin

Potentially downloadable after installation when product/platform policy permits.

Examples:

- ONNX model package
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
```

The editor should never require the implementation name `MobileSAM` to perform subject segmentation.

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

## 7. Image and mask boundary

Do not design the API around repeatedly copying full-resolution images through Dart `Uint8List` or MethodChannel boundaries.

Future contracts should prefer opaque resource abstractions such as:

```text
ImageHandle
MaskHandle
PreviewHandle
```

The implementation may later map these to native buffers, textures, files, shared memory, or other platform-appropriate resources.

Requirements:

1. avoid unnecessary large-image copies;
2. preserve PixelCraft's existing rule that camera pixel buffers do not cross MethodChannel/FRB casually;
3. make cancellation possible;
4. support latest-request-wins behavior for interactive segmentation;
5. prevent stale inference results from replacing newer masks;
6. keep AI output non-authoritative until explicitly committed through normal PixelCraft edit semantics.

## 8. UI extension points

Plugin engine capability and plugin UI contribution should be separate concepts.

Potential extension points may include:

```text
editor.mask_tools
editor.effects
camera.secondary_tools
import.sources
export.targets
settings.plugins
```

A plugin contribution must not be allowed to arbitrarily mutate unrelated application state.

Example:

```text
Mask
├─ Brush
├─ Gradient
└─ Subject AI      # appears only if capability exists
```

If the plugin is unavailable, its contribution disappears or becomes explicitly unavailable without destabilizing the editor.

## 9. Platform targets

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

## 10. MobileSAM backend direction

Do not freeze a specific execution provider in the generic plugin API.

The MobileSAM implementation may select platform-appropriate execution providers internally, for example:

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

Exact providers must be benchmarked and validated when implementation begins; this document does not freeze provider choices.

## 11. Versioning

Plugin compatibility must be explicit.

At minimum maintain separate concepts for:

```text
plugin implementation version
plugin API version
capability contract version where necessary
model/content package version
```

Major incompatible API changes must not silently load incompatible plugins.

## 12. Resource lifecycle

The future host should define ownership for:

```text
model loading/unloading
native session lifetime
GPU/accelerator resources
memory pressure handling
background/foreground transitions
cancellation
timeouts
error reporting
plugin disposal
```

Large AI models must not become permanently resident merely because a plugin exists. Resource policy should allow lazy initialization and eviction where appropriate.

## 13. Proposed future phases

Do not schedule these phases until explicitly activated.

```text
PLUG-P0  Plugin API / Registry / lifecycle / versioning
PLUG-P1  MobileSAM ONNX reference plugin
PLUG-P2  Editor Mask integration and capability fallback
PLUG-P3  Diagnostics, resource lifecycle, cancellation, stale-result protection
PLUG-P4  Cross-platform desktop validation
PLUG-P5  Optional Web feasibility investigation
PLUG-P6  Content/model plugin experiment, e.g. Film/LUT/model pack
```

Third-party downloadable executable plugins, a marketplace, arbitrary scripting, or unrestricted plugin access are **not** part of the initial plan.

## 14. Activation gates

Before PLUG-P0 starts, confirm:

1. current PF camera/editor flow is stable;
2. plugin work does not block PF2/PF3/PF4;
3. package ownership boundaries have been reviewed;
4. the image/mask handle contract is defined without unnecessary copies;
5. MobileSAM model/runtime licensing and redistribution terms are verified;
6. supported execution providers are benchmarked on representative physical devices;
7. memory and thermal budgets are defined;
8. failure/fallback behavior is documented;
9. plugin API versioning policy is agreed;
10. the work is explicitly activated in `docs/PROJECT_HANDOFF.md`.

## 15. Current decision

```text
Plugin architecture: FUTURE / DEFERRED
MobileSAM ONNX: reference plugin candidate
Implementation: DO NOT START NOW
Current priority: continue active PF roadmap and physical-device validation
```

This document preserves the architecture direction without changing current runtime behavior or current milestone priority.

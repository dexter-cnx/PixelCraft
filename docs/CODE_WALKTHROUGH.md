# PixelCraft Code Walkthrough

เอกสารนี้อธิบาย architecture ปัจจุบันของ PixelCraft หลัง G6 reliability closure และหลัง P0/P1 package extraction ถูก merge แล้ว

สถานะหลัก ณ 2026-08-12:

```text
G1  Camera GPU Preview                          CLOSED
G2  Editor GPU Preview Foundation               CLOSED
G3  Production Rendering Pipeline               CLOSED
G4  Product Editor UX / Session Workflow        CLOSED
G5  Editing Feature Completeness                CLOSED / VERIFIED
G6  Reliability / Performance / Device Matrix   CLOSED / VERIFIED
P0  Extract pixelcraft_engine                   CLOSED / MERGED
P1  Extract pixelcraft_gpu                      CLOSED / MERGED
P2  Extract pure editing models/semantics       NEXT
G7  Release / Beta / Store Readiness            PRESERVED / TO REBASE
```

> Rust เป็น authoritative source สำหรับ semantic edits, recipe, history, checkpoint, recovery และ full-resolution export. Flutter เป็น UI/control/presentation plane. Native GPU เป็น faithful low-latency preview path เท่านั้น

---

# 1. Canonical architecture

```text
Camera / imported image
        ↓
clean source image
        ↓
Flutter product / control state
        ↓
interactive GPU preview where faithfully representable
        ↓ gesture release / command
Rust semantic edit graph / recipe
        ↓
authoritative reduced preview + history + checkpoint
        ↓
full-resolution Rust replay/export
```

Hard contracts:

1. Rust owns committed edit semantics.
2. GPU preview never becomes final-render authority.
3. Camera Film is preview-only; captured source remains clean.
4. Live camera frames never cross Dart MethodChannel or FRB.
5. Film/Creative LUT data is generated from Rust-owned canonical data.
6. Unsupported GPU order or native failure falls back to valid Rust/product state.
7. Flutter presentation state must not become a parallel semantic recipe.
8. Film Profiles are reusable configuration data, not Editor session state or captured GPU pixels.
9. New effects are defined and tested in Rust first; GPU support is optional and must be faithful.

---

# 2. Package-oriented monorepo direction

After P0/P1:

```text
PixelCraft/
├── apps/
│   └── pixelcraft/                # target app shell
├── packages/
│   ├── pixelcraft_engine/         # Rust FFI/native build integration
│   ├── pixelcraft_gpu/            # preview-only GPU control plane/runtime
│   ├── pixelcraft_editing/        # P2 target
│   └── pixelcraft_film/           # later film/profile package target
├── rust/                           # authoritative engine
└── docs/
```

Dependency direction target:

```text
App
 ├── pixelcraft_film
 ├── pixelcraft_editing
 └── pixelcraft_gpu
        \       /
      pixelcraft_engine
           |
          Rust
```

No package may depend back on root app source.

---

# 3. App startup and Home

Entry point:

```text
lib/main.dart
```

Startup flow:

```text
WidgetsFlutterBinding
 -> platform/error policy
 -> ProviderScope
 -> Rust bridge initialization
 -> HomeScreen
```

Home routes users into Film Camera, system camera, gallery, bundled sample, Film Profile management and recoverable editor sessions.

Recovery remains explicit:

```text
Resume last edit
[Discard] [Resume]
```

Resume restores original source bytes plus the authoritative Rust recipe.

---

# 4. pixelcraft_engine — P0

Package:

```text
packages/pixelcraft_engine/
```

Purpose:

```text
Flutter app
   ↓
pixelcraft_engine
   ↓ FRB / CargoKit / native packaging
rust/
```

It owns integration glue, not edit semantics.

Authoritative Rust files remain:

```text
rust/src/api.rs
rust/src/engine.rs
rust/src/filters.rs
rust/src/advanced_filters.rs
```

P0 moved the FRB/CargoKit Flutter FFI plugin boundary out of the old root builder layout and made `packages/pixelcraft_engine` the canonical native engine package.

Important invariant:

```text
pixelcraft_engine X app source dependency
```

See `packages/pixelcraft_engine/README.md`.

---

# 5. Rust image engine and recipe

Flutter adapter remains app-side for now:

```text
lib/core/image_engine.dart
```

Rust retains:

- untouched source bytes
- reduced editor preview
- Apply checkpoint preview
- complete operation list
- cursor
- checkpoint cursor
- undo/redo state

Recipe model:

```text
operations = [ ... semantic edits ... ]
cursor
checkpoint_cursor
```

Active draft:

```text
operations[checkpoint_cursor .. cursor]
```

Apply promotes the current draft into the checkpoint boundary. Full-resolution replay is deferred to Export.

---

# 6. Editor adjustment catalog

Central metadata:

```text
lib/state/editor_adjustment_catalog.dart
```

`EditorAdjustmentSpec` defines:

```text
id
label
min
max
neutral
group
unit
gpuPreview
```

Current control families include Tone, Color, Texture, Curve and HSL-based adjustments.

The `gpuPreview` flag is a semantic gate, not merely a performance hint. If a control lacks a verified faithful native implementation, its authoritative visible result is committed through Rust instead of an approximate shader.

---

# 7. EditorController

Primary controller:

```text
lib/state/editor_controller.dart
```

It projects authoritative engine state into Flutter:

- preview/checkpoint bytes
- histogram
- selected tool
- adjustment memories
- Creative selection/intensity
- Film selection/strength
- processing state
- cursor / operation count
- undo / redo capability

Typical adjustment flow:

```text
slider drag
  -> GPU-only draft when faithfully representable

slider release
  -> semantic commit/replace in Rust
  -> authoritative Rust preview
  -> recovery persistence
```

Tool switching does not implicitly Apply or Discard the active draft.

---

# 8. pixelcraft_gpu — P1

Package:

```text
packages/pixelcraft_gpu/
```

P1 moved reusable GPU control-plane and native runtime code into a dedicated Flutter plugin.

The package now owns:

- camera/editor GPU bridges
- editor render-plan and draft-session support
- diagnostics/frame pacing bridges
- Android OpenGL ES + Camera2 runtime
- iOS Metal + AVFoundation runtime
- native plugin registration

The package does not own edit semantics.

```text
GPU = preview only
Rust = authority
```

See `packages/pixelcraft_gpu/README.md`.

---

# 9. Android GPU runtime

Native implementation:

```text
packages/pixelcraft_gpu/android/src/main/kotlin/
```

Eligible camera flow:

```text
Camera2
 -> SurfaceTexture / OES
 -> OpenGL ES canonical Film/Creative processing
 -> Android PlatformView
```

Plugin responsibilities include renderer sessions, method channels, camera permission handling and PlatformView registration.

The plugin Android namespace is intentionally separate from the app namespace:

```text
plugin: dev.pixelcraft.gpu
app:    dev.pixelcraft.pixelcraft
```

This prevents manifest namespace collisions.

---

# 10. iOS GPU runtime

Native implementation:

```text
packages/pixelcraft_gpu/ios/Classes/
```

Eligible camera flow:

```text
AVCaptureVideoDataOutput
 -> CVPixelBuffer
 -> CVMetalTextureCache
 -> Metal canonical Film/Creative processing
 -> UIKit PlatformView
```

The package owns camera/editor GPU registration plus frame-pacing and verification diagnostics.

`AppDelegate` remains an app shell rather than the owner of GPU runtime code.

---

# 11. Camera safety model

Live camera buffers remain native:

```text
Camera frame
  X Dart MethodChannel
  X Flutter Rust Bridge
  ✓ native camera API -> native GPU renderer
```

Dart transports only compact control data such as renderer IDs, profile IDs, lens identifiers, viewport state, strength values and capture file paths.

Film Camera preview never bakes the selected Film into the clean capture source.

---

# 12. GPU Editor render planning

Reusable render-plan code now lives in `pixelcraft_gpu`.

The native plan is created only if active draft operations are faithfully representable in the verified GPU stage order.

Typical native stages:

```text
optional Creative compute/LUT
 -> Gaussian Blur
 -> Sharpen
 -> Brightness
 -> Contrast
 -> Saturation
 -> optional final LUT
```

Fail-closed cases include:

- operation order mismatch
- unsupported operations
- LUT slot conflict
- transform/state conflict
- renderer initialization/runtime failure

The valid Rust preview remains available in all such cases.

---

# 13. App-side GPU adapters still remaining

Some files remain app-side because they depend on app-owned editing-domain models such as:

```text
EditGraphDocument
EditNodeType
```

P1 deliberately did not pull those models into `pixelcraft_gpu`, because that would create the forbidden direction:

```text
packages/pixelcraft_gpu -> lib/...
```

P2 should extract those pure models into:

```text
packages/pixelcraft_editing
```

After P2, `GpuPreviewRenderer` / capability adapters can become thinner and package-safe.

---

# 14. Recovery / Reset / History

Recovery store:

```text
lib/core/editor_session_store.dart
```

Generation-based atomic publishing stores source + recipe and writes the manifest last.

Load validates:

- recipe bounds
- source fingerprint
- generation coherence

If the newest generation is corrupt or incomplete, recovery can fall back to an older coherent generation.

Undo/Redo remain Rust operations.

Reset rewrites only active draft operations after the checkpoint boundary and restores the result through Rust.

---

# 15. Export

Export flow:

```text
untouched original source
 -> Rust decode
 -> replay complete authoritative recipe
 -> encode PNG / JPEG / WEBP
 -> gallery/app backup
 -> optional Share
```

Native GPU preview pixels are never export input.

---

# 16. Film Profiles

Film Profile V1 stores reusable configuration such as:

- identity/name/description
- origin
- optional base Film
- strength
- normalized parameters
- tags
- schema/engine compatibility

It deliberately does not store:

- source image
- per-image crop/transform state
- Editor history
- checkpoint cursor
- captured GPU pixels

Import mapping reports:

```text
exact
approximated
unsupported
```

Unsupported fields must never disappear silently.

---

# 17. Canonical Film / Creative LUT architecture

Rust-owned Film data:

```text
rust/film_profiles/*/look.json
```

Generation flow:

```text
Rust canonical look data
 -> canonical 33^3 LUT / atlas
      -> Rust renderer
      -> generated native GPU assets
```

Built-in Film IDs include:

```text
provia_inspired
velvia_inspired
astia_inspired
e100_inspired
ektar_inspired
chrome64_inspired
```

Creative LUT data follows the same authority principle.

---

# 18. G6 reliability closure

G6 is closed and verified.

Coverage included:

- host baseline
- image-size characterization up to the configured 12/24/48MP matrix where hardware permitted
- recovery/failure injection
- lifecycle and long-session validation
- GPU/LUT parity checks
- Android/iOS device smoke
- manual physical validation

The G6 contract is reliability evidence, not a change in authority: Rust remains the source of committed semantics and GPU remains preview-only.

Primary docs:

```text
docs/G6_RELIABILITY_MATRIX.md
docs/G6_DEVICE_MANUAL_CHECKLIST.md
```

---

# 19. Validation layers after P1

Host / Flutter:

```bash
flutter analyze
flutter test test/state
flutter test test/gpu
flutter test test/ui --exclude-tags=golden
```

Rust:

```bash
cargo fmt --manifest-path rust/Cargo.toml --all -- --check
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml
```

GPU LUT:

```bash
make gpu-lut-verify
```

Native packaging:

```bash
make verify-native
```

CI gates now include Android and iOS native packaging smoke in addition to Flutter/Rust/GPU/golden checks.

P1 was closed only after automated CI passed and physical smoke passed on both iOS and Android.

---

# 20. Important files after P0/P1

```text
Startup
  lib/main.dart

Editor UI/state
  lib/ui/screens/editor_screen.dart
  lib/state/editor_controller.dart
  lib/state/editor_recipe_summary.dart
  lib/state/editor_adjustment_catalog.dart

Recovery
  lib/core/editor_session_store.dart

App-side Rust adapter
  lib/core/image_engine.dart

App-side GPU adapters pending P2
  lib/gpu/gpu_preview_renderer.dart
  lib/gpu/gpu_preview_capability.dart

GPU package
  packages/pixelcraft_gpu/lib/
  packages/pixelcraft_gpu/android/src/main/kotlin/
  packages/pixelcraft_gpu/ios/Classes/

Engine integration package
  packages/pixelcraft_engine/

Rust authority
  rust/src/engine.rs
  rust/src/api.rs
  rust/src/filters.rs
  rust/src/advanced_filters.rs
```

---

# 21. Current continuation point

P0 and P1 are **CLOSED / MERGED**.

Next architecture task:

```text
P2 — extract pure editing models / semantics into packages/pixelcraft_editing
```

Primary P2 objective:

```text
move EditGraphDocument / EditNodeType and related pure contracts
out of app source
        ↓
make GPU renderer/capability adapters depend on package-owned editing models
        ↓
remove remaining package-boundary coupling
```

G7 release-readiness work is preserved separately and should be rebased/recreated against the updated package architecture rather than merged blindly from its older base.

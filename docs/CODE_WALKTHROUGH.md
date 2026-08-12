# PixelCraft Code Walkthrough

เอกสารนี้อธิบาย architecture ปัจจุบันของ PixelCraft หลัง G6 และการแยก package P0/P1 เสร็จแล้ว

สถานะ ณ 2026-08-12:

```text
G1  Camera GPU Preview                          CLOSED
G2  Editor GPU Preview Foundation               CLOSED / MERGED
G3  Production Rendering Pipeline               CLOSED / MERGED
G4  Product Editor UX / Session Workflow        CLOSED / MERGED
G5  Editing Feature Completeness                CLOSED / VERIFIED
G6  Reliability / Performance / Device Matrix   CLOSED / VERIFIED

P0  pixelcraft_engine package extraction        MERGED
P1  pixelcraft_gpu package extraction           MERGED
P2  pixelcraft_editing package extraction        NEXT
G7  Release / Beta / Store Readiness            PLANNED
```

> Rust เป็น authoritative source สำหรับ semantic edits, recipe, history, checkpoint, recovery และ full-resolution export. Flutter เป็น product/control/presentation plane. Native GPU เป็น faithful low-latency preview path เท่านั้น

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
2. GPU preview never becomes final-render source of truth.
3. Camera Film is preview-only; capture source remains clean.
4. Live camera frames never cross Dart MethodChannel or FRB.
5. Film/Creative LUT data is generated from Rust-owned canonical data.
6. Unsupported GPU order or native failure falls back to valid Rust preview.
7. Flutter presentation state must not become a parallel semantic recipe.
8. Film Profiles are reusable configuration data, not Editor session state or captured GPU pixels.
9. Imported recipe fields report exact / approximated / unsupported mapping explicitly.
10. New effects are defined in Rust first; GPU support is enabled only when semantics can be represented faithfully.

---

# 2. Monorepo package boundary after P0/P1

```text
PixelCraft/
├── lib/                          # app UI / state / app-side adapters
├── rust/                         # authoritative image engine
├── packages/
│   ├── pixelcraft_engine/        # FRB/CargoKit build integration
│   └── pixelcraft_gpu/           # preview-only GPU plugin
├── android/
├── ios/
├── test/
├── tool/
└── docs/
```

Dependency direction:

```text
PixelCraft App
   ├── pixelcraft_gpu
   └── pixelcraft_engine
          |
          v
        rust/
```

Packages must never depend back on PixelCraft app source.

Detailed package walkthroughs:

```text
packages/pixelcraft_engine/CODE_WALKTHROUGH.md
packages/pixelcraft_gpu/CODE_WALKTHROUGH.md
```

---

# 3. App startup and Home

Entry point:

```text
lib/main.dart
```

Startup flow:

```text
WidgetsFlutterBinding
 -> portrait orientation policy
 -> Flutter/platform error handlers
 -> ProviderScope
 -> RustBootstrapScreen
 -> initializeRustBridge()
 -> HomeScreen
```

Home:

```text
lib/ui/screens/home_screen.dart
```

Editor entry sources include Film Camera, system camera, gallery, bundled sample and saved recovery sessions.

Recovery remains explicit:

```text
Resume last edit
[Discard] [Resume]
```

Resume passes stored source bytes plus the authoritative recipe into `EditorScreen`.

---

# 4. pixelcraft_engine and Rust authority

`packages/pixelcraft_engine` is not the semantic image engine. It is the Flutter FFI/build package around the root Rust crate.

```text
Flutter app
   ↓
pixelcraft_engine
   ↓ FRB / CargoKit
rust/
```

Important Rust files:

```text
rust/src/api.rs
rust/src/engine.rs
rust/src/filters.rs
rust/src/advanced_filters.rs
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

Operations before `checkpoint_cursor` belong to the last Apply checkpoint.

Full-resolution replay is deferred to Export.

P0 moved the former generated/native build layout under:

```text
packages/pixelcraft_engine/
```

while the authoritative crate intentionally remains:

```text
rust/
```

---

# 5. FRB / CargoKit flow

Conceptual flow:

```text
rust/src/api.rs
   ↓
flutter_rust_bridge_codegen
   ↓
generated Dart bridge + generated Rust bridge
   ↓
pixelcraft_engine native build integration
   ↓
CargoKit
   ↓
platform-native Rust artifact
```

Useful commands:

```bash
make codegen
make integrate
make repair
make verify-native
```

FRB can regenerate a conventional root `rust_builder/`. PixelCraft normalizes it back into `packages/pixelcraft_engine` using project tooling.

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

Current Editor controls include:

```text
Exposure
Brightness
Contrast
Highlights
Shadows
Saturation
Temperature
Tint
Vibrance
Vignette
Grain
Sharpness
Gaussian Blur
```

The `gpuPreview` flag is intentional: controls without a verified faithful native implementation commit through Rust on release instead of using an approximate shader.

---

# 7. EditorController

Primary controller:

```text
lib/state/editor_controller.dart
```

It projects Rust state into Flutter:

- preview/checkpoint bytes
- histogram
- selected tool
- adjustment memories
- Creative selection/intensity
- Film selection/strength
- processing state
- cursor / operation count
- undo / redo capability

Typical Adjust transaction:

```text
slider drag
  -> GPU-only preview draft when faithfully representable

slider release
  -> EditorController commits semantic value
  -> Rust semantic commit/replace
  -> authoritative Rust preview
  -> recovery persistence
```

Tool switching does not Apply or Discard the active draft implicitly.

---

# 8. pixelcraft_gpu after P1

`packages/pixelcraft_gpu` now owns the app-independent preview runtime.

It contains:

- Dart GPU transport/session/render-plan infrastructure
- native camera control bridges
- Android Camera2/OpenGL ES runtime
- iOS AVFoundation/Metal runtime
- plugin registration
- diagnostics / frame pacing

It does not own committed edit semantics or export pixels.

Conceptual dependency:

```text
Flutter app
   ↓ preview intent
pixelcraft_gpu
   ↓
Metal / OpenGL ES

Flutter app
   ↓ semantic commit
Rust
```

Some `lib/gpu/*` code still remains app-side where it adapts app-owned edit graph types. P1 deliberately did not move those files into the package because doing so would create a package → app dependency.

P2 is intended to extract those pure editing-domain contracts.

---

# 9. Editor GPU render plan

Primary package-level concepts:

```text
GpuEditorRenderPlan
GpuEditorDraftSession
native preview bridge
renderer/session generation
```

The render plan is accepted only when operation order can be represented faithfully.

Current verified native topology conceptually includes stages such as:

```text
optional Creative stage
 -> Gaussian Blur
 -> Sharpen
 -> Brightness
 -> Contrast
 -> Saturation
 -> optional Film/final LUT
```

If an operation or ordering cannot be represented safely:

```text
GPU path rejected
   ↓
keep valid Rust preview
```

No silent semantic reordering is allowed.

---

# 10. GPU session lifecycle and invalidation

A preview session must not allow stale native work to override newer editor state.

Typical lifecycle:

```text
activate GPU draft
 -> native renderer active
 -> newer editor state arrives
 -> generation advances
 -> stale work ignored
```

Important invalidation reasons include:

```text
Rust checkpoint changed
editor entered busy state
active tool changed
renderer dropped
new activation superseded old activation
```

After gesture release, the authoritative Rust commit replaces temporary GPU-only visual state.

---

# 11. Android camera GPU path

Eligible path:

```text
Camera2
 -> SurfaceTexture / external OES texture
 -> OpenGL ES canonical Film LUT
 -> Flutter PlatformView
```

P1 moved production registration out of `MainActivity` and into the plugin.

Conceptually:

```text
GeneratedPluginRegistrant
 -> PixelcraftGpuPlugin
 -> FlutterPlugin + ActivityAware
 -> MethodChannel / PlatformView
 -> Camera2 / GLES runtime
```

Android plugin namespace:

```text
dev.pixelcraft.gpu
```

Camera capture remains clean. Dart receives a clean file path/control metadata, not live processed frame buffers.

---

# 12. iOS camera/editor GPU path

Eligible camera path:

```text
AVCaptureVideoDataOutput
 -> CVPixelBuffer
 -> CVMetalTextureCache
 -> Metal canonical Film LUT
 -> Flutter PlatformView
```

Production native GPU sources live under:

```text
packages/pixelcraft_gpu/ios/Classes/
```

P1 moved production GPU registration out of `AppDelegate` into the plugin registrar.

The app `AppDelegate` remains an app shell rather than the production GPU composition root.

Any Runner compatibility stubs are build-project compatibility only and must not contain production GPU implementation.

---

# 13. Canonical Film / Creative LUT architecture

Rust-owned Film data:

```text
rust/film_profiles/*/look.json
```

Build flow:

```text
Rust canonical data
 -> canonical 33^3 LUT
      ├── Rust renderer
      └── generated native GPU assets
             ↓
        pixelcraft_gpu
```

Current built-in Film IDs include:

```text
provia_inspired
velvia_inspired
astia_inspired
e100_inspired
ektar_inspired
chrome64_inspired
```

Creative LUT presets use the same principle: one canonical semantic source, multiple faithful render paths.

---

# 14. FilmProfileV1

Main schema/model:

```text
lib/core/film_profile_v1.dart
```

A Film Profile stores reusable configuration such as:

- id / name / description
- origin
- optional base Film
- strength
- normalized parameter map
- tags
- schema/engine compatibility

It deliberately does not contain:

- source image
- crop/rotate state
- Editor history
- checkpoint cursor
- captured GPU pixels

Loading a Film Profile materializes normal recipe operations and restores those semantics through Rust.

---

# 15. Recovery / Exit / Export

Recovery:

```text
lib/core/editor_session_store.dart
```

Generation-based publishing stores source + recipe and writes the manifest last. Load validates bounds/fingerprint and can fall back from corrupt newest data to an older coherent generation.

Exit policy with an active draft:

```text
Continue Editing
Discard
Apply & Exit
```

Export:

```text
untouched original source
 -> Rust decode
 -> replay complete active recipe
 -> encode output
 -> gallery/app backup/share
```

Native GPU preview pixels are never export input.

---

# 16. Failure / fallback model

Native GPU is optional for correctness.

Fallback can happen for:

```text
protocol mismatch
backend unavailable
missing native assets
shader self-test failure
unsupported LUT capability
blacklisted GPU
renderer init failure
runtime renderer failure
unsupported edit order
```

All such cases fail closed to the valid Rust/product state.

Rust/native engine packaging failures are different: they are build/integration failures and should fail CI visibly rather than silently switch semantic implementation.

---

# 17. Verification layers

Host / Flutter:

```bash
flutter analyze
flutter test
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

P1 merge gate included:

```text
FRB regeneration
Rust checks/tests
G6 12 MP characterization
GPU LUT parity
Flutter analyze
state tests
GPU plan/session tests
widget tests
golden tests
Android native packaging smoke
iOS native packaging smoke
Android physical-device smoke
iOS physical-device smoke
```

The final P1 CI run passed both Android and iOS packaging gates before merge.

---

# 18. Important files

```text
Startup
  lib/main.dart

Home
  lib/ui/screens/home_screen.dart

Editor
  lib/ui/screens/editor_screen.dart
  lib/ui/widgets/editor_tool_panel.dart

Editor presentation
  lib/state/editor_controller.dart
  lib/state/editor_recipe_summary.dart
  lib/state/editor_adjustment_catalog.dart

Film Profile
  lib/core/film_profile_v1.dart
  lib/core/film_profile_recipe.dart
  lib/core/film_profile_store.dart

Recovery
  lib/core/editor_session_store.dart

Rust adapter
  lib/core/image_engine.dart

Engine package
  packages/pixelcraft_engine/README.md
  packages/pixelcraft_engine/CODE_WALKTHROUGH.md

GPU package
  packages/pixelcraft_gpu/README.md
  packages/pixelcraft_gpu/CODE_WALKTHROUGH.md

Rust authority
  rust/src/api.rs
  rust/src/engine.rs
  rust/src/filters.rs
  rust/src/advanced_filters.rs
```

---

# 19. Current continuation point

G6 is **CLOSED / VERIFIED**.

P0 and P1 package extraction are **MERGED**.

Current modularization continuation:

```text
P2: extract pure editing models / contracts into packages/pixelcraft_editing
```

Primary motivation for P2 is to remove app-owned editing-domain dependencies from the remaining GPU renderer/capability adapters without creating a dependency from `pixelcraft_gpu` back into the app.

After modularization work is stable, G7 Release / Beta / Store Readiness can continue from the updated `main` architecture.

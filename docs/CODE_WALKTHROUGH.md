# PixelCraft Code Walkthrough

เอกสารนี้อธิบาย architecture ปัจจุบันของ repository **PixelCraft** / product **Dextryx Pixels** หลัง G1–G7A, package extraction, product UX modernization และการเริ่ม W1 real workspace/catalog foundation.

สถานะ ณ 2026-08-16:

```text
G1  Camera GPU Preview                          CLOSED
G2  Editor GPU Preview Foundation               CLOSED / MERGED
G3  Production Rendering Pipeline               CLOSED / MERGED
G4  Product Editor UX / Session Workflow        CLOSED / MERGED
G5  Editing Feature Completeness                CLOSED / VERIFIED
G6  Reliability / Performance / Device Matrix   CLOSED / VERIFIED

P0-P3 package extraction                        MERGED
PKG-01 dxtr_pixs_* namespace consolidation      COMPLETE

G7A Release Engineering / Store Preparation     MERGED
G7B Store Account Integration / Beta Upload     DEFERRED INDEFINITELY

UX-01 Modern import/add-photo flow               CLOSED / VERIFIED
UX-02 Home / Workspace modernization             CLOSED / VERIFIED
W1 Real workspace/catalog foundation             ACTIVE
```

Latest verified baseline before W1:

```text
PR #40 merge: 29af1b17fa3f0066aa9428190b79fe4e26d8a1b3
main CI: #347 / 31921037298 / SUCCESS
```

> Rust เป็น authoritative source สำหรับ committed semantic edits, recipe, history, checkpoint, recovery และ full-resolution export. Flutter เป็น product/control/presentation plane. Native GPU เป็น faithful low-latency preview path เท่านั้น. Workspace catalog เป็น product metadata และต้องไม่กลายเป็น semantic edit authority อีกชุดหนึ่ง.

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
Rust semantic edit / recipe
        ↓
authoritative reduced preview + history + checkpoint
        ↓
full-resolution Rust replay/export
```

Parallel product metadata path:

```text
Import / Camera acquisition
        ↓
WorkspaceCatalogStore
        ↓
stable catalog identity + source metadata
        ↓
Home / workspace presentation
```

Hard contracts:

1. Rust owns committed edit semantics, history, checkpoints, recovery recipe, and export.
2. GPU preview never becomes final-render source of truth.
3. Camera Film is preview-only; capture source remains clean.
4. Live camera frames never cross Dart MethodChannel or Flutter Rust Bridge.
5. Canonical Film/Creative LUT data remains Rust-owned.
6. Unsupported GPU order/native failure falls back to valid Rust/product state.
7. Flutter presentation state must not become a parallel semantic recipe.
8. Film Profiles are reusable configuration, not Editor session state or captured pixels.
9. Workspace catalog owns product identity/source metadata only; it does not own recipe/history/checkpoint semantics.
10. Recovery generation identity and workspace catalog identity are intentionally separate.
11. New effects are defined/tested in Rust first; GPU support is optional and only enabled when faithful.

---

# 2. Product identity and package graph

```text
master brand: Dextryx
product: Dextryx Pixels
installed label: Dxtr Pixs
repository: PixelCraft
Android applicationId: dev.cnxdev.pixelcraft
iOS bundle id: dev.cnxdev.pixelcraft
```

Current package graph:

```text
PixelCraft App
 ├── dxtr_pixs_film
 ├── dxtr_pixs_gpu
 ├── dxtr_pixs_editing
 └── dxtr_pixs_engine

dxtr_pixs_film    -> dxtr_pixs_editing
dxtr_pixs_gpu     -> dxtr_pixs_editing
dxtr_pixs_editing -> Dart SDK only
dxtr_pixs_engine  -> repository rust/ crate through build integration
```

Native/runtime identifiers intentionally remain stable, including Rust crate/native library/channel/storage schema names.

`tool/check_package_boundaries.sh` enforces forbidden dependency directions.

---

# 3. App startup and Home workspace

Entry point:

```text
lib/main.dart
```

Conceptual flow:

```text
WidgetsFlutterBinding
 -> ProviderScope
 -> Rust bootstrap
 -> HomeScreen
```

Current acquisition hierarchy:

```text
Import                    primary direct gallery path
More ways to add
 ├── Film Camera
 └── Take Photo
Films                     separate secondary destination
```

UX-02 removed demo/sample-photo Home content. Home now shows only real product state:

```text
no recoverable session
 -> honest empty workspace

recoverable session
 -> Recent edit card
 -> real thumbnail from recovery originalBytes
 -> real savedAt when available
 -> Resume / Discard
```

The recovery card is not a multi-item catalog. W1 introduces that persistent product model separately.

---

# 4. Rust authority / dxtr_pixs_engine

```text
Flutter app
   ↓
dxtr_pixs_engine
   ↓ FRB / CargoKit
rust/
```

Rust owns:

```text
untouched source
reduced preview
semantic operations
cursor
checkpoint_cursor
undo / redo
recovery recipe
full-resolution replay/export
```

Useful commands:

```bash
make codegen
make integrate
make repair
make verify-native
```

---

# 5. Editing and Film contracts

`dxtr_pixs_editing` contains reusable pure-Dart editing/profile contracts such as:

```text
EditGraphDocument / EditGraphNode
EditorAdjustmentSpec
FilmProfileV1
FilmProfileOrigin
FilmProfileImportReport
applyFilmProfileToSessionRecipe()
```

Responsibility split:

```text
dxtr_pixs_editing = reusable edit/profile configuration semantics
app/GPU layer      = product state + backend capability policy
Rust               = committed image authority
```

`dxtr_pixs_film` owns product/domain orchestration around profile repository, library, import service and draft editing. Canonical built-in Film/LUT data remains Rust-owned.

---

# 6. Editor transaction model

Primary controller:

```text
lib/state/editor_controller.dart
```

Typical adjustment flow:

```text
slider drag
  -> temporary GPU preview when faithfully supported

slider release
  -> semantic commit/replace
  -> Rust authoritative preview
  -> recovery persistence
```

GPU failure or unsupported render order never silently changes semantic order.

---

# 7. GPU preview runtime

Package:

```text
packages/dxtr_pixs_gpu/
```

Owns preview-only infrastructure:

- Dart GPU transport/session/render-plan code
- native camera control bridges
- Android Camera2/OpenGL ES camera runtime
- iOS AVFoundation/Metal camera runtime
- iOS native Editor GPU preview
- diagnostics/frame pacing

Platform policy remains:

```text
Android -> Camera2/OpenGL ES camera preview
iOS     -> AVFoundation/Metal camera preview + Metal Editor preview
```

Do not casually replace the mobile runtime with wgpu. wgpu remains useful for separate supported targets/validation where already present.

---

# 8. Recovery persistence

Implementation:

```text
lib/core/editor_session_store.dart
```

Current model:

```text
app-support/pixelcraft-session/
  source.<fingerprint>.bin
  recipe.<generation>.json
  generation.<generation>.json
```

The generation manifest is the recovery commit point pairing source + recipe. The store keeps coherent generations and can fall back from incomplete newest data.

Recovery answers: **"How do I resume the most recent editor state safely?"**

It does not answer: **"What images belong to the user's workspace?"**

That distinction is why W1 uses a separate catalog store.

---

# 9. W1 workspace catalog foundation

Implementation introduced by PR #41:

```text
lib/core/workspace_catalog_store.dart
test/core/workspace_catalog_store_test.dart
```

Persistent location:

```text
app-support/pixelcraft-workspace/
  catalog.json
  catalog.json.tmp       transient publish file
  catalog.json.bak       previous committed fallback during replacement
```

`WorkspaceCatalogItem` stores product metadata only:

```text
id
sourceKind
retention
sourcePath
availability
importedAt
updatedAt
lastOpenedAt?
```

Current enums:

```text
WorkspaceSourceKind
  gallery
  systemCamera
  filmCamera

WorkspaceSourceRetention
  externalReference
  managedCopy

WorkspaceSourceAvailability
  unknown
  available
  missing
```

The catalog deliberately does **not** store:

```text
Rust recipe
semantic operation history
checkpoint cursor
rendered pixels as authority
recovery generation identity
```

## W1 write safety

PR #41 hardens four important persistence rules:

1. **Old manifest remains recoverable until replacement commit**

```text
write + flush catalog.json.tmp
old catalog.json -> catalog.json.bak
catalog.json.tmp -> catalog.json
remove .bak only after successful publish
```

If publication fails after moving the old file, the backup is restored. If the process terminates between moves, a later load can recover the `.bak` manifest.

2. **Read APIs fail closed; mutations fail loudly**

`load()` may return an empty catalog when no valid committed manifest can be read. Read-modify-write operations do not interpret malformed/newer-schema data as an empty workspace; they surface the decode/version error so existing bytes are not overwritten.

3. **Serialization is shared across store instances**

Write tails are keyed by the absolute workspace directory path, so two `WorkspaceCatalogStore` objects targeting the same catalog participate in the same serialized read-modify-write queue within the Dart isolate.

4. **IDs survive store recreation**

IDs are chosen under the shared write lock from timestamp + the next unused suffix already present in the catalog. Recreating the store and adding another item at the same timestamp therefore does not replace the earlier identity.

Focused tests cover reload, ordering, availability, last-opened metadata, removal, one-instance concurrency, cross-instance concurrency, recreated-store ID collision prevention, malformed/newer schema mutation refusal, and backup recovery.

---

# 10. Export / share

Implementation:

```text
lib/core/export_file_service.dart
```

Canonical flow:

```text
untouched source
 -> Rust recipe replay
 -> encoded output bytes
 -> app documents/gallery
 -> system share sheet after explicit Share
```

GPU preview pixels and workspace catalog metadata are never export authority.

---

# 11. Release and reliability baseline

G6 physical reliability is closed/verified, including iPhone 11 device evidence and the policy that verifier tooling must not uninstall/overwrite the installed main app `dev.cnxdev.pixelcraft`.

G7A account-independent release engineering is merged. Android release validation rejects debug signing; iOS validates release `--no-codesign` packaging.

G7B is **deferred indefinitely / not scheduled**. It is not the current blocker for W1 and must not be restarted without an explicit project decision.

Dart 3.13 RecordUse/native tree-shaking is documented separately as future/deferred work in:

```text
docs/FUTURE_DART_3_13_NATIVE_TREE_SHAKING.md
```

---

# 12. Verification gates

Standard repo validation:

```bash
bash tool/check_package_boundaries.sh
make gpu-lut-verify
make verify-native
flutter analyze
flutter test
```

Full CI additionally covers Rust fmt/clippy/tests, packages, native builds, golden tests, Android/iOS release packaging and configured wgpu jobs.

A PR head being green is not enough to close a slice. After merge, the resulting `main` push CI must also be verified green.

---

# 13. Important files

```text
Architecture / continuation
  docs/PROJECT_HANDOFF.md
  docs/CODE_WALKTHROUGH.md

Workspace / recovery
  lib/core/workspace_catalog_store.dart
  lib/core/editor_session_store.dart
  lib/ui/screens/home_screen.dart

Editor/export
  lib/state/editor_controller.dart
  lib/core/export_file_service.dart

Packages
  packages/dxtr_pixs_engine/
  packages/dxtr_pixs_gpu/
  packages/dxtr_pixs_editing/
  packages/dxtr_pixs_film/

Rust authority
  rust/
```

---

# 14. Current continuation point

W1 is active on PR #41 / `feature/w1-workspace-catalog-foundation`.

Current sequence:

```text
1. stabilize WorkspaceCatalogItem + WorkspaceCatalogStore contract
2. verify crash-safe manifest replacement and corruption policy
3. verify cross-instance serialized writes and stable identity allocation
4. keep catalog metadata separate from Rust/recovery authority
5. pass full PR CI and address review feedback
6. merge and verify resulting main CI
7. only then integrate real acquisition paths with catalog writes
8. only after real persisted items exist, render multi-item Home workspace UI
```

Do not fake recent/catalog data, do not migrate recovery identity into catalog identity, and do not start G7B/O1/MobileSAM/restoration as part of W1.

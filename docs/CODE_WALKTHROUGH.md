# PixelCraft Code Walkthrough

เอกสารนี้อธิบาย architecture ปัจจุบันของ repository **PixelCraft** / product **Dextryx Pixels** หลัง G1–G7A, package extraction, UX modernization และ W1 real workspace/catalog work.

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

Latest verified W1 baseline:

```text
PR #41 merge: 7f3ae0eaaa6fe40711eca251ac746b3a24e1b69a
main CI: #352 / 31922895364 / SUCCESS
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
Import / Take Photo
        ↓
WorkspaceCatalogStore
        ↓
stable catalog identity + source metadata
        ↓
Home workspace list
        ↓
open source path in ProductEditorScreen
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

Native/runtime identifiers intentionally remain stable, including Rust crate/native library/channel/storage schema names. `tool/check_package_boundaries.sh` enforces forbidden dependency directions.

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

Home contains only real persisted product state:

```text
no recovery + no catalog items
 -> honest empty workspace

recoverable session
 -> Recent edit card
 -> bounded thumbnail from recovery originalBytes
 -> savedAt when valid
 -> Resume / Discard

catalog items
 -> Workspace section
 -> bounded file thumbnail
 -> source filename + source kind
 -> open source in ProductEditorScreen
```

The recovery card and catalog list are separate concepts. Discarding recovery must not delete workspace identity.

---

# 4. Acquisition → catalog integration

Implementation:

```text
lib/ui/screens/home_screen.dart
lib/core/workspace_catalog_store.dart
```

Gallery flow:

```text
Import
 -> ImagePicker.gallery
 -> WorkspaceCatalogStore.add(
      sourceKind: gallery,
      retention: externalReference,
      sourcePath: XFile.path,
      availability: available,
    )
 -> refresh Home catalog
 -> ProductEditorScreen(imagePath: XFile.path)
```

System camera flow:

```text
More ways to add -> Take Photo
 -> ImagePicker.camera
 -> WorkspaceCatalogStore.add(
      sourceKind: systemCamera,
      retention: externalReference,
      sourcePath: XFile.path,
      availability: available,
    )
 -> refresh Home catalog
 -> ProductEditorScreen(imagePath: XFile.path)
```

Lost picker data recovered by Home is cataloged as `systemCamera` before opening the editor.

Catalog writes are **fail-soft for editing** but **fail-closed for metadata preservation**:

- if the catalog mutation fails because the manifest is malformed/newer/inaccessible, Home reports `Workspace catalog update failed`;
- the selected image can still open in the editor;
- the store itself refuses to reinterpret invalid existing catalog data as an empty catalog and therefore does not overwrite unknown data.

Film Camera is intentionally not catalog-integrated in this slice because its capture handoff/path contract must be inspected separately first.

---

# 5. Opening workspace items

Home loads persisted items through `WorkspaceCatalogStore.load()`.

When a user taps an item:

```text
File(sourcePath).exists?
 ├── yes
 │    -> mark availability = available when needed
 │    -> markOpened(id)
 │    -> ProductEditorScreen(imagePath: sourcePath)
 │    -> refresh recovery + catalog after editor returns
 │
 └── no
      -> mark availability = missing
      -> preserve catalog identity
      -> show "This source file is no longer available."
```

Missing source handling never silently deletes the catalog row. This preserves identity for future relink/recovery work.

Catalog thumbnails use `Image.file` with `cacheWidth/cacheHeight` derived from logical thumbnail extent × device pixel ratio, so Home does not intentionally decode full-resolution files merely to populate the list.

---

# 6. Rust authority / dxtr_pixs_engine

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

# 7. Editing and Film contracts

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

# 8. Editor transaction model

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

# 9. GPU preview runtime

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

Do not casually replace the mobile runtime with wgpu.

---

# 10. Recovery persistence

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

The generation manifest is the recovery commit point pairing source + recipe. Recovery answers: **"How do I resume the most recent editor state safely?"** It does not answer: **"What images belong to the user's workspace?"**

---

# 11. W1 workspace catalog persistence

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

The catalog deliberately does not store Rust recipe, semantic operation history, checkpoint cursor, rendered pixels as authority, or recovery generation identity.

## Write safety

1. write + flush `catalog.json.tmp`;
2. preserve previous `catalog.json` as `catalog.json.bak`;
3. publish temp as new `catalog.json`;
4. remove backup only after successful publish;
5. recover backup after interrupted replacement;
6. mutations refuse malformed/newer-schema manifests;
7. read-modify-write serialization is shared across store instances targeting the same directory inside the Dart isolate;
8. IDs are allocated under that shared write lock against existing catalog IDs.

Tests cover persistence, ordering, availability, last-opened metadata, removal, concurrent writes, cross-instance writes, recreated-store ID collision prevention, malformed/newer schema mutation refusal, and backup recovery.

---

# 12. Export / share

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

# 13. Release and reliability baseline

G6 physical reliability is CLOSED / VERIFIED. Verifier tooling must not uninstall/overwrite installed main app `dev.cnxdev.pixelcraft`.

G7A account-independent release engineering is merged. G7B is **deferred indefinitely / not scheduled** and must not be restarted without an explicit project decision.

Dart 3.13 RecordUse/native tree-shaking remains future/deferred in `docs/FUTURE_DART_3_13_NATIVE_TREE_SHAKING.md`.

---

# 14. Verification gates

```bash
bash tool/check_package_boundaries.sh
make gpu-lut-verify
make verify-native
flutter analyze
flutter test
```

Full CI additionally covers Rust fmt/clippy/tests, package suites, native builds, goldens, Android/iOS release packaging and configured wgpu jobs.

A PR head being green is not enough to close a slice. Verify resulting `main` push CI after merge.

---

# 15. Important files

```text
Architecture / continuation
  docs/PROJECT_HANDOFF.md
  docs/CODE_WALKTHROUGH.md

Workspace / recovery
  lib/core/workspace_catalog_store.dart
  lib/core/editor_session_store.dart
  lib/ui/screens/home_screen.dart
  test/core/workspace_catalog_store_test.dart
  test/ui/home_screen_test.dart
  test/ui/home_camera_source_test.dart

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

# 16. Current continuation point

W1 storage foundation is merged and verified through PR #41 / main CI #352. The active slice is acquisition/Home catalog integration on `feature/w1-catalog-integration`.

Current sequence:

```text
1. catalog gallery Import and system Take Photo acquisition
2. render only persisted catalog items on Home
3. preserve recovery card as a separate concern
4. mark missing source without deleting catalog identity
5. keep thumbnails decode-bounded
6. verify widget + catalog persistence tests and full CI
7. address review feedback
8. merge and verify resulting main CI
9. inspect Film Camera capture handoff before integrating it
10. decide managed-copy policy before promising durable source retention across platform picker/cache lifetimes
```

Do not fake catalog data, do not migrate recovery identity into catalog identity, and do not start G7B/O1/MobileSAM/restoration as part of W1.

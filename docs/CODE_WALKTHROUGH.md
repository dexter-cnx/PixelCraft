# PixelCraft Code Walkthrough

Repository: **PixelCraft**  
Product: **Dextryx Pixels**

## Product scope

PixelCraft is the **photo-editing and image-processing product**.

Its primary responsibilities are:

- editor UX and edit-session lifecycle;
- Rust-authoritative edit recipe/history/checkpoint semantics;
- adjustments, transforms, masks, Film/Creative processing;
- realtime GPU preview where faithful;
- full-resolution render/export;
- editor recovery and source reopening continuity.

**Nixin / Dextryx Images is a separate product** whose primary responsibility is image management: Workplaces, import, cataloging, browsing, organization, source management, and large-library UX.

The PixelCraft workspace/catalog implementation is therefore an **editor-local convenience layer**, not a general DAM. Do not extend it into Nixin-style Workplaces, folder ingestion, bulk asset organization, ratings/flags/keywords, or a Lightroom-style library unless PixelCraft receives an explicit product decision to do so.

Nixin may reuse stable, explicitly reusable PixelCraft packages/modules for bounded basic capabilities. That is module reuse, not roadmap reuse, and it must not depend on PixelCraft app internals or transfer catalog/edit authority between products.

A future cross-product direction may allow Nixin to invoke PixelCraft as a full external editor. That protocol does not exist yet and must be designed explicitly before implementation.

---

## Current milestone status

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
W1A/W1B editor-local catalog foundation          CLOSED / VERIFIED
W1C acquisition/catalog/Home integration         CLOSED / VERIFIED
```

PR #42:

```text
final head: 1218ec44d0d9938a89b7f7ab294b0a55a2f435b5
PR CI: #362 / 31930004255 / SUCCESS
merge: a5d015587a9eab0125d8605f91fff9307e8d0c11
main CI: #363 / 31930570158 / SUCCESS
```

---

## Canonical architecture

```text
Camera / imported image
        ↓
clean source image
        ↓
Flutter product/control state
        ↓
faithful low-latency GPU preview where supported
        ↓ commit
Rust semantic edit / recipe
        ↓
authoritative preview + history + checkpoint
        ↓
full-resolution Rust replay/export
```

Hard contracts:

1. Rust owns committed edit semantics, recipe/history/checkpoint/recovery, and export.
2. GPU is preview-only and never final-render authority.
3. Camera Film is preview-only; capture remains clean.
4. Live camera frames never cross MethodChannel/FRB.
5. Canonical Film/Creative LUT data remains Rust-owned.
6. Unsupported GPU operation ordering falls back rather than silently reordering semantics.
7. Flutter state must not become a second semantic edit authority.
8. Film Profiles are reusable configuration, not captured pixels/session authority.
9. PixelCraft catalog metadata never owns recipe/history/pixels.
10. Recovery generation identity and catalog identity remain separate.
11. Nixin owns long-lived Workplaces/library organization; PixelCraft does not duplicate that responsibility.
12. Other products may consume stable reusable PixelCraft modules without importing PixelCraft app state or ownership.

---

## Product identity and package graph

```text
master brand: Dextryx
product: Dextryx Pixels
installed label: Dxtr Pixs
repository: PixelCraft
Android applicationId: dev.cnxdev.pixelcraft
iOS bundle id: dev.cnxdev.pixelcraft
```

```text
PixelCraft App
 ├── dxtr_pixs_film
 ├── dxtr_pixs_gpu
 ├── dxtr_pixs_editing
 └── dxtr_pixs_engine

dxtr_pixs_film    -> dxtr_pixs_editing
dxtr_pixs_gpu     -> dxtr_pixs_editing
dxtr_pixs_editing -> Dart SDK only
dxtr_pixs_engine  -> repository rust/ crate
```

Native ABI/library/channel/persisted schema identifiers remain stable unless separately approved.

---

## Home and acquisition

Primary entry:

```text
Import -> gallery picker
```

Secondary entry:

```text
More ways to add
 ├── Film Camera
 └── Take Photo
```

Home is an **editor-entry and recovery surface**, not a full image library.

It may show:

- honest empty state;
- latest recoverable edit;
- bounded thumbnails for real editor-local source entries;
- missing-source state;
- direct reopen into `ProductEditorScreen`.

No sample/fake asset rows are allowed.

---

## Editor-local workspace catalog

Implementation:

```text
lib/core/workspace_catalog_store.dart
lib/ui/screens/home_screen.dart
```

`WorkspaceCatalogItem` stores only lightweight metadata:

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

It does **not** store:

```text
Rust recipe
edit history
checkpoint cursor
rendered pixels as authority
recovery generation identity
Nixin Workplace membership
ratings / flags / keywords
large-library organization
```

Current source kinds:

```text
gallery
systemCamera
filmCamera
```

Current retention states:

```text
externalReference
managedCopy
```

Current availability states:

```text
unknown
available
missing
```

The store uses `catalog.json`, `.tmp`, and `.bak` with fail-closed mutation semantics and focused corruption/concurrency tests.

---

## Acquisition integration

Gallery:

```text
Import
 -> picker
 -> catalog lightweight source metadata
 -> ProductEditorScreen
```

System camera:

```text
Take Photo
 -> picker
 -> catalog lightweight source metadata
 -> ProductEditorScreen
```

Lost picker recovery does not invent gallery/camera provenance when the platform does not provide it.

Catalog failure does not block the editor from opening, while invalid existing catalog data is not silently overwritten.

Film Camera catalog registration is not yet implemented. If added, it must remain a continuity/reopen feature rather than becoming a DAM expansion.

---

## Opening catalog entries

```text
set in-flight open guard
 -> check source existence
    ├── exists
    │    -> mark available/opened
    │    -> open ProductEditorScreen
    └── missing
         -> mark missing
         -> preserve identity
         -> report unavailable source
 -> clear guard
```

Bounded thumbnail decode prevents Home from intentionally decoding full-resolution originals merely to populate the entry list.

---

## Recovery persistence

Implementation:

```text
lib/core/editor_session_store.dart
```

Recovery answers:

> How can PixelCraft resume the latest coherent editor state safely?

It is not an image-management catalog and must not be repurposed into one.

---

## Rust authority / engine

```text
Flutter app
   ↓
dxtr_pixs_engine
   ↓ FRB / CargoKit
rust/
```

Rust owns:

- untouched source;
- reduced preview;
- semantic operations;
- undo/redo cursor;
- checkpoint cursor;
- recovery recipe;
- full-resolution replay/export.

Useful commands:

```bash
make codegen
make integrate
make repair
make verify-native
```

---

## GPU preview

Package:

```text
packages/dxtr_pixs_gpu/
```

Platform policy:

```text
Android -> Camera2/OpenGL ES camera preview
iOS     -> AVFoundation/Metal camera preview + Metal editor preview
```

Do not casually replace the mobile runtime with wgpu.

---

## Export

Canonical flow:

```text
untouched source
 -> Rust recipe replay
 -> encoded output bytes
 -> destination/gallery
 -> optional share sheet
```

GPU preview pixels and workspace metadata are never export authority.

---

## Explicit PixelCraft non-goals for workspace/catalog

Do not continue the current catalog work into these features by default:

```text
Workplaces hierarchy
folder import / recursive ingestion
bulk asset organization
large-library browser
ratings / flags / keywords
collections
archive management
Lightroom-style DAM workflow
```

Those are Nixin / Dextryx Images responsibilities.

Catalog-related PixelCraft follow-up is allowed only when necessary for editor correctness or continuity, such as source durability, missing-source handling, or source reopening.

---

## Reusable module boundary

Nixin or another product may consume a PixelCraft module when all of these hold:

```text
stable/documented reusable API
bounded capability
no dependency on PixelCraft app-internal UI/state
clear authority ownership
versioned dependency surface
```

If the consumer needs PixelCraft editor-session lifecycle, recipe/history ownership, substantial PixelCraft UI, or bidirectional state return, use a separately designed external-editor integration instead.

---

## Verification gates

```bash
bash tool/check_package_boundaries.sh
make gpu-lut-verify
make verify-native
flutter analyze
flutter test
```

A PR head being green is not enough; verify resulting `main` push CI.

---

## Current continuation point

PR #42 is fully closed/verified through exact resulting main CI #363.

Next:

1. do not start the previously suggested DAM-style W1D;
2. choose the next milestone from **PixelCraft editing / processing / editor UX** priorities;
3. keep catalog work bounded to editor continuity;
4. allow stable reusable PixelCraft modules to serve Nixin when a concrete basic capability benefits from it;
5. do not pull Nixin roadmap items into PixelCraft;
6. do not modify Nixin during PixelCraft work unless the user explicitly requests Nixin or cross-product work.

See `docs/PROJECT_HANDOFF.md` for the canonical execution decision.
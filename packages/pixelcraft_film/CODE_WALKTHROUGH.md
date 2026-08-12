# pixelcraft_film Code Walkthrough

`pixelcraft_film` is the P3 product/domain orchestration boundary for reusable Film Profiles.

## 1. Position in the package graph

```text
Flutter app / screens / platform adapters
                ↓
         pixelcraft_film
                ↓
       pixelcraft_editing

Rust engine = authoritative image semantics and LUT processing
```

The package coordinates Film Profile product behavior. It does not process pixels.

## 2. Repository contract

`FilmProfileRepository` describes the persistence operations required by the product layer:

```dart
loadAll()
save(profile)
delete(id)
```

The interface deliberately does not mention files, directories, SQLite, Hive, SharedPreferences, cloud sync, or `path_provider`.

The current app adapter is:

```text
lib/core/film_profile_store.dart
```

It implements this contract and remains platform infrastructure.

## 3. Library orchestration

`FilmProfileLibrary` is the use-case facade used by presentation code.

It coordinates:

```text
load library
save mutable profile
delete profile
duplicate profile
import source + persist result
```

Direct save of a built-in profile fails. Built-ins must be duplicated first; `FilmProfileV1.duplicate()` converts the copy to `FilmProfileOrigin.user`.

## 4. Creator draft orchestration

`FilmProfileDraft` removes reusable creation/edit rules from `FilmProfileCreatorScreen`.

Initialization:

```text
FilmProfileV1? initial profile
        ↓
FilmProfileDraft.fromProfile
        ↓
all Film parameter slots populated
missing parameter -> semantic neutral
```

During editing:

```text
slider change -> withParameter(id, value)
               -> semantic spec lookup
               -> clamp to supported range

reset         -> resetParameter(id)
               -> semantic neutral value
```

Before save:

```text
UI text fields
 -> copyWith(name / description / parsed tags)
 -> toProfile(newId)
 -> FilmProfileV1 normalization
 -> FilmProfileLibrary.save
 -> repository adapter
```

The package does not generate IDs from time/randomness. The caller supplies `newId`, keeping package behavior deterministic in tests.

## 5. Why parameter semantics remain in pixelcraft_editing

`FilmProfileDraft` uses the parameter catalog from `pixelcraft_editing` rather than duplicating ranges or neutral values.

This preserves the dependency direction:

```text
pixelcraft_film
      ↓
pixelcraft_editing
```

`pixelcraft_film` owns Film product workflow; `pixelcraft_editing` owns reusable editing/profile configuration semantics.

## 6. Import flow

Before P3 the screen decoded JSON and selected the mapping path itself.

After P3:

```text
UI pasted source
   ↓
FilmProfileLibrary.importSource
   ↓
FilmProfileImportService.parse
   ├─ PixelCraft schema -> FilmProfileV1.decode -> origin imported
   └─ generic object    -> importRecipeMap -> profile + mapping report
   ↓
FilmProfileRepository.save
   ↓
UI renders optional mapping report
```

The caller supplies generated IDs for generic imports.

## 7. Mapping ownership

The mapping semantics remain in `pixelcraft_editing`:

```text
exact
approximated
unsupported
```

`pixelcraft_film` owns orchestration and result transport, not the meaning of individual image adjustments.

Unsupported source fields remain visible in the import report and are never silently dropped.

## 8. Storage boundary

The app currently persists profiles as JSON under its application documents directory and writes through a temporary file before rename.

That implementation stays outside `pixelcraft_film` because it depends on Flutter platform storage (`path_provider` / `dart:io`).

This gives a clean replacement seam for future storage backends without contaminating the Film product/domain package.

## 9. Applying a profile to the Editor

P3 does not bypass the existing authority chain:

```text
selected FilmProfileV1
 -> pixelcraft_editing recipe materializer
 -> rewritten draft recipe
 -> restore through Rust engine
 -> authoritative session state
```

`pixelcraft_film` must never render final pixels or claim that a generic imported camera recipe is reproduced 1:1.

Canonical Film LUT data remains Rust-owned.

## 10. Base Film catalog boundary

The current creator UI still presents known base-Film IDs. P3 deliberately does not make `pixelcraft_film` authoritative for LUT inventory because canonical Film LUT data belongs to Rust.

A future base-Film discovery API should be fed from the authoritative engine/catalog rather than hard-coding a second canonical LUT registry into this package.

## 11. Extension rule

A component belongs in `pixelcraft_film` when it is:

- Film/Profile product-domain behavior
- reusable outside a specific screen
- independent of Flutter widgets/navigation
- independent of filesystem/platform APIs
- independent of GPU/native renderer implementation

Keep these outside:

```text
widgets/screens
Clipboard / dialogs
path_provider / dart:io adapter
Rust bridge
Metal/OpenGL
camera lifecycle
canonical LUT pixels
```

## 12. Tests

Package tests verify:

- built-in duplication becomes a user profile
- built-in direct mutation is rejected
- PixelCraft JSON imports as imported origin
- generic recipe import retains unsupported-field reporting
- creator draft starts from semantic neutral values
- parameter values clamp and reset via semantic specs
- profile composition trims metadata and normalizes neutral parameters
- editing an existing profile preserves its id
- unknown parameter IDs fail explicitly

## 13. Dependency invariant

Allowed:

```text
pixelcraft_film -> pixelcraft_editing
```

Forbidden:

```text
pixelcraft_film -> PixelCraft app
pixelcraft_film -> pixelcraft_gpu
pixelcraft_film -> pixelcraft_engine
pixelcraft_film -> Flutter / path_provider / dart:io
pixelcraft_editing -> pixelcraft_film
```

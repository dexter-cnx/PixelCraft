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

The package coordinates Film Profile library behavior. It does not process pixels.

## 2. Repository contract

`FilmProfileRepository` describes the persistence operations required by the product layer:

```dart
loadAll()
save(profile)
delete(id)
```

The interface deliberately does not mention files, directories, SQLite, Hive, SharedPreferences, cloud sync, or `path_provider`.

The current app adapter is `lib/core/film_profile_store.dart`.

## 3. Library orchestration

`FilmProfileLibrary` is the use-case facade used by presentation code.

It currently coordinates:

```text
load library
save mutable profile
delete profile
duplicate profile
import source + persist result
```

Direct save of a built-in profile fails. Built-ins must be duplicated first; `FilmProfileV1.duplicate()` converts the copy to `FilmProfileOrigin.user`.

## 4. Import flow

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

The caller supplies generated IDs. This keeps time/randomness out of the package and makes import behavior deterministic in tests.

## 5. Mapping ownership

The mapping semantics remain in `pixelcraft_editing`:

```text
exact
approximated
unsupported
```

`pixelcraft_film` owns orchestration and result transport, not the meaning of individual image adjustments.

## 6. Storage boundary

The app currently persists profiles as JSON under its application documents directory and writes through a temporary file before rename.

That implementation stays outside `pixelcraft_film` in P3 because it depends on Flutter platform storage (`path_provider`).

This gives us a clean replacement seam for future storage backends without contaminating the Film product/domain package.

## 7. Applying a profile to the Editor

P3 does not bypass the existing authority chain:

```text
selected FilmProfileV1
 -> pixelcraft_editing recipe materializer
 -> rewritten draft recipe
 -> restore through Rust engine
 -> authoritative session state
```

`pixelcraft_film` must never render final pixels or claim that a generic imported camera recipe is reproduced 1:1.

## 8. Extension rule

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
```

## 9. Tests

Package tests use an in-memory `FilmProfileRepository` and verify:

- built-in duplication becomes a user profile
- built-in direct mutation is rejected
- PixelCraft JSON imports as imported origin
- generic recipe import retains unsupported-field reporting

## 10. Dependency invariant

Allowed:

```text
pixelcraft_film -> pixelcraft_editing
```

Forbidden:

```text
pixelcraft_film -> PixelCraft app
pixelcraft_film -> pixelcraft_gpu
pixelcraft_film -> pixelcraft_engine
pixelcraft_editing -> pixelcraft_film
```

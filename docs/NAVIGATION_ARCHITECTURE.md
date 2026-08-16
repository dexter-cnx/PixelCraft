# PixelCraft Navigation Architecture

## Status

Introduced with the `go_router` foundation slice after CI-01.

## Principle

Use routing for workspace/screen boundaries. Keep interactive tools inside a workspace as local/application state.

```text
workspace change = route
workspace tool change = state
```

Examples that are routes:

```text
/camera
/desktop
/editor
/films
/debug/gpu-editor-lab
```

Examples that are not routes:

```text
Film selector
Filter selector
Adjust tool
ISO / EV / WB controls
Before / After interaction
camera control bottom sheet
parameter sliders
```

This preserves direct manipulation and camera/editor continuity instead of turning every editing state into navigation.

## Platform entry

`AppRouter.initialIntent()` remains the platform policy boundary.

```text
phone/tablet -> /camera
desktop      -> /desktop
```

`/` redirects to the platform entry. The debug GPU editor lab can still replace the normal initial location when `GPU_EDITOR_LAB` is enabled in debug builds.

## Rust bootstrap

Every product workspace route is wrapped by `RustBootstrapScreen`.

The Rust initialization Future is shared so navigation does not reinitialize the bridge for each workspace. Failed initialization clears the shared Future and preserves the existing retry UX.

The debug GPU editor lab intentionally preserves its previous bootstrap behavior.

## Editor route contract

The Editor uses a typed `EditorRouteData` payload instead of placing local file paths in the route URL.

Supported route payloads:

```text
file-backed source
in-memory recovery source
optional recovery recipe
optional initial Camera Film profile + strength
```

An initial Camera Film handoff requires a file-backed source because `CameraFilmEditorHandoff` currently operates on an image path.

This keeps navigation separate from future asset identity. A future Nixin/Dextryx Images external-edit contract should pass caller-owned asset identity through its explicit request/result protocol rather than encode local source identity into route paths.

## Migration policy

Migration from imperative `Navigator.push` is incremental.

Priority order:

1. camera -> editor handoff — migrated;
2. top-level Home/Desktop workspace transitions — migrate when those flows are touched;
3. Film management workspace transitions — migrate when product entry points are finalized;
4. debug-only diagnostic screens may remain local `Navigator` routes unless deep linking or workspace-level navigation is needed.

Local modal dismissal such as `Navigator.pop` for a bottom sheet is not part of this migration.

## Dependency

```yaml
go_router: ^17.3.0
```

The application root uses `MaterialApp.router` with one persistent `GoRouter` instance owned by `PixelCraftApp`.

## Guardrails

- Do not add routes for sliders, Film/Filter/Adjust selection, bottom sheets, or other direct-manipulation states.
- Do not encode arbitrary local file paths as public route parameters.
- Do not move Rust edit authority into routing state.
- Do not let navigation become the canonical source of editor recipe/history state.
- Add a route only when the destination represents a meaningful workspace/screen boundary or needs deep-link/external-entry semantics.

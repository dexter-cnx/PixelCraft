# G2.6 Editor GPU / Session Hardening

## Status

**G2.6 CLOSED on the iOS G2 reference device.**

The rapid-switching / repeated-slider stress gate passed without stale Metal overlays or reported unhandled async errors. Host-wide regression commands remain part of the final G2 merge gate in `docs/G2_FINAL_VERIFICATION.md`.

## Goal

G2.6 does not add new image effects. It hardens the existing iOS Metal live-draft path so asynchronous native work can never override a newer editor state.

Rust remains authoritative for committed preview state, history, checkpoints and export.

## Failure model

The Editor must safely handle:

- rapid tool switching while a GPU activation is in flight;
- a slider update arriving after the active GPU draft has changed;
- a Rust checkpoint changing while an old renderer/source is still alive;
- Original-view requests while GPU LIVE is visible;
- native MethodChannel / Metal renderer failure during a slider gesture;
- renderer creation resolving after the editor session already invalidated it;
- Editor busy/error transitions while a GPU overlay is active.

## Generation guards

Two independent monotonically increasing generations are used.

### GPU activation serial

`_gpuActivationSerial`

Every new live draft receives the current serial. Async source upload, draft application and commit handoff must compare against it before changing visible GPU state.

Invalidating a draft increments the serial, making every older async continuation stale.

### Renderer epoch

`_gpuRendererEpoch`

Renderer creation captures the current epoch. If `createRenderer()` resolves after the epoch changes, the newly created native renderer is destroyed immediately and is never installed into Editor state.

A native live-update failure drops the current renderer and increments the epoch so the next eligible gesture creates a clean renderer.

## Central invalidation

The Editor invalidates GPU draft presentation when:

- selected tool changes;
- Rust checkpoint (`originalPreviewBytes`) changes;
- Original preview is requested;
- Editor enters a busy state;
- Editor reports a new error;
- native activation/update fails.

Checkpoint changes additionally clear `_gpuOwnedDraftKind/_gpuOwnedDraftKey` because the ownership optimization is only valid for the checkpoint it was derived from.

## Native failure rule

Errors from realtime `setAdjustments`, `setCreative` or `setFilm` are caught even though slider updates are launched asynchronously.

On failure:

```text
native error
  -> invalidate activation serial
  -> hide GPU overlay
  -> destroy/drop renderer
  -> increment renderer epoch
  -> keep Rust preview visible
```

The slider release still commits through the normal Rust controller path.

## Verification gate

On the physical G2 reference device:

1. Start dragging Brightness until `GPU LIVE`, then immediately switch to Crop/Rotate. The Metal overlay must disappear and must not reappear late.
2. Rapidly alternate Adjust -> Film -> Filters and drag each slider. The visible live draft must always match the currently selected tool.
3. While `GPU LIVE`, long-press for Original. GPU overlay must disappear immediately and Rust Original view must remain authoritative.
4. Complete a GPU edit, then Apply edits so the Rust checkpoint changes. The next GPU gesture must use the new checkpoint, not the previous image.
5. Perform Undo/Redo/Crop/Straighten after GPU edits. No stale Metal overlay may return after the Rust transform completes.
6. Repeat rapid slider gestures for at least 30-60 seconds. No unhandled MethodChannel/Future error should appear in the Flutter log.
7. Normal G2 parity/latency diagnostics must remain unaffected.

## Closure evidence

The physical-device stress sequence above was performed and reported PASS. In particular:

- rapid tool switching did not resurrect a stale GPU overlay;
- repeated slider interaction remained stable;
- no editor-state corruption was observed;
- no unhandled MethodChannel/Future error was reported during the stress pass;
- Rust remained the visible fallback/authority whenever the GPU draft was invalidated.

G2.6 is therefore closed. The final branch-wide analyzer/test/Rust/LUT gate is tracked separately by `tool/verify_g2.sh` and `docs/G2_FINAL_VERIFICATION.md`.

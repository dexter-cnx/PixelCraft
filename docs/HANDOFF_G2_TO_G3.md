# PixelCraft Handoff — G2 Closure → G3

## Purpose

Use this file as the starting context when opening a new ChatGPT conversation after the G2 editor GPU work. Read this file first, then inspect the current branch/HEAD before making further changes.

## Repository / branch

- Repository: `dexter-cnx/PixelCraft`
- Current working branch during G2: `feature/camera-film-preview`
- Rust remains the authoritative renderer for committed edits, history, checkpoints and export.
- Dart/Flutter is the control/UI layer.
- Live camera frame buffers must not cross MethodChannel / Flutter Rust Bridge.

## G2 status

G2 implementation work is functionally complete and is in closure/merge-ready verification.

### Completed areas

- G2.0 editor Metal lab
- G2.1 production editor GPU integration
- G2.2 realtime Sharpen
- G2.3 Gaussian Blur parity + realtime path
- G2.4 Creative filters
  - grayscale / invert native Metal compute
  - vintage / oceanic / lofi / dramatic / golden / pastel_pink via Rust-generated canonical 33^3 LUTs
- G2.5 Transform Preview
  - realtime compositor straighten preview
  - interactive normalized crop overlay
  - source-pixel-space aspect-ratio correction
  - crop regression tests
- G2.6 editor GPU/session hardening
  - stale activation cancellation
  - renderer epoch guard
  - native failure fallback
  - rapid tool switching / Original-view invalidation
- Draft composition semantics
  - Adjust values are independent slots and are remembered before Apply
  - Creative has one mutually-exclusive draft slot with per-preset intensity memory
  - Film has one mutually-exclusive draft slot with per-profile strength memory
  - tool switching does not imply Apply or Cancel

## Important G2 verification evidence

Do not invent additional metrics beyond these recorded results.

### Editor adjustment parity

Deterministic Metal vs Rust u8 parity passed with overall max delta approximately `0.00192630`, tolerance `1/255`.

### Editor adjustment + Film latency

On the iOS G2 reference device (Apple A13):

- average ~1.228 ms
- p50 ~1.121 ms
- p95 ~1.930 ms
- p99/max ~2.560 ms

Target p95 <= 16.67 ms: PASS.

### Sharpen

Numeric parity cases passed with max deltas:

- 0.5: `0.00000012`
- 1.0: `0.00000024`
- 1.5: `0.00000048`

### Gaussian Blur

Deterministic fixture parity passed with overall max delta `0.00000000` for values `.25, .5, 1, 1.5, 2`.

Realtime blur benchmark on A13 at 1024^2, blur value 2 / sigma 5:

- avg 7.778 ms
- p50 7.856 ms
- p95 9.007 ms
- p99/max 9.776 ms

Target p95 <= 16.67 ms: PASS.

### Creative filters

- grayscale / invert parity passed exactly for intensities .25 / .50 / 1.00.
- six Photon presets use Rust-generated 33^3 LUTs and the already-verified Film LUT loader/sampler path.
- G2.4 closure is compositional; no direct Rust-Photon-vs-interpolated-LUT numeric max-delta was measured. Do not claim one.

### Transform / Crop

- realtime straighten functional validation passed on physical iOS device.
- interactive crop functional validation passed.
- crop aspect ratios are defined in source-pixel space, not normalized-square space.
- duplicate crop controls were removed.

### G2.6 hardening

Physical-device stress validation passed:

- rapid tool switching
- repeated slider gestures
- Original view while GPU LIVE
- Apply / Undo / Redo / Crop / Straighten after GPU edits
- no stale Metal overlay returning
- no reported unhandled MethodChannel/Future error during the stress run

## Key contracts

### Rust authority

Committed/final path:

```text
Editor UI / GPU draft
  -> Rust edit graph
  -> authoritative preview/history
  -> full-resolution export
```

GPU/compositor paths are interactive previews only.

### Camera contract

Camera Film is preview-only and must not be baked into the captured clean source image.

### Film LUT contract

- canonical LUT size: 33 x 33 x 33
- Android runtime atlas: 198 x 198 RGBA8 tiled LUT
- iOS: same atlas remapped to `MTLTextureType3D`
- texel-center rule: `(color * 32 + 0.5) / 33`

### Draft composition

Before editor-level Apply, the active draft may contain multiple independent core adjustments plus one Creative slot plus one Film slot.

Example:

```text
Brightness 1.20
Contrast   1.30
Saturation 0.85
Vintage    0.60
Velvia     0.70
```

Switching controls/tools must not reset these values.

Relevant contract: `docs/EDITOR_DRAFT_COMPOSITION.md`.

## G2 closure files

Read these before changing G2 behavior:

- `docs/G2_FINAL_VERIFICATION.md`
- `docs/G2_4_CREATIVE_LUT_CONTRACT.md`
- `docs/G2_5_TRANSFORM_PREVIEW_CONTRACT.md`
- `docs/G2_6_EDITOR_GPU_HARDENING.md`
- `docs/EDITOR_DRAFT_COMPOSITION.md`

Host verification script:

```bash
bash tool/verify_g2.sh
```

Expected successful ending:

```text
[Pixel Craft] G2 HOST GATE: PASS
```

The script is intended to cover analyzer, Dart tests, Golden tests, Rust fmt/clippy/tests, and GPU LUT verification.

## Remaining action before declaring G2 fully CLOSED / MERGED

On the latest HEAD:

```bash
git pull
bash tool/verify_g2.sh
```

Then perform one final physical-device smoke test:

```text
Camera Film preview
-> capture clean image
-> Adjust several controls without Apply
-> revisit Adjust controls and confirm remembered values
-> Creative
-> Film
-> Sharpen
-> Gaussian Blur
-> Crop
-> Straighten
-> Rotate / Flip
-> Undo / Redo
-> Cancel
-> create edits again
-> Apply
-> Export
```

Acceptance conditions:

- host gate passes
- no stale GPU overlay
- Adjust memories remain correct before Apply
- Apply/Cancel semantics remain correct
- Undo/Redo remain recipe-authoritative
- camera Film remains preview-only
- exported image comes from Rust full-resolution rendering

After this, G2 is CLOSED and `feature/camera-film-preview` is merge-ready. Avoid adding new product scope to G2 after closure.

# Next plan — G3 Production Editor GPU Pipeline

G3 should start on a fresh branch after G2 is merged. Suggested branch:

```text
feature/editor-gpu-production
```

## G3.0 Baseline / branch setup

Goal: freeze G2 as the behavioral baseline before extending GPU composition.

Tasks:

1. merge G2 branch after final gate passes
2. create fresh G3 branch from updated `main`
3. record baseline test/golden status
4. keep G2 diagnostics available in debug builds
5. do not change Rust operation semantics as part of branch setup

Exit gate: G3 branch starts from a clean, verified G2 baseline.

## G3.1 Multi-adjustment GPU composition — highest priority

Current Rust draft semantics allow multiple Adjust slots to coexist. The Metal live preview must render the entire active adjustment state, not only the slider currently being dragged.

Target model:

```text
Editor draft state
  |- brightness
  |- contrast
  |- saturation
  |- sharpen
  `- gaussian blur
       |
       v
GpuEditorAdjustmentState
       |
       v
Metal pipeline
       |
       v
composed realtime preview
```

Required behavior example:

```text
Brightness = 1.20
Contrast   = 1.30
Saturation = 0.85
```

When the user revisits Brightness and drags to 1.25, the Metal preview must show Brightness 1.25 + Contrast 1.30 + Saturation 0.85 together.

Do not regress the remembered-slider-value behavior fixed at the end of G2.

Suggested work:

- expose/read complete active Adjust control state from controller
- populate `GpuEditorAdjustmentState` from all active adjustment memories
- only override the currently dragged value with the transient slider value
- preserve Rust commit-on-release semantics
- add deterministic composition tests
- add a parity harness for representative multi-adjust combinations

Exit gate: GPU live draft matches Rust semantics for multiple simultaneous Adjust slots.

## G3.2 Cross-tool GPU composition

Goal: Metal preview represents the composed active draft across Adjust + Creative + Film where the native paths support it.

Target example:

```text
Brightness 1.20
+ Contrast 1.30
+ Vintage 0.60
+ Velvia 0.70
```

Potential pipeline:

```text
source/checkpoint
 -> core adjustments
 -> creative compute or creative LUT
 -> Film LUT
 -> presentation
```

The exact ordering must match Rust recipe semantics. Do not assume an order without inspecting the authoritative Rust edit graph and recipe order.

Required work:

- define operation-order contract between active draft slots
- represent complete GPU draft state instead of one `(kind,key,value)` tuple
- update renderer state atomically where possible
- verify combinations against Rust
- preserve fallback if any node is unsupported

Exit gate: supported cross-tool combinations visually/numerically match the Rust draft within the agreed tolerance.

## G3.3 Production renderer lifecycle

Goal: make the Metal editor path production-safe beyond debug/demo usage.

Cover:

- app background -> foreground
- renderer/view recreation
- orientation / layout resize
- image/source replacement
- memory-pressure recovery where observable
- stale platform-view/native renderer cleanup
- deterministic Rust fallback
- rapid reopen/close of Editor

Debug-only `GPU READY` / `GPU LIVE` UI should eventually be removed or hidden from production builds once lifecycle visibility is no longer needed.

Exit gate: renderer recreation/fallback is transparent to normal editing behavior.

## G3.4 GPU session state model cleanup

The G2 implementation intentionally grew incrementally. G3 should consolidate state so GPU draft ownership is explicit and testable.

Potential direction:

```text
GpuEditorDraftState
  checkpointGeneration
  adjustments
  creative
  film
  activationGeneration
  rendererGeneration
  status
```

Avoid duplicating the Rust edit graph. This model is presentation/native-render state only.

Goals:

- reduce ad-hoc `_gpuDraftKind/_gpuDraftKey/_gpuDraftValue` state
- centralize invalidation rules
- make stale-work tests easier
- preserve Rust as the only semantic source of truth

## G3.5 Verification / release gate

Before calling the production editor GPU path complete:

- Flutter analyzer/test suite passes
- Rust fmt/clippy/tests pass
- LUT verification passes
- single-adjust parity remains passing
- multi-adjust parity added and passing
- representative Adjust + Creative + Film combinations verified
- latency remains within realtime target on reference device
- app lifecycle smoke test passes
- no stale overlay/native error after repeated editor sessions
- full-resolution export remains Rust-authoritative

Create a `docs/G3_FINAL_VERIFICATION.md` when this phase approaches closure.

## Deferred / non-goals unless evidence changes

- Do not duplicate Photon preset algorithms in Metal; continue preferring Rust-generated canonical LUTs.
- Do not move live camera pixel buffers through Dart.
- Do not make GPU output authoritative for final export.
- Quarter-turn/flip do not need a continuous GPU implementation unless profiling/user experience demonstrates a real need.
- A direct Photon-vs-33^3-interpolated-LUT error characterization may be added later if product/color requirements demand it, but it was not part of the G2 closure evidence.

## Recommended first action in the next chat

After reading this file, first verify whether G2 was already merged.

If not merged:

```text
1. inspect current branch/HEAD
2. run/review final G2 host gate result
3. confirm final physical smoke result
4. merge G2
```

If G2 is already merged:

```text
1. create/switch to feature/editor-gpu-production
2. inspect EditorController draft-memory model
3. inspect EditorScreen GPU draft state
4. begin G3.1 Multi-adjustment GPU composition
```

The highest-value next implementation is **G3.1 Multi-adjustment GPU composition**.

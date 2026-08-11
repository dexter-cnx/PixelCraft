# G3 Physical-Device Verification

This checklist closes the device-only evidence required after host CI for G3.1-G3.4.

## Prerequisites

- Use a physical iPhone/iPad with Metal support.
- Build from `feature/editor-gpu-production` at the PR #6 head being verified.
- Keep the app in Debug for diagnostics.
- Confirm the device appears in `flutter devices`.

## Automated device gate

Run either:

```bash
DEVICE=<ios-device-id> make g3-device-verify
```

or directly:

```bash
DEVICE=<ios-device-id> bash tool/verify_g3_device.sh
```

The verification runner deliberately does **not** use the normal development bundle id. Before the test it temporarily changes only the Runner build configurations from:

```text
dev.cnxdev.pixelcraft
```

to:

```text
dev.cnxdev.pixelcraft.g3verify
```

It then restores `ios/Runner.xcodeproj/project.pbxproj` byte-for-byte through a shell trap, including when the test fails or is interrupted. The normal PixelCraft development install therefore remains a separate app and is not the integration-test uninstall target.

The runner uses one consolidated Flutter integration-test invocation, so the device sees one verification-app install/test session instead of the previous two install/uninstall cycles.

The single suite `integration_test/g3_editor_gpu_verification_test.dart` executes:

1. native Metal capability and identity LUT parity
2. all six Film Profile Pack v2 LUT parity cases
3. G3.1 adjustment parity against Rust reference semantics
4. Gaussian Blur parity
5. G3.2 Creative compute parity
6. representative adjustment + Film latency benchmark
7. representative heavy Blur latency benchmark
8. 12 renderer destroy/recreate cycles

### Automated acceptance gates

- All test cases pass.
- Adjustment parity `overallMaxChannelError <= tolerance`.
- Gaussian Blur parity `overallMaxChannelError <= tolerance`.
- Creative compute parity `overallMaxChannelError <= tolerance`.
- Adjustment + Film p95 `<= targetMs` (16.67 ms target in the native harness).
- Blur p95 `<= targetMs`.
- All 12 renderer recreation cycles complete without native error.
- All six Film LUT parity cases remain below their existing native tolerance.

Note: Flutter may still uninstall the temporary `dev.cnxdev.pixelcraft.g3verify` verification app after the integration test. That is expected and does not remove the normal `dev.cnxdev.pixelcraft` development install.

Copy the significant `[G3...]` output lines into `docs/G3_FINAL_VERIFICATION.md` when closing the milestone.

---

## Manual G3.1 — Multi-adjust semantics

Use one normal camera/gallery image with visible highlights, shadows, color, and fine detail.

1. Open Editor.
2. Set Brightness to a visibly non-neutral value.
3. Switch to Contrast and set a visibly non-neutral value.
4. Switch to Saturation and set a visibly non-neutral value.
5. Return to Brightness and drag it continuously.
6. Confirm Contrast and Saturation remain visibly applied during the Brightness drag.
7. Release the slider and confirm there is no visible semantic jump between Metal draft and settled Rust preview beyond expected minor numeric parity tolerance.
8. Repeat with Sharpen + Gaussian Blur active together.
9. Undo/Redo and repeat one drag.

Pass criteria:

- Previously active Adjust slots remain composed while another Adjust slider is dragged.
- No stale overlay appears after release, Undo, or Redo.
- Rust settled preview remains authoritative.

---

## Manual G3.2 — Cross-tool composition and faithful fallback

### Case A — representable composition

Create an active draft whose authoritative recipe order is representable by the current Metal pipeline, for example:

```text
Brightness / Contrast / Saturation
then grayscale or invert
then Film
```

Drag one currently active control and confirm the complete supported draft remains visible.

Pass criteria:

- Adjust + supported Creative compute + Film remain composed when the recipe order is representable.
- Releasing the control settles to the Rust preview without stale native state.

### Case B — deliberate fallback

Create a state the current native renderer cannot represent faithfully, such as:

- a transform node mixed into the active draft, or
- a Creative LUT preset plus Film when both would require the single native LUT slot in an incompatible ordered plan, or
- an order not supported by the current native fixed pipeline.

Then start dragging a control.

Pass criteria:

- Metal overlay does **not** partially lie about the recipe.
- App stays on the valid Rust preview.
- Editing and release still work.
- No semantic node is lost or reordered.

---

## Manual G3.3 — Renderer lifecycle stress

### Background / foreground

Repeat 10 times:

1. Open Editor with a non-neutral draft.
2. Start a GPU-eligible slider interaction and release it.
3. Send the app to background.
4. Wait 2-5 seconds.
5. Return to foreground.
6. Start another GPU-eligible slider interaction.

Pass criteria:

- Foreground first shows a valid Rust preview.
- GPU renderer is recreated lazily when needed.
- No old source/checkpoint flashes over the current preview.
- No crash, black persistent overlay, or corrupted edit state.

### Editor reopen / close

Repeat 10 times:

1. Enter Editor.
2. Make at least one adjustment.
3. Leave Editor.
4. Open Editor again with another source or restored session.

Pass criteria:

- No renderer from the previous Editor becomes visible.
- No previous image/source leaks into the new session.
- Renderer destruction/recreation remains transparent.

### Camera -> Editor

Repeat at least 5 times:

1. Open Film Camera.
2. Capture a clean image.
3. Enter Editor.
4. Make a GPU-eligible edit.
5. Exit and repeat.

Pass criteria:

- Camera Film remains preview-only.
- Editor source is the clean capture.
- No stale Camera/Editor native overlay crosses sessions.

### Memory-pressure/manual interruption

While Editor is open, create normal OS pressure where practical (background the app and use other apps), then return.

Pass criteria:

- If native renderer resources are dropped, Rust preview remains valid.
- A later GPU interaction either recreates a valid renderer or deterministically stays on Rust fallback.

---

## Manual G3.4 — Presentation state cleanup behavior

Verify these state transitions while using the app:

- starting a gesture cannot activate an older asynchronous renderer after a newer gesture/checkpoint
- changing checkpoint invalidates the previous GPU draft
- Original/Before view never leaves a native overlay above the original image
- native update failure does not mutate Rust semantic state
- debug GPU labels are absent from Release builds

Pass criteria:

- presentation state may fail/recreate independently, but Rust recipe/history/export remain correct.

---

## Export authority smoke

After the combined stress above:

1. Apply/settle edits.
2. Export full resolution.
3. Reopen/exported image or inspect it in Photos.

Pass criteria:

- Export contains the authoritative Rust edit result.
- GPU preview state is not used as the source of final pixels.

---

## Evidence template

Paste this into `docs/G3_FINAL_VERIFICATION.md` and fill it after the run:

```text
G3 physical device:
Device model:
iOS version:
Commit:
Date:

Automated native Film/LUT parity: PASS / FAIL
G3 adjustment parity max delta:
G3 blur parity max delta:
G3 creative compute parity max delta:
G3 adjustment+Film latency avg/p95/p99/max:
G3 blur latency avg/p95/p99/max:
Renderer recreate 12 cycles: PASS / FAIL

Multi-adjust manual semantic check: PASS / FAIL
Cross-tool representable composition: PASS / FAIL
Explicit unsupported-plan Rust fallback: PASS / FAIL
Background/foreground x10: PASS / FAIL
Editor reopen x10: PASS / FAIL
Camera -> Editor x5: PASS / FAIL
Original/Before overlay invalidation: PASS / FAIL
Full-resolution Rust export smoke: PASS / FAIL

Notes:
```

G3 is not closed merely because the automated harness passes. The lifecycle and faithful-fallback checks above are part of the production-runtime exit gate.

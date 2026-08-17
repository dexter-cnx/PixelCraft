# PF2 Physical-Device Validation Checklist

## Purpose

This checklist is the physical-device gate for **PF2 Unified Camera Film / Filter / Adjust** on PR #48.

Automated validation is already green on exact head:

```text
branch: feature/pf2-unified-camera-look
head: b4451dce62bd877435cdab4ddd69c3f69cc037cd
CI: #420 / run 31946914217
result: SUCCESS
```

PF2 must **not** be marked complete or ready to merge until the required physical-device checks below pass and evidence is recorded.

The current native preview pipeline is:

```text
camera frame
 -> Adjust
 -> Film
 -> Creative Filter
 -> display
```

Rust remains authoritative for final pixels. Metal/OpenGL ES remain preview-only.

---

# 1. Test devices

Record each device used.

| Field | Device 1 | Device 2 |
|---|---|---|
| Platform | iOS / Android | iOS / Android |
| Device |  |  |
| OS version |  |  |
| Build mode | debug / profile / release | debug / profile / release |
| Commit | `b4451dce62bd877435cdab4ddd69c3f69cc037cd` | `b4451dce62bd877435cdab4ddd69c3f69cc037cd` |
| Result | PENDING | PENDING |

Reference iOS hardware already available in the project:

```text
iPhone 11
UDID: 00008030-0004694C3E68C02E
```

Do not uninstall or overwrite unrelated verifier/test applications as part of this validation.

---

# 2. Launch / basic camera gate

- [ ] App launches successfully into Camera on phone/tablet.
- [ ] Camera preview appears without black frame, frozen frame, stretch, crop regression, or obvious color corruption.
- [ ] Film / Filter / Adjust controls are visible on the verified native GPU path.
- [ ] Gallery, Shutter, and Controls remain usable.
- [ ] No immediate crash, native exception, renderer failure, or repeated error loop.
- [ ] Orientation/layout remains usable for the supported orientation policy.

Pass condition: Camera is immediately usable and the PF2 controls reflect actual preview capability.

---

# 3. Neutral look / baseline

Start from a neutral look.

- [ ] Film = neutral/off.
- [ ] Filter = Original.
- [ ] Brightness = default.
- [ ] Contrast = default.
- [ ] Saturation = default.
- [ ] Preview is visually neutral and does not retain stale Film/Filter/Adjust from a previous state unexpectedly.
- [ ] Returning individual controls to default restores the expected neutral result.

Pass condition: neutral state behaves as a true bypass and does not leave hidden processing active.

---

# 4. Film validation

Test several canonical Film profiles, including repeated switching.

- [ ] Selecting a Film changes the live preview.
- [ ] Film strength changes continuously and predictably.
- [ ] Strength 0 behaves as neutral Film contribution.
- [ ] Strength 1 applies the full Film contribution.
- [ ] Rapidly switch between at least 5 Film profiles.
- [ ] Final visible Film always matches the final selected Film.
- [ ] No stale Film LUT appears after a newer Film has already been selected.
- [ ] Switching away from Film tab and back preserves the selected Film and strength.

Pass condition: Film state is stable, latest-value-wins, and does not regress under rapid selection.

---

# 5. Creative Filter validation

Test all PF2 Creative Filter classes.

## Exact-operation filters

- [ ] `grayscale` changes preview correctly.
- [ ] `invert` changes preview correctly.

## LUT-backed filters

- [ ] `vintage`
- [ ] `oceanic`
- [ ] `lofi`
- [ ] `dramatic`
- [ ] `golden`
- [ ] `pastel_pink`

For each representative filter:

- [ ] Filter intensity changes continuously.
- [ ] Intensity 0 returns to Original contribution.
- [ ] Intensity 1 applies the full filter contribution.
- [ ] Rapid filter switching does not display an older filter after the latest selection.
- [ ] Switching tabs preserves Filter state.

Pass condition: every exposed filter is real, responsive, stable, and independent from Film/Adjust state.

---

# 6. Adjust validation

PF2 realtime Adjust scope is limited to:

```text
brightness
contrast
saturation
```

For each adjustment:

- [ ] Drag from minimum toward maximum continuously.
- [ ] Drag rapidly back and forth for several seconds.
- [ ] Release at a clearly identifiable final value.
- [ ] Final preview matches the final slider position.
- [ ] UI remains responsive while dragging.
- [ ] Preview updates continuously enough to feel interactive.
- [ ] No delayed stale update overwrites the final value after release.
- [ ] Returning to default restores expected appearance.
- [ ] Switching tabs preserves the adjustment value.

Pass condition: continuous adjustment is responsive and latest-value-wins behavior is correct.

---

# 7. Combined Film + Filter + Adjust

This is a required PF2 correctness gate.

Set a clearly visible combination, for example:

```text
Film: non-neutral profile at high strength
Filter: LUT-backed Creative filter at medium/high intensity
Brightness: non-default
Contrast: non-default
Saturation: non-default
```

Then verify:

- [ ] Film remains active after changing Filter.
- [ ] Filter remains active after changing Adjust.
- [ ] Adjust remains active after changing Film.
- [ ] Switching among Film / Filter / Adjust tabs never clears the other layers.
- [ ] Result visibly reflects all three layers together.
- [ ] Returning only one layer to neutral changes only that layer.
- [ ] Re-applying that layer restores the combined look.
- [ ] Rapidly modify all three categories in succession; final preview matches the final complete state.

Pass condition: all three layers coexist and preserve the frozen order **Adjust -> Film -> Creative** without state loss.

---

# 8. Rapid-switch / stale-state stress

Perform at least 20–30 rapid interactions across Film, Filter, and Adjust.

Example sequence:

```text
Film A
 -> Filter vintage
 -> brightness drag
 -> Film B
 -> Filter dramatic
 -> saturation drag
 -> Film C
 -> Filter grayscale
 -> contrast drag
 -> final known state
```

Verify:

- [ ] No crash.
- [ ] No frozen preview.
- [ ] No old Film/Filter appears after the final selection.
- [ ] No slider value jumps backward after release.
- [ ] Final preview corresponds to the final UI state.
- [ ] UI and native renderer remain synchronized.

Pass condition: stale asynchronous LUT/resource work never resurrects an older look.

---

# 9. Sustained preview / thermal / frame pacing

Run Camera continuously for at least **5 minutes** with a non-neutral Film + Filter + Adjust combination.

During the run:

- [ ] Pan camera across detailed/high-contrast scenes.
- [ ] Move camera continuously for at least 30 seconds.
- [ ] Change Film several times.
- [ ] Change Filter several times.
- [ ] Drag Adjust sliders repeatedly.

Observe:

- [ ] Preview remains smooth enough for normal camera use.
- [ ] No progressive frame-rate collapse.
- [ ] No long stalls when LUT-backed Film/Filter changes.
- [ ] No frame freezing.
- [ ] No recurring flash of neutral/previous look.
- [ ] Device does not become abnormally hot for this workload.
- [ ] Controls remain responsive after sustained use.

Record subjective result:

```text
frame pacing: PASS / FAIL / NOTES
thermal: PASS / FAIL / NOTES
interaction latency: PASS / FAIL / NOTES
```

If available, attach profiler/frame-time evidence, but physical usability observations are still required.

---

# 10. Camera/lens switching

When supported by the device:

- [ ] Select a non-neutral Film + Filter + Adjust state.
- [ ] Switch front/back camera.
- [ ] Switch again multiple times.
- [ ] Preview resumes correctly after each switch.
- [ ] No black/frozen preview.
- [ ] No native crash.
- [ ] Look state remains correct or is reset only if the product contract explicitly requires reset.
- [ ] Filter/Adjust availability matches the renderer actually in use.

Pass condition: lens/session recreation does not desynchronize or resurrect stale camera-look state.

---

# 11. App lifecycle

With a non-neutral combined look active:

- [ ] Send app to background.
- [ ] Wait several seconds.
- [ ] Return to foreground.
- [ ] Camera preview resumes.
- [ ] Film/Filter/Adjust state remains coherent.
- [ ] Repeat background/foreground at least 3 times.
- [ ] Lock/unlock device once if practical.
- [ ] No crash, frozen renderer, duplicated session, or stale state appears.

Pass condition: renderer detach/reattach generation handling prevents stale requests from affecting the resumed session.

---

# 12. Shutter / temporary PF2 capture -> editor handoff

PF3 is not implemented yet. PF2 currently captures a clean JPEG and replays `CameraLookState` through the Rust-backed editor.

Test with a clearly non-neutral Film + Filter + Adjust combination.

- [ ] Press Shutter while the preview is stable.
- [ ] Press Shutter immediately after moving an Adjust slider and releasing at a known final value.
- [ ] Handoff uses the final committed CameraLookState, not an older pending preview state.
- [ ] Editor opens successfully.
- [ ] Film is present in editor result.
- [ ] Creative Filter is present in editor result.
- [ ] Brightness/Contrast/Saturation are present in editor result.
- [ ] Combined result follows deterministic order Adjust -> Film -> Creative.
- [ ] No intermediate adjustment is lost because of latest-value-wins coalescing.
- [ ] Source capture remains clean internally; preview framebuffer is not used as saved-output authority.

Pass condition: the captured/edit result corresponds to the final visible selected look without using GPU preview pixels as final authority.

---

# 13. Gallery source neutrality

- [ ] Set a strongly non-neutral Camera Film + Filter + Adjust state.
- [ ] Open Gallery.
- [ ] Pick an existing source image.
- [ ] Gallery-picked source enters editor without inheriting the current Camera look automatically.
- [ ] Original source remains untouched.

Pass condition: Camera look is not leaked into Gallery-originated editing sessions.

---

# 14. Runtime failure / fallback

Where practical, exercise a native preview failure/fallback path. If failure cannot be safely induced on the physical test device, record this item as `NOT INDUCED` and rely on automated failure-path coverage.

Expected behavior on real runtime failure:

```text
native runtimeFailure
 -> detach CameraLookPreviewCoordinator
 -> destroy failed native renderer
 -> fall back to Flutter camera path
 -> visible look reduces to Film-only
 -> Filter/Adjust controls are hidden/unavailable
```

Verify if induced:

- [ ] App remains usable.
- [ ] No hidden Filter/Adjust state continues to affect capture.
- [ ] Filter/Adjust controls disappear when faithful native preview is unavailable.
- [ ] Film-only fallback remains coherent.
- [ ] No crash loop or repeated renderer recreation loop.

Pass condition: failure is fail-closed rather than silently showing a preview that differs from capture semantics.

---

# 15. Localization / control integrity

- [ ] English labels render correctly.
- [ ] Thai labels render correctly.
- [ ] Film / Filter / Adjust tabs remain usable with translated labels.
- [ ] Slider values are readable and do not clip.
- [ ] Filter names/labels do not overflow in common phone layouts.

Pass condition: PF2 controls remain operable in both supported locales.

---

# 16. Regression smoke

Before signing off PF2:

- [ ] Gallery picker still opens existing editor flow.
- [ ] Camera Controls/settings still open.
- [ ] Shutter lockout prevents accidental concurrent capture.
- [ ] Existing Film-only behavior is not regressed.
- [ ] No obvious navigation regression.
- [ ] No obvious permission/camera-availability regression.
- [ ] App can be closed and relaunched normally.

---

# 17. Evidence to record

For every physical-device run record:

```text
date/time:
device:
OS:
build mode:
commit:
CI baseline:
launch/basic camera:
neutral baseline:
Film:
Filter:
Adjust:
Film+Filter+Adjust:
rapid-switch stress:
sustained preview/frame pacing:
thermal observation:
lens switching:
lifecycle:
shutter/editor handoff:
Gallery neutrality:
runtime fallback:
localization:
regression smoke:
overall result:
notes:
```

Optional but useful evidence:

- short screen recording showing combined look and rapid switching;
- profiler/frame-time capture;
- device log excerpt for any failure;
- screenshot of final combined state and editor handoff result.

---

# 18. PF2 close criteria

PF2 may be marked ready for review only when:

- [x] exact-head automated CI is green (`b4451dce...`, CI #420 / run `31946914217`);
- [x] Flutter analyze/tests pass through CI;
- [x] Rust fmt/clippy/tests and image characterization pass through CI;
- [x] GPU LUT parity and package gates pass through CI;
- [x] Android/iOS build/package gates pass through CI;
- [ ] required physical-device checklist passes;
- [ ] sustained-preview/frame-pacing result is acceptable;
- [ ] device evidence is recorded;
- [ ] `PROJECT_HANDOFF.md`, `CODE_WALKTHROUGH.md`, `PF2_CAMERA_LOOK_CONTRACT.md`, and `README.md` reflect the verified final state;
- [ ] PR #48 is changed from Draft to Ready only after the physical-device gate passes.

After merge:

- [ ] verify resulting `main` CI;
- [ ] update final PF2 status to merged/verified;
- [ ] remove the merged feature branch when no longer needed;
- [ ] proceed to PF3 only after the merged baseline is confirmed green.

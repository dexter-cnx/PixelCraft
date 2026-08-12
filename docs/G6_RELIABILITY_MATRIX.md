# G6 Reliability / Performance / Device Matrix

Status: IN PROGRESS
Branch: `feature/g6-reliability-matrix`
Base: `main` after PR #8 (`b6c898a8b4dfc3b0ac2a5ed26f12eea6e58a04a7`)

G6 does not change image semantics. Rust remains authoritative for committed edits, recipe/history/checkpoints/recovery and full-resolution export. Native GPU paths remain preview-only and must fail closed to a valid Rust/product state.

## Evidence rules

- Record only tests that were actually run.
- Keep functional smoke, characterization and numeric performance evidence separate.
- Record device, OS, backend and commit SHA for device measurements.
- Do not infer numeric parity for G5 controls that intentionally commit through Rust.
- A failure is useful G6 evidence; do not hide it by changing thresholds until root cause is understood.
- Physical-device automation must not uninstall or overwrite the developer's installed PixelCraft main app (`dev.cnxdev.pixelcraft`). G6 uses an isolated verifier app id (`dev.cnxdev.pixelcraft.g6verify`).
- Physical-device automation must not mutate the checkout/Xcode project that the developer has open. Verifier bundle/application-id changes are applied only inside a temporary detached git worktree and that worktree is removed when the run exits.

---

## G6.0 Clean baseline

Required host baseline:

```bash
bash tool/g6_host_baseline.sh
```

Equivalent gates:

```text
flutter analyze
make test
make golden-test
make rust-fmt
make rust-clippy
make rust-test
make gpu-lut-verify
```

Record:

| Field | Value |
|---|---|
| Commit | `6c63e60d9e9776bc4f10fc7273b17d35c7c19a6f` |
| Flutter | 3.44.7 |
| Dart | 3.12.2 |
| Rust | 1.95.0 |
| Cargo | 1.95.0 |
| Host OS | macOS / Darwin arm64 |
| Result | PASS via `tool/g6_complete_remaining.sh` |
| Evidence path | `build/g6/baseline/` and `build/g6/final/` |

Exit criterion: all existing host gates green on the G6 branch before reliability findings are classified as regressions.

---

## G6.1 Image-size matrix

Target tiers where hardware permits:

| Tier | Approximate size | Required orientations/formats |
|---|---:|---|
| small | existing sample fixture | PNG baseline |
| 12 MP | ~4000 x 3000 | portrait + landscape, JPEG; PNG/WebP where fixture is available |
| 24 MP | ~6000 x 4000 | portrait + landscape, JPEG |
| 48 MP | ~8000 x 6000 | portrait + landscape, JPEG |

Additional coverage:

- square source
- EXIF orientation for JPEG
- alpha for PNG/WebP where applicable
- missing/invalid source as G6.5 failure injection

Measure where practical:

- source dimension probe / Editor startup
- reduced-preview preparation
- representative Rust adjustment release
- Apply checkpoint
- Undo / Redo
- full-resolution JPEG/PNG/WebP export
- process RSS before/after and peak delta where exposed

Representative operation classes:

```text
Exposure       simple scalar
Highlights     luminance-selective
Temperature    color bias
Grain          deterministic coordinate effect
Curve/HSL      advanced scalar recipe operations
Gaussian Blur  existing heavy path
Film Profile   multi-operation materialization/replay
```

Host characterization harness:

```bash
# Defaults to the 12 MP tier.
cargo test --manifest-path rust/Cargo.toml --test g6_image_matrix -- --ignored --nocapture

# Extend through 24 MP or 48 MP only on a host with sufficient memory.
G6_MAX_MP=24 cargo test --manifest-path rust/Cargo.toml --test g6_image_matrix -- --ignored --nocapture
G6_MAX_MP=48 cargo test --manifest-path rust/Cargo.toml --test g6_image_matrix -- --ignored --nocapture
```

The harness synthesizes deterministic JPEG input at runtime so the repository does not need to commit huge camera fixtures. Output lines are prefixed `PIXELCRAFT_G6_IMAGE`.

Final local automation was run with `G6_MAX_MP=48` and completed successfully, so the configured 12/24/48 MP host characterization tiers all completed on the measured Mac host. Numeric per-tier timings remain in the local `build/g6/final/` evidence logs and are not invented here when they were not pasted into the project record.

Device runner:

```bash
DEVICE=<flutter-device-id> G6_CYCLES=10 bash tool/g6_device_reliability.sh
```

The runner launches one consolidated `flutter drive` session using `integration_test/g6_device_verification_test.dart`. It first creates a temporary detached git worktree at the current `HEAD`, changes the iOS bundle id and Android application id only inside that worktree to `dev.cnxdev.pixelcraft.g6verify`, and runs the verifier from there. The checkout that may be open in Xcode is never edited, so the Runner scheme cannot retain the temporary verifier bundle id. The installed PixelCraft main app (`dev.cnxdev.pixelcraft`) is not the install/uninstall target. Flutter may install/remove the isolated G6 verifier app as part of the drive lifecycle; that is intentional and does not replace the main app. The temporary worktree is removed on normal exit or interruption.

Logs are stored under `build/g6/device/`.

### Results

| Host/device | Source | Result |
|---|---|---|
| Mac host / arm64 | ~12 MP synthetic JPEG characterization | PASS |
| Mac host / arm64 | ~24 MP synthetic JPEG characterization | PASS |
| Mac host / arm64 | ~48 MP synthetic JPEG characterization | PASS |
| iPhone 11 / iOS 26.6 | small sample / consolidated device smoke | PASS |

---

## G6.2 Long-session / soak

Two layers are required.

### Engine/product loop

Repeat a representative sequence:

```text
open source
-> reduced preview
-> Film preview
-> adjustment draft/commit
-> Apply
-> Undo
-> Redo
-> export
-> repeat
```

Suggested cycle levels:

```text
10   smoke
50   normal soak
100  extended soak
```

The individual soak workload remains available in:

```text
integration_test/g6_reliability_soak_test.dart
```

Physical-device G6 runs use the consolidated target:

```text
integration_test/g6_device_verification_test.dart
```

Run repeated physical-device cycles with:

```bash
DEVICE=<flutter-device-id> G6_CYCLES=10 bash tool/g6_device_reliability.sh
DEVICE=<flutter-device-id> G6_CYCLES=50 bash tool/g6_device_reliability.sh
DEVICE=<flutter-device-id> G6_CYCLES=100 bash tool/g6_device_reliability.sh
```

`G6_CYCLES` is executed inside one app process. Do not replace this with a shell loop of `flutter test -d ...`: that would reinstall/reset the test app each cycle and invalidate long-session memory/lifecycle evidence.

Watch for:

- monotonic RSS growth
- progressive latency increase
- renderer/native resource leaks
- stale temp/recovery files
- recipe/history corruption
- Film Profile corruption
- crashes or native exceptions

### Manual product loop

On physical devices also exercise:

```text
Camera -> Film switch -> clean capture -> Editor
-> G5 controls / Curve / HSL
-> Apply / Discard
-> Undo / Redo
-> transform
-> Film Profile create/edit/duplicate/load/import/export
-> export
-> exit/reopen
-> repeat
```

A no-crash run is not sufficient by itself; memory and responsiveness trends must be observed.

### Results

| Device | Cycles | Start RSS | End RSS | Peak RSS | Latency drift | Corruption/crash | Result |
|---|---:|---:|---:|---:|---|---|---|
| iPhone 11 / iOS 26.6 | 10 | ~300.8 MB | ~333.0 MB | ~348 MB observed | ~11.3 s -> ~13.3 s during warm-up | none | PASS |
| iPhone 11 / iOS 26.6 | 50 | ~302.9 MB | ~358.9 MB | ~362.7 MB observed | rises then settles near ~14.5 s/cycle | none | PASS with characterization |
| iPhone 11 / iOS 26.6 | 100 | ~303.0 MB | ~364.9 MB | ~364.9 MB observed | sustained-load steady state reaches ~16.6-16.8 s/cycle late in run | none | PASS with characterization |

### iPhone 11 soak characterization

- 10/50/100-cycle verifier runs all completed their required final cycle and emitted the `PIXELCRAFT_G6_COMPLETE` sentinel.
- JPEG/PNG/WebP export byte counts and recipe byte count remained stable across the observed runs.
- No crash, watchdog termination, recipe corruption, export corruption or VM-service session loss prevented completion.
- RSS shows a repeating sawtooth allocation/release pattern rather than monotonic per-cycle growth. The retained-memory envelope increases modestly during the long run and then appears bounded in the observed range; this is recorded as characterization, not proof that all leaks are impossible.
- Latency rises under sustained load and then approaches a later steady state. G6.4 physical thermal observation is used to characterize whether that sustained-load behavior has a user-visible impact.

---

## G6.3 Device matrix

Minimum useful diversity when hardware is available:

### iOS

```text
A13 reference
newer Apple Silicon tier
lower-memory supported tier
```

### Android

```text
Mali device
Adreno device
```

Record:

| Device | OS | SoC | GPU | RAM | Camera backend | Editor GPU backend | Build mode | Result |
|---|---|---|---|---:|---|---|---|---|
| iPhone 11 | iOS 26.6 | A13-class reference | Apple GPU | device-specific | AVFoundation | Metal / Rust fallback architecture | device verifier | automated smoke PASS; manual product checklist pending |

Required checks per device:

- Camera preview starts/stops repeatedly
- Film LUT preview remains valid
- capture remains clean
- Editor GPU renderer create/dispose/recreate
- Rust fallback remains available
- native engine smoke
- performance profile
- lifecycle background/foreground
- export and gallery/share product flow

The automated iPhone 11 verifier smoke completed successfully on the final local validation run. Broader product-flow observation and additional hardware diversity remain manual/availability-limited and are tracked in `docs/G6_DEVICE_MANUAL_CHECKLIST.md`.

---

## G6.4 Thermal / sustained workload

This section requires physical-device observation and is characterization, not a CI gate.

Suggested scenarios:

```text
Camera preview                         15-30 min
Camera + repeated Film switching       15 min
Editor interactive adjustments         15 min
Repeated heavy Gaussian Blur           10 min
Repeated full-resolution export        10+ exports
Camera -> Editor -> export loop         10+ cycles
```

A repeatable engine workload is available as:

```bash
DEVICE=<flutter-device-id> G6_DURATION_MIN=15 bash tool/g6_thermal_observe.sh
```

The thermal runner now keeps one isolated verifier process alive for the entire requested duration and repeats the workload inside that process. It does not repeatedly call `flutter test`, so the PixelCraft main app remains untouched and the thermal session is not reset by reinstall cycles. Physical heat/thermal-state observations still have to be entered here manually; the script must not invent them.

Observe:

- preview FPS degradation
- interaction latency drift
- export time drift
- device thermal state / user-visible heat
- throttling
- memory pressure / process termination
- battery impact
- continuous rendering while idle

Do not claim a numeric thermal result unless measured on the named device.

### Results

| Device | Scenario | Duration | Start metric | End metric | Thermal observation | Result |
|---|---|---:|---:|---:|---|---|
| iPhone 11 / iOS 26.6 | consolidated Rust engine profile loop | 15:03, 420 cycles | initial profile total ~1.8 s before sustained soak; sustained runner then ramps | late cycles ~2.16-2.19 s/profile, stable | user observation: not hot; no perceived lag | PASS with characterization |

### iPhone 11 thermal characterization

- The 15-minute physical-device session completed 420 cycles and emitted `PIXELCRAFT_G6_COMPLETE mode=thermal completed_cycles=420`.
- Late-run profile totals are tightly grouped around ~2.16-2.19 seconds per cycle, indicating an observed steady state rather than continued unbounded slowdown.
- Late-run RSS remains in a bounded repeating range with periodic release, consistent with the sawtooth behavior observed in G6.2.
- Manual physical observation after the sustained run: the iPhone 11 was **not hot** and showed **no perceived UI/device lag**.
- This does not claim access to an internal iOS thermal-state sensor value. It records measured workload behavior plus the explicit physical observation available from the test.

---

## G6.5 Failure injection

Host-automated failure injection lives in:

```text
test/state/g6_failure_injection_test.dart
```

It covers recovery/profile input corruption that can be exercised deterministically without a physical device.

Existing unit coverage remains responsible for native bridge fallback/generation behavior. Physical-device/manual G6.5 must additionally cover OS/native failures that cannot be truthfully synthesized in host CI.

Required cases:

| Failure | Expected behavior | Automation | Current status |
|---|---|---|---|
| corrupt newest recovery manifest | ignore it and load previous coherent generation | host test | PASS |
| latest recovery source fingerprint mismatch | ignore latest and load previous coherent generation | host test | PASS |
| invalid recipe bounds | reject persistence / restore path | host test | PASS |
| corrupt Film Profile JSON | explicit `FormatException`, no partial profile | host test | PASS |
| unsupported profile schema/version/engine | explicit rejection | host test | PASS |
| unsupported imported recipe field | explicit `unsupported` mapping, never silently dropped | host test | PASS |
| missing/corrupt LUT | GPU path unavailable/fails closed; Rust/product state remains valid | physical/native injection | manual/harness availability pending |
| native renderer init/runtime failure | fall back to valid Rust preview | existing bridge tests + physical injection | host coverage + physical observation pending |
| missing source | reject recovery/open without corrupting current valid state | physical/product injection | manual pending |
| export failure / unwritable destination | surface failure; recipe/session remains intact | physical/product injection | manual pending |
| gallery write failure / permission denied | surface failure; exported/session data remains valid | physical/product injection | manual pending |
| lifecycle interruption during processing | recover to coherent session or clean failure | physical lifecycle test | manual pending |

The final automated validation completed the deterministic G6.5 host suite successfully.

---

## G6 exit criteria

G6 may be closed only when:

1. G6.0 clean baseline is green on the final branch head.
2. G6.1 records at least the highest image tiers supported by available test hardware, with unsupported/unavailable tiers explicitly marked rather than invented.
3. G6.2 includes a repeatable soak and no unexplained monotonic resource growth or progressive slowdown.
4. G6.3 includes meaningful iOS and Android diversity when available; missing hardware is documented as a limitation.
5. G6.4 sustained-workload observations are recorded on physical hardware.
6. G6.5 deterministic failure injection is green and physical/native failure cases have product evidence.
7. No finding violates the architecture invariants or changes Rust authority to make a test pass.
8. Final CI on the latest G6 PR head is green.

## Automated closure status

The consolidated remaining validation completed successfully on commit `6c63e60d9e9776bc4f10fc7273b17d35c7c19a6f` with:

```text
[G6 FINAL] PASS device_smoke
[G6 FINAL] AUTOMATED REMAINING VALIDATION PASS
```

This validates the automated G6.0/G6.1/G6.5 host work plus the isolated iPhone 11 device smoke. GitHub CI run #136 also completed successfully on that code head.

## Current continuation point

Automated closure is complete. Remaining work is intentionally limited to `docs/G6_DEVICE_MANUAL_CHECKLIST.md`: real product-flow observation, permission/lifecycle/native-failure cases, and any additional device diversity that is actually available. Do not infer PASS for unavailable hardware or failure scenarios. After those observations are recorded, ensure CI is green on the latest documentation head and then G6 can be marked CLOSED.

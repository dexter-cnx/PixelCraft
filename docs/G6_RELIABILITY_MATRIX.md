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
| Commit | pending |
| Flutter | pending |
| Dart | pending |
| Rust | pending |
| Cargo | pending |
| Host OS | pending |
| Result | pending |
| Evidence path | `build/g6/baseline/` |

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

Device runner:

```bash
DEVICE=<flutter-device-id> G6_CYCLES=10 bash tool/g6_device_reliability.sh
```

The runner uses the committed native smoke/profile tests and stores logs under `build/g6/device/`.

### Results

| Device | OS | SoC/GPU | Source | Backend | Load/preview | Apply | Export | Peak RSS delta | Result |
|---|---|---|---|---|---:|---:|---:|---:|---|
| pending | | | small | | | | | | |
| pending | | | ~12 MP | | | | | | |
| pending | | | ~24 MP | | | | | | |
| pending | | | ~48 MP | | | | | | |

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

Automated native cycle:

```text
integration_test/g6_reliability_soak_test.dart
```

Run repeated physical-device cycles with:

```bash
DEVICE=<flutter-device-id> G6_CYCLES=10 bash tool/g6_device_reliability.sh
DEVICE=<flutter-device-id> G6_CYCLES=50 bash tool/g6_device_reliability.sh
DEVICE=<flutter-device-id> G6_CYCLES=100 bash tool/g6_device_reliability.sh
```

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
| pending | 10 | | | | | | |
| pending | 50 | | | | | | |
| pending | 100 | | | | | | |

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
| pending | | | | | | | release/profile | |

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

It repeatedly executes the existing native performance profile and records timestamped metrics. Physical heat/thermal-state observations still have to be entered here manually; the script must not invent them.

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
| pending | | | | | | |

---

## G6.5 Failure injection

Host-automated failure injection lives in:

```text
test/state/g6_failure_injection_test.dart
```

It covers recovery/profile input corruption that can be exercised deterministically without a physical device.

Existing unit coverage remains responsible for native bridge fallback/generation behavior. Physical-device/manual G6.5 must additionally cover OS/native failures that cannot be truthfully synthesized in host CI.

Required cases:

| Failure | Expected behavior | Automation |
|---|---|---|
| corrupt newest recovery manifest | ignore it and load previous coherent generation | host test |
| latest recovery source fingerprint mismatch | ignore latest and load previous coherent generation | host test |
| invalid recipe bounds | reject persistence / restore path | host test |
| corrupt Film Profile JSON | explicit `FormatException`, no partial profile | host test |
| unsupported profile schema/version/engine | explicit rejection | host test |
| unsupported imported recipe field | explicit `unsupported` mapping, never silently dropped | host test |
| missing/corrupt LUT | GPU path unavailable/fails closed; Rust/product state remains valid | physical/native injection |
| native renderer init/runtime failure | fall back to valid Rust preview | existing bridge tests + physical injection |
| missing source | reject recovery/open without corrupting current valid state | physical/product injection |
| export failure / unwritable destination | surface failure; recipe/session remains intact | physical/product injection |
| gallery write failure / permission denied | surface failure; exported/session data remains valid | physical/product injection |
| lifecycle interruption during processing | recover to coherent session or clean failure | physical lifecycle test |

Run deterministic host injection directly with:

```bash
flutter test test/state/g6_failure_injection_test.dart
```

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

## Current continuation point

The G6 automation/scaffolding is implemented. After host CI is green, run the device and thermal scripts on each available physical device, run the 12/24/48 MP characterization tiers appropriate for available memory, and append measured evidence to this document. Do not replace `pending` cells with estimates.
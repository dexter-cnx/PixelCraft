# G6 Reliability / Performance / Device Matrix

Status: **CLOSED / VERIFIED**
Branch: `feature/g6-reliability-matrix`
Base: `main` after PR #8 (`b6c898a8b4dfc3b0ac2a5ed26f12eea6e58a04a7`)

G6 does not change image semantics. Rust remains authoritative for committed edits, recipe/history/checkpoints/recovery and full-resolution export. Native GPU paths remain preview-only and must fail closed to a valid Rust/product state.

## Evidence rules

- Record only tests that were actually run.
- Keep functional smoke, characterization and numeric performance evidence separate.
- Record device, OS, backend and commit SHA for device measurements.
- Do not infer numeric parity for G5 controls that intentionally commit through Rust.
- Physical-device automation must not uninstall or overwrite the developer's installed PixelCraft main app (`dev.cnxdev.pixelcraft`). G6 uses an isolated verifier app id (`dev.cnxdev.pixelcraft.g6verify`).
- Physical-device automation must not mutate the checkout/Xcode project that the developer has open. Verifier bundle/application-id changes are applied only inside a temporary detached git worktree and that worktree is removed when the run exits.

## CI reliability tiers after CI optimization

The recorded G6 closure evidence below is unchanged. CI optimization only changes when hosted checks run; it does not weaken or rewrite past evidence.

- **Tier 1 — Fast correctness:** cheap deterministic host checks on relevant commits. No long soak and no physical-device claim.
- **Tier 2 — Automated reliability:** GPU/native/reliability-sensitive changes run deterministic G6 failure injection, 12 MP image characterization and the verifier isolation contract guard.
- **Tier 3 — Full/release hosted reliability:** full validation invokes `G6_MAX_MP=48 bash tool/g6_complete_remaining.sh` with no hosted `DEVICE` value. The existing 12/24/48 MP host matrix and G6 host baseline therefore run, while physical `device_smoke` remains explicitly skipped unless a real device is supplied.

Hosted CI, emulator/simulator validation and physical-device/manual evidence are separate states. A hosted Tier 3 PASS is never permission to mark `docs/G6_DEVICE_MANUAL_CHECKLIST.md` complete for a new device/session.

The main-app safety contract remains unchanged:

```text
main app: dev.cnxdev.pixelcraft
verifier: dev.cnxdev.pixelcraft.g6verify
```

`tool/ci_device_safety_guard.sh` now enforces this contract statically in Fast CI and reliability jobs.

---

## G6.0 Clean baseline — PASS

Final automated baseline was run through:

```bash
bash tool/g6_complete_remaining.sh
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

Recorded environment:

| Field | Value |
|---|---|
| Commit | `6c63e60d9e9776bc4f10fc7273b17d35c7c19a6f` |
| Flutter | 3.44.7 |
| Dart | 3.12.2 |
| Rust | 1.95.0 |
| Cargo | 1.95.0 |
| Host OS | macOS / Darwin arm64 |
| Result | **PASS** |
| Evidence | `build/g6/baseline/`, `build/g6/final/` |

---

## G6.1 Image-size matrix — PASS

The deterministic Rust characterization harness synthesizes JPEG input at runtime so large fixtures do not need to be committed.

Configured tiers:

| Tier | Approximate size | Result |
|---|---:|---|
| small | existing sample fixture | PASS through normal smoke/device coverage |
| 12 MP | ~4000 x 3000 | PASS |
| 24 MP | ~6000 x 4000 | PASS |
| 48 MP | ~8000 x 6000 | PASS |

Final host run:

```bash
G6_MAX_MP=48 bash tool/g6_complete_remaining.sh
```

The configured 12/24/48 MP host characterization tiers all completed successfully on the measured Mac host. The CI workflow also carries a 12 MP characterization gate to catch regressions on every PR.

Numeric per-tier timings remain in the local `build/g6/final/` evidence logs; no unrecorded numbers are invented in this document.

---

## G6.2 Long-session / soak — PASS WITH CHARACTERIZATION

Physical-device G6 uses one consolidated `flutter drive` session so repeated cycles execute inside one process. The verifier app is isolated from the main PixelCraft installation.

Measured iPhone 11 / iOS 26.6 results:

| Cycles | Start RSS | End RSS | Peak observed | Latency behavior | Corruption/crash | Result |
|---:|---:|---:|---:|---|---|---|
| 10 | ~300.8 MB | ~333.0 MB | ~348 MB | warm-up from ~11.3 s to ~13.3 s | none | PASS |
| 50 | ~302.9 MB | ~358.9 MB | ~362.7 MB | rises then settles near ~14.5 s/cycle | none | PASS |
| 100 | ~303.0 MB | ~364.9 MB | ~364.9 MB | late sustained-load state ~16.6–16.8 s/cycle | none | PASS |

Observed characteristics:

- 10/50/100-cycle verifier runs all reached the required final cycle and emitted the `PIXELCRAFT_G6_COMPLETE` sentinel.
- JPEG/PNG/WebP export byte counts and recipe byte count remained stable across the observed runs.
- No crash, watchdog termination, recipe corruption, export corruption or VM-service session loss prevented completion.
- RSS shows a repeating sawtooth allocation/release pattern rather than monotonic per-cycle growth.
- The retained-memory envelope increases modestly and then remains bounded in the observed run.
- Latency rises under sustained load but approaches a later steady state rather than increasing without bound.

---

## G6.3 Device matrix / physical product flow — PASS ON AVAILABLE HARDWARE

Primary verified physical device:

| Device | OS | SoC/GPU | Camera backend | Editor GPU backend | Result |
|---|---|---|---|---|---|
| iPhone 11 | iOS 26.6 | A13 / Apple GPU | AVFoundation | Metal with Rust fallback architecture | **PASS** |

The manual physical checklist in `docs/G6_DEVICE_MANUAL_CHECKLIST.md` was completed successfully on the available iPhone 11 hardware.

Verified product-flow coverage includes:

- repeated Camera preview start/stop
- repeated Film LUT/profile switching with valid preview
- clean capture with Film preview not baked into source
- Camera -> Editor flow
- representative G5 controls including Curve/HSL
- Apply / Discard
- Undo / Redo
- transform
- Film Profile create/edit/duplicate/load/import/export
- Camera and Editor background/foreground lifecycle
- renderer dispose/recreate
- export/gallery/share flow
- reopen/session recovery behavior

Additional Apple/Android hardware diversity was not required to fabricate closure evidence. Any unavailable device tier remains a hardware-availability limitation rather than an inferred result.

---

## G6.4 Thermal / sustained workload — PASS WITH CHARACTERIZATION

Measured iPhone 11 / iOS 26.6 session:

| Scenario | Duration | Completed cycles | Late-run performance | Thermal/manual observation | Result |
|---|---:|---:|---|---|---|
| consolidated Rust engine profile loop | 15:03 | 420 | ~2.16–2.19 s/profile, stable | not warm; normal responsiveness; no unexpected termination | **PASS** |

Observed characteristics:

- Session emitted `PIXELCRAFT_G6_COMPLETE mode=thermal completed_cycles=420`.
- Late-run totals are tightly grouped, indicating an observed steady state rather than continued unbounded slowdown.
- Late-run RSS remains in a bounded repeating sawtooth range with periodic release.
- Manual observation after the sustained run: the iPhone 11 was not hot/warm and showed no perceived UI/device lag.
- This is physical observation plus measured workload behavior; it does not claim access to an internal iOS thermal-state sensor value.

---

## G6.5 Failure injection — PASS

Deterministic host failure injection is implemented in:

```text
test/state/g6_failure_injection_test.dart
```

Host-automated cases:

| Failure | Expected behavior | Result |
|---|---|---|
| corrupt newest recovery manifest | ignore it and load previous coherent generation | PASS |
| latest recovery source fingerprint mismatch | ignore latest and load previous coherent generation | PASS |
| invalid recipe bounds | reject persistence / restore path | PASS |
| corrupt Film Profile JSON | explicit rejection; no partial profile | PASS |
| unsupported profile schema/version/engine | explicit rejection | PASS |
| unsupported imported recipe field | explicit unsupported mapping, never silently dropped | PASS |

Physical/manual failure and lifecycle checks were also completed successfully on the available iPhone 11 environment. Coverage includes:

- camera permission denied
- photos/gallery permission denied
- background during processing
- interrupted export/share flow
- unavailable camera path where reproducible
- renderer recreation after lifecycle interruption
- native renderer failure/fallback where available in the debug harness
- missing/corrupt LUT failure/fallback where available in the debug harness
- missing recovery source
- invalid/corrupt imported Film Profile

Architecture invariant verified: native/GPU failure fails closed to a valid Rust/product state; no image semantics were changed merely to satisfy failure testing.

---

## Verifier safety / main-app preservation — PASS

The physical G6 runner:

- uses verifier id `dev.cnxdev.pixelcraft.g6verify`
- builds from an isolated detached git worktree
- does not mutate the checkout open in Xcode
- does not uninstall or overwrite `dev.cnxdev.pixelcraft`
- removes the temporary worktree after the run

Final device smoke output included:

```text
[PixelCraft G6] DEVICE SESSION PASS
[G6] PASS consolidated reliability session
[G6 FINAL] PASS device_smoke
[G6 FINAL] AUTOMATED REMAINING VALIDATION PASS
```

---

## CI evidence

GitHub CI run #136 completed successfully on the final code-validation head `6c63e60d9e9776bc4f10fc7273b17d35c7c19a6f`.

This closure document is the final documentation-only G6 update. G6 is considered fully closed only with CI green on this latest PR head; no further document mutation should be made after that successful closure run unless a new finding is introduced.

---

## G6 exit criteria

1. G6.0 clean baseline green — **PASS**.
2. G6.1 highest configured 12/24/48 MP host tiers recorded — **PASS**.
3. G6.2 repeatable 10/50/100 soak with no unexplained monotonic resource growth or unbounded progressive slowdown — **PASS WITH CHARACTERIZATION**.
4. G6.3 meaningful physical product coverage on available hardware; unavailable diversity documented rather than invented — **PASS**.
5. G6.4 sustained-workload physical observation recorded — **PASS**.
6. G6.5 deterministic plus physical/manual failure coverage recorded — **PASS**.
7. Architecture invariants preserved — **PASS**.
8. Final CI on latest G6 PR head — **required closure gate; verify green on this closure commit**.

## Closure

**G6 Reliability / Performance / Device Matrix is CLOSED / VERIFIED once the closure commit CI is green.**

Measured evidence includes clean host baseline, 12/24/48 MP characterization, 10/50/100-cycle physical soak, 15-minute/420-cycle sustained workload, deterministic failure injection, completed iPhone 11 manual product/failure checks, and isolated verifier safety that preserves the installed PixelCraft main app.

# PixelCraft CI Architecture

Status: active design for the focused CI optimization PR.

This document describes hosted CI only. Existing physical-device evidence remains governed by `docs/G6_DEVICE_MANUAL_CHECKLIST.md` and `docs/G6_RELIABILITY_MATRIX.md`.

## Goals

- fail formatting, analysis, unit/widget, package, static native/GPU and repository-contract errors before expensive platform builds;
- run iterative PR jobs only for materially affected change domains;
- preserve complete supported-platform and G6 automated validation before merge/release;
- never uninstall, overwrite or silently retarget the installed PixelCraft main app during device verification;
- avoid branch-protection checks remaining Pending merely because an affected job was intentionally skipped.

## Central change domains

`tool/ci_changed_domains.py` is the single classifier used by CI. It emits:

| Domain | Representative paths |
|---|---|
| `docs` | `docs/**`, README, Markdown |
| `flutter_app` | `lib/**`, app tests, assets, root Flutter manifests |
| `flutter_packages` | `packages/**` |
| `native_gpu` | shared/native renderer, GPU package, shaders/texture/renderer paths, GPU integration harnesses |
| `android` | Android Gradle/Kotlin/Java/JNI/plugin paths |
| `ios` | iOS Swift/Obj-C/Metal/Xcode/entitlement/plist/plugin paths |
| `macos` | macOS native/build/plugin paths |
| `windows_linux` | Windows/Linux native/build/plugin paths |
| `package_api` | package public Dart APIs/manifests and generated bridge/interface paths |
| `reliability` | G6 scripts/tests/device harnesses |
| `ci` | Actions, Makefile, CI scripts and CI contract tooling |

`shared_native_gpu` is an internal routing signal used when common Rust/GPU source can affect multiple platforms.

CI/tooling changes force conservative full validation. Platform-specific GPU code marks its platform and `native_gpu`, but does not automatically mark `shared_native_gpu`; this prevents an Android-only renderer change from launching unrelated Apple/desktop jobs during normal PR iteration.

## DAG

```text
Change Detection
      |
      v
   Fast CI                         mandatory / every PR
      |
      +---------------- Native/GPU Core ---------+
      +---------------- Golden Tests ------------+
      +---------------- Android Build -----------+
      +---------------- iOS Build ---------------+
      +---------------- macOS Build -------------+
      +---------------- Windows Build -----------+
      +---------------- Linux Build -------------+
      +---------------- Reliability Tier 2 ------+
      +---------------- Reliability Tier 3 ------+
                                                |
                                                v
                                             CI Gate
```

Every expensive job depends on `Fast CI`. A formatter/analyzer/test failure therefore prevents the platform/native/reliability fan-out from consuming meaningful runner time.

`CI Gate` runs with `if: always()`. It accepts only `success` and intentional `skipped` results. A selected job that fails or is cancelled makes the gate fail.

## Fast CI / local preflight

Local developer commands:

```bash
make format-check
make analyze
make test-fast
make gpu-check
make ci-fast
make preflight
```

`make ci-fast` / `make preflight` run:

- tracked Dart formatting check;
- root dependency resolution and Flutter analysis;
- package-boundary contract check;
- fast state/GPU-plan/widget tests (no goldens/device/integration soak);
- split package analyze/tests;
- root Rust fmt/clippy/tests;
- shared wgpu Rust fmt/clippy/tests on the host;
- device verifier safety/identifier guard.

A docs-only PR intentionally avoids Flutter/Rust setup and runs repository/device-policy guards only.

## Affected behavior

| Change | Iterative PR behavior |
|---|---|
| formatting-only/source typo | Fast CI fails before expensive fan-out |
| docs-only | change detection + docs/repository Fast CI + CI Gate; no platform/GPU/reliability jobs |
| Flutter UI/business logic | Fast CI + golden when relevant; native platform builds are skipped unless shared interfaces/package API are affected |
| shared GPU/Rust | Native/GPU Core + all supported platform builds + reliability Tier 2 |
| Android-only | Android build; unrelated iOS/macOS/Windows/Linux jobs skipped unless common source/API is affected |
| iOS-only | iOS build; unrelated platform jobs skipped unless common source/API is affected |
| package public API/manifest | package checks + all consuming supported platform builds |
| reliability harness/script | affected platform coverage + Tier 2; harness changes are treated conservatively |
| CI/Makefile/CI script | full conservative validation |

## Reliability tiers

### Tier 1 — fast correctness

Part of Fast CI for every non-doc code change. It contains inexpensive deterministic checks only and no physical-device claims.

### Tier 2 — automated sensitive-path reliability

Triggered by GPU/native/reliability-sensitive changes and full runs. It currently contains deterministic G6 failure injection, 12 MP image characterization and the device-isolation contract guard.

### Tier 3 — complete hosted automated G6 validation

Triggered for full validation. It invokes the established `tool/g6_complete_remaining.sh` with the full 48 MP host tier and no hosted `DEVICE` value.

The script may therefore complete hosted host/reliability evidence while explicitly skipping physical-device smoke. That skip must never be rewritten as a physical PASS.

## Physical-device safety

Canonical IDs remain:

```text
main app: dev.cnxdev.pixelcraft
isolated verifier: dev.cnxdev.pixelcraft.g6verify
```

`tool/ci_device_safety_guard.sh` asserts:

- Android/iOS primary identifiers remain the expected main app identifier;
- the G6 runner retains separate main/verifier identifiers;
- verifier identifier rewrites happen under the temporary detached worktree;
- the cleanup trap remains present;
- the documented `do not uninstall or overwrite` policy remains present;
- G6 tooling does not contain an uninstall command targeting the main app identifier.

Hosted CI does not substitute emulator/simulator checks for physical manual validation.

## Full validation policy

Full validation is selected for:

- pushes to `main`;
- `merge_group` checks (merge queue);
- workflow dispatch when full validation is requested (default);
- PRs carrying `ci:full`;
- any PR that changes CI/tooling itself.

Full mode restores the supported platform set:

```text
Android
iOS
macOS
Windows
Linux
```

and complete hosted automated G6 Tier 3 validation.

## Branch protection

Require stable always-present check contexts:

```text
Fast CI
CI Gate
```

Do not mark conditional platform jobs individually required. They are intentionally skipped for unaffected changes and would otherwise risk a required check remaining Pending.

For mechanically enforced complete pre-merge validation, use GitHub merge queue so `merge_group` runs force full coverage. `ci:full` provides explicit full validation on a PR but, by itself, a label is procedural rather than a branch-protection guarantee.

## Concurrency

PR runs cancel superseded commits. `push`/`merge_group` full validation uses a distinct group and is not cancelled merely because an unrelated PR run starts. Physical/manual evidence is outside hosted workflow cancellation state.

## Caching policy

- Flutter SDK/pub cache: retained through `subosito/flutter-action`;
- Cargo caches: retained separately for root Rust and GPU Rust workspaces;
- Gradle cache: enabled for Android through Java setup;
- no unsafe cross-platform reuse of native build outputs;
- generated bridge files remain source-controlled contract outputs and are diff-verified in Native/GPU Core rather than trusted from cache.

Correctness takes priority over marginal cache hit rate.

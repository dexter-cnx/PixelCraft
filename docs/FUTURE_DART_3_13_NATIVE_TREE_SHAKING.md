# Future Dart 3.13 Native Tree-Shaking

## Status

**FUTURE / DEFERRED / DO NOT START NOW**

This document records a future optimization track for Dextryx Pixels. It must not interrupt the current Product / Editor UX work.

Do not change the Dart SDK constraint, Flutter baseline, Flutter Rust Bridge integration, native build pipeline, Rust ABI, or release packaging merely to start this track.

Activation requires an explicit project decision after the start conditions below are satisfied.

---

## Why this matters later

Dextryx Pixels has a meaningful native footprint. Rust-backed engine code and native/GPU packages are core to the product, while ordinary Dart tree shaking does not by itself prove that unused native symbols are absent from shipped binaries.

Dart 3.13 adds link hooks and recorded-usage native tree-shaking. The compiler can record which `@Native` members are referenced by the application and expose that information to a package link hook through `LinkInput.recordedUses`. The link hook can then ask the native linker to keep only the corresponding native symbols.

Official Dart hook documentation states that:

- build hooks can compile native assets, including Rust libraries;
- link hooks can filter, optimize, or tree-shake code assets before application bundling;
- recorded-usage tree shaking was introduced with Dart 3.13;
- when recorded usage is unavailable, the safe behavior is to preserve all symbols;
- when the retain set is empty, a generated native dynamic library can be omitted entirely when the build/link path supports it.

For Dextryx Pixels this creates a future path to:

- reduce unused native code in release artifacts;
- avoid paying the full binary cost of modular native capabilities that are not used by a particular build;
- keep future native feature growth from automatically translating into equivalent application-size growth;
- measure native footprint package-by-package instead of treating the complete Rust/native layer as one indivisible cost;
- make release-size optimization evidence-driven rather than based on assumptions.

This is a **binary-size and build-architecture optimization**. It is not required for current UX, committed image semantics, GPU preview behavior, or current release-readiness maintenance.

---

## Why we should not do it now

1. Current PixelCraft CI evidence is still on a Flutter/Dart baseline before Dart 3.13 recorded-usage support is available in the selected project toolchain.
2. The existing Rust/native integration is working and already has release-validation evidence.
3. `RecordUse` is only one part of the solution: build hooks, link hooks, native symbol mapping, linker configuration, LTO/dead stripping, and packaging all have to cooperate.
4. Native tree-shaking has value only when the final native linker can physically discard unused code.
5. The current product priority is modernizing and polishing UX, not migrating the native build architecture.
6. A before/after binary-size baseline is required; without one, the project cannot prove that the migration complexity is worthwhile.
7. `flutter_rust_bridge` must not be removed merely to make a RecordUse experiment easier. Any binding migration requires separate technical justification.
8. The current mobile `dxtr_pixs_gpu` path uses platform plugin/MethodChannel/PlatformView integration, while the desktop-oriented native surface is not automatically equivalent to the mobile engine path. A desktop experiment must not become a false gate for mobile feasibility.

Therefore this work remains future-only until explicitly activated.

---

## Current project fit

Relevant native surfaces need to be classified separately.

### `dxtr_pixs_gpu`

The mobile runtime is primarily platform-plugin based. The desktop-oriented `pixelcraft_gpu_native` / wgpu surface may be useful for an isolated mechanics experiment if a small `@Native`-observable binding surface can be introduced safely.

A desktop GPU PoC can demonstrate hook mechanics and native size behavior, but it must **not** decide whether `dxtr_pixs_engine` should be evaluated on Android/iOS.

### `dxtr_pixs_engine`

The engine contributes to mobile release artifacts through the Flutter Rust Bridge / Rust native path and is the more important eventual mobile-size candidate.

It must only be evaluated after toolchain confirmation and native-size baselining. The project must preserve Rust ownership of committed edit semantics, history/checkpoint/recovery, and full-resolution export.

---

## Start conditions

Do not begin implementation until all of these are true:

1. The currently prioritized Product / Editor UX work is stable enough that native build optimization is no longer competing with active UX delivery.
2. The selected stable Flutter SDK ships a Dart 3.13-or-newer SDK with the required link-hook / recorded-usage APIs.
3. Required `hooks`, `code_assets`, and `record_use` support is verified in the actual Flutter toolchain used by CI.
4. Android/iOS release-size baselines have been captured before migration; desktop baselines are added where useful.
5. CI can reproduce the intended build/link path without weakening the current release baseline.
6. The team explicitly decides that native binary-size optimization is worth prioritizing.
7. The first PoC can be isolated from authoritative image semantics and final-render behavior.

If any condition is false, keep this track deferred.

---

## Proposed plan

### FNT-0 — Toolchain gate

- identify the exact stable Flutter version that carries the required Dart 3.13 APIs;
- verify `hooks`, `code_assets`, and `record_use` behavior in Flutter builds, not just standalone Dart;
- verify intended platform coverage;
- document any Flutter-specific limitations before changing SDK constraints.

**Exit:** supported toolchain is confirmed and documented.

### FNT-1 — Native size baseline

Capture reproducible pre-migration release sizes for:

- Android APK/AAB;
- iOS release/no-codesign/archive/framework evidence as applicable;
- macOS, Windows, and Linux artifacts where relevant.

Where practical, record native-library/framework contribution separately from Dart/Flutter assets.

**Exit:** before-migration baseline exists.

### FNT-2 — Binding/API audit

For each native surface:

- enumerate exported native ABI symbols;
- identify which symbols are reachable from Dart;
- classify bindings as `@Native`-observable, convertible with minimal justified change, or not suitable for RecordUse;
- identify generated vs manually maintained mappings;
- inspect Rust release settings, export visibility, LTO, section GC, and dead-code behavior.

**Exit:** symbol map and feasibility classification are understood.

### FNT-3 — Optional desktop GPU mechanics PoC

Use `dxtr_pixs_gpu` / `pixelcraft_gpu_native` only if it offers a safe, small experimental surface.

- introduce the minimum `@Native`-observable binding needed for the experiment;
- add build/link hook integration where appropriate;
- map recorded Dart use to exact native symbols;
- verify safe preserve-all behavior when recorded usage is unavailable;
- verify empty-use behavior only when technically valid.

This PoC measures mechanics and desktop/native footprint only.

**Exit:** hook mechanics are proven or rejected without affecting mobile engine decisions.

### FNT-4 — Mobile engine feasibility PoC

Evaluate `dxtr_pixs_engine` independently for Android/iOS.

- measure the engine's real contribution to mobile artifacts;
- determine whether the current FRB-generated/runtime binding path can expose useful recorded usage;
- if not, prototype only the minimum justified observable boundary;
- do not remove Flutter Rust Bridge merely to enable the experiment;
- do not change committed image semantics.

**Exit:** mobile feasibility is demonstrated or explicitly rejected.

### FNT-5 — Linker/LTO verification

Prove that native code is physically removed from final artifacts.

Check where practical:

- native library/framework size;
- exported/retained symbols;
- linker map or equivalent evidence;
- LTO/dead-strip/section-GC behavior;
- unused-symbol removal;
- whole-library omission when no symbols are used and the platform/build path supports it.

**Exit:** native dead-code elimination is demonstrated with artifact evidence.

### FNT-6 — Before/after evaluation

Compare:

- shipped binary size;
- native library/framework size;
- build duration;
- startup/load behavior;
- runtime correctness;
- CI reproducibility;
- maintenance burden.

The project should prefer measurable product value over architectural novelty.

**Exit:** written recommendation backed by measurements.

### FNT-7 — Decision gate

Choose one:

- **ADOPT** — material benefit, acceptable complexity;
- **LIMITED ADOPTION** — useful only for selected native packages;
- **DEFER** — benefit exists but does not yet justify migration cost;
- **REJECT** — approach conflicts with reliability, tooling, or maintenance requirements.

No broader migration happens before this decision.

---

## Acceptance criteria

The future track is successful only if all applicable criteria are met:

1. Unused native symbols are demonstrably absent from final release artifacts.
2. Zero-use native assets can be omitted where the supported build/link pipeline allows it.
3. Release artifact size improves enough to justify new build-system complexity.
4. Rust remains authoritative for committed image semantics, history, recovery, and export.
5. GPU preview remains non-authoritative and fail-closed.
6. Export remains deterministic and equivalent.
7. Android/iOS native packaging checks continue to pass.
8. No runtime-required symbol is removed.
9. CI can reproduce the link process on each adopted platform.
10. Rollback to the current integration remains straightforward.
11. `flutter_rust_bridge` is retained unless a separate technical case justifies migration.
12. Desktop GPU experiments do not block or substitute for mobile engine evaluation.

---

## Stop / rollback conditions

Return this track to deferred status if:

- binary savings are negligible;
- platform support is inconsistent;
- Flutter hook tooling is unstable for required targets;
- build reproducibility gets worse;
- CI becomes fragile;
- symbol mapping becomes too expensive to maintain;
- runtime behavior diverges from the validated Rust/native path;
- the optimization pressures the project to weaken architecture invariants.

---

## Official references

- Dart hooks: https://dart.dev/tools/hooks
- Dart 3.13 announcement — native-library tree shaking with `RecordUse` / `package:record_use`: https://dart.dev/blog/announcing-dart-3-13#tree-shaking-native-libraries-with-recorduse-and-package-record_use

Re-verify the official documentation when this work is actually activated, because hook/toolchain details can evolve.

---

## Current instruction

**Do not implement this now.**

Keep this document as the rationale and implementation plan for a future native-size optimization milestone. Continue from `docs/PROJECT_HANDOFF.md` until an explicit project decision activates this track.

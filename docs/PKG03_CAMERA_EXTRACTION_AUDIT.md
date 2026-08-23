# PKG-03 Camera Package Extraction Audit

Status: **AUDITED / DEFERRED**

Date: 2026-08-22

Base: `main` after PF3 merge (`a203cc6202c1a202526294def5b8fe209ca416cd`)

## Decision

Do **not** extract `lib/camera` into a standalone Flutter package during PF4.

The PF3 contracts are stable enough to review, but the current camera boundary is still product-specific rather than a reusable package boundary. Extraction now would mostly move files while introducing adapter interfaces for dependencies that have only one consumer.

## Evidence

`CameraCapturePipeline` currently depends on:

- app-level `MediaSaveService`;
- app-level `ProcessingJobPhase`;
- the PixelCraft Rust bridge / generated Rust API;
- camera-specific look, crop/orientation and zoom semantics.

The wider `lib/camera` area also contains product UI/state, native GPU preview coordination, recent-thumbnail behavior, composition guides, Film/Filter handoffs, and capture/save orchestration.

These concerns are coherent inside PixelCraft today but do not yet form one independently reusable API surface.

## Why defer

A package extraction is justified only when at least one of these becomes true:

1. another app/package needs the camera runtime as a real consumer;
2. a stable camera-domain API can be expressed without importing PixelCraft app services or generated Rust bindings;
3. native camera/GPU runtime ownership can be separated cleanly from product UI and Gallery/editor orchestration;
4. the extraction reduces dependency complexity rather than adding forwarding interfaces.

None of those conditions is required for PF4.

## PF4 rule

PF4 may introduce source/editor contracts at the app boundary, but it must not reshape camera code merely to make a future package extraction look cleaner.

Keep these ownership rules:

- camera preview/capture remains a PixelCraft product concern;
- Rust remains authoritative for final image semantics/rendering;
- Gallery/editor sources never inherit transient `CameraLook` implicitly;
- long-lived DAM/catalog ownership remains in Nixin;
- future external edit integration uses an explicit versioned request/result contract.

## Revisit trigger

Revisit PKG-03 after PF4/PF5 only if a concrete reusable camera consumer or stable cross-product camera API exists.

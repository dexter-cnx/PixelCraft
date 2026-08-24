# PF5 External Edit Request/Result Contract

Status: PF5 foundation merged in PR #56.

## Purpose

PF5 defines a transport-neutral, versioned boundary for external editors such as Nixin / Dextryx Images to hand an asset into PixelCraft and receive an edit result without transferring catalog authority to PixelCraft.

This milestone defines the contract only. It does not add app-to-app transport, deep links, RAW decoding, MobileSAM, catalog mutation, or a generic plugin runtime.

## Ownership boundary

- Nixin / caller owns long-lived catalog identity and passes `catalogAssetId`.
- PixelCraft must preserve and correlate that identifier; it must not invent or replace catalog identity.
- PixelCraft / Rust remains authoritative for image-edit semantics, recipe/history, and rendered pixels.
- The source supplied by the caller is read-only from the contract perspective.
- Output is a distinct result URI and never implies source mutation.

## Contract version

Current schema version:

```text
1
```

Unsupported schema versions fail closed with `FormatException`.

Implementation:

```text
lib/app/external_edit_contract.dart
```

Regression coverage:

```text
test/app/external_edit_contract_test.dart
```

## Request V1

`ExternalEditRequestV1` carries:

```text
schemaVersion
requestId
catalogAssetId
source
preferredOutputMimeType?  // preference only; not a capability claim
```

The source reuses `MediaSourceDescriptor` and preserves:

```text
uri
provenance
mimeType?
externalId?
```

For an external edit request, `source.provenance` must be `externalEdit`; any other provenance is rejected during decode, and outbound construction also enforces this provenance in release builds.

## Result V1

`ExternalEditResultV1` correlates back with both:

```text
requestId
catalogAssetId
```

Supported statuses:

```text
completed
cancelled
failed
```

### completed

Requires `ExternalEditOutputV1`:

```text
uri
mimeType
suggestedFileName?
authoritativeRecipeJson?
```

`authoritativeRecipeJson` is an opaque PixelCraft/Rust-authored payload for future re-edit continuity. External callers may persist it but must not become edit authority by interpreting or mutating its internal schema.

### cancelled

Carries correlation only and does not invent an output.

### failed

Requires a stable `failureCode`; `failureMessage` is optional presentation/debug context. Outbound failed-result construction rejects an empty or whitespace-only failure code in release builds.

## Validation policy

The decoder fails closed for:

- unsupported schema versions;
- empty required identifiers;
- malformed or scheme-less URIs;
- unsupported source provenance;
- non-`externalEdit` request sources;
- unknown result status;
- missing completed output;
- failed results without a failure code.

Outbound construction additionally release-safely enforces the PF5 review fixes for:

- request source provenance being `externalEdit`;
- completed-output MIME being non-empty after trimming;
- failed-result `failureCode` being non-empty after trimming.

These outbound checks are not a blanket guarantee that every decoder invariant has already been validated on every locally constructed object. Future transport code must still treat contract decoding/validation as authoritative at the boundary.

## Deferred work

PF5 foundation intentionally does not activate:

```text
real RAW decode/demosaic
MobileSAM / ONNX
feature-plugin runtime
Nixin transport/deep-link protocol
catalog write-back implementation
Dart 3.13 RecordUse/native tree-shaking
```

Any later transport layer must adapt to this contract rather than redefine ownership semantics.

## Validation evidence

Final PF5 exact head:

```text
69e317b4cb153f09c3a926d6aab6964ca9fd410d
```

Pixel Craft CI #781 passed on that exact head:

```text
Change Detection  PASS
Fast CI           PASS
Golden Tests      PASS
CI Gate           PASS
```

Codex review P2 findings were fixed, replied to, and resolved before merge:

1. enforce external-edit provenance on outbound request construction;
2. reject empty/whitespace output MIME on outbound completed output construction;
3. reject empty/whitespace failure code on outbound failed-result construction.

PF5 merged in PR #56 with merge commit:

```text
8df08f090c6d2e001526004ef15c9ae652b6a471
```

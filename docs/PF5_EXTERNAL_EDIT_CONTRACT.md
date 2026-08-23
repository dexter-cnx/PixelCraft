# PF5 External Edit Request/Result Contract

Status: PF5 foundation active in PR #56.

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

For an external edit request, `source.provenance` must be `externalEdit`; any other provenance is rejected.

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

Requires a stable `failureCode`; `failureMessage` is optional presentation/debug context.

## Validation policy

The contract fails closed for:

- unsupported schema versions;
- empty required identifiers;
- malformed or scheme-less URIs;
- unsupported source provenance;
- non-`externalEdit` request sources;
- unknown result status;
- missing completed output;
- failed results without a failure code.

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

Implementation head `732787b83a32d5b51ee56386791b2ff4c3e3ed47` passed Pixel Craft CI #777 before this documentation commit:

```text
Change Detection  PASS
Fast CI          PASS
Golden Tests     PASS
CI Gate          PASS
```

Because this document adds a new commit, merge readiness must use exact-head CI from the final PR head rather than reusing CI #777 as final exact-head evidence.

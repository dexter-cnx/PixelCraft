# PF8 — Capture Failure Cleanup

Status: **MERGED**

- PR: #61
- final exact head: `26ed81eb69178ff038ebc200e297472d144ee48a`
- merge commit: `4429291c5f3c4820fe22f690199b75327303cbcd`
- exact-head Pixel Craft CI: **#819 PASS**
- review threads: none open at merge

## Problem

PF7 intentionally preserves the authoritative clean captured JPEG when processing or Gallery delivery fails so Retry can run the same transaction again.

Before PF8, if the user abandoned that failed handoff with Back instead of retrying, the temporary clean capture had no cleanup path and could remain on disk.

## Final behavior

```text
capture processing fails
  ↓
phase = failed
  ↓
keep clean captured JPEG available
  ├── Retry -> reuse the same clean source
  └── Back / abandon -> route pops -> best-effort cleanupSource(imagePath)
```

Processing and saving phases remain non-dismissible. Success cleanup remains unchanged.

## Implementation

Important file:

```text
lib/camera/camera_capture_save_handoff.dart
```

`PopScope.onPopInvokedWithResult` observes an actual successful pop. If the handoff is in `failed`, it invokes the existing `CameraCaptureHandoffTransaction.cleanupSource` boundary.

The transaction boundary remains responsible for file cleanup. The widget does not perform direct filesystem deletion.

## Invariants

1. Retry never loses the authoritative clean source before the retry starts.
2. Active `processing` and `saving` phases remain protected from Back navigation.
3. A failed handoff may be abandoned by the user.
4. Once a failed handoff is actually popped, temporary-source cleanup is attempted best-effort.
5. Success behavior and Gallery delivery semantics are unchanged.
6. The preview framebuffer is never promoted to source authority.
7. PF8 does not change Metal/OpenGL ES architecture, Rust render authority, RAW, MobileSAM, external-edit transport, or plugin runtime policy.

## Regression coverage

`test/ui/camera/camera_capture_frozen_still_test.dart` covers the failed -> Back -> cleanup lifecycle in addition to the PF7 frozen-still success path.

The regression verifies that cleanup does not happen merely because processing failed; it happens only when the failed route is actually abandoned.

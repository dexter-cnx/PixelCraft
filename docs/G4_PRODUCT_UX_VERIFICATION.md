# G4 Product Editor UX Verification

## Status

G4 is **IN PROGRESS**.

Branch: `feature/editor-product-ux`

G3 prerequisite:

- PR #6 `G3: production rendering pipeline` merged into `main` on 2026-08-11.
- Merge commit: `86b9ca78c54326785133f66225dbf5bfd9108a17`.
- G4 branch was created from updated `main` after the merge.

## Architectural invariants

G4 must preserve the verified G3 contracts:

1. Rust remains authoritative for semantic edit state, history, checkpoints, recipe and full-resolution export.
2. GPU/compositor state remains preview-only.
3. Tool switching is neither Apply nor Cancel.
4. Existing draft values remain remembered while the draft is active.
5. Unsupported or failed GPU composition must fall back to the valid Rust preview.
6. Product UX must not expose behavior that the Rust session model cannot guarantee.

## G4.0 — Clean branch / product baseline

### Repository transition

- [x] G3 PR #6 merged into `main`.
- [x] `feature/editor-product-ux` created from `main`.
- [ ] Flutter analyze baseline recorded.
- [ ] Flutter test baseline recorded.
- [ ] Golden baseline recorded.
- [ ] Rust fmt/clippy/test baseline recorded.
- [ ] GPU LUT verification baseline recorded.
- [ ] G3 physical/runtime smoke confirmed unchanged on the G4 branch.

The unchecked gates require execution in the project checkout / CI environment. Do not treat them as PASS until evidence is recorded below.

### Baseline evidence

```text
flutter analyze      NOT RECORDED
make test            NOT RECORDED
make golden-test     NOT RECORDED
make rust-fmt        NOT RECORDED
make rust-clippy     NOT RECORDED
make rust-test       NOT RECORDED
make gpu-lut-verify  NOT RECORDED
G3 runtime smoke     NOT RECORDED
```

## G4.1 — Tool-state UX

Target behavior:

- changed/active indicator on each Adjust control
- Reset current parameter
- Reset section/tool
- optional Reset All Draft only if it preserves Rust session semantics cleanly
- correct neutral/default markers
- remembered values preserved across tool switching
- active draft clearly distinguished from the applied checkpoint

### Implementation notes

The existing controller already keeps per-control remembered values and rehydrates active draft controls from the authoritative Rust session recipe. G4.1 must build on that mechanism rather than introduce a second semantic edit model in Flutter.

Reset behavior must be implemented through an authoritative Rust/session operation. Setting a slider to its neutral value is **not** automatically equivalent to removing an earlier operation from the active recipe, so UI-only neutralization must not be presented as a deterministic reset.

### Acceptance evidence

- [ ] Adjust chips show which parameters differ from their neutral/default values.
- [ ] Selected Adjust parameter shows its neutral/default marker.
- [ ] Reset current parameter deterministically updates the authoritative Rust recipe.
- [ ] Reset Adjust section deterministically updates the authoritative Rust recipe.
- [ ] Tool switching retains active draft values without Apply/Cancel.
- [ ] Apply establishes a new checkpoint and clears draft indicators.
- [ ] Cancel restores the checkpoint and clears draft indicators.
- [ ] Widget/state tests cover changed indicators and reset behavior.
- [ ] Existing G3 GPU planning/session tests remain green.

## Evidence log

### 2026-08-11 — G4 branch opened

- Verified PR #6 is merged.
- Created `feature/editor-product-ux` from `main`.
- Created this verification record before G4 product behavior changes.
- Baseline execution evidence remains intentionally unrecorded until the project test environment runs the gates.

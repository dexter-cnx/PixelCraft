# Local development workflow

PixelCraft keeps formatting failures local by using a repository-managed Git `pre-push` hook. Hosted CI still runs the same read-only formatting checks as an independent safety net because hooks can be bypassed with `git push --no-verify`.

## One-time hook setup

From the repository root on macOS, Linux, WSL, or Git Bash:

```bash
make hooks-install
```

Equivalent direct command:

```bash
bash tool/install_git_hooks.sh
```

On Windows PowerShell, when working directly from Windows rather than Git Bash/WSL:

```powershell
powershell -ExecutionPolicy Bypass -File tool/install_git_hooks.ps1
```

The installer is idempotent. It configures this clone with:

```text
git config --local core.hooksPath .githooks
```

After installation, normal `git push` automatically invokes `.githooks/pre-push`.

## Pre-push behavior

The guard is intentionally cheap. It does not run platform builds, release packaging, benchmarks, or the full reliability matrix.

```text
git push
   ↓
pre-push
   ↓
require clean working tree + required tools
   ↓
make format
   ├─ Dart: canonical changed-file formatter used by CI
   └─ Rust: root engine + dxtr_pixs_gpu Rust crate
   ↓
working tree changed?
   ├─ yes → STOP push → show changed files → review/commit first
   └─ no  → allow push
```

The hook never runs `git add`, never commits, never discards changes, and never continues a push after the formatter changes files.

If formatting changes a tracked file, the expected flow is:

```bash
git diff
# review the formatter-only changes
git add <files>
git commit

git push
```

The next push should pass the formatting guard when the working tree is clean and the committed code is canonical.

## Formatting commands

```bash
make format        # modifies changed Dart files and all repository Rust crates
make format-check  # read-only CI-safe check; exits non-zero on formatting drift
make pre-push      # run the same local guard manually
```

Dart file selection is centralized in `tool/ci_format_changed.sh`. `make format` uses its write mode and `make format-check` uses its read-only check mode, so local formatting and CI do not maintain separate Dart file lists.

Rust formatter manifests are centralized in the Makefile through `RUST_FORMAT_MANIFESTS` and cover both:

```text
rust/Cargo.toml
packages/dxtr_pixs_gpu/rust/Cargo.toml
```

## Tooling failures

The guard fails before formatting if Git, Make, Dart, Cargo, or `rustfmt` is unavailable. Activate the repository Flutter/Dart toolchain and Rust toolchain before retrying. A missing Rust formatter can normally be installed with:

```bash
rustup component add rustfmt
```

## CI remains authoritative

The local hook is an iteration-speed guard, not a replacement for hosted verification:

```text
local make format / pre-push
            ↓
         git push
            ↓
        Fast CI
            ↓
    make format-check
```

`git push --no-verify` can bypass local hooks, so CI formatting validation must remain enabled.

For the broader non-platform local validation suite, continue to use:

```bash
make preflight
```

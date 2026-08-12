# pixelcraft_engine

Flutter FFI build plugin for PixelCraft's Rust image engine.

This package contains the CargoKit/platform glue used to compile and bundle the repository-level `rust/` crate. Rust remains the authoritative owner of committed image semantics, recipes, history, checkpoints, recovery, and full-resolution export.

The package is internal to the PixelCraft monorepo (`publish_to: none`). Regenerating FRB integration may create a temporary root-level `rust_builder/`; run `python3 tool/normalize_rust_builder_layout.py` (or `make integrate`) to relocate and normalize it back into this package.

#!/usr/bin/env python3
"""Normalize FRB/CargoKit glue into PixelCraft's package layout.

flutter_rust_bridge 2.12 generates its Cargokit glue as `rust_builder/`.
PixelCraft keeps that FFI plugin at `packages/pixelcraft_engine/`, so after an
FRB integrate/repair pass we relocate the generated directory and adjust only
paths whose depth changed. Image semantics and the authoritative Rust crate
remain in the repository-level `rust/` directory.
"""
from __future__ import annotations

from pathlib import Path
import shutil
import sys

GENERATED_DIR = Path("rust_builder")
PACKAGE_DIR = Path("packages/pixelcraft_engine")


def replace_once(path: Path, old: str, new: str) -> None:
    if not path.is_file():
        print(f"ERROR: expected file is missing: {path}", file=sys.stderr)
        raise SystemExit(1)
    text = path.read_text(encoding="utf-8")
    if new in text:
        return
    if old not in text:
        print(f"ERROR: expected text not found in {path}: {old!r}", file=sys.stderr)
        raise SystemExit(1)
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def relocate_generated_builder() -> None:
    if not GENERATED_DIR.exists():
        return
    PACKAGE_DIR.parent.mkdir(parents=True, exist_ok=True)
    if PACKAGE_DIR.exists():
        shutil.rmtree(PACKAGE_DIR)
    GENERATED_DIR.rename(PACKAGE_DIR)
    print(f"[PixelCraft] Relocated FRB Cargokit glue to {PACKAGE_DIR}")


def normalize_paths() -> None:
    replace_once(
        Path("pubspec.yaml"),
        "path: rust_builder",
        "path: packages/pixelcraft_engine",
    )
    replace_once(
        PACKAGE_DIR / "android/build.gradle",
        'manifestDir = "../../rust"',
        'manifestDir = "../../../rust"',
    )
    for platform in ("ios", "macos"):
        replace_once(
            PACKAGE_DIR / platform / "pixelcraft_engine.podspec",
            "../../rust pixelcraft_engine",
            "../../../rust pixelcraft_engine",
        )
    replace_once(
        PACKAGE_DIR / "linux/CMakeLists.txt",
        "../../rust pixelcraft_engine",
        "../../../rust pixelcraft_engine",
    )
    replace_once(
        PACKAGE_DIR / "windows/CMakeLists.txt",
        "../../../../../../rust pixelcraft_engine",
        "../../../../../../../rust pixelcraft_engine",
    )


def main() -> None:
    relocate_generated_builder()
    if not PACKAGE_DIR.is_dir():
        print(f"ERROR: Rust builder package is missing: {PACKAGE_DIR}", file=sys.stderr)
        raise SystemExit(1)
    normalize_paths()
    print("[PixelCraft] Rust builder package layout normalized")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Generate deterministic GPU atlases from Rust-generated Creative Filter LUTs.

The authoritative creative look is produced by rust/src/bin/generate_creative_luts.rs,
which executes Pixel Craft's photon-rs filter path at full strength. This script
only converts those canonical 33^3 .cube samples to the same RGBA8 atlas layout
used by Film preview.

Creative assets are emitted beside Film assets with a `creative_` prefix so the
existing native 33^3 LUT loader/sampler can be reused without a second shader or
loader implementation.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from generate_gpu_lut_atlas import (
    ATLAS_SIZE,
    DEFAULT_PARITY_FIXTURES,
    LUT_SIZE,
    TILES_PER_ROW,
    build_rgba8_atlas,
    load_parity_fixtures,
    parse_cube,
    verify_parity,
)

CREATIVE_FILTER_IDS = (
    "vintage",
    "oceanic",
    "lofi",
    "dramatic",
    "golden",
    "pastel_pink",
)


def process(
    creative_root: Path,
    output_root: Path,
    fixture_path: Path,
    *,
    write: bool,
) -> None:
    fixture_points = load_parity_fixtures(fixture_path)
    manifest_profiles: list[dict[str, object]] = []

    for filter_id in CREATIVE_FILTER_IDS:
        cube_path = creative_root / filter_id / "lut.cube"
        if not cube_path.is_file():
            raise FileNotFoundError(
                f"Missing {cube_path}. Run `make creative-luts` first."
            )
        cube = parse_cube(cube_path)
        atlas = build_rgba8_atlas(cube)
        asset_id = f"creative_{filter_id}"
        max_error = verify_parity(asset_id, cube, atlas, fixture_points)
        print(
            f"[Pixel Craft] creative {filter_id}: "
            f"atlas parity max error {max_error:.6f}"
        )
        if write:
            output_root.mkdir(parents=True, exist_ok=True)
            file_name = f"{asset_id}.rgba8"
            (output_root / file_name).write_bytes(atlas)
            manifest_profiles.append(
                {
                    "id": filter_id,
                    "assetId": asset_id,
                    "file": file_name,
                    "sha256": hashlib.sha256(atlas).hexdigest(),
                }
            )

    if write:
        manifest = {
            "version": 1,
            "kind": "creative",
            "source": "rust/photon-rs-0.3.3",
            "format": "rgba8",
            "lutSize": LUT_SIZE,
            "tilesPerRow": TILES_PER_ROW,
            "atlasWidth": ATLAS_SIZE,
            "atlasHeight": ATLAS_SIZE,
            "sliceCount": LUT_SIZE,
            "interpolation": "trilinear",
            "intensity": "post-lut-linear-blend",
            "profiles": manifest_profiles,
        }
        (output_root / "creative_manifest.json").write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--creative-root",
        type=Path,
        default=Path("rust/creative_luts"),
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("build/gpu_luts"),
    )
    parser.add_argument(
        "--fixtures",
        type=Path,
        default=DEFAULT_PARITY_FIXTURES,
    )
    parser.add_argument("--verify-only", action="store_true")
    return parser


def main() -> None:
    args = build_parser().parse_args()
    process(
        args.creative_root,
        args.output,
        args.fixtures,
        write=not args.verify_only,
    )
    if args.verify_only:
        print("[Pixel Craft] Creative GPU LUT atlas parity verification passed")
    else:
        print(f"[Pixel Craft] Creative GPU LUT atlases written to {args.output}")


if __name__ == "__main__":
    main()

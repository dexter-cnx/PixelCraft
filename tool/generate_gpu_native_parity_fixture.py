#!/usr/bin/env python3
"""Generate canonical Film LUT fixture expectations for native GPU tests."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from generate_gpu_lut_atlas import PROFILE_IDS, parse_cube


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--film-root",
        type=Path,
        default=Path("rust/film_profiles"),
    )
    parser.add_argument(
        "--fixtures",
        type=Path,
        default=Path("tool/gpu_lut_parity_fixtures.json"),
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("build/gpu_luts/native_parity.json"),
    )
    args = parser.parse_args()

    fixture_data = json.loads(args.fixtures.read_text(encoding="utf-8"))
    rgb_values = fixture_data.get("rgb")
    if not isinstance(rgb_values, list) or not rgb_values:
        raise ValueError("Parity fixture must contain a non-empty rgb array")

    inputs: list[list[float]] = []
    for index, value in enumerate(rgb_values):
        if not isinstance(value, list) or len(value) != 3:
            raise ValueError(f"Fixture rgb[{index}] must contain three channels")
        inputs.append([float(channel) for channel in value])

    profiles: dict[str, list[list[float]]] = {}
    for profile_id in PROFILE_IDS:
        cube_path = args.film_root / profile_id / "lut.cube"
        cube = parse_cube(cube_path)
        profiles[profile_id] = [
            list(cube.sample((rgb[0], rgb[1], rgb[2]))) for rgb in inputs
        ]

    output = {
        "version": 1,
        "lutSize": 33,
        "tolerance": 2.0 / 255.0,
        "inputs": inputs,
        "profiles": profiles,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(output, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"[Pixel Craft] Native GPU parity fixture written to {args.output}")


if __name__ == "__main__":
    main()

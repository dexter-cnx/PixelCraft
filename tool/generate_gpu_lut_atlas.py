#!/usr/bin/env python3
"""Generate and verify Pixel Craft GPU LUT atlases from materialized .cube LUTs.

The Film Profile authoring source remains rust/film_profiles/*/look.json. Run
`make film-luts` first so Rust build.rs materializes the canonical 33^3 cubes,
then this tool converts those exact samples into an RGBA8 2D atlas suitable for
OpenGL ES / Metal preview backends.

Atlas layout:
- LUT size: 33
- 6 x 6 tiles
- tile size: 33 x 33
- atlas size: 198 x 198
- R -> tile X, G -> tile Y, B -> slice/tile index
- slices 33..35 remain transparent/zero
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
from dataclasses import dataclass
from pathlib import Path

PROFILE_IDS = (
    "provia_inspired",
    "velvia_inspired",
    "astia_inspired",
    "e100_inspired",
    "ektar_inspired",
    "chrome64_inspired",
)
LUT_SIZE = 33
TILES_PER_ROW = 6
ATLAS_SIZE = LUT_SIZE * TILES_PER_ROW
PARITY_SAMPLE_COUNT = 1024
PARITY_TOLERANCE = 2.0 / 255.0
DEFAULT_PARITY_FIXTURES = Path("tool/gpu_lut_parity_fixtures.json")


@dataclass(frozen=True)
class Cube:
    size: int
    data: tuple[tuple[float, float, float], ...]

    def at(self, red: int, green: int, blue: int) -> tuple[float, float, float]:
        return self.data[red + self.size * (green + self.size * blue)]

    def sample(self, rgb: tuple[float, float, float]) -> tuple[float, float, float]:
        scale = self.size - 1
        coords = tuple(max(0.0, min(1.0, value)) * scale for value in rgb)
        low = tuple(int(math.floor(value)) for value in coords)
        high = tuple(min(value + 1, self.size - 1) for value in low)
        fraction = tuple(coords[index] - low[index] for index in range(3))

        c000 = self.at(low[0], low[1], low[2])
        c100 = self.at(high[0], low[1], low[2])
        c010 = self.at(low[0], high[1], low[2])
        c110 = self.at(high[0], high[1], low[2])
        c001 = self.at(low[0], low[1], high[2])
        c101 = self.at(high[0], low[1], high[2])
        c011 = self.at(low[0], high[1], high[2])
        c111 = self.at(high[0], high[1], high[2])

        output = []
        for channel in range(3):
            c00 = _lerp(c000[channel], c100[channel], fraction[0])
            c10 = _lerp(c010[channel], c110[channel], fraction[0])
            c01 = _lerp(c001[channel], c101[channel], fraction[0])
            c11 = _lerp(c011[channel], c111[channel], fraction[0])
            c0 = _lerp(c00, c10, fraction[1])
            c1 = _lerp(c01, c11, fraction[1])
            output.append(_lerp(c0, c1, fraction[2]))
        return tuple(output)  # type: ignore[return-value]


def parse_cube(path: Path) -> Cube:
    size: int | None = None
    samples: list[tuple[float, float, float]] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or line.startswith("TITLE"):
            continue
        if line.startswith("LUT_3D_SIZE"):
            size = int(line.split()[1])
            continue
        if line.startswith("DOMAIN_"):
            continue
        parts = line.split()
        if len(parts) == 3:
            samples.append(tuple(float(value) for value in parts))

    if size != LUT_SIZE:
        raise ValueError(f"{path}: expected LUT_3D_SIZE {LUT_SIZE}, got {size}")
    expected = LUT_SIZE**3
    if len(samples) != expected:
        raise ValueError(f"{path}: expected {expected} samples, got {len(samples)}")
    return Cube(size=LUT_SIZE, data=tuple(samples))


def load_parity_fixtures(path: Path) -> list[tuple[float, float, float]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("version") != 1:
        raise ValueError(f"{path}: unsupported fixture version")
    points = []
    for index, raw_point in enumerate(payload.get("rgb", [])):
        if not isinstance(raw_point, list) or len(raw_point) != 3:
            raise ValueError(f"{path}: rgb fixture {index} must contain 3 values")
        point = tuple(float(value) for value in raw_point)
        if any(value < 0.0 or value > 1.0 for value in point):
            raise ValueError(f"{path}: rgb fixture {index} is outside [0, 1]")
        points.append(point)
    if not points:
        raise ValueError(f"{path}: no RGB parity fixtures found")
    return points  # type: ignore[return-value]


def build_rgba8_atlas(cube: Cube) -> bytes:
    atlas = bytearray(ATLAS_SIZE * ATLAS_SIZE * 4)
    for blue in range(cube.size):
        tile_x = blue % TILES_PER_ROW
        tile_y = blue // TILES_PER_ROW
        for green in range(cube.size):
            for red in range(cube.size):
                sample = cube.at(red, green, blue)
                x = tile_x * LUT_SIZE + red
                y = tile_y * LUT_SIZE + green
                offset = (y * ATLAS_SIZE + x) * 4
                atlas[offset] = _to_u8(sample[0])
                atlas[offset + 1] = _to_u8(sample[1])
                atlas[offset + 2] = _to_u8(sample[2])
                atlas[offset + 3] = 255
    return bytes(atlas)


def sample_rgba8_atlas(
    atlas: bytes,
    rgb: tuple[float, float, float],
) -> tuple[float, float, float]:
    scale = LUT_SIZE - 1
    red = max(0.0, min(1.0, rgb[0])) * scale
    green = max(0.0, min(1.0, rgb[1])) * scale
    blue = max(0.0, min(1.0, rgb[2])) * scale

    blue_low = int(math.floor(blue))
    blue_high = min(blue_low + 1, LUT_SIZE - 1)
    blue_fraction = blue - blue_low

    low_color = _sample_slice_bilinear(atlas, blue_low, red, green)
    high_color = _sample_slice_bilinear(atlas, blue_high, red, green)
    return tuple(
        _lerp(low_color[channel], high_color[channel], blue_fraction)
        for channel in range(3)
    )  # type: ignore[return-value]


def _sample_slice_bilinear(
    atlas: bytes,
    blue: int,
    red: float,
    green: float,
) -> tuple[float, float, float]:
    red_low = int(math.floor(red))
    green_low = int(math.floor(green))
    red_high = min(red_low + 1, LUT_SIZE - 1)
    green_high = min(green_low + 1, LUT_SIZE - 1)
    red_fraction = red - red_low
    green_fraction = green - green_low

    c00 = _atlas_texel(atlas, red_low, green_low, blue)
    c10 = _atlas_texel(atlas, red_high, green_low, blue)
    c01 = _atlas_texel(atlas, red_low, green_high, blue)
    c11 = _atlas_texel(atlas, red_high, green_high, blue)

    output = []
    for channel in range(3):
        low = _lerp(c00[channel], c10[channel], red_fraction)
        high = _lerp(c01[channel], c11[channel], red_fraction)
        output.append(_lerp(low, high, green_fraction))
    return tuple(output)  # type: ignore[return-value]


def _atlas_texel(
    atlas: bytes,
    red: int,
    green: int,
    blue: int,
) -> tuple[float, float, float]:
    tile_x = blue % TILES_PER_ROW
    tile_y = blue // TILES_PER_ROW
    x = tile_x * LUT_SIZE + red
    y = tile_y * LUT_SIZE + green
    offset = (y * ATLAS_SIZE + x) * 4
    return (
        atlas[offset] / 255.0,
        atlas[offset + 1] / 255.0,
        atlas[offset + 2] / 255.0,
    )


def verify_parity(
    profile_id: str,
    cube: Cube,
    atlas: bytes,
    fixture_points: list[tuple[float, float, float]],
) -> float:
    random_source = random.Random(f"pixelcraft:{profile_id}:g0")
    points = list(fixture_points)
    points.extend(
        (random_source.random(), random_source.random(), random_source.random())
        for _ in range(PARITY_SAMPLE_COUNT)
    )

    max_error = 0.0
    for point in points:
        reference = cube.sample(point)
        preview = sample_rgba8_atlas(atlas, point)
        max_error = max(
            max_error,
            max(abs(reference[channel] - preview[channel]) for channel in range(3)),
        )
    if max_error > PARITY_TOLERANCE:
        raise AssertionError(
            f"{profile_id}: GPU atlas parity error {max_error:.6f} exceeds "
            f"{PARITY_TOLERANCE:.6f}"
        )
    return max_error


def write_profile(output_root: Path, profile_id: str, atlas: bytes) -> dict[str, object]:
    output_root.mkdir(parents=True, exist_ok=True)
    file_name = f"{profile_id}.rgba8"
    output_path = output_root / file_name
    output_path.write_bytes(atlas)
    return {
        "id": profile_id,
        "file": file_name,
        "sha256": hashlib.sha256(atlas).hexdigest(),
    }


def process_profiles(
    film_root: Path,
    output_root: Path,
    fixture_path: Path,
    *,
    write: bool,
) -> list[dict[str, object]]:
    fixture_points = load_parity_fixtures(fixture_path)
    manifest_profiles: list[dict[str, object]] = []
    for profile_id in PROFILE_IDS:
        cube_path = film_root / profile_id / "lut.cube"
        if not cube_path.is_file():
            raise FileNotFoundError(
                f"Missing {cube_path}. Run `make film-luts` before GPU LUT generation."
            )
        cube = parse_cube(cube_path)
        atlas = build_rgba8_atlas(cube)
        max_error = verify_parity(profile_id, cube, atlas, fixture_points)
        print(f"[Pixel Craft] {profile_id}: atlas parity max error {max_error:.6f}")
        if write:
            manifest_profiles.append(write_profile(output_root, profile_id, atlas))

    if write:
        manifest = {
            "version": 1,
            "format": "rgba8",
            "lutSize": LUT_SIZE,
            "tilesPerRow": TILES_PER_ROW,
            "atlasWidth": ATLAS_SIZE,
            "atlasHeight": ATLAS_SIZE,
            "sliceCount": LUT_SIZE,
            "interpolation": "bilinear-rg-linear-b",
            "parityFixtureVersion": 1,
            "profiles": manifest_profiles,
        }
        (output_root / "manifest.json").write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    return manifest_profiles


def _to_u8(value: float) -> int:
    return round(max(0.0, min(1.0, value)) * 255.0)


def _lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--film-root",
        type=Path,
        default=Path("rust/film_profiles"),
        help="Directory containing materialized profile lut.cube files.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("build/gpu_luts"),
        help="Output directory for .rgba8 atlases and manifest.json.",
    )
    parser.add_argument(
        "--fixtures",
        type=Path,
        default=DEFAULT_PARITY_FIXTURES,
        help="Shared RGB parity fixture file for future Android/iOS tests.",
    )
    parser.add_argument(
        "--verify-only",
        action="store_true",
        help="Run deterministic cube-vs-atlas parity checks without writing files.",
    )
    return parser


def main() -> None:
    args = build_parser().parse_args()
    process_profiles(
        args.film_root,
        args.output,
        args.fixtures,
        write=not args.verify_only,
    )
    if args.verify_only:
        print("[Pixel Craft] GPU LUT atlas parity verification passed")
    else:
        print(f"[Pixel Craft] GPU LUT atlases written to {args.output}")


if __name__ == "__main__":
    main()

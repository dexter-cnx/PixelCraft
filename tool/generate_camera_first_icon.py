#!/usr/bin/env python3
"""Generate the orange/black camera-first mobile launcher icon set.

Requires Pillow. This is intentionally deterministic so source and generated
Android/iOS launcher assets cannot drift from the camera-first identity.
"""

from pathlib import Path
from PIL import Image, ImageDraw

ORANGE = (255, 106, 0)
ORANGE_LIGHT = (255, 138, 48)
BLACK = (5, 5, 5)


def icon(size: int) -> Image.Image:
    image = Image.new("RGB", (size, size), BLACK)
    draw = ImageDraw.Draw(image)
    center = size / 2

    for step in range(12, 0, -1):
        radius = size * (0.36 + step * 0.012)
        strength = step / 12
        glow = (int(28 + 45 * strength), int(8 + 10 * strength), 0)
        draw.ellipse(
            (center - radius, center - radius, center + radius, center + radius),
            fill=glow,
        )

    inset = size * 0.13
    draw.rounded_rectangle(
        (inset, inset, size - inset, size - inset),
        radius=size * 0.20,
        fill=(7, 7, 7),
    )

    draw.rounded_rectangle(
        (size * 0.22, size * 0.34, size * 0.78, size * 0.70),
        radius=size * 0.085,
        fill=ORANGE,
    )
    draw.rounded_rectangle(
        (size * 0.31, size * 0.27, size * 0.49, size * 0.39),
        radius=size * 0.035,
        fill=ORANGE,
    )
    draw.ellipse(
        (size * 0.35, size * 0.36, size * 0.65, size * 0.66),
        fill=(7, 7, 7),
    )
    draw.ellipse(
        (size * 0.39, size * 0.40, size * 0.61, size * 0.62),
        fill=ORANGE_LIGHT,
    )
    draw.ellipse(
        (size * 0.43, size * 0.44, size * 0.57, size * 0.58),
        fill=(10, 10, 10),
    )
    draw.ellipse(
        (size * 0.47, size * 0.465, size * 0.515, size * 0.51),
        fill=(255, 187, 122),
    )
    draw.ellipse(
        (size * 0.69, size * 0.405, size * 0.73, size * 0.445),
        fill=(20, 20, 20),
    )
    return image


def write(path: str, size: int) -> None:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    icon(size).save(target, "PNG", optimize=True)


OUTPUTS = {
    "assets/branding/app_icon.png": 1024,
    "android/app/src/main/res/mipmap-mdpi/ic_launcher.png": 48,
    "android/app/src/main/res/mipmap-hdpi/ic_launcher.png": 72,
    "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png": 96,
    "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png": 144,
    "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png": 192,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png": 20,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png": 40,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png": 60,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png": 29,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png": 58,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png": 87,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png": 40,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png": 80,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png": 120,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png": 120,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png": 180,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png": 76,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png": 152,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png": 167,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png": 1024,
}


if __name__ == "__main__":
    for output, output_size in OUTPUTS.items():
        write(output, output_size)
    print(f"Generated {len(OUTPUTS)} camera-first launcher assets")

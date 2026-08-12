use image::{DynamicImage, RgbaImage};
use rayon::prelude::*;

const HSL_SECTORS: &[(&str, f32)] = &[
    ("red", 0.0),
    ("yellow", 60.0),
    ("green", 120.0),
    ("cyan", 180.0),
    ("blue", 240.0),
    ("magenta", 300.0),
];

pub fn is_supported(name: &str) -> bool {
    matches!(
        name,
        "temperature"
            | "tint"
            | "vibrance"
            | "vignette"
            | "grain"
            | "curve_shadows"
            | "curve_midtones"
            | "curve_highlights"
    ) || parse_hsl_filter(name).is_some()
}

pub fn apply(image: DynamicImage, name: &str, value: f32) -> Result<DynamicImage, String> {
    match name {
        "temperature" => apply_temperature(image, value),
        "tint" => apply_tint(image, value),
        "vibrance" => apply_vibrance(image, value),
        "vignette" => apply_vignette(image, value),
        "grain" => apply_grain(image, value),
        "curve_shadows" => apply_curve_zone(image, value, CurveZone::Shadows),
        "curve_midtones" => apply_curve_zone(image, value, CurveZone::Midtones),
        "curve_highlights" => apply_curve_zone(image, value, CurveZone::Highlights),
        _ => {
            if let Some((sector, component)) = parse_hsl_filter(name) {
                apply_hsl_sector(image, value, sector, component)
            } else {
                Err(format!("Unknown advanced filter: {name}"))
            }
        }
    }
}

fn clamp_u8(value: f32) -> u8 {
    value.round().clamp(0.0, 255.0) as u8
}

fn map_pixels(
    image: &RgbaImage,
    transform: impl Fn(usize, [u8; 4]) -> [u8; 4] + Sync,
) -> RgbaImage {
    let (width, height) = image.dimensions();
    let mut raw = image.as_raw().clone();
    raw.par_chunks_mut(4)
        .enumerate()
        .for_each(|(index, pixel)| {
            let mapped = transform(index, [pixel[0], pixel[1], pixel[2], pixel[3]]);
            pixel.copy_from_slice(&mapped);
        });
    RgbaImage::from_raw(width, height, raw).expect("pixel buffer size remains valid")
}

fn apply_temperature(image: DynamicImage, value: f32) -> Result<DynamicImage, String> {
    let amount = value.clamp(-1.0, 1.0);
    if amount.abs() <= f32::EPSILON {
        return Ok(image);
    }
    let rgba = image.to_rgba8();
    let result = map_pixels(&rgba, |_, p| {
        let red = 34.0 * amount;
        let green = 6.0 * amount;
        let blue = -34.0 * amount;
        [
            clamp_u8(p[0] as f32 + red),
            clamp_u8(p[1] as f32 + green),
            clamp_u8(p[2] as f32 + blue),
            p[3],
        ]
    });
    Ok(DynamicImage::ImageRgba8(result))
}

fn apply_tint(image: DynamicImage, value: f32) -> Result<DynamicImage, String> {
    let amount = value.clamp(-1.0, 1.0);
    if amount.abs() <= f32::EPSILON {
        return Ok(image);
    }
    let rgba = image.to_rgba8();
    let result = map_pixels(&rgba, |_, p| {
        [
            clamp_u8(p[0] as f32 + 16.0 * amount),
            clamp_u8(p[1] as f32 - 28.0 * amount),
            clamp_u8(p[2] as f32 + 16.0 * amount),
            p[3],
        ]
    });
    Ok(DynamicImage::ImageRgba8(result))
}

fn apply_vibrance(image: DynamicImage, value: f32) -> Result<DynamicImage, String> {
    let amount = value.clamp(-1.0, 1.0);
    if amount.abs() <= f32::EPSILON {
        return Ok(image);
    }
    let rgba = image.to_rgba8();
    let result = map_pixels(&rgba, |_, p| {
        let r = p[0] as f32 / 255.0;
        let g = p[1] as f32 / 255.0;
        let b = p[2] as f32 / 255.0;
        let max = r.max(g).max(b);
        let min = r.min(g).min(b);
        let saturation = if max <= f32::EPSILON {
            0.0
        } else {
            (max - min) / max
        };
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        let protection = if amount >= 0.0 {
            1.0 - saturation
        } else {
            1.0
        };
        let factor = 1.0 + amount * protection;
        [
            clamp_u8((luma + (r - luma) * factor) * 255.0),
            clamp_u8((luma + (g - luma) * factor) * 255.0),
            clamp_u8((luma + (b - luma) * factor) * 255.0),
            p[3],
        ]
    });
    Ok(DynamicImage::ImageRgba8(result))
}

fn apply_vignette(image: DynamicImage, value: f32) -> Result<DynamicImage, String> {
    let amount = value.clamp(-1.0, 1.0);
    if amount.abs() <= f32::EPSILON {
        return Ok(image);
    }
    let rgba = image.to_rgba8();
    let width = rgba.width().max(1) as usize;
    let height = rgba.height().max(1) as f32;
    let width_f = width as f32;
    let result = map_pixels(&rgba, |index, p| {
        let x = index % width;
        let y = index / width;
        let nx = ((x as f32 + 0.5) / width_f - 0.5) * 2.0;
        let ny = ((y as f32 + 0.5) / height - 0.5) * 2.0;
        let radius = (nx * nx + ny * ny).sqrt() / 2.0_f32.sqrt();
        let mask = smoothstep(0.35, 1.0, radius).clamp(0.0, 1.0);
        let scale = if amount >= 0.0 {
            1.0 - amount * mask * 0.72
        } else {
            1.0 + (-amount) * mask * 0.45
        };
        [
            clamp_u8(p[0] as f32 * scale),
            clamp_u8(p[1] as f32 * scale),
            clamp_u8(p[2] as f32 * scale),
            p[3],
        ]
    });
    Ok(DynamicImage::ImageRgba8(result))
}

fn apply_grain(image: DynamicImage, value: f32) -> Result<DynamicImage, String> {
    let amount = value.clamp(0.0, 1.0);
    if amount <= f32::EPSILON {
        return Ok(image);
    }
    let rgba = image.to_rgba8();
    let width = rgba.width().max(1) as usize;
    let result = map_pixels(&rgba, |index, p| {
        let x = (index % width) as u32;
        let y = (index / width) as u32;
        // Fixed coordinate hash is deliberate: grain is reproducible across
        // preview, recovery and full-resolution replay without hidden RNG state.
        let hash = deterministic_hash(x, y, 0x5049_5845);
        let noise = (hash as f32 / u32::MAX as f32) * 2.0 - 1.0;
        let delta = noise * amount * 28.0;
        [
            clamp_u8(p[0] as f32 + delta),
            clamp_u8(p[1] as f32 + delta),
            clamp_u8(p[2] as f32 + delta),
            p[3],
        ]
    });
    Ok(DynamicImage::ImageRgba8(result))
}

fn deterministic_hash(x: u32, y: u32, seed: u32) -> u32 {
    let mut value = x
        .wrapping_mul(0x9E37_79B9)
        .wrapping_add(y.wrapping_mul(0x85EB_CA6B))
        ^ seed;
    value ^= value >> 16;
    value = value.wrapping_mul(0x7FEB_352D);
    value ^= value >> 15;
    value = value.wrapping_mul(0x846C_A68B);
    value ^ (value >> 16)
}

#[derive(Clone, Copy)]
enum CurveZone {
    Shadows,
    Midtones,
    Highlights,
}

fn apply_curve_zone(
    image: DynamicImage,
    value: f32,
    zone: CurveZone,
) -> Result<DynamicImage, String> {
    let amount = value.clamp(-1.0, 1.0);
    if amount.abs() <= f32::EPSILON {
        return Ok(image);
    }
    let rgba = image.to_rgba8();
    let result = map_pixels(&rgba, |_, p| {
        let luma = (0.2126 * p[0] as f32 + 0.7152 * p[1] as f32 + 0.0722 * p[2] as f32) / 255.0;
        let mask = match zone {
            CurveZone::Shadows => 1.0 - smoothstep(0.08, 0.48, luma),
            CurveZone::Midtones => {
                let low = smoothstep(0.12, 0.5, luma);
                let high = 1.0 - smoothstep(0.5, 0.88, luma);
                (low * high).clamp(0.0, 1.0)
            }
            CurveZone::Highlights => smoothstep(0.52, 0.94, luma),
        };
        let mix = amount * mask * 0.38;
        let map = |channel: u8| {
            let c = channel as f32;
            if mix >= 0.0 {
                clamp_u8(c + (255.0 - c) * mix)
            } else {
                clamp_u8(c * (1.0 + mix))
            }
        };
        [map(p[0]), map(p[1]), map(p[2]), p[3]]
    });
    Ok(DynamicImage::ImageRgba8(result))
}

#[derive(Clone, Copy)]
enum HslComponent {
    Hue,
    Saturation,
    Luminance,
}

fn parse_hsl_filter(name: &str) -> Option<(f32, HslComponent)> {
    let rest = name.strip_prefix("hsl_")?;
    let (sector_name, component_name) = rest.rsplit_once('_')?;
    let center = HSL_SECTORS
        .iter()
        .find(|(candidate, _)| *candidate == sector_name)?
        .1;
    let component = match component_name {
        "hue" => HslComponent::Hue,
        "sat" => HslComponent::Saturation,
        "lum" => HslComponent::Luminance,
        _ => return None,
    };
    Some((center, component))
}

fn apply_hsl_sector(
    image: DynamicImage,
    value: f32,
    center: f32,
    component: HslComponent,
) -> Result<DynamicImage, String> {
    let amount = value.clamp(-1.0, 1.0);
    if amount.abs() <= f32::EPSILON {
        return Ok(image);
    }
    let rgba = image.to_rgba8();
    let result = map_pixels(&rgba, |_, p| {
        let (mut h, mut s, mut l) = rgb_to_hsl(p[0], p[1], p[2]);
        let distance = hue_distance(h, center);
        let weight = 1.0 - smoothstep(20.0, 60.0, distance);
        if weight <= f32::EPSILON {
            return p;
        }
        match component {
            HslComponent::Hue => {
                h = (h + amount * 30.0 * weight).rem_euclid(360.0);
            }
            HslComponent::Saturation => {
                s = (s + amount * 0.5 * weight).clamp(0.0, 1.0);
            }
            HslComponent::Luminance => {
                l = (l + amount * 0.35 * weight).clamp(0.0, 1.0);
            }
        }
        let rgb = hsl_to_rgb(h, s, l);
        [rgb[0], rgb[1], rgb[2], p[3]]
    });
    Ok(DynamicImage::ImageRgba8(result))
}

fn hue_distance(a: f32, b: f32) -> f32 {
    let direct = (a - b).abs();
    direct.min(360.0 - direct)
}

fn rgb_to_hsl(r: u8, g: u8, b: u8) -> (f32, f32, f32) {
    let r = r as f32 / 255.0;
    let g = g as f32 / 255.0;
    let b = b as f32 / 255.0;
    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let l = (max + min) * 0.5;
    let delta = max - min;
    if delta <= f32::EPSILON {
        return (0.0, 0.0, l);
    }
    let s = delta / (1.0 - (2.0 * l - 1.0).abs()).max(f32::EPSILON);
    let h = if (max - r).abs() <= f32::EPSILON {
        60.0 * (((g - b) / delta).rem_euclid(6.0))
    } else if (max - g).abs() <= f32::EPSILON {
        60.0 * ((b - r) / delta + 2.0)
    } else {
        60.0 * ((r - g) / delta + 4.0)
    };
    (h.rem_euclid(360.0), s.clamp(0.0, 1.0), l)
}

fn hsl_to_rgb(h: f32, s: f32, l: f32) -> [u8; 3] {
    let c = (1.0 - (2.0 * l - 1.0).abs()) * s;
    let h_prime = h.rem_euclid(360.0) / 60.0;
    let x = c * (1.0 - (h_prime.rem_euclid(2.0) - 1.0).abs());
    let (r1, g1, b1) = match h_prime as i32 {
        0 => (c, x, 0.0),
        1 => (x, c, 0.0),
        2 => (0.0, c, x),
        3 => (0.0, x, c),
        4 => (x, 0.0, c),
        _ => (c, 0.0, x),
    };
    let m = l - c * 0.5;
    [
        clamp_u8((r1 + m) * 255.0),
        clamp_u8((g1 + m) * 255.0),
        clamp_u8((b1 + m) * 255.0),
    ]
}

fn smoothstep(edge0: f32, edge1: f32, value: f32) -> f32 {
    let t = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::Rgba;

    fn solid(pixel: [u8; 4]) -> DynamicImage {
        DynamicImage::ImageRgba8(RgbaImage::from_pixel(4, 4, Rgba(pixel)))
    }

    #[test]
    fn neutral_advanced_controls_are_noops() {
        let source = solid([64, 120, 200, 77]);
        for name in [
            "temperature",
            "tint",
            "vibrance",
            "vignette",
            "grain",
            "curve_shadows",
            "curve_midtones",
            "curve_highlights",
            "hsl_red_hue",
            "hsl_blue_sat",
            "hsl_green_lum",
        ] {
            let output = apply(source.clone(), name, 0.0).unwrap();
            assert_eq!(source.to_rgba8(), output.to_rgba8(), "{name}");
        }
    }

    #[test]
    fn temperature_and_tint_move_expected_channels() {
        let warm = apply(solid([100, 100, 100, 255]), "temperature", 1.0)
            .unwrap()
            .to_rgba8();
        assert!(warm.get_pixel(0, 0).0[0] > warm.get_pixel(0, 0).0[2]);

        let magenta = apply(solid([100, 100, 100, 255]), "tint", 1.0)
            .unwrap()
            .to_rgba8();
        assert!(magenta.get_pixel(0, 0).0[1] < 100);
    }

    #[test]
    fn grain_is_deterministic_and_preserves_alpha() {
        let source = solid([120, 120, 120, 42]);
        let first = apply(source.clone(), "grain", 0.8).unwrap().to_rgba8();
        let second = apply(source, "grain", 0.8).unwrap().to_rgba8();
        assert_eq!(first, second);
        assert!(first.pixels().all(|pixel| pixel.0[3] == 42));
    }

    #[test]
    fn hsl_sector_changes_matching_color_more_than_non_matching_color() {
        let red = apply(solid([220, 40, 40, 255]), "hsl_red_sat", -1.0)
            .unwrap()
            .to_rgba8();
        let blue = apply(solid([40, 40, 220, 255]), "hsl_red_sat", -1.0)
            .unwrap()
            .to_rgba8();
        assert_ne!(red.get_pixel(0, 0).0, [220, 40, 40, 255]);
        assert_eq!(blue.get_pixel(0, 0).0, [40, 40, 220, 255]);
    }
}

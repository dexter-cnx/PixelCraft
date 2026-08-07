use image::{DynamicImage, RgbaImage};
use rayon::prelude::*;

#[derive(Debug, Clone, Copy)]
pub struct FilmProfileSpec {
    pub id: &'static str,
    pub name: &'static str,
    pub description: &'static str,
    pub contrast: f32,
    pub saturation: f32,
    pub red_gain: f32,
    pub green_gain: f32,
    pub blue_gain: f32,
    pub warmth: f32,
    pub fade: f32,
}

pub const PROFILES: &[FilmProfileSpec] = &[
    FilmProfileSpec {
        id: "provia_inspired",
        name: "Provia Inspired",
        description: "Balanced slide-film color with clean blues, lively greens and natural skin.",
        contrast: 1.05,
        saturation: 1.08,
        red_gain: 0.99,
        green_gain: 1.02,
        blue_gain: 1.03,
        warmth: 0.00,
        fade: 0.00,
    },
    FilmProfileSpec {
        id: "e100_inspired",
        name: "E100 Inspired",
        description:
            "Neutral transparency-film look with moderate saturation and clean highlights.",
        contrast: 1.04,
        saturation: 1.06,
        red_gain: 1.01,
        green_gain: 1.00,
        blue_gain: 0.995,
        warmth: 0.01,
        fade: 0.00,
    },
    FilmProfileSpec {
        id: "ektar_inspired",
        name: "Ektar Inspired",
        description:
            "Vivid color-negative look with stronger reds, contrast and landscape saturation.",
        contrast: 1.12,
        saturation: 1.22,
        red_gain: 1.06,
        green_gain: 1.01,
        blue_gain: 0.98,
        warmth: 0.015,
        fade: 0.00,
    },
    FilmProfileSpec {
        id: "chrome64_inspired",
        name: "Chrome 64 Inspired",
        description:
            "Warm nostalgic chrome rendering with restrained saturation and gently lifted blacks.",
        contrast: 1.08,
        saturation: 1.04,
        red_gain: 1.04,
        green_gain: 1.00,
        blue_gain: 0.95,
        warmth: 0.04,
        fade: 0.018,
    },
];

pub fn get(id: &str) -> Option<&'static FilmProfileSpec> {
    PROFILES.iter().find(|profile| profile.id == id)
}

pub fn apply(image: DynamicImage, id: &str, strength: f32) -> Result<DynamicImage, String> {
    let profile = get(id).ok_or_else(|| format!("Unknown film profile: {id}"))?;
    let strength = strength.clamp(0.0, 1.0);
    if strength <= f32::EPSILON {
        return Ok(image);
    }

    let source = image.to_rgba8();
    let width = source.width();
    let height = source.height();
    let mut raw = source.into_raw();

    raw.par_chunks_mut(4).for_each(|pixel| {
        let original = [
            pixel[0] as f32 / 255.0,
            pixel[1] as f32 / 255.0,
            pixel[2] as f32 / 255.0,
        ];

        let mut transformed = original;
        transformed[0] *= profile.red_gain + profile.warmth;
        transformed[1] *= profile.green_gain;
        transformed[2] *= (profile.blue_gain - profile.warmth * 0.6).max(0.0);

        for channel in &mut transformed {
            *channel = ((*channel - 0.5) * profile.contrast + 0.5).clamp(0.0, 1.0);
        }

        let luminance = transformed[0] * 0.2126 + transformed[1] * 0.7152 + transformed[2] * 0.0722;
        for channel in &mut transformed {
            *channel = (luminance + (*channel - luminance) * profile.saturation).clamp(0.0, 1.0);
            if profile.fade > 0.0 {
                *channel = profile.fade + *channel * (1.0 - profile.fade);
            }
        }

        pixel[0] = ((original[0] + (transformed[0] - original[0]) * strength).clamp(0.0, 1.0)
            * 255.0)
            .round() as u8;
        pixel[1] = ((original[1] + (transformed[1] - original[1]) * strength).clamp(0.0, 1.0)
            * 255.0)
            .round() as u8;
        pixel[2] = ((original[2] + (transformed[2] - original[2]) * strength).clamp(0.0, 1.0)
            * 255.0)
            .round() as u8;
    });

    let output = RgbaImage::from_raw(width, height, raw)
        .ok_or_else(|| "Unable to rebuild film-profile pixel buffer".to_string())?;
    Ok(DynamicImage::ImageRgba8(output))
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{Rgba, RgbaImage};

    #[test]
    fn profiles_have_unique_ids() {
        let mut ids = PROFILES.iter().map(|p| p.id).collect::<Vec<_>>();
        ids.sort_unstable();
        ids.dedup();
        assert_eq!(ids.len(), PROFILES.len());
    }

    #[test]
    fn zero_strength_preserves_pixels() {
        let source =
            DynamicImage::ImageRgba8(RgbaImage::from_pixel(2, 2, Rgba([80, 120, 160, 255])));
        let output = apply(source.clone(), "provia_inspired", 0.0).unwrap();
        assert_eq!(source.to_rgba8(), output.to_rgba8());
    }

    #[test]
    fn full_strength_changes_color_without_changing_dimensions() {
        let source =
            DynamicImage::ImageRgba8(RgbaImage::from_pixel(3, 2, Rgba([80, 120, 160, 255])));
        let output = apply(source.clone(), "ektar_inspired", 1.0).unwrap();
        assert_eq!(output.width(), 3);
        assert_eq!(output.height(), 2);
        assert_ne!(source.to_rgba8(), output.to_rgba8());
    }
}

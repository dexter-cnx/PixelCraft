use image::{DynamicImage, RgbaImage};
use imageproc::filter::{filter3x3, gaussian_blur_f32};
use rayon::prelude::*;

use crate::{advanced_filters, photon_filters};

fn parallel_map_pixels(
    image: &RgbaImage,
    transform: impl Fn([u8; 4]) -> [u8; 4] + Sync,
) -> RgbaImage {
    let (width, height) = image.dimensions();
    let mut raw = image.as_raw().clone();
    raw.par_chunks_mut(4).for_each(|pixel| {
        let mapped = transform([pixel[0], pixel[1], pixel[2], pixel[3]]);
        pixel.copy_from_slice(&mapped);
    });
    RgbaImage::from_raw(width, height, raw).expect("pixel buffer size remains valid")
}

fn clamp_u8(value: f32) -> u8 {
    value.round().clamp(0.0, 255.0) as u8
}

fn luminance01(pixel: [u8; 4]) -> f32 {
    (0.2126 * pixel[0] as f32 + 0.7152 * pixel[1] as f32 + 0.0722 * pixel[2] as f32) / 255.0
}

fn smoothstep(edge0: f32, edge1: f32, value: f32) -> f32 {
    if edge0 == edge1 {
        return if value < edge0 { 0.0 } else { 1.0 };
    }
    let t = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

fn apply_masked_tone(pixel: [u8; 4], amount: f32, mask: f32) -> [u8; 4] {
    let mix = amount.clamp(-1.0, 1.0) * mask.clamp(0.0, 1.0) * 0.5;
    let map_channel = |channel: u8| {
        let value = channel as f32;
        if mix >= 0.0 {
            clamp_u8(value + (255.0 - value) * mix)
        } else {
            clamp_u8(value * (1.0 + mix))
        }
    };

    [
        map_channel(pixel[0]),
        map_channel(pixel[1]),
        map_channel(pixel[2]),
        pixel[3],
    ]
}

pub fn apply(image: DynamicImage, filter: &str, value: f32) -> Result<DynamicImage, String> {
    if photon_filters::is_photon_filter(filter) {
        return photon_filters::apply(image, filter, value);
    }
    if advanced_filters::is_supported(filter) {
        return advanced_filters::apply(image, filter, value);
    }

    let rgba = image.to_rgba8();
    let result = match filter {
        "exposure" => {
            // Authoritative G5.1 semantics: value is exposure compensation in EV.
            // The supported range is [-2, +2] EV with 0 EV as neutral.
            let gain = 2.0_f32.powf(value.clamp(-2.0, 2.0));
            parallel_map_pixels(&rgba, |p| {
                [
                    clamp_u8(p[0] as f32 * gain),
                    clamp_u8(p[1] as f32 * gain),
                    clamp_u8(p[2] as f32 * gain),
                    p[3],
                ]
            })
        }
        "brightness" => {
            let offset = (value.clamp(0.0, 2.0) - 1.0) * 255.0;
            parallel_map_pixels(&rgba, |p| {
                [
                    clamp_u8(p[0] as f32 + offset),
                    clamp_u8(p[1] as f32 + offset),
                    clamp_u8(p[2] as f32 + offset),
                    p[3],
                ]
            })
        }
        "contrast" => {
            let factor = value.clamp(0.0, 2.0);
            parallel_map_pixels(&rgba, |p| {
                [
                    clamp_u8((p[0] as f32 - 128.0) * factor + 128.0),
                    clamp_u8((p[1] as f32 - 128.0) * factor + 128.0),
                    clamp_u8((p[2] as f32 - 128.0) * factor + 128.0),
                    p[3],
                ]
            })
        }
        "highlights" => {
            // G5.1 highlights are a selective tonal adjustment in [-1, +1].
            // 0 is neutral. The mask rises smoothly from mid-tones to white.
            let amount = value.clamp(-1.0, 1.0);
            parallel_map_pixels(&rgba, |p| {
                let mask = smoothstep(0.45, 1.0, luminance01(p));
                apply_masked_tone(p, amount, mask)
            })
        }
        "shadows" => {
            // G5.1 shadows are a selective tonal adjustment in [-1, +1].
            // 0 is neutral. The mask falls smoothly from black to mid-tones.
            let amount = value.clamp(-1.0, 1.0);
            parallel_map_pixels(&rgba, |p| {
                let mask = 1.0 - smoothstep(0.0, 0.55, luminance01(p));
                apply_masked_tone(p, amount, mask)
            })
        }
        "saturation" => {
            let factor = value.clamp(0.0, 2.0);
            parallel_map_pixels(&rgba, |p| {
                let luminance =
                    0.2126 * p[0] as f32 + 0.7152 * p[1] as f32 + 0.0722 * p[2] as f32;
                [
                    clamp_u8(luminance + (p[0] as f32 - luminance) * factor),
                    clamp_u8(luminance + (p[1] as f32 - luminance) * factor),
                    clamp_u8(luminance + (p[2] as f32 - luminance) * factor),
                    p[3],
                ]
            })
        }
        "gaussian_blur" => gaussian_blur_f32(&rgba, (value.clamp(0.0, 2.0) * 2.5).max(0.01)),
        "sharpen" => {
            let strength = value.clamp(0.0, 2.0);
            let kernel = [
                0.0,
                -strength,
                0.0,
                -strength,
                1.0 + 4.0 * strength,
                -strength,
                0.0,
                -strength,
                0.0,
            ];
            filter3x3(&rgba, &kernel)
        }
        unknown => return Err(format!("Unknown filter: {unknown}")),
    };
    Ok(DynamicImage::ImageRgba8(result))
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{Rgba, RgbaImage};

    fn image_with_pixel(pixel: [u8; 4]) -> DynamicImage {
        DynamicImage::ImageRgba8(RgbaImage::from_pixel(2, 2, Rgba(pixel)))
    }

    #[test]
    fn neutral_exposure_preserves_pixels() {
        let input = image_with_pixel([64, 128, 192, 200]);
        let output = apply(input, "exposure", 0.0).unwrap().to_rgba8();
        assert_eq!(output.get_pixel(0, 0).0, [64, 128, 192, 200]);
    }

    #[test]
    fn positive_and_negative_exposure_move_luminance_in_expected_direction() {
        let input = image_with_pixel([64, 96, 128, 255]);
        let brighter = apply(input.clone(), "exposure", 1.0).unwrap().to_rgba8();
        let darker = apply(input, "exposure", -1.0).unwrap().to_rgba8();

        assert!(brighter.get_pixel(0, 0).0[1] > 96);
        assert!(darker.get_pixel(0, 0).0[1] < 96);
    }

    #[test]
    fn neutral_highlights_and_shadows_preserve_pixels() {
        let source = [48, 112, 220, 173];
        let highlights = apply(image_with_pixel(source), "highlights", 0.0)
            .unwrap()
            .to_rgba8();
        let shadows = apply(image_with_pixel(source), "shadows", 0.0)
            .unwrap()
            .to_rgba8();

        assert_eq!(highlights.get_pixel(0, 0).0, source);
        assert_eq!(shadows.get_pixel(0, 0).0, source);
    }

    #[test]
    fn highlights_target_bright_pixels_more_than_dark_pixels() {
        let bright = apply(image_with_pixel([220, 220, 220, 255]), "highlights", -1.0)
            .unwrap()
            .to_rgba8();
        let dark = apply(image_with_pixel([32, 32, 32, 255]), "highlights", -1.0)
            .unwrap()
            .to_rgba8();

        assert!(bright.get_pixel(0, 0).0[0] < 220);
        assert_eq!(dark.get_pixel(0, 0).0[0], 32);
    }

    #[test]
    fn shadows_target_dark_pixels_more_than_bright_pixels() {
        let dark = apply(image_with_pixel([32, 32, 32, 255]), "shadows", 1.0)
            .unwrap()
            .to_rgba8();
        let bright = apply(image_with_pixel([240, 240, 240, 255]), "shadows", 1.0)
            .unwrap()
            .to_rgba8();

        assert!(dark.get_pixel(0, 0).0[0] > 32);
        assert_eq!(bright.get_pixel(0, 0).0[0], 240);
    }

    #[test]
    fn tone_controls_preserve_alpha() {
        let source = [80, 120, 200, 91];
        for (name, value) in [("exposure", 1.0), ("highlights", -0.5), ("shadows", 0.5)] {
            let output = apply(image_with_pixel(source), name, value)
                .unwrap()
                .to_rgba8();
            assert_eq!(output.get_pixel(0, 0).0[3], 91, "{name} changed alpha");
        }
    }

    #[test]
    fn neutral_brightness_preserves_pixels() {
        let input = image_with_pixel([64, 128, 192, 255]);
        let output = apply(input, "brightness", 1.0).unwrap().to_rgba8();
        assert_eq!(output.get_pixel(0, 0).0, [64, 128, 192, 255]);
    }

    #[test]
    fn zero_saturation_produces_grayscale() {
        let input = image_with_pixel([200, 20, 80, 255]);
        let output = apply(input, "saturation", 0.0).unwrap().to_rgba8();
        let pixel = output.get_pixel(0, 0).0;
        assert_eq!(pixel[0], pixel[1]);
        assert_eq!(pixel[1], pixel[2]);
        assert_eq!(pixel[3], 255);
    }

    #[test]
    fn advanced_filter_dispatch_is_authoritative() {
        let input = image_with_pixel([100, 100, 100, 255]);
        let output = apply(input, "temperature", 1.0).unwrap().to_rgba8();
        assert!(output.get_pixel(0, 0).0[0] > output.get_pixel(0, 0).0[2]);
    }

    #[test]
    fn unknown_filter_returns_error() {
        let error = apply(image_with_pixel([0, 0, 0, 255]), "missing", 1.0)
            .expect_err("unknown filter must fail");
        assert!(error.contains("Unknown filter"));
    }
}

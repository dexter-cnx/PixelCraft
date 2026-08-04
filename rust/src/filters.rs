use image::{DynamicImage, RgbaImage};
use imageproc::filter::{filter3x3, gaussian_blur_f32};
use rayon::prelude::*;

use crate::photon_filters;

fn parallel_map_pixels(image: &RgbaImage, transform: impl Fn([u8; 4]) -> [u8; 4] + Sync) -> RgbaImage {
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

pub fn apply(image: DynamicImage, filter: &str, value: f32) -> Result<DynamicImage, String> {
    if photon_filters::is_photon_filter(filter) {
        return photon_filters::apply(image, filter, value);
    }

    let rgba = image.to_rgba8();
    let result = match filter {
        "brightness" => {
            let offset = (value.clamp(0.0, 2.0) - 1.0) * 255.0;
            parallel_map_pixels(&rgba, |p| [
                clamp_u8(p[0] as f32 + offset),
                clamp_u8(p[1] as f32 + offset),
                clamp_u8(p[2] as f32 + offset),
                p[3],
            ])
        }
        "contrast" => {
            let factor = value.clamp(0.0, 2.0);
            parallel_map_pixels(&rgba, |p| [
                clamp_u8((p[0] as f32 - 128.0) * factor + 128.0),
                clamp_u8((p[1] as f32 - 128.0) * factor + 128.0),
                clamp_u8((p[2] as f32 - 128.0) * factor + 128.0),
                p[3],
            ])
        }
        "saturation" => {
            let factor = value.clamp(0.0, 2.0);
            parallel_map_pixels(&rgba, |p| {
                let luminance = 0.2126 * p[0] as f32 + 0.7152 * p[1] as f32 + 0.0722 * p[2] as f32;
                [
                    clamp_u8(luminance + (p[0] as f32 - luminance) * factor),
                    clamp_u8(luminance + (p[1] as f32 - luminance) * factor),
                    clamp_u8(luminance + (p[2] as f32 - luminance) * factor),
                    p[3],
                ]
            })
        }
        "gaussian_blur" => {
            gaussian_blur_f32(&rgba, (value.clamp(0.0, 2.0) * 2.5).max(0.01))
        }
        "sharpen" => {
            let strength = value.clamp(0.0, 2.0);
            let kernel = [
                0.0, -strength, 0.0,
                -strength, 1.0 + 4.0 * strength, -strength,
                0.0, -strength, 0.0,
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
    fn unknown_filter_returns_error() {
        let error = apply(image_with_pixel([0, 0, 0, 255]), "missing", 1.0)
            .expect_err("unknown filter must fail");
        assert!(error.contains("Unknown filter"));
    }
}

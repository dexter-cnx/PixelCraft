use image::{DynamicImage, RgbaImage};
use photon_rs::{channels, filters as photon_presets, monochrome, PhotonImage};
use rayon::prelude::*;

/// Filters delegated to photon-rs. Keep this list explicit because
/// photon_rs::filters::filter falls back to another preset for unknown names.
pub const PHOTON_FILTERS: &[&str] = &[
    "grayscale",
    "invert",
    "vintage",
    "oceanic",
    "lofi",
    "dramatic",
    "golden",
    "pastel_pink",
];

pub fn is_photon_filter(name: &str) -> bool {
    PHOTON_FILTERS.contains(&name)
}

/// Applies a Photon effect and blends it with the source so Flutter can use a
/// normalized 0.0..1.0 intensity slider. Alpha is preserved by PhotonImage.
pub fn apply(image: DynamicImage, filter: &str, intensity: f32) -> Result<DynamicImage, String> {
    if !is_photon_filter(filter) {
        return Err(format!("Unknown Photon filter: {filter}"));
    }

    let source = image.to_rgba8();
    let (width, height) = source.dimensions();
    let mut photon = PhotonImage::new(source.as_raw().clone(), width, height);

    match filter {
        "grayscale" => monochrome::grayscale(&mut photon),
        "invert" => channels::invert(&mut photon),
        preset => photon_presets::filter(&mut photon, preset),
    }

    let strength = intensity.clamp(0.0, 1.0);
    let effected = photon.get_raw_pixels();
    if effected.len() != source.as_raw().len() {
        return Err("Photon returned an invalid RGBA buffer".to_string());
    }

    let mut blended = source.into_raw();
    blended
        .par_chunks_mut(4)
        .zip(effected.par_chunks(4))
        .for_each(|(dst, fx)| {
            for channel in 0..3 {
                dst[channel] = (dst[channel] as f32
                    + (fx[channel] as f32 - dst[channel] as f32) * strength)
                    .round()
                    .clamp(0.0, 255.0) as u8;
            }
            // Preserve original alpha to avoid preset-specific alpha changes.
        });

    let rgba = RgbaImage::from_raw(width, height, blended)
        .ok_or_else(|| "Unable to construct Photon output image".to_string())?;
    Ok(DynamicImage::ImageRgba8(rgba))
}

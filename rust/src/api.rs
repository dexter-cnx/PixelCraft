use crate::engine::{decode, encode_png, ENGINE};
use crate::{filters, photon_filters};
use fast_image_resize as fir;
use flutter_rust_bridge::frb;
use image::{DynamicImage, GenericImageView, RgbaImage};
use rayon::prelude::*;
use std::num::NonZeroU32;
use std::time::Instant;

#[derive(Debug, Clone)]
pub struct ProcessedImage {
    pub bytes: Vec<u8>,
    pub elapsed_micros: u64,
}

/// Decodes an image, initializes the Rust-owned history stack, and returns dimensions.
#[frb(sync)]
pub fn load_image(bytes: Vec<u8>) -> Result<(u32, u32), String> {
    let image = decode(&bytes)?;
    let dimensions = image.dimensions();
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .reset(bytes);
    Ok(dimensions)
}

/// Returns a memory-safe preview generated in Rust. The original remains in ENGINE.
#[frb(sync)]
pub fn prepare_preview(image_bytes: Vec<u8>, max_edge: u32) -> Result<Vec<u8>, String> {
    let image = decode(&image_bytes)?;
    let (width, height) = image.dimensions();
    let scale = (max_edge as f64 / width.max(height) as f64).min(1.0);
    let preview = resize_image(
        image_bytes,
        ((width as f64 * scale).round() as u32).max(1),
        ((height as f64 * scale).round() as u32).max(1),
    )?;
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .reset_history(preview.clone());
    Ok(preview)
}

/// Legacy stateless API retained for integrations and benchmarks.
#[frb(sync)]
pub fn apply_filter(image_bytes: Vec<u8>, filter: String, value: f32) -> Result<Vec<u8>, String> {
    Ok(apply_filter_timed(image_bytes, filter, value)?.bytes)
}

#[frb(sync)]
pub fn apply_filter_timed(
    image_bytes: Vec<u8>,
    filter: String,
    value: f32,
) -> Result<ProcessedImage, String> {
    let started = Instant::now();
    let image = decode(&image_bytes)?;
    let filtered = filters::apply(image, &filter, value)?;
    let bytes = encode_png(&filtered)?;
    Ok(ProcessedImage {
        bytes,
        elapsed_micros: started.elapsed().as_micros() as u64,
    })
}

/// Captures the current committed preview as the immutable base for a slider gesture.
#[frb(sync)]
pub fn begin_filter(filter: String) -> Result<(), String> {
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .begin_filter(filter)
}

/// Re-renders from the same decoded base for every slider tick. This prevents
/// cumulative adjustment and avoids decoding the PNG again until commit.
#[frb(sync)]
pub fn update_filter_preview(filter: String, value: f32) -> Result<ProcessedImage, String> {
    let started = Instant::now();
    let base = {
        ENGINE
            .lock()
            .map_err(|_| "Engine lock poisoned".to_string())?
            .preview_base(&filter)?
    };
    let filtered = filters::apply(base, &filter, value)?;
    let bytes = encode_png(&filtered)?;
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .set_pending(bytes.clone());
    Ok(ProcessedImage {
        bytes,
        elapsed_micros: started.elapsed().as_micros() as u64,
    })
}

/// Adds exactly one history entry when the user releases the slider.
#[frb(sync)]
pub fn commit_filter() -> Result<Vec<u8>, String> {
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .commit_filter()
}

#[frb(sync)]
pub fn cancel_filter() -> Result<Vec<u8>, String> {
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .cancel_filter()
}

#[frb(sync)]
pub fn photon_filter_names() -> Vec<String> {
    photon_filters::PHOTON_FILTERS
        .iter()
        .map(|name| (*name).to_string())
        .collect()
}

/// Returns 768 bins: R[0..256], G[256..512], B[512..768].
#[frb(sync)]
pub fn get_histogram(image_bytes: Vec<u8>) -> Result<Vec<u32>, String> {
    let rgba = decode(&image_bytes)?.to_rgba8();
    let bins = rgba
        .as_raw()
        .par_chunks(4)
        .fold(
            || vec![0_u32; 768],
            |mut local, px| {
                local[px[0] as usize] += 1;
                local[256 + px[1] as usize] += 1;
                local[512 + px[2] as usize] += 1;
                local
            },
        )
        .reduce(
            || vec![0_u32; 768],
            |mut left, right| {
                left.iter_mut().zip(right).for_each(|(a, b)| *a += b);
                left
            },
        );
    Ok(bins)
}

#[frb(sync)]
pub fn resize_image(image_bytes: Vec<u8>, width: u32, height: u32) -> Result<Vec<u8>, String> {
    let width = NonZeroU32::new(width).ok_or("width must be > 0")?;
    let height = NonZeroU32::new(height).ok_or("height must be > 0")?;
    let source = decode(&image_bytes)?.to_rgba8();
    let src_width = NonZeroU32::new(source.width()).ok_or("source width is zero")?;
    let src_height = NonZeroU32::new(source.height()).ok_or("source height is zero")?;

    let src = fir::Image::from_vec_u8(src_width, src_height, source.into_raw(), fir::PixelType::U8x4)
        .map_err(|e| format!("Invalid resize source: {e}"))?;
    let mut dst = fir::Image::new(width, height, fir::PixelType::U8x4);
    let mut resizer = fir::Resizer::new(fir::ResizeAlg::Convolution(fir::FilterType::Lanczos3));
    resizer
        .resize(&src.view(), &mut dst.view_mut())
        .map_err(|e| format!("Resize failed: {e}"))?;

    let rgba = RgbaImage::from_raw(width.get(), height.get(), dst.into_vec())
        .ok_or("Invalid resized pixel buffer")?;
    encode_png(&DynamicImage::ImageRgba8(rgba))
}

#[frb(sync)]
pub fn undo() -> Result<Vec<u8>, String> {
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .undo()
        .ok_or_else(|| "No image loaded".to_string())
}

#[frb(sync)]
pub fn redo() -> Result<Vec<u8>, String> {
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .redo()
        .ok_or_else(|| "No image loaded".to_string())
}

#[frb(sync)]
pub fn current_image() -> Result<Vec<u8>, String> {
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .current()
        .ok_or_else(|| "No image loaded".to_string())
}

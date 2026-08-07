use crate::engine::{decode, encode, encode_png, EditOperation, SessionSnapshot, ENGINE};
use crate::{film_profiles, filters, photon_filters};
use fast_image_resize as fir;
use flutter_rust_bridge::frb;
use image::{DynamicImage, GenericImageView, ImageOutputFormat, RgbaImage};
use rayon::prelude::*;
use std::io::Cursor;
use std::num::NonZeroU32;
use std::time::Instant;

#[derive(Debug, Clone)]
pub struct ProcessedImage {
    pub bytes: Vec<u8>,
    pub elapsed_micros: u64,
}

#[derive(Debug, Clone)]
pub struct FilterPreviewImage {
    pub name: String,
    pub bytes: Vec<u8>,
}

#[derive(Debug, Clone)]
pub struct FilmProfileInfo {
    pub id: String,
    pub name: String,
    pub description: String,
}

#[derive(Debug, Clone)]
pub struct FilmProfilePreviewImage {
    pub id: String,
    pub bytes: Vec<u8>,
}

#[derive(Debug, Clone)]
pub struct EditSessionInfo {
    pub version: u32,
    pub operation_count: u32,
    pub cursor: u32,
    pub can_undo: bool,
    pub can_redo: bool,
}

impl From<SessionSnapshot> for EditSessionInfo {
    fn from(value: SessionSnapshot) -> Self {
        Self {
            version: value.version,
            operation_count: value.operation_count,
            cursor: value.cursor,
            can_undo: value.can_undo,
            can_redo: value.can_redo,
        }
    }
}

#[frb(sync)]
pub fn load_image(bytes: Vec<u8>) -> Result<(u32, u32), String> {
    // Reading dimensions must not fully decode a 12-50 MP camera JPEG. The
    // editor immediately prepares a reduced preview afterwards, so a full
    // decode here would make every captured photo pay that cost twice.
    let reader = image::io::Reader::new(Cursor::new(bytes.as_slice()))
        .with_guessed_format()
        .map_err(|error| format!("Unable to detect image format: {error}"))?;
    let dimensions = reader
        .into_dimensions()
        .map_err(|error| format!("Unable to read image dimensions: {error}"))?;

    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .reset(bytes);
    Ok(dimensions)
}

#[frb(sync)]
pub fn prepare_preview(_image_bytes: Vec<u8>, max_edge: u32) -> Result<Vec<u8>, String> {
    let mut engine = ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?;
    engine.set_preview_max_edge(max_edge);
    engine.prepare_preview()
}

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

#[frb(sync)]
pub fn generate_filter_previews(
    image_bytes: Vec<u8>,
    filter_names: Vec<String>,
    max_edge: u32,
) -> Result<Vec<FilterPreviewImage>, String> {
    let source = decode(&image_bytes)?;
    let thumbnail = resize_to_max_edge(source, max_edge.max(1));

    filter_names
        .into_par_iter()
        .map(|name| {
            let filtered = filters::apply(thumbnail.clone(), &name, 1.0)?;
            Ok(FilterPreviewImage {
                name,
                bytes: encode_png(&filtered)?,
            })
        })
        .collect()
}

#[frb(sync)]
pub fn film_profiles() -> Vec<FilmProfileInfo> {
    film_profiles::PROFILES
        .iter()
        .map(|profile| FilmProfileInfo {
            id: profile.id.to_string(),
            name: profile.name.to_string(),
            description: profile.description.to_string(),
        })
        .collect()
}

#[frb(sync)]
pub fn generate_film_profile_previews(
    image_bytes: Vec<u8>,
    profile_ids: Vec<String>,
    max_edge: u32,
) -> Result<Vec<FilmProfilePreviewImage>, String> {
    let source = resize_to_max_edge(decode(&image_bytes)?, max_edge.max(1));
    profile_ids
        .into_par_iter()
        .map(|id| {
            let profiled = film_profiles::apply(source.clone(), &id, 1.0)?;
            Ok(FilmProfilePreviewImage {
                id,
                bytes: encode_png(&profiled)?,
            })
        })
        .collect()
}

#[frb(sync)]
pub fn apply_film_profile(id: String, strength: f32) -> Result<Vec<u8>, String> {
    if film_profiles::get(&id).is_none() {
        return Err(format!("Unknown film profile: {id}"));
    }
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .apply_operation(EditOperation::FilmProfile {
            id,
            strength: strength.clamp(0.0, 1.0),
        })
}

#[frb(sync)]
pub fn replace_film_profile(id: String, strength: f32) -> Result<Vec<u8>, String> {
    if film_profiles::get(&id).is_none() {
        return Err(format!("Unknown film profile: {id}"));
    }
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .replace_last_draft_operation(EditOperation::FilmProfile {
            id,
            strength: strength.clamp(0.0, 1.0),
        })
}

fn resize_to_max_edge(image: DynamicImage, max_edge: u32) -> DynamicImage {
    let (width, height) = image.dimensions();
    let source_max_edge = width.max(height);
    if source_max_edge <= max_edge {
        return image;
    }
    let scale = max_edge as f64 / source_max_edge as f64;
    image.resize_exact(
        ((width as f64 * scale).round() as u32).max(1),
        ((height as f64 * scale).round() as u32).max(1),
        image::imageops::FilterType::Triangle,
    )
}

#[frb(sync)]
pub fn begin_filter(filter: String) -> Result<(), String> {
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .begin_filter(filter)
}

#[frb(sync)]
pub fn update_filter_preview(filter: String, value: f32) -> Result<ProcessedImage, String> {
    let started = Instant::now();
    let bytes = ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .update_filter_preview(&filter, value)?;
    Ok(ProcessedImage {
        bytes,
        elapsed_micros: started.elapsed().as_micros() as u64,
    })
}

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
pub fn apply_crop(x: f32, y: f32, width: f32, height: f32) -> Result<Vec<u8>, String> {
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .apply_operation(EditOperation::Crop {
            x,
            y,
            width,
            height,
        })
}

#[frb(sync)]
pub fn rotate_quarter_turns(turns: u8) -> Result<Vec<u8>, String> {
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .apply_operation(EditOperation::Rotate90 { turns: turns % 4 })
}

#[frb(sync)]
pub fn straighten(degrees: f32) -> Result<Vec<u8>, String> {
    if !(-15.0..=15.0).contains(&degrees) {
        return Err("Straighten angle must be between -15 and 15 degrees".to_string());
    }
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .apply_operation(EditOperation::RotateDegrees { degrees })
}

#[frb(sync)]
pub fn flip_horizontal() -> Result<Vec<u8>, String> {
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .apply_operation(EditOperation::FlipHorizontal)
}

#[frb(sync)]
pub fn flip_vertical() -> Result<Vec<u8>, String> {
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .apply_operation(EditOperation::FlipVertical)
}

#[frb(sync)]
pub fn resize_committed(width: u32, height: u32) -> Result<Vec<u8>, String> {
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .apply_operation(EditOperation::Resize { width, height })
}

#[frb(sync)]
pub fn session_info() -> Result<EditSessionInfo, String> {
    Ok(ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .snapshot()
        .into())
}

#[frb(sync)]
pub fn export_session_recipe() -> Result<String, String> {
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .export_recipe_json()
}

#[frb(sync)]
pub fn restore_session(bytes: Vec<u8>, recipe_json: String) -> Result<Vec<u8>, String> {
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .restore_recipe_json(bytes, &recipe_json)
}

/// Promotes the current reduced preview to the next editing checkpoint while
/// retaining the complete operation recipe. Full-resolution work is deferred
/// until export.
#[frb(sync)]
pub fn apply_edits() -> Result<Vec<u8>, String> {
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .apply_checkpoint()
}

#[frb(sync)]
pub fn export_image(format: String, quality: u8) -> Result<Vec<u8>, String> {
    let image = ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .render_full_resolution()?;
    let output_format = match format.to_ascii_lowercase().as_str() {
        "png" => ImageOutputFormat::Png,
        "jpeg" | "jpg" => ImageOutputFormat::Jpeg(quality.clamp(1, 100)),
        "webp" => ImageOutputFormat::WebP,
        other => return Err(format!("Unsupported export format: {other}")),
    };
    encode(&image, output_format)
}

#[frb(sync)]
pub fn original_preview() -> Result<Vec<u8>, String> {
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .original_preview()
}

#[frb(sync)]
pub fn photon_filter_names() -> Vec<String> {
    photon_filters::PHOTON_FILTERS
        .iter()
        .map(|name| (*name).to_string())
        .collect()
}

#[frb(sync)]
pub fn get_histogram(image_bytes: Vec<u8>) -> Result<Vec<u32>, String> {
    // During initial load `image_bytes` is the exact checkpoint preview we just
    // encoded. Reuse the already-decoded pixels kept by EngineState instead of
    // decoding that PNG again solely to build a histogram.
    let cached_rgba = {
        let engine = ENGINE
            .lock()
            .map_err(|_| "Engine lock poisoned".to_string())?;
        match (&engine.checkpoint_preview_bytes, &engine.checkpoint_preview) {
            (Some(cached_bytes), Some(cached_image))
                if cached_bytes.as_slice() == image_bytes.as_slice() =>
            {
                Some(cached_image.to_rgba8())
            }
            _ => None,
        }
    };

    let rgba = match cached_rgba {
        Some(rgba) => rgba,
        None => decode(&image_bytes)?.to_rgba8(),
    };
    Ok(histogram_bins(&rgba))
}

fn histogram_bins(rgba: &RgbaImage) -> Vec<u32> {
    rgba.as_raw()
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
        )
}

#[frb(sync)]
pub fn resize_image(image_bytes: Vec<u8>, width: u32, height: u32) -> Result<Vec<u8>, String> {
    let width = NonZeroU32::new(width).ok_or("width must be > 0")?;
    let height = NonZeroU32::new(height).ok_or("height must be > 0")?;
    let source = decode(&image_bytes)?.to_rgba8();
    let src_width = NonZeroU32::new(source.width()).ok_or("source width is zero")?;
    let src_height = NonZeroU32::new(source.height()).ok_or("source height is zero")?;

    let src = fir::Image::from_vec_u8(
        src_width,
        src_height,
        source.into_raw(),
        fir::PixelType::U8x4,
    )
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
}

#[frb(sync)]
pub fn redo() -> Result<Vec<u8>, String> {
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .redo()
}

#[frb(sync)]
pub fn current_image() -> Result<Vec<u8>, String> {
    ENGINE
        .lock()
        .map_err(|_| "Engine lock poisoned".to_string())?
        .render_preview()
}

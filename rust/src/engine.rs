use image::{imageops, DynamicImage, GenericImageView, ImageOutputFormat, Rgba};
use imageproc::geometric_transformations::{rotate_about_center, Interpolation};
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use std::io::Cursor;
use std::sync::Mutex;

use crate::{film_profiles, filters};

const DEFAULT_PREVIEW_MAX_EDGE: u32 = 1280;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum EditOperation {
    Filter {
        name: String,
        value: f32,
    },
    FilmProfile {
        id: String,
        strength: f32,
    },
    Crop {
        x: f32,
        y: f32,
        width: f32,
        height: f32,
    },
    Rotate90 {
        turns: u8,
    },
    RotateDegrees {
        degrees: f32,
    },
    FlipHorizontal,
    FlipVertical,
    Resize {
        width: u32,
        height: u32,
    },
}

#[derive(Debug, Clone)]
pub struct SessionSnapshot {
    pub version: u32,
    pub operation_count: u32,
    pub cursor: u32,
    pub can_undo: bool,
    pub can_redo: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionRecipe {
    pub version: u32,
    pub preview_max_edge: u32,
    pub operations: Vec<EditOperation>,
    pub cursor: usize,
    pub checkpoint_cursor: usize,
}

pub struct EngineState {
    /// Original full-resolution compressed bytes are kept untouched until export.
    pub original: Option<Vec<u8>>,
    /// Full edit recipe. Applied checkpoints stay in this list so export can
    /// replay the complete recipe against the original full-resolution image.
    pub operations: Vec<EditOperation>,
    /// Absolute cursor inside `operations`.
    pub cursor: usize,
    /// Operations before this cursor belong to the latest Apply checkpoint.
    /// Undo/Redo and the UI session counters operate only after this boundary.
    pub checkpoint_cursor: usize,
    pub preview_max_edge: u32,
    /// Reduced image representing the latest Apply checkpoint. All interactive
    /// editing is replayed from this image, never from the full-resolution source.
    pub checkpoint_preview: Option<DynamicImage>,
    pub checkpoint_preview_bytes: Option<Vec<u8>>,
    pub preview_base: Option<DynamicImage>,
    pub pending_operation: Option<EditOperation>,
    pub pending_preview: Option<Vec<u8>>,
    pub active_filter: Option<String>,
}

impl Default for EngineState {
    fn default() -> Self {
        Self {
            original: None,
            operations: Vec::new(),
            cursor: 0,
            checkpoint_cursor: 0,
            preview_max_edge: DEFAULT_PREVIEW_MAX_EDGE,
            checkpoint_preview: None,
            checkpoint_preview_bytes: None,
            preview_base: None,
            pending_operation: None,
            pending_preview: None,
            active_filter: None,
        }
    }
}

impl EngineState {
    pub fn reset(&mut self, bytes: Vec<u8>) {
        self.original = Some(bytes);
        self.operations.clear();
        self.cursor = 0;
        self.checkpoint_cursor = 0;
        self.preview_max_edge = DEFAULT_PREVIEW_MAX_EDGE;
        self.checkpoint_preview = None;
        self.checkpoint_preview_bytes = None;
        self.clear_transaction();
    }

    pub fn set_preview_max_edge(&mut self, max_edge: u32) {
        let max_edge = max_edge.max(1);
        if self.preview_max_edge != max_edge {
            self.preview_max_edge = max_edge;
            self.checkpoint_preview = None;
            self.checkpoint_preview_bytes = None;
        }
    }

    /// Decodes the full-resolution source once, immediately reduces it to the
    /// editor working size, and caches that reduced image for all later edits.
    pub fn prepare_preview(&mut self) -> Result<Vec<u8>, String> {
        let original = self
            .original
            .as_ref()
            .ok_or_else(|| "No image loaded".to_string())?;
        let image = resize_to_max_edge(decode(original)?, self.preview_max_edge);
        let bytes = encode_png(&image)?;
        self.checkpoint_preview = Some(image);
        self.checkpoint_preview_bytes = Some(bytes.clone());
        Ok(bytes)
    }

    pub fn original_preview(&self) -> Result<Vec<u8>, String> {
        if let Some(bytes) = &self.checkpoint_preview_bytes {
            return Ok(bytes.clone());
        }
        let original = self
            .original
            .as_ref()
            .ok_or_else(|| "No image loaded".to_string())?;
        encode_png(&resize_to_max_edge(
            decode(original)?,
            self.preview_max_edge,
        ))
    }

    pub fn begin_filter(&mut self, filter: String) -> Result<(), String> {
        self.preview_base = Some(self.render_preview_image()?);
        self.pending_operation = None;
        self.pending_preview = None;
        self.active_filter = Some(filter);
        Ok(())
    }

    pub fn update_filter_preview(&mut self, filter: &str, value: f32) -> Result<Vec<u8>, String> {
        if self.active_filter.as_deref() != Some(filter) {
            return Err("Filter transaction was not started".to_string());
        }
        let base = self
            .preview_base
            .clone()
            .ok_or_else(|| "No preview base is available".to_string())?;
        let filtered = filters::apply(base, filter, value)?;
        let bytes = encode_png(&filtered)?;
        self.pending_operation = Some(EditOperation::Filter {
            name: filter.to_string(),
            value,
        });
        self.pending_preview = Some(bytes.clone());
        Ok(bytes)
    }

    pub fn commit_filter(&mut self) -> Result<Vec<u8>, String> {
        let operation = self
            .pending_operation
            .take()
            .ok_or_else(|| "No filter preview to commit".to_string())?;
        let bytes = self
            .pending_preview
            .take()
            .ok_or_else(|| "No filter preview to commit".to_string())?;
        self.push_operation(operation);
        self.clear_transaction();
        Ok(bytes)
    }

    pub fn apply_operation(&mut self, operation: EditOperation) -> Result<Vec<u8>, String> {
        self.clear_transaction();
        self.push_operation(operation);
        self.render_preview()
    }

    pub fn replace_last_draft_operation(
        &mut self,
        operation: EditOperation,
    ) -> Result<Vec<u8>, String> {
        self.clear_transaction();
        if self.cursor > self.checkpoint_cursor {
            self.cursor -= 1;
        }
        self.operations.truncate(self.cursor);
        self.push_operation(operation);
        self.render_preview()
    }

    pub fn cancel_filter(&mut self) -> Result<Vec<u8>, String> {
        self.clear_transaction();
        self.render_preview()
    }

    pub fn undo(&mut self) -> Result<Vec<u8>, String> {
        self.clear_transaction();
        if self.cursor > self.checkpoint_cursor {
            self.cursor -= 1;
        }
        self.render_preview()
    }

    pub fn redo(&mut self) -> Result<Vec<u8>, String> {
        self.clear_transaction();
        if self.cursor < self.operations.len() {
            self.cursor += 1;
        }
        self.render_preview()
    }

    pub fn render_preview(&self) -> Result<Vec<u8>, String> {
        encode_png(&self.render_preview_image()?)
    }

    /// Apply is intentionally cheap: promote the already-rendered bounded
    /// preview to the next checkpoint and keep the full operation recipe.
    /// No full-resolution decode/filter/encode happens here.
    pub fn apply_checkpoint(&mut self) -> Result<Vec<u8>, String> {
        self.clear_transaction();
        let preview = self.render_preview_image()?;
        let bytes = encode_png(&preview)?;
        self.operations.truncate(self.cursor);
        self.checkpoint_cursor = self.cursor;
        self.checkpoint_preview = Some(preview);
        self.checkpoint_preview_bytes = Some(bytes.clone());
        Ok(bytes)
    }

    pub fn render_full_resolution(&self) -> Result<DynamicImage, String> {
        let original = self
            .original
            .as_ref()
            .ok_or_else(|| "No image loaded".to_string())?;
        let image = decode(original)?;
        replay_operations(image, &self.operations[..self.cursor])
    }

    pub fn snapshot(&self) -> SessionSnapshot {
        let operation_count = self.operations.len().saturating_sub(self.checkpoint_cursor);
        let cursor = self.cursor.saturating_sub(self.checkpoint_cursor);
        SessionSnapshot {
            version: 3,
            operation_count: operation_count as u32,
            cursor: cursor as u32,
            can_undo: self.cursor > self.checkpoint_cursor,
            can_redo: self.cursor < self.operations.len(),
        }
    }

    pub fn export_recipe_json(&self) -> Result<String, String> {
        serde_json::to_string(&SessionRecipe {
            version: 1,
            preview_max_edge: self.preview_max_edge,
            operations: self.operations.clone(),
            cursor: self.cursor,
            checkpoint_cursor: self.checkpoint_cursor,
        })
        .map_err(|error| format!("Unable to serialize session recipe: {error}"))
    }

    pub fn restore_recipe_json(&mut self, bytes: Vec<u8>, json: &str) -> Result<Vec<u8>, String> {
        let recipe: SessionRecipe = serde_json::from_str(json)
            .map_err(|error| format!("Unable to deserialize session recipe: {error}"))?;
        if recipe.version != 1 {
            return Err(format!("Unsupported session recipe version: {}", recipe.version));
        }
        if recipe.checkpoint_cursor > recipe.cursor || recipe.cursor > recipe.operations.len() {
            return Err("Invalid session recipe cursor bounds".to_string());
        }

        self.reset(bytes);
        self.preview_max_edge = recipe.preview_max_edge.max(1);
        self.operations = recipe.operations;
        self.cursor = recipe.cursor;
        self.checkpoint_cursor = recipe.checkpoint_cursor;

        let original = self
            .original
            .as_ref()
            .ok_or_else(|| "No image loaded".to_string())?;
        let base = resize_to_max_edge(decode(original)?, self.preview_max_edge);
        let checkpoint = replay_preview_operations(
            base,
            &self.operations[..self.checkpoint_cursor],
            self.preview_max_edge,
        )?;
        let checkpoint_bytes = encode_png(&checkpoint)?;
        self.checkpoint_preview = Some(checkpoint);
        self.checkpoint_preview_bytes = Some(checkpoint_bytes);
        self.render_preview()
    }

    fn push_operation(&mut self, operation: EditOperation) {
        self.operations.truncate(self.cursor);
        self.operations.push(operation);
        self.cursor = self.operations.len();
    }

    fn render_preview_image(&self) -> Result<DynamicImage, String> {
        if let Some(checkpoint) = &self.checkpoint_preview {
            return replay_preview_operations(
                checkpoint.clone(),
                &self.operations[self.checkpoint_cursor..self.cursor],
                self.preview_max_edge,
            );
        }

        let original = self
            .original
            .as_ref()
            .ok_or_else(|| "No image loaded".to_string())?;
        let base = resize_to_max_edge(decode(original)?, self.preview_max_edge);
        replay_preview_operations(base, &self.operations[..self.cursor], self.preview_max_edge)
    }

    fn clear_transaction(&mut self) {
        self.preview_base = None;
        self.pending_operation = None;
        self.pending_preview = None;
        self.active_filter = None;
    }
}

pub fn replay_operations(
    mut image: DynamicImage,
    operations: &[EditOperation],
) -> Result<DynamicImage, String> {
    for operation in operations {
        image = apply_operation_to_image(image, operation, None)?;
    }
    Ok(image)
}

fn replay_preview_operations(
    mut image: DynamicImage,
    operations: &[EditOperation],
    preview_max_edge: u32,
) -> Result<DynamicImage, String> {
    for operation in operations {
        image = apply_operation_to_image(image, operation, Some(preview_max_edge))?;
    }
    Ok(image)
}

fn apply_operation_to_image(
    image: DynamicImage,
    operation: &EditOperation,
    preview_max_edge: Option<u32>,
) -> Result<DynamicImage, String> {
    Ok(match operation {
        EditOperation::Filter { name, value } => filters::apply(image, name, *value)?,
        EditOperation::FilmProfile { id, strength } => {
            film_profiles::apply(image, id, *strength)?
        }
        EditOperation::Crop {
            x,
            y,
            width,
            height,
        } => crop_normalized(image, *x, *y, *width, *height)?,
        EditOperation::Rotate90 { turns } => match turns % 4 {
            0 => image,
            1 => image.rotate90(),
            2 => image.rotate180(),
            _ => image.rotate270(),
        },
        EditOperation::RotateDegrees { degrees } => rotate_degrees(image, *degrees),
        EditOperation::FlipHorizontal => image.fliph(),
        EditOperation::FlipVertical => image.flipv(),
        EditOperation::Resize { width, height } => {
            if *width == 0 || *height == 0 {
                return Err("Resize dimensions must be greater than zero".to_string());
            }
            if let Some(max_edge) = preview_max_edge {
                let (target_width, target_height) = fit_dimensions(*width, *height, max_edge);
                image.resize_exact(target_width, target_height, imageops::FilterType::Triangle)
            } else {
                image.resize_exact(*width, *height, imageops::FilterType::Lanczos3)
            }
        }
    })
}

fn resize_to_max_edge(image: DynamicImage, max_edge: u32) -> DynamicImage {
    let (width, height) = image.dimensions();
    if width.max(height) <= max_edge {
        return image;
    }
    let (target_width, target_height) = fit_dimensions(width, height, max_edge);
    image.resize_exact(target_width, target_height, imageops::FilterType::Triangle)
}

fn fit_dimensions(width: u32, height: u32, max_edge: u32) -> (u32, u32) {
    let source_max = width.max(height).max(1);
    if source_max <= max_edge {
        return (width.max(1), height.max(1));
    }
    let scale = max_edge as f64 / source_max as f64;
    (
        ((width as f64 * scale).round() as u32).max(1),
        ((height as f64 * scale).round() as u32).max(1),
    )
}

fn rotate_degrees(image: DynamicImage, degrees: f32) -> DynamicImage {
    if degrees.abs() < f32::EPSILON {
        return image;
    }
    let rgba = image.to_rgba8();
    let rotated = rotate_about_center(
        &rgba,
        degrees.to_radians(),
        Interpolation::Bilinear,
        Rgba([0, 0, 0, 0]),
    );
    DynamicImage::ImageRgba8(rotated)
}

fn crop_normalized(
    image: DynamicImage,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
) -> Result<DynamicImage, String> {
    if width <= 0.0 || height <= 0.0 {
        return Err("Crop width and height must be greater than zero".to_string());
    }
    let (source_width, source_height) = image.dimensions();
    if source_width == 0 || source_height == 0 {
        return Err("Cannot crop an empty image".to_string());
    }
    let left = ((x.clamp(0.0, 1.0) * source_width as f32).floor() as u32).min(source_width - 1);
    let top = ((y.clamp(0.0, 1.0) * source_height as f32).floor() as u32).min(source_height - 1);
    let crop_width = (width.clamp(0.0, 1.0) * source_width as f32).round() as u32;
    let crop_height = (height.clamp(0.0, 1.0) * source_height as f32).round() as u32;
    let crop_width = crop_width.max(1).min(source_width - left);
    let crop_height = crop_height.max(1).min(source_height - top);
    Ok(image.crop_imm(left, top, crop_width, crop_height))
}

pub static ENGINE: Lazy<Mutex<EngineState>> = Lazy::new(|| Mutex::new(EngineState::default()));

pub fn decode(bytes: &[u8]) -> Result<DynamicImage, String> {
    image::load_from_memory(bytes).map_err(|e| format!("Unable to decode image: {e}"))
}

pub fn encode_png(image: &DynamicImage) -> Result<Vec<u8>, String> {
    encode(image, ImageOutputFormat::Png)
}

pub fn encode(image: &DynamicImage, format: ImageOutputFormat) -> Result<Vec<u8>, String> {
    let mut output = Cursor::new(Vec::new());
    image
        .write_to(&mut output, format)
        .map_err(|e| format!("Unable to encode image: {e}"))?;
    Ok(output.into_inner())
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{Rgba, RgbaImage};

    fn source_png() -> Vec<u8> {
        let image =
            DynamicImage::ImageRgba8(RgbaImage::from_pixel(40, 30, Rgba([80, 120, 160, 255])));
        encode_png(&image).unwrap()
    }

    #[test]
    fn one_filter_commit_creates_one_operation() {
        let mut engine = EngineState::default();
        engine.reset(source_png());
        engine.set_preview_max_edge(20);
        engine.prepare_preview().unwrap();
        engine.begin_filter("brightness".to_string()).unwrap();
        engine.update_filter_preview("brightness", 1.2).unwrap();
        engine.update_filter_preview("brightness", 1.4).unwrap();
        engine.commit_filter().unwrap();

        assert_eq!(engine.operations.len(), 1);
        assert_eq!(engine.cursor, 1);
        assert_eq!(
            engine.operations[0],
            EditOperation::Filter {
                name: "brightness".to_string(),
                value: 1.4,
            }
        );
    }

    #[test]
    fn film_profile_is_replayable() {
        let mut engine = EngineState::default();
        engine.reset(source_png());
        engine.set_preview_max_edge(20);
        engine.prepare_preview().unwrap();
        let bytes = engine
            .apply_operation(EditOperation::FilmProfile {
                id: "provia_inspired".to_string(),
                strength: 0.8,
            })
            .unwrap();
        assert!(!bytes.is_empty());
        assert_eq!(engine.cursor, 1);
    }

    #[test]
    fn apply_checkpoint_keeps_full_recipe_but_resets_draft_session() {
        let mut engine = EngineState::default();
        engine.reset(source_png());
        engine.set_preview_max_edge(20);
        engine.prepare_preview().unwrap();
        engine
            .apply_operation(EditOperation::Filter {
                name: "brightness".to_string(),
                value: 1.3,
            })
            .unwrap();

        engine.apply_checkpoint().unwrap();

        assert_eq!(engine.operations.len(), 1);
        assert_eq!(engine.checkpoint_cursor, 1);
        assert_eq!(engine.cursor, 1);
        let snapshot = engine.snapshot();
        assert_eq!(snapshot.operation_count, 0);
        assert_eq!(snapshot.cursor, 0);
        assert!(!snapshot.can_undo);
        assert_eq!(
            engine.render_full_resolution().unwrap().dimensions(),
            (40, 30)
        );
    }

    #[test]
    fn session_recipe_round_trip_restores_checkpoint_and_draft() {
        let original = source_png();
        let mut engine = EngineState::default();
        engine.reset(original.clone());
        engine.set_preview_max_edge(20);
        engine.prepare_preview().unwrap();
        engine
            .apply_operation(EditOperation::FilmProfile {
                id: "e100_inspired".to_string(),
                strength: 0.7,
            })
            .unwrap();
        engine.apply_checkpoint().unwrap();
        engine
            .apply_operation(EditOperation::Rotate90 { turns: 1 })
            .unwrap();
        let expected = engine.render_preview().unwrap();
        let recipe = engine.export_recipe_json().unwrap();

        let mut restored = EngineState::default();
        let actual = restored.restore_recipe_json(original, &recipe).unwrap();
        assert_eq!(actual, expected);
        assert_eq!(restored.checkpoint_cursor, 1);
        assert_eq!(restored.cursor, 2);
    }

    #[test]
    fn undo_does_not_cross_apply_checkpoint() {
        let mut engine = EngineState::default();
        engine.reset(source_png());
        engine.prepare_preview().unwrap();
        engine
            .apply_operation(EditOperation::Rotate90 { turns: 1 })
            .unwrap();
        engine.apply_checkpoint().unwrap();
        engine
            .apply_operation(EditOperation::FlipHorizontal)
            .unwrap();

        engine.undo().unwrap();
        assert_eq!(engine.cursor, engine.checkpoint_cursor);
        engine.undo().unwrap();
        assert_eq!(engine.cursor, engine.checkpoint_cursor);
    }

    #[test]
    fn new_commit_after_undo_discards_redo_operations() {
        let mut engine = EngineState::default();
        engine.reset(source_png());
        engine.prepare_preview().unwrap();
        for value in [1.1, 1.2] {
            engine.begin_filter("brightness".to_string()).unwrap();
            engine.update_filter_preview("brightness", value).unwrap();
            engine.commit_filter().unwrap();
        }
        engine.undo().unwrap();
        engine.begin_filter("contrast".to_string()).unwrap();
        engine.update_filter_preview("contrast", 1.3).unwrap();
        engine.commit_filter().unwrap();

        assert_eq!(engine.operations.len(), 2);
        assert_eq!(engine.cursor, 2);
        assert!(matches!(
            engine.operations[1],
            EditOperation::Filter { ref name, .. } if name == "contrast"
        ));
    }
}

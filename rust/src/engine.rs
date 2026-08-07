use image::{imageops, DynamicImage, GenericImageView, ImageOutputFormat, Rgba};
use imageproc::geometric_transformations::{rotate_about_center, Interpolation};
use once_cell::sync::Lazy;
use std::io::Cursor;
use std::sync::Mutex;

use crate::filters;

const DEFAULT_PREVIEW_MAX_EDGE: u32 = 1280;

#[derive(Debug, Clone, PartialEq)]
pub enum EditOperation {
    Filter {
        name: String,
        value: f32,
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

pub struct EngineState {
    pub original: Option<Vec<u8>>,
    pub operations: Vec<EditOperation>,
    /// Number of active operations. Operations after the cursor are redo items.
    pub cursor: usize,
    pub preview_max_edge: u32,
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
            preview_max_edge: DEFAULT_PREVIEW_MAX_EDGE,
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
        self.preview_max_edge = DEFAULT_PREVIEW_MAX_EDGE;
        self.clear_transaction();
    }

    pub fn set_preview_max_edge(&mut self, max_edge: u32) {
        self.preview_max_edge = max_edge.max(1);
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

    pub fn cancel_filter(&mut self) -> Result<Vec<u8>, String> {
        self.clear_transaction();
        self.render_preview()
    }

    pub fn undo(&mut self) -> Result<Vec<u8>, String> {
        self.clear_transaction();
        self.cursor = self.cursor.saturating_sub(1);
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

    pub fn render_full_resolution(&self) -> Result<DynamicImage, String> {
        let original = self
            .original
            .as_ref()
            .ok_or_else(|| "No image loaded".to_string())?;
        let image = decode(original)?;
        replay_operations(image, &self.operations[..self.cursor])
    }

    pub fn snapshot(&self) -> SessionSnapshot {
        SessionSnapshot {
            version: 1,
            operation_count: self.operations.len() as u32,
            cursor: self.cursor as u32,
            can_undo: self.cursor > 0,
            can_redo: self.cursor < self.operations.len(),
        }
    }

    fn push_operation(&mut self, operation: EditOperation) {
        self.operations.truncate(self.cursor);
        self.operations.push(operation);
        self.cursor = self.operations.len();
    }

    fn render_preview_image(&self) -> Result<DynamicImage, String> {
        let full = self.render_full_resolution()?;
        let (width, height) = full.dimensions();
        let max_edge = width.max(height);
        if max_edge <= self.preview_max_edge {
            return Ok(full);
        }
        let scale = self.preview_max_edge as f64 / max_edge as f64;
        let target_width = ((width as f64 * scale).round() as u32).max(1);
        let target_height = ((height as f64 * scale).round() as u32).max(1);
        Ok(full.resize_exact(target_width, target_height, imageops::FilterType::Lanczos3))
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
        image = match operation {
            EditOperation::Filter { name, value } => filters::apply(image, name, *value)?,
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
                image.resize_exact(*width, *height, imageops::FilterType::Lanczos3)
            }
        };
    }
    Ok(image)
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
            DynamicImage::ImageRgba8(RgbaImage::from_pixel(4, 3, Rgba([80, 120, 160, 255])));
        encode_png(&image).unwrap()
    }

    #[test]
    fn one_filter_commit_creates_one_operation() {
        let mut engine = EngineState::default();
        engine.reset(source_png());
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
    fn transform_operations_are_replayable_and_undoable() {
        let mut engine = EngineState::default();
        engine.reset(source_png());
        engine
            .apply_operation(EditOperation::Rotate90 { turns: 1 })
            .unwrap();
        engine
            .apply_operation(EditOperation::FlipHorizontal)
            .unwrap();
        engine
            .apply_operation(EditOperation::Crop {
                x: 0.0,
                y: 0.0,
                width: 0.5,
                height: 1.0,
            })
            .unwrap();

        assert_eq!(engine.operations.len(), 3);
        assert_eq!(engine.cursor, 3);
        engine.undo().unwrap();
        assert_eq!(engine.cursor, 2);
        engine.redo().unwrap();
        assert_eq!(engine.cursor, 3);
    }

    #[test]
    fn new_commit_after_undo_discards_redo_operations() {
        let mut engine = EngineState::default();
        engine.reset(source_png());
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

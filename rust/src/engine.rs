use image::{DynamicImage, ImageOutputFormat};
use once_cell::sync::Lazy;
use std::io::Cursor;
use std::sync::Mutex;

const MAX_HISTORY: usize = 20;

#[derive(Default)]
pub struct EngineState {
    /// Original compressed image, retained for future full-resolution export.
    pub original: Option<Vec<u8>>,
    /// Compressed preview history. Keeping PNG entries avoids retaining many
    /// 48 MB raw buffers for a 4000x3000 RGBA source.
    pub history: Vec<Vec<u8>>,
    pub cursor: usize,
    /// Decoded immutable base captured when a slider gesture starts.
    pub preview_base: Option<DynamicImage>,
    /// Latest preview output. It is committed only when the gesture ends.
    pub pending_preview: Option<Vec<u8>>,
    pub active_filter: Option<String>,
}

impl EngineState {
    pub fn reset(&mut self, bytes: Vec<u8>) {
        self.original = Some(bytes.clone());
        self.history.clear();
        self.history.push(bytes);
        self.cursor = 0;
        self.clear_transaction();
    }

    pub fn reset_history(&mut self, bytes: Vec<u8>) {
        self.history.clear();
        self.history.push(bytes);
        self.cursor = 0;
        self.clear_transaction();
    }

    pub fn begin_filter(&mut self, filter: String) -> Result<(), String> {
        let current = self
            .current()
            .ok_or_else(|| "No image loaded".to_string())?;
        self.preview_base = Some(decode(&current)?);
        self.pending_preview = None;
        self.active_filter = Some(filter);
        Ok(())
    }

    pub fn preview_base(&self, filter: &str) -> Result<DynamicImage, String> {
        if self.active_filter.as_deref() != Some(filter) {
            return Err("Filter transaction was not started".to_string());
        }
        self.preview_base
            .clone()
            .ok_or_else(|| "No preview base is available".to_string())
    }

    pub fn set_pending(&mut self, bytes: Vec<u8>) {
        self.pending_preview = Some(bytes);
    }

    pub fn commit_filter(&mut self) -> Result<Vec<u8>, String> {
        let bytes = self
            .pending_preview
            .take()
            .ok_or_else(|| "No filter preview to commit".to_string())?;
        self.push(bytes.clone());
        self.clear_transaction();
        Ok(bytes)
    }

    pub fn cancel_filter(&mut self) -> Result<Vec<u8>, String> {
        self.clear_transaction();
        self.current().ok_or_else(|| "No image loaded".to_string())
    }

    pub fn push(&mut self, bytes: Vec<u8>) {
        self.history.truncate(self.cursor + 1);
        self.history.push(bytes);
        if self.history.len() > MAX_HISTORY {
            self.history.remove(0);
        }
        self.cursor = self.history.len().saturating_sub(1);
    }

    pub fn undo(&mut self) -> Option<Vec<u8>> {
        self.clear_transaction();
        if self.cursor > 0 {
            self.cursor -= 1;
        }
        self.history.get(self.cursor).cloned()
    }

    pub fn redo(&mut self) -> Option<Vec<u8>> {
        self.clear_transaction();
        if self.cursor + 1 < self.history.len() {
            self.cursor += 1;
        }
        self.history.get(self.cursor).cloned()
    }

    pub fn current(&self) -> Option<Vec<u8>> {
        self.history.get(self.cursor).cloned()
    }

    fn clear_transaction(&mut self) {
        self.preview_base = None;
        self.pending_preview = None;
        self.active_filter = None;
    }
}

pub static ENGINE: Lazy<Mutex<EngineState>> = Lazy::new(|| Mutex::new(EngineState::default()));

pub fn decode(bytes: &[u8]) -> Result<DynamicImage, String> {
    image::load_from_memory(bytes).map_err(|e| format!("Unable to decode image: {e}"))
}

pub fn encode_png(image: &DynamicImage) -> Result<Vec<u8>, String> {
    let mut output = Cursor::new(Vec::new());
    image
        .write_to(&mut output, ImageOutputFormat::Png)
        .map_err(|e| format!("Unable to encode PNG: {e}"))?;
    Ok(output.into_inner())
}

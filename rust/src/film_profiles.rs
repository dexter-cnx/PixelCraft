use image::{DynamicImage, RgbaImage};
use once_cell::sync::Lazy;
use rayon::prelude::*;
use serde::Deserialize;

const FILM_PROFILE_PACK_VERSION: u32 = 2;
const FILM_LUT_SIZE: usize = 33;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct FilmProfileManifest {
    id: String,
    name: String,
    description: String,
    lut: String,
    lut_size: usize,
    pack_version: u32,
    default_strength: f32,
}

#[derive(Debug, Clone)]
pub struct FilmProfileSpec {
    pub id: String,
    pub name: String,
    pub description: String,
    lut: CubeLut,
}

#[derive(Debug, Clone)]
struct CubeLut {
    size: usize,
    domain_min: [f32; 3],
    domain_max: [f32; 3],
    data: Vec<[f32; 3]>,
}

struct EmbeddedProfileSource {
    manifest: &'static str,
    lut: &'static str,
}

const PROFILE_SOURCES: &[EmbeddedProfileSource] = &[
    EmbeddedProfileSource {
        manifest: include_str!("../film_profiles/provia_inspired/profile.json"),
        lut: include_str!(concat!(
            env!("OUT_DIR"),
            "/film_profiles/provia_inspired/lut.cube"
        )),
    },
    EmbeddedProfileSource {
        manifest: include_str!("../film_profiles/velvia_inspired/profile.json"),
        lut: include_str!(concat!(
            env!("OUT_DIR"),
            "/film_profiles/velvia_inspired/lut.cube"
        )),
    },
    EmbeddedProfileSource {
        manifest: include_str!("../film_profiles/astia_inspired/profile.json"),
        lut: include_str!(concat!(
            env!("OUT_DIR"),
            "/film_profiles/astia_inspired/lut.cube"
        )),
    },
    EmbeddedProfileSource {
        manifest: include_str!("../film_profiles/e100_inspired/profile.json"),
        lut: include_str!(concat!(
            env!("OUT_DIR"),
            "/film_profiles/e100_inspired/lut.cube"
        )),
    },
    EmbeddedProfileSource {
        manifest: include_str!("../film_profiles/ektar_inspired/profile.json"),
        lut: include_str!(concat!(
            env!("OUT_DIR"),
            "/film_profiles/ektar_inspired/lut.cube"
        )),
    },
    EmbeddedProfileSource {
        manifest: include_str!("../film_profiles/chrome64_inspired/profile.json"),
        lut: include_str!(concat!(
            env!("OUT_DIR"),
            "/film_profiles/chrome64_inspired/lut.cube"
        )),
    },
];

pub static PROFILES: Lazy<Vec<FilmProfileSpec>> = Lazy::new(|| {
    PROFILE_SOURCES
        .iter()
        .map(|source| {
            parse_profile(source)
                .unwrap_or_else(|error| panic!("Invalid bundled film profile: {error}"))
        })
        .collect()
});

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
        let transformed = profile.lut.sample(original);

        pixel[0] = mix_channel(original[0], transformed[0], strength);
        pixel[1] = mix_channel(original[1], transformed[1], strength);
        pixel[2] = mix_channel(original[2], transformed[2], strength);
    });

    let output = RgbaImage::from_raw(width, height, raw)
        .ok_or_else(|| "Unable to rebuild film-profile pixel buffer".to_string())?;
    Ok(DynamicImage::ImageRgba8(output))
}

fn mix_channel(source: f32, target: f32, strength: f32) -> u8 {
    ((source + (target - source) * strength).clamp(0.0, 1.0) * 255.0).round() as u8
}

fn parse_profile(source: &EmbeddedProfileSource) -> Result<FilmProfileSpec, String> {
    let manifest: FilmProfileManifest = serde_json::from_str(source.manifest)
        .map_err(|error| format!("Invalid profile.json: {error}"))?;
    if manifest.id.trim().is_empty() || manifest.name.trim().is_empty() {
        return Err("Film profile id and name must not be empty".to_string());
    }
    if manifest.lut != "lut.cube" {
        return Err(format!(
            "Profile {} references unsupported LUT file {}",
            manifest.id, manifest.lut
        ));
    }
    if manifest.pack_version != FILM_PROFILE_PACK_VERSION {
        return Err(format!(
            "Profile {} uses packVersion {}, expected {}",
            manifest.id, manifest.pack_version, FILM_PROFILE_PACK_VERSION
        ));
    }
    if manifest.lut_size != FILM_LUT_SIZE {
        return Err(format!(
            "Profile {} declares LUT size {}, expected {}",
            manifest.id, manifest.lut_size, FILM_LUT_SIZE
        ));
    }
    if !(0.0..=1.0).contains(&manifest.default_strength) {
        return Err(format!(
            "Profile {} defaultStrength must be between 0 and 1",
            manifest.id
        ));
    }

    let lut = CubeLut::parse(source.lut)?;
    if lut.size != manifest.lut_size {
        return Err(format!(
            "Profile {} manifest declares {}^3 but LUT contains {}^3",
            manifest.id, manifest.lut_size, lut.size
        ));
    }

    Ok(FilmProfileSpec {
        id: manifest.id,
        name: manifest.name,
        description: manifest.description,
        lut,
    })
}

impl CubeLut {
    fn parse(source: &str) -> Result<Self, String> {
        let mut size = None;
        let mut domain_min = [0.0_f32; 3];
        let mut domain_max = [1.0_f32; 3];
        let mut data = Vec::new();

        for (line_number, raw_line) in source.lines().enumerate() {
            let line = raw_line.trim();
            if line.is_empty() || line.starts_with('#') || line.starts_with("TITLE") {
                continue;
            }

            if let Some(value) = line.strip_prefix("LUT_3D_SIZE") {
                size = Some(
                    value
                        .trim()
                        .parse::<usize>()
                        .map_err(|_| format!("Invalid LUT_3D_SIZE on line {}", line_number + 1))?,
                );
                continue;
            }
            if let Some(value) = line.strip_prefix("DOMAIN_MIN") {
                domain_min = parse_triplet(value, line_number + 1)?;
                continue;
            }
            if let Some(value) = line.strip_prefix("DOMAIN_MAX") {
                domain_max = parse_triplet(value, line_number + 1)?;
                continue;
            }
            if line.starts_with("LUT_1D_SIZE") {
                return Err("1D LUTs are not supported for film profiles".to_string());
            }

            data.push(parse_triplet(line, line_number + 1)?);
        }

        let size = size.ok_or_else(|| "Missing LUT_3D_SIZE".to_string())?;
        if size < 2 {
            return Err("LUT_3D_SIZE must be at least 2".to_string());
        }
        let expected = size
            .checked_mul(size)
            .and_then(|value| value.checked_mul(size))
            .ok_or_else(|| "LUT size overflow".to_string())?;
        if data.len() != expected {
            return Err(format!(
                "LUT contains {} samples but {} were expected for size {}",
                data.len(), expected, size
            ));
        }
        for channel in 0..3 {
            if domain_max[channel] <= domain_min[channel] {
                return Err("DOMAIN_MAX must be greater than DOMAIN_MIN".to_string());
            }
        }

        Ok(Self {
            size,
            domain_min,
            domain_max,
            data,
        })
    }

    fn sample(&self, rgb: [f32; 3]) -> [f32; 3] {
        let scale = (self.size - 1) as f32;
        let coords = [0, 1, 2].map(|channel| {
            ((rgb[channel] - self.domain_min[channel])
                / (self.domain_max[channel] - self.domain_min[channel]))
                .clamp(0.0, 1.0)
                * scale
        });

        let low = coords.map(|value| value.floor() as usize);
        let high = [0, 1, 2].map(|channel| (low[channel] + 1).min(self.size - 1));
        let fraction = [0, 1, 2].map(|channel| coords[channel] - low[channel] as f32);

        let c000 = self.at(low[0], low[1], low[2]);
        let c100 = self.at(high[0], low[1], low[2]);
        let c010 = self.at(low[0], high[1], low[2]);
        let c110 = self.at(high[0], high[1], low[2]);
        let c001 = self.at(low[0], low[1], high[2]);
        let c101 = self.at(high[0], low[1], high[2]);
        let c011 = self.at(low[0], high[1], high[2]);
        let c111 = self.at(high[0], high[1], high[2]);

        [0, 1, 2].map(|channel| {
            let c00 = lerp(c000[channel], c100[channel], fraction[0]);
            let c10 = lerp(c010[channel], c110[channel], fraction[0]);
            let c01 = lerp(c001[channel], c101[channel], fraction[0]);
            let c11 = lerp(c011[channel], c111[channel], fraction[0]);
            let c0 = lerp(c00, c10, fraction[1]);
            let c1 = lerp(c01, c11, fraction[1]);
            lerp(c0, c1, fraction[2]).clamp(0.0, 1.0)
        })
    }

    fn at(&self, red: usize, green: usize, blue: usize) -> [f32; 3] {
        // Pixel Craft's .cube files use the common red-fastest ordering.
        self.data[red + self.size * (green + self.size * blue)]
    }
}

fn parse_triplet(source: &str, line_number: usize) -> Result<[f32; 3], String> {
    let values = source
        .split_whitespace()
        .map(|value| {
            value
                .parse::<f32>()
                .map_err(|_| format!("Invalid numeric value on line {line_number}"))
        })
        .collect::<Result<Vec<_>, _>>()?;
    if values.len() != 3 {
        return Err(format!("Expected 3 values on line {line_number}"));
    }
    Ok([values[0], values[1], values[2]])
}

fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{Rgba, RgbaImage};

    #[test]
    fn pack_v2_has_six_unique_33_cube_profiles() {
        let mut ids = PROFILES
            .iter()
            .map(|profile| profile.id.as_str())
            .collect::<Vec<_>>();
        ids.sort_unstable();
        ids.dedup();

        assert_eq!(PROFILES.len(), 6);
        assert_eq!(ids.len(), PROFILES.len());
        assert!(PROFILES.iter().all(|profile| !profile.name.is_empty()));
        assert!(PROFILES.iter().all(|profile| profile.lut.size == FILM_LUT_SIZE));
        assert!(PROFILES.iter().all(|profile| profile.lut.data.len() == 35_937));
        assert!(get("provia_inspired").is_some());
        assert!(get("velvia_inspired").is_some());
        assert!(get("astia_inspired").is_some());
        assert!(get("e100_inspired").is_some());
        assert!(get("ektar_inspired").is_some());
        assert!(get("chrome64_inspired").is_some());
    }

    #[test]
    fn cube_parser_rejects_wrong_sample_count() {
        let result = CubeLut::parse("LUT_3D_SIZE 2\n0 0 0\n");
        assert!(result.is_err());
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

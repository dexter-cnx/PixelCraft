use serde::Deserialize;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

const PROFILE_IDS: &[&str] = &[
    "provia_inspired",
    "velvia_inspired",
    "astia_inspired",
    "e100_inspired",
    "ektar_inspired",
    "chrome64_inspired",
];
const FILM_LUT_SIZE: usize = 33;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProfileManifest {
    name: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LookDefinition {
    lut_size: usize,
    contrast: f32,
    black_lift: f32,
    toe: f32,
    shoulder: f32,
    saturation: f32,
    matrix: [[f32; 3]; 3],
    channel_gamma: [f32; 3],
    shadow_tint: [f32; 3],
    highlight_tint: [f32; 3],
    selective: Vec<SelectiveAdjustment>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SelectiveAdjustment {
    center_hue: f32,
    width: f32,
    saturation: f32,
    value: f32,
    hue_shift: f32,
}

fn main() {
    // flutter_rust_bridge 2.12 expands #[frb(...)] using cfg(frb_expand).
    // Register it with rustc's check-cfg system so `clippy -D warnings`
    // accepts the macro-generated configuration name on modern Rust.
    println!("cargo:rustc-check-cfg=cfg(frb_expand)");
    println!("cargo:rerun-if-env-changed=PIXELCRAFT_EXPORT_LUT_DIR");

    let crate_root = PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    let out_root = PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR")).join("film_profiles");
    let export_root = env::var_os("PIXELCRAFT_EXPORT_LUT_DIR").map(PathBuf::from);

    for id in PROFILE_IDS {
        let profile_root = crate_root.join("film_profiles").join(id);
        let manifest_path = profile_root.join("profile.json");
        let look_path = profile_root.join("look.json");
        println!("cargo:rerun-if-changed={}", manifest_path.display());
        println!("cargo:rerun-if-changed={}", look_path.display());

        let manifest: ProfileManifest = read_json(&manifest_path);
        let look: LookDefinition = read_json(&look_path);
        if look.lut_size != FILM_LUT_SIZE {
            panic!(
                "Film Profile Pack v2 requires {}^3 LUTs; {} requested {}",
                FILM_LUT_SIZE, id, look.lut_size
            );
        }
        validate_look(id, &look);

        let cube = generate_cube(&manifest.name, &look);
        write_cube(&out_root.join(id).join("lut.cube"), &cube);
        if let Some(root) = &export_root {
            write_cube(&root.join(id).join("lut.cube"), &cube);
        }
    }
}

fn read_json<T: for<'de> Deserialize<'de>>(path: &Path) -> T {
    let source = fs::read_to_string(path)
        .unwrap_or_else(|error| panic!("Unable to read {}: {error}", path.display()));
    serde_json::from_str(&source)
        .unwrap_or_else(|error| panic!("Invalid JSON in {}: {error}", path.display()))
}

fn validate_look(id: &str, look: &LookDefinition) {
    if !(0.75..=1.4).contains(&look.contrast) {
        panic!("{id}: contrast is outside the supported authoring range");
    }
    if !(0.0..=0.12).contains(&look.black_lift) {
        panic!("{id}: blackLift is outside the supported authoring range");
    }
    if !(0.0..=0.35).contains(&look.toe) || !(0.0..=0.35).contains(&look.shoulder) {
        panic!("{id}: toe/shoulder is outside the supported authoring range");
    }
    if !(0.65..=1.5).contains(&look.saturation) {
        panic!("{id}: saturation is outside the supported authoring range");
    }
    if look.channel_gamma.iter().any(|value| !(0.75..=1.3).contains(value)) {
        panic!("{id}: channelGamma is outside the supported authoring range");
    }
    for adjustment in &look.selective {
        if adjustment.width <= 0.0 || adjustment.width > 180.0 {
            panic!("{id}: selective hue width must be in (0, 180]");
        }
    }
}

fn write_cube(path: &Path, cube: &str) {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .unwrap_or_else(|error| panic!("Unable to create {}: {error}", parent.display()));
    }
    fs::write(path, cube)
        .unwrap_or_else(|error| panic!("Unable to write {}: {error}", path.display()));
}

fn generate_cube(title: &str, look: &LookDefinition) -> String {
    let size = look.lut_size;
    let mut output = String::with_capacity(size * size * size * 32);
    output.push_str(&format!("TITLE \"{}\"\n", title.replace('"', "'")));
    output.push_str(&format!("LUT_3D_SIZE {size}\n"));
    output.push_str("DOMAIN_MIN 0.0 0.0 0.0\n");
    output.push_str("DOMAIN_MAX 1.0 1.0 1.0\n\n");

    let denominator = (size - 1) as f32;
    // .cube red-fastest ordering: R changes fastest, then G, then B.
    for blue in 0..size {
        for green in 0..size {
            for red in 0..size {
                let rgb = [
                    red as f32 / denominator,
                    green as f32 / denominator,
                    blue as f32 / denominator,
                ];
                let transformed = apply_look(rgb, look);
                output.push_str(&format!(
                    "{:.7} {:.7} {:.7}\n",
                    transformed[0], transformed[1], transformed[2]
                ));
            }
        }
    }
    output
}

fn apply_look(rgb: [f32; 3], look: &LookDefinition) -> [f32; 3] {
    let mut color = multiply_matrix(look.matrix, rgb);
    color = color.map(clamp01);

    let luminance = luma(color);
    for channel in &mut color {
        *channel = luminance + (*channel - luminance) * look.saturation;
    }
    color = color.map(clamp01);

    let mut hsv = rgb_to_hsv(color);
    for adjustment in &look.selective {
        let weight = hue_band_weight(hsv[0], adjustment.center_hue, adjustment.width);
        hsv[0] = wrap_hue(hsv[0] + adjustment.hue_shift * weight);
        hsv[1] = clamp01(hsv[1] * (1.0 + (adjustment.saturation - 1.0) * weight));
        hsv[2] = clamp01(hsv[2] * (1.0 + (adjustment.value - 1.0) * weight));
    }
    color = hsv_to_rgb(hsv);

    let luminance = luma(color);
    let shadow_weight = (1.0 - luminance).powi(2);
    let highlight_weight = luminance.powi(2);
    for channel in 0..3 {
        color[channel] += look.shadow_tint[channel] * shadow_weight;
        color[channel] += look.highlight_tint[channel] * highlight_weight;
        color[channel] = clamp01(color[channel]);
        color[channel] = color[channel].powf(look.channel_gamma[channel]);
        color[channel] = filmic_tone(color[channel], look);
    }
    color.map(clamp01)
}

fn filmic_tone(value: f32, look: &LookDefinition) -> f32 {
    let mut value = look.black_lift + value * (1.0 - look.black_lift);
    value = 0.5 + (value - 0.5) * look.contrast;
    value = clamp01(value);

    if look.toe > 0.0 {
        let toe_weight = (1.0 - value).powi(2);
        let darkened = value.powf(1.0 + look.toe);
        value = value + (darkened - value) * toe_weight;
    }
    if look.shoulder > 0.0 {
        let highlight_weight = value.powi(2);
        let compressed = 1.0 - (1.0 - value).powf(1.0 / (1.0 + look.shoulder));
        value = value + (compressed - value) * highlight_weight;
    }
    clamp01(value)
}

fn multiply_matrix(matrix: [[f32; 3]; 3], rgb: [f32; 3]) -> [f32; 3] {
    [
        matrix[0][0] * rgb[0] + matrix[0][1] * rgb[1] + matrix[0][2] * rgb[2],
        matrix[1][0] * rgb[0] + matrix[1][1] * rgb[1] + matrix[1][2] * rgb[2],
        matrix[2][0] * rgb[0] + matrix[2][1] * rgb[1] + matrix[2][2] * rgb[2],
    ]
}

fn luma(rgb: [f32; 3]) -> f32 {
    rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722
}

fn hue_band_weight(hue: f32, center: f32, width: f32) -> f32 {
    let mut distance = (hue - center).abs();
    if distance > 180.0 {
        distance = 360.0 - distance;
    }
    let normalized = (1.0 - distance / width).clamp(0.0, 1.0);
    normalized * normalized * (3.0 - 2.0 * normalized)
}

fn rgb_to_hsv(rgb: [f32; 3]) -> [f32; 3] {
    let max = rgb[0].max(rgb[1]).max(rgb[2]);
    let min = rgb[0].min(rgb[1]).min(rgb[2]);
    let delta = max - min;
    let hue = if delta <= f32::EPSILON {
        0.0
    } else if max == rgb[0] {
        60.0 * (((rgb[1] - rgb[2]) / delta) % 6.0)
    } else if max == rgb[1] {
        60.0 * (((rgb[2] - rgb[0]) / delta) + 2.0)
    } else {
        60.0 * (((rgb[0] - rgb[1]) / delta) + 4.0)
    };
    [wrap_hue(hue), if max <= f32::EPSILON { 0.0 } else { delta / max }, max]
}

fn hsv_to_rgb(hsv: [f32; 3]) -> [f32; 3] {
    let hue = wrap_hue(hsv[0]);
    let saturation = clamp01(hsv[1]);
    let value = clamp01(hsv[2]);
    if saturation <= f32::EPSILON {
        return [value, value, value];
    }
    let chroma = value * saturation;
    let x = chroma * (1.0 - (((hue / 60.0) % 2.0) - 1.0).abs());
    let m = value - chroma;
    let base = match (hue / 60.0).floor() as i32 {
        0 => [chroma, x, 0.0],
        1 => [x, chroma, 0.0],
        2 => [0.0, chroma, x],
        3 => [0.0, x, chroma],
        4 => [x, 0.0, chroma],
        _ => [chroma, 0.0, x],
    };
    [base[0] + m, base[1] + m, base[2] + m]
}

fn wrap_hue(mut hue: f32) -> f32 {
    while hue < 0.0 {
        hue += 360.0;
    }
    while hue >= 360.0 {
        hue -= 360.0;
    }
    hue
}

fn clamp01(value: f32) -> f32 {
    value.clamp(0.0, 1.0)
}

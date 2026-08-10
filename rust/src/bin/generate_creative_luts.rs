use image::{DynamicImage, Rgba, RgbaImage};
use std::env;
use std::fs;
use std::path::PathBuf;

#[path = "../photon_filters.rs"]
mod photon_filters;

const LUT_SIZE: usize = 33;
const CREATIVE_FILTERS: &[&str] = &[
    "vintage",
    "oceanic",
    "lofi",
    "dramatic",
    "golden",
    "pastel_pink",
];

fn main() {
    let output_root = parse_output_root();
    fs::create_dir_all(&output_root).unwrap_or_else(|error| {
        panic!(
            "Unable to create creative LUT output directory {}: {error}",
            output_root.display()
        )
    });

    let source = build_rgb_grid();
    for filter in CREATIVE_FILTERS {
        let effected = photon_filters::apply(
            DynamicImage::ImageRgba8(source.clone()),
            filter,
            1.0,
        )
        .unwrap_or_else(|error| panic!("Unable to generate {filter} LUT: {error}"))
        .to_rgba8();

        let cube = build_cube(filter, &effected);
        let path = output_root.join(filter).join("lut.cube");
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)
                .unwrap_or_else(|error| panic!("Unable to create {}: {error}", parent.display()));
        }
        fs::write(&path, cube)
            .unwrap_or_else(|error| panic!("Unable to write {}: {error}", path.display()));
        println!("[Pixel Craft] creative LUT: {}", path.display());
    }
}

fn parse_output_root() -> PathBuf {
    let mut args = env::args().skip(1);
    let mut output = PathBuf::from("creative_luts");
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--output" => {
                output = PathBuf::from(
                    args.next()
                        .unwrap_or_else(|| panic!("--output requires a path")),
                );
            }
            unknown => panic!("Unknown argument: {unknown}"),
        }
    }
    output
}

fn build_rgb_grid() -> RgbaImage {
    let sample_count = LUT_SIZE * LUT_SIZE * LUT_SIZE;
    let mut image = RgbaImage::new(sample_count as u32, 1);
    let denominator = (LUT_SIZE - 1) as f32;
    let mut index = 0u32;

    // .cube red-fastest ordering: R changes fastest, then G, then B.
    for blue in 0..LUT_SIZE {
        for green in 0..LUT_SIZE {
            for red in 0..LUT_SIZE {
                image.put_pixel(
                    index,
                    0,
                    Rgba([
                        grid_u8(red, denominator),
                        grid_u8(green, denominator),
                        grid_u8(blue, denominator),
                        255,
                    ]),
                );
                index += 1;
            }
        }
    }
    image
}

fn grid_u8(index: usize, denominator: f32) -> u8 {
    ((index as f32 / denominator) * 255.0)
        .round()
        .clamp(0.0, 255.0) as u8
}

fn build_cube(filter: &str, image: &RgbaImage) -> String {
    let expected = LUT_SIZE * LUT_SIZE * LUT_SIZE;
    assert_eq!(image.width() as usize, expected);
    assert_eq!(image.height(), 1);

    let mut output = String::with_capacity(expected * 32);
    output.push_str(&format!("TITLE \"Pixel Craft Creative: {filter}\"\n"));
    output.push_str(&format!("LUT_3D_SIZE {LUT_SIZE}\n"));
    output.push_str("DOMAIN_MIN 0.0 0.0 0.0\n");
    output.push_str("DOMAIN_MAX 1.0 1.0 1.0\n\n");

    for pixel in image.pixels() {
        output.push_str(&format!(
            "{:.7} {:.7} {:.7}\n",
            pixel[0] as f32 / 255.0,
            pixel[1] as f32 / 255.0,
            pixel[2] as f32 / 255.0,
        ));
    }
    output
}

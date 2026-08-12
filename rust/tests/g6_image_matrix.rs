use image::{DynamicImage, ImageBuffer, ImageOutputFormat, Rgb};
use pixelcraft_engine::api;
use std::env;
use std::io::Cursor;
use std::time::Instant;

#[derive(Clone, Copy)]
struct Tier {
    label: &'static str,
    width: u32,
    height: u32,
    mp: u32,
}

fn synthetic_jpeg(tier: Tier) -> Vec<u8> {
    let image = ImageBuffer::from_fn(tier.width, tier.height, |x, y| {
        // Deterministic spatial pattern with enough variation to exercise a
        // real JPEG decode/resize without requiring committed large fixtures.
        Rgb([
            ((x * 31 + y * 7) & 0xff) as u8,
            ((x * 11 + y * 19) & 0xff) as u8,
            ((x * 3 + y * 29) & 0xff) as u8,
        ])
    });
    let mut encoded = Cursor::new(Vec::new());
    DynamicImage::ImageRgb8(image)
        .write_to(&mut encoded, ImageOutputFormat::Jpeg(90))
        .expect("encode synthetic JPEG");
    encoded.into_inner()
}

#[test]
#[ignore = "G6 characterization: opt in with cargo test --test g6_image_matrix -- --ignored --nocapture"]
fn characterize_image_size_matrix() {
    let max_mp = env::var("G6_MAX_MP")
        .ok()
        .and_then(|value| value.parse::<u32>().ok())
        .unwrap_or(12);
    let tiers = [
        Tier {
            label: "12mp",
            width: 4000,
            height: 3000,
            mp: 12,
        },
        Tier {
            label: "24mp",
            width: 6000,
            height: 4000,
            mp: 24,
        },
        Tier {
            label: "48mp",
            width: 8000,
            height: 6000,
            mp: 48,
        },
    ];

    for tier in tiers.into_iter().filter(|tier| tier.mp <= max_mp) {
        let fixture_watch = Instant::now();
        let source = synthetic_jpeg(tier);
        let fixture_ms = fixture_watch.elapsed().as_millis();

        let load_watch = Instant::now();
        let dimensions = api::load_image(source.clone()).expect("load image dimensions");
        let load_ms = load_watch.elapsed().as_millis();
        assert_eq!(dimensions, (tier.width, tier.height));

        let preview_watch = Instant::now();
        let preview = api::prepare_preview(source.clone(), 1024).expect("prepare reduced preview");
        let preview_ms = preview_watch.elapsed().as_millis();
        assert!(!preview.is_empty());

        let adjustment_watch = Instant::now();
        api::begin_filter("exposure".to_string()).expect("begin exposure");
        let draft = api::update_filter_preview("exposure".to_string(), 0.25)
            .expect("update exposure preview");
        assert!(!draft.bytes.is_empty());
        let committed = api::commit_filter().expect("commit exposure");
        assert!(!committed.is_empty());
        let adjustment_ms = adjustment_watch.elapsed().as_millis();

        let apply_watch = Instant::now();
        let checkpoint = api::apply_edits().expect("apply checkpoint");
        let apply_ms = apply_watch.elapsed().as_millis();
        assert!(!checkpoint.is_empty());

        let export_watch = Instant::now();
        let exported = api::export_image("jpeg".to_string(), 90).expect("full-resolution export");
        let export_ms = export_watch.elapsed().as_millis();
        assert!(!exported.is_empty());

        println!(
            "PIXELCRAFT_G6_IMAGE tier={} width={} height={} source_bytes={} fixture_ms={} load_ms={} preview_ms={} adjustment_ms={} apply_ms={} export_ms={} export_bytes={}",
            tier.label,
            tier.width,
            tier.height,
            source.len(),
            fixture_ms,
            load_ms,
            preview_ms,
            adjustment_ms,
            apply_ms,
            export_ms,
            exported.len(),
        );
    }
}

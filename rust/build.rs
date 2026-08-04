fn main() {
    // flutter_rust_bridge 2.12 expands #[frb(...)] using cfg(frb_expand).
    // Register it with rustc's check-cfg system so `clippy -D warnings`
    // accepts the macro-generated configuration name on modern Rust.
    println!("cargo:rustc-check-cfg=cfg(frb_expand)");
}

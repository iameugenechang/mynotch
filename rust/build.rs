fn main() {
    println!("cargo:rerun-if-changed=native/gate.m");
    println!("cargo:rerun-if-changed=native/gate.h");
    if std::env::var_os("CARGO_FEATURE_GUI").is_none() {
        return;
    }
    assert_eq!(
        std::env::var("CARGO_CFG_TARGET_OS").unwrap(),
        "macos",
        "the graphical gate is macOS-only"
    );
    cc::Build::new()
        .file("native/gate.m")
        .flag("-fobjc-arc")
        .flag("-fmodules")
        .compile("anotchup_gate_native");
    for framework in ["AppKit", "QuartzCore", "CoreVideo", "CoreGraphics"] {
        println!("cargo:rustc-link-lib=framework={framework}");
    }
}

use env_logger::Builder;

#[flutter_rust_bridge::frb(sync)] // Synchronous mode for simplicity of the demo
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Default utilities - feel free to customize

    let _ = Builder::new()
        .filter_level(log::LevelFilter::Warn)
        .filter_module("rust_lib_clutter", log::LevelFilter::Debug)
        .init();
    flutter_rust_bridge::setup_backtrace();
}

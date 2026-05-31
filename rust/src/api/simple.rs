use env_logger::Builder;

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    let _ = Builder::new()
        .filter_level(log::LevelFilter::Warn)
        .filter_module("rust_lib_clutter", log::LevelFilter::Debug)
        .try_init();
    flutter_rust_bridge::setup_backtrace();
}

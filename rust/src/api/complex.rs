#[flutter_rust_bridge::frb(sync)] // Synchronous mode for simplicity of the demo
pub fn spank(name: String) -> String {
    format!("Hello, {name}!")
}

#[derive(Debug)]
pub struct Hello {
    pub name: String,
}

pub fn print_hello(hello: &Hello) {
    println!("Hello {hello:?}!");
}

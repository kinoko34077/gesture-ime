//! Native reference output for the identical JavaScript/Wasm JSON entry point.
use gesture_ime_core_web::inspect_profile_json;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let path = std::env::args().nth(1).ok_or("provide Profile JSON path")?;
    let input = std::fs::read_to_string(path)?;
    println!("{}", inspect_profile_json(&input));
    Ok(())
}

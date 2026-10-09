//! Native reference output used to verify executed WebAssembly parity.
use gesture_ime_core_web::trace_profile_json;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let profile_path = std::env::args().nth(1).ok_or("provide Profile JSON path")?;
    let event_path = std::env::args().nth(2).ok_or("provide event JSON path")?;
    let profile = std::fs::read_to_string(profile_path)?;
    let events = std::fs::read_to_string(event_path)?;
    println!("{}", trace_profile_json(&profile, &events));
    Ok(())
}

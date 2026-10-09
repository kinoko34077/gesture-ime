//! Native reference for the exact browser Profile v3 gesture replay entry point.
use gesture_ime_core_web::trace::trace_profile_json;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args().skip(1);
    let profile_path = args.next().ok_or("provide Profile JSON path")?;
    let script_path = args.next().ok_or("provide gesture script JSON path")?;
    let profile = std::fs::read_to_string(profile_path)?;
    let script = std::fs::read_to_string(script_path)?;
    println!("{}", trace_profile_json(&profile, &script));
    Ok(())
}

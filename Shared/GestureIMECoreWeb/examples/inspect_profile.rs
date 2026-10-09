//! Native reference output for the identical JavaScript/Wasm JSON entry point.
use gesture_ime_core_web::{inspect_board_json, inspect_profile_json};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args().skip(1);
    let path = args.next().ok_or("provide Profile JSON path")?;
    let input = std::fs::read_to_string(path)?;
    let layer_id = args.next();
    let board_id = args.next();
    match (layer_id, board_id) {
        (None, None) => println!("{}", inspect_profile_json(&input)),
        (Some(layer), Some(board)) => println!("{}", inspect_board_json(&input, &layer, &board)),
        _ => return Err("provide both layerId and boardId".into()),
    }
    Ok(())
}

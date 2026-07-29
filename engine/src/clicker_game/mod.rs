//! The clicker game holds the state associated with a run — calories, weight,
//! upgrades, achievements — such that we can reload and replay a given
//! save-state file, and serialize/deserialize it to/from disk.
//!
//! Layout:
//!
//! * [`defs`]  — static content tables (food, upgrades, achievements).
//! * [`state`] — the pure simulation. No Godot types, plain `cargo test`.
//! * [`game`]  — the thin `ClickerGame` GDExtension class GDScript talks to.
//!
//! The boundary between Rust and GDScript is deliberately narrow: scalars in,
//! JSON strings out. That keeps the binding surface small and lets the UI
//! layer stay declarative.

pub const SAVE_FILE_VERSION: &str = env!("CARGO_PKG_VERSION");

pub mod defs;
pub mod game;
pub mod state;

pub use game::ClickerGame;
pub use state::{Event, Game, SaveState};

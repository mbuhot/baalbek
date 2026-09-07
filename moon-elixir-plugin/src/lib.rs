//! A moon toolchain plugin that reads each Elixir project's `mix.exs`: it
//! infers `dependsOn` from the path dependencies, and hands the third-party
//! dependency list to the project's `deps` task.

pub mod config;
pub mod deps_task;
pub mod inference;
pub mod mix;

#[cfg(feature = "wasm")]
mod tier1;
#[cfg(feature = "wasm")]
mod tier2;

#[cfg(feature = "wasm")]
pub use tier1::*;
#[cfg(feature = "wasm")]
pub use tier2::*;

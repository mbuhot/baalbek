//! A moon toolchain plugin that infers `dependsOn` between Elixir projects
//! from the path dependencies in their `mix.exs` files.

pub mod config;
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

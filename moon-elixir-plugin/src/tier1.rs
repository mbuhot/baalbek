//! Toolchain registration: what moon needs to recognize an Elixir project.

use extism_pdk::*;
use moon_config::LanguageType;
use moon_pdk_api::*;

#[plugin_fn]
pub fn register_toolchain(
    Json(_): Json<RegisterToolchainInput>,
) -> FnResult<Json<RegisterToolchainOutput>> {
    Ok(Json(RegisterToolchainOutput {
        name: "Elixir".into(),
        plugin_version: env!("CARGO_PKG_VERSION").into(),
        // moon has no Elixir language variant, and `language: elixir` in a
        // moon.yml already deserializes to this.
        language: Some(LanguageType::other("elixir")?),
        exe_names: vec!["mix".into(), "elixir".into(), "iex".into()],
        lock_file_names: vec!["mix.lock".into()],
        manifest_file_names: vec!["mix.exs".into()],
        vendor_dir_name: Some("deps".into()),
        ..Default::default()
    }))
}

#[plugin_fn]
pub fn initialize_toolchain(
    Json(_): Json<InitializeToolchainInput>,
) -> FnResult<Json<InitializeToolchainOutput>> {
    Ok(Json(InitializeToolchainOutput {
        docs_url: Some(
            "https://github.com/mbuhot/baalbek/tree/main/moon-elixir-plugin/README.md".into(),
        ),
        ..Default::default()
    }))
}

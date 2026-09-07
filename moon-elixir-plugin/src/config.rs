//! The toolchain's settings in `.moon/toolchains.yml`.

use serde::Deserialize;

#[derive(Debug, Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct ElixirToolchainConfig {
    /// Turns dependency inference off, leaving every `dependsOn` hand-written.
    pub infer_relationships: Option<bool>,
}

impl ElixirToolchainConfig {
    pub fn infer_relationships(&self) -> bool {
        self.infer_relationships.unwrap_or(true)
    }
}

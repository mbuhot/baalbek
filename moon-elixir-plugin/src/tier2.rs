//! Project-graph extension: what every `mix.exs` says about its project.

use crate::config::ElixirToolchainConfig;
use crate::deps_task::{DEPS_TASK, dependency_env};
use crate::inference::{InferredScope, ProjectSources, infer_dependencies};
use crate::mix::{READ_MANIFESTS_EXS, manifest_arg, parse_manifests};
use extism_pdk::*;
use moon_config::{DependencyScope, PartialTaskConfig};
use moon_pdk::{
    ExecCommandInput, HostLogInput, command_exists, exec, get_host_environment, host_log,
    parse_toolchain_config,
};
use moon_pdk_api::*;
use std::collections::BTreeMap;

#[host_fn]
extern "ExtismHost" {
    fn host_log(input: Json<moon_pdk::HostLogInput>);
}

#[plugin_fn]
pub fn extend_project_graph(
    Json(input): Json<ExtendProjectGraphInput>,
) -> FnResult<Json<ExtendProjectGraphOutput>> {
    let config = parse_toolchain_config::<ElixirToolchainConfig>(input.toolchain_config.clone())?;
    let mut output = ExtendProjectGraphOutput::default();

    if !config.infer_relationships() {
        return Ok(Json(output));
    }

    let mut args = vec![];

    for (id, source) in &input.project_sources {
        let mix_exs = input.context.workspace_root.join(source).join("mix.exs");

        if !mix_exs.exists() {
            continue;
        }

        args.push(manifest_arg(id, source));

        // Declared so moon invalidates the cached project graph when a
        // dependency list changes.
        output.input_files.push(mix_exs);
    }

    if args.is_empty() {
        return Ok(Json(output));
    }

    let manifests = match read_manifests(&input.context.workspace_root, args) {
        Ok(manifests) => manifests,
        Err(reason) => {
            // Every Elixir project keeps whatever `dependsOn` its moon.yml
            // declares, so the graph is ordered but not inferred. Failing the
            // call instead would fail every moon command, including the ones
            // that install Elixir or fix the manifest.
            host_log!(
                stderr,
                "elixir toolchain: cannot read mix.exs dependencies: {reason}"
            );

            return Ok(Json(output));
        }
    };

    let sources = ProjectSources::new(
        input
            .project_sources
            .iter()
            .map(|(id, source)| (id.to_string(), source.to_owned())),
    );

    for manifest in manifests {
        if let Some(error) = manifest.error {
            host_log!(
                stderr,
                "elixir toolchain: cannot infer dependsOn for {}: {}",
                manifest.id,
                error.trim()
            );

            continue;
        }

        let dependencies = infer_dependencies(&sources, &manifest.id, &manifest.deps)
            .into_iter()
            .map(|dep| {
                Ok(ProjectDependency {
                    id: Id::new(dep.id)?,
                    scope: match dep.scope {
                        InferredScope::Production => DependencyScope::Production,
                        InferredScope::Development => DependencyScope::Development,
                    },
                    via: Some(dep.via),
                })
            })
            .collect::<AnyResult<Vec<_>>>()?;

        // The task carries the list even for a project with no path deps, and
        // the dependencies exist even for one with no third-party tree, so
        // either alone is worth an entry.
        let path_deps: Vec<String> = manifest
            .path_deps
            .iter()
            .map(|dep| dep.app.clone())
            .collect();

        let tasks = BTreeMap::from([(
            Id::new(DEPS_TASK)?,
            PartialTaskConfig {
                env: Some(dependency_env(&manifest.third_party, &path_deps)),
                ..Default::default()
            },
        )]);

        output.extended_projects.insert(
            Id::new(manifest.id)?,
            ExtendProjectOutput {
                dependencies,
                tasks,
                ..Default::default()
            },
        );
    }

    Ok(Json(output))
}

/// Run one `elixir` process over every manifest. One process rather than one
/// per project, because BEAM startup dominates the cost.
fn read_manifests(
    workspace_root: &VirtualPath,
    args: Vec<String>,
) -> Result<Vec<crate::mix::ProjectManifest>, String> {
    // Probed, not attempted: the host aborts the whole guest call when asked to
    // execute a command that is not on PATH ("Command or script elixir does not
    // exist"), and an aborted call fails the project graph and therefore every
    // moon command. `command_exists` shells out to `which` (or `Get-Command`),
    // which is always present, so a missing Elixir stays recoverable.
    let env = get_host_environment().map_err(|error| format!("no host environment: {error}"))?;

    if !command_exists(env, "elixir") {
        return Err("`elixir` is not on PATH".to_owned());
    }

    let mut command_args = vec!["-e".to_owned(), READ_MANIFESTS_EXS.to_owned()];
    command_args.extend(args);

    let result = exec(ExecCommandInput::pipe("elixir", command_args).cwd(workspace_root.clone()))
        .map_err(|error| format!("`elixir` could not be run: {error}"))?;

    if result.exit_code != 0 {
        return Err(format!(
            "`elixir` exited with {}: {}",
            result.exit_code,
            result.stderr.trim()
        ));
    }

    parse_manifests(&result.stdout)
}

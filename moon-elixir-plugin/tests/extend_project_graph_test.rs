//! Drives the compiled `wasm32-wasip1` plugin through moon's plugin harness.
//!
//! Every expectation comes from `__fixtures__/projects`, never from the
//! workspace this crate happens to sit in — the plugin is publishable on its
//! own and must not assert on a sibling project's shape.
//!
//! `elixir` must be on `PATH`: the plugin asks Mix for each dependency list
//! rather than parsing `mix.exs`.

use moon_config::DependencyScope;
use moon_elixir_plugin::deps_task::{DEPS_TASK, THIRD_PARTY_ENV};
use moon_pdk_api::*;
use moon_pdk_test_utils::create_moon_sandbox;
use serde_json::json;

/// Every project in the `projects` fixture, as moon would pass them.
fn all_project_sources() -> ExtendProjectGraphInput {
    let mut input = ExtendProjectGraphInput::default();

    for id in [
        "app",
        "lib",
        "facade",
        "noisy",
        "unevaluable",
        "unlockable",
        "escaping",
        "no-mix",
    ] {
        input.project_sources.insert(Id::raw(id), id.into());
    }

    input
}

/// The third-party dependency list the plugin attached to a project, as the
/// `deps` task reads it.
fn third_party(output: &ExtendProjectGraphOutput, id: &str) -> Option<String> {
    output
        .extended_projects
        .get(&Id::raw(id))?
        .tasks
        .get(&Id::raw(DEPS_TASK))?
        .env
        .as_ref()?
        .get(THIRD_PARTY_ENV)?
        .clone()
}

fn dependency_ids(output: &ExtendProjectGraphOutput, id: &str) -> Vec<String> {
    output
        .extended_projects
        .get(&Id::raw(id))
        .map(|project| {
            project
                .dependencies
                .iter()
                .map(|dep| dep.id.to_string())
                .collect()
        })
        .unwrap_or_default()
}

#[tokio::test(flavor = "multi_thread")]
async fn infers_a_literal_path_dep_list() {
    let sandbox = create_moon_sandbox("projects");
    let plugin = sandbox.create_toolchain("elixir").await;

    let output = plugin.extend_project_graph(all_project_sources()).await;

    assert_eq!(dependency_ids(&output, "app"), ["lib", "facade"]);
    assert!(dependency_ids(&output, "lib").is_empty());

    // A project with no mix.exs is not read at all.
    assert!(!output.extended_projects.contains_key(&Id::raw("no-mix")));
}

/// Every locked dependency, transitive ones included, and no path dependency:
/// `app`'s manifest lists three of those and `mix.lock` locks none of them.
#[tokio::test(flavor = "multi_thread")]
async fn reads_the_third_party_dependency_list_out_of_the_lock() {
    let sandbox = create_moon_sandbox("projects");
    let plugin = sandbox.create_toolchain("elixir").await;

    let output = plugin.extend_project_graph(all_project_sources()).await;

    assert_eq!(
        third_party(&output, "app").as_deref(),
        Some("phoenix plug vendored")
    );

    // `nimble_parsec` is locked without appearing in the manifest.
    assert_eq!(
        third_party(&output, "lib").as_deref(),
        Some("jason nimble_parsec")
    );
}

/// A lockfile Mix cannot read is an empty map, not an error, so the project
/// keeps its inferred edges and its list is empty.
#[tokio::test(flavor = "multi_thread")]
async fn reports_an_empty_list_for_a_lock_it_cannot_read() {
    let sandbox = create_moon_sandbox("projects");
    let plugin = sandbox.create_toolchain("elixir").await;

    let output = plugin.extend_project_graph(all_project_sources()).await;

    assert_eq!(third_party(&output, "unlockable").as_deref(), Some(""));
    assert_eq!(dependency_ids(&output, "unlockable"), ["lib"]);

    // No lockfile at all reads the same way.
    assert_eq!(third_party(&output, "escaping").as_deref(), Some(""));
}

/// A manifest that raises delivers no list, which is what the consuming task
/// distinguishes from a list that is genuinely empty.
#[tokio::test(flavor = "multi_thread")]
async fn delivers_no_list_for_a_manifest_that_cannot_be_evaluated() {
    let sandbox = create_moon_sandbox("projects");
    let plugin = sandbox.create_toolchain("elixir").await;

    let output = plugin.extend_project_graph(all_project_sources()).await;

    assert_eq!(third_party(&output, "unevaluable"), None);
}

/// The reason this plugin asks Mix instead of reading the file: `facade`'s
/// dependency list is built by `File.ls` at evaluation time, and both entries
/// point inside `lib`'s source rather than at its root.
#[tokio::test(flavor = "multi_thread")]
async fn infers_a_dependency_list_that_only_exists_once_mix_evaluates_it() {
    let sandbox = create_moon_sandbox("projects");
    let plugin = sandbox.create_toolchain("elixir").await;

    let output = plugin.extend_project_graph(all_project_sources()).await;

    assert_eq!(dependency_ids(&output, "facade"), ["lib"]);
}

#[tokio::test(flavor = "multi_thread")]
async fn carries_the_scope_and_provenance_of_each_edge() {
    let sandbox = create_moon_sandbox("projects");
    let plugin = sandbox.create_toolchain("elixir").await;

    let output = plugin.extend_project_graph(all_project_sources()).await;
    let app = &output.extended_projects[&Id::raw("app")];

    assert_eq!(
        app.dependencies[0],
        ProjectDependency {
            id: Id::raw("lib"),
            scope: DependencyScope::Production,
            via: Some("mix.exs path dep :lib".into()),
        }
    );

    // `{:fixtures, path: "../lib/test/fixtures", only: [:dev, :test]}` points
    // inside `lib`, which already owns a production edge, so it is dropped
    // rather than downgrading that edge.
    assert!(app.dependencies.iter().all(|dep| dep.id != Id::raw("fixtures")));
}

/// A manifest that raises infers nothing for its own project and nothing else
/// for anyone: the other projects in the same run are unaffected.
#[tokio::test(flavor = "multi_thread")]
async fn infers_nothing_for_a_manifest_that_cannot_be_evaluated() {
    let sandbox = create_moon_sandbox("projects");
    let plugin = sandbox.create_toolchain("elixir").await;

    let output = plugin.extend_project_graph(all_project_sources()).await;

    assert!(!output.extended_projects.contains_key(&Id::raw("unevaluable")));
    assert_eq!(dependency_ids(&output, "app"), ["lib", "facade"]);
}

/// A `mix.exs` may print while Mix evaluates it, and that output need not end
/// in a newline. It must not be able to run into the result: one stray write
/// used to void the inference for every project at once.
#[tokio::test(flavor = "multi_thread")]
async fn infers_through_output_a_manifest_wrote_to_stdout() {
    let sandbox = create_moon_sandbox("projects");
    let plugin = sandbox.create_toolchain("elixir").await;

    let output = plugin.extend_project_graph(all_project_sources()).await;

    assert_eq!(dependency_ids(&output, "noisy"), ["lib"]);
    assert_eq!(dependency_ids(&output, "app"), ["lib", "facade"]);
}

/// A path dep leaving the workspace, naming an absolute path, pointing at the
/// project itself, or landing on no project at all is not an edge moon can
/// express.
#[tokio::test(flavor = "multi_thread")]
async fn infers_nothing_from_paths_that_name_no_other_project() {
    let sandbox = create_moon_sandbox("projects");
    let plugin = sandbox.create_toolchain("elixir").await;

    let output = plugin.extend_project_graph(all_project_sources()).await;

    assert!(dependency_ids(&output, "escaping").is_empty());
}

/// The `mix.exs` files the inference read, so moon invalidates its cached
/// project graph when a dependency list changes.
#[tokio::test(flavor = "multi_thread")]
async fn reports_every_mix_exs_it_read_as_an_input_file() {
    let sandbox = create_moon_sandbox("projects");
    let plugin = sandbox.create_toolchain("elixir").await;

    let output = plugin.extend_project_graph(all_project_sources()).await;
    let mut files = output
        .input_files
        .iter()
        .map(|path| path.to_string_lossy().to_string())
        .collect::<Vec<_>>();

    files.sort();

    assert_eq!(
        files,
        [
            "/workspace/app/mix.exs",
            "/workspace/escaping/mix.exs",
            "/workspace/facade/mix.exs",
            "/workspace/lib/mix.exs",
            "/workspace/noisy/mix.exs",
            "/workspace/unevaluable/mix.exs",
            "/workspace/unlockable/mix.exs",
        ]
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn infers_nothing_when_inference_is_turned_off() {
    let sandbox = create_moon_sandbox("projects");
    let plugin = sandbox.create_toolchain("elixir").await;

    let mut input = all_project_sources();
    input.toolchain_config = json!({ "inferRelationships": false });

    let output = plugin.extend_project_graph(input).await;

    assert!(output.extended_projects.is_empty());
    assert!(output.input_files.is_empty());
}

#[tokio::test(flavor = "multi_thread")]
async fn registers_as_the_elixir_toolchain() {
    let sandbox = create_moon_sandbox("projects");
    let plugin = sandbox.create_toolchain("elixir").await;

    let metadata = plugin
        .register_toolchain(RegisterToolchainInput { id: Id::raw("elixir") })
        .await;

    assert_eq!(metadata.name, "Elixir");
    assert_eq!(metadata.manifest_file_names, ["mix.exs"]);
    assert_eq!(metadata.lock_file_names, ["mix.lock"]);
    assert_eq!(
        metadata.language,
        Some(moon_config::LanguageType::other("elixir").unwrap())
    );
}

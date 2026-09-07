//! Asks Elixir for each project's dependency list, rather than parsing `mix.exs`.
//!
//! `mix.exs` is Elixir source, evaluated by Mix, so a dependency list can be
//! computed at evaluation time. One `elixir` process evaluates every project's
//! `project/0` in turn and prints the result as JSON; a project whose manifest
//! raises is reported against that project alone and infers nothing.

use serde::Deserialize;

/// Marks the start of the result on stdout. A `mix.exs` is free to print while
/// Mix evaluates it, and such output need not end in a newline, so the result
/// cannot be found by position — it is found by this marker.
pub const RESULT_MARKER: &str = "@@moon-elixir-plugin-result@@";

/// The Elixir program that reads the manifests. `System.argv()` carries one
/// `<id>=<source>` pair per project, with `source` relative to the working
/// directory, which is the workspace root.
///
/// `Mix.Project.in_project/3` evaluates the manifest the way `mix` itself
/// does, so a computed dependency list is resolved rather than reported. A
/// manifest that raises is caught per project: Mix's own error text is the
/// most useful thing to show, because it is written for the person who has to
/// fix it.
pub const READ_MANIFESTS_EXS: &str = r#"
Mix.start()

defmodule MoonElixirPlugin do
  @marker "@@moon-elixir-plugin-result@@"

  def main(specs) do
    root = File.cwd!()
    json = encode(%{"projects" => Enum.map(specs, &read(&1, root))})

    # The marker starts a line of its own, so anything a mix.exs printed while
    # being evaluated cannot run into the result.
    IO.write(["\n", @marker, json, "\n"])
  end

  # JSON ships in Elixir 1.18+, :json in OTP 27+. One of the two is present on
  # any toolchain new enough to matter, and needing neither is not worth a
  # hand-rolled encoder.
  defp encode(data) do
    cond do
      Code.ensure_loaded?(JSON) -> JSON.encode!(data)
      Code.ensure_loaded?(:json) -> IO.iodata_to_binary(:json.encode(data))
      true -> raise "no JSON encoder: this plugin needs Elixir 1.18+ or OTP 27+"
    end
  end

  defp read(spec, root) do
    [id, source] = String.split(spec, "=", parts: 2)
    dir = Path.expand(source, root)

    try do
      {deps, third_party} =
        Mix.Project.in_project(:"moon_elixir_plugin_#{id}", dir, fn _module ->
          {Mix.Project.config()[:deps] || [], third_party()}
        end)

      %{
        "id" => id,
        "error" => nil,
        "deps" => Enum.flat_map(deps, &path_dep(&1, dir, root)),
        "third_party" => third_party
      }
    rescue
      error -> failed(id, Exception.message(error))
    catch
      kind, reason -> failed(id, Exception.format(kind, reason))
    end
  end

  # Every dependency Mix resolves from a registry or a git ref, transitive ones
  # included: a `path:` dependency is never written to the lock. A lockfile Mix
  # cannot read is an empty map, which is what `Mix.Dep.Lock.read/1` returns.
  defp third_party do
    Mix.Dep.Lock.read() |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()
  end

  defp failed(id, message),
    do: %{"id" => id, "error" => message, "deps" => [], "third_party" => []}

  defp path_dep({app, opts}, dir, root) when is_list(opts), do: path_dep(app, opts, dir, root)
  defp path_dep({app, _req, opts}, dir, root) when is_list(opts), do: path_dep(app, opts, dir, root)
  defp path_dep(_entry, _dir, _root), do: []

  defp path_dep(app, opts, dir, root) do
    case Keyword.fetch(opts, :path) do
      {:ok, path} when is_binary(path) ->
        # Path.relative_to/2 returns the absolute path unchanged when it is not
        # under root, which is how a dep outside the workspace stays rejectable.
        [
          %{
            "app" => Atom.to_string(app),
            "path" => Path.relative_to(Path.expand(path, dir), root),
            "dev_only" => dev_only?(opts)
          }
        ]

      _ ->
        []
    end
  end

  defp dev_only?(opts) do
    case Keyword.fetch(opts, :only) do
      {:ok, envs} -> :prod not in List.wrap(envs)
      :error -> false
    end
  end
end

MoonElixirPlugin.main(System.argv())
"#;

/// A `path:` dependency of one project, as Elixir resolved it.
#[derive(Clone, Debug, Deserialize, PartialEq, Eq)]
pub struct PathDep {
    /// The dependency's OTP application name.
    pub app: String,
    /// Workspace-relative when the dependency is inside the workspace, and
    /// absolute when it is not.
    pub path: String,
    /// True when `only:` excludes `:prod`.
    pub dev_only: bool,
}

/// What Elixir said about one project's manifest.
#[derive(Clone, Debug, Deserialize, PartialEq, Eq)]
pub struct ProjectManifest {
    pub id: String,
    /// Mix's own message when the manifest could not be evaluated. Both lists
    /// are then empty and nothing is inferred for the project.
    pub error: Option<String>,
    pub deps: Vec<PathDep>,
    /// Every locked dependency name, sorted: the third-party tree, transitive
    /// entries included, and never a `path:` dependency.
    pub third_party: Vec<String>,
}

#[derive(Deserialize)]
struct ReadManifestsOutput {
    projects: Vec<ProjectManifest>,
}

/// Parse the Elixir program's stdout.
///
/// Everything before the last [`RESULT_MARKER`] is whatever the manifests
/// printed while Mix evaluated them, and is discarded.
pub fn parse_manifests(stdout: &str) -> Result<Vec<ProjectManifest>, String> {
    let (_, result) = stdout.rsplit_once(RESULT_MARKER).ok_or_else(|| {
        format!(
            "elixir printed no result: {}",
            tail(stdout).unwrap_or("nothing")
        )
    })?;

    let line = result.lines().next().unwrap_or_default();

    serde_json::from_str::<ReadManifestsOutput>(line)
        .map(|output| output.projects)
        .map_err(|error| format!("cannot read elixir's output ({error}): {line}"))
}

/// The end of a stream, for a diagnostic that must not paste a whole build log.
fn tail(output: &str) -> Option<&str> {
    let trimmed = output.trim();

    match trimmed.char_indices().nth_back(500) {
        Some((index, _)) => Some(&trimmed[index..]),
        None if trimmed.is_empty() => None,
        None => Some(trimmed),
    }
}

/// The `<id>=<source>` argument for one project.
pub fn manifest_arg(id: &str, source: &str) -> String {
    format!("{id}={}", if source.is_empty() { "." } else { source })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn output(json: &str) -> String {
        format!("\n{RESULT_MARKER}{json}\n")
    }

    #[test]
    fn reads_the_projects_out_of_the_marked_line() {
        let manifests = parse_manifests(&output(
            r#"{"projects":[{"id":"server","error":null,"deps":[{"app":"core","path":"core","dev_only":false}],"third_party":["jason","phoenix"]}]}"#,
        ))
        .unwrap();

        assert_eq!(
            manifests,
            vec![ProjectManifest {
                id: "server".into(),
                error: None,
                deps: vec![PathDep {
                    app: "core".into(),
                    path: "core".into(),
                    dev_only: false
                }],
                third_party: vec!["jason".into(), "phoenix".into()],
            }]
        );
    }

    /// A manifest that prints while it is evaluated must not be able to reach
    /// the result, whether or not its output ends in a newline.
    #[test]
    fn ignores_anything_a_manifest_printed_before_the_result() {
        let json = r#"{"projects":[{"id":"a","error":null,"deps":[],"third_party":[]}]}"#;

        for noise in ["compiling something\n", "no trailing newline", ""] {
            let manifests = parse_manifests(&format!("{noise}{}", output(json)))
                .unwrap_or_else(|error| panic!("noise {noise:?} broke the parse: {error}"));

            assert_eq!(manifests.len(), 1);
        }
    }

    #[test]
    fn reports_output_it_cannot_read() {
        assert!(parse_manifests("").is_err());
        assert!(parse_manifests("** (Mix.Error) boom").is_err());
        assert!(parse_manifests(&output("not json")).is_err());
    }

    #[test]
    fn names_the_workspace_root_project_as_a_dot() {
        assert_eq!(manifest_arg("root", ""), "root=.");
        assert_eq!(manifest_arg("core", "core"), "core=core");
    }
}

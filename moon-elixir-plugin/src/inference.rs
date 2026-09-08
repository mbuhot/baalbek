//! Turns a `mix.exs` path dependency into an edge between two moon projects.

use crate::mix::PathDep;
use std::collections::BTreeMap;

/// The moon dependency scope an inferred edge carries.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum InferredScope {
    Production,
    Development,
}

/// One inferred project-to-project edge.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct InferredDependency {
    /// The moon id of the depended-on project.
    pub id: String,
    pub scope: InferredScope,
    /// Provenance moon shows in `moon project` output.
    pub via: String,
}

/// Maps workspace-relative project sources back to their moon ids.
///
/// The workspace root project is excluded: it encloses every other source, so
/// keeping it would make it the fallback owner of any path that resolves
/// outside a real project.
pub struct ProjectSources {
    by_source: BTreeMap<String, String>,
}

impl ProjectSources {
    pub fn new(sources: impl IntoIterator<Item = (String, String)>) -> Self {
        Self {
            by_source: sources
                .into_iter()
                .map(|(id, source)| (normalize_source(&source), id))
                .filter(|(source, _)| !source.is_empty())
                .collect(),
        }
    }

    /// The project owning a workspace-relative directory: the project rooted
    /// exactly there, else the nearest one rooted above it.
    fn owner(&self, dir: &str) -> Option<&String> {
        let mut candidate = dir;

        loop {
            if let Some(id) = self.by_source.get(candidate) {
                return Some(id);
            }

            candidate = match candidate.rfind('/') {
                Some(index) => &candidate[..index],
                None => return None,
            };
        }
    }
}

/// Infer one project's dependencies from its `mix.exs` path deps.
///
/// A path dep resolving outside the workspace, or onto the project itself, is
/// dropped: neither is an edge moon can express.
pub fn infer_dependencies(
    sources: &ProjectSources,
    project_id: &str,
    path_deps: &[PathDep],
) -> Vec<InferredDependency> {
    let mut inferred: Vec<InferredDependency> = vec![];

    for dep in path_deps {
        let Some(dir) = inside_workspace(&dep.path) else {
            continue;
        };
        let Some(id) = sources.owner(&dir) else {
            continue;
        };

        if id == project_id || inferred.iter().any(|other| &other.id == id) {
            continue;
        }

        inferred.push(InferredDependency {
            id: id.clone(),
            scope: if dep.dev_only {
                InferredScope::Development
            } else {
                InferredScope::Production
            },
            via: format!("mix.exs path dep :{}", dep.app),
        });
    }

    inferred
}

/// A project source as a plain relative path: the workspace root is `""`.
fn normalize_source(source: &str) -> String {
    source
        .split('/')
        .filter(|segment| !segment.is_empty() && *segment != ".")
        .collect::<Vec<_>>()
        .join("/")
}

/// The workspace-relative directory a path dep names, or `None` when it is
/// outside the workspace. Elixir resolves each `path:` against the manifest's
/// own directory and reports it relative to the workspace root, so an absolute
/// path or a leading `..` is exactly the "outside" case.
fn inside_workspace(path: &str) -> Option<String> {
    if path.starts_with('/') || path.contains(':') || path.split('/').any(|part| part == "..") {
        return None;
    }

    Some(normalize_source(path))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sources() -> ProjectSources {
        ProjectSources::new([
            ("root".to_owned(), ".".to_owned()),
            ("core".to_owned(), "core".to_owned()),
            ("server".to_owned(), "server".to_owned()),
            ("timeline".to_owned(), "timeline".to_owned()),
            ("nested".to_owned(), "apps/nested".to_owned()),
        ])
    }

    fn path_dep(app: &str, path: &str) -> PathDep {
        PathDep {
            app: app.to_owned(),
            path: path.to_owned(),
            dev_only: false,
        }
    }

    fn ids(deps: &[InferredDependency]) -> Vec<&str> {
        deps.iter().map(|dep| dep.id.as_str()).collect()
    }

    #[test]
    fn resolves_a_sibling_path_dep_to_its_project() {
        let deps = infer_dependencies(&sources(), "server", &[path_dep("core", "core")]);

        assert_eq!(
            deps,
            vec![InferredDependency {
                id: "core".into(),
                scope: InferredScope::Production,
                via: "mix.exs path dep :core".into(),
            }]
        );
    }

    #[test]
    fn resolves_a_nested_project_source() {
        let deps = infer_dependencies(&sources(), "server", &[path_dep("nested", "apps/nested")]);

        assert_eq!(ids(&deps), ["nested"]);
    }

    // A Gleam or Rust project's build output sits inside that project's source,
    // so a path dep pointing at it is still an edge onto the project.
    #[test]
    fn attributes_a_path_inside_a_project_to_that_project() {
        let deps = infer_dependencies(
            &sources(),
            "timeline_facade",
            &[path_dep("timeline", "timeline/build/otp/timeline")],
        );

        assert_eq!(ids(&deps), ["timeline"]);
    }

    #[test]
    fn drops_a_path_dep_that_matches_no_project() {
        let deps = infer_dependencies(&sources(), "server", &[path_dep("vendored", "vendor/v")]);

        assert_eq!(ids(&deps), [] as [&str; 0]);
    }

    // The root project's source encloses every path, so it must never be the
    // fallback owner of one.
    #[test]
    fn never_resolves_to_the_workspace_root_project() {
        let deps = infer_dependencies(&sources(), "core", &[path_dep("weird", ".")]);

        assert_eq!(ids(&deps), [] as [&str; 0]);
    }

    #[test]
    fn drops_a_self_edge_and_a_duplicate() {
        let deps = infer_dependencies(
            &sources(),
            "core",
            &[
                path_dep("core", "core"),
                path_dep("server", "server"),
                path_dep("server_again", "server"),
            ],
        );

        assert_eq!(ids(&deps), ["server"]);
    }

    #[test]
    fn drops_a_path_dep_outside_the_workspace() {
        let deps = infer_dependencies(
            &sources(),
            "core",
            &[
                path_dep("above", "../elsewhere"),
                path_dep("absolute", "/opt/elsewhere"),
            ],
        );

        assert_eq!(ids(&deps), [] as [&str; 0]);
    }

    #[test]
    fn carries_the_development_scope_of_a_test_only_path_dep() {
        let deps = infer_dependencies(
            &sources(),
            "server",
            &[PathDep {
                app: "core".into(),
                path: "core".into(),
                dev_only: true,
            }],
        );

        assert_eq!(deps[0].scope, InferredScope::Development);
    }
}

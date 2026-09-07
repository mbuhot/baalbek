//! How a project's third-party dependency list reaches its `deps` task.

use moon_config::EnvMap;

/// The task the list is attached to: one that does nothing, and exists to be
/// read with `extends`.
///
/// A task the consuming project's own `moon.yml` declares replaces the
/// plugin's version of it, so the list travels on a task nothing else
/// declares. See
/// `spec/decisions/adr-0003-the-plugin-hands-over-the-third-party-dependency-list.md`.
pub const DEPS_TASK: &str = "deps-list";

/// The environment variable carrying the locked third-party names.
///
/// Environment rather than arguments, because inherited arguments are appended
/// ahead of the project's own. It reaches the task's hash either way.
pub const THIRD_PARTY_ENV: &str = "MIX_THIRD_PARTY_DEPS";

/// One project's third-party dependency list, as task environment.
///
/// Space-separated: the consumer passes it to `mix deps.compile` as a word
/// list, and a dependency name needs no quoting.
pub fn dependency_env(third_party: &[String]) -> EnvMap {
    EnvMap::from_iter([(THIRD_PARTY_ENV.to_owned(), Some(third_party.join(" ")))])
}

#[cfg(test)]
mod tests {
    use super::*;

    fn names(list: &[&str]) -> Vec<String> {
        list.iter().map(|name| name.to_string()).collect()
    }

    #[test]
    fn joins_the_list_into_one_word_list() {
        let env = dependency_env(&names(&["ash", "jason"]));

        assert_eq!(env[THIRD_PARTY_ENV], Some("ash jason".to_owned()));
    }

    /// The variable is set even when the list is empty, so the task can tell
    /// an empty list apart from one the plugin never delivered.
    #[test]
    fn sets_an_empty_value_for_a_list_with_no_entries() {
        let env = dependency_env(&[]);

        assert_eq!(env[THIRD_PARTY_ENV], Some(String::new()));
    }
}

//! Reading how a service wires its inbox prefix (XR-021 CONTRACTS R3-01), shared by `bus_acl.rs`. A text scan of tracked `.rs` files: the limitation is stated where the tests use it.
//!
//! Limitation, stated plainly. A call counts when `custom_inbox_prefix(` is followed by the prefix literal or by the name of a `const NAME: &str = "<prefix>"` declared in the same crate (the nearest tracked `Cargo.toml` above the file); test files do not count, because a test that sets the prefix proves nothing about the service. The scan cannot see a prefix assembled at run time, and it does not know whether the call sits on the connection the service really opens: it proves the literal and the call exist together, and the real-broker tests of each service (R3-01 rule 4) prove the connection.
//!
//! Real matches at the round 3 pins (identity: file that declares the constant, all passed to `custom_inbox_prefix(`): TELEGRAM: `services/dispatcher/src/notifications.rs`; CHATGPT: `crates/chatgpt-archive/src/receipt/outbox.rs`; CLAUDE: `crates/claude-archive/src/operation_outbox.rs`; X: `services/x/src/bus.rs`; INSTAGRAM: `services/instagram-archive/src/nats_transport.rs`; THREADS: `crates/threads-archive/src/nats.rs`; EXTRACTOR: `crates/eventing/src/topology.rs` (called from `outbox.rs`, same crate); `EXTRACTOR_BROWSER_WORKER`: `services/browser-worker/src/lib.rs`; KNOWLEDGE: `services/knowledge/src/bus.rs`; GITHUB: `services/catalog/src/bus.rs`; VAULT: `services/vault/src/policy_bus/connection.rs`; `CHANNEL_DIGESTS`: `src/bus.rs`. Both extractor identities use a constant named `INBOX_PREFIX`, which is why the call must be in the declaring crate: a call in the browser worker must not satisfy the extractor.

use crate::checkout::{committed_manifest, require_checkout, tracked_files};

/// Sources of one repository: tracked `.rs` files and the directories of tracked `Cargo.toml`s.
pub(crate) struct Sources {
    pub(crate) rust: Vec<(String, String)>,
    pub(crate) crate_dirs: Vec<String>,
}

pub(crate) fn sources_of(repository: &str) -> Sources {
    let manifest = committed_manifest();
    let root = require_checkout(&manifest, repository);
    let crate_dirs = tracked_files(&root, "Cargo.toml")
        .into_iter()
        .map(|(path, _)| {
            path.strip_suffix("Cargo.toml")
                .unwrap_or_default()
                .to_owned()
        })
        .collect();
    Sources {
        rust: tracked_files(&root, "*.rs"),
        crate_dirs,
    }
}

fn is_test_path(path: &str) -> bool {
    path.starts_with("tests/") || path.contains("/tests/") || path.ends_with("/tests.rs")
}

/// The directory of the crate a file belongs to: the longest tracked `Cargo.toml` directory above it.
fn crate_dir_of<'a>(path: &str, crate_dirs: &'a [String]) -> Option<&'a str> {
    crate_dirs
        .iter()
        .filter(|dir| path.starts_with(dir.as_str()))
        .max_by_key(|dir| dir.len())
        .map(String::as_str)
}

/// The argument text of every `custom_inbox_prefix(...)` call in a source, up to the first `)`.
fn inbox_call_arguments(text: &str) -> Vec<String> {
    text.match_indices("custom_inbox_prefix(")
        .filter_map(|(at, marker)| {
            let rest = text.get(at + marker.len()..)?;
            let (arguments, _) = rest.split_once(')')?;
            Some(arguments.trim().trim_start_matches('&').trim().to_owned())
        })
        .collect()
}

/// `(name, value)` of every `const NAME: &str = "value";` in a source.
fn string_constants(text: &str) -> Vec<(String, String)> {
    text.match_indices("const ")
        .filter_map(|(at, marker)| {
            let rest = text.get(at + marker.len()..)?;
            let name = rest
                .chars()
                .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
                .collect::<String>();
            let after_name = rest.get(name.len()..)?.trim_start().strip_prefix(':')?;
            let (declared_type, value) = after_name.split_once('=')?;
            if !declared_type.contains("str") {
                return None;
            }
            let value = value.trim_start().strip_prefix('"')?;
            let (value, _) = value.split_once('"')?;
            Some((name, value.to_owned()))
        })
        .collect()
}

/// Why `sources` do not hand `prefix` to `custom_inbox_prefix(`, or `None` when they do.
///
/// Accepted wirings, in non-test files only: the literal itself as the argument, or a
/// `const NAME: &str = "<prefix>"` whose NAME is the argument of a call in the same crate.
pub(crate) fn inbox_wiring_problem(sources: &Sources, prefix: &str) -> Option<String> {
    let literal = format!("\"{prefix}\"");
    let production = sources
        .rust
        .iter()
        .filter(|(path, _)| !is_test_path(path))
        .collect::<Vec<_>>();
    let calls_with = |name: &str, scope: Option<&str>| {
        production.iter().any(|(path, text)| {
            let in_scope =
                scope.is_none_or(|dir| crate_dir_of(path, &sources.crate_dirs) == Some(dir));
            in_scope
                && inbox_call_arguments(text)
                    .iter()
                    .any(|argument| argument == name)
        })
    };
    if calls_with(&literal, None) {
        return None;
    }
    let mut declared = false;
    for (path, text) in &production {
        for (name, value) in string_constants(text) {
            if value != prefix {
                continue;
            }
            declared = true;
            let scope = crate_dir_of(path, &sources.crate_dirs);
            if calls_with(&name, scope) {
                return None;
            }
        }
    }
    Some(if declared {
        format!(
            "`{prefix}` is declared as a constant but no `custom_inbox_prefix(` call in its crate uses it"
        )
    } else {
        format!("no non-test source declares `{prefix}` or passes it to `custom_inbox_prefix(`")
    })
}

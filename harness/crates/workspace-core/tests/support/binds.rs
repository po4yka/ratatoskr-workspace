//! Reading the listener binds that deploy examples document, shared by the tests that compare them
//! with the port table (`port_allocation.rs`) and with Edge's route table (`edge_upstreams.rs`).

use std::fs;
use std::path::{Path, PathBuf};

/// Bind keys end in one of these.
pub(crate) const BIND_SUFFIXES: [&str; 3] = ["__BIND", "__LISTEN_ADDRESS", "__LISTENER"];

/// The example files of a repository: `.env.example` and every `*.example` under `deploy/`.
pub(crate) fn example_files(root: &Path) -> Vec<PathBuf> {
    let mut files = Vec::new();
    let env_example = root.join(".env.example");
    if env_example.is_file() {
        files.push(env_example);
    }
    let mut pending = vec![root.join("deploy")];
    while let Some(directory) = pending.pop() {
        let Ok(entries) = fs::read_dir(&directory) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().into_owned();
            if path.is_dir() {
                if name != "target" && name != "node_modules" && name != ".git" {
                    pending.push(path);
                }
            } else if name.ends_with(".example") {
                files.push(path);
            }
        }
    }
    files.sort();
    files
}

/// `Some((key, port))` when the line is a bind, documented or commented out.
pub(crate) fn bind_of(line: &str) -> Option<(String, u16)> {
    let statement = line.trim().trim_start_matches('#').trim_start();
    if !statement.starts_with("RATATOSKR__") {
        return None;
    }
    let (key, value) = statement.split_once('=')?;
    let key = key.trim();
    if !BIND_SUFFIXES.iter().any(|suffix| key.ends_with(suffix)) {
        return None;
    }
    let value = value.trim().trim_matches('"');
    let (host, port) = value.rsplit_once(':')?;
    if host.is_empty() {
        return None;
    }
    Some((key.to_owned(), port.trim().parse::<u16>().ok()?))
}

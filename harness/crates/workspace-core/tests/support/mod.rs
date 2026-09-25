pub(crate) const REPOSITORY_IDS: [&str; 16] = [
    "browser-extension",
    "chatgpt",
    "claude",
    "contracts",
    "export-agent",
    "extractor",
    "github",
    "instagram",
    "knowledge",
    "mobile",
    "platform",
    "telegram",
    "threads",
    "vault",
    "web",
    "x",
];

pub(crate) fn complete_manifest() -> String {
    let mut source = String::from("format_version = 1\n");
    for id in REPOSITORY_IDS {
        source.push_str(&repository(id));
    }
    source
}

pub(crate) fn repository(id: &str) -> String {
    repository_with_dependencies(id, &[])
}

pub(crate) fn repository_with_digest_inputs(id: &str, digest_inputs: &[&str]) -> String {
    let mut repository = repository(id);
    let values = digest_inputs
        .iter()
        .map(|path| format!("\"{path}\""))
        .collect::<Vec<_>>()
        .join(", ");
    repository = repository.replace("digest_inputs = []", &format!("digest_inputs = [{values}]"));
    repository
}

pub(crate) fn repository_with_dependencies(
    id: &str,
    dependencies: &[(&str, &str, &str)],
) -> String {
    let dependencies = dependencies
        .iter()
        .map(|(repository, kind, purpose)| {
            format!(
                "{{ repository = \"{repository}\", kind = \"{kind}\", purpose = \"{purpose}\" }}"
            )
        })
        .collect::<Vec<_>>()
        .join(", ");

    format!(
        r#"
[[repositories]]
id = "{id}"
path = "repos/{id}"
remote = "https://github.com/po4yka/ratatoskr-{id}.git"
default_branch = "main"
kind = "service"
owner = "po4yka"
security = "private-data"
commands = ["check"]
contracts = []
profiles = []
digest_inputs = []
dependencies = [{dependencies}]
"#
    )
}

pub(crate) struct GitWorkspace {
    root: PathBuf,
    commits: BTreeMap<String, String>,
}

#[derive(Debug, Eq, PartialEq)]
pub(crate) struct ChildObservation {
    pub(crate) head: String,
    pub(crate) status: String,
    pub(crate) refs: String,
    pub(crate) readme: Vec<u8>,
    pub(crate) untracked: Option<Vec<u8>>,
}

impl GitWorkspace {
    pub(crate) fn new() -> Self {
        let sequence = NEXT_FIXTURE.fetch_add(1, Ordering::Relaxed);
        let root = std::env::temp_dir().join(format!(
            "ratatoskr-workspace-git-fixture-{}-{sequence}",
            std::process::id()
        ));
        fs::create_dir_all(&root).expect("create temporary Git workspace");
        git(&root, &["init", "--quiet"]);
        configure_identity(&root);

        let mut commits = BTreeMap::new();
        let mut gitmodules = String::new();
        for id in REPOSITORY_IDS {
            let path = format!("repos/{id}");
            let child = root.join(&path);
            fs::create_dir_all(&child).expect("create child repository directory");
            git(&child, &["init", "--quiet"]);
            configure_identity(&child);
            fs::write(child.join("README.md"), format!("# {id}\n")).expect("write child fixture");
            git(&child, &["add", "README.md"]);
            git(&child, &["commit", "--quiet", "-m", "fixture"]);
            git(
                &child,
                &[
                    "remote",
                    "add",
                    "origin",
                    &format!("https://github.com/po4yka/ratatoskr-{id}.git"),
                ],
            );
            let commit = git_output(&child, &["rev-parse", "HEAD"]);
            commits.insert(id.to_owned(), commit);
            write!(
                gitmodules,
                "[submodule \"{id}\"]\n\tpath = {path}\n\turl = https://github.com/po4yka/ratatoskr-{id}.git\n"
            )
            .expect("render .gitmodules fixture");
        }

        fs::write(root.join(".gitmodules"), gitmodules).expect("write .gitmodules fixture");
        git(&root, &["add", ".gitmodules"]);
        for (id, commit) in &commits {
            git(
                &root,
                &[
                    "update-index",
                    "--add",
                    "--cacheinfo",
                    "160000",
                    commit,
                    &format!("repos/{id}"),
                ],
            );
        }

        Self { root, commits }
    }

    pub(crate) fn root(&self) -> &Path {
        &self.root
    }

    pub(crate) fn commit(&self, id: &str) -> &str {
        self.commits
            .get(id)
            .map(String::as_str)
            .expect("fixture repository commit")
    }

    pub(crate) fn set_gitmodule(&self, id: &str, path: &str, remote: &str) {
        git(
            &self.root,
            &[
                "config",
                "-f",
                ".gitmodules",
                &format!("submodule.{id}.path"),
                path,
            ],
        );
        git(
            &self.root,
            &[
                "config",
                "-f",
                ".gitmodules",
                &format!("submodule.{id}.url"),
                remote,
            ],
        );
    }

    pub(crate) fn replace_gitlink_with_regular_mode(&self, id: &str) {
        let blob = git_output(&self.root, &["hash-object", "-w", ".gitmodules"]);
        git(
            &self.root,
            &[
                "update-index",
                "--cacheinfo",
                "100644",
                &blob,
                &format!("repos/{id}"),
            ],
        );
    }

    pub(crate) fn make_uninitialized(&self, id: &str) {
        fs::remove_dir_all(self.root.join(format!("repos/{id}")))
            .expect("remove temporary child materialization");
    }

    pub(crate) fn advance_head(&self, id: &str) {
        let child = self.root.join(format!("repos/{id}"));
        fs::write(child.join("SECOND.md"), "second commit\n").expect("write second commit file");
        git(&child, &["add", "SECOND.md"]);
        git(&child, &["commit", "--quiet", "-m", "advance fixture"]);
    }

    pub(crate) fn dirty_child(&self, id: &str) {
        let child = self.root.join(format!("repos/{id}"));
        fs::write(child.join("README.md"), "tracked modification\n")
            .expect("write tracked modification");
        fs::write(child.join("UNTRACKED.md"), "untracked modification\n")
            .expect("write untracked modification");
    }

    pub(crate) fn observe_child(&self, id: &str) -> ChildObservation {
        let child = self.root.join(format!("repos/{id}"));
        ChildObservation {
            head: git_output(&child, &["rev-parse", "HEAD"]),
            status: git_output(
                &child,
                &["status", "--porcelain=v1", "--untracked-files=all"],
            ),
            refs: git_output(&child, &["show-ref"]),
            readme: fs::read(child.join("README.md")).expect("read tracked fixture"),
            untracked: fs::read(child.join("UNTRACKED.md")).ok(),
        }
    }

    pub(crate) fn add_files_and_repin(&mut self, id: &str, files: &[(&str, &[u8])]) {
        let child = self.root.join(format!("repos/{id}"));
        for (path, bytes) in files {
            let target = child.join(path);
            if let Some(parent) = target.parent() {
                fs::create_dir_all(parent).expect("create digest fixture parent");
            }
            fs::write(target, bytes).expect("write digest fixture file");
        }
        git(&child, &["add", "--all"]);
        self.commit_and_repin(id, "digest fixture");
    }

    pub(crate) fn add_symlink_and_repin(&mut self, id: &str, path: &str, target: &str) {
        use std::os::unix::fs::symlink;

        let child = self.root.join(format!("repos/{id}"));
        let link = child.join(path);
        if let Some(parent) = link.parent() {
            fs::create_dir_all(parent).expect("create symlink fixture parent");
        }
        symlink(target, link).expect("create symlink fixture");
        git(&child, &["add", "--all"]);
        self.commit_and_repin(id, "symlink fixture");
    }

    fn commit_and_repin(&mut self, id: &str, message: &str) {
        let child = self.root.join(format!("repos/{id}"));
        git(&child, &["commit", "--quiet", "-m", message]);
        let commit = git_output(&child, &["rev-parse", "HEAD"]);
        self.commits.insert(id.to_owned(), commit.clone());
        git(
            &self.root,
            &[
                "update-index",
                "--cacheinfo",
                "160000",
                &commit,
                &format!("repos/{id}"),
            ],
        );
    }
}

impl Drop for GitWorkspace {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

fn configure_identity(repository: &Path) {
    git(
        repository,
        &["config", "user.email", "fixture@example.invalid"],
    );
    git(repository, &["config", "user.name", "Fixture"]);
}

fn git(repository: &Path, arguments: &[&str]) {
    let output = Command::new("git")
        .args(arguments)
        .current_dir(repository)
        .env("GIT_AUTHOR_DATE", "2000-01-01T00:00:00Z")
        .env("GIT_COMMITTER_DATE", "2000-01-01T00:00:00Z")
        .output()
        .expect("run Git fixture command");
    assert!(
        output.status.success(),
        "git {arguments:?} failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
}

fn git_output(repository: &Path, arguments: &[&str]) -> String {
    let output = Command::new("git")
        .args(arguments)
        .current_dir(repository)
        .env("GIT_AUTHOR_DATE", "2000-01-01T00:00:00Z")
        .env("GIT_COMMITTER_DATE", "2000-01-01T00:00:00Z")
        .output()
        .expect("run Git fixture command");
    assert!(
        output.status.success(),
        "git {arguments:?} failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8(output.stdout)
        .expect("Git fixture output is UTF-8")
        .trim()
        .to_owned()
}
use std::collections::BTreeMap;
use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT_FIXTURE: AtomicU64 = AtomicU64::new(1);

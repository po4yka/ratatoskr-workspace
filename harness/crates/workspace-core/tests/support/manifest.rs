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

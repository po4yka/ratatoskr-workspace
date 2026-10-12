//! One current schema definition (XR-021 CONTRACTS R4-10): while the development status holds there are no migrations, so a `schema.sql` states each table once and a schema change edits that statement in place. An `ALTER TABLE ... ADD COLUMN` after the `CREATE TABLE` is a migration written as a repeatable statement, and it hides a column that the table definition does not show.
//!
//! The check reads every tracked `schema.sql` of every pinned repository, removes `--` comments, and reports each `ALTER TABLE` statement that adds a column, with the file and the line of the statement. A statement that adds a constraint (`ADD CONSTRAINT`, `ADD FOREIGN KEY` and the other constraint forms) is allowed, whether it stands alone or sits inside a `DO $$ ... $$` block: that is how a foreign key that closes a cycle between two tables is written when neither table can name the other first.
//!
//! Limitation, stated plainly. This is a text scan. A statement is the text from `alter table` to the next semicolon, an added column is the word `add` followed by anything other than a constraint keyword, and a semicolon inside a string literal or a dollar-quoted body would cut a statement short. The scan cannot see SQL that is assembled by an application at start-up, and it says nothing about a column that a service adds with `ALTER` in Rust code.
//!
//! Sanity run of the extraction on a real sample. Against the round 3 pin of the `chatgpt` repository (`d994f8b`, `schema.sql`) the scan reports seven statements: the lines of `alter table chatgpt_archive.import_runs add column if not exists parser_name`, four statements on `outbox_events` (`deduplication_key`, `tenant_id`, `export_id`, `undeliverable_at`) and two on `inbox_events` (`tenant_id`, `export_id`). Against the same round 3 pins, X (three `ADD CONSTRAINT` statements inside `DO` blocks), Instagram (`media_current_revision_id_fkey`) and Vault (`restore_drills_replica_target_fk`) hold `alter table` statements and none is reported.

#![allow(dead_code, clippy::expect_used, clippy::panic)]

#[path = "support/checkout.rs"]
mod checkout;

use checkout::{committed_manifest, require_checkout, tracked_files};
use std::path::Path;

/// The words that follow `add` when the clause adds a constraint, not a column.
const CONSTRAINT_WORDS: [&str; 6] = [
    "constraint",
    "foreign",
    "primary",
    "unique",
    "check",
    "exclude",
];

/// `sql` with every `--` comment removed, newlines kept so that line numbers survive.
fn without_comments(sql: &str) -> String {
    sql.lines()
        .map(|line| line.split_once("--").map_or(line, |(code, _)| code))
        .collect::<Vec<_>>()
        .join("\n")
}

/// Whether one `alter table` statement (lowercase, whitespace collapsed) adds a column.
fn adds_a_column(statement: &str) -> bool {
    let words = statement.split_whitespace().collect::<Vec<_>>();
    words.iter().enumerate().any(|(at, word)| {
        *word == "add"
            && words
                .get(at + 1)
                .is_none_or(|next| !CONSTRAINT_WORDS.contains(next))
    })
}

/// The 1-based line of every `alter table` statement in `sql` that adds a column.
fn column_additions(sql: &str) -> Vec<usize> {
    let code = without_comments(sql).to_lowercase();
    let mut lines = Vec::new();
    for (start, _) in code.match_indices("alter table") {
        let rest = code.get(start..).unwrap_or_default();
        let statement = rest.split(';').next().unwrap_or_default();
        if adds_a_column(statement) {
            let before = code.get(..start).unwrap_or_default();
            lines.push(before.matches('\n').count() + 1);
        }
    }
    lines
}

/// One finding per column addition of every `schema.sql` of a checkout, as `path:line`.
fn findings_of(checkout: &Path) -> Vec<String> {
    tracked_files(checkout, ":(glob)**/schema.sql")
        .into_iter()
        .flat_map(|(path, sql)| {
            column_additions(&sql)
                .into_iter()
                .map(move |line| format!("{path}:{line}"))
        })
        .collect()
}

/// Findings for every repository of the manifest, as `repository/path:line`.
fn fleet_findings() -> Vec<String> {
    let manifest = committed_manifest();
    manifest
        .repositories()
        .iter()
        .flat_map(|repository| {
            let root = require_checkout(&manifest, &repository.id);
            findings_of(&root)
                .into_iter()
                .map(|finding| format!("{}/{finding}", repository.id))
        })
        .collect()
}

#[test]
fn no_schema_adds_a_column_after_creating_a_table() {
    let findings = fleet_findings();
    assert!(
        findings.is_empty(),
        "a schema.sql adds a column with ALTER TABLE; edit the CREATE TABLE statement in place \
         (development status: one current definition, no migrations):\n{}",
        findings.join("\n")
    );
}

#[test]
fn the_constraint_additions_that_close_a_foreign_key_cycle_are_allowed() {
    let manifest = committed_manifest();
    for id in ["x", "instagram", "vault"] {
        let root = require_checkout(&manifest, id);
        let schemas = tracked_files(&root, ":(glob)**/schema.sql");
        assert!(
            schemas
                .iter()
                .any(|(_, sql)| without_comments(sql).to_lowercase().contains("alter table")),
            "`{id}` no longer holds an ALTER TABLE statement, so this test proves nothing; \
             name another repository that closes a foreign key cycle"
        );
        assert!(
            findings_of(&root).is_empty(),
            "`{id}`: {:?}",
            findings_of(&root)
        );
    }
}

#[test]
fn the_scan_reports_a_column_addition_and_ignores_constraints_and_comments() {
    let sql = "\
create table t (id uuid primary key);
-- alter table t add column ignored text;
alter table t
    add column if not exists a text;
alter table t add b text;
alter table t add constraint t_fk foreign key (id) references u (id);
do $$ begin
    alter table t add constraint t_chk check (id is not null);
end $$;
alter table t add column c text, add column d text;
";
    assert_eq!(column_additions(sql), vec![3, 5, 10]);
}

#[test]
fn a_column_appended_to_a_real_schema_is_reported() {
    let manifest = committed_manifest();
    let root = require_checkout(&manifest, "knowledge");
    let (path, sql) = tracked_files(&root, ":(glob)**/schema.sql")
        .into_iter()
        .next()
        .expect("knowledge tracks a schema.sql");
    assert!(
        column_additions(&sql).is_empty(),
        "the unmodified {path} must pass before the mutation means anything"
    );
    let mutated = format!("{sql}\nalter table knowledge.documents add column extra text;\n");
    let lines = column_additions(&mutated);
    assert_eq!(lines.len(), 1, "{lines:?}");
    assert_eq!(lines.first().copied(), Some(sql.matches('\n').count() + 2));
}

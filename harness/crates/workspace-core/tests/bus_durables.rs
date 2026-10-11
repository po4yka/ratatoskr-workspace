//! Durable agreement: the fixed consumers Edge provisions (XR-021 CONTRACTS S04) are named and
//! filtered in two places that nothing compiles together, Platform's table in
//! `crates/eventing/src/stream.rs` and the owning service, which hard-codes the same name and
//! filter and verifies them at startup. A rename on one side only leaves the service refusing to
//! start (or a durable nobody reads), so the harness reads both.
//!
//! Limitation, stated plainly. This is a text scan. A row counts as present in Platform's table
//! when the quoted durable name is followed, after a comma, by the quoted filter (the
//! `FixedConsumerSpec::standard(stream, "name", "filter")` form) or by `filter_subject: "filter"`
//! (the struct form). A service counts as agreeing when its tracked `.rs` files contain the name
//! and the filter each as a quoted string literal somewhere. The scan cannot see a literal that is
//! assembled at run time (`format!`, `concat!`, a constant imported from another crate), cannot
//! tell which file uses the literal, and says nothing about ack wait, `max_deliver` or the stream
//! (the services verify those at startup and the native smoke reads them from `jsz`). The mutation
//! test at the bottom proves that the scan reports a renamed durable.
//!
//! Real matches at the round 2 pins are recorded in the changeset `XR-021-fleet-cross-repo-fixes`.

#![allow(dead_code, clippy::expect_used, clippy::panic)]

#[path = "support/checkout.rs"]
mod checkout;

use checkout::{committed_manifest, require_checkout};
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;
use std::process::Command;

/// One durable: its name, filter and the repository whose source must name them.
#[derive(Debug, Clone, Copy)]
struct Durable {
    name: &'static str,
    filter: &'static str,
    owner: &'static str,
    /// Whether the owner's source must contain the durable name. The AI-archive projections are
    /// created and read by Edge; their owners only publish to the filtered subject.
    owner_holds_name: bool,
    /// Whether Platform lists the durable as a `name, filter` row. The Telegram notification
    /// durable is declared through two named constants instead, so for it the scan asks for the
    /// two literals separately.
    platform_row: bool,
}

const fn durable(name: &'static str, filter: &'static str, owner: &'static str) -> Durable {
    Durable {
        name,
        filter,
        owner,
        owner_holds_name: true,
        platform_row: true,
    }
}

/// The 18 service-owned entries of CONTRACTS S04 (`DOMAIN_CONSUMERS`).
const DOMAIN: [Durable; 18] = [
    durable(
        "ratatoskr_extractor_capture",
        "cmd.content.capture.requested.v1",
        "extractor",
    ),
    durable(
        "ratatoskr_browser_worker",
        "cmd.content.render.requested.v1",
        "extractor",
    ),
    durable(
        "ratatoskr_knowledge_channel_recap",
        "cmd.knowledge.channel_digest_recap.requested.v1",
        "knowledge",
    ),
    durable(
        "ratatoskr_channel_digest_subscriptions",
        "cmd.channel_digest.subscription.set_requested.v1",
        "channel-digests",
    ),
    durable(
        "ratatoskr_channel_digest_runs",
        "cmd.channel_digest.run.requested.v1",
        "channel-digests",
    ),
    durable(
        "ratatoskr_channel_digest_schedule_occurrences",
        "cmd.channel_digest.schedule.occurrence_requested.v1",
        "channel-digests",
    ),
    durable(
        "ratatoskr_vault_backup_policy",
        "cmd.vault.backup_policy.apply_requested.v1",
        "vault",
    ),
    durable(
        "ratatoskr_knowledge_documents",
        "evt.content.document.extracted.v1",
        "knowledge",
    ),
    durable(
        "ratatoskr_knowledge_social_sources",
        "evt.social.source.>",
        "knowledge",
    ),
    durable(
        "ratatoskr_knowledge_ai_archive",
        "evt.ai_archive.>",
        "knowledge",
    ),
    durable(
        "ratatoskr_knowledge_repository_requests",
        "evt.knowledge.repository_analysis.requested.v1",
        "knowledge",
    ),
    durable(
        "ratatoskr_github_analysis_completed",
        "evt.knowledge.repository_analysis.completed.v1",
        "github",
    ),
    durable(
        "ratatoskr_github_analysis_failed",
        "evt.knowledge.repository_analysis.failed.v1",
        "github",
    ),
    durable(
        "ratatoskr_github_policy_acknowledged",
        "evt.vault.backup_policy.acknowledged.v1",
        "github",
    ),
    durable(
        "ratatoskr_x_extractor_reports",
        "evt.platform.operation.reported.v1",
        "x",
    ),
    durable(
        "ratatoskr_channel_digest_recap_completed",
        "evt.knowledge.channel_digest_recap.completed.v1",
        "channel-digests",
    ),
    durable(
        "ratatoskr_channel_digest_recap_failed",
        "evt.knowledge.channel_digest_recap.failed.v1",
        "channel-digests",
    ),
    durable(
        "ratatoskr_extractor_render_awaits",
        "evt.content.render.>",
        "extractor",
    ),
];

/// The durables that existed before S04, listed separately with their owners: the three social
/// capture consumers, the Telegram notification consumer and the two AI-archive projections.
const OTHER: [Durable; 6] = [
    durable(
        "ratatoskr_x_browser_capture",
        "cmd.x.capture.requested.v1",
        "x",
    ),
    durable(
        "ratatoskr_instagram_browser_capture",
        "cmd.instagram.capture.requested.v1",
        "instagram",
    ),
    durable(
        "threads_browser_capture",
        "cmd.threads.capture.requested.v1",
        "threads",
    ),
    Durable {
        platform_row: false,
        ..durable(
            "ratatoskr_telegram_notifications",
            "evt.platform.notification.raised.v1",
            "telegram",
        )
    },
    Durable {
        name: "platform_ai_archive_chatgpt_projection",
        filter: "evt.ai-archive.chatgpt.operation.reported.v1",
        owner: "chatgpt",
        owner_holds_name: false,
        platform_row: true,
    },
    Durable {
        name: "platform_ai_archive_claude_projection",
        filter: "evt.ai-archive.claude.operation.reported.v1",
        owner: "claude",
        owner_holds_name: false,
        platform_row: true,
    },
];

/// Consumers that only Platform creates, outside the table: Edge's own projection and the schedule
/// registration consumer that `consumer::run` creates. They are scanned in Platform's sources by
/// name only.
const PLATFORM_ONLY: [&str; 2] = ["platform_edge_projection", "platform_schedule_registration"];

const PLATFORM_TABLE: &str = "crates/eventing/src/stream.rs";

/// Whether `source` holds a table row with this durable name followed by this filter.
fn table_has_row(source: &str, name: &str, filter: &str) -> bool {
    let quoted_name = format!("\"{name}\"");
    let quoted_filter = format!("\"{filter}\"");
    source.match_indices(&quoted_name).any(|(at, _)| {
        let Some(rest) = source.get(at + quoted_name.len()..) else {
            return false;
        };
        let rest = rest.trim_start();
        let Some(rest) = rest.strip_prefix(',') else {
            return false;
        };
        let rest = rest.trim_start();
        let rest = rest
            .strip_prefix("filter_subject:")
            .map_or(rest, str::trim_start);
        rest.starts_with(&quoted_filter)
    })
}

/// Whether the text holds the value as a quoted string literal.
fn has_literal(text: &str, value: &str) -> bool {
    text.contains(&format!("\"{value}\""))
}

/// Disagreements between Platform's table text and the durables, one line each.
fn table_problems(table: &str, durables: &[Durable]) -> Vec<String> {
    durables
        .iter()
        .filter(|durable| {
            if durable.platform_row {
                !table_has_row(table, durable.name, durable.filter)
            } else {
                !(has_literal(table, durable.name) && has_literal(table, durable.filter))
            }
        })
        .map(|durable| {
            format!(
                "Platform's {PLATFORM_TABLE} has no row `\"{}\", \"{}\"`",
                durable.name, durable.filter
            )
        })
        .collect()
}

/// The text of every tracked `.rs` file of a checkout.
fn tracked_rust_sources(root: &Path) -> String {
    let output = Command::new("git")
        .arg("-C")
        .arg(root)
        .args(["ls-files", "-z", "--", "*.rs"])
        .output()
        .expect("git runs");
    assert!(
        output.status.success(),
        "git ls-files failed in {}: {}",
        root.display(),
        String::from_utf8_lossy(&output.stderr)
    );
    let mut text = String::new();
    for path in output
        .stdout
        .split(|byte| *byte == 0)
        .filter(|p| !p.is_empty())
    {
        let relative = String::from_utf8_lossy(path).into_owned();
        if let Ok(source) = fs::read_to_string(root.join(&relative)) {
            text.push_str(&source);
            text.push('\n');
        }
    }
    text
}

/// Disagreements between the owner repositories' sources and the durables.
fn owner_problems(sources: &BTreeMap<&str, String>, durables: &[Durable]) -> Vec<String> {
    let mut problems = Vec::new();
    for durable in durables {
        let source = &sources[durable.owner];
        if durable.owner_holds_name && !has_literal(source, durable.name) {
            problems.push(format!(
                "`{}` has no string literal \"{}\" in a tracked .rs file",
                durable.owner, durable.name
            ));
        }
        if !has_literal(source, durable.filter) {
            problems.push(format!(
                "`{}` has no string literal \"{}\" (the filter of {}) in a tracked .rs file",
                durable.owner, durable.filter, durable.name
            ));
        }
    }
    problems
}

fn all_durables() -> Vec<Durable> {
    DOMAIN.iter().chain(OTHER.iter()).copied().collect()
}

fn platform_table_text() -> String {
    let manifest = committed_manifest();
    let platform = require_checkout(&manifest, "platform");
    fs::read_to_string(platform.join(PLATFORM_TABLE))
        .unwrap_or_else(|error| panic!("cannot read Platform's {PLATFORM_TABLE}: {error}"))
}

#[test]
fn platform_names_every_durable_with_its_contract_filter() {
    let table = platform_table_text();
    let mut problems = table_problems(&table, &all_durables());
    for name in PLATFORM_ONLY {
        if !has_literal(&tracked_rust_sources(&checkout_of("platform")), name) {
            problems.push(format!("Platform has no string literal \"{name}\""));
        }
    }
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn every_owner_hard_codes_its_durable_name_and_filter() {
    let manifest = committed_manifest();
    let mut owners = all_durables()
        .iter()
        .map(|durable| durable.owner)
        .collect::<Vec<_>>();
    owners.sort_unstable();
    owners.dedup();
    let sources = owners
        .into_iter()
        .map(|owner| {
            (
                owner,
                tracked_rust_sources(&require_checkout(&manifest, owner)),
            )
        })
        .collect::<BTreeMap<_, _>>();
    let problems = owner_problems(&sources, &all_durables());
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

fn checkout_of(id: &str) -> std::path::PathBuf {
    require_checkout(&committed_manifest(), id)
}

#[test]
fn the_table_scan_reports_a_renamed_durable_and_a_changed_filter() {
    let durables = all_durables();
    let table = platform_table_text();
    assert!(
        table_problems(&table, &durables).is_empty(),
        "the unmodified table must pass before the mutation means anything"
    );

    let renamed = table.replace(
        "\"ratatoskr_knowledge_documents\"",
        "\"ratatoskr_knowledge_docs\"",
    );
    assert_ne!(renamed, table, "the mutation did not change the source");
    let problems = table_problems(&renamed, &durables);
    assert_eq!(problems.len(), 1, "{problems:?}");
    assert!(
        problems
            .first()
            .is_some_and(|line| line.contains("ratatoskr_knowledge_documents"))
    );

    let refiltered = table.replace(
        "\"evt.content.document.extracted.v1\"",
        "\"evt.content.document.extracted.v2\"",
    );
    assert_ne!(refiltered, table, "the mutation did not change the source");
    let problems = table_problems(&refiltered, &durables);
    assert_eq!(problems.len(), 1, "{problems:?}");
    assert!(
        problems
            .first()
            .is_some_and(|line| line.contains("evt.content.document.extracted.v1"))
    );
}

#[test]
fn the_row_matcher_accepts_both_row_forms_and_rejects_a_misplaced_filter() {
    let standard =
        "FixedConsumerSpec::standard(\n    EVENT_STREAM,\n    \"a_durable\",\n    \"evt.a.v1\",\n)";
    let structured = "FixedConsumerSpec {\n    durable_name: \"a_durable\",\n    filter_subject: \"evt.a.v1\",\n}";
    let swapped = "\"evt.a.v1\", \"a_durable\"";
    let elsewhere = "\"a_durable\" => 1,\n\"evt.a.v1\"";
    assert!(table_has_row(standard, "a_durable", "evt.a.v1"));
    assert!(table_has_row(structured, "a_durable", "evt.a.v1"));
    assert!(!table_has_row(swapped, "a_durable", "evt.a.v1"));
    assert!(!table_has_row(elsewhere, "a_durable", "evt.a.v1"));
}

#[test]
fn the_owner_scan_reports_a_missing_literal() {
    let durable = durable("a_durable", "evt.a.v1", "owner");
    let mut sources = BTreeMap::new();
    sources.insert("owner", "const N: &str = \"a_durable\";".to_owned());
    let problems = owner_problems(&sources, &[durable]);
    assert_eq!(problems.len(), 1, "{problems:?}");
    assert!(
        problems
            .first()
            .is_some_and(|line| line.contains("evt.a.v1"))
    );

    sources.insert(
        "owner",
        "const N: &str = \"a_durable\"; const F: &str = \"evt.a.v1\";".to_owned(),
    );
    assert!(owner_problems(&sources, &[durable]).is_empty());
}

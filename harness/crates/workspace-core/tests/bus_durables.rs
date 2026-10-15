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
//! Ack waits (XR-021 CONTRACTS R4-05 and R4-08) are the one property of a durable that the scan
//! above leaves out, and a service that states a different wait than Edge's table refuses to
//! verify the durable at start-up. `service_ack_wait_constants_agree_with_edges_durable_table`
//! reads the constant each service states (`INGEST_ACK_WAIT_SECONDS` and
//! `CHANNEL_RECAP_ACK_WAIT_SECONDS` in Knowledge, `NOTIFICATION_ACK_WAIT_SECONDS` in Telegram) and
//! the ack wait in Edge's row: the text from the quoted durable name to the next
//! `FixedConsumerSpec::standard(` or the end of the declaration, where a
//! `.with_ack_wait_seconds(N)` call sets `N` and its absence means the standard 30. The Telegram
//! notification durable is declared through two named constants, so its row is found by the
//! `TELEGRAM_NOTIFICATION_CONSUMERS` array that holds it. Limitation: a text scan again. It cannot
//! see a constant that is computed (`30 * 4`), a wait set through a differently named builder, or
//! a service that ignores its own constant; each service's start-up verification and the native
//! smoke (`jsz` after Edge provisions the durables) cover the running behaviour.
//!
//! Round 5 (R5-11) added five rows, `ratatoskr_{chatgpt,claude,x,instagram,threads}_deletion_acks`,
//! all on the same filter. Platform declares that filter once as the constant
//! `DELETION_ACKNOWLEDGED_SUBJECT` and names the constant in each row, so the row matcher also
//! resolves a bare identifier through a `const NAME: &str = "value";` in the same text. Sanity run
//! on the real sample, `platform` at `3275d52`, `crates/eventing/src/stream.rs`: the five rows
//! resolve to `evt.knowledge.deletion.acknowledged.v1`, and renaming the constant's value makes all
//! five report. The count of 23 service rows is checked against the length in
//! `DOMAIN_CONSUMERS: [FixedConsumerSpec; 23]`, so a row added to one side only is reported.
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

/// The subject Knowledge publishes when it has applied or refused a deletion fact (R5-11).
const DELETION_ACKNOWLEDGED: &str = "evt.knowledge.deletion.acknowledged.v1";

const fn durable(name: &'static str, filter: &'static str, owner: &'static str) -> Durable {
    Durable {
        name,
        filter,
        owner,
        owner_holds_name: true,
        platform_row: true,
    }
}

/// The 30 service-owned entries of CONTRACTS S04 (`DOMAIN_CONSUMERS`), as amended by R5-11, by
/// OBS-023, which added the two Knowledge durables of the notes events, by OBS-024, which added
/// the notes durable of the write command, and by SITE-025, which added the four sites durables.
const DOMAIN: [Durable; 30] = [
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
        "ratatoskr_chatgpt_deletion_acks",
        DELETION_ACKNOWLEDGED,
        "chatgpt",
    ),
    durable(
        "ratatoskr_claude_deletion_acks",
        DELETION_ACKNOWLEDGED,
        "claude",
    ),
    durable("ratatoskr_x_deletion_acks", DELETION_ACKNOWLEDGED, "x"),
    durable(
        "ratatoskr_instagram_deletion_acks",
        DELETION_ACKNOWLEDGED,
        "instagram",
    ),
    durable(
        "ratatoskr_threads_deletion_acks",
        DELETION_ACKNOWLEDGED,
        "threads",
    ),
    durable(
        "ratatoskr_extractor_render_awaits",
        "evt.content.render.>",
        "extractor",
    ),
    durable(
        "ratatoskr_knowledge_notes_files",
        "evt.notes.file.changed.v1",
        "knowledge",
    ),
    durable(
        "ratatoskr_knowledge_notes_vaults",
        "evt.notes.vault.>",
        "knowledge",
    ),
    durable(
        "ratatoskr_notes_write_requests",
        "cmd.notes.file.write_requested.v1",
        "notes",
    ),
    durable(
        "ratatoskr_sites_release_builds",
        "cmd.sites.release.build_requested.v1",
        "sites",
    ),
    durable(
        "ratatoskr_sites_note_changes",
        "evt.notes.file.changed.v1",
        "sites",
    ),
    durable(
        "ratatoskr_sites_vault_disconnections",
        "evt.notes.vault.disconnected.v1",
        "sites",
    ),
    durable(
        "ratatoskr_sites_approvals",
        "evt.platform.site_approval.changed.v1",
        "sites",
    ),
];

/// `(durable, ack wait in seconds)` that the site-publications delta of `fleet-bus-topology` fixes
/// for the sites durables. Edge's table is checked against it directly, because the sites service
/// states the waits as arguments of one table, not as one constant for each durable.
const SITES_ACK_WAITS: [(&str, u64); 4] = [
    ("ratatoskr_sites_release_builds", 300),
    ("ratatoskr_sites_note_changes", 120),
    ("ratatoskr_sites_vault_disconnections", 30),
    ("ratatoskr_sites_approvals", 30),
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

/// Consumers that only Platform creates, outside the table: Edge's own projection, the schedule
/// registration consumer, the stream erasure consumer (R5-12) and the projection of the notes
/// conflict events (OBS-024) that `consumer::run` creates. They are scanned in Platform's sources by
/// name only.
const PLATFORM_ONLY: [&str; 4] = [
    "platform_edge_projection",
    "platform_schedule_registration",
    "platform_stream_erasure",
    "platform_notes_conflict_projection",
];

const PLATFORM_TABLE: &str = "crates/eventing/src/stream.rs";

/// The string value of `const NAME: &str = "value";` (any visibility) in `source`.
fn string_constant(source: &str, name: &str) -> Option<String> {
    let needle = format!("const {name}: &str");
    let at = source.find(&needle)? + needle.len();
    let rest = source.get(at..)?.trim_start().strip_prefix('=')?;
    let rest = rest.trim_start().strip_prefix('"')?;
    Some(rest.split('"').next()?.to_owned())
}

/// Whether `source` holds a table row with this durable name followed by this filter. The filter
/// is a quoted literal, or a bare identifier that `source` declares as a `&str` constant with the
/// same value (R5-11 names one constant in five rows).
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
        if rest.starts_with(&quoted_filter) {
            return true;
        }
        let identifier = rest
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
            .collect::<String>();
        !identifier.is_empty()
            && identifier
                .chars()
                .all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == '_')
            && string_constant(source, &identifier).is_some_and(|value| value == filter)
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

/// One ack wait the owning service states as a constant, and the durables it must agree with.
#[derive(Debug, Clone, Copy)]
struct AckWaitRule {
    /// The repository whose tracked `.rs` files declare the constant.
    owner: &'static str,
    /// The `const NAME: u64 = <seconds>` or `const NAME: Duration = Duration::from_secs(<seconds>)`
    /// the service states.
    constant: &'static str,
    /// The durable whose row in Edge's table must carry the same wait, and where the row starts.
    durable: &'static str,
    /// The text in Edge's table that starts the durable's row.
    anchor: &'static str,
    /// The wait the contract (CONTRACTS S04) fixes for this durable.
    contract_seconds: u64,
}

const fn ack_rule(
    owner: &'static str,
    constant: &'static str,
    durable: &'static str,
    contract_seconds: u64,
) -> AckWaitRule {
    AckWaitRule {
        owner,
        constant,
        durable,
        anchor: durable,
        contract_seconds,
    }
}

const ACK_WAIT_RULES: [AckWaitRule; 9] = [
    ack_rule(
        "knowledge",
        "INGEST_ACK_WAIT_SECONDS",
        "ratatoskr_knowledge_documents",
        120,
    ),
    ack_rule(
        "knowledge",
        "INGEST_ACK_WAIT_SECONDS",
        "ratatoskr_knowledge_social_sources",
        120,
    ),
    ack_rule(
        "knowledge",
        "INGEST_ACK_WAIT_SECONDS",
        "ratatoskr_knowledge_ai_archive",
        120,
    ),
    ack_rule(
        "knowledge",
        "INGEST_ACK_WAIT_SECONDS",
        "ratatoskr_knowledge_repository_requests",
        120,
    ),
    ack_rule(
        "knowledge",
        "INGEST_ACK_WAIT_SECONDS",
        "ratatoskr_knowledge_notes_files",
        120,
    ),
    ack_rule(
        "knowledge",
        "INGEST_ACK_WAIT_SECONDS",
        "ratatoskr_knowledge_notes_vaults",
        120,
    ),
    ack_rule(
        "knowledge",
        "CHANNEL_RECAP_ACK_WAIT_SECONDS",
        "ratatoskr_knowledge_channel_recap",
        30,
    ),
    ack_rule(
        "notes",
        "WRITE_ACK_WAIT",
        "ratatoskr_notes_write_requests",
        30,
    ),
    AckWaitRule {
        anchor: "TELEGRAM_NOTIFICATION_CONSUMERS: [",
        ..ack_rule(
            "telegram",
            "NOTIFICATION_ACK_WAIT_SECONDS",
            "ratatoskr_telegram_notifications",
            30,
        )
    },
];

/// The standard ack wait of `FixedConsumerSpec::standard`.
const STANDARD_ACK_WAIT_SECONDS: u64 = 30;

/// The number that follows `prefix` in `text`, digit separators allowed.
fn number_after(text: &str, prefix: &str) -> Option<u64> {
    let start = text.find(prefix)? + prefix.len();
    let digits = text
        .get(start..)?
        .trim_start()
        .chars()
        .take_while(|c| c.is_ascii_digit() || *c == '_')
        .filter(char::is_ascii_digit)
        .collect::<String>();
    digits.parse().ok()
}

/// The ack wait Edge's table gives the row that starts at `anchor`.
fn table_ack_wait(table: &str, anchor: &str) -> Option<u64> {
    let start = table.find(anchor)? + anchor.len();
    let rest = table.get(start..)?;
    let end = [rest.find("FixedConsumerSpec::standard("), rest.find(';')]
        .into_iter()
        .flatten()
        .min()
        .unwrap_or(rest.len());
    let row = rest.get(..end)?;
    Some(number_after(row, ".with_ack_wait_seconds(").unwrap_or(STANDARD_ACK_WAIT_SECONDS))
}

/// Disagreements between the stated constants, Edge's table and the contract, one line each.
fn ack_wait_problems(table: &str, sources: &BTreeMap<&str, String>) -> Vec<String> {
    let mut problems = Vec::new();
    for rule in ACK_WAIT_RULES {
        let source = sources.get(rule.owner).map_or("", String::as_str);
        let Some(stated) = number_after(source, &format!("const {}: u64 =", rule.constant))
            .or_else(|| {
                number_after(
                    source,
                    &format!("const {}: Duration = Duration::from_secs(", rule.constant),
                )
            })
        else {
            problems.push(format!(
                "`{}` has no `const {}: u64 = <seconds>` and no `const {}: Duration = Duration::from_secs(<seconds>)` in a tracked .rs file",
                rule.owner, rule.constant, rule.constant
            ));
            continue;
        };
        let Some(edge) = table_ack_wait(table, rule.anchor) else {
            problems.push(format!(
                "Platform's {PLATFORM_TABLE} has no row for `{}`",
                rule.durable
            ));
            continue;
        };
        if stated != edge {
            problems.push(format!(
                "`{}` states {} = {stated} seconds but Edge provisions `{}` with {edge}",
                rule.owner, rule.constant, rule.durable
            ));
        }
        if edge != rule.contract_seconds {
            problems.push(format!(
                "Edge provisions `{}` with {edge} seconds but CONTRACTS S04 fixes {}",
                rule.durable, rule.contract_seconds
            ));
        }
    }
    problems
}

fn ack_wait_sources() -> BTreeMap<&'static str, String> {
    let manifest = committed_manifest();
    let mut owners = ACK_WAIT_RULES
        .iter()
        .map(|rule| rule.owner)
        .collect::<Vec<_>>();
    owners.sort_unstable();
    owners.dedup();
    owners
        .into_iter()
        .map(|owner| {
            (
                owner,
                tracked_rust_sources(&require_checkout(&manifest, owner)),
            )
        })
        .collect()
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

#[test]
fn edge_provisions_the_sites_durables_with_their_contract_ack_waits() {
    let table = platform_table_text();
    let mut problems = Vec::new();
    for (durable, seconds) in SITES_ACK_WAITS {
        match table_ack_wait(&table, durable) {
            Some(edge) if edge == seconds => {}
            Some(edge) => problems.push(format!(
                "Edge provisions `{durable}` with {edge} seconds, the contract fixes {seconds}"
            )),
            None => problems.push(format!(
                "Platform's {PLATFORM_TABLE} has no row for `{durable}`"
            )),
        }
    }
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
fn the_row_matcher_resolves_a_named_filter_constant_and_rejects_a_different_value() {
    let table = "const SHARED: &str = \"evt.shared.v1\";\nFixedConsumerSpec::standard(E, \"one\", SHARED),\nFixedConsumerSpec::standard(E, \"two\", SHARED),";
    assert!(table_has_row(table, "one", "evt.shared.v1"));
    assert!(table_has_row(table, "two", "evt.shared.v1"));
    assert!(!table_has_row(table, "one", "evt.other.v1"));
    let undeclared = "FixedConsumerSpec::standard(E, \"one\", SHARED),";
    assert!(!table_has_row(undeclared, "one", "evt.shared.v1"));
    let lowercase = "const shared: &str = \"evt.shared.v1\";\nrow(E, \"one\", shared),";
    assert!(!table_has_row(lowercase, "one", "evt.shared.v1"));
}

#[test]
fn the_service_table_length_equals_the_durables_the_harness_lists() {
    let table = platform_table_text();
    let declared = number_after(&table, "DOMAIN_CONSUMERS: [FixedConsumerSpec;")
        .expect("DOMAIN_CONSUMERS declares its length");
    assert_eq!(
        declared,
        DOMAIN.len() as u64,
        "Platform's DOMAIN_CONSUMERS has {declared} rows, the harness lists {}",
        DOMAIN.len()
    );
    let mutated = table.replace(
        &format!("DOMAIN_CONSUMERS: [FixedConsumerSpec; {declared}]"),
        "DOMAIN_CONSUMERS: [FixedConsumerSpec; 0]",
    );
    assert_ne!(mutated, table, "the mutation did not change the table");
    assert_eq!(
        number_after(&mutated, "DOMAIN_CONSUMERS: [FixedConsumerSpec;"),
        Some(0)
    );
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

#[test]
fn service_ack_wait_constants_agree_with_edges_durable_table() {
    let problems = ack_wait_problems(&platform_table_text(), &ack_wait_sources());
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn the_ack_wait_scan_reports_a_changed_constant_and_a_changed_table_row() {
    let table = platform_table_text();
    let sources = ack_wait_sources();
    assert!(
        ack_wait_problems(&table, &sources).is_empty(),
        "the unmodified checkout must pass before the mutation means anything"
    );

    let mut changed = sources.clone();
    let knowledge = changed.get_mut("knowledge").expect("knowledge sources");
    let mutated = knowledge.replace(
        "const CHANNEL_RECAP_ACK_WAIT_SECONDS: u64 = 30;",
        "const CHANNEL_RECAP_ACK_WAIT_SECONDS: u64 = 31;",
    );
    assert_ne!(
        &mutated, knowledge,
        "the mutation did not change the source"
    );
    *knowledge = mutated;
    let problems = ack_wait_problems(&table, &changed);
    assert!(
        problems
            .iter()
            .any(|line| line.contains("CHANNEL_RECAP_ACK_WAIT_SECONDS = 31")),
        "{problems:?}"
    );

    let retimed = table.replacen(
        ".with_ack_wait_seconds(120)",
        ".with_ack_wait_seconds(121)",
        1,
    );
    assert_ne!(retimed, table, "the mutation did not change the table");
    let problems = ack_wait_problems(&retimed, &sources);
    assert!(
        problems
            .iter()
            .any(|line| line.contains("ratatoskr_knowledge_documents")),
        "{problems:?}"
    );
}

#[test]
fn the_ack_wait_row_reader_reads_the_chain_and_the_default() {
    let table = "FixedConsumerSpec::standard(E, \"a\", \"f\")\n.with_ack_wait_seconds(120),\nFixedConsumerSpec::standard(E, \"b\", \"g\"),\n];";
    assert_eq!(table_ack_wait(table, "\"a\""), Some(120));
    assert_eq!(table_ack_wait(table, "\"b\""), Some(30));
    assert_eq!(table_ack_wait(table, "\"missing\""), None);
    assert_eq!(
        number_after("const X: u64 = 1_20;", "const X: u64 ="),
        Some(120)
    );
}

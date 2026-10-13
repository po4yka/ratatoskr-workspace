//! Alert-rule series agreement (XR-021 CONTRACTS R5-13, R5-14 rule 6).
//!
//! `platform/deploy/monitoring/ratatoskr-bus-alerts.rules.yml` is the rule file that tells an operator when a consumer of the events stream falls behind. An alert whose series was renamed or never existed never fires, and nothing evaluates the file in CI, so this test reads both sides: every series name in an `expr:` must be the value of a `pub const NAME: &str` in Platform's `crates/telemetry/src/metrics.rs`, or match the documented allow-list of producer-side names, and every alert must state `for`, `labels.severity` and `annotations.summary`.
//!
//! The allow-list is the file's own comment line that starts with `# PRODUCER-SIDE NAMES` and lists each pattern as `*_suffix` between backticks: the gauges the five deletion producers export (R5-11) are not Platform constants. A name in an `expr:` is allowed when it ends with a listed suffix, and so is a `__name__=~".*suffix"` matcher.
//!
//! Limitation, stated plainly. This is a line scan, not a `YAML` or `PromQL` parser (the harness takes no parser dependency: `deny.toml` allows MIT, Apache-2.0 and Unicode-3.0 only and denies duplicate versions). The scan finds each alert by its `- alert:` line, treats everything up to the next `- alert:` line as that alert's block, and reads `for:`, `severity:` and `summary:` as keys anywhere in the block. It strips string literals, `{...}` matchers, `[...]` ranges and the label lists of `by`, `without`, `on` and `ignoring` before it reads metric names, and it knows the `PromQL` words listed in `PROMQL_WORDS`; a function outside that list shows up as an unknown series and fails loudly, which is the safe direction. It cannot see that a label used in a matcher exists, that a threshold is sensible or that the file parses (flow F0 of the native smoke parses it with the YAML library of the selected interpreter or Ruby).
//!
//! Sanity run on the real sample (platform `3275d52`, six alerts): the extraction finds `platform_bus_consumer_oldest_unacked_age_seconds`, `platform_bus_consumer_pending`, `platform_bus_stream_bytes`, `platform_bus_stream_max_bytes`, `platform_bus_consumer_redelivered` and the `__name__` matcher of the tombstone alert, all resolved; renaming one series in a copy of the file reports exactly that name.

#![allow(dead_code, clippy::expect_used, clippy::panic)]

#[path = "support/checkout.rs"]
mod checkout;

use checkout::{committed_manifest, require_checkout};
use std::collections::BTreeSet;
use std::fs;

const RULES: &str = "deploy/monitoring/ratatoskr-bus-alerts.rules.yml";
const METRICS: &str = "crates/telemetry/src/metrics.rs";

/// `PromQL` words that appear in the rule file and are not series names.
const PROMQL_WORDS: [&str; 16] = [
    "by", "without", "on", "ignoring", "and", "or", "unless", "bool", "max", "min", "sum", "avg",
    "count", "rate", "increase", "absent",
];

/// The value of every `pub const NAME: &str = "value";` of the metrics module.
fn metric_names(metrics: &str) -> BTreeSet<String> {
    metrics
        .split("pub const ")
        .skip(1)
        .filter_map(|chunk| {
            let (declaration, _) = chunk.split_once(';')?;
            if !declaration.contains(": &str") {
                return None;
            }
            let (_, value) = declaration.split_once('=')?;
            let quoted = value.trim().strip_prefix('"')?;
            let (name, _) = quoted.split_once('"')?;
            Some(name.to_owned())
        })
        .collect()
}

/// The suffixes the rule file's comment documents as producer-side series.
fn producer_side_suffixes(rules: &str) -> Vec<String> {
    rules
        .lines()
        .filter(|line| line.trim_start().starts_with("# PRODUCER-SIDE NAMES"))
        .filter_map(|line| line.split_once("):").map(|(_, rest)| rest))
        .flat_map(|rest| rest.split('`').skip(1).step_by(2))
        .filter_map(|pattern| pattern.strip_prefix('*'))
        .map(str::to_owned)
        .collect()
}

/// One alert: its name and the text of its block.
struct Alert {
    name: String,
    block: String,
}

fn alerts(rules: &str) -> Vec<Alert> {
    let mut found: Vec<Alert> = Vec::new();
    for line in rules.lines() {
        let trimmed = line.trim_start();
        if let Some(name) = trimmed.strip_prefix("- alert:") {
            found.push(Alert {
                name: name.trim().to_owned(),
                block: String::new(),
            });
        } else if let Some(alert) = found.last_mut()
            && !trimmed.starts_with('#')
        {
            alert.block.push_str(line);
            alert.block.push('\n');
        }
    }
    found
}

/// The value of the first `key:` line of a block.
fn key_value<'a>(block: &'a str, key: &str) -> Option<&'a str> {
    block.lines().find_map(|line| {
        line.trim_start()
            .strip_prefix(key)
            .and_then(|rest| rest.strip_prefix(':'))
            .map(str::trim)
            .filter(|value| !value.is_empty())
    })
}

/// Removes everything between `open` and `close`, nesting not supported (`PromQL` has none here).
fn strip_between(text: &str, open: char, close: char) -> String {
    let mut output = String::new();
    let mut depth = 0_u32;
    for c in text.chars() {
        if c == open {
            depth += 1;
        } else if c == close && depth > 0 {
            depth -= 1;
        } else if depth == 0 {
            output.push(c);
        }
    }
    output
}

/// The series names and `__name__` regex suffixes an `expr:` value uses.
fn expression_names(expr: &str) -> (BTreeSet<String>, BTreeSet<String>) {
    let mut regex_suffixes = BTreeSet::new();
    if let Some((_, after)) = expr.split_once("__name__=~\"")
        && let Some((pattern, _)) = after.split_once('"')
    {
        regex_suffixes.insert(pattern.trim_start_matches(".*").to_owned());
    }
    let without_matchers = strip_between(expr, '{', '}');
    let without_ranges = strip_between(&without_matchers, '[', ']');
    let mut text = without_ranges;
    for word in ["by", "without", "on", "ignoring"] {
        let opener = format!("{word} (");
        while let Some((before, after)) = text.split_once(&opener) {
            let Some((_, tail)) = after.split_once(')') else {
                break;
            };
            text = format!("{before}{tail}");
        }
    }
    let names = text
        .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_' || c == ':'))
        .filter(|token| {
            token
                .chars()
                .next()
                .is_some_and(|c| c.is_ascii_alphabetic() || c == '_')
        })
        .filter(|token| !PROMQL_WORDS.contains(token))
        .map(str::to_owned)
        .collect();
    (names, regex_suffixes)
}

/// Disagreements between the rule file and the metric constants, one line each.
fn problems(rules: &str, metrics: &str) -> Vec<String> {
    let constants = metric_names(metrics);
    let suffixes = producer_side_suffixes(rules);
    let mut problems = Vec::new();
    let parsed = alerts(rules);
    if parsed.is_empty() {
        problems.push("the rule file holds no `- alert:` entry".to_owned());
    }
    for alert in &parsed {
        for key in ["for", "severity", "summary"] {
            if key_value(&alert.block, key).is_none() {
                problems.push(format!("alert {} has no `{key}:`", alert.name));
            }
        }
        let Some(expr) = key_value(&alert.block, "expr") else {
            problems.push(format!("alert {} has no `expr:`", alert.name));
            continue;
        };
        let (names, regexes) = expression_names(expr);
        for name in names {
            let producer_side = suffixes
                .iter()
                .any(|suffix| name.ends_with(suffix.as_str()));
            if !constants.contains(&name) && !producer_side {
                problems.push(format!(
                    "alert {} uses `{name}`, which is not a constant of {METRICS} nor a documented producer-side name",
                    alert.name
                ));
            }
        }
        for regex in regexes {
            if !suffixes.contains(&regex) {
                problems.push(format!(
                    "alert {} matches __name__ against `.*{regex}`, which is not a documented producer-side suffix",
                    alert.name
                ));
            }
        }
    }
    problems
}

fn platform_file(relative: &str) -> String {
    let manifest = committed_manifest();
    let root = require_checkout(&manifest, "platform");
    fs::read_to_string(root.join(relative))
        .unwrap_or_else(|error| panic!("cannot read Platform's {relative}: {error}"))
}

#[test]
fn every_series_in_the_bus_alert_rules_is_a_metric_constant_or_a_documented_producer_name() {
    let problems = problems(&platform_file(RULES), &platform_file(METRICS));
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn the_rule_file_has_the_alerts_of_r5_13_and_the_extraction_reads_their_series() {
    let rules = platform_file(RULES);
    let names = alerts(&rules)
        .into_iter()
        .map(|alert| alert.name)
        .collect::<Vec<_>>();
    assert_eq!(names.len(), 6, "{names:?}");
    let constants = metric_names(&platform_file(METRICS));
    for series in [
        "platform_bus_consumer_oldest_unacked_age_seconds",
        "platform_bus_consumer_pending",
        "platform_bus_stream_bytes",
        "platform_bus_stream_max_bytes",
        "platform_bus_consumer_redelivered",
    ] {
        assert!(
            constants.contains(series),
            "{series} is not a constant of {METRICS}"
        );
        assert!(rules.contains(series), "{series} is not used by the rules");
    }
}

#[test]
fn a_renamed_series_and_a_missing_key_are_reported() {
    let rules = platform_file(RULES);
    let metrics = platform_file(METRICS);
    assert!(
        problems(&rules, &metrics).is_empty(),
        "the unmodified file must pass before the mutation means anything"
    );

    let renamed = rules.replace(
        "platform_bus_stream_max_bytes",
        "platform_bus_stream_capacity_bytes",
    );
    assert_ne!(renamed, rules, "the mutation did not change the file");
    let found = problems(&renamed, &metrics);
    assert!(
        found
            .iter()
            .any(|line| line.contains("platform_bus_stream_capacity_bytes")),
        "{found:?}"
    );

    let no_severity = rules.replacen("severity: warning", "sev: warning", 1);
    assert_ne!(no_severity, rules, "the mutation did not change the file");
    let found = problems(&no_severity, &metrics);
    assert!(
        found.iter().any(|line| line.contains("`severity:`")),
        "{found:?}"
    );

    let wrong_suffix = rules.replace(
        "__name__=~\".*_oldest_unacknowledged_tombstone_age_seconds\"",
        "__name__=~\".*_oldest_unacknowledged_age_seconds\"",
    );
    assert_ne!(wrong_suffix, rules, "the mutation did not change the file");
    let found = problems(&wrong_suffix, &metrics);
    assert!(
        found
            .iter()
            .any(|line| line.contains("producer-side suffix")),
        "{found:?}"
    );
}

#[test]
fn the_extraction_handles_matchers_ranges_and_grouping() {
    let (names, regexes) = expression_names(
        "max by (durable) (platform_a{durable=~\"x_.*\"}) > 3600 and increase(platform_b[15m]) > 1",
    );
    assert_eq!(
        names,
        BTreeSet::from(["platform_a".to_owned(), "platform_b".to_owned()])
    );
    assert!(regexes.is_empty());
    let (names, regexes) =
        expression_names("max by (job) ({__name__=~\".*_age_seconds\"}) > 86400");
    assert!(names.is_empty(), "{names:?}");
    assert_eq!(regexes, BTreeSet::from(["_age_seconds".to_owned()]));
}

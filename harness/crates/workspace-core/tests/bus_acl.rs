//! Bus ACL equality: `ratatoskr-platform/deploy/nats/ratatoskr.conf` is the only deployed NATS
//! authorization file, every service that carries a copy of its own stanza must carry an equal
//! one, and the stanzas must keep the least-privilege invariants of the XR-021 bus topology.
//!
//! The splitter is plain text on purpose. The comparison is on what a reviewer read (comments,
//! whitespace and the nkey token ignored), so it must not depend on a NATS parser's idea of
//! meaning. A stanza is a brace block that opens at the start of a file or right after `[` or
//! `,`; `jetstream {`, `authorization {` and `permissions: {` open after a word or a colon.

#![allow(dead_code, clippy::expect_used, clippy::panic)]

#[path = "support/checkout.rs"]
mod checkout;

use checkout::{committed_manifest, require_checkout};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;

const PLACEHOLDER_PREFIX: &str = "UREPLACE_ME_WITH_THE_PUBLIC_NKEY_OF_RATATOSKR_";

const IDENTITIES: [&str; 13] = [
    "EDGE",
    "TELEGRAM",
    "CHATGPT",
    "CLAUDE",
    "X",
    "INSTAGRAM",
    "THREADS",
    "EXTRACTOR",
    "EXTRACTOR_BROWSER_WORKER",
    "KNOWLEDGE",
    "GITHUB",
    "VAULT",
    "CHANNEL_DIGESTS",
];

/// The repository that owns each identity: it publishes or consumes with it.
const OWNERS: [(&str, &str); 13] = [
    ("EDGE", "platform"),
    ("TELEGRAM", "telegram"),
    ("CHATGPT", "chatgpt"),
    ("CLAUDE", "claude"),
    ("X", "x"),
    ("INSTAGRAM", "instagram"),
    ("THREADS", "threads"),
    ("EXTRACTOR", "extractor"),
    ("EXTRACTOR_BROWSER_WORKER", "extractor"),
    ("KNOWLEDGE", "knowledge"),
    ("GITHUB", "github"),
    ("VAULT", "vault"),
    ("CHANNEL_DIGESTS", "channel-digests"),
];

/// `(repository, path of the copy, identity)`.
const FRAGMENTS: [(&str, &str, &str); 6] = [
    ("extractor", "deploy/nats/identity.conf", "EXTRACTOR"),
    (
        "extractor",
        "deploy/nats/identity-browser-worker.conf",
        "EXTRACTOR_BROWSER_WORKER",
    ),
    ("knowledge", "deploy/nats/identity.conf", "KNOWLEDGE"),
    (
        "channel-digests",
        "deploy/nats/identity.conf",
        "CHANNEL_DIGESTS",
    ),
    ("github", "deploy/nats/identity.conf", "GITHUB"),
    ("vault", "deploy/nats/identity.conf", "VAULT"),
];

const COMMANDS: &str = "ratatoskr_commands";
const EVENTS: &str = "ratatoskr_events";

/// `(stream, durable, owning identity)`: the ACL owner column of the fixed-durable table.
const DURABLE_OWNERS: [(&str, &str, &str); 22] = [
    (EVENTS, "ratatoskr_telegram_notifications", "TELEGRAM"),
    (COMMANDS, "ratatoskr_x_browser_capture", "X"),
    (COMMANDS, "ratatoskr_instagram_browser_capture", "INSTAGRAM"),
    (COMMANDS, "threads_browser_capture", "THREADS"),
    (COMMANDS, "ratatoskr_extractor_capture", "EXTRACTOR"),
    (
        COMMANDS,
        "ratatoskr_browser_worker",
        "EXTRACTOR_BROWSER_WORKER",
    ),
    (COMMANDS, "ratatoskr_knowledge_channel_recap", "KNOWLEDGE"),
    (
        COMMANDS,
        "ratatoskr_channel_digest_subscriptions",
        "CHANNEL_DIGESTS",
    ),
    (COMMANDS, "ratatoskr_channel_digest_runs", "CHANNEL_DIGESTS"),
    (
        COMMANDS,
        "ratatoskr_channel_digest_schedule_occurrences",
        "CHANNEL_DIGESTS",
    ),
    (COMMANDS, "ratatoskr_vault_backup_policy", "VAULT"),
    (EVENTS, "ratatoskr_knowledge_documents", "KNOWLEDGE"),
    (EVENTS, "ratatoskr_knowledge_social_sources", "KNOWLEDGE"),
    (EVENTS, "ratatoskr_knowledge_ai_archive", "KNOWLEDGE"),
    (
        EVENTS,
        "ratatoskr_knowledge_repository_requests",
        "KNOWLEDGE",
    ),
    (EVENTS, "ratatoskr_github_analysis_completed", "GITHUB"),
    (EVENTS, "ratatoskr_github_analysis_failed", "GITHUB"),
    (EVENTS, "ratatoskr_github_policy_acknowledged", "GITHUB"),
    (EVENTS, "ratatoskr_x_extractor_reports", "X"),
    (
        EVENTS,
        "ratatoskr_channel_digest_recap_completed",
        "CHANNEL_DIGESTS",
    ),
    (
        EVENTS,
        "ratatoskr_channel_digest_recap_failed",
        "CHANNEL_DIGESTS",
    ),
    (EVENTS, "ratatoskr_extractor_render_awaits", "EXTRACTOR"),
];

/// Subjects (or prefixes) no identity other than EDGE may be able to publish.
const FORBIDDEN_EXACT: [&str; 3] = ["$JS.API.>", "evt.>", "cmd.>"];
const FORBIDDEN_PREFIXES: [&str; 4] = [
    "$JS.API.CONSUMER.CREATE",
    "$JS.API.CONSUMER.DURABLE.CREATE",
    "$JS.API.STREAM.CREATE",
    "$JS.API.STREAM.UPDATE",
];
const FORBIDDEN_FRAGMENTS: [&str; 2] = ["STREAM.MSG.GET.ratatoskr_", "DIRECT.GET.ratatoskr_"];

#[derive(Debug)]
struct Stanza {
    /// Identity name, taken from the nkey placeholder.
    name: String,
    placeholder: String,
    /// Comment-free text of the whole stanza.
    text: String,
}

impl Stanza {
    /// Whitespace-free text with the nkey token removed: what two copies are compared on.
    fn normalized(&self) -> String {
        self.text
            .replace(&self.placeholder, "")
            .split_whitespace()
            .collect()
    }
}

/// Removes `#` comments, leaving quoted strings alone.
fn strip_comments(source: &str) -> String {
    let mut output = String::with_capacity(source.len());
    for line in source.lines() {
        let mut in_string = false;
        for character in line.chars() {
            match character {
                '"' => {
                    in_string = !in_string;
                    output.push(character);
                }
                '#' if !in_string => break,
                _ => output.push(character),
            }
        }
        output.push('\n');
    }
    output
}

/// The identity name and filler of a placeholder, split at the last underscore.
fn identity_of(placeholder: &str) -> String {
    let rest = placeholder
        .strip_prefix(PLACEHOLDER_PREFIX)
        .unwrap_or_else(|| panic!("nkey `{placeholder}` does not use the placeholder grammar"));
    let (name, filler) = rest
        .rsplit_once('_')
        .unwrap_or_else(|| panic!("placeholder `{placeholder}` has no filler segment"));
    assert!(
        !filler.is_empty() && filler.chars().all(|c| c == 'X'),
        "placeholder `{placeholder}` filler `{filler}` is not one or more X"
    );
    assert!(
        !name.is_empty() && name.chars().all(|c| c.is_ascii_uppercase() || c == '_'),
        "placeholder `{placeholder}` name `{name}` is not [A-Z_]+"
    );
    name.to_owned()
}

fn stanzas(source: &str) -> Vec<Stanza> {
    let text = strip_comments(source);
    let characters = text.chars().collect::<Vec<_>>();
    let mut found = Vec::new();
    let mut previous: Option<char> = None;
    let mut index = 0;
    while let Some(&character) = characters.get(index) {
        let opens_stanza = character == '{' && matches!(previous, None | Some('[' | ','));
        if opens_stanza {
            let mut depth = 0_usize;
            let mut in_string = false;
            let mut end = index;
            for (offset, &inner) in characters.iter().enumerate().skip(index) {
                match inner {
                    '"' => in_string = !in_string,
                    '{' if !in_string => depth += 1,
                    '}' if !in_string => {
                        depth -= 1;
                        if depth == 0 {
                            end = offset;
                            break;
                        }
                    }
                    _ => {}
                }
            }
            assert!(end > index, "unbalanced braces in a NATS stanza");
            let body = characters
                .iter()
                .skip(index)
                .take(end - index + 1)
                .collect::<String>();
            let placeholder = body
                .split_once("nkey:")
                .and_then(|(_, rest)| rest.split_whitespace().next())
                .unwrap_or_else(|| panic!("stanza has no nkey: {body}"))
                .trim_matches(',')
                .to_owned();
            found.push(Stanza {
                name: identity_of(&placeholder),
                placeholder,
                text: body,
            });
            index = end + 1;
            previous = Some('}');
            continue;
        }
        if !character.is_whitespace() {
            previous = Some(character);
        }
        index += 1;
    }
    found
}

/// The quoted strings of the first `[...]` that follows `marker` and then `allow:` in `text`.
fn allow_list(text: &str, marker: &str) -> Vec<String> {
    let Some((_, after_marker)) = text.split_once(marker) else {
        return Vec::new();
    };
    let Some((_, after_allow)) = after_marker.split_once("allow:") else {
        return Vec::new();
    };
    let Some((_, after_open)) = after_allow.split_once('[') else {
        return Vec::new();
    };
    let Some((list, _)) = after_open.split_once(']') else {
        return Vec::new();
    };
    list.split('"')
        .enumerate()
        .filter(|(position, _)| position % 2 == 1)
        .map(|(_, piece)| piece.to_owned())
        .collect()
}

fn platform_stanzas() -> Vec<Stanza> {
    let manifest = committed_manifest();
    let root = require_checkout(&manifest, "platform");
    let path = root.join("deploy/nats/ratatoskr.conf");
    let source = fs::read_to_string(&path)
        .unwrap_or_else(|error| panic!("read {}: {error}", path.display()));
    stanzas(&source)
}

fn owner_of(identity: &str) -> &'static str {
    let Some((_, owner)) = OWNERS.iter().find(|(name, _)| *name == identity) else {
        panic!("identity `{identity}` has no owner repository");
    };
    owner
}

fn is_allowed_wildcard(subject: &str) -> bool {
    if !subject.contains('>') && !subject.contains('*') {
        return true;
    }
    if subject.contains('*') {
        return false;
    }
    let segments = subject.split('.').collect::<Vec<_>>();
    let wildcard_is_last = segments.last() == Some(&">")
        && segments
            .iter()
            .take(segments.len().saturating_sub(1))
            .all(|segment| !segment.contains('>'));
    if !wildcard_is_last {
        return false;
    }
    let is_ack =
        segments.len() == 5 && segments.first() == Some(&"$JS") && segments.get(1) == Some(&"ACK");
    let is_kv_direct_get = segments.len() == 6
        && segments.first() == Some(&"$JS")
        && segments.get(1) == Some(&"API")
        && segments.get(2) == Some(&"DIRECT")
        && segments.get(3) == Some(&"GET")
        && segments
            .get(4)
            .is_some_and(|bucket| bucket.starts_with("KV_"));
    let is_kv_subject = segments.len() == 3 && segments.first() == Some(&"$KV");
    is_ack || is_kv_direct_get || is_kv_subject
}

#[test]
fn platform_conf_has_exactly_the_thirteen_identities() {
    let manifest = committed_manifest();
    let found = platform_stanzas();
    let names = found
        .iter()
        .map(|stanza| stanza.name.clone())
        .collect::<Vec<_>>();
    let unique = names.iter().cloned().collect::<BTreeSet<_>>();
    let placeholders = found
        .iter()
        .map(|stanza| stanza.placeholder.clone())
        .collect::<BTreeSet<_>>();

    assert_eq!(
        names.len(),
        unique.len(),
        "an identity appears twice in ratatoskr.conf: {names:?}"
    );
    assert_eq!(
        placeholders.len(),
        found.len(),
        "two identities share one nkey placeholder"
    );
    assert_eq!(
        unique,
        IDENTITIES
            .iter()
            .map(|name| (*name).to_owned())
            .collect::<BTreeSet<_>>(),
        "ratatoskr.conf must hold exactly the thirteen identities of the bus topology"
    );
    for identity in IDENTITIES {
        require_checkout(&manifest, owner_of(identity));
    }
}

#[test]
fn every_service_fragment_equals_its_platform_stanza() {
    let manifest = committed_manifest();
    let platform = platform_stanzas()
        .into_iter()
        .map(|stanza| (stanza.name.clone(), stanza))
        .collect::<BTreeMap<_, _>>();
    let mut problems = Vec::new();

    for (repository, relative, identity) in FRAGMENTS {
        let root = require_checkout(&manifest, repository);
        let path = root.join(relative);
        let Ok(source) = fs::read_to_string(&path) else {
            problems.push(format!("{repository}: {relative} is missing"));
            continue;
        };
        let copies = stanzas(&source);
        let [copy] = copies.as_slice() else {
            problems.push(format!(
                "{repository}: {relative} holds {} stanzas, expected exactly one",
                copies.len()
            ));
            continue;
        };
        if copy.name != identity {
            problems.push(format!(
                "{repository}: {relative} is the `{}` identity, expected `{identity}`",
                copy.name
            ));
            continue;
        }
        let Some(reviewed) = platform.get(identity) else {
            problems.push(format!("ratatoskr.conf has no `{identity}` stanza"));
            continue;
        };
        if copy.normalized() != reviewed.normalized() {
            problems.push(format!(
                "{repository}: {relative} differs from the `{identity}` stanza of ratatoskr.conf"
            ));
        }
    }

    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn extractor_permissions_conf_is_gone() {
    let manifest = committed_manifest();
    let root = require_checkout(&manifest, "extractor");
    let old = root.join("deploy/nats/extractor-permissions.conf");

    assert!(
        !old.exists(),
        "{} still exists; the extractor's narrow stanza replaced it",
        old.display()
    );
}

#[test]
fn non_edge_stanzas_obey_the_permission_invariants() {
    let found = platform_stanzas();
    let mut problems = Vec::new();
    let mut holders = BTreeMap::<(String, String, String), BTreeSet<String>>::new();

    for stanza in found.iter().filter(|stanza| stanza.name != "EDGE") {
        if stanza.text.contains("deny:") {
            problems.push(format!("{} has a deny block", stanza.name));
        }
        let subscribe = allow_list(&stanza.text, "subscribe:");
        if subscribe != ["_INBOX.>"] {
            problems.push(format!(
                "{} subscribes to {subscribe:?}, expected only `_INBOX.>`",
                stanza.name
            ));
        }
        for subject in allow_list(&stanza.text, "publish:") {
            if FORBIDDEN_EXACT.contains(&subject.as_str())
                || FORBIDDEN_PREFIXES
                    .iter()
                    .any(|prefix| subject.starts_with(prefix))
                || FORBIDDEN_FRAGMENTS
                    .iter()
                    .any(|fragment| subject.contains(fragment))
            {
                problems.push(format!("{} may publish `{subject}`", stanza.name));
            }
            if !is_allowed_wildcard(&subject) {
                problems.push(format!(
                    "{} holds the wildcard `{subject}`, which is not an ack, KV direct-get or KV subject",
                    stanza.name
                ));
            }
            for (kind, prefix) in [
                ("info", "$JS.API.CONSUMER.INFO."),
                ("next", "$JS.API.CONSUMER.MSG.NEXT."),
                ("ack", "$JS.ACK."),
            ] {
                let Some(rest) = subject.strip_prefix(prefix) else {
                    continue;
                };
                let rest = rest.trim_end_matches(".>");
                if let Some((stream, durable)) = rest.split_once('.') {
                    holders
                        .entry((kind.to_owned(), stream.to_owned(), durable.to_owned()))
                        .or_default()
                        .insert(stanza.name.clone());
                }
            }
        }
    }

    for ((kind, stream, durable), owners) in &holders {
        if owners.len() != 1 {
            problems.push(format!(
                "the {kind} permission of durable `{durable}` on `{stream}` is held by {owners:?}, expected exactly one stanza"
            ));
        }
    }
    for (stream, durable, owner) in DURABLE_OWNERS {
        let info = holders.get(&("info".to_owned(), stream.to_owned(), durable.to_owned()));
        if info.is_none_or(|owners| !owners.contains(owner)) {
            problems.push(format!(
                "durable `{durable}` on `{stream}` has no consumer-info permission in the `{owner}` stanza"
            ));
        }
    }
    let edge = found.iter().find(|stanza| stanza.name == "EDGE");
    match edge {
        Some(edge) => {
            let publish = allow_list(&edge.text, "publish:");
            if publish != ["cmd.>", "$JS.API.>", "$JS.ACK.>"] {
                problems.push(format!("EDGE publish allow is {publish:?}"));
            }
        }
        None => problems.push("ratatoskr.conf has no EDGE stanza".to_owned()),
    }

    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

const FIXTURE_STANZA: &str = r#"
# comment with "quotes" and { braces
{
    nkey: UREPLACE_ME_WITH_THE_PUBLIC_NKEY_OF_RATATOSKR_VAULT_XXXXXXXX
    permissions: {
        publish: { allow: ["evt.vault.backup_policy.acknowledged.v1"] }
        subscribe: { allow: ["_INBOX.>"] }
    }
}
"#;

#[test]
fn comparison_ignores_comments_whitespace_and_the_nkey_token() {
    let reformatted = FIXTURE_STANZA
        .replace('\n', " ")
        .replace("# comment with \"quotes\" and { braces", "")
        .replace("XXXXXXXX", "XXXX");
    let other = stanzas(&reformatted);
    let original = stanzas(FIXTURE_STANZA);

    assert_eq!(original.len(), 1);
    assert_eq!(
        original.first().map(|stanza| stanza.name.as_str()),
        Some("VAULT")
    );
    assert_eq!(other.len(), 1);
    assert_eq!(
        original.first().map(Stanza::normalized),
        other.first().map(Stanza::normalized)
    );
}

#[test]
fn comparison_detects_a_changed_subject() {
    let widened = FIXTURE_STANZA.replace("acknowledged.v1", "acknowledged.v2");
    let original = stanzas(FIXTURE_STANZA);
    let changed = stanzas(&widened);

    assert_ne!(
        original.first().map(Stanza::normalized),
        changed.first().map(Stanza::normalized)
    );
}

#[test]
fn wildcard_rule_accepts_only_ack_kv_direct_get_and_kv_subjects() {
    for allowed in [
        "evt.vault.backup_policy.acknowledged.v1",
        "$JS.ACK.ratatoskr_commands.ratatoskr_vault_backup_policy.>",
        "$JS.API.DIRECT.GET.KV_browser_worker_completions.>",
        "$KV.browser_worker_completions.>",
    ] {
        assert!(is_allowed_wildcard(allowed), "{allowed} should be allowed");
    }
    for refused in ["evt.>", "cmd.>", "$JS.API.>", "$JS.ACK.>", "evt.*.v1"] {
        assert!(!is_allowed_wildcard(refused), "{refused} should be refused");
    }
}

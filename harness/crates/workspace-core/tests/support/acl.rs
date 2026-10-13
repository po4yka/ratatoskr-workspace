//! Reading `ratatoskr-platform/deploy/nats/ratatoskr.conf` as plain-text stanzas, shared by `bus_acl.rs` and `tombstone_acks.rs`. A stanza is a brace block that opens at the start of a file or right after `[` or `,`; the comparison is on what a reviewer read (comments, whitespace and the nkey token ignored), so it does not depend on a NATS parser's idea of meaning.

use crate::checkout::{committed_manifest, require_checkout};
use std::fs;

pub(crate) const PLACEHOLDER_PREFIX: &str = "UREPLACE_ME_WITH_THE_PUBLIC_NKEY_OF_RATATOSKR_";

#[derive(Debug)]
pub(crate) struct Stanza {
    /// Identity name, taken from the nkey placeholder.
    pub(crate) name: String,
    pub(crate) placeholder: String,
    /// Comment-free text of the whole stanza.
    pub(crate) text: String,
}

impl Stanza {
    /// Whitespace-free text with the nkey token removed: what two copies are compared on.
    pub(crate) fn normalized(&self) -> String {
        self.text
            .replace(&self.placeholder, "")
            .split_whitespace()
            .collect()
    }
}

/// Removes `#` comments, leaving quoted strings alone.
pub(crate) fn strip_comments(source: &str) -> String {
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
pub(crate) fn identity_of(placeholder: &str) -> String {
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

pub(crate) fn stanzas(source: &str) -> Vec<Stanza> {
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
pub(crate) fn allow_list(text: &str, marker: &str) -> Vec<String> {
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

pub(crate) fn platform_stanzas() -> Vec<Stanza> {
    let manifest = committed_manifest();
    let root = require_checkout(&manifest, "platform");
    let path = root.join("deploy/nats/ratatoskr.conf");
    let source = fs::read_to_string(&path)
        .unwrap_or_else(|error| panic!("read {}: {error}", path.display()));
    stanzas(&source)
}

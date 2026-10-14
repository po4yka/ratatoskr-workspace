//! Every pinned repository that ships a systemd unit publishes its artifact through the one
//! reusable workflow (openspec `release-artifacts`): exactly one job calls
//! `po4yka/ratatoskr-workspace/.github/workflows/reusable-release-artifact.yml@<40-hex SHA>`.
//!
//! A repository that copies the steps instead, calls the workflow twice, or follows a moving ref
//! such as `@main` fails here, by name. A repository without a unit, or with template units
//! (`*@.service`) only, is not asked to publish, and a template unit may start only a host or npm
//! binary, also through `env` or the `-c` string of a shell.

#![allow(dead_code, clippy::expect_used, clippy::panic)]

#[path = "support/checkout.rs"]
mod checkout;

use checkout::{
    committed_manifest, is_checked_out, repository_root, tracked_files, workspace_root,
};

const CALLEE: &str = "po4yka/ratatoskr-workspace/.github/workflows/reusable-release-artifact.yml@";

#[derive(Debug, PartialEq, Eq)]
struct Calls {
    pinned: usize,
    unpinned: Vec<String>,
}

/// The `uses:` lines of the given workflow files that name the reusable workflow.
fn release_calls(workflows: &[(String, String)]) -> Calls {
    let mut calls = Calls {
        pinned: 0,
        unpinned: Vec::new(),
    };
    for (path, text) in workflows {
        for line in text.lines() {
            let trimmed = line.trim_start().trim_start_matches("- ").trim_start();
            let Some(target) = trimmed.strip_prefix("uses:") else {
                continue;
            };
            let target = target.split_whitespace().next().unwrap_or_default();
            let Some(reference) = target.strip_prefix(CALLEE) else {
                continue;
            };
            if reference.len() == 40 && reference.bytes().all(|b| b.is_ascii_hexdigit()) {
                calls.pinned += 1;
            } else {
                calls.unpinned.push(format!("{path}: @{reference}"));
            }
        }
    }
    calls
}

/// Whether the units a repository ships (paths under `deploy/systemd/`) oblige it to publish. A
/// template unit (`*@.service`) does not: the playbook copies it from the pinned repository, and
/// it starts no binary that the repository builds, which `repository_binaries` holds it to.
fn publishes(units: &[&str]) -> bool {
    units.iter().any(|unit| !unit.ends_with("@.service"))
}

/// The directories a template unit may start a binary from: those of Debian packages, and the npm
/// prefix of `ob` that the `nodejs` role installs. The playbook installs a binary of the artifact
/// in `/usr/local/bin/`, and systemd also searches `/usr/local/bin/` for a bare name, so a template
/// unit that starts either would need the artifact it is exempt from.
const HOST_BINARY_DIRECTORIES: [&str; 5] = [
    "/usr/bin/",
    "/bin/",
    "/usr/sbin/",
    "/sbin/",
    "/opt/ratatoskr-ob/",
];

/// The unit settings that start a command.
const COMMAND_SETTINGS: [&str; 7] = [
    "ExecCondition",
    "ExecStartPre",
    "ExecStart",
    "ExecStartPost",
    "ExecReload",
    "ExecStop",
    "ExecStopPost",
];

/// The prefixes that systemd reads before the binary of a command setting. `@` moves `argv[0]` to
/// the second word. A `|` prefix starts the command through the login shell of the user, so it is
/// not here, and the check refuses it as a path outside the host directories.
const COMMAND_PREFIXES: [char; 5] = ['-', '@', ':', '+', '!'];

/// The shells, by file name, whose `-c` string the check reads.
const SHELLS: [&str; 3] = ["sh", "dash", "bash"];

/// The reserved words of a shell that open or close a compound command. The word after one of
/// them starts a command.
const SHELL_KEYWORDS: [&str; 13] = [
    "if", "then", "else", "elif", "fi", "do", "done", "while", "until", "{", "}", "!", "esac",
];

/// The shell builtins that start no other command. The shell runs them without a search of PATH.
/// `exec` and `command` start the word after them, and `eval`, `.`, `source` and `trap` run a
/// string, so none of these is in the list.
const SHELL_BUILTINS: [&str; 22] = [
    ":", "[", "break", "cd", "continue", "echo", "exit", "export", "false", "local", "printf",
    "pwd", "read", "readonly", "return", "set", "shift", "test", "true", "umask", "unset", "wait",
];

/// The host tools that a shell string may name without a path. systemd gives a unit the PATH
/// `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin`, so the shell finds a binary in
/// `/usr/local/bin/` first. A bare name is safe only while no artifact installs a binary of that
/// name there, which `no_artifact_binary_has_the_name_of_a_bare_host_tool` holds `services.json`
/// to, and while the unit does not set its own PATH.
const BARE_HOST_TOOLS: [&str; 1] = ["cat"];

/// The control and redirection operators of a shell, the longest first.
const SHELL_OPERATORS: [&str; 21] = [
    "<<<", "<<-", "&>>", ";;", ";&", "&&", "||", "<<", ">>", "<&", ">&", "<>", ">|", "&>", ";",
    "&", "|", "(", ")", "<", ">",
];

/// The shell operators whose next word is a file, not a command.
const REDIRECTIONS: [&str; 12] = [
    "<<<", "<<-", "&>>", "<<", ">>", "<&", ">&", "<>", ">|", "&>", "<", ">",
];

/// The commands of a template unit that start something other than a host or npm binary. Each
/// argument is `(path, unit text)`. The check follows `env` to the command it starts and reads
/// every command of a `sh -c` string, so a wrapper cannot hide a binary of the artifact.
fn repository_binaries(units: &[(String, String)]) -> Vec<String> {
    let mut findings = Vec::new();
    for (path, text) in units {
        let settings: Vec<(&str, &str)> = text
            .lines()
            .filter_map(|line| line.trim().split_once('='))
            .map(|(setting, value)| (setting.trim(), value))
            .collect();
        let mut commands = Commands {
            bare_tools: !settings.iter().any(|(setting, value)| {
                matches!(*setting, "ExecSearchPath" | "EnvironmentFile")
                    || (*setting == "Environment" && value.contains("PATH="))
            }),
            refused: Vec::new(),
        };
        for (setting, command) in &settings {
            if !COMMAND_SETTINGS.contains(setting) {
                continue;
            }
            if command.trim_end().ends_with('\\') {
                commands.refused.push(
                    "a command that continues on the next line, which the check does not read"
                        .to_owned(),
                );
            } else {
                let command = command.trim_start();
                let binary = command.trim_start_matches(COMMAND_PREFIXES);
                let mut words = systemd_words(binary);
                let prefixes = command.strip_suffix(binary).unwrap_or_default();
                if prefixes.contains('@') && words.len() > 1 {
                    words.remove(1);
                }
                commands.program(&words);
            }
            for reason in commands.refused.drain(..) {
                findings.push(format!("{path}: {setting}= starts {reason}"));
            }
        }
    }
    findings
}

/// The words of a command setting, as systemd splits them: at white space, without the quotes and
/// the backslash escapes, and with `$$` read as `$`.
fn systemd_words(command: &str) -> Vec<String> {
    let mut words = Vec::new();
    let mut word: Option<String> = None;
    let mut quote = None;
    let mut chars = command.chars();
    while let Some(c) = chars.next() {
        match (quote, c) {
            (None, c) if c.is_whitespace() => words.extend(word.take()),
            (None, '\'' | '"') => {
                quote = Some(c);
                word.get_or_insert_with(String::new);
            }
            (Some(open), c) if c == open => quote = None,
            (_, '\\') => word.get_or_insert_with(String::new).extend(chars.next()),
            (_, c) => word.get_or_insert_with(String::new).push(c),
        }
    }
    words.extend(word);
    words
        .into_iter()
        .map(|word| word.replace("$$", "$"))
        .collect()
}

/// Whether a program word is an absolute path under the host directories that no expansion can
/// change.
fn host_binary(word: &str) -> bool {
    HOST_BINARY_DIRECTORIES
        .iter()
        .any(|directory| word.starts_with(directory))
        && !word.split('/').any(|part| part == "..")
        && !word.contains(['$', '`', '*', '?', '['])
}

/// A word of a shell string without its quotes and backslash escapes.
fn unquote(word: &str) -> String {
    let mut text = String::new();
    let mut quote = None;
    let mut chars = word.chars();
    while let Some(c) = chars.next() {
        match (quote, c) {
            (None, '\'' | '"') => quote = Some(c),
            (Some(open), c) if c == open => quote = None,
            (None | Some('"'), '\\') => text.extend(chars.next()),
            (_, c) => text.push(c),
        }
    }
    text
}

/// Whether a word of a shell command is a variable assignment, `NAME=VALUE`.
fn shell_assignment(word: &str) -> bool {
    word.split_once('=').is_some_and(|(name, _)| {
        name.starts_with(|c: char| c.is_ascii_alphabetic() || c == '_')
            && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
    })
}

/// The index of the closing `quote` at or after `index`, or the end of the string.
fn quote_close(chars: &[char], index: usize, quote: char) -> usize {
    (index..chars.len())
        .find(|&at| chars.get(at) == Some(&quote))
        .unwrap_or(chars.len())
}

/// The index of the `` ` `` that closes a command substitution whose text starts at `index`.
fn backtick_close(chars: &[char], mut index: usize) -> usize {
    while let Some(&c) = chars.get(index) {
        match c {
            '`' => return index,
            '\\' => index += 2,
            _ => index += 1,
        }
    }
    chars.len()
}

/// The index of the `"` that closes a double-quoted string whose text starts at `index`.
fn double_close(chars: &[char], mut index: usize) -> usize {
    while let Some(&c) = chars.get(index) {
        match c {
            '"' => return index,
            '\\' => index += 2,
            '$' if chars.get(index + 1) == Some(&'(') => {
                index = substitution_close(chars, index + 2) + 1;
            }
            '`' => index = backtick_close(chars, index + 1) + 1,
            _ => index += 1,
        }
    }
    chars.len()
}

/// The index of the `)` that closes a `$(` whose text starts at `index`.
fn substitution_close(chars: &[char], mut index: usize) -> usize {
    let mut depth = 0_usize;
    while let Some(&c) = chars.get(index) {
        match c {
            ')' if depth == 0 => return index,
            ')' => {
                depth -= 1;
                index += 1;
            }
            '(' => {
                depth += 1;
                index += 1;
            }
            '\\' => index += 2,
            '\'' => index = quote_close(chars, index + 1, '\'') + 1,
            '"' => index = double_close(chars, index + 1) + 1,
            '`' => index = backtick_close(chars, index + 1) + 1,
            '$' if chars.get(index + 1) == Some(&'(') => {
                index = substitution_close(chars, index + 2) + 1;
            }
            _ => index += 1,
        }
    }
    chars.len()
}

/// A word or an operator of a shell string. A word keeps its quotes.
enum Token {
    Word(String),
    Operator(String),
}

/// Reads the commands that a command setting starts, and keeps the reason for each one that is
/// not a host or npm binary.
struct Commands {
    /// Whether a bare host tool finds its host binary: not when the unit sets its own PATH.
    bare_tools: bool,
    refused: Vec<String>,
}

impl Commands {
    /// A command as systemd or `env` starts it: the program, then its arguments.
    fn program(&mut self, words: &[String]) {
        let Some((program, arguments)) = words.split_first() else {
            return;
        };
        if !host_binary(program) {
            self.refused
                .push(format!("{program}, which is not a host or npm binary"));
            return;
        }
        let name = program.rsplit('/').next().unwrap_or_default();
        if name == "env" {
            self.env(program, arguments);
        } else if SHELLS.contains(&name) {
            self.shell(program, arguments);
        }
    }

    /// `env [OPTION]... [NAME=VALUE]... COMMAND`: the command that `env` starts. GNU `env` reads
    /// each word with a `=` before the command as a variable. An option that the check does not
    /// know, such as `-S`, which splits a string into a new command, is refused.
    fn env(&mut self, program: &str, arguments: &[String]) {
        let mut index = 0;
        while let Some(word) = arguments.get(index) {
            match word.as_str() {
                "-i" | "--ignore-environment" | "-0" | "--null" | "-" | "-v" | "--debug" => {
                    index += 1;
                }
                "-u" | "--unset" | "-C" | "--chdir" => index += 2,
                "--" => {
                    index += 1;
                    break;
                }
                word if word.starts_with("--unset=") || word.starts_with("--chdir=") => {
                    index += 1;
                }
                word if word.starts_with('-') => {
                    self.refused
                        .push(format!("{program} {word}, which the check does not read"));
                    return;
                }
                word if word.contains('=') => index += 1,
                _ => break,
            }
        }
        while arguments.get(index).is_some_and(|word| word.contains('=')) {
            index += 1;
        }
        self.program(arguments.get(index..).unwrap_or_default());
    }

    /// `sh [OPTION]... -c STRING [NAME [ARGUMENT]...]`: the commands of the string. A shell
    /// without `-c` reads a file or its standard input, which the check does not read.
    fn shell(&mut self, program: &str, arguments: &[String]) {
        let mut string = false;
        let mut index = 0;
        while let Some(word) = arguments.get(index) {
            match word.strip_prefix(['-', '+']) {
                Some("-") => {
                    index += 1;
                    break;
                }
                Some("o") => index += 2,
                Some(flags)
                    if !flags.is_empty() && flags.chars().all(|c| c.is_ascii_alphabetic()) =>
                {
                    string |= word.starts_with('-') && flags.contains('c');
                    index += 1;
                }
                _ => break,
            }
        }
        match arguments.get(index) {
            Some(script) if string => self.script(script),
            _ => self.refused.push(format!(
                "{program} without -c, which the check does not read"
            )),
        }
    }

    /// The commands of a shell string: the first word of each simple command after its
    /// assignments, redirections and reserved words, and the commands of each `$(...)` and
    /// `` `...` ``.
    fn script(&mut self, script: &str) {
        let mut words: Vec<String> = Vec::new();
        // The next word is the file of a redirection.
        let mut target = false;
        // The words are the patterns of a `case` item, up to its `)`.
        let mut pattern = false;
        for token in self.tokens(script) {
            match token {
                Token::Word(_) if target => target = false,
                Token::Word(word) if pattern => pattern = word != "esac",
                Token::Word(word) => words.push(word),
                Token::Operator(operator) if REDIRECTIONS.contains(&operator.as_str()) => {
                    target = true;
                }
                Token::Operator(operator) if pattern => pattern = operator != ")",
                Token::Operator(operator) => {
                    pattern = self.simple_command(&words) || operator == ";;" || operator == ";&";
                    words.clear();
                }
            }
        }
        self.simple_command(&words);
    }

    /// One simple command of a shell string, as words with their quotes. Returns whether it is the
    /// head of a `case`, `case WORD in`, after which the patterns of an item come.
    fn simple_command(&mut self, words: &[String]) -> bool {
        let mut words = words;
        while let Some((first, rest)) = words.split_first() {
            if !SHELL_KEYWORDS.contains(&first.as_str()) && !shell_assignment(first) {
                break;
            }
            words = rest;
        }
        match words.first().map(String::as_str) {
            None | Some("for" | "select") => false,
            Some("case") => words.len() == 3 && words.last().is_some_and(|word| word == "in"),
            Some(_) => {
                self.shell_command(words);
                false
            }
        }
    }

    /// A command that a shell runs: a builtin, `exec` or `command` and the command after it, a bare
    /// host tool, or a program.
    fn shell_command(&mut self, words: &[String]) {
        let Some((first, rest)) = words.split_first() else {
            return;
        };
        let name = unquote(first);
        match name.as_str() {
            "exec" => self.shell_command(rest),
            "command" => {
                let options = rest.iter().take_while(|word| word.starts_with('-')).count();
                self.shell_command(rest.get(options..).unwrap_or_default());
            }
            name if SHELL_BUILTINS.contains(&name) => {}
            name if BARE_HOST_TOOLS.contains(&name) => {
                if !self.bare_tools {
                    self.refused.push(format!(
                        "{name}, which the PATH of the unit can find outside the host directories"
                    ));
                }
            }
            _ => self.program(&words.iter().map(|word| unquote(word)).collect::<Vec<_>>()),
        }
    }

    /// The words and operators of a shell string. A newline is the operator `;`, and a comment is
    /// dropped. The commands of each command substitution are read on the way.
    fn tokens(&mut self, script: &str) -> Vec<Token> {
        let chars: Vec<char> = script.chars().collect();
        let mut tokens = Vec::new();
        let mut word = String::new();
        let mut index = 0;
        while let Some(&c) = chars.get(index) {
            match c {
                ' ' | '\t' | '\n' => {
                    if !word.is_empty() {
                        tokens.push(Token::Word(std::mem::take(&mut word)));
                    }
                    if c == '\n' {
                        tokens.push(Token::Operator(";".to_owned()));
                    }
                    index += 1;
                }
                '#' if word.is_empty() => {
                    index = quote_close(&chars, index, '\n');
                }
                ';' | '&' | '|' | '(' | ')' | '<' | '>' => {
                    // A file descriptor, as the 2 of 2>/dev/null, is not a word.
                    if matches!(c, '<' | '>') && word.chars().all(|c| c.is_ascii_digit()) {
                        word.clear();
                    }
                    if !word.is_empty() {
                        tokens.push(Token::Word(std::mem::take(&mut word)));
                    }
                    let rest: String = chars.iter().skip(index).take(3).collect();
                    let operator = SHELL_OPERATORS
                        .iter()
                        .find(|operator| rest.starts_with(**operator))
                        .expect("every operator character is an operator");
                    tokens.push(Token::Operator((*operator).to_owned()));
                    index += operator.len();
                }
                _ => {
                    let end = match c {
                        '\\' => index + 2,
                        '\'' => quote_close(&chars, index + 1, '\'') + 1,
                        '"' => {
                            let close = double_close(&chars, index + 1);
                            self.double_quoted(chars.get(index + 1..close).unwrap_or_default());
                            close + 1
                        }
                        '$' if chars.get(index + 1) == Some(&'(') => {
                            let close = substitution_close(&chars, index + 2);
                            self.substitution(chars.get(index + 2..close).unwrap_or_default());
                            close + 1
                        }
                        '`' => {
                            let close = backtick_close(&chars, index + 1);
                            self.backticks(chars.get(index + 1..close).unwrap_or_default());
                            close + 1
                        }
                        _ => index + 1,
                    }
                    .min(chars.len());
                    word.extend(chars.get(index..end).unwrap_or_default());
                    index = end;
                }
            }
        }
        if !word.is_empty() {
            tokens.push(Token::Word(word));
        }
        tokens
    }

    /// The command substitutions inside a double-quoted string.
    fn double_quoted(&mut self, chars: &[char]) {
        let mut index = 0;
        while let Some(&c) = chars.get(index) {
            match c {
                '\\' => index += 2,
                '$' if chars.get(index + 1) == Some(&'(') => {
                    let close = substitution_close(chars, index + 2);
                    self.substitution(chars.get(index + 2..close).unwrap_or_default());
                    index = close + 1;
                }
                '`' => {
                    let close = backtick_close(chars, index + 1);
                    self.backticks(chars.get(index + 1..close).unwrap_or_default());
                    index = close + 1;
                }
                _ => index += 1,
            }
        }
    }

    /// The commands of a `$(...)`. A `case` inside one is refused: the `)` of its first pattern
    /// would end the substitution for this reader, and the rest would read as arguments.
    fn substitution(&mut self, chars: &[char]) {
        let script: String = chars.iter().collect();
        if script
            .split(|c: char| !c.is_ascii_alphanumeric() && c != '_')
            .any(|word| word == "case")
        {
            self.refused
                .push("a case inside $(...), which the check does not read".to_owned());
        }
        self.script(&script);
    }

    /// The commands of a `` `...` ``, where `\$`, `` \` `` and `\\` stand for the character.
    fn backticks(&mut self, chars: &[char]) {
        let mut script = String::new();
        let mut index = 0;
        while let Some(&c) = chars.get(index) {
            if let ('\\', Some(&next @ ('$' | '`' | '\\'))) = (c, chars.get(index + 1)) {
                script.push(next);
                index += 2;
            } else {
                script.push(c);
                index += 1;
            }
        }
        self.substitution(&script.chars().collect::<Vec<_>>());
    }
}

#[test]
fn every_repository_that_ships_a_unit_publishes_through_the_reusable_workflow() {
    let manifest = committed_manifest();
    let mut failures = Vec::new();
    let mut publishers = 0;
    for repository in manifest.repositories() {
        let root = repository_root(repository);
        assert!(
            is_checked_out(&root),
            "repository `{}` is not checked out at {}; run `git submodule update --init {}`",
            repository.id,
            root.display(),
            repository.path
        );
        let units = tracked_files(&root, "deploy/systemd/*.service");
        if !publishes(
            &units
                .iter()
                .map(|(path, _)| path.as_str())
                .collect::<Vec<_>>(),
        ) {
            continue;
        }
        publishers += 1;
        let calls = release_calls(&tracked_files(&root, ".github/workflows/*.yml"));
        if calls.pinned != 1 || !calls.unpinned.is_empty() {
            failures.push(format!(
                "{}: {} pinned call(s) to the reusable release-artifact workflow, expected exactly 1{}",
                repository.id,
                calls.pinned,
                if calls.unpinned.is_empty() {
                    String::new()
                } else {
                    format!("; not pinned to a commit: {}", calls.unpinned.join(", "))
                }
            ));
        }
    }
    assert!(publishers > 0, "no pinned repository ships a systemd unit");
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
fn a_repository_that_ships_only_template_units_is_not_asked_to_publish() {
    let template = "deploy/systemd/ratatoskr-notes-cleanup@.service";
    let service = "deploy/systemd/ratatoskr-notes.service";
    assert!(!publishes(&[]));
    assert!(!publishes(&[template]));
    assert!(publishes(&[service]));
    assert!(publishes(&[template, service]));
}

#[test]
fn every_template_unit_starts_only_a_host_or_npm_binary() {
    let manifest = committed_manifest();
    let mut findings = Vec::new();
    for repository in manifest.repositories() {
        let root = repository_root(repository);
        assert!(
            is_checked_out(&root),
            "repository `{}` is not checked out at {}; run `git submodule update --init {}`",
            repository.id,
            root.display(),
            repository.path
        );
        for finding in repository_binaries(&tracked_files(&root, "deploy/systemd/*@.service")) {
            findings.push(format!("{}: {finding}", repository.id));
        }
    }
    assert!(findings.is_empty(), "{}", findings.join("\n"));
}

/// The binaries that the playbook installs in `/usr/local/bin/`: one for each service that
/// `services.json` enrolls, and nothing else.
fn artifact_binaries() -> Vec<String> {
    let path = workspace_root().join("deploy/ansible/group_vars/all/services.json");
    let text = std::fs::read_to_string(&path)
        .unwrap_or_else(|error| panic!("{} must exist: {error}", path.display()));
    let inventory: serde_json::Value = serde_json::from_str(&text)
        .unwrap_or_else(|error| panic!("{} is not valid: {error}", path.display()));
    inventory
        .get("ratatoskr_services")
        .and_then(serde_json::Value::as_array)
        .expect("services.json lists ratatoskr_services")
        .iter()
        .map(|service| {
            service
                .get("binary")
                .and_then(serde_json::Value::as_str)
                .expect("each service names its binary")
                .to_owned()
        })
        .collect()
}

/// The bare host tools that a binary of these names in `/usr/local/bin/` would hide.
fn hidden_host_tools(binaries: &[String]) -> Vec<String> {
    binaries
        .iter()
        .filter(|binary| BARE_HOST_TOOLS.contains(&binary.as_str()))
        .cloned()
        .collect()
}

#[test]
fn no_artifact_binary_has_the_name_of_a_bare_host_tool() {
    assert_eq!(
        hidden_host_tools(&["ratatoskr-edge".to_owned(), "cat".to_owned()]),
        vec!["cat".to_owned()]
    );
    let binaries = artifact_binaries();
    assert!(!binaries.is_empty(), "services.json enrolls no binary");
    assert_eq!(hidden_host_tools(&binaries), Vec::<String>::new());
}

#[test]
fn a_template_unit_that_starts_a_repository_binary_is_caught() {
    let unit = |exec: &str| {
        vec![(
            "deploy/systemd/ratatoskr-notes-sync@.service".to_owned(),
            format!("[Unit]\nDescription=x\n\n[Service]\nType=simple\n{exec}\n"),
        )]
    };
    let host = unit(
        "ExecStartPre=+/bin/mkdir -p /run/x\nExecStart=-/usr/bin/ob sync --path /x/%i\n\
         ExecStart=/opt/ratatoskr-ob/node_modules/obsidian-headless/cli.js\nExecStop=",
    );
    assert_eq!(repository_binaries(&host), Vec::<String>::new());

    let built = unit("ExecStart=/usr/local/bin/ratatoskr-notes sync %i");
    assert_eq!(
        repository_binaries(&built),
        vec![
            "deploy/systemd/ratatoskr-notes-sync@.service: ExecStart= starts \
             /usr/local/bin/ratatoskr-notes, which is not a host or npm binary"
                .to_owned()
        ]
    );
    for exec in [
        "ExecStartPre=ratatoskr-notes migrate",
        "ExecStartPost=@/usr/local/lib/ratatoskr/notes x",
        "ExecStop=/usr/bin/../local/bin/ratatoskr-notes stop",
        "ExecStopPost=!!/srv/ratatoskr-notes",
    ] {
        assert_eq!(repository_binaries(&unit(exec)).len(), 1, "{exec}");
    }
}

#[test]
fn a_template_unit_that_starts_a_repository_binary_through_a_wrapper_is_caught() {
    let unit = |exec: &str| {
        vec![(
            "deploy/systemd/ratatoskr-notes-sync@.service".to_owned(),
            format!("[Unit]\nDescription=x\n\n[Service]\nType=oneshot\n{exec}\n"),
        )]
    };
    // The shell itself is a host binary. The notes login unit runs ob, cat and builtins through it.
    for exec in [
        "ExecStart=/bin/sh -c 'set -- --email \"$$(cat \"$$CREDENTIALS_DIRECTORY/email\")\"; \
         mfa=\"$$(cat \"$$CREDENTIALS_DIRECTORY/mfa\")\"; if [ -n \"$$mfa\" ]; then set -- \"$$@\" \
         --mfa \"$$mfa\"; fi; /usr/bin/ob login \"$$@\" < \"$$CREDENTIALS_DIRECTORY/password\" || \
         exit 10; test -s \"$$XDG_CONFIG_HOME/obsidian-headless/auth_token\" || exit 11'",
        "ExecStart=/bin/sh -c '/usr/bin/ob sync-setup --vault \"$$(cat \
         \"$$CREDENTIALS_DIRECTORY/vault\")\" --device-name ratatoskr-%i < \
         \"$$CREDENTIALS_DIRECTORY/e2e\"; status=$$?; case $$status in 0) exit 0 ;; 2) exit 12 ;; \
         *) exit 10 ;; esac'",
        "ExecStart=/usr/bin/env -i HOME=/x /usr/bin/ob sync",
        "ExecStart=/bin/sh -ec 'exec /usr/bin/ob sync 2>/dev/null'",
    ] {
        assert_eq!(
            repository_binaries(&unit(exec)),
            Vec::<String>::new(),
            "{exec}"
        );
    }

    assert_eq!(
        repository_binaries(&unit("ExecStart=/usr/bin/env ratatoskr-notes sync %i")),
        vec![
            "deploy/systemd/ratatoskr-notes-sync@.service: ExecStart= starts ratatoskr-notes, \
             which is not a host or npm binary"
                .to_owned()
        ]
    );
    assert_eq!(
        repository_binaries(&unit(
            "ExecStart=/bin/sh -c '/usr/local/bin/ratatoskr-notes sync %i'"
        )),
        vec![
            "deploy/systemd/ratatoskr-notes-sync@.service: ExecStart= starts \
             /usr/local/bin/ratatoskr-notes, which is not a host or npm binary"
                .to_owned()
        ]
    );
    // systemd puts /usr/local/bin/ first in PATH, so a bare name in a shell command is caught
    // unless the shell runs it as a builtin, and every form below hides one command.
    for exec in [
        "ExecStart=/bin/bash -c 'ratatoskr-notes sync'",
        "ExecStart=/usr/bin/env -i HOME=/x -u PATH ratatoskr-notes",
        "ExecStart=/usr/bin/env -S 'ratatoskr-notes sync'",
        "ExecStart=/bin/sh -c 'exec ratatoskr-notes sync'",
        "ExecStart=/bin/sh -c 'command ratatoskr-notes'",
        "ExecStart=/bin/sh -c 'ob sync'",
        "ExecStart=/bin/sh -c 'test -d /x && /usr/local/bin/ratatoskr-notes'",
        "ExecStart=/bin/sh -c 'x=$$(ratatoskr-notes id); /usr/bin/ob \"$$x\"'",
        "ExecStart=/bin/sh -c '/usr/bin/ob `ratatoskr-notes id`'",
        "ExecStart=/bin/sh -c \"/usr/bin/ob x | ratatoskr-notes y\"",
        "ExecStart=/bin/sh -ec 'if true; then ratatoskr-notes; fi'",
        "ExecStart=/bin/sh -c '(cd /x; ratatoskr-notes)'",
        "ExecStart=/bin/sh -c '$$CMD sync'",
        "ExecStart=/bin/sh -c 'eval ratatoskr-notes'",
        "ExecStart=/bin/sh -c '/usr/bin/env ratatoskr-notes'",
        "ExecStart=/bin/sh -c '/bin/sh -c ratatoskr-notes'",
        "ExecStart=/bin/sh /usr/local/lib/ratatoskr/notes.sh",
        "ExecStart=@/bin/sh sh -c ratatoskr-notes",
        "ExecStart=/bin/sh -c \\\n    'ratatoskr-notes sync'",
        "Environment=PATH=/srv/bin:/usr/bin\nExecStart=/bin/sh -c 'cat /x'",
    ] {
        assert_eq!(repository_binaries(&unit(exec)).len(), 1, "{exec}");
    }
}

#[test]
fn a_moving_ref_and_a_second_call_are_both_caught() {
    let pinned = format!("{CALLEE}{}", "a".repeat(40));
    let one = vec![(
        "ci.yml".to_owned(),
        format!("jobs:\n  release-artifact:\n    uses: {pinned} # main\n"),
    )];
    assert_eq!(
        release_calls(&one),
        Calls {
            pinned: 1,
            unpinned: Vec::new()
        }
    );

    let moving = vec![(
        "ci.yml".to_owned(),
        format!("jobs:\n  release-artifact:\n    uses: {CALLEE}main\n"),
    )];
    assert_eq!(release_calls(&moving).pinned, 0);
    assert_eq!(release_calls(&moving).unpinned, vec!["ci.yml: @main"]);

    let twice = vec![
        ("ci.yml".to_owned(), format!("    uses: {pinned}\n")),
        (
            "release.yml".to_owned(),
            format!("      - uses: {pinned}\n"),
        ),
    ];
    assert_eq!(release_calls(&twice).pinned, 2);
}

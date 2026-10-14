//! Every pinned repository that ships a systemd unit publishes its artifact through the one
//! reusable workflow (openspec `release-artifacts`): exactly one job calls
//! `po4yka/ratatoskr-workspace/.github/workflows/reusable-release-artifact.yml@<40-hex SHA>`.
//!
//! A repository that copies the steps instead, calls the workflow twice, or follows a moving ref
//! such as `@main` fails here, by name. A repository without a unit, or with template units
//! (`*@.service`) only, is not asked to publish. Each command setting of a template unit must start
//! a program of `TEMPLATE_UNIT_PROGRAMS` by its exact path, and each command of a `/bin/sh -c`
//! string must be such a program, a shell builtin, or `cat`. A command or a setting that the check
//! cannot read to that end fails here: `repository_binaries` lists what the check reads.

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

/// The programs that a template unit may start, by exact path: the programs that the notes template
/// units start. The playbook installs a binary of the artifact in `/usr/local/bin/`, so a template
/// unit that starts one would need the artifact it is exempt from. A program in this list must not
/// start a program that its arguments name, because the check does not read them. `/bin/sh` is the
/// one exception: the check reads its `-c` string and holds each command of it to this list.
/// To add a program is a one-line edit that a reviewer must approve against that rule.
const TEMPLATE_UNIT_PROGRAMS: [&str; 3] = ["/usr/bin/ob", "/bin/rm", SHELL];

/// The one shell whose `-c` string the check reads. On Debian it is dash.
const SHELL: &str = "/bin/sh";

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
/// not here, and the check refuses it as a program that is not in `TEMPLATE_UNIT_PROGRAMS`.
const COMMAND_PREFIXES: [char; 5] = ['-', '@', ':', '+', '!'];

/// The options of `/bin/sh` that the check reads. Another option can change what the shell runs:
/// `-i`, for example, makes the shell read the file that ENV names first.
const SHELL_OPTIONS: [char; 4] = ['c', 'e', 'u', 'x'];

/// The settings that can give a command a PATH, ENV or `BASH_ENV` from outside the unit text. A
/// wrong PATH makes `cat` find another program, and ENV or `BASH_ENV` names a file that a shell
/// runs first. `Environment=` and `PassEnvironment=` are refused only when they name one of the
/// three or hold a C escape, which systemd decodes and the check does not.
const ENVIRONMENT_SETTINGS: [&str; 4] = [
    "Environment",
    "PassEnvironment",
    "EnvironmentFile",
    "ExecSearchPath",
];

/// The reserved words of a shell that open or close a compound command. The word after one of
/// them starts a command.
const SHELL_KEYWORDS: [&str; 13] = [
    "if", "then", "else", "elif", "fi", "do", "done", "while", "until", "{", "}", "!", "esac",
];

/// The builtins of dash that start no other command. The shell runs them without a search of PATH.
/// `exec` and `command` start the word after them, and `eval`, `.`, `source` and `trap` run a
/// string, so none of these is in the list. dash has no `[[`, so it is not here either: dash
/// searches PATH for a program of that name.
const SHELL_BUILTINS: [&str; 25] = [
    ":", "[", "break", "cd", "continue", "echo", "exit", "export", "false", "getopts", "kill",
    "local", "printf", "pwd", "read", "readonly", "return", "set", "shift", "test", "true",
    "ulimit", "umask", "unset", "wait",
];

/// The host tools that a shell string may name without a path. systemd gives a unit the PATH
/// `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin`, so the shell finds a binary in
/// `/usr/local/bin/` first. A bare name is safe only while no artifact installs a binary of that
/// name there, which `no_artifact_binary_has_the_name_of_a_bare_host_tool` holds `services.json`
/// to, and while nothing changes PATH: the check refuses a unit that can set PATH and a script that
/// names it.
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

/// The findings for a template unit. Each argument is `(path, unit text)`. The check passes a
/// unit only when it can read every program that the unit starts:
///
/// - each command setting starts a program of `TEMPLATE_UNIT_PROGRAMS`, by its exact path;
/// - `/bin/sh` has `-c` and a string, and only the options of `SHELL_OPTIONS`;
/// - each command of that string, also inside `$(...)`, `` `...` `` and a nested `/bin/sh -c`, is
///   a builtin of `SHELL_BUILTINS`, a tool of `BARE_HOST_TOOLS`, or a program of
///   `TEMPLATE_UNIT_PROGRAMS` by its exact path;
/// - no command setting holds a backslash, a `$` variable or a `;` word, which systemd decodes,
///   expands or reads as a second command before the program starts;
/// - no string names PATH, holds a process substitution or a specifier other than `%i`;
/// - no setting of `ENVIRONMENT_SETTINGS` can set PATH, ENV or `BASH_ENV`, and no line continues on
///   the next line.
///
/// The check does not read drop-in files, the environment of the service manager, or what a
/// program of `TEMPLATE_UNIT_PROGRAMS` does with its arguments. The reader of a shell string is not
/// a full shell parser: it reads the grammar that the notes units use and the forms that the
/// fixtures below hold.
fn repository_binaries(units: &[(String, String)]) -> Vec<String> {
    let mut findings = Vec::new();
    for (path, text) in units {
        let mut settings = Vec::new();
        for line in text.lines().map(str::trim) {
            if line.starts_with(['#', ';']) {
                continue;
            }
            if line.ends_with('\\') {
                findings.push(format!(
                    "{path}: a line continues on the next line, which the check does not read"
                ));
            } else if let Some((setting, value)) = line.split_once('=') {
                settings.push((setting.trim(), value));
            }
        }
        for (setting, value) in &settings {
            if ENVIRONMENT_SETTINGS.contains(setting)
                && (matches!(*setting, "EnvironmentFile" | "ExecSearchPath")
                    || ["PATH", "ENV", "\\"]
                        .iter()
                        .any(|name| value.contains(name)))
            {
                findings.push(format!(
                    "{path}: {setting}= can set PATH, ENV or BASH_ENV, which the check does not \
                     read"
                ));
            }
            if !COMMAND_SETTINGS.contains(setting) {
                continue;
            }
            let mut commands = Commands {
                refused: Vec::new(),
            };
            let command = value.trim_start();
            let binary = command.trim_start_matches(COMMAND_PREFIXES);
            match systemd_words(binary) {
                Ok(mut words) => {
                    let prefixes = command.strip_suffix(binary).unwrap_or_default();
                    if prefixes.contains('@') && words.len() > 1 {
                        words.remove(1);
                    }
                    commands.program(&words);
                }
                Err(reason) => commands.refused.push(reason.to_owned()),
            }
            for reason in commands.refused {
                findings.push(format!("{path}: {setting}= starts {reason}"));
            }
        }
    }
    findings
}

/// The words of a command setting, as systemd splits them: at white space, without the quotes, and
/// with `$$` read as `$`. A backslash, a `$` variable and a `;` word are refused: systemd decodes
/// the escape, puts the value of the variable in the word, or starts a second command, and the
/// check does not follow any of them.
fn systemd_words(command: &str) -> Result<Vec<String>, &'static str> {
    if command.contains('\\') {
        return Err("a command with a backslash, which systemd decodes and the check does not");
    }
    let mut words = Vec::new();
    let mut word: Option<String> = None;
    let mut quoted = false;
    let mut quote = None;
    // A space at the end closes the last word.
    let mut chars = command.chars().chain([' ']).peekable();
    while let Some(c) = chars.next() {
        match (quote, c) {
            (None, c) if c.is_whitespace() => {
                if !quoted && word.as_deref() == Some(";") {
                    return Err("a second command after a ; word, which the check does not read");
                }
                words.extend(word.take());
                quoted = false;
            }
            (None, '\'' | '"') => {
                quote = Some(c);
                quoted = true;
                word.get_or_insert_with(String::new);
            }
            (Some(open), c) if c == open => quote = None,
            (_, '$') if chars.next_if_eq(&'$').is_none() => {
                return Err(
                    "a command with a $ variable, which systemd expands and the check \
                            does not read",
                );
            }
            (_, c) => word.get_or_insert_with(String::new).push(c),
        }
    }
    words.extend(word);
    Ok(words)
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

/// Reads the commands that a command setting starts, and keeps the reason for each one that the
/// check refuses.
struct Commands {
    refused: Vec<String>,
}

impl Commands {
    /// A command as systemd or a shell starts it: the program, then its arguments.
    fn program(&mut self, words: &[String]) {
        let Some((program, arguments)) = words.split_first() else {
            return;
        };
        if !TEMPLATE_UNIT_PROGRAMS.contains(&program.as_str()) {
            self.refused.push(format!(
                "{program}, which is not a program that a template unit may start"
            ));
        } else if program == SHELL {
            self.shell(program, arguments);
        }
    }

    /// `/bin/sh [OPTION]... -c STRING [NAME [ARGUMENT]...]`: the commands of the string. A shell
    /// without `-c` reads a file or its standard input, and an option outside `SHELL_OPTIONS` can
    /// change what it runs, so the check refuses both.
    fn shell(&mut self, program: &str, arguments: &[String]) {
        let mut string = false;
        let mut index = 0;
        while let Some(options) = arguments.get(index).and_then(|word| word.strip_prefix('-')) {
            index += 1;
            if options == "-" {
                break;
            }
            if options.is_empty() || !options.chars().all(|c| SHELL_OPTIONS.contains(&c)) {
                self.refused.push(format!(
                    "{program} -{options}, which the check does not read"
                ));
                return;
            }
            string |= options.contains('c');
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
    /// `` `...` ``. A string that names PATH can make a bare tool find another program, and
    /// systemd replaces a specifier other than `%i` with text that the check does not read, so the
    /// check refuses both and reads no further.
    fn script(&mut self, script: &str) {
        if script
            .split(|c: char| !c.is_ascii_alphanumeric() && c != '_')
            .any(|word| word == "PATH")
        {
            self.refused
                .push("a string that names PATH, which the check does not follow".to_owned());
            return;
        }
        let mut chars = script.chars();
        while let Some(c) = chars.next() {
            if c == '%' && !matches!(chars.next(), Some('%' | 'i')) {
                self.refused.push(
                    "a string with a specifier other than %i, which the check does not read"
                        .to_owned(),
                );
                return;
            }
        }
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
            name if SHELL_BUILTINS.contains(&name) || BARE_HOST_TOOLS.contains(&name) => {}
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
                    if c == '('
                        && index
                            .checked_sub(1)
                            .and_then(|at| chars.get(at))
                            .is_some_and(|before| matches!(before, '<' | '>'))
                    {
                        self.refused.push(
                            "a process substitution, which the check does not read".to_owned(),
                        );
                    }
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
fn every_template_unit_starts_only_an_allowed_program() {
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
    // /usr/bin/ob starts with #!/usr/bin/env node, so env finds a node in /usr/local/bin/ first.
    assert_eq!(
        hidden_host_tools(&["ratatoskr-edge".to_owned(), "node".to_owned()]),
        vec!["node".to_owned()]
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
        "ExecStart=-/usr/bin/ob sync-unlink --path /x/%i/tree\n\
         ExecStart=/bin/rm -rf -- /x/%i/tree /x/%i/ob-home\nExecStop=",
    );
    assert_eq!(repository_binaries(&host), Vec::<String>::new());

    let built = unit("ExecStart=/usr/local/bin/ratatoskr-notes sync %i");
    assert_eq!(
        repository_binaries(&built),
        vec![
            "deploy/systemd/ratatoskr-notes-sync@.service: ExecStart= starts \
             /usr/local/bin/ratatoskr-notes, which is not a program that a template unit may \
             start"
                .to_owned()
        ]
    );
    for exec in [
        "ExecStartPre=ratatoskr-notes migrate",
        "ExecStartPost=@/usr/local/lib/ratatoskr/notes x",
        "ExecStop=/usr/bin/../local/bin/ratatoskr-notes stop",
        "ExecStopPost=!!/srv/ratatoskr-notes",
        // No notes unit starts these host and npm programs, so the allow-list does not hold them.
        "ExecStartPre=+/bin/mkdir -p /run/x",
        "ExecStart=/opt/ratatoskr-ob/node_modules/obsidian-headless/cli.js",
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
    // /bin/sh is on the allow-list. The notes login unit runs ob, cat and builtins through it.
    for exec in [
        "ExecStart=/bin/sh -c 'set -- --email \"$$(cat \"$$CREDENTIALS_DIRECTORY/email\")\"; \
         mfa=\"$$(cat \"$$CREDENTIALS_DIRECTORY/mfa\")\"; if [ -n \"$$mfa\" ]; then set -- \"$$@\" \
         --mfa \"$$mfa\"; fi; /usr/bin/ob login \"$$@\" < \"$$CREDENTIALS_DIRECTORY/password\" || \
         exit 10; test -s \"$$XDG_CONFIG_HOME/obsidian-headless/auth_token\" || exit 11'",
        "ExecStart=/bin/sh -c '/usr/bin/ob sync-setup --vault \"$$(cat \
         \"$$CREDENTIALS_DIRECTORY/vault\")\" --device-name ratatoskr-%i < \
         \"$$CREDENTIALS_DIRECTORY/e2e\"; status=$$?; case $$status in 0) exit 0 ;; 2) exit 12 ;; \
         *) exit 10 ;; esac'",
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
            "deploy/systemd/ratatoskr-notes-sync@.service: ExecStart= starts /usr/bin/env, \
             which is not a program that a template unit may start"
                .to_owned()
        ]
    );
    assert_eq!(
        repository_binaries(&unit(
            "ExecStart=/bin/sh -c '/usr/local/bin/ratatoskr-notes sync %i'"
        )),
        vec![
            "deploy/systemd/ratatoskr-notes-sync@.service: ExecStart= starts \
             /usr/local/bin/ratatoskr-notes, which is not a program that a template unit may \
             start"
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
fn a_template_unit_that_hides_a_program_from_the_check_is_caught() {
    let unit = |exec: &str| {
        vec![(
            "deploy/systemd/ratatoskr-notes-sync@.service".to_owned(),
            format!("[Unit]\nDescription=x\n\n[Service]\nType=oneshot\n{exec}\n"),
        )]
    };
    let wrong: Vec<String> = [
        // A host program that starts the program in its arguments.
        "ExecStart=/usr/bin/timeout 5 /usr/local/bin/ratatoskr-notes",
        "ExecStart=/usr/bin/nice -n 5 /usr/local/bin/ratatoskr-notes",
        "ExecStart=/usr/bin/nohup /usr/local/bin/ratatoskr-notes",
        "ExecStart=/usr/bin/setpriv --reuid=1 /usr/local/bin/ratatoskr-notes",
        "ExecStart=/usr/bin/flock /run/x /usr/local/bin/ratatoskr-notes",
        "ExecStart=/usr/bin/stdbuf -oL /usr/local/bin/ratatoskr-notes",
        "ExecStart=/usr/bin/systemd-cat /usr/local/bin/ratatoskr-notes",
        "ExecStart=/usr/bin/systemd-run --wait /usr/local/bin/ratatoskr-notes",
        "ExecStart=/usr/bin/xargs -a /x /usr/local/bin/ratatoskr-notes",
        "ExecStart=/usr/bin/find /x -exec /usr/local/bin/ratatoskr-notes {} +",
        "ExecStart=/usr/bin/node -e 'require(\"child_process\").execSync(\"ratatoskr-notes\")'",
        "ExecStart=/usr/bin/python3 -c 'import os; os.system(\"ratatoskr-notes\")'",
        "ExecStart=/bin/busybox sh -c ratatoskr-notes",
        "ExecStart=/bin/zsh -c ratatoskr-notes",
        "ExecStart=/bin/bash -c '/usr/bin/ob sync'",
        "ExecStart=/bin/dash -c '/usr/bin/ob sync'",
        "ExecStart=/bin/sh -c '/usr/bin/timeout 5 /usr/local/bin/ratatoskr-notes'",
        "ExecStart=/bin/sh -c 'nice ratatoskr-notes'",
        "ExecStart=/usr/bin/env -i /usr/bin/nohup /usr/local/bin/ratatoskr-notes",
        "ExecStart=/usr/bin/env -i HOME=/x /usr/bin/ob sync",
        // An interactive shell reads the file that ENV names before the string.
        "ExecStart=/bin/sh -ic '/usr/bin/ob sync'",
        // dash has no [[, so it searches PATH for a program of that name.
        "ExecStart=/bin/sh -c '[[ -n x ]] && /usr/bin/ob sync'",
        // systemd decodes a C escape before the shell reads the string.
        "ExecStart=/bin/sh -c 'echo a\\x3b/usr/local/bin/ratatoskr-notes'",
        "ExecStart=/bin/sh -c 'echo a\\n/usr/local/bin/ratatoskr-notes'",
        "ExecStart=/bin/sh -c 'echo a\\073/usr/local/bin/ratatoskr-notes'",
        "ExecStart=/bin/sh -c 'echo\\s/usr/bin/ob'",
        // A process substitution starts a command.
        "ExecStart=/bin/sh -c 'cat <(/usr/local/bin/ratatoskr-notes)'",
        "ExecStart=/bin/sh -c '/usr/bin/ob sync >(/usr/local/bin/ratatoskr-notes)'",
        // systemd reads a ; word as the start of a second command.
        "ExecStart=/usr/bin/ob sync ; /usr/local/bin/ratatoskr-notes",
        "ExecStart=/bin/rm -rf /x ; /usr/local/bin/ratatoskr-notes",
        // systemd puts the value of a variable in the string before the shell reads it.
        "Environment=\"HOME=a;/usr/local/bin/ratatoskr-notes\"\nExecStart=/bin/sh -c 'echo ${HOME}'",
        // A PATH that the script or the unit sets makes cat find another program.
        "ExecStart=/bin/sh -c 'PATH=/srv/bin cat /x'",
        "ExecStart=/bin/sh -c 'export PATH=/srv/bin; cat /x'",
        "ExecStart=/bin/sh -c 'read PATH < /x; cat /y'",
        "ExecStart=/bin/sh -c '/usr/bin/env PATH=/srv/bin cat /x'",
        "ExecStart=/usr/bin/env PATH=/srv/bin /bin/sh -c 'cat /x'",
        "PassEnvironment=PATH\nExecStart=/bin/sh -c 'cat /x'",
        "EnvironmentFile=/etc/x\nExecStart=/usr/bin/ob sync",
        "Environment=A=1 \\\n PATH=/srv/bin\nExecStart=/bin/sh -c 'cat /x'",
        // A brace or a specifier in a program word.
        "ExecStart=/bin/sh -c '/usr/bin/{ob,../local/bin/ratatoskr-notes}'",
        "ExecStart=/bin/sh -c '/usr/bin/%I'",
        "ExecStart=/opt/ratatoskr-ob/%I",
        "ExecStart=/bin/sh -c 'echo %I'",
        // The shell reads the file that BASH_ENV or ENV names.
        "Environment=BASH_ENV=/srv/x\nExecStart=/bin/sh -c 'cat /x'",
        "Environment=ENV=/srv/x\nExecStart=/bin/sh -c 'cat /x'",
    ]
    .into_iter()
    .filter_map(|exec| {
        let findings = repository_binaries(&unit(exec));
        (findings.len() != 1).then(|| format!("{exec}: {findings:?}"))
    })
    .collect();
    assert!(
        wrong.is_empty(),
        "each fixture must give exactly one finding:\n{}",
        wrong.join("\n")
    );
}

#[test]
fn a_template_unit_that_sets_an_unlisted_variable_or_a_mount_is_caught() {
    let unit = |setting: &str| {
        vec![(
            "deploy/systemd/ratatoskr-notes-sync@.service".to_owned(),
            format!("[Service]\nType=oneshot\n{setting}\nExecStart=/usr/bin/ob sync\n"),
        )]
    };
    let wrong: Vec<String> = [
        // Node.js reads a startup variable before ob runs, and the dynamic linker reads its
        // variables before node runs.
        "Environment=NODE_OPTIONS=--require=/srv/x.js",
        "Environment=NODE_PATH=/srv/lib",
        "Environment=LD_PRELOAD=/srv/x.so",
        "Environment=LD_LIBRARY_PATH=/srv/lib",
        "Environment=LD_AUDIT=/srv/x.so",
        "Environment=HOME=/x NODE_OPTIONS=--require=/srv/x.js",
        "Environment=\"HOME=/x y\" 'NODE_OPTIONS=--require=/srv/x.js'",
        "PassEnvironment=HOME NODE_OPTIONS",
        // Node.js does not read NODE_ENV, but a package can build a file path from its value.
        "Environment=NODE_ENV=production",
        // A word that is not NAME=VALUE.
        "Environment=1X=y",
        "Environment=%iX=y",
        // A mount or root setting can put another file at /usr/bin/ob, /bin/sh or /bin/rm, or
        // hide /usr/bin/env.
        "BindPaths=/srv/x:/usr/bin/ob",
        "BindReadOnlyPaths=/srv/sh:/bin/sh",
        "RootDirectory=/srv/root",
        "RootImage=/srv/x.raw",
        "RootImageOptions=root:nosuid",
        "MountImages=/srv/x.raw:/usr",
        "ExtensionImages=/srv/x.raw",
        "ExtensionDirectories=/srv/x",
        "TemporaryFileSystem=/usr/bin",
    ]
    .into_iter()
    .filter_map(|setting| {
        let findings = repository_binaries(&unit(setting));
        (findings.len() != 1).then(|| format!("{setting}: {findings:?}"))
    })
    .collect();
    assert!(
        wrong.is_empty(),
        "each fixture must give exactly one finding:\n{}",
        wrong.join("\n")
    );

    // A listed variable, a setting that only removes a variable, and a setting that only
    // restricts the file system pass.
    for setting in [
        "Environment=XDG_CONFIG_HOME=/var/lib/x/%i",
        "Environment=HOME=/x XDG_CONFIG_HOME=/var/lib/x/%i",
        "Environment=\"HOME=/x y\" 'XDG_CONFIG_HOME=/y'",
        "PassEnvironment=HOME XDG_CONFIG_HOME",
        "UnsetEnvironment=NODE_OPTIONS",
        "ReadWritePaths=-/var/lib/x/%i",
        "ReadOnlyPaths=/var/lib/x",
        "InaccessiblePaths=/var/lib/y",
        "ProtectSystem=strict",
        "PrivateTmp=yes",
    ] {
        assert_eq!(
            repository_binaries(&unit(setting)),
            Vec::<String>::new(),
            "{setting}"
        );
    }
}

#[test]
fn a_shell_builtin_that_starts_no_command_passes() {
    let unit = vec![(
        "deploy/systemd/ratatoskr-notes-sync@.service".to_owned(),
        "[Service]\nExecStart=/bin/sh -c 'ulimit -n 1024; kill -0 1 || exit 1; \
         while getopts ab o; do :; done; /usr/bin/ob sync'\n"
            .to_owned(),
    )];
    assert_eq!(repository_binaries(&unit), Vec::<String>::new());
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

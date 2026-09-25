//! Ratatoskr workspace snapshot command-line interface.

#![forbid(unsafe_code)]
#![deny(rustdoc::broken_intra_doc_links)]

use std::env;
use std::fs;
use std::io::{self, Write as _};
use std::path::{Path, PathBuf};
use std::process;
use workspace_core::{
    FleetClass, FleetInitReport, GitTopologyReport, ManifestDiagnostic, ValidatedManifest,
    compare_workspace_lock, dependency_order, fleet_init, generate_workspace_lock,
    inspect_baseline, inspect_git_topology, render_workspace_lock, validate_manifest,
    write_workspace_lock_atomic,
};

const EXIT_VALIDATION: u8 = 2;
const EXIT_USAGE: u8 = 64;
const EXIT_IO: u8 = 74;

struct FleetInitArguments<'a> {
    target: &'a str,
    from: Option<&'a str>,
    force: bool,
}

struct SnapshotContext {
    manifest_source: String,
    manifest: ValidatedManifest,
    topology: GitTopologyReport,
}

fn main() {
    process::exit(i32::from(run()));
}

fn run() -> u8 {
    let arguments = env::args().skip(1).collect::<Vec<_>>();
    let root = match env::var_os("RATATOSKR_WORKSPACE_ROOT") {
        Some(root) => PathBuf::from(root),
        None => match env::current_dir() {
            Ok(root) => root,
            Err(error) => return emit_io_error("workspace.current-directory", &error),
        },
    };

    match arguments.as_slice() {
        [group, command] if group == "manifest" && command == "check" => manifest_check(&root),
        [group, command] if group == "lock" && command == "check" => lock_check(&root),
        [group, command, flag, output]
            if group == "lock" && command == "generate" && flag == "--output" =>
        {
            lock_generate(&root, output)
        }
        [command] if command == "status" => status(&root),
        [command] if command == "doctor" => doctor(&root),
        [group, command, rest @ ..] if group == "fleet" && command == "init" => {
            parse_fleet_init(rest).map_or_else(usage, |arguments| fleet(&root, &arguments))
        }
        _ => usage(),
    }
}

fn usage() -> u8 {
    let message = concat!(
        "usage: ws manifest check | ws lock generate --output PATH | ",
        "ws lock check | ws status | ws doctor | ",
        "ws fleet init TARGET [--from SOURCE] [--force]\n"
    );
    write_stderr(message).map_or(EXIT_IO, |()| EXIT_USAGE)
}

fn parse_fleet_init(arguments: &[String]) -> Option<FleetInitArguments<'_>> {
    let mut target = None;
    let mut from = None;
    let mut force = false;
    let mut arguments = arguments.iter();
    while let Some(argument) = arguments.next() {
        match argument.as_str() {
            "--force" if !force => force = true,
            "--from" if from.is_none() => from = Some(arguments.next()?.as_str()),
            value if !value.starts_with("--") && target.is_none() => target = Some(value),
            _ => return None,
        }
    }
    Some(FleetInitArguments {
        target: target?,
        from,
        force,
    })
}

fn fleet(root: &Path, arguments: &FleetInitArguments<'_>) -> u8 {
    let target = workspace_relative_path(root, arguments.target);
    let source = arguments.from.map_or_else(
        || root.to_owned(),
        |from| workspace_relative_path(root, from),
    );
    match fleet_init(&source, &target, arguments.force) {
        Ok(report) => write_stdout(&render_fleet_report(&report)).map_or(EXIT_IO, |()| 0),
        Err(diagnostics) => {
            let status = if diagnostics
                .iter()
                .any(|diagnostic| diagnostic.code == "fleet.io")
            {
                EXIT_IO
            } else {
                EXIT_VALIDATION
            };
            emit_diagnostics(&diagnostics, OutputStream::Stderr).map_or(EXIT_IO, |()| status)
        }
    }
}

fn render_fleet_report(report: &FleetInitReport) -> String {
    let class = match report.class {
        FleetClass::Rust => "Rust",
        FleetClass::NonRust => "non-Rust",
    };
    let mut lines = vec![format!("fleet: {class} target")];
    lines.extend(
        report
            .copied
            .iter()
            .map(|path| format!("fleet: copied {path}")),
    );
    lines.push(format!("fleet: unchanged {} files", report.unchanged.len()));
    lines.extend(
        report
            .absent_from_source
            .iter()
            .map(|path| format!("fleet: absent from the source: {path}")),
    );
    lines.extend(report.withheld.iter().map(|path| {
        format!(
            "fleet: not copied: {path} (the source keeps its Rust below the root, so its copy is not the fleet form; pass --from a repository with a root Cargo.toml)"
        )
    }));
    lines.extend(
        report
            .still_missing
            .iter()
            .map(|path| format!("fleet: still missing, write by hand: {path}")),
    );
    lines.push(String::new());
    lines.join("\n")
}

fn manifest_check(root: &Path) -> u8 {
    match load_context(root) {
        Ok(context) if context.topology.diagnostics.is_empty() => {
            write_stdout("manifest: valid\n").map_or(EXIT_IO, |()| 0)
        }
        Ok(context) => emit_validation(&context.topology.diagnostics, OutputStream::Stderr),
        Err(diagnostics) => emit_validation(&diagnostics, OutputStream::Stderr),
    }
}

fn lock_check(root: &Path) -> u8 {
    let context = match load_context(root) {
        Ok(context) if context.topology.diagnostics.is_empty() => context,
        Ok(context) => {
            return emit_validation(&context.topology.diagnostics, OutputStream::Stderr);
        }
        Err(diagnostics) => return emit_validation(&diagnostics, OutputStream::Stderr),
    };
    let expected = match generate_workspace_lock(
        root,
        &context.manifest_source,
        &context.manifest,
        &context.topology,
    ) {
        Ok(lock) => lock,
        Err(diagnostics) => return emit_validation(&diagnostics, OutputStream::Stderr),
    };
    let committed = match fs::read_to_string(root.join("workspace.lock")) {
        Ok(source) => source,
        Err(error) => return emit_io_error("lock.read", &error),
    };
    let diagnostics = compare_workspace_lock(&expected, &committed);
    if diagnostics.is_empty() {
        write_stdout("lock: current\n").map_or(EXIT_IO, |()| 0)
    } else {
        emit_validation(&diagnostics, OutputStream::Stderr)
    }
}

fn lock_generate(root: &Path, output: &str) -> u8 {
    let context = match load_context(root) {
        Ok(context) if context.topology.diagnostics.is_empty() => context,
        Ok(context) => {
            return emit_validation(&context.topology.diagnostics, OutputStream::Stderr);
        }
        Err(diagnostics) => return emit_validation(&diagnostics, OutputStream::Stderr),
    };
    let lock = match generate_workspace_lock(
        root,
        &context.manifest_source,
        &context.manifest,
        &context.topology,
    ) {
        Ok(lock) => lock,
        Err(diagnostics) => return emit_validation(&diagnostics, OutputStream::Stderr),
    };
    let output = workspace_relative_path(root, output);
    if let Err(error) = write_workspace_lock_atomic(&output, &render_workspace_lock(&lock)) {
        return emit_io_error("lock.write", &error);
    }
    write_stdout(&format!("lock: wrote {}\n", output.display())).map_or(EXIT_IO, |()| 0)
}

fn status(root: &Path) -> u8 {
    let context = match load_context(root) {
        Ok(context) => context,
        Err(diagnostics) => return emit_validation(&diagnostics, OutputStream::Stdout),
    };
    let baseline = inspect_baseline(root, &context.topology);
    let mut diagnostics = context.topology.diagnostics;
    diagnostics.extend(baseline.diagnostics);
    if diagnostics.is_empty() {
        write_stdout("status: clean\n").map_or(EXIT_IO, |()| 0)
    } else {
        emit_diagnostics(&diagnostics, OutputStream::Stdout).map_or(EXIT_IO, |()| 0)
    }
}

fn doctor(root: &Path) -> u8 {
    let context = match load_context(root) {
        Ok(context) => context,
        Err(diagnostics) => return emit_validation(&diagnostics, OutputStream::Stderr),
    };
    let baseline = inspect_baseline(root, &context.topology);
    let lock_diagnostics = if context.topology.diagnostics.is_empty() {
        doctor_lock_diagnostics(root, &context)
    } else {
        Vec::new()
    };
    let mut diagnostics = context.topology.diagnostics;
    diagnostics.extend(baseline.diagnostics);
    diagnostics.extend(lock_diagnostics);
    if diagnostics.is_empty() {
        write_stdout("doctor: healthy\n").map_or(EXIT_IO, |()| 0)
    } else {
        emit_validation(&diagnostics, OutputStream::Stderr)
    }
}

fn doctor_lock_diagnostics(root: &Path, context: &SnapshotContext) -> Vec<ManifestDiagnostic> {
    let expected = match generate_workspace_lock(
        root,
        &context.manifest_source,
        &context.manifest,
        &context.topology,
    ) {
        Ok(lock) => lock,
        Err(diagnostics) => return diagnostics,
    };
    match fs::read_to_string(root.join("workspace.lock")) {
        Ok(source) => compare_workspace_lock(&expected, &source),
        Err(error) => vec![ManifestDiagnostic {
            code: "lock.read",
            message: error.to_string(),
        }],
    }
}

fn load_context(root: &Path) -> Result<SnapshotContext, Vec<ManifestDiagnostic>> {
    let manifest_source = fs::read_to_string(root.join("workspace.toml")).map_err(|error| {
        vec![ManifestDiagnostic {
            code: "manifest.read",
            message: error.to_string(),
        }]
    })?;
    let manifest = validate_manifest(&manifest_source)?;
    dependency_order(&manifest)?;
    let topology = inspect_git_topology(root, &manifest);
    Ok(SnapshotContext {
        manifest_source,
        manifest,
        topology,
    })
}

fn workspace_relative_path(root: &Path, output: &str) -> PathBuf {
    let output = PathBuf::from(output);
    if output.is_absolute() {
        output
    } else {
        root.join(output)
    }
}

#[derive(Copy, Clone)]
enum OutputStream {
    Stdout,
    Stderr,
}

fn emit_validation(diagnostics: &[ManifestDiagnostic], stream: OutputStream) -> u8 {
    emit_diagnostics(diagnostics, stream).map_or(EXIT_IO, |()| EXIT_VALIDATION)
}

fn emit_diagnostics(diagnostics: &[ManifestDiagnostic], stream: OutputStream) -> io::Result<()> {
    let output = diagnostics
        .iter()
        .map(|diagnostic| format!("{}: {}", diagnostic.code, diagnostic.message))
        .collect::<Vec<_>>()
        .join("\n");
    let output = format!("{output}\n");
    match stream {
        OutputStream::Stdout => write_stdout(&output),
        OutputStream::Stderr => write_stderr(&output),
    }
}

fn emit_io_error(code: &'static str, error: &io::Error) -> u8 {
    let diagnostic = ManifestDiagnostic {
        code,
        message: error.to_string(),
    };
    emit_diagnostics(&[diagnostic], OutputStream::Stderr).map_or(EXIT_IO, |()| EXIT_IO)
}

fn write_stdout(message: &str) -> io::Result<()> {
    io::stdout().lock().write_all(message.as_bytes())
}

fn write_stderr(message: &str) -> io::Result<()> {
    io::stderr().lock().write_all(message.as_bytes())
}

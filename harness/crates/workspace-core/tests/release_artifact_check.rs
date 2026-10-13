//! The artifact check of `reusable-release-artifact.yml`, run exactly as the workflow runs it.
//!
//! A reusable workflow cannot be called in a way that is expected to fail: a failed job fails the
//! caller's run. So the decision whether to publish lives in one Python block between two marker
//! comments in the workflow, and this test lifts that block out and runs it against fixtures it
//! generates. Editing the block in the workflow is editing what this test runs; there is no copy.
//!
//! The fixtures are synthetic ELF files: a 64-byte header with the machine field set, followed by
//! the `GLIBC_x.y` version strings a dynamic binary carries in `.dynstr`. That is all the check
//! reads, so a real compiler is not needed to exercise every refusal.

#![allow(dead_code, clippy::expect_used, clippy::panic)]

#[path = "support/checkout.rs"]
mod checkout;

use checkout::workspace_root;
use sha2::{Digest, Sha256};
use std::fs;
use std::path::PathBuf;
use std::process::Command;

const WORKFLOW: &str = ".github/workflows/reusable-release-artifact.yml";
const BEGIN: &str = "# BEGIN artifact-check";
const END: &str = "# END artifact-check";

const EM_AARCH64: u16 = 183;
const EM_X86_64: u16 = 62;

/// The Python block between the markers, with the YAML indentation removed.
fn check_script() -> String {
    let path = workspace_root().join(WORKFLOW);
    let source = fs::read_to_string(&path)
        .unwrap_or_else(|error| panic!("{} must exist: {error}", path.display()));
    let lines = source.lines().collect::<Vec<_>>();
    let begin = lines
        .iter()
        .position(|line| line.trim() == BEGIN)
        .unwrap_or_else(|| panic!("{WORKFLOW} has no `{BEGIN}` line"));
    let end = lines
        .iter()
        .position(|line| line.trim() == END)
        .unwrap_or_else(|| panic!("{WORKFLOW} has no `{END}` line"));
    assert!(begin < end, "`{BEGIN}` must come before `{END}`");
    let first = lines.get(begin).copied().unwrap_or_default();
    let indent = first.len() - first.trim_start().len();
    lines
        .get(begin..=end)
        .unwrap_or_default()
        .iter()
        .map(|line| line.get(indent..).unwrap_or("").trim_end())
        .collect::<Vec<_>>()
        .join("\n")
}

/// A minimal little-endian ELF64 file for `machine` that requires the given glibc versions.
fn elf(machine: u16, glibc: &[&str]) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(128);
    bytes.extend_from_slice(b"\x7fELF");
    bytes.extend_from_slice(&[2, 1, 1]); // ELFCLASS64, little endian, EV_CURRENT
    bytes.resize(16, 0);
    bytes.extend_from_slice(&3_u16.to_le_bytes()); // ET_DYN
    bytes.extend_from_slice(&machine.to_le_bytes());
    bytes.resize(64, 0);
    bytes.extend_from_slice(b"\0libc.so.6\0");
    for version in glibc {
        bytes.extend_from_slice(version.as_bytes());
        bytes.push(0);
    }
    bytes
}

struct Case {
    root: PathBuf,
}

impl Case {
    fn new(name: &str) -> Self {
        let root = std::env::temp_dir().join(format!(
            "ratatoskr-artifact-check-{}-{name}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("units")).expect("units dir");
        fs::create_dir_all(root.join("out")).expect("out dir");
        Self { root }
    }

    fn unit(&self, name: &str, exec_start: &str) -> &Self {
        let body = format!(
            "[Unit]\nDescription=fixture\n\n[Service]\nType=exec\n\
             ExecStartPre=/usr/local/bin/ignored-pre check-config\nExecStart={exec_start}\n\n\
             [Install]\nWantedBy=ratatoskr.target\n"
        );
        fs::write(self.root.join("units").join(name), body).expect("write unit");
        self
    }

    fn binary(&self, name: &str, bytes: &[u8]) -> &Self {
        fs::write(self.out().join(name), bytes).expect("write binary");
        self
    }

    fn out(&self) -> PathBuf {
        self.root.join("out")
    }

    /// Runs the workflow's check; returns (success, combined output).
    fn run(&self) -> (bool, String) {
        let script = self.root.join("check.py");
        fs::write(&script, check_script()).expect("write script");
        let output = Command::new("python3")
            .arg(&script)
            .arg(self.root.join("units"))
            .arg(self.out())
            .output()
            .expect("python3 runs");
        let text = format!(
            "{}{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        (output.status.success(), text)
    }
}

impl Drop for Case {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

fn good() -> Vec<u8> {
    elf(
        EM_AARCH64,
        &["GLIBC_2.17", "GLIBC_2.34", "GLIBC_2.36", "GLIBC_PRIVATE"],
    )
}

fn assert_refused(case: &Case, needle: &str) {
    let (success, output) = case.run();
    assert!(!success, "the check accepted a bad artifact:\n{output}");
    assert!(
        output.contains(needle),
        "the refusal does not name `{needle}`:\n{output}"
    );
    assert!(
        !case.out().join("SHA256SUMS").exists(),
        "a refused artifact must not get a SHA256SUMS file"
    );
}

#[test]
fn a_unit_binary_missing_from_the_export_is_refused() {
    let case = Case::new("missing");
    case.unit("svc-a.service", "/usr/local/bin/svc-a")
        .unit("svc-b.service", "-/usr/local/bin/svc-b --flag")
        .binary("svc-a", &good());
    assert_refused(&case, "svc-b");
}

#[test]
fn a_binary_for_another_machine_is_refused() {
    let case = Case::new("x86");
    case.unit("svc-a.service", "/usr/local/bin/svc-a")
        .binary("svc-a", &elf(EM_X86_64, &["GLIBC_2.17"]));
    assert_refused(&case, "aarch64");
}

#[test]
fn a_binary_that_needs_a_newer_glibc_is_refused() {
    let case = Case::new("glibc");
    case.unit("svc-a.service", "/usr/local/bin/svc-a")
        .binary("svc-a", &elf(EM_AARCH64, &["GLIBC_2.17", "GLIBC_2.38"]));
    assert_refused(&case, "GLIBC_2.38");
}

#[test]
fn a_file_that_no_unit_starts_is_refused() {
    let case = Case::new("extra");
    case.unit("svc-a.service", "/usr/local/bin/svc-a")
        .binary("svc-a", &good())
        .binary("stray", &good());
    assert_refused(&case, "stray");
}

#[test]
fn a_complete_export_is_accepted_and_summed() {
    let case = Case::new("complete");
    let a = good();
    let b = elf(EM_AARCH64, &["GLIBC_2.17"]);
    case.unit("svc-a.service", "/usr/local/bin/svc-a")
        .unit("svc-b.service", "/usr/local/bin/svc-b serve")
        .binary("svc-a", &a)
        .binary("svc-b", &b);
    let (success, output) = case.run();
    assert!(success, "the check refused a good artifact:\n{output}");
    let sums = fs::read_to_string(case.out().join("SHA256SUMS")).expect("SHA256SUMS written");
    let expected = format!("{}  svc-a\n{}  svc-b\n", hex(&a), hex(&b));
    assert_eq!(
        sums, expected,
        "SHA256SUMS must be `sha256sum -c` format, sorted"
    );
}

fn hex(bytes: &[u8]) -> String {
    use std::fmt::Write as _;
    Sha256::digest(bytes)
        .iter()
        .fold(String::new(), |mut out, byte| {
            let _ = write!(out, "{byte:02x}");
            out
        })
}

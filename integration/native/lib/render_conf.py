"""Renders a shipped deploy example into an EnvironmentFile and records every change. usage: render_conf.py SRC DST DEVIATIONS [RULE...]

The rules are the only changes the native smoke may make (R3 native smoke plan): addresses (the database host and port), paths under the smoke directory, the CHANGE-ME secrets, PLATFORM_ACCOUNTS user ids, and the per-flow keys a flow names. Every rule is written to DEVIATIONS as `<file>: <KEY>: <how>` with secrets redacted.

  --set KEY=VALUE        replace the value of the active line KEY=...; a missing key is an error (a key a flow needs that no example states is a defect to report)
  --uncomment KEY=VALUE  turn the commented example line `# KEY=...` into an active line with VALUE
  --remove KEY           comment the active line out (a documented opt-out)
  --add KEY=VALUE        append a key the example does not state (a documented test seam)
"""
import pathlib
import re
import sys

SECRET = re.compile(r"(SECRET|KEY|TOKEN|PASSWORD|HASH)", re.I)


def shown(key: str, value: str) -> str:
    value = re.sub(r"(://[^:/@]+:)[^@]*@", r"\1<pw>@", value)
    return "<redacted>" if SECRET.search(key) and "/" not in value else value


def main() -> int:
    src, dst, log = (pathlib.Path(p) for p in sys.argv[1:4])
    lines = src.read_text(encoding="utf-8").split("\n")
    notes: list[str] = []

    def find(key: str, commented: bool) -> int:
        pattern = re.compile(r"^\s*#\s*" + re.escape(key) + r"=" if commented else r"^\s*" + re.escape(key) + r"=")
        for index, line in enumerate(lines):
            if pattern.match(line):
                return index
        return -1

    for rule in sys.argv[4:]:
        action, _, body = rule.partition(" ")
        if action == "--remove":
            index = find(body, False)
            if index < 0:
                sys.exit(f"{src.name}: no active line {body} to remove")
            notes.append(f"{dst.name}: {body}: removed (documented opt-out)")
            lines[index] = "# (removed for this flow) " + lines[index]
            continue
        key, _, value = body.partition("=")
        if action == "--set":
            index = find(key, False)
            if index < 0:
                sys.exit(f"{src.name}: no active line {key}; a key the example does not state is a defect to report")
            old = lines[index].partition("=")[2]
            notes.append(f"{dst.name}: {key}: {shown(key, old)} -> {shown(key, value)}")
            lines[index] = f"{key}={value}"
        elif action == "--uncomment":
            index = find(key, True)
            if index < 0:
                sys.exit(f"{src.name}: no commented line {key}")
            notes.append(f"{dst.name}: {key}: enabled -> {shown(key, value)}")
            lines[index] = f"{key}={value}"
        elif action == "--add":
            notes.append(f"{dst.name}: {key}: added (not in the example) -> {shown(key, value)}")
            lines.append(f"{key}={value}")
        else:
            sys.exit(f"unknown rule {rule}")
    dst.write_text("\n".join(lines), encoding="utf-8")
    dst.chmod(0o600)
    with log.open("a", encoding="utf-8") as handle:
        handle.write("\n".join(notes) + ("\n" if notes else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

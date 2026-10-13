#!/usr/bin/python3
# Renders a child repository's config example into the host's config file, on the host.
#
# The example is installed unchanged next to this (sources/), and rendering fills only host values:
# the settings the enrolment names, and the database password, which is read from the host file it
# was generated into. A value of the form {file:/path} is read from that host file, so a secret is
# never a module argument and never crosses the SSH connection. The module refuses to write a file
# that still holds a placeholder (CHANGE-ME, REPLACE_ME) in an active line, because every service
# refuses to start on one and the error is clearer here. It returns no content.

DOCUMENTATION = r"""
module: ratatoskr_render
short_description: Render a config example on the host from host-side values
options:
  src: {required: true, type: path}
  dest: {required: true, type: path}
  owner: {default: root, type: str}
  group: {default: root, type: str}
  mode: {default: "0640", type: str}
  format: {default: env, choices: [env, tokens], type: str}
  settings: {default: {}, type: dict, description: "env format: KEY -> value, set or appended."}
  replacements: {default: {}, type: dict, description: "tokens format: token (a regular expression) -> value."}
  database_role: {type: str, description: "env format: role whose host password fills RATATOSKR__DATABASE__URL."}
  password_dir: {default: /etc/ratatoskr/secrets/postgres, type: path}
  placeholders: {default: [CHANGE-ME, REPLACE_ME], type: list, elements: str}
"""

import grp
import os
import pwd
import re

from ansible.module_utils.basic import AnsibleModule

FILE_TOKEN = re.compile(r"\{file:([^}]+)\}")


def expand(module, value):
    def read(match):
        path = match.group(1)
        try:
            with open(path, encoding="utf-8") as handle:
                return handle.read().strip()
        except OSError as error:
            module.fail_json(msg=f"a value names {path}, which cannot be read: {error.strerror}")
        return ""

    return FILE_TOKEN.sub(read, str(value))


def render_env(module, text, p):
    settings = {key: expand(module, value) for key, value in p["settings"].items()}
    used = set()
    lines = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#") and "=" in stripped:
            key = stripped.split("=", 1)[0]
            if key in settings:
                line = f"{key}={settings[key]}"
                used.add(key)
            elif key == "RATATOSKR__DATABASE__URL" and p["database_role"]:
                line = f"{key}={with_password(module, stripped.split('=', 1)[1], p)}"
        lines.append(line)
    missing = [key for key in settings if key not in used]
    if missing:
        lines.append("")
        lines.append("# Set by ratatoskr-workspace deploy/ansible; not in the example.")
        lines.extend(f"{key}={settings[key]}" for key in missing)
    return "\n".join(lines) + "\n"


def with_password(module, url, p):
    match = re.match(r"^(?P<scheme>[a-z]+://)(?P<user>[^:@/]+):(?P<password>[^@]*)@(?P<rest>.+)$", url)
    if match is None:
        module.fail_json(msg="RATATOSKR__DATABASE__URL has no user:password@ part to fill")
        raise SystemExit(1)  # fail_json exits; this tells a type checker so
    if match.group("user") != p["database_role"]:
        module.fail_json(
            msg=f"the example's database user is {match.group('user')}, the enrolment says {p['database_role']}"
        )
    password = expand(module, "{file:" + os.path.join(p["password_dir"], p["database_role"] + ".password") + "}")
    return f"{match.group('scheme')}{match.group('user')}:{password}@{match.group('rest')}"


def main():
    module = AnsibleModule(
        argument_spec=dict(
            src=dict(type="path", required=True),
            dest=dict(type="path", required=True),
            owner=dict(type="str", default="root"),
            group=dict(type="str", default="root"),
            mode=dict(type="str", default="0640"),
            format=dict(type="str", default="env", choices=["env", "tokens"]),
            settings=dict(type="dict", default={}),
            replacements=dict(type="dict", default={}),
            database_role=dict(type="str"),
            password_dir=dict(type="path", default="/etc/ratatoskr/secrets/postgres"),
            placeholders=dict(type="list", elements="str", default=["CHANGE-ME", "REPLACE_ME"]),
        ),
        supports_check_mode=True,
    )
    p = module.params
    with open(p["src"], encoding="utf-8") as handle:
        source = handle.read()

    if p["format"] == "env":
        rendered = render_env(module, source, p)
        active = [l for l in rendered.splitlines() if l.strip() and not l.strip().startswith("#")]
        left = sorted(
            {l.split("=", 1)[0] for l in active if any(token in l for token in p["placeholders"])}
        )
    else:
        rendered = source
        for pattern, value in p["replacements"].items():
            replacement = expand(module, value)
            rendered = re.sub(pattern, lambda _match: replacement, rendered)
        active = [l for l in rendered.splitlines() if not l.strip().startswith("#")]
        left = sorted({t for t in p["placeholders"] for l in active if t in l})
    if left:
        module.fail_json(msg=f"{p['dest']} would still hold a placeholder in: {', '.join(left)}")

    uid = pwd.getpwnam(p["owner"]).pw_uid
    gid = grp.getgrnam(p["group"]).gr_gid
    mode = int(p["mode"], 8)
    current = None
    if os.path.exists(p["dest"]):
        with open(p["dest"], encoding="utf-8") as handle:
            current = handle.read()
    changed = current != rendered
    if not changed:
        st = os.stat(p["dest"])
        changed = st.st_uid != uid or st.st_gid != gid or (st.st_mode & 0o7777) != mode
    if changed and not module.check_mode:
        tmp = f"{p['dest']}.tmp-{os.getpid()}"
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(rendered)
        os.chown(tmp, uid, gid)
        os.chmod(tmp, mode)
        os.replace(tmp, p["dest"])
    module.exit_json(changed=changed, dest=p["dest"])


if __name__ == "__main__":
    main()

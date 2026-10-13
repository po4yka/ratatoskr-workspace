#!/usr/bin/python3
# Runs one checked-in SQL file, as written, through the shared-postgres container, and only when
# the file differs from the one last run (a marker keeps its SHA-256). That is what makes a second
# run of the playbook change nothing while still re-running a file whose owner changed it.
#
# `postgres-provisioning`: a role file that does not run as written is a defect of its owner and is
# not patched by whoever provisions. So a failure stops here, names the file, and is not retried.
#
# With `password_role` it instead sets that role's password from the host file it was generated
# into, through psql's standard input, so the password is never an argument or a log line.

DOCUMENTATION = r"""
module: ratatoskr_sql
short_description: Run a SQL file, or set a role password, through docker exec psql
options:
  file: {type: path, description: The SQL file to run as written.}
  label: {required: true, type: str, description: Names the marker and the provision-log event.}
  password_role: {type: str}
  password_file: {type: path}
  container: {default: shared-postgres, type: str}
  database: {default: postgres, type: str}
  marker_dir: {default: /var/lib/ratatoskr-deploy/sql, type: path}
"""

import hashlib
import os
import time

from ansible.module_utils.basic import AnsibleModule

LOG = "/var/lib/ratatoskr-deploy/provision.log"


def main():
    module = AnsibleModule(
        argument_spec=dict(
            file=dict(type="path"),
            label=dict(type="str", required=True),
            password_role=dict(type="str"),
            password_file=dict(type="path", no_log=False),
            container=dict(type="str", default="shared-postgres"),
            database=dict(type="str", default="postgres"),
            marker_dir=dict(type="path", default="/var/lib/ratatoskr-deploy/sql"),
        ),
        required_one_of=[("file", "password_role")],
        mutually_exclusive=[("file", "password_role")],
        required_together=[("password_role", "password_file")],
        supports_check_mode=True,
    )
    p = module.params
    if p["file"]:
        with open(p["file"], "rb") as handle:
            stdin = handle.read()
    else:
        role = p["password_role"]
        if not role.replace("_", "").isalnum():
            module.fail_json(msg=f"{role} is not a plain role name")
        with open(p["password_file"], encoding="utf-8") as handle:
            password = handle.read().strip()
        if "'" in password or "\\" in password:
            module.fail_json(msg=f"the password file of {role} holds a quote or a backslash")
        stdin = f"alter role {role} password '{password}';\n".encode()

    digest = hashlib.sha256(stdin).hexdigest()
    marker = os.path.join(p["marker_dir"], p["label"] + ".sha256")
    if os.path.exists(marker):
        with open(marker, encoding="utf-8") as handle:
            if handle.read().strip() == digest:
                module.exit_json(changed=False, label=p["label"])
    if module.check_mode:
        module.exit_json(changed=True, label=p["label"])

    rc, out, err = module.run_command(
        ["docker", "exec", "-i", p["container"], "psql", "-U", "postgres", "-d", p["database"],
         "-v", "ON_ERROR_STOP=1", "-q", "-X"],
        data=stdin,
        binary_data=True,
    )
    if rc != 0:
        what = p["file"] or f"the password of {p['password_role']}"
        # psql echoes the failing statement; for a password that would be the secret itself.
        detail = err.strip() if p["file"] else "psql refused it"
        module.fail_json(msg=f"{what} failed as written (exit {rc}): {detail}", label=p["label"])

    os.makedirs(p["marker_dir"], mode=0o700, exist_ok=True)
    with open(marker, "w", encoding="utf-8") as handle:
        handle.write(digest + "\n")
    with open(LOG, "a", encoding="utf-8") as log:
        log.write(f"{time.time_ns()} sql:{p['label']}\n")
    module.exit_json(changed=True, label=p["label"])


if __name__ == "__main__":
    main()

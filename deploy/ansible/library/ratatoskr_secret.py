#!/usr/bin/python3
# The secret is generated on the host and never leaves it (openspec host-provisioning): this module
# writes the file when it is absent, keeps it when it is present, and returns nothing about its
# content. Only the ownership and the mode are corrected on a later run.

DOCUMENTATION = r"""
module: ratatoskr_secret
short_description: Ensure a random secret file exists on the host, without returning it
options:
  path: {required: true, type: path}
  owner: {default: root, type: str}
  group: {default: root, type: str}
  mode: {default: "0600", type: str}
  bytes: {default: 32, type: int, description: Random bytes before encoding.}
  encoding: {default: hex, choices: [hex, urlsafe], type: str}
  event: {type: str, description: Line appended to the provision log when the secret is created.}
"""

import grp
import os
import pwd
import secrets
import time

from ansible.module_utils.basic import AnsibleModule

LOG = "/var/lib/ratatoskr-deploy/provision.log"


def record(event):
    if event:
        os.makedirs(os.path.dirname(LOG), mode=0o700, exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as log:
            log.write(f"{time.time_ns()} {event}\n")


def main():
    module = AnsibleModule(
        argument_spec=dict(
            path=dict(type="path", required=True),
            owner=dict(type="str", default="root"),
            group=dict(type="str", default="root"),
            mode=dict(type="str", default="0600"),
            bytes=dict(type="int", default=32),
            encoding=dict(type="str", default="hex", choices=["hex", "urlsafe"]),
            event=dict(type="str"),
        ),
        supports_check_mode=True,
    )
    p = module.params
    path = p["path"]
    uid = pwd.getpwnam(p["owner"]).pw_uid
    gid = grp.getgrnam(p["group"]).gr_gid
    mode = int(p["mode"], 8)
    changed = False

    if not os.path.exists(path):
        changed = True
        if not module.check_mode:
            raw = secrets.token_bytes(p["bytes"])
            value = raw.hex() if p["encoding"] == "hex" else secrets.token_urlsafe(p["bytes"])
            tmp = f"{path}.tmp-{os.getpid()}"
            fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(value + "\n")
            os.chown(tmp, uid, gid)
            os.chmod(tmp, mode)
            os.replace(tmp, path)
            record(p["event"])
    else:
        st = os.stat(path)
        if st.st_uid != uid or st.st_gid != gid or (st.st_mode & 0o7777) != mode:
            changed = True
            if not module.check_mode:
                os.chown(path, uid, gid)
                os.chmod(path, mode)

    module.exit_json(changed=changed, path=path)


if __name__ == "__main__":
    main()

#!/usr/bin/python3
# One NATS identity's nkey pair, generated on the host with `nk -gen user -pubout` (Platform's
# deploy/nats/README.md) from the pinned nats-box image, so the host gains no package. The seed is
# written for its service's group only and never returned; the public key is not a secret and is
# returned, because it goes into ratatoskr.conf.

DOCUMENTATION = r"""
module: ratatoskr_nkey
short_description: Ensure an nkey seed and its public key exist on the host
options:
  seed_path: {required: true, type: path}
  pub_path: {required: true, type: path}
  group: {default: root, type: str}
  image: {required: true, type: str, description: Pinned natsio/nats-box image reference.}
"""

import grp
import os

from ansible.module_utils.basic import AnsibleModule


def write(path, content, uid, gid, mode):
    tmp = f"{path}.tmp-{os.getpid()}"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(content)
    os.chown(tmp, uid, gid)
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def main():
    module = AnsibleModule(
        argument_spec=dict(
            seed_path=dict(type="path", required=True),
            pub_path=dict(type="path", required=True),
            group=dict(type="str", default="root"),
            image=dict(type="str", required=True),
        ),
        supports_check_mode=False,
    )
    p = module.params
    gid = grp.getgrnam(p["group"]).gr_gid
    # A seed no service reads yet stays root-only; an enrolled one is readable by its service group.
    seed_mode = 0o600 if p["group"] == "root" else 0o640
    changed = False

    if not os.path.exists(p["seed_path"]):
        rc, out, err = module.run_command(["docker", "run", "--rm", p["image"], "nk", "-gen", "user", "-pubout"])
        lines = [l.strip() for l in out.splitlines() if l.strip()]
        if rc != 0 or len(lines) != 2 or not lines[0].startswith("SU") or not lines[1].startswith("U"):
            module.fail_json(msg=f"nk did not produce a user key pair (exit {rc}): {err.strip()}")
        write(p["seed_path"], lines[0] + "\n", 0, gid, seed_mode)
        write(p["pub_path"], lines[1] + "\n", 0, 0, 0o644)
        changed = True
    elif not os.path.exists(p["pub_path"]):
        rc, out, err = module.run_command(
            ["docker", "run", "--rm", "-v", f"{p['seed_path']}:/seed:ro", p["image"], "nk", "-inkey", "/seed", "-pubout"]
        )
        public = out.strip().splitlines()[-1].strip() if out.strip() else ""
        if rc != 0 or not public.startswith("U"):
            module.fail_json(msg=f"nk could not derive the public key (exit {rc}): {err.strip()}")
        write(p["pub_path"], public + "\n", 0, 0, 0o644)
        changed = True

    st = os.stat(p["seed_path"])
    if st.st_uid != 0 or st.st_gid != gid or (st.st_mode & 0o7777) != seed_mode:
        os.chown(p["seed_path"], 0, gid)
        os.chmod(p["seed_path"], seed_mode)
        changed = True
    with open(p["pub_path"], encoding="utf-8") as handle:
        public = handle.read().strip()
    module.exit_json(changed=changed, public_key=public)


if __name__ == "__main__":
    main()

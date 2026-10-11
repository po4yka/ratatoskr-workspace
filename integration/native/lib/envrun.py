"""Runs a command with a systemd-style EnvironmentFile, the way the shipped unit files do. usage: envrun.py CONF COMMAND [ARG...]

Every RATATOSKR__* variable of the parent environment is dropped first, so a service sees only what its rendered example states."""
import os
import sys

env = dict(os.environ)
for key in [name for name in env if name.startswith("RATATOSKR__")]:
    del env[key]
with open(sys.argv[1], encoding="utf-8") as handle:
    for line in handle:
        line = line.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key, _, value = line.partition("=")
        env[key.strip()] = value
os.execvpe(sys.argv[2], sys.argv[2:], env)

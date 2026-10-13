# Reads workspace.lock, the generated snapshot of the pinned commits, for the controller-side
# preflight. tomllib is in the standard library from Python 3.11, which the controller needs.

import tomllib


def ratatoskr_lock(text):
    """workspace.lock text -> {repository id: {path, commit, remote, slug}}."""
    lock = tomllib.loads(text)
    pinned = {}
    for repository in lock.get("repositories", []):
        remote = repository["remote"]
        slug = remote.removeprefix("https://github.com/").removesuffix(".git")
        pinned[repository["id"]] = {
            "path": repository["path"],
            "commit": repository["commit"],
            "remote": remote,
            "slug": slug,
        }
    return pinned


class FilterModule:
    def filters(self):
        return {"ratatoskr_lock": ratatoskr_lock}

#!/usr/bin/env bash
set -euo pipefail

output_dir=${1:?usage: export-agent-product-fixtures.sh OUTPUT_DIR}
mkdir -p "$output_dir"
if [[ -n $(find "$output_dir" -mindepth 1 -maxdepth 1 -print -quit) ]]; then
  printf 'fixture output directory must be empty: %s\n' "$output_dir" >&2
  exit 2
fi

python3 - "$output_dir" <<'PY'
import json
import pathlib
import sys
import zipfile

root = pathlib.Path(sys.argv[1])
stamp = (2026, 8, 31, 0, 0, 0)

chatgpt = {
    "conversations.json": [
        {
            "id": "xpa020-chatgpt-conversation",
            "title": "Synthetic fixture",
            "mapping": {
                "xpa020-chatgpt-message": {
                    "id": "xpa020-chatgpt-message",
                    "parent": None,
                    "message": {
                        "id": "xpa020-chatgpt-message",
                        "author": {"role": "user"},
                        "content": {"parts": ["Synthetic inert message"]},
                    },
                }
            },
        }
    ],
    "projects.json": [
        {
            "id": "xpa020-chatgpt-project",
            "title": "Synthetic project",
            "description": "Invented integration fixture",
            "instructions": [],
            "conversation_ids": ["xpa020-chatgpt-conversation"],
            "asset_ids": [],
        }
    ],
    "user.json": {"id": "xpa020-chatgpt-user", "synthetic": True},
}

claude_export = {
    "schema": "claude-export-2026-08-synthetic",
    "projects": [
        {
            "id": "xpa020-claude-project",
            "name": "Synthetic project",
            "description": "Invented integration fixture",
            "instructions": "Remain inert.",
            "knowledge_files": [],
        }
    ],
    "conversations": [
        {
            "id": "xpa020-claude-conversation",
            "project_id": "xpa020-claude-project",
            "title": "Synthetic fixture",
            "created_at": "2026-08-31T00:00:00Z",
            "messages": [
                {
                    "id": "xpa020-claude-message",
                    "role": "user",
                    "content": [{"type": "text", "text": "Synthetic inert message"}],
                }
            ],
        }
    ],
}
claude = {
    "conversations.json": claude_export,
    "projects.json": claude_export["projects"],
    "users.json": [{"id": "xpa020-claude-user", "synthetic": True}],
}

def write_archive(name, members):
    destination = root / name
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_STORED) as archive:
        for member_name in sorted(members):
            payload = json.dumps(
                members[member_name], ensure_ascii=True, sort_keys=True, separators=(",", ":")
            ).encode("utf-8") + b"\n"
            info = zipfile.ZipInfo(member_name, stamp)
            info.compress_type = zipfile.ZIP_STORED
            info.create_system = 3
            info.external_attr = 0o100600 << 16
            archive.writestr(info, payload)

write_archive("chatgpt-synthetic.zip", chatgpt)
write_archive("claude-synthetic.zip", claude)
PY

printf 'deterministic synthetic ChatGPT and Claude fixtures: ready\n'

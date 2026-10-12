"""Synthetic ChatGPT and Claude archives that hold ONE very large conversation, for the large-fact legs of flow F2 (R5-03: a conversation fact of about 2 MiB and one just below RATATOSKR__RECEIPT__MAX_EVENT_BYTES, 8000000, must reach Knowledge and be searchable). usage: big_archives.py OUTDIR

Written next to archives.py with the same rules: invented content, stored ZIPs, fixed timestamps, byte-for-byte reproducible. The text starts with a distinctive word so the fake summariser's summary (the first 300 characters) makes the conversation searchable."""
import json
import pathlib
import sys
import zipfile

out = pathlib.Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
STAMP = (2026, 8, 31, 0, 0, 0)
SIZES = {"2mib": 2 * 1024 * 1024, "7p9mb": 7_850_000}
WORDS = {("chatgpt", "2mib"): "pangolin", ("chatgpt", "7p9mb"): "wombat", ("claude", "2mib"): "ocelot", ("claude", "7p9mb"): "lemming"}


def text(word, size):
    head = f"We decided to plan the {word} expedition for April. "
    filler = f"Further notes about the {word} expedition were recorded here. "
    body = head + filler * (size // len(filler) + 1)
    return body[:size]


def write(name, member, payload):
    with zipfile.ZipFile(out / name, "w", compression=zipfile.ZIP_STORED) as z:
        info = zipfile.ZipInfo(member, STAMP)
        info.compress_type = zipfile.ZIP_STORED
        info.create_system = 3
        info.external_attr = 0o100600 << 16
        z.writestr(info, json.dumps(payload, ensure_ascii=True, sort_keys=True, separators=(",", ":")).encode() + b"\n")


for (provider, label), word in WORDS.items():
    body = text(word, SIZES[label])
    if provider == "chatgpt":
        write(f"chatgpt-large-{label}.zip", "conversations.json", [{"id": f"conversation-big-{label}", "title": f"{word.capitalize()} planning notes", "mapping": {f"message-big-{label}": {
            "id": f"message-big-{label}", "parent": None, "message": {"id": f"message-big-{label}", "author": {"role": "user"}, "content": {"parts": [body]}}}}}])
    else:
        write(f"claude-large-{label}.zip", "export.json", {"schema": "claude-export-2026-08-synthetic", "projects": [{
            "id": f"project-big-{label}", "name": f"{word.capitalize()} plans", "description": "Seasonal notes", "instructions": "Use metric units.", "knowledge_files": []}],
            "conversations": [{"id": f"conversation-big-{label}", "project_id": f"project-big-{label}", "title": f"{word.capitalize()} calendar", "created_at": "2026-08-01T08:00:00Z",
            "messages": [{"id": f"message-big-{label}-1", "role": "user", "content": [{"type": "text", "text": body}]},
                         {"id": f"message-big-{label}-2", "parent_id": f"message-big-{label}-1", "role": "assistant", "model": "claude-synthetic", "content": [{"type": "text", "text": "After the last frost."}]}]}]})
print(sorted(p.name for p in out.iterdir()))

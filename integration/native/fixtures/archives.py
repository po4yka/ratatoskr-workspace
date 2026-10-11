"""Synthetic ChatGPT and Claude archives for the native smoke. usage: archives.py OUTDIR

All content is invented. Archives are stored (uncompressed) ZIPs with fixed timestamps so digests are stable. Besides the single archives of flow F1 there is a cumulative series per provider (R3-06): export 2 repeats everything export 1 held and adds a conversation, export 3 does the same again, so deleting the oldest export must not make a conversation that a retained export still holds unsearchable. Tenant 2 gets one export per provider with distinct ids and a distinct word, which is how a flow shows that identical bytes of two tenants stay isolated."""
import hashlib, json, pathlib, sys, zipfile

out = pathlib.Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
STAMP = (2026, 8, 31, 0, 0, 0)

def dump(v): return json.dumps(v, ensure_ascii=True, sort_keys=True, separators=(",", ":")).encode() + b"\n"

def write_zip(name, members):
    with zipfile.ZipFile(out / name, "w", compression=zipfile.ZIP_STORED) as z:
        for n in sorted(members):
            info = zipfile.ZipInfo(n, STAMP); info.compress_type = zipfile.ZIP_STORED; info.create_system = 3
            info.external_attr = 0o100600 << 16
            data = members[n]
            z.writestr(info, data if isinstance(data, bytes) else dump(data))

def conv(tag, word, extra=""):
    return {"id": f"conversation-{tag}", "title": f"{word.capitalize()} planning notes", "mapping": {f"message-{tag}": {
        "id": f"message-{tag}", "parent": None, "message": {"id": f"message-{tag}", "author": {"role": "user"},
        "content": {"parts": [f"We decided to plan the {word} expedition for April. {extra}"]}}}}}

def project(tag, word, assets):
    return {"id": f"project-{tag}", "title": f"{word.capitalize()} logistics project", "description": "Invented fixture only",
            "instructions": [{"id": f"instruction-{tag}", "kind": "instruction", "content": "Preserve evidence."}],
            "conversation_ids": [f"conversation-{tag}"], "asset_ids": assets}

NOTE = b"invented note body\n"
def declaration(tag):
    return [{"id": f"asset-{tag}", "kind": "uploaded", "display_name": "note.txt", "archive_path": "assets/note.txt",
             "media_type": "text/plain", "length_bytes": len(NOTE), "sha256": hashlib.sha256(NOTE).hexdigest()}]

# ChatGPT
write_zip("chatgpt-conversations-only.zip", {"conversations.json": [conv("cgonly", "marmot")]})
write_zip("chatgpt-full.zip", {
    "conversations.json": [conv("cgfull", "quokka")],
    "projects.json": [project("cgfull", "quokka", ["asset-cgfull"])],
    "canvas.json": [{"id": "canvas-cgfull", "project_id": "project-cgfull", "conversation_id": "conversation-cgfull",
                     "content": ["# Inert Canvas", {"kind": "code", "text": "never execute"}]}],
    "assets.json": declaration("cgfull"), "assets/note.txt": NOTE})
write_zip("chatgpt-asset-missing.zip", {
    "conversations.json": [conv("cgmiss", "zanzibar")],
    "projects.json": [project("cgmiss", "zanzibar", ["asset-cgmiss"])],
    "assets.json": declaration("cgmiss")})
# multi-chunk: > 2 chunks at the 65536 minimum chunk size (padding lives in an inert asset)
pad = (b"padding-line-for-a-multi-chunk-upload\n" * 6000)
big_decl = [{"id": "asset-cgbig", "kind": "uploaded", "display_name": "pad.txt", "archive_path": "assets/pad.txt",
             "media_type": "text/plain", "length_bytes": len(pad), "sha256": hashlib.sha256(pad).hexdigest()}]
write_zip("chatgpt-multichunk.zip", {
    "conversations.json": [conv("cgbig", "narwhal")],
    "projects.json": [project("cgbig", "narwhal", ["asset-cgbig"])],
    "assets.json": big_decl, "assets/pad.txt": pad})

# Claude (a ZIP holding one synthetic consumer export JSON)
KB = b"garden plan"
def claude_export(tag, word, knowledge):
    return {"schema": "claude-export-2026-08-synthetic",
            "projects": [{"id": f"project-{tag}", "name": f"{word.capitalize()} plans", "description": "Seasonal notes",
                          "instructions": "Use metric units.", "knowledge_files": knowledge}],
            "conversations": [{"id": f"conversation-{tag}", "project_id": f"project-{tag}", "title": f"{word.capitalize()} calendar",
                               "created_at": "2026-08-01T08:00:00Z",
                               "messages": [{"id": f"message-{tag}-1", "role": "user",
                                             "content": [{"type": "text", "text": f"When should the {word} be planted?"}]},
                                            {"id": f"message-{tag}-2", "parent_id": f"message-{tag}-1", "role": "assistant", "model": "claude-synthetic",
                                             "content": [{"type": "text", "text": "After the last frost."}]}]}]}
good_kb = [{"id": "knowledge-ok", "filename": "garden-plan.txt", "media_type": "text/plain",
            "sha256": hashlib.sha256(KB).hexdigest(), "bytes": list(KB)}]
write_zip("claude-complete.zip", {"export.json": claude_export("clcomp", "basil", good_kb)})
write_zip("claude-nofiles.zip", {"export.json": claude_export("clnone", "thyme", [])})
write_zip("claude-reference-only.zip", {"export.json": claude_export("clref", "sage", [
    {"id": "knowledge-ref", "filename": "seasonal-source.pdf", "media_type": "application/pdf"}])})
# not a zip, not an archive at all (importer must fail it permanently)
(out / "corrupt.zip").write_bytes(b"this is not a zip archive\n" * 40)

# Cumulative series (tenant 1) and the one export of tenant 2, for each provider.
def series_conv(tag, word):
    return conv(tag, word, extra="Series fixture.")

def chatgpt_series(n, words):
    convs = [series_conv(f"s{i}", words[i]) for i in range(n)]
    projects = [project(f"s{i}", words[i], []) for i in range(n)]
    return {"conversations.json": convs, "projects.json": projects, "canvas.json": []}

CG_WORDS = ["aardvark", "bobcat", "civet"]
for n in (1, 2, 3):
    write_zip(f"chatgpt-series-{n}.zip", chatgpt_series(n, CG_WORDS))
write_zip("chatgpt-u2.zip", {"conversations.json": [conv("u2cg", "tapir")], "projects.json": [project("u2cg", "tapir", [])], "canvas.json": []})

CL_WORDS = ["fennel", "garlic", "hyssop"]
for n in (1, 2, 3):
    exports = claude_export(f"cs{n}", CL_WORDS[n - 1], [])
    exports["projects"] = [claude_export(f"cs{i}", CL_WORDS[i], [])["projects"][0] for i in range(n)]
    exports["conversations"] = [claude_export(f"cs{i}", CL_WORDS[i], [])["conversations"][0] for i in range(n)]
    write_zip(f"claude-series-{n}.zip", {"export.json": exports})
write_zip("claude-u2.zip", {"export.json": claude_export("u2cl", "okapi", [])})
print(sorted(p.name for p in out.iterdir()))

"""LOOPBACK FAKE of OpenRouter's chat-completions endpoint (Knowledge: RATATOSKR__PROVIDER__OPENROUTER__BASE_URL). Labelled in every result.txt: nothing it returns is a live provider result.

usage: fake_openrouter.py PORT LOGFILE RUNDIR

It answers schema-valid, evidence-grounded JSON for the families Knowledge asks about: an article paragraph, an AI-archive conversation, an AI-archive project, a social source (the post text the prompt carries after post_text:), a repository (the README the prompt carries between README_BEGIN and README_END, or the full name when there is none; the body is the RepositoryAnalysis schema of knowledge/crates/knowledge/src/family_analysis.rs) and a channel-digest recap (which cites each revision reference found in the request). Every request is appended to LOGFILE as one JSON line (path, model, family, answered; never a credential). When the file RUNDIR/fake-fail exists it answers 401 to everything, which is how a flow makes the provider fail permanently. When RUNDIR/fake-status exists it holds a schedule, one "STATUS SECONDS" pair per line (for example "401 60", "402 30", "404 30"), counted from the file's modification time: the fake answers each STATUS for its SECONDS and 200 again after the last stage, which is how a flow makes the provider's credential or account fail for a while and then recover (R5-03)."""
import http.server
import json
import os
import re
import sys

PORT, LOG, RUNDIR = int(sys.argv[1]), sys.argv[2], sys.argv[3]


def answer(user: str, whole: str):
    refs = list(dict.fromkeys(re.findall(r"channel-post-revision:[0-9a-f-]{36}", whole)))
    if refs:
        return {
            "headline": "Offline fake recap",
            "overview": "Two synthetic posts were summarised by a loopback fake provider.",
            "topics": [{"label": f"Update {i + 1}", "summary": "A grounded update from the cited revision.", "citations": [ref]} for i, ref in enumerate(refs)],
            "notable_items": [],
            "warnings": [],
        }, "channel_recap"
    if "family: repository" in user:
        readme = re.search(r"README_BEGIN\n(.*)README_END", user, re.S)
        lines = [line.strip() for line in (readme.group(1) if readme else "").splitlines() if line.strip()]
        full_name = re.search(r"^full_name: (.*)$", user, re.M)
        excerpt = (lines[0] if lines else (full_name.group(1) if full_name else "repository"))[:200]
        return {"summary": "Scripted repository summary: " + excerpt, "topics": ["scripted"], "evidence_excerpt": excerpt, "readme_evidence": "present" if lines else "absent"}, "repository"
    if "family: social" in user:
        post = re.search(r"^post_text: (.*)$", user, re.M)
        text = (post.group(1) if post else "").strip()
        excerpt = (text or "social post")[:200]
        return {"summary": "Scripted social summary: " + excerpt, "topics": ["scripted"], "evidence_excerpt": excerpt, "confidence": "grounded" if text else "limited"}, "social"
    if "family: ai_archive_project" in user:
        title = re.search(r"^title: (.*)$", user, re.M)
        text = title.group(1) if title else "project"
        return {"summary": "Scripted project summary: " + text, "topics": ["scripted"], "evidence_excerpt": text}, "ai_archive_project"
    if "family: ai_archive" in user:
        ids = re.findall(r"^message_id: (.*)$", user, re.M)
        text = re.search(r"^text: (.*)$", user, re.M)
        return {"summary": "Scripted conversation summary: " + (text.group(1) if text else "no text")[:300], "summary_message_ids": ids[:1], "decisions": []}, "ai_archive"
    block = re.search(r'^block (\d+) paragraph: (".*")$', user, re.M)
    if block:
        paragraph = json.loads(block.group(2))
        return {"summary": paragraph[:2000], "key_points": [{"text": paragraph[:500], "source_block_indexes": [int(block.group(1))]}]}, "article"
    return None, "unknown"


def scheduled_status():
    """The status the schedule file demands now, or None when there is no file or the schedule is over."""
    path = os.path.join(RUNDIR, "fake-status")
    try:
        started = os.stat(path).st_mtime
        stages = [line.split() for line in open(path, encoding="utf-8").read().splitlines() if line.strip()]
    except OSError:
        return None
    import time
    elapsed = time.time() - started
    for status, seconds in stages:
        if elapsed < float(seconds):
            return int(status)
        elapsed -= float(seconds)
    return None


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        length = int(self.headers.get("content-length", 0))
        raw = self.rfile.read(length)
        try:
            request = json.loads(raw)
        except json.JSONDecodeError:
            request = {}
        messages = request.get("messages") or [{}, {}]
        user = str(messages[-1].get("content", ""))
        body, family = answer(user, json.dumps(request))
        with open(LOG, "a", encoding="utf-8") as handle:
            handle.write(json.dumps({"path": self.path, "model": request.get("model"), "family": family, "answered": body is not None, "authorization": "present" if self.headers.get("authorization", "").startswith("Bearer ") else "absent", "bytes": length}) + "\n")
        scheduled = scheduled_status()
        if scheduled is not None:
            self.send_response(scheduled)
            self.end_headers()
            self.wfile.write(b"{}")
            return
        if os.path.exists(os.path.join(RUNDIR, "fake-fail")):
            self.send_response(401)
            self.end_headers()
            self.wfile.write(b"{}")
            return
        if body is None or not self.path.endswith("/chat/completions"):
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"{}")
            return
        envelope = {"id": "fake-or-1", "choices": [{"message": {"role": "assistant", "content": json.dumps(body)}}], "usage": {"prompt_tokens": max(1, length // 4), "completion_tokens": 40}}
        data = json.dumps(envelope).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()

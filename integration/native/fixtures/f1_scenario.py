"""Flow F1 driver: export-agent style HTTP calls into Platform Edge (127.0.0.1:8080) with the real ChatGPT receipt listener (8096) and Claude receipt listener (8097) behind it. Ported from the by-hand scenario of the Round 3 AI-archive smoke (.workspaces/XR-021/smoke/ai/scenario.py), which produced the recorded F1 result; extended with the cumulative series for flow F6 (section s13). Not yet run through run.sh as committed.

Prints `ASSERT <name>: PASS|FAIL <detail>` and writes redacted evidence under $EV/http and $EV/ops. usage: f1_scenario.py [section ...] (default: all)

Environment: RATATOSKR_SMOKE_DIR (state), EV (evidence directory of the flow), NATIVE_ROOT."""
import base64, hashlib, http.client, json, os, pathlib, re, subprocess, sys, time, urllib.parse

S = pathlib.Path(os.environ["RATATOSKR_SMOKE_DIR"])
NATIVE = pathlib.Path(os.environ["NATIVE_ROOT"])
sys.path.insert(0, str(NATIVE / "fixtures"))
import natsprobe

EV = pathlib.Path(os.environ["EV"])
FX = S / "fx"
EDGE = ("127.0.0.1", 8080)
U1 = "01980000-0000-7000-8000-000000000001"
U2 = "01980000-0000-7000-8000-000000000002"
TERMINAL = {"succeeded", "failed", "partially_succeeded", "cancelled"}
results = []
state = {}
SECRET_KEYS = ("code", "device_secret", "credential", "refresh_token")


def A(name, cond, detail=""):
    ok = bool(cond)
    results.append((name, ok, detail))
    print(f"ASSERT {name}: {'PASS' if ok else 'FAIL'} {detail}".rstrip(), flush=True)
    return ok


def sh(cmd):
    libs = " ".join(f"source {NATIVE}/lib/{name}.sh;" for name in ("common", "assert", "postgres", "nats", "services"))
    return subprocess.run(["bash", "-c", f"{libs} {cmd}"], capture_output=True, text=True, timeout=300)


def redact(text):
    for k in SECRET_KEYS:
        text = re.sub(rf'("{k}"\s*:\s*")[^"]+', r"\1[redacted]", text)
    return text


counter = [0]


def http_req(name, method, url_path, headers=None, body=None, host=EDGE, timeout=300, save=True):
    headers = dict(headers or {})
    conn = http.client.HTTPConnection(host[0], host[1], timeout=timeout)
    if isinstance(body, (dict, list)):
        body = json.dumps(body).encode(); headers.setdefault("Content-Type", "application/json")
    t0 = time.time()
    try:
        conn.request(method, url_path, body=body, headers=headers)
        r = conn.getresponse(); data = r.read()
        status, rh = r.status, dict((k.lower(), v) for k, v in r.getheaders())
    except Exception as e:  # connection refused etc.
        status, rh, data = 0, {}, f"{type(e).__name__}: {e}".encode()
    finally:
        conn.close()
    if save:
        counter[0] += 1
        d = EV / "http"; d.mkdir(parents=True, exist_ok=True)
        shown = {k: ("Bearer [redacted]" if k.lower() == "authorization" else v) for k, v in headers.items()}
        bsample = body if isinstance(body, bytes) and len(body) < 4096 else f"<{len(body) if body else 0} bytes>"
        (d / f"{counter[0]:03d}-{name}.txt").write_text(
            f"{method} {host[0]}:{host[1]}{url_path}\n{json.dumps(shown)}\n{redact(bsample.decode(errors='replace') if isinstance(bsample, bytes) else bsample)}\n"
            f"--> {status} ({time.time()-t0:.2f}s)\n{json.dumps(rh)}\n{redact(data[:3000].decode(errors='replace'))}\n")
    return status, rh, data


def js(data):
    try:
        return json.loads(data)
    except Exception:
        return {}


def bearer(tok):
    return {"Authorization": f"Bearer {tok}"}


def pair(user_tag):
    tok = (S / f"conf/secret.browser{user_tag}").read_text()
    st, _, b = http_req(f"u{user_tag}-pairing-code", "POST", "/v1/devices/pairing-codes", bearer(tok), {"expected_kind": "export_agent", "label": "smoke"})
    code = js(b).get("code")
    st2, _, b2 = http_req(f"u{user_tag}-pair", "POST", "/v1/devices/pair", {}, {"code": code, "kind": "export_agent", "display_name": f"smoke device {user_tag}"})
    j = js(b2)
    return st, st2, j


def sha_of(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class Upload:
    def __init__(self, provider, cred, path, chunk=65536, key=None):
        self.provider, self.cred, self.path, self.chunk = provider, cred, pathlib.Path(path), chunk
        self.data = self.path.read_bytes(); self.sha = hashlib.sha256(self.data).hexdigest()
        self.key = key or f"smoke-{self.path.stem}-{os.urandom(4).hex()}"
        self.op = None; self.token = None; self.upload_path = None; self.tag = self.path.stem

    def prepare(self, size=None, sha=None):
        st, _, b = http_req(f"{self.tag}-prepare", "POST", f"/v1/ai-archives/{self.provider}",
                            {**bearer(self.cred), "Idempotency-Key": self.key},
                            {"sha256": sha or self.sha, "byte_size": size if size is not None else len(self.data)})
        j = js(b)
        if st == 202:
            self.op = j.get("operation_id"); self.upload_path = j.get("upload_path")
        return st, j

    def open(self):
        up = self.upload_path
        if not up.startswith("/"):
            up = "/" + up
        self.upload_path = up
        st, _, b = http_req(f"{self.tag}-open", "POST", up, bearer(self.cred),
                            {"declared_size_bytes": len(self.data), "media_type": "application/zip",
                             "digest": {"algorithm": "sha256", "hex": self.sha}, "chunk_size_bytes": self.chunk})
        j = js(b)
        if st == 201:
            self.token = j.get("resumption_token")
        return st, j

    def chunks(self):
        return [self.data[i:i + self.chunk] for i in range(0, len(self.data), self.chunk)]

    def put(self, index, payload=None):
        body = payload if payload is not None else self.chunks()[index]
        st, _, b = http_req(f"{self.tag}-chunk{index}", "PUT", f"{self.upload_path}/{self.token}/chunks/{index}",
                            {**bearer(self.cred), "Content-Type": "application/octet-stream"}, body)
        return st, js(b)

    def status(self):
        st, _, b = http_req(f"{self.tag}-status", "GET", f"{self.upload_path}/{self.token}/status", bearer(self.cred))
        return st, js(b)

    def finalize(self):
        st, rh, b = http_req(f"{self.tag}-finalize", "POST", f"{self.upload_path}/{self.token}/finalize", bearer(self.cred), {"resumption_token": self.token})
        return st, js(b), rh

    def all_but_finalize(self):
        self.prepare(); st, _ = self.open()
        for i in range(len(self.chunks())):
            self.put(i)

    def poll(self, max_s=180):
        return poll_op(self.op, self.cred, max_s, self.tag)


def poll_op(op, cred, max_s=180, tag="op"):
    end = time.time() + max_s; last = {}
    while time.time() < end:
        st, _, b = http_req(f"{tag}-poll", "GET", f"/v1/operations/{op}", bearer(cred), save=False)
        last = js(b)
        if last.get("status") in TERMINAL:
            break
        time.sleep(2)
    (EV / "ops").mkdir(parents=True, exist_ok=True)
    (EV / "ops" / f"{tag}-{op}.json").write_text(json.dumps(last, indent=1))
    return last


def warn_codes(op_json):
    found = []
    def walk(o):
        if isinstance(o, dict):
            if isinstance(o.get("code"), str) and "." in o["code"]:
                found.append(o["code"])
            for v in o.values(): walk(v)
        elif isinstance(o, list):
            for v in o: walk(v)
    walk(op_json)
    return found


def full_upload(provider, cred, name, chunk=65536):
    u = Upload(provider, cred, FX / name, chunk)
    st, j = u.prepare()
    if st != 202:
        return u, {"status": f"prepare-{st}", "body": j}, None
    st, j = u.open()
    if st != 201:
        return u, {"status": f"open-{st}", "body": j}, None
    for i in range(len(u.chunks())):
        cs, _ = u.put(i)
        if cs != 200:
            return u, {"status": f"chunk{i}-{cs}"}, None
    fs, fj, _ = u.finalize()
    if fs != 200:
        return u, {"status": f"finalize-{fs}", "body": fj}, fj
    return u, u.poll(), fj


# ----------------------------------------------------------------------------------------------------------------------------------
def s1_surface():
    for prov, rport, oport in (("chatgpt", 8096, 9085), ("claude", 8097, 9086)):
        st, rh, b = http_req(f"{prov}-capabilities", "GET", "/v1/capabilities", host=("127.0.0.1", rport))
        A(f"{prov}.receipt_capabilities_200", st == 200, f"status={st} body={b[:160].decode(errors='replace')}")
        A(f"{prov}.capabilities_cache_control_no_store", "no-store" in rh.get("cache-control", ""), f"cache-control={rh.get('cache-control')}")
        st, _, _ = http_req(f"{prov}-operator-ready", "GET", "/health/ready", host=("127.0.0.1", oport))
        A(f"{prov}.operator_ready_200", st == 200, f"status={st}")
        st, _, _ = http_req(f"{prov}-receipt-metrics", "GET", "/metrics", host=("127.0.0.1", rport))
        A(f"{prov}.metrics_404_on_receipt_port", st == 404, f"status={st}")
        st, _, _ = http_req(f"{prov}-operator-has-no-receipt", "POST", "/v1/ai-archives/receipt", host=("127.0.0.1", oport), body=b"x", headers={"Content-Type": "application/zip"})
        A(f"{prov}.receipt_route_404_on_operator_port", st == 404, f"status={st}")
    st, _, b = http_req("edge-ready", "GET", "/health/ready", host=("127.0.0.1", 9464))
    A("edge.ready_with_receivers_up", st == 200, f"status={st}")


def s2_pair():
    for t, u in ((1, U1), (2, U2)):
        c, p, j = pair(t)
        A(f"pair.u{t}_pairing_code_201", c == 201, f"status={c}")
        A(f"pair.u{t}_paired_201", p == 201 and j.get("user_id") == u and j.get("credential"), f"status={p} user_matches={j.get('user_id') == u}")
        state[f"cred{t}"] = j.get("credential"); state[f"dev{t}"] = j.get("device_id")
        # a paired device kind check is also what makes prepare 404 for a non-export_agent principal
    st, _, b = http_req("edge-capabilities-u1", "GET", "/v1/capabilities", bearer(state["cred1"]))
    j = js(b)
    (EV / "edge-capabilities.json").write_text(json.dumps(j, indent=1))
    txt = json.dumps(j)
    A("edge.capabilities_200_with_device_credential", st == 200, f"status={st}")
    svc = {s["service"]: s for s in j.get("services", [])}
    A("edge.capabilities_report_chatgpt_and_claude_fresh", all(svc.get(p, {}).get("document") and not svc[p].get("stale") for p in ("chatgpt", "claude")),
      "chatgpt=%s claude=%s" % (svc.get("chatgpt", {}).get("stale"), svc.get("claude", {}).get("stale")))


def s3_uploads():
    c1 = state["cred1"]
    plan = [
        ("chatgpt", "chatgpt-conversations-only.zip", "succeeded", None, 65536),
        ("chatgpt", "chatgpt-full.zip", "succeeded", None, 65536),
        ("chatgpt", "chatgpt-multichunk.zip", "succeeded", None, 65536),
        ("chatgpt", "chatgpt-asset-missing.zip", "partially_succeeded", "ai_archive.import.incomplete", 65536),
        ("claude", "claude-complete.zip", "succeeded", None, 65536),
        ("claude", "claude-nofiles.zip", "succeeded", None, 65536),
        ("claude", "claude-reference-only.zip", None, None, 65536),
        ("chatgpt", "corrupt.zip", "failed", None, 65536),
    ]
    state["ops"] = {}
    for prov, name, want, want_code, chunk in plan:
        u, op, fj = full_upload(prov, c1, name, chunk)
        got = op.get("status")
        codes = warn_codes(op)
        nchunks = len(u.chunks()) if u.data else 0
        tag = f"upload.{prov}.{name.replace('.zip', '')}"
        if want is None:
            print(f"INFO {tag}: observed status={got} codes={codes} (no expectation: reference-only knowledge file)")
        else:
            A(f"{tag}_{want}", got == want, f"op={u.op} chunks={nchunks} observed={got} codes={codes}")
        if want_code:
            A(f"{tag}_warning_{want_code}", want_code in codes, f"codes={codes}")
        state["ops"][name] = {"op": u.op, "status": got, "provider": prov, "codes": codes}
    # claude account row created by the first receipt (no row was inserted by hand)
    r = sh("q ratatoskr \"select count(*) from claude_archive.accounts\"").stdout.strip()
    A("claude.account_row_created_by_first_receipt", r not in ("", "0"), f"claude_archive.accounts rows={r}")
    r2 = sh("q ratatoskr \"select count(*) from chatgpt_archive.accounts\"").stdout.strip()
    A("chatgpt.account_row_created_by_first_receipt", r2 not in ("", "0"), f"chatgpt_archive.accounts rows={r2}")


def s4_unmapped():
    c2 = state["cred2"]
    for prov, name in (("chatgpt", "chatgpt-conversations-only.zip"), ("claude", "claude-complete.zip")):
        u = Upload(prov, c2, FX / name)
        u.prepare(); u.open()
        for i in range(len(u.chunks())):
            u.put(i)
        staging_before = sh(f"ls {S}/staging/edge | wc -l").stdout.strip()
        fs, fj, _ = u.finalize()
        A(f"unmapped.{prov}_finalize_403", fs == 403, f"status={fs} code={fj.get('code')}")
        A(f"unmapped.{prov}_code_account_unmapped", fj.get("code") == f"{prov}.account.unmapped", f"code={fj.get('code')}")
        op = u.poll(30)
        A(f"unmapped.{prov}_operation_failed", op.get("status") == "failed", f"status={op.get('status')} codes={warn_codes(op)}")
        A(f"unmapped.{prov}_delivery_failed_code", "platform.ai_archive.delivery_failed" in warn_codes(op), f"codes={warn_codes(op)}")
        gone = sh(f"find {S}/staging/edge -name '*{u.op}*' | wc -l").stdout.strip()
        A(f"unmapped.{prov}_staging_removed", gone == "0", f"staging entries for op={gone} (dir listing before={staging_before})")
        st, _, _ = http_req("u2-capabilities-after", "GET", "/v1/capabilities", bearer(c2))
        A(f"unmapped.{prov}_pairing_still_works", st == 200, f"status={st}")
    log = (S / "logs/chatgpt.log").read_text() + (S / "logs/claude.log").read_text()
    A("unmapped.receiver_logs_closed_class_for_refusal", "unmapped" in log.lower(), "searched receiver logs for 'unmapped'")


def s5_receiver_down():
    c1 = state["cred1"]
    for prov, name, svc in (("chatgpt", "chatgpt-conversations-only.zip", "chatgpt"),):
        u = Upload(prov, c1, FX / name, key=f"smoke-down-{os.urandom(3).hex()}")
        # change the bytes so this is a fresh operation (append a stored-zip-neutral change is not possible; use a fresh key + same bytes would replay)
        data = (FX / "chatgpt-full.zip").read_bytes()
        u.data = data; u.sha = hashlib.sha256(data).hexdigest(); u.path = FX / "chatgpt-full.zip"; u.tag = "down-chatgpt"
        u.key = f"smoke-down-{os.urandom(3).hex()}"
        st, j = u.prepare()
        A("receiver_down.prepare_202_for_new_key", st == 202, f"status={st} op={u.op}")
        u.open()
        for i in range(len(u.chunks())):
            u.put(i)
        sh(f"svc_stop {svc}")
        fs, fj, _ = u.finalize()
        A("receiver_down.finalize_502_or_503", fs in (502, 503), f"status={fs} code={fj.get('code')}")
        st, _, b = http_req("down-op", "GET", f"/v1/operations/{u.op}", bearer(c1))
        A("receiver_down.operation_stays_accepted", js(b).get("status") == "accepted", f"status={js(b).get('status')}")
        sh("svc_start chatgpt")
        for _ in range(40):
            if http_req("down-ready", "GET", "/health/ready", host=("127.0.0.1", 9085), save=False)[0] == 200:
                break
            time.sleep(1)
        time.sleep(3)
        fs, fj, _ = u.finalize()
        A("receiver_down.same_finalize_succeeds_after_restart", fs == 200, f"status={fs} code={fj.get('code')} outcome={fj.get('outcome')}")
        op = u.poll(120)
        A("receiver_down.operation_reaches_succeeded", op.get("status") in ("succeeded", "partially_succeeded"), f"status={op.get('status')} codes={warn_codes(op)}")


def s6_direct_receipt():
    claims = {"x-ratatoskr-user-id": U1, "x-ratatoskr-device-id": state["dev1"] or U1, "x-correlation-id": "correlation:smoke-direct",
              "x-ratatoskr-operation-id": "01980000-0000-7000-8000-0000000000f1", "x-ratatoskr-archive-sha256": "0" * 64, "x-ratatoskr-archive-byte-size": "3"}
    h = ("127.0.0.1", 8096)
    st, rh, b = http_req("direct-octet", "POST", "/v1/ai-archives/receipt", {**claims, "Content-Type": "application/octet-stream", "Content-Length": "3"}, b"abc", host=h)
    A("direct.octet_stream_400_error_envelope", st == 400 and "code" in js(b), f"status={st} body={b[:200].decode(errors='replace')}")
    st, rh, b = http_req("direct-authz", "POST", "/v1/ai-archives/receipt", {**claims, "Content-Type": "application/zip", "Authorization": "Bearer x"}, b"abc", host=h)
    A("direct.authorization_header_401", st == 401, f"status={st} body={b[:200].decode(errors='replace')}")
    st, rh, b = http_req("direct-get", "GET", "/v1/ai-archives/receipt", host=h)
    A("direct.get_405_json", st == 405 and "code" in js(b), f"status={st} body={b[:200].decode(errors='replace')}")


def s7_ceilings():
    c1 = state["cred1"]
    big = 2 * 1024 ** 3 + 1
    u = Upload("chatgpt", c1, FX / "chatgpt-conversations-only.zip", key=f"smoke-big-{os.urandom(3).hex()}")
    st, j = u.prepare(size=big, sha="1" * 64)
    A("ceiling.declared_size_above_2GiB_413", st == 413, f"status={st} code={j.get('code')}")
    # chunk boundary: declare 20 MiB with the 16 MiB chunk ceiling; a 16 MiB chunk is accepted, one byte more is refused
    sha = "2" * 64
    u2 = Upload("chatgpt", c1, FX / "chatgpt-conversations-only.zip", chunk=16 * 1024 * 1024, key=f"smoke-chunk-{os.urandom(3).hex()}")
    u2.data = b"\0" * (20 * 1024 * 1024); u2.sha = sha; u2.tag = "chunkmax"
    st, j = u2.prepare()
    A("ceiling.prepare_20MiB_202", st == 202, f"status={st}")
    st, j = u2.open()
    A("ceiling.open_session_16MiB_chunks_201", st == 201, f"status={st} code={j.get('code')}")
    cs, cj = u2.put(0, b"\0" * (16 * 1024 * 1024 + 1))
    A("ceiling.chunk_one_byte_above_max_413", cs == 413, f"status={cs} code={cj.get('code')}")
    cs, cj = u2.put(0, b"\0" * (16 * 1024 * 1024))
    A("ceiling.chunk_at_max_200", cs == 200, f"status={cs} code={cj.get('code')}")
    state["unfinished_op"] = u2.op


def s8_edge_restart():
    c1 = state["cred1"]
    u = Upload("chatgpt", c1, FX / "chatgpt-multichunk.zip", key=f"smoke-resume-{os.urandom(3).hex()}")
    # chunk size 65536 gives >= 2 chunks; use a fresh sha by suffixing a stored ZIP comment-free change is unnecessary: use a new archive
    data = (FX / "chatgpt-multichunk.zip").read_bytes()
    n = len(data)
    A("resume.fixture_is_multichunk", n > 2 * 65536, f"bytes={n}")
    # distinct bytes: append trailing junk after the end-of-central-directory comment is invalid; instead use the full archive of a different provider tag is not possible,
    # so make the content distinct by choosing a different chunk size (the digest of the archive is the same as an earlier operation: idempotency is by key)
    u.chunk = 65536
    u.tag = "resume"
    st, j = u.prepare()
    A("resume.prepare_202", st == 202, f"status={st} op={u.op} code={j.get('code')}")
    u.open()
    cs, _ = u.put(0)
    A("resume.chunk0_200", cs == 200, f"status={cs}")
    sh("svc_stop edge")
    time.sleep(1)
    sh("svc_start edge")
    for _ in range(30):
        if http_req("edge-ready-poll", "GET", "/health/ready", host=("127.0.0.1", 9464), save=False)[0] == 200:
            break
        time.sleep(1)
    st, j = u.status()
    A("resume.status_shows_chunk0_after_edge_restart", st == 200 and j.get("received_chunks") == [0] and j.get("session_state") == "open", f"status={st} body={json.dumps(j)[:300]}")
    for i in range(1, len(u.chunks())):
        u.put(i)
    fs, fj, _ = u.finalize()
    A("resume.finalize_200", fs == 200, f"status={fs} code={fj.get('code')}")
    op = u.poll(180)
    A("resume.same_operation_reaches_terminal", op.get("status") in TERMINAL, f"op={u.op} status={op.get('status')}")
    # preparing the same bytes again with the same key returns the same operation
    st, j = Upload.prepare(u)
    A("resume.same_key_same_bytes_same_operation", st in (200, 202) and j.get("operation_id") == u.op, f"status={st} op={j.get('operation_id')} expected={u.op}")
    u3 = Upload("chatgpt", c1, FX / "chatgpt-multichunk.zip", key=f"smoke-newkey-{os.urandom(3).hex()}")
    st, j = u3.prepare()
    print(f"INFO resume.same_bytes_new_key: status={st} op={u3.op} (same as first={u3.op == u.op})")
    # a corrupt archive that failed once ends failed at once when uploaded again
    uc, opc, _ = full_upload("chatgpt", c1, "corrupt.zip")
    A("resume.corrupt_archive_failed_again", opc.get("status") == "failed", f"status={opc.get('status')}")


def s9_connz():
    def conns():
        j = json.loads(sh("curl -s 'http://127.0.0.1:8222/connz?auth=true'").stdout)
        return j.get("num_connections"), sorted((c.get("name") or c.get("nkey", "")[:6], c.get("ip")) for c in j.get("connections", []))
    n1, c1 = conns(); time.sleep(60); n2, c2 = conns()
    A("connz.importer_connections_constant_over_60s_idle", n1 == n2, f"before={n1} after={n2}")
    (EV / "connz.json").write_text(json.dumps({"before": c1, "after": c2}, default=str))


def s10_facts():
    seed = str(S / "nk/edge.nkey")
    info = natsprobe.stream_subjects(seed, "ratatoskr_events", "evt.ai_archive.>")
    st = info.get("state", {})
    subjects = st.get("subjects", {})
    (EV / "stream-state.json").write_text(json.dumps(st, indent=1))
    A("facts.ai_archive_subjects_on_events_stream", bool(subjects), f"subjects={json.dumps(subjects)}")
    first, last = st.get("first_seq", 1), st.get("last_seq", 0)
    msgs = [m for m in natsprobe.stream_messages(seed, "ratatoskr_events", first, last) if m["subject"].startswith("evt.ai_archive.")]
    tenants = set(); producers = set()
    for m in msgs:
        try:
            env = json.loads(m["data"]); tenants.add(env.get("tenant_id")); producers.add(env.get("producer"))
        except Exception:
            tenants.add("<unparsed>")
    A("facts.tenant_is_user_U1", tenants == {f"user:{U1}"}, f"tenants={tenants} producers={producers} count={len(msgs)}")
    # consumer pending (Knowledge is not running here: its ai_archive durable accumulates the retained facts)
    j = json.loads(sh("curl -s 'http://127.0.0.1:8222/jsz?consumers=true&config=true'").stdout)
    rows = [(c["name"], c.get("num_pending"), c.get("num_ack_pending")) for s in j["account_details"][0]["stream_detail"] for c in s.get("consumer_detail", [])]
    (EV / "consumers.json").write_text(json.dumps(rows))
    d = {n: (p, a) for n, p, a in rows}
    A("facts.platform_projections_have_no_backlog", all(d.get(n, (1, 1)) == (0, 0) for n in ("platform_ai_archive_chatgpt_projection", "platform_ai_archive_claude_projection")), f"{ {k: d.get(k) for k in ('platform_ai_archive_chatgpt_projection', 'platform_ai_archive_claude_projection')} }")


def s11_nats_log():
    out = sh(f"rg -c 'Publish Violation|Subscription Violation|Authorization Violation' {S}/logs/nats.log || true").stdout.strip()
    lines = sh(f"rg 'Publish Violation|Subscription Violation|Authorization Violation' {S}/logs/nats.log | head -20 || true").stdout
    (EV / "nats-violations.txt").write_text(lines)
    A("nats.no_acl_violations_in_log", out in ("", "0"), f"count={out or 0}\n{lines[:1200]}")


def s12_sigkill_edge():
    c1 = state["cred1"]
    u = Upload("chatgpt", c1, FX / "chatgpt-multichunk.zip", key=f"smoke-kill-{os.urandom(3).hex()}")
    u.tag = "kill"
    st, j = u.prepare(); u.open()
    cs, _ = u.put(0); cs1, _ = u.put(1)
    A("sigkill.chunks_0_1_200", cs == 200 and cs1 == 200, f"{cs} {cs1}")
    sh("svc_kill edge")
    st0, _, _ = http_req("edge-down-probe", "GET", "/health/ready", host=("127.0.0.1", 9464), save=False, timeout=3)
    A("sigkill.edge_is_down", st0 == 0, f"probe status={st0}")
    sh("svc_start edge")
    for _ in range(30):
        if http_req("edge-ready-poll", "GET", "/health/ready", host=("127.0.0.1", 9464), save=False)[0] == 200:
            break
        time.sleep(1)
    st, j = u.status()
    A("sigkill.status_shows_chunks_0_1_after_hard_kill", st == 200 and j.get("received_chunks") == [0, 1], f"status={st} body={json.dumps(j)[:240]}")
    for i in range(2, len(u.chunks())):
        u.put(i)
    fs, fj, _ = u.finalize()
    op = u.poll(180)
    A("sigkill.finalize_200_and_terminal_succeeded", fs == 200 and op.get("status") == "succeeded", f"finalize={fs} status={op.get('status')}")
    ucl, opcl, _ = full_upload("claude", c1, "corrupt.zip")
    A("claude.corrupt_archive_ends_failed", opcl.get("status") == "failed", f"status={opcl.get('status')} codes={warn_codes(opcl)}")


def s13_series():
    """The cumulative series of flow F6 (R3-06): three exports per provider for tenant 1, one for tenant 2. Tenant 2 is mapped first, because the receivers answered 403 for it in s4."""
    r = sh("map_second_user")
    A("series.second_user_mapped_and_importers_restarted", r.returncode == 0, r.stdout[-200:] + r.stderr[-200:])
    for provider, names in (("chatgpt", [f"chatgpt-series-{n}.zip" for n in (1, 2, 3)]), ("claude", [f"claude-series-{n}.zip" for n in (1, 2, 3)])):
        for name in names:
            u, op, fj = full_upload(provider, state["cred1"], name)
            A(f"series.u1.{provider}.{name.replace('.zip', '')}_terminal", op.get("status") in ("succeeded", "partially_succeeded"), f"op={u.op} status={op.get('status')} codes={warn_codes(op)}")
    for provider, name in (("chatgpt", "chatgpt-u2.zip"), ("claude", "claude-u2.zip")):
        u, op, fj = full_upload(provider, state["cred2"], name)
        A(f"series.u2.{provider}.{name.replace('.zip', '')}_terminal", op.get("status") in ("succeeded", "partially_succeeded"), f"op={u.op} status={op.get('status')} codes={warn_codes(op)}")


SECTIONS = [("s1", s1_surface), ("s2", s2_pair), ("s3", s3_uploads), ("s4", s4_unmapped), ("s5", s5_receiver_down),
            ("s6", s6_direct_receipt), ("s7", s7_ceilings), ("s8", s8_edge_restart), ("s9", s9_connz), ("s10", s10_facts), ("s12", s12_sigkill_edge), ("s13", s13_series), ("s11", s11_nats_log)]

if __name__ == "__main__":
    want = set(sys.argv[1:])
    EV.mkdir(parents=True, exist_ok=True)
    if (S / "conf/state.json").exists():
        state.update(json.loads((S / "conf/state.json").read_text()))
    for name, fn in SECTIONS:
        if want and name not in want:
            continue
        print(f"=== {name} {fn.__name__}", flush=True)
        try:
            fn()
        except Exception as e:
            import traceback
            A(f"{name}.section_completed", False, f"{type(e).__name__}: {e}\n{traceback.format_exc()[-800:]}")
        (S / "conf/state.json").write_text(json.dumps(state))
    npass = sum(1 for _, ok, _ in results if ok)
    print(f"SUMMARY pass={npass} fail={len(results) - npass}")
    (EV / f"asserts-{'-'.join(sorted(want)) or 'all'}.txt").write_text("\n".join(f"{'PASS' if ok else 'FAIL'} {n} {d}" for n, ok, d in results))

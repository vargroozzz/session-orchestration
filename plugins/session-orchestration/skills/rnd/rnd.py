#!/usr/bin/env python3 -I
"""R&D measurement over Claude Code transcripts. Read-only; prints short TSV rows, never transcript bodies.

usage: python3 -I rnd.py [--until YYYY-MM-DDTHH:MM[:SS]] CMD [args]
  sessions [days=7]               one row per session: turns, peak context, compactions, tokens, USD, human msgs,
                                  denials, `!` handoffs, AskUserQuestion, tool errors, cross-session in/out, first prompt
  events [days=7]                 one row per event: deny, bang (a session suggests `! cmd`), ran (the user ran a
                                  `!` command), ask, err, bash (+ permission reasonType), self (admitted mistake),
                                  human, xmsg; snippets capped at 220 chars. Last column `test`: -p or dontAsk for
                                  a headless test session (leave those out of refusal counts), else empty
  context [days=7] [split_iso] [project_rx]  context per request (avg, median, >200K and excess, base median) for
                                  all, since split, and matching projects; `over` rows per session; `fork` rows
  units [days=7] [--project RX] [--merge|--done|--post RX]  merged PRs, finished tickets, review posts whose
                                  command ran, one row each; USD per unit on stderr
  waits [days=7] [min=5]          tool calls whose result came back >= min minutes later (prompts, hangs)
  bgtasks REGEX [days=7]              background Bash launches vs. their completion notices (SILENT = died with
                                  its session); totals on stderr
  replies [days=7]                task sessions idle > 6 h that never wrote replies/<KEY>* (lost reports); totals on stderr
  triggers SESSION_PREFIX [days=7]     a session's wakes, requests and USD by trigger: human/xmsg/bgtask/cron/other
  usage [days=30]                 one row per plugin feature (pane button, tool, skill, doc, session-status flag,
                                  config key): uses in the window, first seen, `unused` when 0 uses all window;
                                  presses from the local usage log (telemetry=local), which it trims to 180 days
  chunks [days=7] [--session PREFIX]  one row per chunk (first prompt `Chunk: KEY/N`, successors joined through
                                  Supersedes: and summed) or per matching session: kind/model/effort, est, act growth
                                  (K), peak, cache read, out, USD, turns, compactions, handoff (none|before|after a
                                  compaction), minutes; then a `ratio` line per kind (median act/est, last 20)
  trial [days=28]                 the planner trial's arms side by side (tasks with a chunk session vs the rest):
                                  units, median USD and tokens per unit, peak, compactions, handoffs, /code-review
                                  findings and runs per unit, step-ins per unit
  html IN.md OUT.html            Markdown report -> self-contained HTML

Transcripts: <account>/projects/*/*.jsonl for every account dir ($CLAUDE_CONFIG_DIR, ~/.claude, ~/.claude-*),
each distinct projects/ tree once (accounts that share one through a symlink are read once).
The window is the `days` before --until (UTC, default now): rerun an old window with --until.
Cost uses rough Opus-class list rates (USD/Mtok in, out, cache read, cache write), override via env RATES="in,out,cr,cw".
"""
import glob, html, json, os, re, statistics, sys, time
from datetime import datetime, timezone

R_IN, R_OUT, R_CR, R_CW = map(float, os.environ.get("RATES", "5,25,0.5,10").split(","))
HOME = os.path.expanduser("~")
P = lambda s: datetime.fromisoformat(s.replace("Z", "+00:00"))
END = time.time()


def window(days):
    global CUT, CUT_ISO, END_ISO
    CUT = END - float(days) * 86400
    CUT_ISO = time.strftime("%Y-%m-%dT%H:%M", time.gmtime(CUT))
    END_ISO = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(END))


def out_of(ts):
    """A timestamped line outside the window. Lines without a timestamp always count."""
    return bool(ts) and (ts < CUT_ISO or ts[:19] > END_ISO)


def roots():
    seen = []
    for d in [os.environ.get("CLAUDE_CONFIG_DIR") or f"{HOME}/.claude", f"{HOME}/.claude"] + sorted(glob.glob(f"{HOME}/.claude-*")):
        p = os.path.realpath(os.path.join(os.path.expanduser(d), "projects"))
        if os.path.isdir(p) and p not in seen:
            seen.append(p)
    return seen


def transcripts():
    for r in roots():
        for f in glob.glob(f"{r}/*/*.jsonl"):
            if os.path.getmtime(f) >= CUT:
                yield f


def lines(f):
    for line in open(f, errors="replace"):
        try:
            yield line, json.loads(line)
        except Exception:
            continue


def usd(i, o, cr, cw):
    return (i * R_IN + o * R_OUT + cr * R_CR + cw * R_CW) / 1e6


def clip(s, n=220):
    return re.sub(r"\s+", " ", str(s))[:n]


def sessions(days=7):
    window(days)
    home_enc = re.sub(r"[^A-Za-z0-9]", "-", HOME) + "-"
    print("project\tsession\tname\tstart\tend\tturns\tpeak_ctx\tcompacts\tout_tok\tcache_write\tcache_read\tusd\thuman_msgs\tdenials\tbang_cmds\tasks\ttool_errs\txmsg_in\tsendmsg\tfirst_prompt")
    for f in transcripts():
        seen, peak, comp, out, cw, cr, inp = set(), 0, 0, 0, 0, 0, 0
        human = den = bang = asks = errs = xin = sm = 0
        name, first, ts = "", "", []
        for _, o in lines(f):
            t = o.get("type")
            if out_of(o.get("timestamp")):
                continue  # only activity inside the window
            if o.get("timestamp"):
                ts.append(o["timestamp"])
            if t == "agent-name":
                name = o.get("agentName") or name
            if t == "system" and o.get("subtype") == "compact_boundary":
                comp += 1
            pd = o.get("permissionDecision") or {}
            if pd.get("decision") == "reject":
                den += 1
            m = o.get("message") or {}
            c = m.get("content")
            if t == "assistant" and not o.get("isSidechain"):
                u = m.get("usage") or {}
                rid = o.get("requestId")
                if rid and rid not in seen:
                    seen.add(rid)
                    ctx = u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0) + u.get("cache_creation_input_tokens", 0)
                    peak = max(peak, ctx)
                    out += u.get("output_tokens", 0); cw += u.get("cache_creation_input_tokens", 0)
                    cr += u.get("cache_read_input_tokens", 0); inp += u.get("input_tokens", 0)
                for b in c if isinstance(c, list) else []:
                    if b.get("type") == "text" and re.search(r"`! [a-z~/]", b.get("text", "")):
                        bang += 1
                    if b.get("type") == "tool_use":
                        if b.get("name") == "AskUserQuestion": asks += 1
                        if b.get("name") == "SendMessage": sm += 1
            if t == "user" and not o.get("isSidechain"):
                if isinstance(c, str):
                    txt = c
                elif isinstance(c, list):
                    txt = " ".join(b.get("text", "") for b in c if b.get("type") == "text")
                    errs += sum(1 for b in c if b.get("type") == "tool_result" and b.get("is_error"))
                else:
                    txt = ""
                if "cross-session-message" in txt:
                    xin += 1
                elif txt and not o.get("toolUseResult") and not txt.startswith("<") and not o.get("isMeta"):
                    human += 1
                    if not first:
                        first = re.sub(r"\s+", " ", txt)[:100]
        if not seen:
            continue
        proj = os.path.basename(os.path.dirname(f)).replace(home_enc, "")
        sid = os.path.basename(f)[:8]
        print("\t".join(map(str, [proj[-45:], sid, name, min(ts)[:16], max(ts)[:16], len(seen), peak, comp, out, cw, cr,
                                  round(usd(inp, out, cr, cw), 2), human, den, bang, asks, errs, xin, sm, first.replace("\t", " ")])))


SELF = re.compile(r"\b(I was wrong|my mistake|I retract|retracting|I misread|that was wrong|I got that wrong|correction:|I stand corrected|wrongly (said|claimed)|I (incorrectly|wrongly))\b", re.I)


def events(days=7):
    window(days)
    print("session\tts\tkind\tdetail\tdetail2\ttest")
    for f in transcripts():
        sid = os.path.basename(f)[:8]
        test = headless(f)
        uses = {}  # tool_use_id -> (name, input)
        for _, o in lines(f):
            ts = o.get("timestamp", "")
            if out_of(ts) or o.get("isSidechain"):
                continue
            m = o.get("message") or {}
            c = m.get("content")
            blocks = c if isinstance(c, list) else []
            row = lambda k, a, b="": print("\t".join([sid, ts[:16], k, clip(a), clip(b), test]))
            if o.get("type") == "assistant":
                for b in blocks:
                    if b.get("type") == "tool_use":
                        uses[b.get("id")] = (b.get("name"), b.get("input") or {})
                        if b.get("name") == "AskUserQuestion":
                            qs = (b.get("input") or {}).get("questions") or [{}]
                            row("ask", qs[0].get("question", ""))
                    if b.get("type") == "text":
                        t = b.get("text", "")
                        for cmd in re.findall(r"`! ([^`]+)`", t):
                            row("bang", cmd)
                        mm = SELF.search(t)
                        if mm:
                            row("self", t[max(0, mm.start() - 80): mm.start() + 160])
            if o.get("type") == "user":
                pd = o.get("permissionDecision") or {}
                for b in blocks:
                    if b.get("type") != "tool_result":
                        continue
                    name, inp = uses.get(b.get("tool_use_id"), ("?", {}))
                    arg = inp.get("command") or inp.get("file_path") or inp.get("to") or json.dumps(inp)[:200]
                    if pd.get("decision") == "reject":
                        row("deny", f"{name}: {arg}", f"{pd.get('source')}/{pd.get('reasonType')}")
                    elif b.get("is_error"):
                        rc = b.get("content")
                        rc = rc if isinstance(rc, str) else " ".join(x.get("text", "") for x in rc or [] if isinstance(x, dict))
                        row("err", f"{name}: {arg}", rc.strip().split("\n")[0])
                    if name == "Bash":
                        row("bash", inp.get("command", ""), pd.get("reasonType") or pd.get("source") or "")
                txt = c if isinstance(c, str) else " ".join(b.get("text", "") for b in blocks if b.get("type") == "text")
                k = said(o, txt)
                if k == "xmsg":
                    mm = re.search(r"<cross-session-message[^>]*>", txt)
                    row("xmsg", mm.group(0) if mm else "", txt[mm.end():][:200] if mm else "")
                elif k == "ran":
                    for cmd in RAN.findall(txt):
                        row("ran", cmd.strip())
                elif k == "human":
                    row("human", txt)


RAN = re.compile(r"<bash-input>([\s\S]*?)</bash-input>")


def said(o, txt):
    """What a user line's text is: xmsg (another session), ran (the user's `!` commands), human, or ''."""
    if "cross-session-message" in txt:
        return "xmsg"
    if "<bash-input>" in txt:
        return "ran"
    return "human" if txt and not o.get("toolUseResult") and not txt.startswith("<") and not o.get("isMeta") \
        and not o.get("isCompactSummary") else ""


def headless(f):
    """A test session: a `-p` run (entrypoint sdk-cli) or one in dontAsk mode (permission tests); '' otherwise."""
    s = open(f, errors="replace").read()
    return "-p" if '"entrypoint":"sdk-cli"' in s else "dontAsk" if '"permissionMode":"dontAsk"' in s else ""


def requests(f, whole=False):
    """Main-loop requests inside the window (all of them if WHOLE), each once: (ts, context tokens, usage)."""
    seen = set()
    for _, o in lines(f):
        ts = o.get("timestamp") or ""
        rid = o.get("requestId")
        if (out_of(ts) and not whole) or o.get("type") != "assistant" or o.get("isSidechain") or not rid or rid in seen:
            continue
        seen.add(rid)
        u = (o.get("message") or {}).get("usage") or {}
        yield ts, u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0) + u.get("cache_creation_input_tokens", 0), u


def context(days=7, split="", project=""):
    """Context per request: a row per scope (all, since SPLIT, projects matching PROJECT): requests, average, median,
    over 200K and their excess, base (a session's first request, for sessions that started in the window) median.
    Then `over` rows (sessions with requests over 200K) and `fork` rows (session pairs sharing >= 10 messages)."""
    window(days)
    reqs, first, ids = [], {}, {}
    for f in transcripts():
        sid, proj = os.path.basename(f)[:8], os.path.basename(os.path.dirname(f))
        ids[sid] = {o["uuid"] for _, o in lines(f) if o.get("uuid") and o.get("type") in ("user", "assistant")}
        mine = [(sid, proj, ts, c) for ts, c, _ in requests(f)]
        reqs += mine
        # Base: the transcript's very first request, if that falls in the window (a session started before it doesn't count).
        start = next(requests(f, whole=True), None)
        if start and not out_of(start[0]):
            first[sid] = (sid, proj, start[0], start[1])
    print("scope\treqs\tavg\tmedian\tover200K\texcess\tbase_median\tbase_n")
    med = lambda xs: sorted(xs)[len(xs) // 2] if xs else 0
    scopes = [("all", lambda r: True)] + ([(f"since {split}", lambda r: r[2] >= split)] if split else []) \
        + ([(f"project {project}", lambda r: re.search(project, r[1]))] if project else [])
    for label, keep in scopes:
        rs, base = [r[3] for r in reqs if keep(r)], [v[3] for v in first.values() if keep(v)]
        big = [c for c in rs if c > 200_000]
        print("\t".join(map(str, [label, len(rs), round(sum(rs) / max(len(rs), 1)), med(rs), len(big),
                                  sum(c - 200_000 for c in big), med(base), len(base)])))
    over = {}
    for s, p, _, c in reqs:
        if c > 200_000:
            a = over.setdefault(s, [0, 0, 0, p])
            a[0] += 1; a[1] += c - 200_000; a[2] = max(a[2], c)
    for s, (n, e, pk, p) in sorted(over.items(), key=lambda kv: -kv[1][1]):
        print(f"over\t{s}\t{n}\t{e}\t{pk}\t{p[-45:]}")
    sids = sorted(ids)
    for i, a in enumerate(sids):
        for b in sids[i + 1:]:
            n = len(ids[a] & ids[b])
            if n >= 10:
                print(f"fork\t{a}\t{b}\t{n}")


# Right after the CLI's name (`…-cli[@version]`, `gh` or `glab`), so a heredoc or grep that only mentions one doesn't
# count. The PR number may follow a `-R OWNER/REPO`. Posts: Bitbucket's `pr comment create`, gh's `pr comment` or
# `pr review`, glab's `mr note`.
CLI = r"(?:-cli(?:@\S+)?|\bgh|\bglab)\s+"
REPO = r"(?:(?:-R|--repo)[ =]\S+\s+)?"
UNITS = {"merge": CLI + r"(?:pr|mr) merge\s+" + REPO + r"(\d+)",
         "done": CLI + r"issue transition (\S+) --to \"?Ready for Test",
         "post": CLI + r"(?:pr comment create|pr comment|pr review|mr note)\s+" + REPO + r"(\d+)"}


def units(days=7, *opts):
    """Units of work whose command ran (its result is neither an error nor a denial): `merge`, `done` (a ticket
    finished) and `post` (a review comment posted from a review session: name or first prompt says review), one
    row per unit id, first time. --merge/--done/--post RX override the regexes (one capture group: the id);
    --project RX keeps transcripts whose project folder matches. The totals line on stderr gives USD per merge and per
    finished ticket over those sessions, and per post over the review sessions among them."""
    window(days)
    o_ = dict(zip(opts[::2], opts[1::2]))
    rx = {k: re.compile(o_.get(f"--{k}", v)) for k, v in UNITS.items()}
    proj = re.compile(o_.get("--project", ""))
    found, total, review = {}, 0.0, 0.0
    print("kind\tid\tsession\tts\tcommand")
    for f in transcripts():
        if not proj.search(os.path.basename(os.path.dirname(f))):
            continue
        sid = os.path.basename(f)[:8]
        cost = sum(usd(u.get("input_tokens", 0), u.get("output_tokens", 0), u.get("cache_read_input_tokens", 0),
                       u.get("cache_creation_input_tokens", 0)) for _, _, u in requests(f))
        total += cost
        hits, is_review = unit_hits(f, rx)
        for key, ts, cmd in hits:
            if key not in found:
                found[key] = sid
                print("\t".join([key[0], key[1], sid, ts[:16], clip(cmd, 120)]))
        if is_review:
            review += cost
    n = {k: sum(1 for key in found if key[0] == k) for k in UNITS}
    per = lambda k, v: f"{k}={v} per_{k}={(review if k == 'post' else total) / v:.1f}" if v else f"{k}=0"
    print(f"usd={total:.0f} review_usd={review:.1f} " + " ".join(per(k, v) for k, v in n.items()), file=sys.stderr)


def unit_hits(f, rx):
    """A transcript's units whose command ran: ([(key, ts, command)], whether it's a review session). key is
    (kind, id), or (kind, id, session) for a post."""
    sid, uses, name, first, hits = os.path.basename(f)[:8], {}, "", "", []
    for _, o in lines(f):
        ts = o.get("timestamp") or ""
        name = o.get("agentName") or name
        c = (o.get("message") or {}).get("content")
        if not first and o.get("type") == "user" and isinstance(c, str) and not c.startswith("<"):
            first = c[:200]
        # Only the conversation's own rows: an api-request-blob repeats a call with no timestamp.
        if out_of(ts) or o.get("isSidechain") or o.get("type") not in ("user", "assistant"):
            continue
        for b in c if isinstance(c, list) else []:
            if b.get("type") == "tool_use" and b.get("name") == "Bash":
                uses[b.get("id")] = (ts, (b.get("input") or {}).get("command", ""))
            if b.get("type") != "tool_result" or b.get("tool_use_id") not in uses:
                continue
            ts, cmd = uses.pop(b["tool_use_id"])  # a result line may carry no timestamp: the call's
            if b.get("is_error") or (o.get("permissionDecision") or {}).get("decision") == "reject" or "--help" in cmd:
                continue
            repo = re.search(r"(?:--repo|-R)[ =](\S+)", cmd)
            for k, r in rx.items():
                if k == "post" and not re.search("review", name + first, re.I):
                    continue
                for uid in r.findall(cmd):
                    uid = f"{repo.group(1)}#{uid}" if repo and k != "done" else uid  # PR numbers repeat across repos
                    hits.append(((k, uid, sid) if k == "post" else (k, uid), ts, cmd))  # a later review round is another post
    return hits, bool(re.search("review", name + first, re.I))


SUP = re.compile(r"(?:Supersedes: |[Yy]ou replace (?:session )?)([0-9a-f]{8})")


def stat(f):
    """One session's numbers inside the window, for chunks and trial. growth: the sum of context increases between
    requests (each message id once), not counting a session's first request or the one after a compaction."""
    s = dict(sid=os.path.basename(f)[:8], first="", ts0="", ts1="", growth=0, peak=0, inp=0, out=0, cr=0, cw=0,
             turns=0, comp=0, models={}, findings=0, reviews=0, steps=0)
    seen, prev = set(), None
    for _, o in lines(f):
        ts, t = o.get("timestamp") or "", o.get("type")
        m = o.get("message") or {}
        c = m.get("content")
        blocks = c if isinstance(c, list) else []
        txt = c if isinstance(c, str) else " ".join(b.get("text", "") for b in blocks if b.get("type") == "text")
        if t == "user" and not s["first"] and not o.get("isSidechain") and said(o, txt) == "human":
            s["first"], s["ts0"] = txt, ts  # the brief, even before the window (it holds the markers); not a step-in
            continue
        if out_of(ts) or o.get("isSidechain"):
            continue
        if t == "system" and o.get("subtype") == "compact_boundary":
            s["comp"] += 1
            prev = None
        if t == "assistant":
            rid = m.get("id") or o.get("requestId")
            if rid and rid not in seen:
                seen.add(rid)
                u = m.get("usage") or {}
                ctx = u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0) + u.get("cache_creation_input_tokens", 0)
                s["growth"] += max(0, ctx - prev) if prev is not None else 0
                prev = ctx
                s["peak"] = max(s["peak"], ctx)
                s["inp"] += u.get("input_tokens", 0); s["out"] += u.get("output_tokens", 0)
                s["cr"] += u.get("cache_read_input_tokens", 0); s["cw"] += u.get("cache_creation_input_tokens", 0)
                s["turns"] += 1
                s["ts1"] = max(s["ts1"], ts)
                mod = re.search(r"opus|sonnet|haiku|fable", str(m.get("model")))
                if mod:
                    s["models"][mod.group(0)] = s["models"].get(mod.group(0), 0) + 1
            for b in blocks:
                if b.get("type") == "tool_use" and b.get("name") == "ReportFindings":
                    s["findings"] += len((b.get("input") or {}).get("findings") or [])
                if b.get("type") == "tool_use" and b.get("name") == "Skill" and \
                        str((b.get("input") or {}).get("skill", "")).split(":")[-1] == "code-review":
                    s["reviews"] += 1
        if t == "user":
            s["reviews"] += len(re.findall(r"<command-name>/?(?:[\w-]+:)?code-review</command-name>", txt))
            k = said(o, txt)
            if k == "ran":
                s["steps"] += len(RAN.findall(txt))
            elif k == "human":
                s["steps"] += 1
    if not seen:
        return None
    # /code-review runs in a subagent (the session's subagents/ transcripts): it reports through ReportFindings, or as
    # a ```json list of findings (each with a failure_scenario) in its last message.
    for sub in glob.glob(f"{f[:-6]}/subagents/*.jsonl"):
        last = ""
        for _, o in lines(sub):
            if o.get("type") == "assistant" and not out_of(o.get("timestamp") or ""):
                for b in (o.get("message") or {}).get("content") or []:
                    if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") == "ReportFindings":
                        s["findings"] += len((b.get("input") or {}).get("findings") or [])
                    if isinstance(b, dict) and b.get("type") == "text":
                        last = b.get("text", "")
        for block in re.findall(r"```json\s*(\[[\s\S]*?\])\s*```", last):
            try:
                s["findings"] += sum(1 for x in json.loads(block) if isinstance(x, dict) and "failure_scenario" in x)
            except ValueError:
                pass
    mark = lambda rx: (re.search(rx, s["first"], re.M) or [None, ""])[1]
    # A key: `Session task: KEY` (trailing punctuation dropped), or a brief starting `Work on PROJ-123`.
    s.update(task=mark(r"^Session task: ([\w./-]*\w)") or mark(r"^Work on ([A-Za-z][\w]*-\d+)\b"), chunk=mark(r"^Chunk: (\S+)"), sup=mark(SUP.pattern),
             model=max(s["models"], key=s["models"].get, default="?"), usd=usd(s["inp"], s["out"], s["cr"], s["cw"]))
    s["ts0"] = s["ts0"] or s["ts1"]
    return s


def stats():
    """Every session's stat in the window, by 8-char id, with `task` and `chunk` carried to successors (Supersedes:)
    and `handoff` set on a predecessor: after (it was compacted first) or before."""
    ss = {}
    for f in transcripts():
        s = stat(f)
        if s:
            ss[s["sid"]] = s
    for s in sorted(ss.values(), key=lambda s: s["ts0"]):  # a predecessor starts first, so it's resolved first
        p = ss.get(s["sup"])
        if p:
            s["task"], s["chunk"] = s["task"] or p["task"], s["chunk"] or p["chunk"]
            p["handoff"] = "after" if p["comp"] else "before"
    return ss


def chunk_lines():
    """The usage log's chunk lines (lib.sh usage): [{t, what, model, effort, est, act}], up to the window's end."""
    log = os.path.join(STATE, "usage.jsonl")
    if not os.path.exists(log):
        return []
    return sorted((o for _, o in lines(log) if isinstance(o, dict) and o.get("k") == "chunk"
                   and isinstance(o.get("t"), (int, float)) and o["t"] <= END), key=lambda o: o["t"])


def chunks(days=7, *opts):
    """One row per chunk (sessions whose first prompt has `Chunk: KEY/N`, successors joined through Supersedes: and
    summed), or per session matching --session PREFIX. Kind, effort and est come from the usage log's chunk line
    when one matches, else `?`. Then a `ratio` line per kind: the median act/est over its last 20 chunk lines."""
    if str(days).startswith("--"):
        days, opts = 7, (days,) + opts
    window(days)
    o_ = dict(zip(opts[::2], opts[1::2]))
    if "--session" in o_:
        groups = {}
        for f in transcripts():
            s = os.path.basename(f).startswith(o_["--session"]) and stat(f)
            if s:
                s["chunk"] = s["chunk"] or s["sid"]
                groups[s["sid"]] = [s]
    else:
        groups = {}
        for s in stats().values():
            if s["chunk"]:
                groups.setdefault(s["chunk"], []).append(s)
    logged = chunk_lines()
    epoch = lambda ts: P(ts).timestamp()
    print("key\tchunk\tkind/model/effort\test\tact_K\tpeak\tcache_read\tout\tusd\tturns\tcompacts\thandoff\tminutes")
    for name, g in sorted(groups.items(), key=lambda kv: min(s["ts0"] for s in kv[1])):
        t0, t1 = min(s["ts0"] for s in g), max(s["ts1"] for s in g)
        act = sum(s["growth"] for s in g) / 1000
        # ponytail: a log line carries no key, so it's matched by time (from the chunk's start to an hour after its
        # last request) and then by the closest act; parallel chunks of the same size could swap. Add the key if so.
        near = [o for o in logged if epoch(t0) <= o["t"] <= epoch(t1) + 3600]
        hit = min(near, key=lambda o: abs((o.get("act") or 0) - act), default={})
        if hit:
            logged.remove(hit)
        key, _, n = name.rpartition("/")
        print("\t".join(map(str, [key or "-", n, f"{hit.get('what', '?')}/{g[0]['model']}/{hit.get('effort', '?')}",
                                  hit.get("est", "?"), round(act), max(s["peak"] for s in g), sum(s["cr"] for s in g),
                                  sum(s["out"] for s in g), round(sum(s["usd"] for s in g), 2), sum(s["turns"] for s in g),
                                  sum(s["comp"] for s in g), ",".join(s["handoff"] for s in g if s.get("handoff")) or "none",
                                  round((epoch(t1) - epoch(t0)) / 60)])))
    by = {}
    for o in chunk_lines():
        if o.get("est") and isinstance(o.get("act"), (int, float)):
            by.setdefault(o.get("what", "?"), []).append(o["act"] / o["est"])
    for kind, rs in sorted(by.items()):
        print(f"ratio\t{kind}\t{statistics.median(rs[-20:]):.2f}\tn={len(rs[-20:])}")


def trial(days=28):
    """The planner trial's two arms side by side: tasks (`Session task:` KEY, successors joined) with any chunk
    session, and the rest. Per arm: finished units (merges, finished tickets, as `units`), median USD per unit (per
    task), tokens per unit, median peak, compactions per session, handoffs before/after a compaction, /code-review
    findings (ReportFindings) and runs per unit, and step-ins (human messages after the brief, `!` commands) per unit.
    ponytail: changed lines per unit, reverted commits and an external reviewer's findings per PR need the code host
    or the adapter, not transcripts: chunk 3b."""
    window(days)
    ss = stats()
    files = {os.path.basename(f)[:8]: f for f in transcripts()}
    rx = {k: re.compile(v) for k, v in UNITS.items() if k != "post"}
    tasks = {}
    for s in ss.values():
        if s["task"]:
            tasks.setdefault(s["task"], []).append(s)
    arms = {"planner": {}, "off": {}}
    for key, g in tasks.items():
        found = {k for s in g for k, _, _ in unit_hits(files[s["sid"]], rx)[0]}
        arms["planner" if any(s["chunk"] for s in g) else "off"][key] = (g, len(found))
    med = lambda xs: statistics.median(xs) if xs else 0
    rows = []
    for arm, ts in arms.items():
        ses = [s for g, _ in ts.values() for s in g]
        n = sum(u for _, u in ts.values())
        per = lambda v: round(v / n, 2) if n else "-"
        tot = lambda k: sum(s[k] for s in ses)
        hand = [s.get("handoff") for s in ses]
        # The median is over tasks that finished something; the total also charges unfinished tasks' cost.
        rows.append([len(ts), len(ses), n, round(med([sum(s["usd"] for s in g) / u for g, u in ts.values() if u]), 2),
                     per(tot("usd")), per(tot("out")), per(tot("cr")), per(tot("cw")), med([s["peak"] for s in ses]),
                     round(tot("comp") / len(ses), 2) if ses else "-", hand.count("before"), hand.count("after"),
                     per(tot("findings")), per(tot("reviews")), per(tot("steps"))])
    print("measure\tplanner\toff")
    names = ["tasks", "sessions", "units", "usd_per_unit_median", "usd_per_unit_total", "out_per_unit", "cache_read_per_unit",
             "cache_write_per_unit", "peak_median", "compacts_per_session", "handoffs_before", "handoffs_after",
             "findings_per_unit", "reviews_per_unit", "stepins_per_unit"]
    for i, m in enumerate(names):
        print(f"{m}\t{rows[0][i]}\t{rows[1][i]}")


def waits(days=7, min_minutes=5):
    window(days)
    MIN = float(min_minutes)
    print("session\tts\tminutes\ttool\tdecision\tinput")
    for f in transcripts():
        sid = os.path.basename(f)[:8]
        pend = {}
        for _, o in lines(f):
            ts = o.get("timestamp")
            if not ts or out_of(ts) or o.get("isSidechain"):
                continue
            c = (o.get("message") or {}).get("content")
            for b in c if isinstance(c, list) else []:
                if b.get("type") == "tool_use":
                    inp = b.get("input") or {}
                    if inp.get("run_in_background"):
                        continue
                    pend[b["id"]] = (ts, b.get("name"), inp.get("command") or inp.get("file_path") or json.dumps(inp)[:150])
                if b.get("type") == "tool_result" and b.get("tool_use_id") in pend:
                    t0, name, arg = pend.pop(b["tool_use_id"])
                    mins = (P(ts) - P(t0)).total_seconds() / 60
                    pd = o.get("permissionDecision") or {}
                    if mins >= MIN and name not in ("Monitor", "ScheduleWakeup", "Agent"):
                        print("\t".join([sid, t0[:16], f"{mins:.0f}", name, f"{pd.get('source')}/{pd.get('reasonType')}", re.sub(r"\s+", " ", arg)[:160]]))


def bgtasks(regex=None, days=7):
    if not regex:
        sys.exit("usage: rnd.py bgtasks REGEX [days=7]")
    window(days)
    RX = re.compile(regex)
    tot = {"launched": 0, "notified": 0, "silent": 0}
    for f in transcripts():
        sid, uses, tasks, last = os.path.basename(f)[:8], {}, {}, ""
        for s, o in lines(f):
            ts = o.get("timestamp") or ""
            if ts and ts[:19] > END_ISO:
                continue  # a notice after the window doesn't count
            if ts:
                last = ts
            if ts and ts < CUT_ISO:
                continue
            c = (o.get("message") or {}).get("content")
            for b in c if isinstance(c, list) else []:
                if b.get("type") == "tool_use" and b.get("name") == "Bash":
                    i = b.get("input") or {}
                    if i.get("run_in_background") and RX.search(i.get("command", "")):
                        uses[b["id"]] = (ts, i.get("command", "")[:90])
                if b.get("type") == "tool_result" and b.get("tool_use_id") in uses:
                    m = re.search(r"with ID: (\w+)", json.dumps(b.get("content")))
                    if m:
                        tasks[m.group(1)] = uses[b["tool_use_id"]] + (None,)
            notices = re.findall(r"<task-notification>.*?</task-notification>", s) or [s]  # one line can batch several
            for tid in list(tasks):
                for n in notices:
                    if tasks[tid][2] is None and f"<task-id>{tid}</task-id>" in n:
                        st = re.search(r"<status>(\w+)</status>", n)
                        ex = re.search(r"exit code (\d+)", n)
                        tasks[tid] = tasks[tid][:2] + ((ts or last, st.group(1) if st else "?", ex.group(1) if ex else "-"),)
        for tid, (t0, cmd, note) in tasks.items():
            tot["launched"] += 1
            if note:
                tot["notified"] += 1
                # a notice line without a timestamp is timed by the line before it
                took = f"{(P(note[0]) - P(t0)).total_seconds() / 60:.0f}m" if note[0] and t0 else "-"
                print(f"{sid}\t{t0[:16]}\t{note[1]}/exit {note[2]}\t{took}\t{cmd}")
            elif last and P(last).timestamp() >= END - 1800:
                # ponytail: "active in the window's last 30 min" stands in for "still running"; a live process check
                # would be exact but can't replay an old window
                tot["running"] = tot.get("running", 0) + 1
                print(f"{sid}\t{t0[:16]}\tNO NOTICE YET (session active {last[:16]}, likely still running)\t-\t{cmd}")
            else:
                tot["silent"] += 1
                print(f"{sid}\t{t0[:16]}\tSILENT (session last active {last[:16]})\t-\t{cmd}")
    print(tot, file=sys.stderr)


TASK = re.compile(r"(?:Session task:|Work on)\s+(?:https?://\S+/browse/)?([A-Z]+-\d+)")


def replies(days=7):
    """Lost replies: task sessions (first prompt "Work on KEY", or "Session task: KEY") idle > 6 h that never wrote
    replies/<KEY>* (Write/Edit on it, or `>`, mv, cp, open() onto it)."""
    window(days)
    tot = {"task": 0, "wrote": 0, "lost": 0, "open": 0}
    for f in transcripts():
        key = last = name = None
        wrote = False
        for line, o in lines(f):
            ts = o.get("timestamp") or ""
            if ts and ts[:19] > END_ISO:
                break  # replaying an old window: what came after it doesn't count
            last = ts or last
            name = o.get("agentName") or name
            m = o.get("message") or {}
            if key is None and o.get("type") == "user" and not o.get("isSidechain") and not o.get("isMeta"):
                c = m.get("content")
                txt = c if isinstance(c, str) else " ".join(b.get("text", "") for b in c or [] if isinstance(b, dict))
                if txt.startswith("<") and "<cross-session-message" not in txt:
                    continue  # a slash command or caveat line, not the first prompt
                if "<cross-session-message" not in txt and (k := TASK.search(txt[:400])):
                    key = k.group(1)
                elif txt.strip():
                    key = ""  # the first prompt names no task: not a task session
            if key and o.get("type") == "assistant" and f"replies/{key}" in line:
                path = rf"replies/{re.escape(key)}(?!\d)"  # ABC-12 isn't ABC-123
                for b in m.get("content") or []:
                    i = (b.get("input") or {}) if isinstance(b, dict) and b.get("type") == "tool_use" else {}
                    # ponytail: `cp replies/KEY… elsewhere` still counts as a write; rare in practice
                    if re.search(path, i.get("file_path", "")) or \
                            re.search(rf"(>\s*|\bmv\b.*|\bcp\b.*|open\(.*)\S*{path}", i.get("command", "")):
                        wrote = True
        if not key:
            continue
        tot["task"] += 1
        if wrote:
            tot["wrote"] += 1
        elif last and P(last).timestamp() > END - 6 * 3600:
            tot["open"] += 1  # ponytail: active in the last 6 h stands in for "still working"
        else:
            tot["lost"] += 1
            print(f"{os.path.basename(f)[:8]}\t{key}\t{(last or '')[:16]}\t{name or ''}")
    print(tot, file=sys.stderr)


def triggers(sid, days=7):
    window(days)
    fs = [f for r in roots() for f in glob.glob(f"{r}/*/{sid}*.jsonl")]
    if not fs:  # a session name (session-status --coordinator prints names): its newest transcript in the window
        tag = f'"agentName":"{sid}"'
        fs = sorted((f for f in transcripts() if tag in open(f, errors="replace").read()), key=os.path.getmtime, reverse=True)[:1]
    if len(fs) != 1:
        sys.exit(f"{len(fs)} transcripts match {sid}: " + " ".join(os.path.basename(f)[:13] for f in fs))
    cur, agg, seen = "other", {}, set()
    for _, o in lines(fs[0]):
        ts = o.get("timestamp") or ""
        if out_of(ts) or o.get("isSidechain"):
            continue
        t, m = o.get("type"), o.get("message") or {}
        c = m.get("content")
        if t == "system" and o.get("subtype") == "scheduled_task_fire":
            cur = "cron"; agg.setdefault(cur, [0, 0, 0.0])[0] += 1
        if t == "user" and not o.get("toolUseResult"):
            txt = c if isinstance(c, str) else " ".join(b.get("text", "") for b in c or [] if b.get("type") == "text")
            k = None
            if "<task-notification>" in txt: k = "bgtask"
            elif "cross-session-message" in txt: k = "xmsg"
            elif txt and not txt.startswith("<") and not o.get("isMeta"): k = "human"
            if k:
                cur = k; agg.setdefault(cur, [0, 0, 0.0])[0] += 1
        if t == "assistant" and o.get("requestId") not in seen:
            seen.add(o.get("requestId"))
            u = m.get("usage") or {}
            a = agg.setdefault(cur, [0, 0, 0.0])
            a[1] += 1
            a[2] += usd(u.get("input_tokens", 0), u.get("output_tokens", 0), u.get("cache_read_input_tokens", 0), u.get("cache_creation_input_tokens", 0))
    for k, (w, n, d) in sorted(agg.items(), key=lambda x: -x[1][2]):
        print(f"{sid}\t{k}\twakes={w}\trequests={n}\tusd={d:.2f}\tper_wake={d / max(w, 1):.2f}")


def inline(t):
    t = html.escape(t, quote=False)
    t = re.sub(r"`([^`]+)`", r"<code>\1</code>", t)
    t = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", t)
    t = re.sub(r"(?<![*\w])\*([^*\s][^*]*)\*(?!\w)", r"<em>\1</em>", t)
    return re.sub(r"\[([^\]]+)\]\((https?://[^)]+)\)", r'<a href="\2">\1</a>', t)


CSS = """
:root{--bg:#fbfbf9;--fg:#1d1d1b;--mut:#5f5f5a;--acc:#2f5d8a;--line:#deded8;--code:#efefea;--q:#f3f1ea}
@media (prefers-color-scheme:dark){:root{--bg:#18191b;--fg:#e6e6e2;--mut:#a0a09a;--acc:#8ab4e0;--line:#34363a;--code:#26282c;--q:#222428}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
main{max-width:980px;margin:0 auto;padding:32px 16px 80px}
h1{font-size:26px;margin:0 0 12px}h2{font-size:20px;margin:40px 0 8px;padding-top:12px;border-top:1px solid var(--line)}
h3{font-size:16.5px;margin:28px 0 6px;color:var(--acc)}
code{background:var(--code);padding:1px 5px;border-radius:4px;font:13px ui-monospace,SFMono-Regular,Menlo,monospace;word-break:break-word}
ul,ol{padding-left:22px;margin:6px 0}li{margin:4px 0}
pre{background:var(--code);padding:10px 12px;border-radius:6px;overflow-x:auto}pre code{padding:0;background:none;word-break:normal}
blockquote{margin:8px 0;padding:8px 12px;background:var(--q);border-left:3px solid var(--acc);border-radius:4px}
table{border-collapse:collapse;width:100%;margin:10px 0;font-size:14px;display:block;overflow-x:auto}
th,td{border:1px solid var(--line);padding:6px 8px;text-align:left;vertical-align:top}th{background:var(--code)}
a{color:var(--acc)}p{margin:8px 0}
"""


def md2html(src, dst):
    """ponytail: covers only the Markdown subset the reports use (headings, lists, quotes, tables, inline);
    swap for a real converter if they grow."""
    lines_ = open(src).read().split("\n")
    out, i, title = [], 0, "Report"
    while i < len(lines_):
        l = lines_[i]
        if not l.strip():
            i += 1; continue
        m = re.match(r"(#{1,4}) (.*)", l)
        if m:
            n = len(m.group(1))
            if n == 1: title = m.group(2)
            out.append(f"<h{n}>{inline(m.group(2))}</h{n}>"); i += 1; continue
        if l.startswith("|"):
            rows = []
            while i < len(lines_) and lines_[i].startswith("|"):
                rows.append([c.strip() for c in lines_[i].strip().strip("|").split("|")]); i += 1
            h, body = rows[0], [r for r in rows[1:] if not re.match(r"^[-: ]+$", "".join(r))]
            out.append("<table><thead><tr>" + "".join(f"<th>{inline(c)}</th>" for c in h) + "</tr></thead><tbody>"
                       + "".join("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>" for r in body) + "</tbody></table>")
            continue
        if l.lstrip().startswith("```"):
            code, i = [], i + 1
            while i < len(lines_) and not lines_[i].lstrip().startswith("```"):
                code.append(lines_[i]); i += 1
            out.append("<pre><code>" + html.escape("\n".join(code), quote=False) + "</code></pre>"); i += 1; continue
        if re.match(r"\d+\. ", l):
            # numbered list, one level; indented continuation lines join the previous item
            items = []
            while i < len(lines_) and lines_[i].strip() and (re.match(r"\d+\. ", lines_[i]) or lines_[i].startswith(" ")):
                mm = re.match(r"\d+\. (.*)", lines_[i])
                if mm: items.append(mm.group(1))
                else: items[-1] += " " + lines_[i].strip()
                i += 1
            out.append("<ol>" + "".join(f"<li>{inline(t)}</li>" for t in items) + "</ol>"); continue
        if re.match(r"\s*- ", l):
            # nested list by indent; continuation lines (indented, not a bullet) join the previous item
            items = []
            while i < len(lines_) and lines_[i].strip() and (re.match(r"\s*- ", lines_[i]) or lines_[i].startswith(" ")):
                s = lines_[i]
                mm = re.match(r"(\s*)- (.*)", s)
                if mm:
                    items.append([len(mm.group(1)), mm.group(2)])
                elif s.strip().startswith(">"):
                    items[-1].append(("quote", s.strip()[1:].strip()))
                else:
                    items[-1][1] += " " + s.strip()
                i += 1
            buf, stack = [], []
            for it in items:
                ind = it[0]
                while stack and ind < stack[-1]:
                    buf.append("</li></ul>"); stack.pop()
                if not stack or ind > stack[-1]:
                    buf.append("<ul>"); stack.append(ind)
                else:
                    buf.append("</li>")
                buf.append("<li>" + inline(it[1]))
                for q in it[2:]:
                    buf.append(f"<blockquote>{inline(q[1])}</blockquote>")
            while stack:
                buf.append("</li></ul>"); stack.pop()
            out.append("".join(buf).replace("<ul></li>", "<ul>"))
            continue
        if l.startswith(">"):
            q = []
            while i < len(lines_) and lines_[i].startswith(">"):
                q.append(lines_[i][1:].strip()); i += 1
            out.append("<blockquote>" + inline(" ".join(q)) + "</blockquote>"); continue
        # the first line is always the paragraph's, so a line no rule above takes (`#3879 …`) can't stall the loop
        p, i = [l.strip()], i + 1
        while i < len(lines_) and lines_[i].strip() and not re.match(r"(#{1,4} |\||\s*- |>|\s*```|\d+\. )", lines_[i]):
            p.append(lines_[i].strip()); i += 1
        out.append("<p>" + inline(" ".join(p)) + "</p>")
    open(dst, "w").write(f"<!doctype html><html lang=en><head><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'>"
                         f"<title>{html.escape(title)}</title><style>{CSS}</style></head><body><main>{''.join(out)}</main></body></html>")


PLUGIN = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
STATE = os.path.join(os.environ.get("XDG_STATE_HOME") or f"{HOME}/.local/state", "session-orchestration")


def inventory():
    """What the plugin has, from its own files: {(kind, name)}. kind: press, tool, skill, doc, flag, config."""
    reg = open(f"{PLUGIN}/hooks/register.tsx", errors="replace").read()
    keys = re.search(r"BUILTIN_KEYS: Record<string, string> = \{([\s\S]*?)\n\}", reg)
    extra = re.search(r"USAGE_EXTRA = \[([^\]]*)\]", reg)
    labels = re.findall(r"'([^']+)'", (keys.group(1) if keys else "") + (extra.group(1) if extra else ""))
    labels += re.findall(r"label: '([^']+)'", reg[:reg.find("BUILTIN_KEYS")])  # FIXES, spread into BUILTIN_KEYS
    slug = lambda s: re.sub(r"^-|-$", "", re.sub(r"[^a-z0-9]+", "-", s.lower()))
    inv = {("press", slug(s)) for s in labels}
    inv |= {("tool", t) for t in re.findall(r"tool\.register\(\{\s*name: '([a-z_]+)'", reg)}
    inv |= {("skill", d) for d in os.listdir(f"{PLUGIN}/skills") if os.path.isfile(f"{PLUGIN}/skills/{d}/SKILL.md")}
    inv |= {("doc", os.path.basename(f)) for f in glob.glob(f"{PLUGIN}/**/*.md", recursive=True)
            if os.path.basename(f) not in ("SKILL.md", "README.md")}
    ss = open(f"{PLUGIN}/skills/orchestrating-sessions/session-status", errors="replace").read()
    inv |= {("flag", fl) for fl in re.findall(r"^#\s+session-status (--[a-z-]+)", ss, re.M)}
    lib = open(f"{PLUGIN}/lib.sh", errors="replace").read()
    keys = re.search(r"^\s+(tracker\|host\|[a-z_.|]+)\) ;;", lib, re.M)
    inv |= {("config", k) for k in (keys.group(1).split("|") if keys else [])}
    return inv


def usage(days=30):
    """Each feature with its uses in the window and first-seen date; `unused` when 0 uses and it existed all window.
    Uses: the pane's usage log (telemetry=local), transcript tool calls, skill loads, doc reads, session-status flags.
    First-seen: the earliest inventory snapshot listing it (one saved per run in the state folder). Also trims the
    log to 180 days."""
    window(days)
    inv = inventory()
    snaps = os.path.join(STATE, "inventory")
    os.makedirs(snaps, exist_ok=True)
    today = time.strftime("%Y-%m-%d", time.gmtime())  # the real date even with --until: it's what exists now
    with open(os.path.join(snaps, f"{today}.json"), "w") as fh:
        json.dump(sorted(map(list, inv)), fh)
    first = {}
    for f in sorted(glob.glob(f"{snaps}/*.json")):
        try:
            for k, n in json.load(open(f)):
                first.setdefault((k, n), os.path.basename(f)[:10])
        except Exception:
            continue
    count = dict.fromkeys(inv, 0)
    log = os.path.join(STATE, "usage.jsonl")
    on = False  # presses are judged only when the log starts by the window's start (telemetry on all window)
    if os.path.exists(log):
        rows = [(l, o) for l, o in lines(log) if isinstance(o, dict) and isinstance(o.get("t"), (int, float))]
        on = any(o["t"] <= CUT for _, o in rows)
        keep = [l for l, o in rows if o["t"] >= time.time() - 180 * 86400]
        if len(keep) < len(rows) or len(rows) < sum(1 for _ in open(log, errors="replace")):
            # ponytail: a press appended between the read and the replace is lost; a lock if that ever matters.
            with open(log + ".tmp", "w") as fh:
                fh.writelines(keep)
            os.replace(log + ".tmp", log)
        for _, o in rows:
            h = (o.get("k"), o.get("what"))
            if CUT <= o["t"] <= END:
                if h in count or h[0] == "path":
                    count[h] = count.get(h, 0) + 1
    flags = [n for k, n in inv if k == "flag"]
    # The pane runs these itself (no transcript shows it): their presses are measured instead, never flagged here.
    reg = open(f"{PLUGIN}/hooks/register.tsx", errors="replace").read()
    pane = {("flag", fl) for fl in flags if f"'{fl}'" in reg}
    docs = re.compile(r"/session-orchestration/\S*?([\w.-]+\.md)\b")  # the plugin's docs only, not a project's namesakes
    for f in transcripts():
        for _, o in lines(f):
            if out_of(o.get("timestamp", "")):
                continue
            c = (o.get("message") or {}).get("content")
            if o.get("type") == "user" and isinstance(c, str):  # a skill started by its slash command
                for s in re.findall(r"<command-name>/?(?:[\w-]+:)?([\w-]+)</command-name>", c):
                    if ("skill", s) in count:
                        count[("skill", s)] += 1
            if o.get("type") != "assistant":
                continue
            for b in c or []:
                if not isinstance(b, dict) or b.get("type") != "tool_use":
                    continue
                name, inp = b.get("name", ""), b.get("input") or {}
                hit = []
                if name.startswith("mcp__session-orchestration__"):
                    hit = [("tool", name.split("__")[-1])]
                elif name == "Skill":
                    hit = [("skill", str(inp.get("skill", "")).split(":")[-1])]
                elif name == "Read":
                    hit = [("doc", d) for d in docs.findall(str(inp.get("file_path", "")))]
                elif name == "Bash":
                    cmd = str(inp.get("command", ""))
                    hit = [("doc", d) for d in docs.findall(cmd)]  # cat/sed of a doc
                    if "session-status" in cmd:
                        hit += [("flag", fl) for fl in flags if re.search(rf"session-status\b[^|;&]*\s{fl}\b", cmd)]
                for h in hit:
                    if h in count:
                        count[h] += 1
    print("kind\tfeature\tuses\tfirst_seen\tflag")
    start = time.strftime("%Y-%m-%d", time.gmtime(CUT))
    # ponytail: config keys have no use count (they're set in files, not called): listed, never flagged; count the
    # roots that set each one if a key's removal comes up. Presses count only with the log; path lines aren't inventoried.
    for k, n in sorted(count):
        known = k not in ("config", "path") and (k != "press" or on)
        unused = known and (k, n) not in pane and count[(k, n)] == 0 and first.get((k, n), today) <= start
        print(f"{k}\t{n}\t{count[(k, n)] if known or k == 'path' else '-'}\t{first.get((k, n), '-' if k == 'path' else today)}\t{'unused' if unused else ''}")


CMDS = {"sessions": sessions, "events": events, "context": context, "units": units, "waits": waits, "bgtasks": bgtasks, "replies": replies,
        "triggers": triggers, "usage": usage, "chunks": chunks, "trial": trial, "html": md2html}

if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["--until"] and len(a) > 1:
        END = datetime.fromisoformat(a[1].rstrip("Z")).replace(tzinfo=timezone.utc).timestamp(); a = a[2:]
    if not a or a[0] not in CMDS:
        sys.exit(__doc__)
    CMDS[a[0]](*a[1:])

#!/usr/bin/env python3 -I
"""Retro measurement over Claude Code transcripts. Read-only; prints short TSV rows, never transcript bodies.

usage: python3 -I retro.py [--until YYYY-MM-DDTHH:MM[:SS]] CMD [args] [--project ROOT|RX]
  --project (any command): read only the transcripts of one project: ROOT, a path (/, ~ or . first), keeps the
                                  sessions whose working directory is ROOT or under it (its worktrees too); else RX, a
                                  regex on the transcript's project folder name
  sessions [days=7]               one row per session: turns, peak context, compactions, tokens, USD, human msgs,
                                  denials, `!` handoffs, AskUserQuestion, tool errors, cross-session in/out, first prompt
  events [days=7]                 one row per event: deny (detail2: source/reasonType: the hook's or classifier's
                                  message, 160 chars), bang (a session suggests `! cmd`), ran (the user ran a
                                  `!` command), ask, err, bash (+ permission reasonType), self (admitted mistake),
                                  human, xmsg; snippets capped at 220 chars. Last column `test`: -p or dontAsk for
                                  a headless test session (leave those out of refusal counts), else empty. stderr:
                                  `noverdict` (denials whose classifier gave no verdict, by cause: a hook changed the
                                  call's input, another call in the response was changed, the response ended first)
  context [days=7] [split_iso] [project_rx]  context per request (avg, median, >200K and excess, base median) for
                                  all, since split, and matching projects; `over` rows per session; `fork` rows
  units [days=7] [--merge|--done|--post RX] [--merged FILE] [--keys FILE]  merged PRs, finished
                                  tickets, review posts (not --parent-id replies) whose command ran, one row each; USD per unit on stderr.
                                  --merged: the adapter's `yesterday EPOCH KEY…` output, whose merges of the sessions'
                                  keys count too (a reviewer pressed merge); merge_ran on stderr is the ones a session
                                  ran. --keys: also write the sessions' task keys to FILE, one line, for `yesterday`
  waits [days=7] [min=5]          tool calls whose result came back >= min minutes later (prompts, hangs); `sleep`
                                  marks one ending in the same minute in 3+ sessions (the machine woke); totals on stderr
  bgtasks REGEX [days=7]              background Bash launches vs. their completion notices (SILENT = died with
                                  its session); totals on stderr
  replies [days=7]                task sessions idle > 6 h that never wrote replies/<KEY>* (by hand, or the reply
                                  tool's report with that key: lost reports); the key without the project's prefix,
                                  its project's sessions' writes during its life and a successor's (Supersedes:) count; totals
                                  on stderr
  waste DIR [days=7]              the waste counts of a retro folder's sessions/events/waits/usage.tsv (each
                                  optional) and the denial log: spend totals, denials by class and their retries,
                                  hook blocks (on landing commands too), `!` handoffs, waits by class, usage faults
  merges DIR PRS_JSON [days=7] [OWNER/REPO] [RUNS_JSON]
                                  DIR/units.tsv's merge rows against the host's PR list (number, createdAt, mergedAt):
                                  distinct, duplicate, not merged, merge command -> merged, open -> merged, session
                                  start -> merge command, the host's merged/opened in the window, $ per PR; then a
                                  `quality` row per merged PR: #N, the merging session's kind (host, unknown), CI runs
                                  failed or re-run between open and merge, first-try green 1/0, CHANGES_REQUESTED
                                  reviews, follow-up PRs (same branch later, or fixes/reverts/follow-up next to #N); `-`
                                  when none or unmeasured. PRS_JSON adds headRefName, isCrossRepository, reviews, title,
                                  body; RUNS_JSON: headBranch, conclusion, attempt, createdAt. A `quality KIND n=…` line
                                  per kind ends with the merging sessions' median $ per PR they merged
  spend [days=7] DIR              where the window's spend went, as Markdown: by account, project, session, kind,
                                  model, trigger and context size; rebuilds of big contexts, wakes, test runs, gh
                                  calls, handovers. Writes DIR/spend-{req,sess,wakes,ev}.tsv first
  triggers SESSION_PREFIX [days=7]     a session's wakes, requests and USD by trigger: human/xmsg/bgtask/cron/other
  usage [days=30]                 one row per plugin feature (pane button, tool, skill, doc, session-status flag,
                                  config key): uses in the window, first seen, `unused` when 0 uses all window;
                                  presses from the local usage log (telemetry=local or full), which it trims to 180
                                  days; with telemetry=full (the default) also one row per fault the log holds
                                  (block, refuse, relay, wake, error: what [at] [n], counted, first_seen `-`)
  chunks [days=7] [--session PREFIX]  one row per chunk (first prompt `Chunk: KEY/N`, successors joined through
                                  Supersedes: and summed) or per matching session: kind/model/effort, est, act growth
                                  (K), peak, cache read, out, USD, turns, compactions, handoff (none|before|after a
                                  compaction), minutes; then a `ratio` line per kind (median act/est, last 20) and
                                  an `escalations` line (chunk handovers with --escalate in the window, when any)
  kinds [days=7]                  per kind/model/effort of the usage log's start lines (session-status --kind KIND NAME),
                                  joined to sessions by hashed name and their successors: starts, joined, USD (sum,
                                  median), share reaching `reply … done`, handovers, nudges, median minutes to done,
                                  escalations, median advisor calls per start and their USD (subagents' too); a
                                  sized start (--kind build:L) groups as build:L, one with an advisor
                                  (plan.advisor.KIND) as build+fable. No usage log, or one starting after the
                                  window's end: `unmeasured: WHY` on stderr, exit 2 (chunks says it too, and goes on)
  trial [days=28]                 the planner trial's arms side by side (tasks with a chunk session vs the rest):
                                  units, median USD and tokens per unit, peak, compactions, handoffs, /code-review
                                  findings and runs per unit, step-ins per unit
  handoff [days=28]               one row per coordinator handoff entry (config pending.file, else the state folder's
                                  pending.md; open and archived; an entry with no history: from its line, rewordings -):
                                  wait, blocker bucket, rewordings, rounds, reason, detail/history bytes, reads of
                                  its files in the window (tokens, sessions); stderr: totals, wait per bucket, and
                                  entries whose history a session read against the rest
  start [days=7]                  one row per coordinator started in the window: its entrypoint, Start's requests, context
                                  at the first request (base) and after Start, Start's increment, and its tokens by
                                  part (skill, coord_docs, feature_docs, project_docs, schemas, status, rest); then the
                                  medians, per entrypoint too
  loads [days=7]                  one row per session kind (sessions started in the window): messages (mid-turn too),
                                  skill loads and re-injects, worker.md reads, reply cards, SendMessage and reply
                                  schema loads and calls, median tokens of a skill load, a card and a reply schema
  search TEXT [days=7]            one line per hit of TEXT in prompts, cross-session messages and sessions' own text:
                                  NAME (ID8) · date · who: snippet, masked (emails, credentials, long opaque strings)
                                  and capped at 220 chars; 3 a session, 30 in all (session-status --search)
  sections SCOPE [NAME…]          the report sections a SCOPE run (project or plugin) writes, one per line, in order:
                                  NAMEs (config retro.sections) keep only those; one the scope lacks is named on stderr
  sections --groups SCOPE [NAME…] the same sections as a group plan, one `GROUP: SECTION…` line per group with any
                                  (config retro.groups, else GROUPS), then `writer: SECTION…` for those no group lists
  writer DIR [--file [K…]]        a split run's writer, from DIR's run.json and sections/: each group's state, then
                                  `## Section` + `no data: WHY` for every section of a failed group or a missing one
                                  (no status or no sections/G.md: names its session id), then the feedback drafts
                                  (`feedback add …` lines in sections/*.md), numbered, exact repeats dropped. --file
                                  files drafts K… (all with none) by ../orchestrating-sessions/feedback: one whose open
                                  case exists gets `feedback seen` on it instead; prints `filed|seen K PATH`
  html IN.md OUT.html             Markdown report -> self-contained HTML

Transcripts: <account>/projects/*/*.jsonl for every account dir ($CLAUDE_CONFIG_DIR, ~/.claude, ~/.claude-*),
each distinct projects/ tree once (accounts that share one through a symlink are read once).
The window is the `days` before --until (UTC, default now): rerun an old window with --until.
Cost prices each request at its model's list rates (USD/Mtok in, out, cache read, 1-hour cache write: opus 5,25,0.5,10,
sonnet 3,15,0.3,6, haiku 1,5,0.1,2, fable 8,40,0.8,16, older opus 4/4.1 and haiku 3/3.5 at theirs; any other model as
opus; 5-minute cache writes at 1.25x input); env RATES="in,out,cr,cw" prices every model alike. A request's advisor calls
(usage.iterations of type advisor_message, left out of its totals) are added at the advisor model's rates.
"""
import bisect, calendar, collections, csv, glob, hashlib, html, json, os, re, statistics, sys, time
from datetime import datetime, timezone

# Model id pattern -> list rates, first match wins: older generations before their family.
# shortcut: unknown models are priced as opus; add a row when their list rate is known.
RATES = [(r"opus-4-(?:1-)?2025|3-opus", (15, 75, 1.5, 30)), (r"3-5-haiku", (0.8, 4, 0.08, 1.6)),
         (r"3-haiku", (0.25, 1.25, 0.03, 0.5)), (r"opus", (5, 25, 0.5, 10)), (r"sonnet", (3, 15, 0.3, 6)),
         (r"haiku", (1, 5, 0.1, 2)), (r"fable", (8, 40, 0.8, 16))]
RATES_ALL = tuple(map(float, os.environ["RATES"].split(","))) if os.environ.get("RATES") else None
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


PROJECT = None  # --project's test on a transcript path; None reads every project


def project_filter(arg):
    """--project's value as a test on a transcript. A path: the session's first `cwd` is the root or under it (as typed
    or resolved: a symlinked root), its folder named after one of those (Claude Code makes every non-alphanumeric
    character a dash); a transcript with no cwd keeps its folder named exactly so, or a dot folder's (`--`) under it.
    Anything else: a regex on the folder name."""
    if arg[:1] not in "/~.":
        rx = re.compile(arg)
        return lambda f: bool(rx.search(os.path.basename(os.path.dirname(f))))
    rs = {os.path.abspath(os.path.expanduser(arg)), os.path.realpath(os.path.expanduser(arg))}
    enc = tuple(re.sub(r"[^A-Za-z0-9]", "-", r) for r in rs)

    def keep(f):
        d = os.path.basename(os.path.dirname(f))
        if not d.startswith(enc):
            return False
        cwd = next((o["cwd"] for _, o in lines(f) if isinstance(o.get("cwd"), str)), None)
        if cwd is None:
            return any(d == e or d.startswith(e + "--") for e in enc)
        return any(cwd == r or cwd.startswith(r.rstrip("/") + "/") for r in rs)
    return keep


def transcripts(every=False):
    for r in roots():
        for f in glob.glob(f"{r}/*/*.jsonl"):
            if os.path.getmtime(f) >= CUT and (every or not PROJECT or PROJECT(f)):
                yield f


def lines(f):
    for line in open(f, errors="replace"):
        try:
            yield line, json.loads(line)
        except Exception:
            continue


def usd(i, o, cr, cw, model=""):
    r_in, r_out, r_cr, r_cw = RATES_ALL or next((r for rx, r in RATES if re.search(rx, str(model or ""))), dict(RATES)["opus"])
    return (i * r_in + o * r_out + cr * r_cr + cw * r_cw) / 1e6


def req_tokens(u):
    """A request's usage as usd's (in, out, cache read, cache write). Cache write is priced at the 1-hour rate (2x input),
    so 5-minute writes (1.25x input), when the usage splits them out, count as 0.625 of a token each."""
    split = u.get("cache_creation") or {}
    w5 = split.get("ephemeral_5m_input_tokens", 0)
    cw = u.get("cache_creation_input_tokens", w5 + split.get("ephemeral_1h_input_tokens", 0))
    return (u.get("input_tokens", 0), u.get("output_tokens", 0), u.get("cache_read_input_tokens", 0),
            cw - min(w5, cw) * 0.375)   # the 5-minute split is part of the total: a zero total writes nothing


def advisor(u):
    """A request's advisor calls as (calls, USD): its usage.iterations of type advisor_message, each a read of the
    transcript at the advisor model's rates, which the request's own token totals leave out."""
    its = [x for x in u.get("iterations") or [] if isinstance(x, dict) and x.get("type") == "advisor_message"]
    return len(its), sum(usd(*req_tokens(x), x.get("model")) for x in its)


def ctx_of(u):
    """A request's context: input + cache read + cache write of its last message iteration when it has iterations (the
    totals add up each one an advisor call splits the turn into), else of the whole usage."""
    its = [x for x in u.get("iterations") or [] if isinstance(x, dict) and x.get("type") == "message"]
    x = its[-1] if its else u
    return x.get("input_tokens", 0) + x.get("cache_read_input_tokens", 0) + x.get("cache_creation_input_tokens", 0)


def req_usd(u, model):
    """A request's cost: its own tokens at MODEL's rates plus its advisor calls."""
    return usd(*req_tokens(u), model) + advisor(u)[1]


def clip(s, n=220):
    return re.sub(r"\s+", " ", str(s))[:n]


def sessions(days=7):
    window(days)
    home_enc = re.sub(r"[^A-Za-z0-9]", "-", HOME) + "-"
    print("project\tsession\tname\tstart\tend\tturns\tpeak_ctx\tcompacts\tout_tok\tcache_write\tcache_read\tusd\thuman_msgs\tdenials\tbang_cmds\tasks\ttool_errs\txmsg_in\tsendmsg\tfirst_prompt")
    for f in transcripts():
        seen, peak, comp, out, cw, cr, inp, cost = set(), 0, 0, 0, 0, 0, 0, 0.0
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
                    ctx = ctx_of(u)
                    peak = max(peak, ctx)
                    cost += req_usd(u, m.get("model"))
                    out += u.get("output_tokens", 0); cw += u.get("cache_creation_input_tokens", 0)
                    cr += u.get("cache_read_input_tokens", 0); inp += u.get("input_tokens", 0)
                for b in c if isinstance(c, list) else []:
                    if b.get("type") == "text" and re.search(r"`! [a-z~/]", b.get("text", "")):
                        bang += 1
                    if b.get("type") == "tool_use":
                        if b.get("name") == "AskUserQuestion": asks += 1
                        if b.get("name") in ("SendMessage", "mcp__session-orchestration__reply"): sm += 1
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
                                  round(cost, 2), human, den, bang, asks, errs, xin, sm, first.replace("\t", " ")])))


SELF = re.compile(r"\b(I was wrong|my mistake|I retract|retracting|I misread|that was wrong|I got that wrong|correction:|I stand corrected|wrongly (said|claimed)|I (incorrectly|wrongly))\b", re.I)


# A no-verdict denial's cause, from the classifier's text: the first that matches; else `other`.
NOVERDICT = [("hook_changed", "a hook changed this call's input"), ("sibling_changed", "another call in this response was changed"),
             ("ended", "response ended before its verdict")]


def events(days=7):
    window(days)
    nv = dict.fromkeys([k for k, _ in NOVERDICT] + ["other"], 0)
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
                    rc = b.get("content")
                    rc = rc if isinstance(rc, str) else " ".join(x.get("text", "") for x in rc or [] if isinstance(x, dict))
                    if pd.get("decision") == "reject":
                        # The hook's or classifier's own words, so a split hint can be told from a refusal.
                        msg = " ".join(rc.split())[:160]
                        row("deny", f"{name}: {arg}", f"{pd.get('source')}/{pd.get('reasonType')}: {msg}")
                        if "gave no verdict" in rc and not test:
                            full = " ".join(rc.split())
                            nv[next((k for k, t in NOVERDICT if t in full), "other")] += 1
                    elif b.get("is_error"):
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
    print("noverdict " + " ".join(f"{k}={v}" for k, v in nv.items()), file=sys.stderr)


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
    """Main-loop requests inside the window (all of them if WHOLE), each once: (ts, context tokens, USD)."""
    seen = set()
    for _, o in lines(f):
        ts = o.get("timestamp") or ""
        rid = o.get("requestId")
        if (out_of(ts) and not whole) or o.get("type") != "assistant" or o.get("isSidechain") or not rid or rid in seen:
            continue
        seen.add(rid)
        m = o.get("message") or {}
        u = m.get("usage") or {}
        yield ts, ctx_of(u), \
            req_usd(u, m.get("model"))


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


# The CLI (`…-cli[@version]`, `gh` or `glab`) where a command starts (after npx, env, rtk proxy or VAR=x), so a
# grep, a message or a heredoc body that only mentions one doesn't count (unit_hits drops bodies no shell runs).
# The PR number may follow a `-R OWNER/REPO`. Posts: Bitbucket's and Forgejo's `pr comment create`, gh's `pr comment`
# or `pr review`, glab's `mr note`.
CLI = (r"(?:^|[;&|(\n])\s*(?:[A-Za-z_]\w*=\S*\s+|(?:env|command|sudo|rtk proxy|npx(?:\s+-y)?)\s+)*"
       r"(?:\S*-cli(?:@\S+)?|(?:\S*/)?gh|(?:\S*/)?glab)\s+")
REPO = r"(?:(?:-R|--repo)[ =]\S+\s+)?"
UNITS = {"merge": CLI + r"(?:pr|mr) merge\s+" + REPO + r"(\d+)",
         "done": CLI + r"issue transition (\S+) --to \"?Ready for Test",
         "post": CLI + r"(?:pr comment create|pr comment|pr review|mr note)\s+" + REPO + r"(\d+)"}


def units(days=7, *opts):
    """Units of work whose command ran (its result is neither an error nor a denial): `merge`, `done` (a ticket
    finished) and `post` (a review comment posted from a review session: name or first prompt says review; a --parent-id reply left out), one
    row per unit id, first time. --merge/--done/--post RX override the regexes (one capture group: the id);
    --project (a global option) keeps one project's transcripts. The totals line on stderr gives USD per merge and per
    finished ticket over those sessions, and per post over the review sessions among them."""
    window(days)
    o_ = dict(zip(opts[::2], opts[1::2]))
    rx = {k: re.compile(o_.get(f"--{k}", v)) for k, v in UNITS.items()}
    found, total, review, keys = {}, 0.0, 0.0, set()
    print("kind\tid\tsession\tts\tcommand")
    for f in transcripts():
        sid = os.path.basename(f)[:8]
        cost = sum(c for _, _, c in requests(f))
        total += cost
        hits, is_review, first = unit_hits(f, rx)
        if k := task().search(first):
            keys.add(k.group(1))
        for key, ts, cmd in hits:
            if key not in found:
                found[key] = sid
                print("\t".join([key[0], key[1], sid, ts[:16], clip(cmd, 120)]))
        if is_review:
            review += cost
    ran = sum(1 for key in found if key[0] == "merge")
    if o_.get("--keys"):
        with open(o_["--keys"], "w", encoding="utf-8") as fh:
            fh.write(" ".join(sorted(keys)) + "\n")
    if o_.get("--merged"):
        # Same PR: same number, and the same repo when both name one (a merge run as `merge 22` names none).
        def same(a, b):
            (ra, _, na), (rb, _, nb) = a.rpartition("#"), b.rpartition("#")
            ra, rb = ra.split("/")[-1], rb.split("/")[-1]
            return na == nb and (not ra or not rb or ra == rb)
        ours = [key[1] for key in found if key[0] == "merge"]
        for key, ts, ref in host_merges(o_["--merged"], keys):
            if not any(same(ref, o) for o in ours):
                ours.append(ref)
                found[("merge", ref)] = "host"
                print("\t".join(["merge", ref, "host", ts, f"{key}: merged on the code host"]))
    n = {k: sum(1 for key in found if key[0] == k) for k in UNITS}
    per = lambda k, v: f"{k}={v} per_{k}={(review if k == 'post' else total) / v:.1f}" if v else f"{k}=0"
    print(f"usd={total:.0f} review_usd={review:.1f} " + " ".join(per(k, v) for k, v in n.items()) + f" merge_ran={ran}",
          file=sys.stderr)


def host_merges(path, keys):
    """PRs merged in the window, whoever pressed merge, from an adapter's `yesterday EPOCH KEY…` output (rows
    `KEY<TAB>…`, events `  EPOCH<TAB>REPO#N merged[ by NAME]`): [(key, ts, REPO#N)] for the keys sessions worked on."""
    out, key = [], None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if not line.strip():
                continue
            if not line[0].isspace():
                key = line.split("\t")[0].strip()
                continue
            ep, _, text = line.strip().partition("\t")
            m = re.match(r"(\S+#\d+) merged\b", text)
            if m and key in keys and ep.isdigit() and CUT <= int(ep) <= END:
                out.append((key, time.strftime("%Y-%m-%dT%H:%M", time.gmtime(int(ep))), m.group(1)))
    return out


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
            cmd = heredoc_text_dropped(cmd)
            repo = re.search(r"(?:--repo|-R)[ =](\S+)", cmd)
            for k, r in rx.items():
                if k == "post" and not re.search("review", name + first, re.I):
                    continue
                for mt in r.finditer(cmd):
                    # a --parent-id reply answers a thread (often a reviewer on one's own PR): not a review posted
                    if k == "post" and re.match(r"[^;&|\n]*\s--parent-id\b", cmd[mt.end():]):
                        continue
                    uid = mt.group(1)
                    uid = f"{repo.group(1)}#{uid}" if repo and k != "done" else uid  # PR numbers repeat across repos
                    hits.append(((k, uid, sid) if k == "post" else (k, uid), ts, cmd))  # a later review round is another post
    return hits, bool(re.search("review", name + first, re.I)), first


# The approved-action hook's heredoc rule (hooks/approved-action.sh, lex, safe with CAT), so units counts what the
# hook gates: heredoc bodies are dropped only when nothing but cat runs in the command without them.
PRE = set("env command time nohup rtk proxy then do else ! { } if elif while until done fi esac".split())


def lex(s, q=""):
    """S with quoting resolved, as the hook's lex: (text, quote still open). A # at a word start is a command `#`."""
    o, j = [], 0
    while j < len(s):
        c = s[j]
        if c == "\\" and q in ("", '"'):
            o.append("_"); j += 2; continue
        if not q and c == "#" and (j == 0 or s[j - 1] in " \t\n;|&()"):
            o.append(";#"); j += 1; continue
        if not q:
            if c in "\"'":
                q = c
            else:
                o.append(c)
        elif c == q:
            q = ""
        elif q == '"' and (c == "`" or s[j:j + 2] == "$("):
            o.append(c)
        else:
            o.append("_" if c in ";|&()<>`$\n" else c)
        j += 1
    return "".join(o), q


def only_cat(u):
    """Every command in lexed text U is cat, and nothing sets a variable (the hook's safe(U, 1))."""
    for seg in re.split(r"[;|&()`\n]|\$\(", u):
        t = ""
        for x in seg.split():
            if x in PRE:
                continue
            if re.match(r"[A-Za-z_]\w*=", x):
                return False
            t = x; break
        if t and t != "cat":
            return False
    return True


def heredoc_text_dropped(cmd):
    """CMD without its heredoc bodies when only cat runs in the rest (cat > f <<EOF … EOF), else CMD."""
    out, body, rows, i, q, cut = [], [], cmd.split("\n"), 0, "", False
    while i < len(rows):
        line = rows[i]
        u, q = lex(line, q)
        out.append(line); body.append(False)
        i += 1
        m = re.search(r"<<(-?)\s*([A-Za-z_]\w*)", u)
        if q or re.search(r"\(\(|<<<", u) or line.endswith("\\") or not m or u.count("<<") > 1:
            continue
        end = next((k for k in range(i, len(rows)) if (rows[k].lstrip("\t") if m.group(1) else rows[k]) == m.group(2)), None)
        if end is None:
            continue
        out.extend(rows[i:end + 1]); body.extend([True] * (end + 1 - i)); i = end + 1; cut = True
    kept = [x for x, b in zip(out, body) if not b]
    return "\n".join(kept if cut and only_cat(lex("\n".join(kept))[0]) else out)


SUP = re.compile(r"(?:Supersedes: |[Yy]ou replace (?:session )?)([0-9a-f]{8})")


def stat(f):
    """One session's numbers inside the window, for chunks and trial. growth: the sum of context increases between
    requests (each message id once), not counting a session's first request or the one after a compaction. adv, adv_usd:
    its advisor calls and their cost, its subagents' included (usd has only its own thread's, as for every request)."""
    s = dict(sid=os.path.basename(f)[:8], first="", ts0="", ts1="", growth=0, peak=0, inp=0, out=0, cr=0, cw=0,
             turns=0, comp=0, models={}, findings=0, reviews=0, steps=0, done_t=set(), usd=0.0, names=set(), nudges=0,
             done_at="", adv=0, adv_usd=0.0)
    seen, prev, done_ids, reply_ids = set(), None, set(), set()
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
        if t in ("agent-name", "custom-title"):   # every name it had: a handed-over session is renamed NAME-prev-K
            s["names"].add(o.get("agentName") or o.get("customTitle") or "")
        if t == "system" and o.get("subtype") == "compact_boundary":
            s["comp"] += 1
            prev = None
        if t == "assistant":
            rid = m.get("id") or o.get("requestId")
            if rid and rid not in seen:
                seen.add(rid)
                u = m.get("usage") or {}
                ctx = ctx_of(u)
                s["growth"] += max(0, ctx - prev) if prev is not None else 0
                prev = ctx
                s["peak"] = max(s["peak"], ctx)
                s["inp"] += u.get("input_tokens", 0); s["out"] += u.get("output_tokens", 0)
                s["cr"] += u.get("cache_read_input_tokens", 0); s["cw"] += u.get("cache_creation_input_tokens", 0)
                s["turns"] += 1
                n, c = advisor(u); s["adv"] += n; s["adv_usd"] += c
                s["usd"] += usd(*req_tokens(u), m.get("model")) + c   # req_usd, its advisor scanned once
                s["ts1"] = max(s["ts1"], ts)
                mod = re.search(r"opus|sonnet|haiku|fable", str(m.get("model")))
                if mod:
                    s["models"][mod.group(0)] = s["models"].get(mod.group(0), 0) + 1
            for b in blocks:
                cmd = str((b.get("input") or {}).get("command", "")) if b.get("type") == "tool_use" and b.get("name") == "Bash" else ""
                if "--plan" in cmd and "--done" in cmd:
                    done_ids.add(b.get("id"))
                if b.get("type") == "tool_use" and b.get("name") == "ReportFindings":
                    s["findings"] += len((b.get("input") or {}).get("findings") or [])
                if b.get("type") == "tool_use" and b.get("name") == "Skill" and \
                        str((b.get("input") or {}).get("skill", "")).split(":")[-1] == "code-review":
                    s["reviews"] += 1
                if b.get("type") == "tool_use" and re.search(r"(?:^|__)reply$", str(b.get("name"))) and \
                        (b.get("input") or {}).get("done"):
                    reply_ids.add(b.get("id"))
        if t == "user":
            for b in blocks:   # the chunk line this session's own `--plan --done` printed: its t joins it to the log
                if not isinstance(b, dict) or b.get("type") != "tool_result":
                    continue
                r = b.get("content")
                r = r if isinstance(r, str) else " ".join(x.get("text", "") for x in r or [] if isinstance(x, dict))
                if b.get("tool_use_id") in done_ids:
                    s["done_t"].update(int(x) for x in re.findall(r'\{"t":(\d+),"k":"chunk"', r))
                # a `reply … done` the done gate let through (a refused one comes back as an error)
                if b.get("tool_use_id") in reply_ids and not b.get("is_error"):
                    s["done_at"] = s["done_at"] or ts
            s["reviews"] += len(re.findall(r"<command-name>/?(?:[\w-]+:)?code-review</command-name>", txt))
            k = said(o, txt)
            if k == "ran":
                s["steps"] += len(RAN.findall(txt))
            elif k == "human":
                s["steps"] += 1
            elif k == "xmsg":
                s["nudges"] += 1
    if not seen:
        return None
    # /code-review runs in a subagent (the session's subagents/ transcripts): it reports through ReportFindings, or as
    # a ```json list of findings (each with a failure_scenario) in its last message.
    # Each subagent consults the advisor on its own: its calls count too (each message id once).
    for sub in glob.glob(f"{f[:-6]}/subagents/*.jsonl"):
        last, sub_seen = "", set()
        for _, o in lines(sub):
            if o.get("type") == "assistant" and not out_of(o.get("timestamp") or ""):
                m = o.get("message") or {}
                rid = m.get("id") or o.get("requestId")
                if rid and rid not in sub_seen:
                    sub_seen.add(rid)
                    n, c = advisor(m.get("usage") or {}); s["adv"] += n; s["adv_usd"] += c
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
    # retro-run's `retro run, scope S` is task retro-S, as context-watch keys it (its successor's marker says so)
    rs = mark(r"^Session task: retro run, scope ([a-z]+)")
    s.update(task=rs and "retro-" + rs or mark(r"^Session task: ([\w./-]*\w)") or mark(r"^Work on ([A-Za-z][\w]*-\d+)\b"), chunk=mark(r"^Chunk: (\S+)"), sup=mark(SUP.pattern),
             model=max(s["models"], key=s["models"].get, default="?"))
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


def log_lines(k):
    """The usage log's lines of kind K (lib.sh usage), up to the window's end: chunk {t, what, model, effort, est, act},
    start {t, what, model, effort, sess, size, advisor}, escalate {t, what, model, effort, sess}."""
    log = os.path.join(STATE, "usage.jsonl")
    if not os.path.exists(log):
        return []
    return sorted((o for _, o in lines(log) if isinstance(o, dict) and o.get("k") == k
                   and isinstance(o.get("t"), (int, float)) and o["t"] <= END), key=lambda o: o["t"])


def log_gap():
    """Why the usage log can't measure the window, or None: it's missing, empty, or starts after the window's end (an
    old window rerun with --until). A log with lines by then measures, zeros included."""
    log = os.path.join(STATE, "usage.jsonl")
    if not os.path.exists(log):
        return "no usage log (telemetry off, or nothing logged yet)"
    ts = [o["t"] for _, o in lines(log) if isinstance(o, dict) and isinstance(o.get("t"), (int, float))]
    if not ts:
        return "the usage log has no lines"
    if min(ts) > END:
        return f"the usage log starts {time.strftime('%Y-%m-%d', time.gmtime(min(ts)))}, after the window's end"
    if min(ts) > CUT:
        print(f"partial: the usage log starts {time.strftime('%Y-%m-%d', time.gmtime(min(ts)))}, inside the window", file=sys.stderr)
    return None


def kinds(days=7):
    """Per kind, model and effort of the usage log's start lines in the window (session-status --kind KIND NAME): starts,
    joined (a session whose name hashes to the line's sess, started from it to that name's next start, plus its
    Supersedes: successors),
    USD (sum, median per start), the share whose `reply … done` the gate let through, handovers, nudges (cross-session
    messages in), median minutes from start to done, escalations (session-status --handover --escalate). KIND carries the
    start's size (build:L) when it had one and its advisor (build+fable) when it logged one, and advisor calls per start
    (median) and their USD sum, subagents' included. A start without sess (before the name was logged) is unjoined."""
    import hashlib
    window(days)
    if gap := log_gap():   # empty rows would read as no starts: a measured zero
        print(f"unmeasured: {gap}", file=sys.stderr)
        sys.exit(2)
    ss = stats()
    epoch = lambda ts: P(ts).timestamp() if ts else 0
    by_hash = {}
    for s in ss.values():
        for n in s["names"]:
            by_hash.setdefault(hashlib.sha256(n.encode()).hexdigest()[:12], []).append(s)
    succ = {}
    for s in ss.values():
        succ.setdefault(s["sup"], []).append(s)
    groups, starts, escs = {}, log_lines("start"), log_lines("escalate")
    for i, o in enumerate(starts):
        if o["t"] < CUT:
            continue
        # A reused name: this start's sessions began from it (a minute of clock slack) to the name's next start.
        nxt = next((x["t"] for x in starts[i + 1:] if o.get("sess") and x.get("sess") == o["sess"]), float("inf"))
        g = [s for s in by_hash.get(o.get("sess"), []) if o["t"] - 60 <= epoch(s["ts0"]) < nxt - 60]
        seen = {s["sid"] for s in g}
        for s in g:   # its successors (handovers), whatever they're named; g grows as it's walked
            for n in succ.get(s["sid"], []):
                if n["sid"] not in seen:
                    seen.add(n["sid"]); g.append(n)
        # its --handover --escalate lines: sess hashes one of its sessions' names, logged from this start to the next
        hs = {o.get("sess")} | {hashlib.sha256(n.encode()).hexdigest()[:12] for s in g for n in s["names"]}
        e = sum(1 for x in escs if x.get("sess") and x.get("sess") in hs and o["t"] <= x["t"] < nxt)
        kind = o.get("what", "?") + (f":{o['size']}" if o.get("size") in ("S", "L") else "")   # M: as configured
        kind += f"+{o['advisor']}" if o.get("advisor") and isinstance(o["advisor"], str) else ""   # a trial arm: build+fable
        groups.setdefault((kind, o.get("model", "?"), o.get("effort", "?")), []).append((o["t"], g, e))
    print("kind\tmodel\teffort\tstarts\tjoined\tusd\tusd_median\tdone_share\thandovers\tnudges\tminutes_to_done\tescalations"
          "\tadvisor_calls_median\tadvisor_usd")
    for (kind, model, effort), rows in sorted(groups.items()):
        j = [(t, g) for t, g, _ in rows if g]
        cost = [sum(s["usd"] for s in g) for _, g in j]
        done = [min((s["done_at"] for s in g if s["done_at"]), default="") for _, g in j]
        mins = [(epoch(d) - t) / 60 for (t, _), d in zip(j, done) if d]
        print("\t".join(map(str, [kind, model, effort, len(rows), len(j), round(sum(cost), 2),
                                  round(statistics.median(cost), 2) if cost else "-",
                                  f"{len(mins) / len(j):.2f}" if j else "-",
                                  sum(1 for _, g in j for s in g if s.get("handoff")),
                                  sum(s["nudges"] for _, g in j for s in g),
                                  round(statistics.median(mins)) if mins else "-", sum(e for _, _, e in rows),
                                  statistics.median(sum(s["adv"] for s in g) for _, g in j) if j else "-",
                                  round(sum((s["adv_usd"] for _, g in j for s in g), 0.0), 2)])))


def chunks(days=7, *opts):
    """One row per chunk (sessions whose first prompt has `Chunk: KEY/N`, successors joined through Supersedes: and
    summed), or per session matching --session PREFIX. Kind, effort and est come from the usage log's chunk line
    when one matches, else `?`. Then a `ratio` line per kind: the median act/est over its last 20 chunk lines."""
    if str(days).startswith("--"):
        days, opts = 7, (days,) + opts
    window(days)
    if gap := log_gap():   # the rows still measure the transcripts; only kind, effort, est and ratio are missing
        print(f"unmeasured: kind, effort, est and ratio ({gap})", file=sys.stderr)
    o_ = dict(zip(opts[::2], opts[1::2]))
    if "--session" in o_:   # the session and the predecessors its Supersedes: chain reaches (a handed-over chunk)
        groups, files = {}, {os.path.basename(f)[:8]: f for f in transcripts()}
        for f in files.values():
            s = os.path.basename(f).startswith(o_["--session"]) and stat(f)
            if s:
                g = [s]
                while g[0]["sup"] in files and len(g) < 50:
                    p = stat(files[g[0]["sup"]])
                    if not p:
                        break
                    g.insert(0, p)
                groups[s["sid"]] = g
    else:
        groups = {}
        for s in stats().values():
            if s["chunk"]:
                groups.setdefault(s["chunk"], []).append(s)
    logged = log_lines("chunk")
    own = set().union(*(s["done_t"] for g in groups.values() for s in g))
    pool = [o for o in logged if o["t"] not in own]   # the time match below is for sessions without their own --done
    epoch = lambda ts: P(ts).timestamp()
    print("key\tchunk\tkind/model/effort\test\tact_K\tpeak\tcache_read\tout\tusd\tturns\tcompacts\thandoff\tminutes")
    for name, g in sorted(groups.items(), key=lambda kv: min(s["ts0"] for s in kv[1])):
        t0, t1 = min(s["ts0"] for s in g), max(s["ts1"] for s in g)
        act = sum(s["growth"] for s in g) / 1000
        # The line the chunk's own `--plan --done` printed (its t), else, for one that ran none, by time (from the chunk's
        # start to an hour after its last request) and then by the closest act among lines no session printed.
        ts = set().union(*(s["done_t"] for s in g))
        hit = next((o for o in reversed(logged) if o["t"] in ts), None)
        if not hit:
            near = [o for o in pool if epoch(t0) <= o["t"] <= epoch(t1) + 3600]
            hit = min(near, key=lambda o: abs((o.get("act") or 0) - act), default={})
            if hit:
                pool.remove(hit)
        key, _, n = name.rpartition("/")
        print("\t".join(map(str, [key or "-", n, f"{hit.get('what', '?')}/{g[0]['model']}/{hit.get('effort', '?')}",
                                  hit.get("est", "?"), round(act), max(s["peak"] for s in g), sum(s["cr"] for s in g),
                                  sum(s["out"] for s in g), round(sum(s["usd"] for s in g), 2), sum(s["turns"] for s in g),
                                  sum(s["comp"] for s in g), ",".join(s["handoff"] for s in g if s.get("handoff")) or "none",
                                  round((epoch(t1) - epoch(t0)) / 60)])))
    by = {}
    for o in log_lines("chunk"):
        if o.get("est") and isinstance(o.get("act"), (int, float)):
            by.setdefault(o.get("what", "?"), []).append(o["act"] / o["est"])
    for kind, rs in sorted(by.items()):
        print(f"ratio\t{kind}\t{statistics.median(rs[-20:]):.2f}\tn={len(rs[-20:])}")
    # chunk handovers with --escalate in the window (the chunk lines carry no session, so a count, not per chunk)
    e = sum(1 for o in log_lines("escalate") if o["t"] >= CUT and o.get("what") == "chunk")
    if e:
        print(f"escalations\t{e}")


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
    rows = []
    for f in transcripts(every=True):   # a wake shows across projects: --project narrows the rows printed, not this
        sid = os.path.basename(f)[:8]
        keep = not PROJECT or PROJECT(f)
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
                        rows.append((ts[:16], mins, keep, [sid, t0[:16], f"{mins:.0f}", name, f"{pd.get('source')}/{pd.get('reasonType')}", re.sub(r"\s+", " ", arg)[:160]]))
    # A wait ending in the same minute as waits in 2+ other sessions is the machine waking from sleep, not a wait.
    # shortcut: two sessions waking together, three answered in one minute by hand, or a wake whose results straddle a
    # minute boundary are misread; upgrade with the power log (pmset -g log) or a no-line-in-any-session test when that
    # shows up.
    woke = {}
    for end, _, _, r in rows:
        woke.setdefault(end, set()).add(r[0])
    tot = {"waits": 0, "minutes": 0, "sleep": 0, "sleep_minutes": 0}
    print("session\tts\tminutes\ttool\tdecision\tinput\tsleep")
    for end, mins, keep, r in rows:
        if not keep:
            continue
        sl = len(woke[end]) >= 3
        tot["sleep" if sl else "waits"] += 1; tot["sleep_minutes" if sl else "minutes"] += round(mins)
        print("\t".join(r + ["sleep" if sl else ""]))
    print(tot, file=sys.stderr)


def bgtasks(regex=None, days=7):
    if not regex:
        sys.exit("usage: retro.py bgtasks REGEX [days=7]")
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


task_re = lambda k: re.compile(r"(?:Session task:|Work on)\s+(?:https?://\S+/browse/)?" + k)
TASK = task_re(r"([A-Z][A-Z0-9]+-\d+)")   # lib.sh key_re's default; --project ROOT takes the project's (task())
ROOT = None   # --project's value when it is a path: task() reads that project's key_pattern
POSIX = {"[:upper:]": "A-Z", "[:lower:]": "a-z", "[:digit:]": "0-9", "[:alnum:]": "A-Za-z0-9", "[:alpha:]": "A-Za-z",
         "[:space:]": r"\s", "[:xdigit:]": "0-9A-Fa-f"}   # key_re's ERE classes, which Python reads as plain sets


def project_key(root):
    """The task key regex of the project at ROOT as lib.sh key_re gives it (config key_pattern, else the adapter's,
    else the default), or None when ROOT isn't a folder or the pattern isn't one Python reads."""
    import subprocess
    if not os.path.isdir(root):
        return None
    lib = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "lib.sh")
    try:
        k = subprocess.run(["bash", "-c", '. "$1" && cd "$2" && key_re "$(adapter_path .)"', "_", lib, root],
                           capture_output=True, text=True, timeout=30).stdout.strip()
        for c, py in POSIX.items():
            k = k.replace(c, py)
        return task_re(k) if k else None   # key_re wraps it in parentheses: group(1) is the key
    except (OSError, subprocess.SubprocessError, re.error):
        return None


_task = []


def task():
    """TASK, or the project's (project_key) under --project ROOT; worked out once, by the commands that read keys only
    (it runs the project's adapter)."""
    if not _task:
        _task.append(ROOT and project_key(ROOT) or TASK)
    return _task[0]


def replies(days=7):
    """Lost replies: task sessions (first prompt "Work on KEY", or "Session task: KEY") idle > 6 h that never wrote
    replies/<KEY>* (Write/Edit on it, a Bash command that names it after `>`, mv, cp, tee, sed -i or python, or the
    reply tool's report with key KEY). KEY is the task key or the key without the project's prefix (the folder name
    and a dash: proj-fix-x writes replies/fix-x.md), not another task's longer key (x-s2 for x) nor a folder; the write
    may be any session's of the same project folder during this one's life, or come from a successor (Supersedes: its id, transitively), and a session is open while any of that chain is."""
    window(days)
    tot = {"task": 0, "wrote": 0, "lost": 0, "open": 0}
    untasked = 0
    ss, writes = [], []   # pass 1: every project's transcripts, since another session's write excuses one of ours
    for f in transcripts(every=True):
        s = dict(sid=os.path.basename(f)[:8], key=None, first="", last="", name="", sup="", root="",
                 counted=not PROJECT or PROJECT(f))
        rep = {}
        for line, o in lines(f):
            ts = o.get("timestamp") or ""
            if ts and ts[:19] > END_ISO:
                break  # replaying an old window: what came after it doesn't count
            s["first"] = s["first"] or ts
            s["last"] = ts or s["last"]
            s["name"] = o.get("agentName") or s["name"]
            if not s["root"] and isinstance(o.get("cwd"), str):
                s["root"] = os.path.basename(re.sub(r"/\.(?:claude/)?worktrees/.*", "", o["cwd"]))
            m = o.get("message") or {}
            if s["key"] is None and o.get("type") == "user" and not o.get("isSidechain") and not o.get("isMeta"):
                c = m.get("content")
                txt = c if isinstance(c, str) else " ".join(b.get("text", "") for b in c or [] if isinstance(b, dict))
                if txt.startswith("<") and "<cross-session-message" not in txt:
                    continue  # a slash command or caveat line, not the first prompt
                if "<cross-session-message" not in txt and (k := task().search(txt[:400])):
                    s["key"] = k.group(1)
                elif txt.strip():
                    s["key"] = ""  # the first prompt names no task: not a task session
                if txt.strip():
                    s["sup"] = (SUP.search(txt) or [None, ""])[1]
            if rep and o.get("type") == "user" and (o.get("permissionDecision") or {}).get("decision") != "reject":
                for b in m.get("content") if isinstance(m.get("content"), list) else []:
                    if isinstance(b, dict) and b.get("tool_use_id") in rep and not b.get("is_error"):
                        writes.append((ts, "key", rep[b["tool_use_id"]], "", s))
            if o.get("type") == "assistant" and ("replies/" in line or '"report"' in line):
                for b in m.get("content") if isinstance(m.get("content"), list) else []:
                    i = (b.get("input") or {}) if isinstance(b, dict) and b.get("type") == "tool_use" else {}
                    # the reply tool's report writes replies/<key>.md (no key: the session's task key) once it is sent
                    if i and str(b.get("name")).endswith("__reply") and i.get("report") and i.get("key", s["key"]):
                        rep[b.get("id")] = i.get("key", s["key"])
                    fp, cmd = str(i.get("file_path", "")), str(i.get("command", ""))
                    if "replies/" in fp + cmd:
                        writes.append((ts, "text", fp, cmd, s))
        ss.append(s)
    by_sup = collections.defaultdict(list)
    for s in ss:
        if s["sup"]:
            by_sup[s["sup"]].append(s)

    def short(x):
        return x["key"].removeprefix(x["root"] + "-") if x["root"] else x["key"]
    every_key = {k for x in ss if x["key"] for k in (x["key"], short(x))}

    def wrote(s, keys):
        """A write of replies/<one of keys>[-suffix] during s's life, by s or another session of its project."""
        longer = [k2[len(k):] for k2 in every_key - keys for k in keys if k2.startswith(k + "-")]   # x-s2 is another task's, not x's
        path = (rf"replies/(?:{'|'.join(map(re.escape, keys))})(?![\d/])"   # ABC-12 isn't ABC-123; replies/x/ is a folder
                + (rf"(?!(?:{'|'.join(map(re.escape, longer))})(?![\w-]))" if longer else ""))
        for w in writes:
            if not (s["first"] <= w[0] <= s["last"]) or (w[4] is not s and w[4]["root"] != s["root"]):
                continue
            if w[1] == "key":
                if w[2] in keys:
                    return True
                continue
            fp, cmd = w[2], w[3]
            # shortcut: `cp replies/KEY… elsewhere`, or a script that reads the reply and writes another file,
            # still counts as a write; parse the command if that shows up
            if re.search(path, fp) or \
                    re.search(rf"(>\s*|\b(?:mv|cp|tee|sed\s+-i)\b[^\n]*)\S*{path}", cmd) or \
                    re.search(rf"open\([^)]*{path}[^)]*,\s*['\"][wa]", cmd) or \
                    (re.search(r"\.write(?:_text)?\(|writeFile", cmd) and re.search(path, cmd)):
                return True
        return False

    def chain(s, seen):
        """s and its successors through Supersedes:, each once."""
        if s["sid"] in seen:
            return
        seen.add(s["sid"])
        yield s
        for n in by_sup.get(s["sid"], []):
            yield from chain(n, seen)

    for s in ss:
        key = s["key"]
        if not s["counted"] or not key:
            untasked += s["counted"] and key == ""
            continue
        tot["task"] += 1
        links = list(chain(s, set()))
        keys = {k for x in links if x["key"] for k in (x["key"], short(x))}
        if any(wrote(x, keys) for x in links):
            tot["wrote"] += 1
        elif any(x["last"] and P(x["last"]).timestamp() > END - 6 * 3600 for x in links):
            tot["open"] += 1  # ponytail: active in the last 6 h stands in for "still working"
        else:
            tot["lost"] += 1
            print(f"{s['sid']}\t{key}\t{s['last'][:16]}\t{s['name']}")
    print(tot, file=sys.stderr)
    if untasked and not tot["task"]:
        hint = ("ROOT's key_pattern was read" if task() is not TASK else
                "ROOT's key_pattern couldn't be read" if ROOT else "a key_pattern this can't see? Pass --project ROOT")
        print(f"note: {untasked} sessions in the window, none named a task by {task().pattern}: {hint}.", file=sys.stderr)


# What a handoff entry waits on, from its last wording; the first that matches. ponytail: keyword buckets, read the
# top rows by wait to see what they miss.
BUCKETS = [("user decision", r"\b(your call|decid|decision|approv|on you|asks? (you|the user)|yes/no|which (one|of))"),
           ("human review", r"\breview"), ("release", r"\b(release|deploy|plugin-release|publish)"),
           ("cleanup ask", r"\b(clean ?up|delete|prune|remove|archive)"), ("fault", r"\b(fail|broken|bug|error|crash|stuck)"),
           ("outside person", r"\b(waits? (on|for)|waiting (on|for)|asked|reply from|answer from|ping)")]
slug_of = lambda x: re.sub(r"^-+|-+$", "", re.sub(r"[^A-Za-z0-9._-]+", "-", x))[:60]  # pending's SLUG
HLINE = re.compile(r"^- (\d{4}-\d\d-\d\d \d\d:\d\d) \(([^)]*)\) (.*)$")


def handoff(days=28):
    """Each handoff entry (pending.file, else the state folder's pending.md, of every coordinated root a transcript ran in) open at the window's end or
    resolved in it, its rounds merged (open and archived files): its wait
    (first wording to resolved, or to the window's end), blocker bucket, rewordings, rounds (resolved more than once:
    recurring), reason unknown, detail and history sizes, and the transcript reads of its files (tokens ~ chars/4,
    sessions). stderr: totals, wait by bucket, and entries whose history was read against the rest."""
    window(days)
    cwds, reads, files = set(), [], list(transcripts())
    for f in files:  # a transcript's cwd is on its first lines
        for _, o in lines(f):
            if o.get("cwd"):
                cwds.add(o["cwd"])
                break
    rootset = {}
    for c in cwds:
        d = c
        while d not in ("/", ""):
            cfg = os.path.join(d, ".claude", "coordination.local.json")
            if os.path.isfile(cfg):
                try:
                    rel = (json.load(open(cfg)).get("pending") or {}).get("file")
                except Exception:
                    rel = None
                # unset: the state folder's pending.md, where setup puts it (lib.sh proj_dir; the adapter cats it)
                dflt = os.path.join(STATE, "projects", re.sub(r"[^A-Za-z0-9]", "-", os.path.realpath(d)), "pending.md")
                if rel or os.path.isfile(dflt):
                    rootset[d] = os.path.expanduser(rel) if rel else dflt  # relative: to the root; absolute or ~ kept
                break
            d = os.path.dirname(d)
    # reads of the entries' files: a Read of one, or a Bash command naming one (cat, sed, grep) or running
    # `--pending-history LABEL`, with its output's size. A history read is noted as `history:SLUG`.
    dirs = sorted({os.path.basename(rel[:-3]) + s + "/" for rel in rootset.values() for s in ("", "-archive")})
    HIST = re.compile(r"--pending-history\s+(?!--)(['\"]?)(.+?)\1(?:\s+--last\b|\s*$|\s*[|;&])")
    for f in files if dirs else []:
        sid, pend = os.path.basename(f)[:8], {}
        for line, o in lines(f):
            if out_of(o.get("timestamp")) or not (pend or "--pending-history" in line or any(d in line for d in dirs)):
                continue
            for b in (o.get("message") or {}).get("content") or []:
                if not isinstance(b, dict):
                    continue
                if b.get("type") == "tool_use" and b.get("name") in ("Read", "Bash"):
                    i = b.get("input") or {}
                    p = str(i.get("file_path") or i.get("command") or "")
                    if m := HIST.search(p):
                        p = "history:" + slug_of(m.group(2))
                    if p.startswith("history:") or any(d in p for d in dirs):
                        pend[b.get("id")] = p
                elif b.get("type") == "tool_result" and b.get("tool_use_id") in pend:
                    r = o.get("toolUseResult")
                    r = r if isinstance(r, dict) else {}
                    body = r["file"].get("content") if isinstance(r.get("file"), dict) else r.get("stdout")
                    reads.append((sid, pend.pop(b["tool_use_id"]), len(str(body or "")) // 4))
    print("root\tstate\tlabel\tadded\tresolved\twait_d\tbucket\trewordings\trounds\treason\tdetail_b\thistory_b\treads\tread_tok\treaders")
    rows = []
    for root, rel in sorted(rootset.items()):
        D = os.path.join(root, rel[:-3])
        A, DN = D + "-archive", os.path.basename(D)
        slugs = {os.path.basename(h)[:-len(".history.md")] for h in glob.glob(f"{D}/*.history.md") + glob.glob(f"{A}/*.history.md")}
        # An open entry with no history (pending.file unset: no hook keeps one): a row from its line alone, added on
        # its date, one round, rewordings unknown (-). Entries and LABEL as `pending`'s awk.
        try:
            body = open(D + ".md", errors="replace").read().split("\n")[1:]
        except OSError:
            body = []
        ents, on = [], False
        for x in body:
            if x.startswith("- "):
                on = True
                ents.append(x[2:])
            elif on and (x.startswith("#") or (x.strip() and not x[:1].isspace())):
                break
        for e in ents:
            m = re.match(r"(\d{4}-\d\d-\d\d) (.*)", e)
            label = re.match(r"(.*?)(?: \(|:|$)", m.group(2) if m else e).group(1)
            slug = slug_of(label)
            if not m or slug in slugs or (t0 := datetime.strptime(m.group(1), "%Y-%m-%d").timestamp()) > END:
                continue
            wait = (END - t0) / 86400
            bucket = next((n for n, rx in BUCKETS if re.search(rx, e, re.I)), "other")
            det = f"{D}/{slug}.md"
            mine = [(sd, t) for sd, pth, t in reads if f"{DN}/{slug}." in pth]
            rows.append(("open", bucket, wait, None, 1, "", None))  # no history to read: out of the read/unread split
            print("\t".join(map(str, [os.path.basename(root), "open", label, m.group(1), "", f"{wait:.1f}", bucket, "-", 1,
                                      "", os.path.getsize(det) if os.path.exists(det) else 0, 0, len(mine),
                                      sum(x[1] for x in mine), ",".join(sorted({x[0] for x in mine}))])))
        # one entry per slug: its archived rounds and its open one, lines after the window's end left out
        for slug in sorted(slugs):
            hs = [h for h in (f"{A}/{slug}.history.md", f"{D}/{slug}.history.md") if os.path.exists(h)]
            hl = sorted(m.groups() for h in hs for m in map(HLINE.match, open(h, errors="replace")) if m)
            ep = lambda t: datetime.strptime(t, "%Y-%m-%d %H:%M").timestamp()  # history times are local
            hl = [x for x in hl if ep(x[0]) <= END]
            if not hl:
                continue
            res = [x for x in hl if x[2].startswith("resolved: ")]
            state = "resolved" if hl[-1][2].startswith("resolved: ") else "open"
            if state == "resolved" and ep(res[-1][0]) < CUT:
                continue  # resolved before the window: last runs counted it
            words = [x[2] for x in hl if not x[2].startswith("resolved: ")]
            rounds = len(res) + (state == "open")
            # the wait: each round's first wording to its resolve, the open one to END
            wait, t0 = 0.0, None
            for t, _, x in hl:
                if t0 is None:
                    t0 = ep(t)
                if x.startswith("resolved: "):
                    wait, t0 = wait + ep(t) - t0, None
            wait = (wait + (END - t0 if t0 is not None else 0)) / 86400
            bucket = next((n for n, rx in BUCKETS if words and re.search(rx, words[-1], re.I)), "other")
            why = res[-1][2][len("resolved: "):] if state == "resolved" else ""
            det = next((p for p in (f"{D}/{slug}.md", f"{A}/{slug}.md") if os.path.exists(p)), "")
            at = [f"{DN}{s}/{slug}." for s in ("", "-archive")]  # open then, archived now: both
            mine = [(s, t, ".history.md" in p or p == "history:" + slug) for s, p, t in reads if p == "history:" + slug or any(a in p for a in at)]
            label = open(hs[-1], errors="replace").readline()[2:].rsplit(": history", 1)[0]
            rows.append((state, bucket, wait, len(words) - rounds, rounds, why, any(x[2] for x in mine)))
            print("\t".join(map(str, [os.path.basename(root), state, label, hl[0][0][:10], res[-1][0] if state == "resolved" else "",
                                      f"{wait:.1f}", bucket, max(0, len(words) - rounds), rounds,
                                      clip(why, 120), os.path.getsize(det) if det else 0, sum(map(os.path.getsize, hs)),
                                      len(mine), sum(x[1] for x in mine), ",".join(sorted({x[0] for x in mine}))])))
    med = lambda xs: f"{statistics.median(xs):.1f}" if xs else "-"
    print({"entries": len(rows), "open": sum(r[0] == "open" for r in rows), "unknown_reason": sum(r[5] == "unknown" for r in rows),
           "recurring": sum(r[4] > 1 for r in rows)}, file=sys.stderr)
    for b in sorted({r[1] for r in rows}):
        w = [r[2] for r in rows if r[1] == b]
        print(f"bucket\t{b}\t{len(w)} entries\tmedian wait {med(w)} d\ttotal {sum(w):.1f} d", file=sys.stderr)
    for read in (True, False):
        g = [r for r in rows if r[6] == read]
        print(f"history {'read' if read else 'unread'}\t{len(g)} entries\tmedian wait {med([r[2] for r in g])} d\t"
              f"median rewordings {med([r[3] for r in g if r[3] is not None])}\trecurring {sum(r[4] > 1 for r in g)}", file=sys.stderr)


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
            a[2] += req_usd(u, m.get("model"))
    for k, (w, n, d) in sorted(agg.items(), key=lambda x: -x[1][2]):
        print(f"{sid}\t{k}\twakes={w}\trequests={n}\tusd={d:.2f}\tper_wake={d / max(w, 1):.2f}")


CARD = "Coordinated session (session-orchestration)"  # the reply card's first words (hooks/reply-card.txt)
PLUGIN_MD = re.compile(r"session-orchestration/(?:\S*/)?(skills/[\w-]+|features|messages|terminals)/([\w.-]+\.md)\b")
STATUS_CMD = re.compile(r"[\w.]-status\b")  # session-status, or a project's own (proj-status); not a --status flag
OUTPUT = re.compile(r"/tasks/(\w+)\.output\b")  # a background Bash's output file


def doc_part(path):
    """The part of the context a read Markdown file is: skill (the orchestrating-sessions SKILL.md), coord_docs (the
    plugin's other skill files), feature_docs (features/, messages/, terminals/) or project_docs; None if not Markdown."""
    m = PLUGIN_MD.search(path)
    if m:
        if m.group(1) == "skills/orchestrating-sessions" and m.group(2) == "SKILL.md":
            return "skill"
        return "coord_docs" if m.group(1).startswith("skills") else "feature_docs"
    return "project_docs" if path.endswith(".md") else None


def kind_of(first, name, coord):
    """context-watch.sh's session kinds from the first prompt (coordinator, subcoordinator, chunk, review, task), with retro and other
    told apart; a session with neither a task nor retro that opened the pane or ran the status command with --start,
    --changes, --watch or --owner (lib.sh's coord_re) is a coordinator (a task that tests session-status stays a task)."""
    if re.search(r"^Act as a coordinator", first, re.M):
        return "coordinator"
    if re.match(r"\s*Coordinate +[A-Z][A-Z0-9]*-\d+([^0-9]|$)", first):
        return "subcoordinator"
    if re.search(r"^Chunk: [^/\n]+/[A-Za-z0-9]+", first, re.M):
        return "chunk"
    if re.search(r"^Session task: \S+ review([.,;:!)]|$)", first, re.M):
        return "review"
    if re.match(r"\s*([Ww]ork on |[A-Z][A-Z0-9]+-\d+:)", first) or re.search(r"^Session task: ", first, re.M):
        return "task"
    if re.search(r"R&D run|(rnd|retro)-weekly|<command-name>/?(session-orchestration:)?(rnd|retro)<", first) or name.startswith(("rnd", "retro-weekly")):
        return "retro"
    return "coordinator" if coord else "other"


def scan(f):
    """A main transcript: its requests ([context, output, ts]), what reached the context ([part, chars, what, the
    request it first reached, tokens]: each request's growth less the previous output, split by characters over what
    arrived since), counts per kind of load, the request before the first typed prompt after the first one, the
    request after the status watcher was armed, and whether it's a `-p` run."""
    reqs, items, pending, calls, bg, seen, n = [], [], [], {}, set(), set(), {}
    first = name = ""
    coord, typed, watch, test, entry = False, None, None, False, ""
    add = lambda part, chars, what="": pending.append([part, chars, what])
    count = lambda k, v=1: n.__setitem__(k, n.get(k, 0) + v)
    for _, o in lines(f):
        if o.get("isSidechain"):
            continue
        test = test or o.get("entrypoint") == "sdk-cli"
        entry = entry or o.get("entrypoint") or ""
        t, a, m = o.get("type"), o.get("attachment") or {}, o.get("message") or {}
        c = m.get("content")
        if t == "agent-name":
            name = o.get("agentName") or name
        elif a:
            at = a.get("type")
            if at == "deferred_tools_record":  # the schemas a ToolSearch loaded (their text is here, not in its result)
                names = {e.get("name") for e in a.get("entries") or [] if isinstance(e, dict)}
                count("sendmessage_schema", "SendMessage" in names)
                count("reply_schema", "mcp__session-orchestration__reply" in names)
                if names:
                    add("schemas", len(json.dumps(a)), "reply" if names == {"mcp__session-orchestration__reply"} else "")
            elif at == "invoked_skills":  # a compaction put the skill back
                for s in a.get("skills") or []:
                    ours = "orchestrating-sessions" in s.get("name", "")
                    count("skill_reinject", ours)
                    add("skill" if ours else "rest", len(s.get("content", "")))
            elif at == "hook_additional_context":
                body = json.dumps(a.get("content", ""))
                count("card", CARD in body)
                add("rest", len(body), "card" if CARD in body else "")
            elif at == "queued_command" and "<cross-session-message" in str(a.get("prompt", "")):
                count("msgs"); count("mid_turn")
                add("rest", len(str(a.get("prompt", ""))))
        elif t == "user":
            blocks = [b for b in c if isinstance(b, dict)] if isinstance(c, list) else []
            txt = c if isinstance(c, str) else "".join(b.get("text", "") for b in blocks if b.get("type") == "text")
            results = [b for b in blocks if b.get("type") == "tool_result"]
            if isinstance(c, str):
                count("msgs", c.startswith("Another Claude session sent a message"))
                add("rest", len(c))
            if not first and txt.strip() and not results and not o.get("isMeta"):
                first = txt
            elif first and typed is None and txt != first and said(o, txt) == "human" \
                    and not txt.startswith(("Coordinator pane", "Approval pane")):  # the pane's prompts
                typed = len(reqs) - 1
            for b in results:
                part, what = calls.get(b.get("tool_use_id"), ("rest", ""))
                rt = b.get("content")
                rt = rt if isinstance(rt, str) else "".join(x.get("text", "") for x in rt or [] if isinstance(x, dict))
                mm = re.search(r"with ID: (\w+)", rt) if part == "status" else None
                if mm:
                    bg.add(mm.group(1))  # its output, read later, is status output too
                add(part, len(rt), what)
            for b in blocks:
                if b.get("type") == "text":
                    tx = b.get("text", "")
                    ours = tx.startswith("Base directory for this skill:") and "orchestrating-sessions" in tx.split("\n", 1)[0]
                    count("skill_load", ours)
                    add("skill" if ours else "rest", len(tx), "load" if ours else "")
        elif t == "assistant":
            rid = o.get("requestId")
            if rid and rid not in seen and m.get("model") != "<synthetic>":  # a synthetic one (an API error) has no usage
                seen.add(rid)
                u = m.get("usage") or {}
                items += [it + [len(reqs)] for it in pending]
                pending.clear()
                reqs.append([ctx_of(u),
                             u.get("output_tokens", 0), o.get("timestamp") or ""])
            for b in c if isinstance(c, list) else []:
                if not isinstance(b, dict) or b.get("type") != "tool_use":
                    continue
                nm, inp = b.get("name", ""), b.get("input") or {}
                cmd, p = str(inp.get("command", "")), str(inp.get("file_path", ""))
                out = OUTPUT.search(cmd if nm == "Bash" else p)
                docs = [(d, os.path.basename(x)) for x in ([p] if nm == "Read" else re.findall(r"\S+\.md\b", cmd) if nm == "Bash" else [])
                        for d in [doc_part(x)] if d]
                # shortcut: a cat of several files counts as its first one's part; split it if such reads turn up at Start
                part, what = docs[0] if docs and (nm == "Read" or re.search(r"\b(cat|sed|head|tail|awk)\b", cmd)) else ("rest", "")
                if part == "rest" and ((nm == "Bash" and STATUS_CMD.search(cmd)) or (out and out.group(1) in bg)):
                    part = "status"
                part = "schemas" if nm == "ToolSearch" else part
                if nm == "Bash" and STATUS_CMD.search(cmd) and re.search(r"\s--(start|changes|watch|owner)\b", cmd):
                    coord = True
                    if watch is None and re.search(r"\s--watch\b", cmd):
                        watch = len(reqs)  # this call's request is len(reqs) - 1: the next one is the first after it
                coord = coord or nm == "mcp__session-orchestration__open_pane"
                count("worker_md", part == "coord_docs" and what == "worker.md")
                count("sendmessage_call", nm == "SendMessage")
                count("reply_call", nm == "mcp__session-orchestration__reply")
                calls[b.get("id")] = (part, what)
    tot = {}
    for it in items:
        tot[it[3]] = tot.get(it[3], 0) + it[1]
    for it in items:
        i = it[3]
        grow = reqs[i][0] - reqs[i - 1][0] - reqs[i - 1][1] if i > 0 else 0
        share = round(grow * it[1] / tot[i]) if grow > 0 and tot[i] else 0
        # The card rides on a task's early tool call, whose growth carries context no line records (reminders,
        # attachments): its share took that too (3.6K for a ~0.7K card). Capped at its size (≥ 3 chars a token).
        it.append(min(share, it[1] // 3) if it[2] == "card" else share)
    return dict(kind=kind_of(first, name, coord), reqs=reqs, items=items, n=n, typed=typed, watch=watch, test=test, entry=entry or "-")


def started(days):
    """The main transcripts whose first request falls in the window, scanned; `-p` runs left out."""
    window(days)
    for f in transcripts():
        s = scan(f)
        if s["reqs"] and not s["test"] and not out_of(s["reqs"][0][2]):
            yield os.path.basename(f)[:8], s


START_PARTS = ["skill", "coord_docs", "feature_docs", "project_docs", "schemas", "status"]


def start(days=7):
    """One row per coordinator that started in the window: its entrypoint (claude-desktop, cli: the harness base
    differs), its Start's requests, the context at the first request (base) and after Start, Start's own increment
    (after_start - base), and what Start added by part (tokens; rest: model output, small reads, hook text); then the medians.
    Start ends at the request after the status watcher was armed, or the one before the first typed prompt after the
    first if that comes sooner; with neither, at request 15. Medians: over all, then per entrypoint when several."""
    print("session\tstarted\tentry\treqs\tbase\tafter_start\tincrement\t" + "\t".join(START_PARTS) + "\trest")
    rows = []
    for sid, s in started(days):
        if s["kind"] != "coordinator":
            continue
        reqs = s["reqs"]
        ends = [e for e in (s["watch"], s["typed"]) if e is not None and e >= 1]
        end = min(min(ends) if ends else 14, len(reqs) - 1)
        parts = [sum(x[4] for x in s["items"] if x[0] == p and x[3] <= end) for p in START_PARTS]
        row = [end + 1, reqs[0][0], reqs[end][0], reqs[end][0] - reqs[0][0]] + parts + [reqs[end][0] - reqs[0][0] - sum(parts)]
        rows.append((s["entry"], row))
        print("\t".join(map(str, [sid, reqs[0][2][:16], s["entry"]] + row)))
    med = lambda xs: sorted(xs)[len(xs) // 2] if xs else 0
    entries = sorted({e for e, _ in rows})
    groups = ["all"] + (entries if len(entries) > 1 else [])
    for e in groups:
        rs = [r for x, r in rows if e in ("all", x)]
        print("\t".join(map(str, ["median", f"n={len(rs)}", e] + [med([r[i] for r in rs]) for i in range(len(START_PARTS) + 5)])))
    # each median against its target (SKILL.md, protocol): over/target, so the furthest over shows
    for e in groups:
        rs = [r for x, r in rows if e in ("all", x)]
        for name, part, limit in START_TARGETS:
            v = med([part(r) for r in rs])
            print("\t".join(map(str, ["target", e, name, v, limit, f"{'over' if v > limit else 'ok'} {round(100 * v / limit)}%"])))


# Start's targets: (name, the row's value, at most). Row: reqs base after_start increment, START_PARTS, rest.
START_TARGETS = [("increment", lambda r: r[3], 23000), ("reqs", lambda r: r[0], 6), ("skill+coord_docs", lambda r: r[4] + r[5], 6500),
                 ("feature_docs", lambda r: r[6], 500), ("project_docs", lambda r: r[7], 6000), ("schemas", lambda r: r[8], 2600),
                 ("status+rest", lambda r: r[9] + r[10], 7000)]


LOADS = ["msgs", "mid_turn", "skill_load", "skill_reinject", "worker_md", "card", "sendmessage_schema", "reply_schema",
         "sendmessage_call", "reply_call"]


def loads(days=7):
    """One row per session kind, over sessions that started in the window: sessions, those with messages, then counts
    of messages (mid-turn too), orchestrating-sessions skill loads and compaction re-injects, worker.md reads, reply
    cards, SendMessage and reply schema loads and calls, and the median tokens of a skill load, a card and a reply
    schema load (only reply in its ToolSearch), over those after the first request (one before it has no growth to
    measure)."""
    agg = {}
    for _, s in started(days):
        a = agg.setdefault(s["kind"], {"sessions": 0, "with_msgs": 0, "tok": {"load": [], "card": [], "reply": []}})
        a["sessions"] += 1
        a["with_msgs"] += s["n"].get("msgs", 0) > 0
        for k in LOADS:
            a[k] = a.get(k, 0) + s["n"].get(k, 0)
        for x in s["items"]:
            if x[2] in a["tok"] and x[3] > 0:
                a["tok"][x[2]].append(x[4])
    med = lambda xs: sorted(xs)[len(xs) // 2] if xs else "-"
    # reply: card_tok + reply_tok, against its 1K target (SKILL.md, protocol); `-` with neither measured
    print("kind\tsessions\twith_msgs\t" + "\t".join(LOADS) + "\tskill_tok\tcard_tok\treply_tok\treply\treply_target")
    for k, a in sorted(agg.items(), key=lambda kv: -kv[1]["sessions"]):
        m = [med(a["tok"][t]) for t in ("load", "card", "reply")]
        r = sum(x for x in m[1:] if x != "-") if m[1:] != ["-", "-"] else "-"
        t = "-" if r == "-" else f"{'over' if r > 1000 else 'ok'} {round(r / 10)}%"
        print("\t".join(map(str, [k, a["sessions"], a["with_msgs"]] + [a[x] for x in LOADS] + m + [r, t])))


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
    lines_ = open(src, encoding="utf-8").read().split("\n")
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
    # the generator mark: reply's done report refuses a page without it (a pandoc page lost dark mode)
    open(dst, "w", encoding="utf-8").write(f"<!doctype html><html lang=en><head><meta charset=utf-8><meta name=generator content=retro.py><meta name=viewport content='width=device-width,initial-scale=1'>"
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
    secs = re.search(r"USAGE_SECTIONS = \[([^\]]*)\]", reg)
    inv |= {("press", f"{p}-{slug(s)}") for s in re.findall(r"'([^']+)'", secs.group(1) if secs else "") for p in ("fold", "unfold", "card")}
    inv |= {("tool", t) for t in re.findall(r"tool\.register\(\{\s*name: '([a-z_]+)'", reg)}
    inv |= {("skill", d) for d in os.listdir(f"{PLUGIN}/skills") if os.path.isfile(f"{PLUGIN}/skills/{d}/SKILL.md")}
    inv |= {("doc", os.path.basename(f)) for f in glob.glob(f"{PLUGIN}/**/*.md", recursive=True)
            if os.path.basename(f) not in ("SKILL.md", "README.md")}
    ss = open(f"{PLUGIN}/skills/orchestrating-sessions/session-status", errors="replace").read()
    inv |= {("flag", fl) for fl in re.findall(r"^#\s+session-status (--[a-z-]+)", ss, re.M)}
    lib = open(f"{PLUGIN}/lib.sh", errors="replace").read()
    cfg = lib.partition("\nconfig() {")[2].partition("\n  esac")[0]   # config()'s first case: its key lines
    inv |= {("config", k) for ks in re.findall(r"^\s+([a-z_.|]+)\) ;;", cfg, re.M) for k in ks.split("|")}
    return inv


FAULTS = ("block", "refuse", "relay", "wake", "error")  # lib.sh usage's telemetry=full kinds


def usage(days=30):
    """Each feature with its uses in the window and first-seen date; `unused` when 0 uses and it existed all window.
    Uses: the pane's usage log (telemetry=local or full; full adds its fault lines), transcript tool calls, skill loads, doc reads, session-status flags.
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
            if h[0] in FAULTS:  # one row per fault and where: a hook line, a --flag, an exit code
                n = None if h == ("wake", "wake") else o.get("n")  # a wake's n is the lines it reported, not a kind
                at = f"{o['at']}@{o['v']}" if ":" in o.get("at", "") and o.get("v") else o.get("at")  # a file:line holds for its version; a --flag across them
                h = (h[0], " ".join(str(x) for x in (h[1], at, n) if x not in (None, "")))
            if CUT <= o["t"] <= END:
                if h in count or h[0] in ("path", "auto", *FAULTS):
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
                    s = "retro" if s == "rnd" else s  # the old name of the skill counts as retro
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
                    hit = [("skill", {"rnd": "retro"}.get(sk := str(inp.get("skill", "")).split(":")[-1], sk))]
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
        known = k not in ("config", "path", "auto", *FAULTS) and (k != "press" or on)
        unused = known and (k, n) not in pane and count[(k, n)] == 0 and first.get((k, n), today) <= start
        logged = k in ("path", "auto", *FAULTS)
        print(f"{k}\t{n}\t{count[(k, n)] if known or logged else '-'}\t{first.get((k, n), '-' if logged else today)}\t{'unused' if unused else ''}")


MASKS = [(re.compile(p, re.I), r) for p, r in [
    (r"[\w.+-]+@[\w-]+(\.[\w-]+)+", "<email>"),
    (r"\b(bearer|basic)\s+(?=[\w.~+/-]*[\d+/])[\w.~+/-]{12,}=*", r"\1 <masked>"),
    (r"\b((?:\w*[_-])?(?:password|passwd|secret|token|api[_-]?key|auth[_-]?token|cookie|session[_-]?key))\b(\"?\s*[:=]\s*)(\"[^\"]*\"|'[^']*'|[^\s,;]+)", r"\1\2<masked>"),
    (r"\b(gh[pousr]_|github_pat_|glpat-|xox[abprs]-|sk-|AKIA|AIza|eyJ)[\w.+/=-]{8,}", "<masked>"),
    (r"(?<![\w+=])(?=[\w+=]*\d)(?=[\w+=]*[A-Za-z])[\w+=]{32,}", "<masked>"),  # long opaque runs: keys, SHAs
]]
# A mixed-case run with digits and a 16+ piece between / or -: a key such as AWS's, not a path or slug.
KEYISH = re.compile(r"(?<![\w+/=.-])[\w+/=-]{24,}")
iskey = lambda m: bool(re.search(r"\d", m) and re.search(r"[a-z]", m) and re.search(r"[A-Z]", m)) and \
    max(map(len, re.split(r"[/-]", m))) >= 16


def mask(s):
    """S with emails, credentials and long opaque strings replaced, and the home folder as ~."""
    s = re.sub(re.escape(HOME) + r"(?![\w.-])", "~", s)
    for rx, r in MASKS:
        s = rx.sub(r, s)
    return KEYISH.sub(lambda m: "<masked>" if iskey(m.group(0)) else m.group(0), s)


def search(text="", days=7):
    """One line per hit of TEXT (case-insensitive, whitespace-insensitive) in sessions' prompts, messages from other
    sessions and their own text, newest first: `NAME (ID8) · DATE · who: snippet` (who: you, msg, claude; local
    time), the snippet masked and clipped like events'; masked text isn't found. Not tool calls or results, sidechains
    or the calling session. At most 3 hits a session and 30 lines, then how many more; exit 1 with no hit."""
    needle = " ".join(text.split()).lower()
    if not needle:
        sys.exit("usage: retro.py search TEXT [days=7]")
    window(days)
    longest = max(needle.replace("~", " ").split() or [""], key=len)   # ~ is the masked home: the raw line has the path
    pre = "" if re.search(r'["\\]', longest) else longest   # raw-line prefilter where JSON keeps the text as is
    me = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    hits, names = {}, {}  # session id -> [(ts, who, snippet)] over all its transcripts; its name
    for f in transcripts():
        sid = os.path.basename(f).removesuffix(".jsonl")
        if me and sid == me:
            continue
        for line in open(f, errors="replace"):
            if '"agent-name"' in line:
                try:
                    names[sid] = json.loads(line).get("agentName") or names.get(sid, "")
                except Exception:
                    pass
                continue
            if pre and pre not in line.lower():
                continue
            try:
                o = json.loads(line)
            except Exception:
                continue
            ts = o.get("timestamp", "")
            if out_of(ts) or o.get("isSidechain") or o.get("type") not in ("user", "assistant"):
                continue
            c = (o.get("message") or {}).get("content")
            txt = c if isinstance(c, str) else " ".join(b.get("text", "") for b in c or [] if isinstance(b, dict) and b.get("type") == "text")
            who = "claude" if o["type"] == "assistant" else {"human": "you", "xmsg": "msg"}.get(said(o, txt))
            t = " ".join(txt.split())
            if not who or needle not in t.lower().replace(HOME.lower(), "~"):   # cheap check before masking
                continue
            t = mask(t)
            i = t.lower().find(needle)
            if i >= 0:
                hits.setdefault(sid, []).append((ts, who, ("…" if i > 80 else "") + clip(t[max(0, i - 80):])))
    rows = sorted(((ts, sid, who, snip) for sid, g in hits.items() for ts, who, snip in g), reverse=True)
    shown, per, cut = [], {}, set()
    when = lambda ts: P(ts).astimezone().strftime("%Y-%m-%d %H:%M") if ts else "-"
    for ts, sid, who, snip in rows:
        if per.get(sid, 0) < 3 and len(shown) < 30:
            per[sid] = per.get(sid, 0) + 1
            nm = names.get(sid)
            shown.append(f"{nm + ' (' + sid[:8] + ')' if nm else sid[:8]} · {when(ts)} · {who}: {snip}")
        else:
            cut.add(sid)
    print("\n".join(shown) or f"no hits for {text!r} in {days} days")
    if cut:
        print(f"… {len(rows) - len(shown)} more (sessions: {len(cut)}): narrow TEXT or days, or --peek ID")
    if not shown:
        sys.exit(1)


def tsv(d, name):
    """DIR/NAME's rows as dicts (tab-separated, no quoting); [] when the file is missing."""
    csv.field_size_limit(10**9)
    try:
        with open(os.path.join(d, name), errors="replace", newline="") as f:
            return list(csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE))
    except FileNotFoundError:
        return []


med = lambda xs: statistics.median(xs) if xs else 0
ep = lambda s: calendar.timegm(time.strptime(s[:16], "%Y-%m-%dT%H:%M")) + (int(s[17:19]) if s[17:19].isdigit() else 0)
UTC = lambda s: datetime.fromisoformat(s.replace("Z", "")[:19]).replace(tzinfo=timezone.utc)
LAND = re.compile(r"gh pr (merge|view|checks)|gh run (watch|list|view)")


def deny_class(d2):
    """An events.tsv deny row's class, from its detail2 (`source/reasonType: message`)."""
    src, _, msg = d2.partition(": ")
    if msg.startswith("Background session: this compound command"):
        return "split-hint"
    if "gave no verdict" in msg or "Classifier unavailable" in msg:
        return "no-verdict"
    if src.startswith("hook"):
        return "hook-block"
    return "refusal" if "classifier" in src else "other:" + src[:30]


def wait_class(r):
    """A waits.tsv row's class: what the call waited on."""
    c, tool = r.get("input") or "", r.get("tool") or ""
    if re.search(r"gh pr checks|gh run watch|--watch", c):
        return "ci-watch"
    if re.search(r"\.test\.sh|plugin test|tsc ", c):
        return "tests"
    if tool in ("Edit", "Write", "NotebookEdit"):
        return "edit"
    if tool in ("AskUserQuestion", "ExitPlanMode") or "ask_approval" in tool:
        return "ask"
    if tool != "Bash":
        return "tool:" + tool[:28]
    return "cd…" if c.startswith("cd ") else "bash-other"


def usage_faults(d):
    return [u for u in tsv(d, "usage.tsv") if u.get("kind") in FAULTS or (u.get("feature") or "").startswith(("fold-", "unfold-", "card-"))]


def waste(d="", days=7, opening_chars=24):
    """The waste counts of a retro folder: DIR's sessions.tsv, events.tsv, waits.tsv and usage.tsv (each optional, as
    this script's commands wrote them) and the denial log, in the window. Counts and ids only."""
    if not d:
        sys.exit("usage: retro.py waste DIR [days=7]")
    window(days)
    N = int(opening_chars)
    s = tsv(d, "sessions.tsv")
    if s:
        n = lambda k: sum(float(r[k] or 0) for r in s)
        co = [r for r in s if "coordinator" in r["name"]]
        print(f"sessions {len(s)} usd {n('usd'):.2f} out {n('out_tok') / 1e6:.1f}M cw {n('cache_write') / 1e6:.1f}M "
              f"cr {n('cache_read') / 1e6:.1f}M peak_ctx median {int(med([int(r['peak_ctx']) for r in s]))} "
              f"compacted {sum(r['compacts'] not in ('', '0') for r in s)} ({int(n('compacts'))}) "
              f"coordinator-named {len(co)} usd {sum(float(r['usd']) for r in co):.2f}")
    live = [r for r in tsv(d, "events.tsv") if not r.get("test")]   # headless test sessions left out
    if live:
        opening = lambda cmd: re.sub(r"\s+", " ", cmd).strip()[:N]
        by = collections.defaultdict(list)
        for r in live:
            by[r["session"]].append(r)
        den, retry, hooks = collections.Counter(), collections.Counter(), collections.Counter()
        land = 0
        for rs in by.values():
            for k, r in enumerate(rs):
                if r["kind"] != "deny":
                    continue
                c = deny_class(r["detail2"] or "")
                den[c] += 1
                if c == "hook-block":
                    hooks[re.sub(r"[0-9a-f]{8,}|\d+", "N", r["detail2"].partition(": ")[2])[:70]] += 1
                    land += bool(LAND.search(r["detail"] or ""))
                name, _, arg = (r["detail"] or "").partition(": ")
                if name != "Bash":
                    continue
                t, o, own = ep(r["ts"]), opening(arg), True
                for r2 in rs[k + 1:]:   # the same opening again within 5 minutes; the first is the denied call's own row
                    if ep(r2["ts"]) - t > 300:
                        break
                    if r2["kind"] == "bash" and opening(r2["detail"] or "") == o:
                        if own:
                            own = False
                            continue
                        retry[c] += 1
                        break
        print("deny", sum(den.values()), dict(den))
        print("retries", sum(v for k, v in retry.items() if k != "split-hint"), dict(retry))
        print("hook blocks on landing commands", land)
        print("hook block texts:")
        for k, v in hooks.most_common(12):
            print(f"  {v:4d}  {k}")
        bang = {(r["session"], r["detail"]) for r in live if r["kind"] == "bang"}
        cnt = collections.Counter(r["kind"] for r in live)
        print("bang distinct", len(bang), "sessions", len({x for x, _ in bang}),
              " ".join(f"{k} {cnt[k]}" for k in ("ran", "self", "ask", "human", "xmsg", "err")))
        print("bang openings:", collections.Counter(re.sub(r"\s+", " ", c).split(" ")[0][:30] for _, c in bang).most_common(12))
    w = tsv(d, "waits.tsv")
    if w:
        for tag in ("", "sleep"):
            byc = collections.defaultdict(lambda: [0, 0])
            for r in w:
                if (r.get("sleep") or "") == tag:
                    v = byc[wait_class(r)]
                    v[0] += 1; v[1] += int(float(r["minutes"] or 0))
            print(f"waits{' (sleep)' if tag else ''}", sum(v[0] for v in byc.values()), "minutes", sum(v[1] for v in byc.values()),
                  sorted(((k, *v) for k, v in byc.items()), key=lambda x: -x[2])[:10])
        print("waits by decision:", collections.Counter(r["decision"] for r in w).most_common(6))
    dn, p = [], f"{HOME}/.cache/session-status/denied.jsonl"
    rset = {os.path.abspath(os.path.expanduser(ROOT)), os.path.realpath(os.path.expanduser(ROOT))} if ROOT else set()
    for _, o in lines(p) if os.path.exists(p) else []:
        if not isinstance(o, dict) or not isinstance(o.get("time"), (int, float)) or not CUT <= o["time"] <= END:
            continue
        cwd = str(o.get("cwd") or "")
        if ROOT and not any(cwd == r or cwd.startswith(r.rstrip("/") + "/") for r in rset):
            continue
        rs = str(o.get("reason") or "")
        o["k"] = ("noverdict" if "Classifier unavailable" in rs or "no verdict" in rs else
                  "split" if "Background session: this compound command" in rs else "refusal")
        dn.append(o)
    print("denied.jsonl", len(dn), dict(collections.Counter(o["k"] for o in dn)))
    print("refusal reasons:", collections.Counter(str(o.get("reason"))[:40] for o in dn if o["k"] == "refusal").most_common(8))
    f = usage_faults(d)
    if f:
        print("usage faults:", "; ".join(f"{u['kind']} {u['feature']} {u['uses']}" for u in f))


def merges(d="", prs_json="", days=7, repo="", runs_json=""):
    """The merge rows of DIR's units.tsv against the host's PR list (PRS_JSON: number, createdAt, mergedAt): how long a
    merge command took to land, and $ per merged PR. OWNER/REPO drops merge rows that name another repo. Then
    quality()'s rows (PRS_JSON with headRefName, reviews, title, body; RUNS_JSON the host's CI runs)."""
    if not d or not prs_json:
        sys.exit("usage: retro.py merges DIR PRS_JSON [days=7] [OWNER/REPO] [RUNS_JSON]")
    window(days)
    prs = {p["number"]: p for p in json.load(open(prs_json))}
    s = tsv(d, "sessions.tsv")
    usd_all = sum(float(r["usd"] or 0) for r in s)
    sstart = {r["session"]: r["start"] for r in s}
    num = lambda r: r["id"].rpartition("#")[2]
    ms = [r for r in tsv(d, "units.tsv") if r["kind"] == "merge" and num(r).isdigit()
          and not (repo and "#" in r["id"] and r["id"].rpartition("#")[0] != repo)]
    nums = collections.Counter(int(num(r)) for r in ms)
    mins = lambda a, b: (UTC(a) - UTC(b)).total_seconds() / 60
    p90 = lambda x: sorted(x)[min(len(x) - 1, int(0.9 * len(x)))] if x else 0
    m2m, o2m, s2m, notm, seen = [], [], [], set(), set()
    for r in ms:
        n = int(num(r))
        p = prs.get(n) or {}
        if not p.get("mergedAt"):
            notm.add(n)
            continue
        if n in seen:   # a PR's first merge row only
            continue
        seen.add(n)
        m2m.append(mins(p["mergedAt"], r["ts"]))
        o2m.append(mins(p["mergedAt"], p["createdAt"]))
        if r["session"] in sstart:
            s2m.append(mins(r["ts"], sstart[r["session"]]))
    print(f"merge rows {len(ms)} distinct {len(nums)} dup {sorted(n for n, c in nums.items() if c > 1)} not merged {sorted(notm)}")
    print(f"merge cmd -> merged min: median {med(m2m):.0f} p90 {p90(m2m):.0f}; open -> merged median {med(o2m):.0f}; "
          f"first activity in window -> merge cmd median {med(s2m):.0f} (n={len(s2m)})")
    inwin = lambda ts: bool(ts) and not out_of(ts[:19])
    gm = [p for p in prs.values() if inwin(p.get("mergedAt"))]
    print(f"host: merged in window {len(gm)} opened {sum(inwin(p.get('createdAt')) for p in prs.values())}")
    print(f"$ per merged PR: ran {usd_all / max(1, len(nums) - len(notm)):.2f} host {usd_all / max(1, len(gm)):.2f}")
    quality(ms, prs, s, runs_json)


def quality(ms, prs, s, runs_json=""):
    """Per merged PR of the merge rows: CI runs on its branch from its opening to its merge that failed or were re-run
    (first-try green when none; `-` without RUNS_JSON, runs, or for a fork's PR), CHANGES_REQUESTED reviews, and
    follow-ups opened by the window's end: a later PR on the same branch (the task reopened) or one whose title or body
    says fixes/reverts/follow-up next to #N. Its kind is the merging session's, as spend reads it (`host`: a reviewer
    merged; `unknown`: no transcript). Then one line per kind, with n and the merging sessions' median $ per PR merged."""
    runs = collections.defaultdict(list)
    for r in json.load(open(runs_json)) if runs_json else []:
        runs[r.get("headBranch")].append(r)
    usd = {r["session"]: float(r["usd"] or 0) for r in s}
    sids = {r["session"] for r in ms}
    kinds = {os.path.basename(f)[:8]: scan(f)["kind"] for f in transcripts() if os.path.basename(f)[:8] in sids}
    rows, seen = [], set()
    for r in ms:
        n = int(r["id"].rpartition("#")[2])
        p = prs.get(n) or {}
        if n in seen or not p.get("mergedAt"):
            continue
        seen.add(n)
        br, done, fork = p.get("headRefName"), p["mergedAt"], p.get("isCrossRepository")
        # a reused branch: runs after its previous PR's merge only
        prev = max([q["mergedAt"] for q in prs.values() if q.get("headRefName") == br and q.get("mergedAt")
                    and q["mergedAt"] < done] + [p.get("createdAt") or ""])
        rs = [] if fork else [x for x in runs.get(br, []) if prev <= (x.get("createdAt") or "") <= done]
        # gh lists a run's last attempt only: a re-run means an earlier attempt didn't pass
        fails = sum((x.get("conclusion") in ("failure", "timed_out", "startup_failure")) + max(0, (x.get("attempt") or 1) - 1)
                    for x in rs)
        rounds = sum(v.get("state") == "CHANGES_REQUESTED" for v in p.get("reviews") or [])
        fix = re.compile(rf"(?i)\b(fix(es)?|reverts?|follow-?up( to| for| of)?)\W+(\S+\W+)?#{n}\b|#{n}\b\W+follow-?up\b")
        fu = [q["number"] for q in prs.values() if done < (q.get("createdAt") or "") <= END_ISO + "Z"
              and ((q.get("headRefName") == br and not fork and not q.get("isCrossRepository"))
                   or fix.search(f"{q.get('title', '')}\n{q.get('body') or ''}"))]
        sid = r["session"]
        kind = kinds.get(sid) or ("host" if sid == "host" else "unknown")
        rows.append([kind, n, fails if rs else None, rounds, fu, sid])
        print("\t".join(map(str, ["quality", f"#{n}", kind, "-" if not rs else fails, "-" if not rs else int(not fails),
                                  rounds, ",".join(f"#{x}" for x in fu) or "-"])))
    merged = collections.Counter(x[5] for x in rows)
    for k in sorted({x[0] for x in rows}):
        g = [x for x in rows if x[0] == k]
        ci = [x for x in g if x[2] is not None]
        cost = [usd[x[5]] / merged[x[5]] for x in g if x[5] in usd and x[5] in kinds]
        print(f"quality {k} n={len(g)}: first-try green {sum(not x[2] for x in ci)}/{len(ci)}, CHANGES_REQUESTED "
              f"{sum(x[3] for x in g)} in {sum(x[3] > 0 for x in g)} PRs, follow-up {sum(bool(x[4]) for x in g)}, "
              f"merging session's $ per PR merged median {f'{med(cost):.2f}' if cost else '-'}")


TEST_RX = [(k, re.compile(rx)) for k, rx in [
    ("shell-suite", r"\S*\.test\.sh\b"), ("plugin-test", r"claude plugin (?:test|validate)"), ("tsc", r"\btsc\b"),
    ("scrub", r"scrub-check"), ("js-test", r"\b(?:npm|pnpm|yarn|bun|npx)\b[^|;&]*\b(?:test|jest|vitest|lint|typecheck|build)\b"),
    ("pytest", r"\bpytest\b|python3? -m (?:pytest|unittest)"), ("go-test", r"\bgo (?:test|build|vet)\b"),
    ("cargo", r"\bcargo (?:test|build|check|clippy)\b"), ("gradle", r"gradlew?\b[^|;&]*\b(?:test|build|check|assemble)"),
    ("mvn", r"\bmvn\b"), ("dotnet", r"\bdotnet (?:test|build)\b"), ("make", r"\bmake (?:test|check|build)\b"),
    ("playwright", r"playwright test")]]
RATE = re.compile(r"rate limit|HTTP 429|submitted too quickly|abuse detection|rate.?limited", re.I)
GH = re.compile(r"(?:^|[;&|(`{\n]|\bthen|\bdo|\bif|\buntil|\bwhile|\$\()\s*(?:\w+=\S+\s+)*(?:rtk\s+(?:proxy\s+)?)?gh\s+(\w+)(?:\s+(\w[\w-]*))?")
HANDOVER = re.compile(r"(?:-status[\"']?|\$\{?\w+\}?[\"']?)\s+--handover\b")
SUITE = re.compile(r"(?:^|[;&|(){\n]|\bthen|\bdo|\btime|\bexec)\s*(?:\w+=\S+\s+)*(?:(?:bash|sh|zsh)\s+(?:-\w+\s+)*)?[\"']?([^\s=\"']*\.test\.sh)[\"']?([^;&|)\n]*)")


def suite_runs(cmd):
    """The *.test.sh files a command runs (in command position, or bash's argument; a variable holding one is
    resolved), as 'name:full' or 'name:<n sections>'. A grep, sed or cat of the file is not a run."""
    var = dict(re.findall(r"\b(\w+)=[\"']?(\S*\.test\.sh)\b", cmd))
    c = re.sub(r"\$\{?(\w+)\}?", lambda m: var.get(m.group(1), m.group(0)), cmd)
    out = []
    for path, rest in SUITE.findall(c):
        args = re.split(r"\d*[<>]", rest)[0].split()   # sections named before any redirect
        out.append(f"{os.path.basename(path)}:{len(args) or 'full'}")
    return out


def account_dirs():
    """Account dirs ($CLAUDE_CONFIG_DIR, ~/.claude, ~/.claude-*) as (label, path), each once; label ~/.claude-work style."""
    out, seen = [], set()
    for d in [os.environ.get("CLAUDE_CONFIG_DIR") or "", f"{HOME}/.claude"] + sorted(glob.glob(f"{HOME}/.claude-*")):
        p = os.path.abspath(os.path.expanduser(d)) if d else ""
        if p and os.path.isdir(p) and p not in seen:
            seen.add(p)
            out.append(("~" + p[len(HOME):] if p.startswith(HOME + "/") else p, p))
    return out


def spend_extract(d):
    """One pass over the window's transcripts (main threads and subagents) into DIR/spend-{req,sess,wakes,ev}.tsv:
    a row per request, session, wake (what started a turn) and event (test run, gh call, handover, compaction, rate
    limit). Snippets are capped at 80 chars. Each request's account: its owner uuid, voted to an account dir by the
    jobs/<id8>/state.json that dir holds and by a transcript tree only that dir holds."""
    jobs, holds = {}, collections.defaultdict(set)
    for label, p in account_dirs():
        holds[os.path.realpath(f"{p}/projects")].add(label)
        for sp in glob.glob(f"{p}/jobs/*/state.json"):
            try:
                s = json.load(open(sp))
            except (OSError, ValueError):
                continue
            fl = (s.get("respawnFlags") if isinstance(s, dict) else None) or []
            flag = lambda k: next((fl[i + 1] for i in range(len(fl) - 1) if fl[i] == k), "")
            jobs.setdefault(os.path.basename(os.path.dirname(sp)), {})[label] = (flag("--model"), flag("--effort"))
    home_enc = re.sub(r"[^A-Za-z0-9]", "-", HOME) + "-"
    clip80 = lambda s: clip(s, 80).strip()
    h8 = lambda s: hashlib.sha1(re.sub(r"\s+", " ", s).encode()).hexdigest()[:8]
    votes, sess_acct, req_rows, sess_rows, wake_rows, ev_rows = collections.defaultdict(collections.Counter), {}, [], [], [], []
    for f in transcripts():
        sid = os.path.basename(f)[:8]
        proj = os.path.basename(os.path.dirname(f)).replace(home_enc, "")
        st = dict(owner="", name="", names=[], first="", entry="", coord=False, turn=0, trig="start", flag="first",
                  owners=[], tl=[], edit="")
        calls, bgids, seen, best, rows, wakes, evs = {}, {}, set(), {}, [], [], []

        def wake(o, trig, cls, txt, hashed=None):
            st["turn"] += 1
            st["trig"] = trig
            ts = (o.get("timestamp") or "")[:19]
            if not out_of(ts):
                wakes.append([sid, st["turn"], ts, trig, cls, len(txt), h8(hashed if hashed is not None else txt), clip80(txt)])

        for _, o in lines(f):
            if not isinstance(o, dict):
                continue
            t, ts = o.get("type"), (o.get("timestamp") or "")[:19]
            if t == "session-owner":
                st["owner"] = o.get("accountUuid") or st["owner"]
                if st["owner"] and st["owner"] not in st["owners"][-1:]:
                    st["owners"].append(st["owner"])
                continue
            if t in ("agent-name", "custom-title"):
                n = o.get("agentName") or o.get("customTitle") or ""
                st["name"] = n or st["name"]
                if n and n not in st["names"]:
                    st["names"].append(n)
                continue
            if o.get("isSidechain"):
                continue
            st["entry"] = st["entry"] or o.get("entrypoint") or ""
            m = o.get("message") or {}
            c = m.get("content")
            inwin = not out_of(ts)
            if t == "system":
                sub = o.get("subtype")
                if sub == "compact_boundary":
                    cm = o.get("compactMetadata") or {}
                    if inwin:
                        evs.append([sid, ts, "compact", str(cm.get("trigger") or ""), "", "", cm.get("preTokens") or "", "", "", ""])
                    st["flag"] = "postcompact"
                elif sub == "scheduled_task_fire":
                    wake(o, "cron", "cron", str(o.get("content") or ""))
            elif t == "user":
                blocks = [b for b in c if isinstance(b, dict)] if isinstance(c, list) else []
                results = [b for b in blocks if b.get("type") == "tool_result"]
                txt = c if isinstance(c, str) else " ".join(b.get("text", "") for b in blocks if b.get("type") == "text")
                for b in results:
                    call = calls.pop(b.get("tool_use_id"), None)
                    if not call:
                        continue
                    rc = b.get("content")
                    rt = rc if isinstance(rc, str) else " ".join(x.get("text", "") for x in rc or [] if isinstance(x, dict))
                    dur = ep(ts) - ep(call["ts"]) if ts and call["ts"] else ""
                    err = int(bool(b.get("is_error")))
                    mm = re.search(r"with ID: (\w+)", rt) if call["bg"] else None
                    if mm:
                        bgids[mm.group(1)] = call
                    for typ, cls in call["tags"] if not out_of(call["ts"]) else []:
                        if not (mm and typ == "test"):   # a background test is logged when its notice comes
                            evs.append([sid, call["ts"], typ, cls, dur, err, len(rt), int(call["bg"]), call["cmd"],
                                        call["what"] if typ == "test" else ""])
                    rl = RATE.search(rt)
                    if rl and inwin and (call["gh"] or re.search(r"github|GraphQL", rt)):
                        evs.append([sid, ts, "ratelimit", call["gh"] or "-", dur, err, len(rt), int(call["bg"]), call["cmd"],
                                    clip80(rt[max(0, rl.start() - 40): rl.start() + 60])])
                if results or o.get("toolUseResult") or not txt.strip():
                    continue
                ok = (o.get("origin") or {}).get("kind") if isinstance(o.get("origin"), dict) else ""
                if o.get("isCompactSummary") or txt.startswith(("This session is being continued from a previous conversation",
                                                                 "Base directory for this skill:")):
                    continue
                if ok == "task-notification" or "<task-notification>" in txt:
                    tid = (re.search(r"<task-id>(\w+)</task-id>", txt) or [None, ""])[1]
                    summ = (re.search(r"<summary>([\s\S]*?)</summary>", txt) or [None, ""])[1]
                    status = (re.search(r"<status>(\w+)</status>", txt) or [None, ""])[1]
                    call, cls = bgids.pop(tid, None), "other"
                    if call:
                        cls = next((c2 for t2, c2 in call["tags"] if t2 == "test"), None)
                        cls = "test:" + cls if cls else ("watch" if "--watch" in call["cmd"] and "status" in call["full"] else
                                                          "gh-wait" if call["gh"] else "sleep" if re.search(r"\bsleep\b", call["full"]) else "other")
                        for typ, c2 in call["tags"] if not out_of(call["ts"]) else []:
                            if typ == "test":
                                evs.append([sid, call["ts"], "test", c2, ep(ts) - ep(call["ts"]) if ts and call["ts"] else "",
                                            int(status not in ("completed", "")), len(txt), 1, call["cmd"], call["what"]])
                    elif "agent" in summ.lower() or tid.startswith("a") and len(tid) > 12:
                        cls = "subagent"
                    wake(o, "bgtask", cls, summ or txt, summ or txt)
                elif ok == "peer" or "cross-session-message" in txt:
                    frm = (re.search(r'from-name="([^"]*)"', txt) or [None, ""])[1]
                    body = re.sub(r"^[\s\S]*?<cross-session-message[^>]*>", "", txt)
                    wake(o, "xmsg", "from:" + ("coordinator" if "coordinator" in frm else "worker" if frm else "?"), body, body)
                elif "<bash-input>" in txt:
                    wake(o, "human", "ran", txt)
                elif txt.startswith("<") or o.get("isMeta"):
                    if o.get("promptSource") == "system" and not txt.startswith("<"):
                        wake(o, "system", "meta-prompt", txt)   # a respawn's "Continue …" and the like
                    elif re.match(r"<command-(name|message)>", txt):
                        wake(o, "human", "slash", txt)
                elif not st["first"]:
                    st["first"] = txt
                    wake(o, "start", "brief", txt)
                else:
                    wake(o, "human", "pane" if txt.startswith(("Coordinator pane", "Approval pane")) else "typed", txt)
            elif t == "assistant":
                for b in c if isinstance(c, list) else []:
                    if not isinstance(b, dict) or b.get("type") != "tool_use":
                        continue
                    nm, inp = b.get("name", ""), b.get("input") or {}
                    if nm in ("Edit", "Write", "NotebookEdit") and not st["edit"]:
                        st["edit"] = ts
                    if nm == "mcp__session-orchestration__open_pane":
                        st["coord"] = True
                    if nm != "Bash":
                        continue
                    cmd = str(inp.get("command", ""))
                    if STATUS_CMD.search(cmd) and re.search(r"\s--(start|changes|watch|owner)\b", cmd):
                        st["coord"] = True
                    tags = [("test", k) for k, rx in TEST_RX if rx.search(cmd)][:1]
                    what = ""
                    if tags and tags[0][1] == "shell-suite":
                        what = ",".join(suite_runs(cmd))
                        tags = tags if what else []
                    ghs = [f"gh {g.group(1)} {g.group(2) or ''}".strip() for g in GH.finditer(cmd)]
                    tags += [("gh", x) for x in ghs]
                    gh = ghs[0] if ghs else ""
                    if HANDOVER.search(cmd):
                        tags.append(("handover", "escalate" if "--escalate" in cmd else "handover"))
                    calls[b.get("id")] = dict(ts=ts, bg=bool(inp.get("run_in_background")), tags=tags, gh=gh, cmd=clip80(cmd),
                                              full=cmd[:2000], what=what)
                mdl, rid, u = m.get("model"), o.get("requestId") or m.get("id"), m.get("usage") or {}
                if mdl == "<synthetic>" or not rid or not u:
                    continue
                if u.get("output_tokens", 0) >= best.get(rid, {}).get("output_tokens", -1):
                    best[rid] = u   # a request's lines repeat its usage as it streams: the most output is the final one
                if rid in seen:
                    continue
                seen.add(rid)
                if inwin:
                    rows.append(dict(rid=rid, ts=ts, owner=st["owner"], model=mdl or "", effort=o.get("effort") or "",
                                     turn=st["turn"], trig=st["trig"], flag=st["flag"]))
                st["flag"] = ""
                st["tl"].append((ts, st["owner"]))
        if not rows:
            continue
        held = holds.get(os.path.dirname(os.path.dirname(f)), set()) if len(holds.get(os.path.dirname(os.path.dirname(f)), ())) == 1 else set()
        j = jobs.get(sid, {})
        voted = held | (set(j) if len(j) == 1 else set())
        if len(voted) == 1:
            sess_acct[sid] = next(iter(voted))
            for ow in st["owners"]:   # shortcut: a session that moved accounts votes every owner; the majority decides
                votes[ow][sess_acct[sid]] += 1
        prev = None
        for r in rows:
            u = best[r["rid"]]
            gap = ep(r["ts"]) - ep(prev) if prev and r["ts"] else ""
            prev = r["ts"] or prev
            req_rows.append([sid, 0, r["ts"], r["owner"], r["model"], r["effort"], *req_tokens(u)[:3],
                             u.get("cache_creation_input_tokens", 0), (u.get("cache_creation") or {}).get("ephemeral_5m_input_tokens", 0),
                             ctx_of(u), round(req_usd(u, r["model"]), 5), r["turn"], r["trig"], gap, r["flag"]])
        tl_ts = [x[0] for x in st["tl"]]
        for sf in sorted(glob.glob(f"{f[:-6]}/subagents/*.jsonl")):
            reqs = {}
            for _, o in lines(sf):
                if not isinstance(o, dict) or o.get("type") != "assistant":
                    continue
                m = o.get("message") or {}
                rid, u = o.get("requestId") or m.get("id"), m.get("usage") or {}
                if m.get("model") == "<synthetic>" or not rid or not u:
                    continue
                r = reqs.setdefault(rid, dict(ts=(o.get("timestamp") or "")[:19], u=u, model=m.get("model") or "", effort=o.get("effort") or ""))
                if u.get("output_tokens", 0) >= r["u"].get("output_tokens", 0):
                    r["u"] = u
            prev = None
            for r in reqs.values():
                ts, u = r["ts"], r["u"]
                if out_of(ts):
                    continue
                k = bisect.bisect_right(tl_ts, ts) - 1
                owner = st["tl"][max(k, 0)][1] if st["tl"] else st["owner"]
                gap = ep(ts) - ep(prev) if prev and ts else ""
                prev = ts or prev
                req_rows.append([sid, 1, ts, owner, r["model"], r["effort"], *req_tokens(u)[:3], u.get("cache_creation_input_tokens", 0),
                                 (u.get("cache_creation") or {}).get("ephemeral_5m_input_tokens", 0), ctx_of(u),
                                 round(req_usd(u, r["model"]), 5), 0, "subagent", gap, ""])
        first = st["first"]
        mark = lambda rx: (re.search(rx, first, re.M) or [None, ""])[1]
        rs = mark(r"^Session task: retro run, scope ([a-z]+)")
        task_ = rs and "retro-" + rs or mark(r"^Session task: ([\w./-]*\w)") or mark(r"^Work on ([A-Za-z][\w]*-\d+)\b")
        jm = next((v[0] for v in j.values() if v[0]), "")
        je = next((v[1] for v in j.values() if v[1]), "")
        tss = [r["ts"] for r in rows if r["ts"]]
        sess_rows.append([proj, sid, st["name"], kind_of(first, st["name"], st["coord"]), task_, st["entry"], mark(SUP.pattern),
                          "+".join(sorted(j)), jm, je, min(tss, default=""), max(tss, default=""),
                          "+".join(x[:8] for x in st["owners"]), "|".join(st["names"])[:120], st["edit"]])
        wake_rows += wakes
        ev_rows += evs
    own = {ow: c.most_common(1)[0][0] for ow, c in votes.items()}
    for r in req_rows:
        r[3] = own.get(r[3]) or sess_acct.get(r[0]) or "?"
    for name, head, rows in (
            ("req", "sid sub ts acct model effort inp out cr cw cw5 ctx usd turn trig gap_s flag", req_rows),
            ("sess", "project sid name kind task entry sup job_accts job_model job_effort ts0 ts1 owners names first_edit", sess_rows),
            ("wakes", "sid turn ts trig class chars hash snippet", wake_rows),
            ("ev", "sid ts type class dur_s err chars bg detail what", ev_rows)):
        with open(os.path.join(d, f"spend-{name}.tsv"), "w") as out:
            out.write("\t".join(head.split()) + "\n")
            for r in rows:
                out.write("\t".join(str(x).replace("\t", " ").replace("\n", " ") for x in r) + "\n")


def spend(*a):
    """Where the window's spend went (Markdown): by account, project, session, kind, model, trigger and context size,
    then rebuilds of big contexts, wakes, test runs, gh calls and handovers. Writes DIR/spend-*.tsv first."""
    if len(a) not in (1, 2):
        sys.exit("usage: retro.py spend [days=7] DIR")
    days, d = a if len(a) == 2 else (7, a[0])
    if not re.fullmatch(r"[\d.]+", str(days)):   # DIR [days] too
        days, d = d, days
    window(days)
    os.makedirs(d, exist_ok=True)
    spend_extract(d)
    days = float(days)
    sess = {s["sid"]: s for s in tsv(d, "spend-sess.tsv")}
    home_enc = re.sub(r"[^A-Za-z0-9]", "-", HOME) + "-"
    proj = lambda folder: re.sub(r"--(claude-)?worktrees-.*", "", folder.replace(home_enc, "")) or "?"
    req = tsv(d, "spend-req.tsv")
    for r in req:
        for k in ("inp", "out", "cr", "cw", "cw5", "ctx", "turn"):
            r[k] = int(r[k] or 0)
        r["usd"], r["sub"] = float(r["usd"]), r["sub"] == "1"
        s = sess.get(r["sid"], {})
        r["proj"], r["kind"] = proj(s.get("project", "?")), "subagent" if r["sub"] else s.get("kind", "?")
        r["gap"] = int(r["gap_s"]) if r["gap_s"] else None
        m = r["model"]
        # $ by token type; a 5-minute cache write costs 0.625 of a 1-hour one; the rest is advisor calls
        r["$in"], r["$out"], r["$cr"] = usd(r["inp"], 0, 0, 0, m), usd(0, r["out"], 0, 0, m), usd(0, 0, r["cr"], 0, m)
        r["$cw1"], r["$cw5"] = usd(0, 0, 0, r["cw"] - r["cw5"], m), usd(0, 0, 0, r["cw5"] * 0.625, m)
        r["$rest"] = r["usd"] - r["$in"] - r["$out"] - r["$cr"] - r["$cw1"] - r["$cw5"]
    main = [r for r in req if not r["sub"]]
    TOTAL = sum(r["usd"] for r in req) or 1
    accts = sorted({r["acct"] for r in req})
    out = []
    say = out.append
    fmt = lambda c: (f"{c:,.2f}" if abs(c) < 100 else f"{c:,.0f}") if isinstance(c, float) else f"{c:,}" if isinstance(c, int) else str(c)
    pct = lambda a, b: f"{100 * a / b:.0f}%" if b else "-"
    Mt = lambda n: round(n / 1e6, 1)
    BY = ["requests", "$", "% of $", "avg ctx", "$ per request"]
    model = lambda r: r["model"].replace("claude-", "")
    skind = lambda sid: sess.get(sid, {}).get("kind", "?")
    sname = lambda sid: sess.get(sid, {}).get("name", "?")

    def table(title, head, rows, note=""):
        say(f"\n## {title}\n")
        if note:
            say(note + "\n")
        say("| " + " | ".join(head) + " |")
        say("|" + "---|" * len(head))
        for row in rows:
            say("| " + " | ".join(fmt(c) for c in row) + " |")

    def by(rows, key, top=None):
        """(key, requests, $, share %, average ctx, $ per request), biggest $ first."""
        g = collections.defaultdict(lambda: [0, 0.0, 0])
        for r in rows:
            v = g[key(r)]
            v[0] += 1; v[1] += r["usd"]; v[2] += r["ctx"]
        t = sorted(([k, n, u, 100 * u / TOTAL, c // n, u / n] for k, (n, u, c) in g.items()), key=lambda x: -x[2])
        return t[:top] if top else t

    say(f"# Spend, {CUT_ISO} → {END_ISO[:16]} (UTC)\n")
    say(f"{len(req):,} requests, ${sum(r['usd'] for r in req):,.0f}, {len({r['sid'] for r in req})} sessions. $ is the list price "
        "of the tokens (retro.py's rates), a proxy for the plan limit, whose formula isn't visible.")
    wins = [("all accounts", None)] + [(a_, a_) for a_ in accts]
    rows = []
    for name, acct in wins:
        w = [r for r in req if acct is None or r["acct"] == acct]
        u = sum(r["usd"] for r in w)
        rows.append([name, len(w), len({r["sid"] for r in w}), Mt(sum(r["inp"] for r in w)), Mt(sum(r["out"] for r in w)),
                     Mt(sum(r["cr"] for r in w)), Mt(sum(r["cw"] for r in w)), u, u / days])
    table("Accounts", ["account", "requests", "sessions", "in Mtok", "out Mtok", "cache read Mtok", "cache write Mtok", "$", "$ per day"], rows)
    for name, acct in wins:
        table(f"Projects: {name}", ["project"] + BY, by([r for r in req if acct is None or r["acct"] == acct], lambda r: r["proj"], 10))
    dd = collections.defaultdict(lambda: [collections.Counter(), 0, set(), 0])
    for r in req:
        v = dd[r["ts"][:10]]
        v[0][r["acct"]] += r["usd"]; v[1] += 1; v[2].add(r["sid"]); v[3] += r["flag"] == "first" and not r["sub"]
    table("$ per day and account (UTC days)", ["day", *accts, "all", "requests", "$ per request", "sessions active", "sessions started"],
          [[k, *[c[a_] for a_ in accts], sum(c.values()), n, sum(c.values()) / n, len(ss), st_] for k, (c, n, ss, st_) in sorted(dd.items())])

    def top_sessions(title, rows, n=15):
        g = collections.defaultdict(list)
        for r in rows:
            g[r["sid"]].append(r)
        t = []
        for sid, rs in sorted(g.items(), key=lambda kv: -sum(r["usd"] for r in kv[1]))[:n]:
            mn = [r for r in rs if not r["sub"]]
            me = collections.Counter((model(r), r["effort"]) for r in mn or rs).most_common(1)[0][0]
            t.append([rs[0]["proj"], sid, sname(sid), skind(sid), rs[0]["acct"], " ".join(me), len(rs),
                      sum(r["ctx"] for r in mn) // max(len(mn), 1), sum(r["usd"] for r in rs), sum(r["usd"] for r in rs if r["sub"])])
        table(title, ["project", "sid", "name", "kind", "account", "model effort", "requests", "avg ctx (main)", "$", "of it subagents $"], t)

    top_sessions("Top 15 sessions", req)
    for a_ in accts if len(accts) > 1 else []:
        top_sessions(f"Top 10 sessions: {a_}", [r for r in req if r["acct"] == a_], 10)
    nsess = collections.Counter(skind(s) for s in {r["sid"] for r in main})
    table("Session kind (subagents as their own row)", ["kind", "sessions"] + BY, [[k, nsess.get(k, "-"), *v] for k, *v in by(req, lambda r: r["kind"])])
    table("Model × effort", ["model", "effort", "thread"] + BY,
          [[*k, *v] for k, *v in by(req, lambda r: (model(r), r["effort"] or "-", "sub" if r["sub"] else "main"), 20)])
    ty = [("input", "$in", "inp"), ("output", "$out", "out"), ("cache read", "$cr", "cr"), ("cache write 1h", "$cw1", None),
          ("cache write 5m", "$cw5", "cw5"), ("advisor", "$rest", None)]
    tok = lambda k, f: sum(r[f] for r in req) if f else sum(r["cw"] - r["cw5"] for r in req) if k == "$cw1" else 0
    nm = max(len(main), 1)
    table("$ by token type", ["type", "Mtok", "$", "% of $", "main $", "subagents $"],
          [[n, Mt(tok(k, f)), sum(r[k] for r in req), 100 * sum(r[k] for r in req) / TOTAL, sum(r[k] for r in main),
            sum(r[k] for r in req if r["sub"])] for n, k, f in ty],
          f"Main thread: average context {sum(r['ctx'] for r in main) // nm:,}, median {int(med([r['ctx'] for r in main])):,}; "
          f"average cache read per request {sum(r['cr'] for r in main) // nm:,} tokens (${sum(r['$cr'] for r in main) / nm:.3f}), "
          f"average output {sum(r['out'] for r in main) // nm:,} tokens (${sum(r['$out'] for r in main) / nm:.3f}).")
    table("By trigger of the turn", ["trigger"] + BY, by(req, lambda r: r["trig"]))
    table("Main thread against subagents", ["thread", "model"] + BY, [[*k, *v] for k, *v in by(req, lambda r: ("sub" if r["sub"] else "main", model(r)))])
    ctxb = lambda r: "<50K" if r["ctx"] < 5e4 else "50-100K" if r["ctx"] < 1e5 else "100-150K" if r["ctx"] < 1.5e5 else "150K+"
    ORD = ["<50K", "50-100K", "100-150K", "150K+", "none", "< 5 min", "5-60 min", "> 60 min"]
    table("Main-thread requests by context size", ["context"] + BY, sorted(by(main, ctxb), key=lambda x: ORD.index(x[0])))
    coord = [r for r in main if r["kind"] == "coordinator"]
    table("Coordinator sessions by model and effort", ["model", "effort"] + BY, [[*k, *v] for k, *v in by(coord, lambda r: (model(r), r["effort"]))])
    table("Coordinator sessions by day", ["day"] + BY, sorted(by(coord, lambda r: r["ts"][:10]), key=lambda x: x[0]))
    base = int(med([r["ctx"] for r in main if r["flag"] == "first"]))   # what a session reads before any work
    re_read = sum(usd(0, 0, min(base, r["cr"]), 0, r["model"]) for r in main)
    say(f"\nBase context (median at the first request of the sessions started in the window): {base:,} tokens. Re-reading it on "
        f"every main-thread request costs ${re_read:,.0f} ({pct(re_read, TOTAL)} of the window's $); each 1K off it saves "
        f"${sum(usd(0, 0, 1000, 0, r['model']) for r in main):,.0f} a window.")

    # rebuilds: a request that writes at least half of a context of 100K+ to the cache again
    extra = lambda r: r["$cw1"] + r["$cw5"] - usd(0, 0, r["cw"], 0, r["model"])   # the write, less what a cache read would have cost
    gapb = lambda r: "none" if r["gap"] is None else "< 5 min" if r["gap"] < 300 else "5-60 min" if r["gap"] < 3600 else "> 60 min"
    big = [r for r in req if r["cw"] >= r["ctx"] / 2 and r["ctx"] >= 100_000 and not r["flag"]]
    X = sum(extra(r) for r in big)

    def wrows(rows, key, top=None):
        g = collections.defaultdict(lambda: [0, 0, 0.0, 0.0])
        for r in rows:
            v = g[key(r)]
            v[0] += 1; v[1] += r["cw"]; v[2] += r["usd"]; v[3] += extra(r)
        t = sorted(([k, n, Mt(cw), u, x] for k, (n, cw, u, x) in g.items()), key=lambda x: -x[4])
        return t[:top] if top else t

    W1 = ["rebuilds", "cache write Mtok", "$ of these requests", "extra $ over a cache read"]
    say("\n# Rebuilds of big contexts\n")
    say(f"A rebuild: a request that writes at least half of a context of 100K+ to the cache again (not the first, not after a "
        f"compaction). {len(big)} rebuilds in {len({r['sid'] for r in big})} sessions, extra ${X:,.0f} ({pct(X, TOTAL)} of the "
        f"window's $); 5-minute writes are {pct(sum(r['cw5'] for r in big), sum(r['cw'] for r in big))} of their cache-write "
        f"tokens; subagents' rebuilds: {sum(r['sub'] for r in big)}.")
    table("Rebuilds by idle gap before the request", ["gap"] + W1, sorted(wrows(big, gapb), key=lambda x: ORD.index(x[0])))
    table("Rebuilds by trigger", ["trigger"] + W1, wrows(big, lambda r: r["trig"]))
    table("Rebuilds by account", ["account"] + W1, wrows(big, lambda r: r["acct"]))
    table("Rebuilds by session kind", ["kind"] + W1, wrows(big, lambda r: r["kind"]))
    table("Rebuilds by project", ["project"] + W1, wrows(big, lambda r: r["proj"], 8))
    table("Rebuilds: top sessions", ["sid", "name", "kind"] + W1, [[k, sname(k), skind(k), *v] for k, *v in wrows(big, lambda r: r["sid"], 12)])
    allw = collections.defaultdict(lambda: [0, 0, 0, 0.0])
    for r in main:
        if not r["flag"]:
            v = allw[gapb(r)]
            v[0] += 1; v[1] += r["cw"]; v[2] += r["ctx"]; v[3] += extra(r)
    table("All main-thread requests by idle gap (any context size)", ["gap", "requests", "cache write Mtok", "share of context rewritten", "extra $ over a cache read"],
          [[k, n, Mt(cw), pct(cw, cx), x] for k, (n, cw, cx, x) in sorted(allw.items(), key=lambda x: ORD.index(x[0]))],
          "Extra $ here counts every cache write, the ordinary growth of a turn too: the '> 60 min' row is the price of an expired cache.")
    moved = [s for s in sess.values() if s["sup"] in sess and sess[s["sup"]]["owners"] != s["owners"]]
    say(f"\nAccount moves (a successor under another owner than the session it supersedes): {len(moved)}"
        + (": " + ", ".join(f"{s['sid']} ({s['kind']})" for s in moved[:12]) if moved else "") + ".")

    say("\n# Wakes\n")
    rq = collections.defaultdict(list)
    for r in main:
        rq[r["sid"], r["turn"]].append(r)

    def wname(w):
        if (w["trig"], w["class"]) != ("bgtask", "other"):
            return w["class"]
        m = re.match(r'Background command "(\S+)', w["snippet"])
        word = (m.group(1) if m else w["snippet"].split(":")[0][:22]).lower()
        return "other:" + {"arm": "re-arm", "wait": "wait", "watch": "watch", "run": "run", "re-arm": "re-arm", "gh": "gh"}.get(word, "rest" if m else word)

    wakes = sorted(tsv(d, "spend-wakes.tsv"), key=lambda w: (w["sid"], w["ts"]))
    seen, G = set(), collections.defaultdict(lambda: {"n": 0, "reqs": 0, "usd": 0.0, "ctx": [], "noop": 0, "noop$": 0.0, "dup": 0, "dup$": 0.0, "none": 0})
    for w in wakes:
        rs = rq.get((w["sid"], int(w["turn"])), [])
        g, u = G[w["trig"], wname(w)], sum(r["usd"] for r in rs)
        w["usd"], w["noop"] = u, bool(rs) and len(rs) <= 2 and sum(r["out"] for r in rs) < 300
        g["n"] += 1; g["reqs"] += len(rs); g["usd"] += u
        if not rs:
            g["none"] += 1
        else:
            g["ctx"].append(rs[0]["ctx"])
            if w["noop"]:
                g["noop"] += 1; g["noop$"] += u
        if (w["sid"], w["hash"]) in seen:
            g["dup"] += 1; g["dup$"] += u
        seen.add((w["sid"], w["hash"]))
    tot = {k: sum(g[k] for g in G.values()) for k in ("n", "reqs", "usd", "noop", "noop$", "dup", "dup$", "none")}
    say(f"{tot['n']:,} wakes, {tot['reqs']:,} main-thread requests joined (${tot['usd']:,.0f}); {tot['none']} wakes with no request. "
        f"No-op wakes (at most 2 requests, under 300 output tokens): {tot['noop']:,}, ${tot['noop$']:,.0f}. "
        f"Duplicates (the same text woke the session before): {tot['dup']:,}, ${tot['dup$']:,.0f}.")
    table("Wakes by trigger and class", ["trigger", "class", "wakes", "requests", "requests per wake", "$", "$ per wake", "median ctx at first request",
                                         "no-op", "no-op $", "duplicate", "duplicate $"],
          [[t, c, g["n"], g["reqs"], g["reqs"] / g["n"], g["usd"], g["usd"] / g["n"], int(med(g["ctx"])), g["noop"], g["noop$"], g["dup"], g["dup$"]]
           for (t, c), g in sorted(G.items(), key=lambda kv: -kv[1]["usd"])])
    wk = collections.defaultdict(lambda: [0, 0.0, 0, 0.0])
    for w in wakes:
        v = wk[skind(w["sid"]), w["trig"]]
        v[0] += 1; v[1] += w["usd"]; v[2] += w["noop"]; v[3] += w["usd"] * w["noop"]
    table("Wakes by session kind and trigger", ["kind", "trigger", "wakes", "$", "no-op", "no-op $"],
          [[*k, *v] for k, v in sorted(wk.items(), key=lambda kv: -kv[1][1])][:14])
    op = collections.defaultdict(lambda: [0, 0.0, 0])
    for w in wakes:   # what the machine-written wakes say, digits and ids folded (a typed prompt's text stays out)
        if w["trig"] in ("system", "bgtask", "cron"):
            v = op[w["trig"], re.sub(r"[0-9a-f]{7,}|\d+", "#", w["snippet"])[:46]]
            v[0] += 1; v[1] += w["usd"]; v[2] += w["noop"]
    table("Machine-written wakes by their opening (top 40 by $)", ["trigger", "opening", "wakes", "$", "no-op"],
          [[*k, *v] for k, v in sorted(op.items(), key=lambda kv: -kv[1][1])][:40])

    say("\n# Test runs\n")
    ev = tsv(d, "spend-ev.tsv")
    tests = sorted((e for e in ev if e["type"] == "test"), key=lambda e: e["ts"])
    CAP = 3600   # shortcut: a run's length is capped at an hour for the overlap count (the longest span the Mac's sleep)
    for e in tests:
        e["d"] = int(e["dur_s"] or 0)
        e["t0"] = ep(e["ts"]); e["t1"] = e["t0"] + min(e["d"], CAP)
    for i, e in enumerate(tests):   # overlapped: another session's run was going at some point of this one
        e["ov"] = any(o["sid"] != e["sid"] and o["t0"] < e["t1"] and o["t1"] > e["t0"] for o in tests[max(0, i - 80):i + 80] if o is not e)
    peak = cur = 0
    for _, step in sorted([(e["t0"], 1) for e in tests if e["d"]] + [(e["t1"], -1) for e in tests if e["d"]]):
        cur += step
        peak = max(peak, cur)
    say(f"{len(tests):,} test runs, {sum(e['d'] for e in tests) / 60:,.0f} minutes, {sum(e['err'] == '1' for e in tests)} failed; "
        f"{sum(e['ov'] for e in tests)} overlapped another session's run; peak {peak} at once.")
    TH = ["runs", "minutes", "median s", "failed", "in background", "overlapped"]
    trow = lambda k, es: [k, len(es), sum(e["d"] for e in es) / 60, int(med([e["d"] for e in es])), sum(e["err"] == "1" for e in es),
                          sum(e["bg"] == "1" for e in es), sum(e["ov"] for e in es)]
    grp = lambda key, es: {k: [e for e in es if key(e) == k] for k in {key(e) for e in es}}
    table("Test runs by class", ["class"] + TH, sorted((trow(k, es) for k, es in grp(lambda e: e["class"], tests).items()), key=lambda x: -x[2]))
    sg = grp(lambda e: e["what"], [e for e in tests if e["class"] == "shell-suite"])
    table("Shell suites by run", ["suite:sections"] + TH, sorted((trow(k, es) for k, es in sg.items()), key=lambda x: -x[2])[:14])
    fulls = [k for k in sg if k.endswith(":full")]
    if fulls:
        name = max(fulls, key=lambda k: sum(e["d"] for e in sg[k]))   # the full suite that took the most minutes
        full = sg[name]
        real = [e for e in full if e["d"] >= 60]
        say(f"\nFull `{name[:-5]}` runs: {len(full)}; of them {len(real)} ran a minute or more ({sum(e['d'] for e in real) / 60:,.0f} minutes). "
            f"Median seconds alone {int(med([e['d'] for e in real if not e['ov']]))} (n={sum(not e['ov'] for e in real)}), "
            f"overlapped {int(med([e['d'] for e in real if e['ov']]))} (n={sum(e['ov'] for e in real)}).")
        fp = grp(lambda e: proj(sess.get(e["sid"], {}).get("project", "?")), full)
        table(f"Full {name[:-5]} runs by project", ["project", "runs", "minutes", "sessions"],
              [[p, len(es), sum(e["d"] for e in es) / 60, len({e["sid"] for e in es})] for p, es in sorted(fp.items(), key=lambda kv: -len(kv[1]))])
        table(f"Full {name[:-5]} runs by day", ["day", "runs", "minutes"],
              [[k, len(es), sum(e["d"] for e in es) / 60] for k, es in sorted(grp(lambda e: e["ts"][:10], full).items())])
        fs = grp(lambda e: e["sid"], full)
        table(f"Full {name[:-5]} runs: top sessions", ["sid", "name", "kind", "runs", "minutes", "failed"],
              [[k, sname(k), skind(k), len(es), sum(e["d"] for e in es) / 60, sum(e["err"] == "1" for e in es)]
               for k, es in sorted(fs.items(), key=lambda kv: -len(kv[1]))[:10]], f"{len(fs)} sessions ran it in full.")
    tw = [g for k, g in G.items() if k[1].startswith("test:")]
    say(f"\nWakes from a finished background test run: {sum(g['n'] for g in tw)}, ${sum(g['usd'] for g in tw):,.0f}.")

    say("\n# gh calls and rate limits\n")
    gh = [e for e in ev if e["type"] == "gh"]
    gc = grp(lambda e: e["class"], gh)
    table("gh calls by subcommand", ["call", "calls", "failed", "in background", "sessions"],
          [[k, len(es), sum(e["err"] == "1" for e in es), sum(e["bg"] == "1" for e in es), len({e["sid"] for e in es})]
           for k, es in sorted(gc.items(), key=lambda kv: -len(kv[1]))[:12]],
          f"{len(gh):,} gh calls in {len({e['sid'] for e in gh})} sessions, {sum(e['err'] == '1' for e in gh)} failed.")
    rl = [e for e in ev if e["type"] == "ratelimit"]
    say(f"\nRate-limit rows: {len(rl)}, real (the call failed): {sum(e['err'] == '1' for e in rl)}"
        + "".join(f"; {e['sid']} {e['ts'][:16]} {e['class']}" for e in sorted(rl, key=lambda e: e["ts"]) if e["err"] == "1") + ".")
    gs = collections.Counter(e["sid"] for e in gh)
    table("gh calls: top sessions", ["sid", "name", "kind", "calls", "pr view", "pr checks"],
          [[k, sname(k), skind(k), n, sum(e["sid"] == k and e["class"] == "gh pr view" for e in gh),
            sum(e["sid"] == k and e["class"] == "gh pr checks" for e in gh)] for k, n in gs.most_common(8)])
    gw = G.get(("bgtask", "gh-wait"))
    if gw:
        say(f"\ngh-wait wakes: {gw['n']}, {gw['reqs']} requests, ${gw['usd']:,.0f} (${gw['usd'] / gw['n']:.2f} each).")
    f = usage_faults(d)
    if f:
        say("\nusage.tsv fault rows: " + "; ".join(f"{u['kind']} {u['feature']} {u['uses']}" for u in f) + ".")

    say("\n# Handovers\n")
    ho = [e for e in ev if e["type"] == "handover"]
    ok = [e for e in ho if e["err"] != "1"]
    say(f"{len(ho)} handover calls ({sum(e['class'] == 'escalate' for e in ho)} escalations, {len(ho) - len(ok)} failed) in "
        f"{len({e['sid'] for e in ho})} sessions. Failed calls by kind: {dict(collections.Counter(skind(e['sid']) for e in ho if e['err'] == '1'))}.")
    hp = collections.Counter((skind(e["sid"]), proj(sess.get(e["sid"], {}).get("project", "?"))) for e in ho)
    table("Handover calls by session kind and project", ["kind", "project", "calls"], [[*k, n] for k, n in hp.most_common()])
    mreq = collections.defaultdict(list)
    for r in main:
        mreq[r["sid"]].append(r)
    last = []
    for e in ok:   # the context the predecessor had reached when it handed over
        before = [r["ctx"] for r in mreq[e["sid"]] if r["ts"] <= e["ts"]]
        if before:
            last.append((before[-1], e))
    hb = lambda c: "< 100K (premature)" if c < 1e5 else "100-140K" if c < 1.4e5 else "140-160K" if c < 1.6e5 else "160K+"
    hk = collections.defaultdict(collections.Counter)
    for c, e in last:
        hk[skind(e["sid"])][hb(c)] += 1
    cols = ["< 100K (premature)", "100-140K", "140-160K", "160K+"]
    table("Context at the handover call, by session kind", ["kind"] + cols + ["median ctx"],
          [[k, *[c[x] for x in cols], int(med([cx for cx, e in last if skind(e["sid"]) == k]))] for k, c in sorted(hk.items())],
          f"Median over all: {int(med([c for c, _ in last])):,}. Premature ones: "
          + ", ".join(f"{e['sid']} {c // 1000}K" for c, e in sorted(last, key=lambda x: x[0])[:14] if c < 1e5) + ".")
    pk = collections.defaultdict(list)
    succ = [s for s in sess.values() if s["sup"]]
    for s in succ:
        rs = mreq[s["sid"]]
        pre = [r for r in rs if r["ts"] < s["first_edit"]] if s["first_edit"] else rs[:10]
        if pre:
            pk[s["kind"] + (", edits" if s["first_edit"] else ", never edits")].append((len(pre), sum(r["usd"] for r in pre), pre[-1]["ctx"], pre[0]["ctx"]))
    picked = sum(p[1] for ps in pk.values() for p in ps)
    table("Successors (sessions that supersede another) and their pick-up cost",
          ["kind", "successors", "median requests before the first edit", "median $ to pick up", "sum $", "median first ctx", "median ctx at the first edit"],
          [[k, len(ps), int(med([p[0] for p in ps])), med([p[1] for p in ps]), sum(p[1] for p in ps), int(med([p[3] for p in ps])),
            int(med([p[2] for p in ps]))] for k, ps in sorted(pk.items())],
          f"{len(succ)} successors, pick-up ${picked:,.0f} in all ({pct(picked, TOTAL)} of the window's $). "
          "Pick-up: a successor's requests before its first Edit or Write (none: its first 10).")
    root = lambda sid, n=0: root(sess[sid]["sup"], n + 1) if n < 50 and sid in sess and sess[sid]["sup"] else sid
    chains = collections.defaultdict(list)
    for s in succ:
        chains[root(s["sid"])].append(s["sid"])
    cl = sorted(((len(v) + 1, k) for k, v in chains.items()), reverse=True)
    say(f"\nChains through Supersedes: {len(cl)}; with 3+ sessions: {sum(n >= 3 for n, _ in cl)}; longest: "
        + ", ".join(f"{sname(k) if k in sess else sname(chains[k][0])} ({n})" for n, k in cl[:8]) + ".")
    table("Chain length", ["sessions in the chain", "chains"], sorted(collections.Counter(n for n, _ in cl).items()))

    st = [r for r in tsv(d, "start.tsv") if r.get("started", "").startswith("20")]   # the file ends with its own median row
    if st:
        num = lambda r, k: int(r[k] or 0)
        sc = [sum(r["usd"] for r in mreq[s["session"]][:num(s, "reqs")]) for s in st]
        busy = [r for r in st if num(r, "after_start") > 75_000]
        say(f"\nCoordinator Starts: {len(st)}, ${sum(sc):,.0f} for their Start requests (median ${med(sc):.2f}). After Start over 75K: "
            f"{len(busy)}; at or under 65K: {sum(num(r, 'after_start') <= 65_000 for r in st)}.")
        K = ("reqs", "base", "after_start", "increment", "skill", "status", "rest")
        table("Coordinator Starts by day (start.tsv)", ["day", "starts", *[f"median {k}" for k in K]],
              [[k, len(rs), *[int(med([num(r, x) for r in rs])) for x in K]] for k, rs in sorted(grp(lambda r: r["started"][:10], st).items())]
              + [["all", len(st), *[int(med([num(r, x) for r in st])) for x in K]]])
    else:
        say("\nCoordinator Starts: no start.tsv in DIR (the protocol section's `start 7 > start.tsv` writes it first).")
    print("\n".join(out))


# Report sections in order, and the scopes that have each (skills/retro/SKILL.md, Sections).
BOTH, PROJ, PLUG = {"project", "plugin"}, {"project"}, {"plugin"}
SECTIONS = {"units": BOTH, "context": BOTH, "waste": BOTH, "spend": PLUG, "feedback": BOTH, "coordinator": PROJ, "memory": PROJ,
            "protocol": PLUG, "features": PLUG, "sizing": PLUG}


# Default section groups per scope (config retro.groups overrides a scope's): each group is one session's work.
GROUPS = {"project": {"units": ["units", "context", "coordinator"], "waste": ["waste"], "feedback": ["feedback", "memory"]},
          "plugin": {"units": ["units", "context"], "waste": ["waste"], "spend": ["spend"], "protocol": ["protocol"],
                     "features": ["features", "sizing"]}}


def lib(fn, warn=False):
    """Run a lib.sh shell snippet (with $1 = lib.sh) from the cwd, its stdout stripped; warn passes its stderr on."""
    import subprocess
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "lib.sh")
    return subprocess.run(["bash", "-c", '. "$1" && ' + fn, "_", path], stdout=subprocess.PIPE, stderr=None if warn else subprocess.DEVNULL,
                          text=True, timeout=30).stdout.strip()


def sections(*args):
    groups = "--groups" in args
    scope, *names = [a for a in args if a != "--groups"] or [""]
    if scope not in ("project", "plugin"):
        sys.exit("usage: retro.py sections [--groups] project|plugin [NAME…]")
    if scope == "plugin":   # plugin scope has one home, as lib.sh config retro.scope says
        pr = lib('pr=$(plugin_root) && [ "$pr" != "$(find_root)" ] && echo "$pr"')
        if pr:
            print(f"warning: plugin scope runs only from feedback.repo_dir's root ({pr}): project", file=sys.stderr)
            scope = "project"
    for n in names:
        if scope not in SECTIONS.get(n, set()):
            print(f"skipped: {n} (not a {scope} section)", file=sys.stderr)
    run = [n for n, scopes in SECTIONS.items() if scope in scopes and (not names or n in names)]
    if not groups:
        print("\n".join(run))
        return
    # The group plan: config retro.groups' groups for the scope (else GROUPS), each narrowed to the sections this run
    # writes, empty ones dropped; the sections no group lists are the writer's (plugin feedback by default), so none is lost.
    cfg = lib("config retro.groups", warn=True)   # a bad value's warning reaches the run
    plan = (json.loads(cfg) if cfg else {}).get(scope) or GROUPS[scope]
    seen = set()
    for g, secs in plan.items():
        secs = [n for n in secs if n in run and n not in seen]
        seen.update(secs)
        if secs:
            print(f"{g}: {' '.join(secs)}")
    rest = [n for n in run if n not in seen]
    if rest:
        print(f"writer: {' '.join(rest)}")

def writer(d="", *args):
    """A split run's writer: the groups' states, the no-data headings, and the feedback drafts, filed with --file."""
    import shlex, subprocess
    if not d or (args and args[0] != "--file") or not os.path.isfile(os.path.join(d, "run.json")):
        sys.exit("usage: retro.py writer DIR [--file [K…]]  (DIR: a split run's folder, with run.json)")
    run = json.load(open(os.path.join(d, "run.json")))
    drafts = []
    for g, v in (run.get("groups") or {}).items():
        st = os.path.join(d, "sections", g + ".status")
        md = os.path.join(d, "sections", g + ".md")
        state = open(st).read().strip().splitlines()[0] if os.path.isfile(st) and os.path.getsize(st) else ""
        sid = (v.get("id") or "no id")[:8]
        why = (state[len("failed:"):].strip() if state.startswith("failed")
               else "" if state.startswith("done") and os.path.isfile(md)
               else f"section session {v.get('name', g)} ({sid}) wrote no sections/{g}.md" if state.startswith("done")
               else f"section session {v.get('name', g)} ({sid}) ended without a result")
        print(f"{g}: {state or 'missing'}")
        for s in v.get("sections", []):
            if why:
                print(f"## {s.capitalize()}\nno data: {why}")
        if not why:
            for line in open(md):
                m = re.search(r"(?:^|[\s`/])feedback add (.+)", line)
                if m:
                    try:
                        a = shlex.split(m.group(1).strip().rstrip("`"))
                    except ValueError as e:
                        print(f"draft skipped ({g}): {e}: {clip(line.strip())}", file=sys.stderr)
                        continue
                    if a not in [x for _, x in drafts]:   # two sections drafting the same case file it once
                        drafts.append((g, a))
    for k, (g, a) in enumerate(drafts, 1):
        print(f"draft {k} ({g}): feedback add {shlex.join(a)}")
    if not args:
        return
    fb = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "orchestrating-sessions", "feedback")
    pick = [int(k) for k in args[1:]] or range(1, len(drafts) + 1)
    rc = 0
    for k in pick:
        if not 1 <= k <= len(drafts):
            sys.exit(f"no draft {k} (1–{len(drafts)})")
        p = subprocess.run([fb, "add", *drafts[k - 1][1]], stdout=subprocess.PIPE, text=True)
        if p.returncode == 0:
            print(f"filed {k} {p.stdout.strip()}")
            continue
        # exit 3: an open case is the same one (feedback add lists it first); it counts there, not as a new file
        m = re.search(r"^\s+(\S+\.md) — ", p.stdout, re.M) if p.returncode == 3 else None
        if m and subprocess.run([fb, "seen", m.group(1)]).returncode == 0:
            print(f"seen {k} {m.group(1)}")
        else:
            print(f"failed {k}: {clip(p.stdout.strip())}"); rc = 1
    sys.exit(rc)


CMDS = {"sessions": sessions, "events": events, "context": context, "units": units, "waits": waits, "bgtasks": bgtasks, "replies": replies,
        "triggers": triggers, "usage": usage, "chunks": chunks, "kinds": kinds, "trial": trial, "handoff": handoff, "start": start, "loads": loads, "search": search,
        "sections": sections, "writer": writer, "html": md2html, "waste": waste, "merges": merges, "spend": spend}

if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["--until"] and len(a) > 1:
        END = datetime.fromisoformat(a[1].rstrip("Z")).replace(tzinfo=timezone.utc).timestamp(); a = a[2:]
    if "--project" in a:
        i = a.index("--project")
        if i + 1 >= len(a):
            sys.exit("--project needs a ROOT path or a regex")
        PROJECT = project_filter(a[i + 1])
        if a[i + 1][:1] in "/~.":
            ROOT = os.path.expanduser(a[i + 1])
        a = a[:i] + a[i + 2:]
    if not a or a[0] not in CMDS:
        sys.exit(__doc__)
    CMDS[a[0]](*a[1:])

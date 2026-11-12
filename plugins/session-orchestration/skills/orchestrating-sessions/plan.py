"""session-status --plan: a design's plan table (session-status runs it with the PLAN_* environment; its
--plan block documents the modes)."""
import os, re, shlex, subprocess, sys
die = lambda msg: sys.exit(print(msg, file=sys.stderr) or 2)
usage = "usage: session-status --plan FILE [--check | --next | --brief N | --done N]"
a = sys.argv[1:]
if not a or a[1:2] not in ([], ["--check"], ["--next"], ["--brief"], ["--done"]) or \
        (len(a) == 3) != (a[1:2] in (["--brief"], ["--done"])) or len(a) > 3:
    die(usage)
if not os.path.isfile(a[0]): die(f"no file {a[0]}")
path = os.path.abspath(a[0]); mode = a[1] if len(a) > 1 else ""
d, key = os.path.dirname(path), os.path.basename(path).removesuffix(".md")
MODEL_EFFORT = r"[a-z][a-z0-9.-]*/(low|medium|high|xhigh|max)"
KINDS = dict(m.split("=", 1) for m in os.environ["PLAN_MODELS"].split())
MAXP, AT = max(1, int(os.environ["PLAN_MAXP"])), int(os.environ["PLAN_AT"])
okme = lambda me: bool(re.fullmatch(MODEL_EFFORT, me)) and "fable" not in me   # lib.sh model_ok: one rule
START = 60000   # ponytail: a constant session start; a later chunk calibrates it from rnd.py's measured base

lines, i = open(path).read().splitlines(), 0
while i < len(lines) and not re.match(r"## (Build )?[Pp]lan(\s|$)", lines[i]): i += 1
i += 1
while i < len(lines) and not lines[i].startswith(("|", "# ", "## ")): i += 1   # the table is in the plan's section
rows, bad = [], []
for ln in lines[i:]:
    if not ln.startswith("|"): break
    c = [x.strip().replace("\\|", "|") for x in re.split(r"(?<!\\)\|", ln.strip())[1:-1]]
    if not any(c): continue   # a lone `|` or empty cells
    if c[:1] == ["#"] or c and c[0] and set(c[0]) <= set("-: "): continue   # the header and the --- line
    (rows if len(c) == 8 else bad).append(c)
if not rows: die(f"no plan table in {path}")
R, dup = {}, []
nil = lambda s: s.lower() in ("", "-", "–", "—", "none")   # a Deps or Touches cell that names nothing
for n, title, kind, deps, touch, est, model, done in rows:
    ds = []
    if n in R: dup.append(n)
    for p in ([] if nil(deps) else re.split(r"\s*,\s*", deps)):
        m = re.fullmatch(r"c?(\d+)\s*[–-]\s*c?(\d+)", p)   # a range, 1–4
        p = p.removeprefix("c")
        ds += [str(x) for x in range(int(m[1]), int(m[2]) + 1)] if m else [p]
    ts = [] if nil(touch) or touch[:1] in "-–—" else re.findall(r"`([^`]+)`", touch) or re.split(r"\s*,\s*", touch)
    m = re.fullmatch(r"(\d+)\s*[Kk]", est)
    R[n] = dict(title=title, kind=kind, deps=ds, touch=ts, est=int(m[1]) * 1000 if m else None, raw_est=est, model=model, done=done)
state = {}
try:
    for m in re.finditer(r"^## c(\S+): (done|handoff)\b", open(os.path.join(d, f"{key}-build.md")).read(), re.M):
        state[m[1]] = "done" if "done" in (m[2], state.get(m[1])) else m[2]   # any done is done (--handover's rule)
except FileNotFoundError: pass
isdone = lambda n: state.get(n) == "done"
LIVE = set(os.environ["PLAN_LIVE"].splitlines())
if os.environ["PLAN_LFAIL"]: print("couldn't list an account's sessions: a running chunk may show as not running", file=sys.stderr)
running = lambda n: not isdone(n) and f"{key}-c{n}" in LIVE   # a live KEY-cN session; KEY-cN-prev-K isn't one

# Waves: 1 + the latest wave of a chunk's deps. A chunk on a cycle or with an unknown dep gets none.
wave, cycles = {}, []
def wv(n, path=()):
    if n in path: cycles.append(path[path.index(n):] + (n,)); return None
    if n not in R: return None
    if n not in wave:
        ws = [wv(x, path + (n,)) for x in R[n]["deps"]]
        wave[n] = None if None in ws else 1 + max(ws, default=0)
    return wave[n]
for n in R: wv(n)
W = sorted({w for w in wave.values() if w})
waves = " → ".join("{" + ",".join(n for n in R if wave[n] == w) + "}" for w in W)

def anc(n, seen=None):   # every chunk n waits for
    seen = set() if seen is None else seen
    for x in R.get(n, {}).get("deps", []):
        if x not in seen: seen.add(x); anc(x, seen)
    return seen
def base(t):   # the part before the first glob character, and whether there was one
    m = re.search(r"[*?\[]", t); return (t[:m.start()], True) if m else (t, False)
def overlap(x, y):
    (px, gx), (py, gy) = base(x), base(y)
    if gx or gy: return px.startswith(py) or py.startswith(px)
    return x == y or x.startswith(y.rstrip("/") + "/") or y.startswith(x.rstrip("/") + "/")

if mode == "--check":
    if os.environ["PLAN_W"] != os.environ["PLAN_WANT"]:   # info, not a problem (stderr: stdout is one line per problem)
        print(f"window {os.environ['PLAN_W']} from {os.environ['PLAN_WFROM']}; expected {os.environ['PLAN_WANT']}", file=sys.stderr)
    out, seen =[f"row {c[0]}: {len(c)} cells, not 8" for c in bad] + [f"c{n}: two rows" for n in dup], set()
    for n, r in R.items():
        out += [f"c{n}: unknown dep {x}" for x in r["deps"] if x not in R]
        if r["kind"] not in KINDS: out.append(f"c{n}: unknown kind {r['kind'] or '(none)'}")
        if not r["done"]: out.append(f"c{n}: no done-when")
        if r["model"] != "default" and not okme(r["model"]): out.append(f"c{n}: model/effort {r['model'] or '(none)'} is not like opus/medium (efforts: low medium high xhigh max; no fable)")
        if r["est"] is None: out.append(f"c{n}: est {r['raw_est'] or '(none)'} is not like 60K")
        elif AT > 0 and r["est"] > AT - START: out.append(f"c{n}: est {r['est'] // 1000}K over the {(AT - START) // 1000}K budget")
    for cy in cycles:
        k = frozenset(cy)
        if k not in seen: seen.add(k); out.append("cycle: " + " → ".join(f"c{x}" for x in cy))
    ns = list(R)
    for i, x in enumerate(ns):
        for y in ns[i + 1:]:
            if x not in anc(y) and y not in anc(x):   # neither waits for the other: they may run at once
                both = [f"{s} ~ {t}" if s != t else s for s in R[x]["touch"] for t in R[y]["touch"] if overlap(s, t)]
                if both: out.append(f"c{x} and c{y} both touch {', '.join(both)}")
    if out: sys.exit(print("\n".join(out)) or 1)
    sys.exit()

if mode == "--done":   # row N's kind, model/effort and est, and this session's act from rnd.py, as a usage chunk line
    n = a[2].removeprefix("c")
    if n not in R: die(f"no row {n} in {path}")
    r = R[n]; m, _, e = (KINDS.get(r["kind"], "") if r["model"] == "default" else r["model"]).partition("/")
    if r["est"] is None: sys.exit(print(f"nothing logged: c{n}'s est {r['raw_est'] or '(none)'} is not like 60K"))
    if os.environ["PLAN_TELEMETRY"] != "local":
        sys.exit(print(f"nothing logged: telemetry is {os.environ['PLAN_TELEMETRY']}, not local (config telemetry)"))
    act, sid = "", os.environ.get("CLAUDE_CODE_SESSION_ID", "")[:8]
    try:   # growth has one definition: rnd.py's; no session id, no act
        if not sid: raise ValueError
        out = subprocess.run([sys.executable, "-I", os.path.join(os.path.dirname(os.environ["PLAN_LIB"]), "skills/rnd/rnd.py"),
                              "chunks", "7", "--session", sid], capture_output=True, text=True, timeout=120).stdout.splitlines()
        act = out[1].split("\t")[out[0].split("\t").index("act_K")] if len(out) > 1 else ""
    except (OSError, ValueError, IndexError, subprocess.SubprocessError): pass
    log = os.environ["PLAN_LOG"]; size = os.path.getsize(log) if os.path.exists(log) else 0
    subprocess.run(["bash", "-c", '. "$0" && usage "$@"', os.environ["PLAN_LIB"], r["kind"], "chunk", m, e, str(r["est"] // 1000), act])
    new = open(log).read()[size:].strip() if os.path.exists(log) else ""
    print(new or f"nothing logged: usage refused or couldn't write kind {r['kind']}, model/effort {m}/{e}, est {r['est'] // 1000}, act {act or '-'}")
    sys.exit()

if mode == "--brief":
    n = a[2].removeprefix("c")
    if n not in R: die(f"no row {n} in {path}")
    r = R[n]; me = KINDS.get(r["kind"], "?") if r["model"] == "default" else r["model"]
    print(f"""# {key} c{n} · {r['title']}

Kind: {r['kind']} · Model: {me} · Est: {r['raw_est']} growth · Deps: {', '.join(r['deps']) or 'none'} · Wave {wave[n] or '?'}

**First:** read `{d}/{key}-chunk-rules.md` (paths, setup, interface, landing). N = {n}.

**Goal.** {r['title']}

**Read only:** (sections, as line ranges)

**Touches:** {', '.join(f'`{t}`' for t in r['touch']) or '–'}.

**Done when:** {r['done']}""")
    sys.exit()

print(f"waves: {waves or '(none)'}")
if mode == "--next" and os.environ["PLAN_ON"] == "false":
    print("plan.enabled is false: run tasks without a plan")
elif mode == "--next":
    run = [n for n in R if running(n)]
    cand = list(run)   # running chunks first: they hold slots and touches
    for n in R:   # runnable, in row order, skipping one whose touches overlap a chunk already picked
        if n not in run and not isdone(n) and wave[n] and all(isdone(x) for x in R[n]["deps"]) and \
           not any(overlap(s, t) for c in cand for s in R[c]["touch"] for t in R[n]["touch"]): cand.append(n)
    tops = [{t.split("/")[0] if "/" in t else "." for t in R[n]["touch"]} for n in cand]
    if any(tops[i] & tops[j] for i in range(min(len(tops), MAXP)) for j in range(i)):   # 2+ in one top-level directory: cap at 2,
        k = max(1, len(run))   # keeping the running ones (or the first pick), preferring a disjoint one
        cand = cand[:k] + ([n for n, t in zip(cand[k:], tops[k:]) if not t & tops[0]] or cand[k:k + 1])[:max(0, 2 - k)]
    cand = [n for n in cand[:MAXP] if n not in run]
    for n in cand:
        r = R[n]; me = KINDS.get(r["kind"], "opus/medium") if r["model"] == "default" else r["model"]
        if not okme(me): print(f"c{n}: model/effort {me} not allowed (--check): not started"); continue
        m, _, e = me.partition("/")
        prompt = f"Session task: {key}\nChunk: {key}/{n}\nRead {d}/{key}-c{n}.md and do it."
        print(f"{os.environ['PLAN_BG']} --model {shlex.quote(m)} --effort {shlex.quote(e)} -n {shlex.quote(f'{key}-c{n}')} {shlex.quote(prompt)}")
else:
    for n, r in R.items():
        st = "running" if running(n) else state.get(n) or ("ready" if wave[n] and all(isdone(x) for x in r["deps"]) else "waiting" if wave[n] else "blocked")
        print(f"c{n:<3} {st:<8} {r['kind']:<10} {r['title']}")

# Status command and pane reference

Read when writing or debugging a project's `session-status-adapter`, editing
`.claude/coordinator-actions.json`, when a status line, a pane group or a pane word is unclear, for an
option the coordinator's [SKILL.md](SKILL.md) doesn't name. The rules a coordinator acts on every day are in
[SKILL.md](SKILL.md).

## Contents

- [Footers in detail](#footers-in-detail)
- [Commands in detail](#commands-in-detail)
- [Context watch](#context-watch)
- [The adapter](#the-adapter)
- [Words the pane reads in EXTRA](#words-the-pane-reads-in-extra)
- [Without an adapter, and task ownership](#without-an-adapter-and-task-ownership)
- [The pane in detail](#the-pane-in-detail)
- [Project actions in detail](#project-actions-in-detail)
- [Modules: terminals, messages and features](#modules-terminals-messages-and-features)

## Footers in detail

`session-status` prints one line per task: status, the local worktree (dirty files, unpushed commits), and the
owning session, live (name + state) or closed (`closed Nh`). Then the footers: **Waiting on you** (blocked background
sessions that sit on a prompt or whose last turn asks the user, with the `claude attach` command and, on a prompt, what
it waits on: `— blocked: Bash \`…\``; one at rest asking nothing shows idle), **Stale prompts** (prompts unanswered 6h+,
with the stop command: answer or stop), **Leftovers** (sessions and worktrees of finished tasks, with the stop/remove
command; `--watch` stops the sessions at rest itself, see `--changes`; one idle a week whose removal loses nothing moves to **Resolved**; a worktree whose branch names no task key shows as
`no task` once idle a week; an untracked symlink to the main checkout's same path, such as `node_modules`, counts as
clean), **Notices** (from the messages module,
then the adapter, the handoff file and the docs watch (`features/docs-watch.md`); act on a message line per the module's doc; a message line the user calls handled: `session-status
--dismiss "LINE"`, for every session, not passed on again) and **Other sessions** (live sessions that own no task,
e.g. a reviewer: `· reviews KEY`), and last, at most once a day, `plugin feedback: N open (M seen ≥2×) — apply?` (or
its plugin-coordinator form, below). It
asks `claude agents --json` of your account (with `features.accounts`, every account sharing your transcripts:
[features/accounts.md](../../features/accounts.md)). A background session whose process ended (Claude Code still
lists it `blocked`, with no pid) has ended: its row says `closed`, and neither Waiting on you nor Other sessions lists
it, so the user is never asked to stop it. Its `claude attach` command resumes it if its work goes on. A background
session that finished its turn is `state: blocked` on older engines; agent view (2.1.330 on) says `state: done`
while its process is alive (`pid` set), and `done` with no `pid` once it ended. The status lists a live `done` as
blocked, so there blocked means idle *or* waiting and done means retired. `status` tells them apart: `idle` (turn
over), `waiting` (a permission prompt or question; `waitingFor` names it on newer engines), `busy` (mid-turn);
`--activity` prints it.

**Waiting on you** shows what a blocked session waits on from the plugin's hooks. A task's worker at rest
(Claude Code reports a background session `blocked` once its turn ends) whose row only waits on a reviewer
(`no-human-approval`, no CONFLICT, CI-FAILED, `!NAME`, `↩` or unpushed commits) isn't listed there: its row
shows it `idle`, so the pane puts the task under In review, not on the user (0.32.1, the user 2026-10-21).
On a prompt or question (status `waiting`, or a hooks/blocked.sh record), or while another row it owns still needs the user, it still is. A `+NAME` on any of the task's PRs makes it the user's
merge call.

The list keeps itself current (0.35.0, the user 2026-10-21: "it should update itself"). Any other blocked
session is on you only while it sits on an open prompt, or its last turn asks the user: a question, a
`! command` for them to run, or words like "your call", "blocked", "decision for you" (in its text or its
SendMessage summaries and `reply` texts since the last prompt). A row with CONFLICT or `+NAME` keeps its session on you
regardless. Not on you, first match: busy (a session limit leaves it blocked mid-turn), superseded, a
reviewer at rest (its report is delivered; comments to post wait in the review inbox), its work landed (it
started in a clean worktree whose branch, with a commit made after it started, is merged into origin's
default), or a finished turn that asks nothing. Its row says `idle` or `busy`; one with no row is under Other sessions.
A question needs a `?`, a `! command` line or the words outside code (fenced blocks and `spans` are
skipped). Limits: a turn that asks while its branch has landed counts as landed; a squash-merged branch never
counts as landed; `--changes` still ignores a plain entry appearing (workers report questions by message).
A prompt hooks/blocked.sh didn't record (status `waiting`, no record) shows what Claude Code's `waitingFor` names
(`— blocked: dialog open`), else `— blocked: a prompt`, aged by its
transcript's last write (nothing is written while it waits). A prompt unanswered for 6 hours (`SESSION_STATUS_STALE_HOURS`) moves to **Stale prompts**, with
`· unanswered Nh; stop: PREFIX stop ID`, and its row says `stale`: answer it or stop the session. So does a prompt
whose work landed (above), at any age, with `· its work landed`: the prompt is moot. The pane
doesn't count those on you and offers Stop on them (`session-status --stop ID`, then a refresh); `--changes` doesn't compare that section.

**Other sessions**
lists live sessions that own no task row (no task, a reviewer, a session in one of the adapter's
`session-dirs`) and aren't on you (Waiting on you and Stale prompts list those), coordinators left out, one line each:
`"NAME" STATE AGE[ · reviews KEY][ · superseded by NEWID][ — LAST TEXT] (PREFIX attach ID)`. A superseded
session (below) at rest is listed here, not under Waiting on you; on a prompt it still waits on you. AGE counts from its start while
it works, else from its last transcript write; an idle or done one drops off after 3 hours
(`SESSION_STATUS_OTHER_HOURS`), unless it is superseded or at rest (blocked): those stay, and the pane folds them
with the ones idle a day into one row with Stop all. `--changes` doesn't compare that section.

**Stale** (stale.jq) flags the pane's queued asks and the handoff file's entries whose facts moved on, and sessions
asking the user with no ask queued, one line each, its reasons joined by `; `:
`ask ID KEY: WHY`, `pending "LABEL": WHY`, `session "NAME" (ID8)[ KEY]: decision not on the pane`. The reasons:
`ticket done` (the tracker calls the key finished and no PR of it is open), `[reword: ]REPO#N merged` (a PR it names
settled; `reword:` while another it names is open), `names ID8, gone` (a session it names isn't live),
`worktree PATH gone` (relative ones looked up under the root and the session-dirs), `reword: names ask N, not
queued` (an entry's `ask N` / `pane id N`; prose like "ask 2 reviewers" matches too), `= ask N` (an entry whose key
has a queued ask), and `recheck: queued over 3d` / `recheck: unchanged over 7d` (age alone: check, never a cancel by
itself). `session-status --stale` prints the items alone; `--changes` says each new item once (a session's line
never: Waiting on you has it). Nothing is cancelled or archived on its own: the pane draws a STALE chip on the ask
or entry with Cancel (the ask is dropped and the coordinator told) or Archive (`--pending-done LABEL -- stale:
WHY`), neither offered when age is the only reason; Archive not for `reword:` and age alone either, nor when two
entries share the label. A turn that ends with a `reply` marked done, asks no `?` question and hands no `! command`
waits on no one. A leftover idle a week whose
removal loses nothing (a session, a clean worktree whose commits are merged or on origin) moves to
**Resolved (idle a week)**, so Leftovers empties on its own; `--changes` ignores that section. One with
uncommitted or unpushed work stays a leftover, and so does one with ignored or hidden files the main checkout lacks
(`git worktree remove` would delete them; its line says so instead of giving the command). Under `--watch` a finished task's worktree that loses nothing goes on
its own, as does a Resolved `no task` one whose commits landed (see `--changes`).

**Plugin feedback** comes last, one line: `plugin feedback: N open (M seen ≥2×) — apply? (feedback.md)`, from
`feedback footer` ([feedback.md](feedback.md)). Only a coordinator's sweep shows it (the calling session ran
`--start`, `--changes`, `--watch` or `--owner`, or opened the pane), at most once a day per person (the stamp
`.footer-shown` in the feedback folder), and only with open cases. With a plugin coordinator (`feedback.repo_dir`;
[features/plugin-coordinator.md](../../features/plugin-coordinator.md)), another project's sweep leaves the plugin
part out while that coordinator runs (checked at most once an hour). While it doesn't run, the part reads `…, for
the plugin coordinator, which isn't running — start it? (feedback coordinator --start)`, once a day on a stamp of its
own (`.footer-elsewhere`). The plugin coordinator's own `--changes` adds a
`Feedback (feedback list --plugin)` section, one `* TITLE (FILE)` per open plugin case, so a new case wakes its
watcher, and an `Issues (feedback issues)` section, one `* #N by LOGIN (URL)` per open issue on the plugin repo that
no PR closes and no case names (never the issue's text: it is outside users' data). This project's own cases add `· project feedback:
K open (…), for the next retro` (alone when the plugin has none): nothing to do but pass it on. Never in the `--changes` child (so the watcher
doesn't wake on it) or the pane's runs, which set `SESSION_STATUS_NO_FEEDBACK=1`.

## Commands in detail

Transcripts live in `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/<encoded cwd>/*.jsonl`, the encoded cwd being the
path with every non-alphanumeric character turned into `-` (`/home/a.b/proj` → `-home-a-b-proj`); `--peek` and
`--activity` read them for you.

| Command | Shows |
|---------|-------|
| `session-status` | All open tasks, plus the footers |
| `session-status KEY [KEY…]` | These tasks only, no footers. A key owned by a live sub-coordinator (first prompt `Coordinate KEY`) has `sub: STATE[; plan D/N landed, cX running]` before its title (`sub done: …` once it ended cleanly, `sub gone, KEY unfinished: …` otherwise), and lists the sessions folded into its row under `Under KEY-coordinator:`, one `"NAME" STATE (PREFIX attach ID)[ — blocked: …]` each |
| `session-status ARG…` | Other args go to the adapter (e.g. an extra query clause); one starting `--` is refused as an unknown option (exit 2) |
| `session-status --help [--FLAG]` (or `-h`) | This table's rows (those of --FLAG), with no sweep; exit 2 when no row names --FLAG |
| `session-status --coordinator` | Names of this account's live sessions that ran `--start`, `--changes`, `--watch` or `--owner`, or opened the pane (coordinators), newest first (a ready handover successor before the one it replaces), excluding the caller; then, with `features.accounts` on, another account's such sessions as the `uds:` address of their live socket (none without one). No tracker calls. Workers use it to find where to report |
| `session-status --address NAME\|ID [--other]` | The `uds:` address SendMessage reaches a live session at, under any listed account (`--other`: another account's only, by exact name; exit 4 when one of this account matches, 3 whenever a listing failed, 5 for a name in `remote.tsv`, saying what reaches it: Remote Control, or `--link send`; the plugin's `session.send` hook uses it for a SendMessage by name the engine refused): its socket `/tmp/cc-socks/<pid>.sock` (`SESSION_STATUS_SOCK_DIR`), for the listed pid only when that process lives. NAME exact, or an id prefix of 8+ characters. Exit 1: listed, but no live socket; 2: no live session matches, or several; 3: none found and an account's listing failed ([accounts](../../features/accounts.md)) |
| `session-status --coordinator-of DIR [--start]` | The coordinator of the project DIR is in, when that's another than this one (a subproject with its own adapter below, the parent above), under any account: its name (under another account, that account and, with `features.accounts` on and a live socket, `SendMessage to "uds:…"`; else `SendMessage reaches it only from there`), exit 1 when it isn't running, 3 when an account's listing failed, 4 when DIR has none of its own (this project covers it; a coordinator already opened there is named), 2 for this project's own root. `--start` opens the one that isn't running in a terminal tab (config `terminal`), or, for exit 4's, a new coordinator in DIR whose setup offers `--init --own`; exit 5 when nothing opened (the command to run is printed). sessions.md, Subprojects |
| `session-status --owner KEY [KEY…]` | Who owns each task and why: the row's session column, then each candidate (owner first) with its rule (first-prompt, marker, review, maybe), state, first prompt line and markers. No tracker calls. Run it before giving task work to a session |
| `session-status --compact ID` | Makes an idle background session run `/compact`: stops it, waits for its process to end, resumes it under the same id with `/compact` as its prompt (a retired one is just resumed). Refuses (exit 3) a busy or waiting session, an interactive one, and one another `--compact` is already working on (a per-session lock, whoever runs it). ID: 8+ characters of its id |
| `session-status --stop ID` | Stops a session in whichever account lists it (`claude stop` under that account's prefix) and waits up to 30s for its process to end: the pane's Stop on a stale prompt or a superseded session. Prints `stopped "NAME" (ID8)`; `isn't running` (exit 0) when it has no process; exit 2 when no account lists it, 1 when the listing or the stop failed, 3 mid-turn or while a `--compact` holds it. ID: 8+ characters of its id |
| `session-status --send-when-idle [--here] ID TEXT` | Waits until the session isn't busy, then delivers TEXT without forking it. A live one under another account with a live socket: at once, busy or on a prompt too, `send: SendMessage to "uds:…" now (…)`, exit 0; with none, stopped and resumed with TEXT. `--here`: a session under another Claude account is resumed under this one (name kept), so SendMessage reaches it after. Refuses (exit 4) a resume of one holding over 200K tokens (`SESSION_STATUS_MAX_RESUME`) and prints the `--handover` command. Refuses (exit 5) a session a later handover superseded (`Supersedes: ID`, followed to the newest) and names that successor, which owns the task now; so too one renamed `NAME-prev-K` (a coordinator's handover too) while a session of the same project (its folder or one holding it), live or retired but not failed, is named `NAME`, naming that one. See [resuming.md](resuming.md) |
| `session-status --start [args]` | A coordinator's Start in one run, under `## ` headers: the status (args as for a plain run; its exit code; bounded: at most 5 lines each of `Leftovers (task finished):` and `Other sessions:`, then `  (and K more: … prints them all)`, so the plain status shows the whole board), the handoff file (the adapter's `pending`, its path when `pending.file` is set), the last handover note (`coordinator-handover.md` in the replies folder) and, under `## Handover lines`, the text of the `file:N` / `file:N-M` spots it names (as `--handover`'s brief: from the project root, within 8000 characters with the note), the replies written since that note (since the last day when there's none; newest first, 20 at most, each with its first line) and the coordination config (`--init --check` without its first line: the active line, each feature's start line, with `features.accounts` each account's weekly use, the warnings). When there are any, a `## Ended while the background service was off (or failed), task still open` section after the handoff file: one line per such session of the project (`claude agents` state `failed`, no process) that owns a status row or whose key or short id the handoff file names, unless a later session's first prompt supersedes it or another session (not failed itself, live or retired) has its name, then one ask for them all, key `resume-after-restart`, whose yes runs the `--resume-ended` it prints ([resuming.md](resuming.md#after-a-restart)). A failed listing says so there: ended sessions in that account are unknown |
| `session-status --resume-ended [--pause SECS] ID…` | Resumes `--start`'s ended sessions one at a time, SECS (60) apart. Just before each (after the pause), a fresh listing: one no longer failed, superseded, or whose name another session has is skipped with the reason (a resume would start a duplicate). Each resume is `--send-when-idle`'s (its own id and account; over 200K refused with the `--handover` command) with a note that it was resumed after a restart and approves nothing. Exit 0 when all went, else the last problem's code (1 a listing or resume failed, 2 not listed, 3 skipped, 4 too big) |
| `session-status --changes [args]` | Only lines changed since the last `--changes` run, or `no changes`; idle/busy and ages ignored, and so is a session only entering `working`, flipping between working, idle and blocked, or its worktree's dirty/unpushed counts changing while it works (entering done or closed counts, with the current counts). A plain "Waiting on you" entry appearing doesn't count, nor does one going away while its session lives on; one whose session ended does, and so does one saying what it's `blocked:` on. Emptied section headers aren't printed. With `features.accounts` on it adds `Reports:` and `Weekly limit:` ([accounts](../../features/accounts.md)). It adds `PR events (…):` lines, `* REPO#ID ci-failed|conflict|changes-requested @SHA (KEY) → "NAME" ID`, for an owned open PR's new CI-FAILED, CONFLICT or `!NAME`: once per PR, event and head SHA (the worktree's pushed head), changes-requested once while it stays; and `* REPO#ID[,…] all-merged (KEY, STATUS) → "NAME" ID` (or `→ no owner`) once per task and PR set when all its PRs are MERGED and it is still on the board; the first run only records (sessions.md, PR events). Each has its nudge for the owner on the line under it (`    nudge: TEXT`). A key a live sub-coordinator runs lists no per-PR events (all-merged still, owned by the sub) for any caller but that sub ([subcoordinator.md](subcoordinator.md)); the sub's own run marks each `(not forwarded: yours: send it to the session whose PR it is)` and sends nothing. Under `--watch` (`SESSION_STATUS_FORWARD=1`) a committing run sends each owned event's nudge itself: `--send-when-idle` without waiting, and a live session (`send:`, or busy; under another account by its socket's `uds:` address, which `--outbox` looks up as it prints, so a pane must be open for those too) through the outbox (`~/.cache/session-status/<project>.outbox`), which the coordinator pane's 60s timer reads (`--outbox`), sends and reports back (`--outbox-done`, which only then drops the entries). A sent one shows under `Forwarded (…)` only beside other news; one not sent stays a PR event with `(not forwarded: WHY)`, as does an outbox entry no pane took in `SESSION_STATUS_OUTBOX_S` (600) seconds. A committing `--watch` run also stops each finished task's background session at rest (Leftovers or Resolved; state idle or done, quiet `SESSION_STATUS_STOP_AFTER_S` (600) seconds; not busy, on a prompt (`waiting`), under Waiting on you (but one there only because its last turn reads as asking, with no prompt: its task is finished, so its report is in), the caller or a coordinator; a sub-coordinator counts as a worker here, so a finished key's sub stops too) with `--stop`, drops its lines (Leftovers, Waiting on you, Stale) from the board and the baseline, and lists it under `Stopped (finished tasks' sessions and worktrees, by the watcher; tell the user in one line):` as `* KEY[ LABEL] — "NAME" (ID8)`, which is news; a peek stops nothing but lists them as `* would stop: …` (so `--watch` confirms), and one `--stop` refuses stays a leftover. Then, for a finished task no live session holds any more (none left, or each of the key's stopped just now) and with every account's sessions listed (a failed listing removes nothing), it removes each worktree of the key that loses nothing, with `git worktree remove` and `git branch -D`: on a branch that names no open row's key, not the main checkout, no live session working inside the folder, no uncommitted or untracked file (whatever `status.showUntrackedFiles` says) nor a skip-worktree or assume-unchanged one, every ignored file also in the main checkout (a file the same; a folder holding each of its files the same; a symlink at a path the main checkout has too: build output and caches pass, a `.env` only the worktree has keeps it; a folder ignored itself and named like a dependency, build or cache one, such as `node_modules`, `dist`, `.turbo` or `.venv`, passes unread: an install or build makes it again), and `git cherry` against `origin/HEAD` lists no commit whose change is missing there, nor any merge commit (main lands by rebase, so the copies have other SHAs; a base that says otherwise is fetched once per repo per run, with `--prune`, then checked again), or, after that fetch, every commit is on some remote branch (pushed to its own branch, never merged: `N unmerged commit(s) all on origin/BR`). A worktree whose branch names no task key, once Resolved, goes the same way, but only when its commits landed (a pushed one may be an open PR under review). Each shows under `Stopped` as `* KEY[ LABEL] — removed worktree REL and branch BR` (a peek: `* would remove: KEY[ LABEL] — worktree REL, branch BR`), and its Leftovers line leaves the board and the baseline; any other stays a Leftovers line. A file action (`.claude/coordinator-actions.json`) whose `when` held at the last committing run and no longer does (each check capped at 10s) shows under `Logins restored (…):` as `* LABEL[ — blocked on it: KEY, …]`, the keys of the replies-folder reports of the last 7 days whose first line says `· blocked` and whose `Blocker:` line names the label, the command or a sign-in (the words `login`, `sign in`, `signed out`, `auth`, `expired`); a check that times out keeps its last state. The first run, a peek too, only records (`<state>.when`); a later peek records nothing. State is kept per arg list: while a watcher runs, a manual run with its args consumes its change |
| `session-status --watch [--every SECS] [args]` | Blocks until a change shows at two polls in a row (120s apart, `SESSION_STATUS_CONFIRM_S`), prints it and exits. Checks every SECS (default 1800). A failed poll (Jira/Bitbucket timeout, a jq error) logs one line to stderr and is retried at the next check (120s while a change is being confirmed); 3 in a row (`SESSION_STATUS_WATCH_TRIES`) end it with "gave up after 3 failed polls in a row" and the last error. Every tick (`SESSION_STATUS_TICK_S`, 60) it also reads `sessions/*.json` of each account (no tracker, adapter or CLI call) for a background session of this project (cwd the root or under it) whose status is idle for at least a tick; it skips a dead pid, the caller, a coordinator (`-coordinator`, `-prev-N`) and one already reported for that idle turn (`~/.cache/session-status/<project>.idle`, rewritten each tick). It reads the transcript from the session's start: a reply (reply tool or SendMessage) in the last turn, or a background Bash, Monitor, Agent or Skill not yet ended, is held. Any other idle turn prints `Idle: NAME (ID8): its last line`, once, and the watch exits 0 (all such lines in one wake). **The 5-hour limit**: each tick of the project's own watcher (not a sub's `--watch KEY`) also queues, with the scheduled starts, one resume for each live background session of this project (not the caller) whose last message is Claude Code's 5-hour limit row (`quotaLimits` rejected for `five_hour`, its `resetsAt` within the last day), due at `resetsAt` plus a minute. It is listed as `resume:NAME:ID8 · resume · MM-DD HH:MM · after its 5-hour limit resets` (`--launch --cancel resume:NAME:ID8` drops it; `--now` sends it at once, but only once the limit has reset: before that it stays queued, exit 1). Once per limit hit: `~/.cache/session-status/<project>.limit-resets` keeps each session and `resetsAt` queued in the last day (checked and written under a lock), so later ticks, and a second watcher, queue nothing more for that hit. Such a session prints no `Idle:` line. Due, it is sent the way PR event nudges are forwarded: `--send-when-idle ID TEXT` without waiting, and through the outbox for a live session (the coordinator pane sends it), so it wakes no one and shows under `Forwarded` at the next wake. TEXT says the limit reset, to continue, and to act on any message that came during the wait. A session whose last message is no longer that row (resumed meanwhile), or with no live process (stopped meanwhile: a stop wins), is skipped. A send that fails wakes the watcher with `Limit resume: "NAME" (ID8) 5-hour limit reset, not sent: WHY. Send it yourself: TEXT`; without the last sentence when WHY names its own next step (`--send-when-idle`'s exit 3, 4 or 5). **Messages sent during the wait** are not dropped: Claude Code delivers each one at once, writes it to the transcript and answers it with another limit row (same `resetsAt`, so nothing more is queued). The resume turn has them in its context, and TEXT tells the session to act on them |
| `session-status --handover ID\|--self [--model M] [--effort E] [--escalate] [--] 'WHAT NEXT'` | Hands a task or chunk over from a session too big to resume (`--send-when-idle`'s exit 4 prints this command). ID's task key: the one its first prompt or own `Session task:` markers name (exactly one). Refuses (exit 3) while it is mid-turn, waiting on a prompt, or interactive and live; (exit 2) when the replies folder (the project `CLAUDE.md`'s "Replies folder … \`PATH\`" line) has no `KEY.md`. Then stops it (waits up to 30s for its process to end), and runs `claude --bg -n NAME 'Work on KEY: continue from <replies>/KEY.md. WHAT NEXT. Supersedes: ID (transcript PATH; read only the parts you need, never whole).'` from the project root under the caller's account (plain `claude`: the old one's may be at its weekly limit, and only the caller's sessions can message its coordinator), unless `features.accounts_weekly_switch` is on, the caller's is past 90% of its weekly limit and the old one's is under it ([accounts](../../features/accounts.md)). NAME is the old name if it starts with KEY, else `KEY-<old name, slugged>`. Prints `handed KEY over: … superseded by "NAME" (NEWID)`. `--model M` and `--effort E` go onto the `claude --bg` line (`fable` only under an account config `fable.accounts` lists). Each one left out is, for a chunk, row N of the plan `KEY.md` in the replies folder (`--plan … --brief N`; it may have been re-planned), else what the old session last ran on (its transcript's last reply: model, with its `[1m]` variant, and effort, `fable` included when the user put it there, but `opus` at its effort while the caller's account is at its Fable limit; the effort only with that same model), else the daemon's default. **`--escalate`** (the same failure twice, [sessions.md](sessions.md), Repeats and reloads): the successor runs one rung above that model and effort: the effort first, up to `xhigh`; then the model, `haiku` → `sonnet` → `opus` at the same effort (`xhigh` or `max`; a `[1m]` suffix kept, a full id taking the next family's alias); then `xhigh` → `max` on any other model, `fable` included; then `opus`/`max` → `fable`/`max` (a `[1m]` suffix kept) under an account config `fable.accounts` lists, never elsewhere. Refused (exit 2, `--escalate: … not handed over`, nothing stopped) at `max` on a model past `sonnet` with no rung left (`fable`/`max`, or `opus`/`max` without fable), or when the model or effort is unknown (pass both). The printed line ends `, escalated to M/E`, and with `telemetry` `local` or `full` (the default) it logs `{"t":…,"k":"escalate","what":"task"|"chunk","model":M,"effort":E,"sess":H}` (H: the old session's name, `-prev-K` dropped, hashed as `--kind`'s), which `retro.py kinds` counts per start and `retro.py chunks` counts for chunks. **A chunk session** (a `Chunk: KEY/N` line in its first prompt) needs no `KEY.md`: its successor, named `KEY-cN`, gets a five-line prompt that continues from the last `## cN: handoff` in `KEY-build.md` and follows the brief `KEY-cN.md`, both in the replies folder. **The handover brief**: either prompt then carries the handoff (the last `## Handoff` section of the file it continues from, or the last `## cN: handoff`) and, below it, the text of each `file:N` or `file:N-M` spot the handoff names (N alone: N-2 to N+2; at most 80 lines a spot), numbered, read from the task's worktree in any of the project's repos (a branch named as the session, else KEY), else the old session's folder, else the project root (a bare name: the one tracked file whose path ends in it), else the replies folder; outside the replies folder only a file git tracks (no `.env` goes into a prompt), and an absolute path only inside one of those folders; a spot none holds is left out. Each excerpt names the file it came from. All of it within 8000 characters (`SESSION_STATUS_BRIEF_MAX`): spots past it are listed as `Not pasted (past 8000 characters): …`, and a handoff over it isn't pasted at all (the successor reads the file, as before). Pasted lines that would read as the prompt's own markers (`Chunk:` or `Act as a coordinator` at a line's start, `Session task:`, `Supersedes:`, `You replace`, `You succeed`) get a space or a colon added. It is refused (exit 2) when `KEY-build.md` has `## cN: done` (`cN is done (…): nothing to hand over`), and unless it has ID's own `## cN: handoff ID8` (ID8: ID's first 8 characters); failing that, more writers of `## cN: handoff` sections than ID has predecessors (its `Supersedes:` chain), where each id-less heading counts one and each other ID8 one. `--self` with `CLAUDE_CODE_SESSION_ID` unset says so (exit 2). A name ending `-prev-K` loses it first. When the old session still has the successor's name (it didn't rename itself), it prints one more line: `"NAME" (old) wasn't renamed: two sessions share NAME until it is`. **`--self`** (the caller's own id): a session hands itself over as its last step at its context mark, a coordinator running or not (the coordinator isn't messaged: its status shows the successor). It isn't refused as busy; it prints `handed over; rename yourself (call name_session with "NAME-prev-K"), then end your turn now, with no message (…)`, and a detached loop stops a background caller once its turn ends (`--stop` every 30s, up to 40 times, retrying while it is busy or the listing fails); an interactive one is left for the user to close. Refused (exit 2) for a review session. A successor's approval hook also reads the relays its predecessors received (its `Supersedes:` chain), each usable once over the chain |
| `session-status --prev-name [NAME]` | `NAME-prev-K`, the name a session takes when it hands off (`name_session`), so its successor can keep NAME. NAME (default: the caller's own, by `$CLAUDE_CODE_SESSION_ID`) loses any `-prev-K` first; K is the lowest number no listed session of any account (live or retired, `claude agents --json --all`) carries. A caller already named `NAME-prev-K` gets that name back. A failed listing gives K = 1. `--prev-name --title` also titles the caller's terminal tab with it (the terminal's `title_tty`; a note on stderr when it can't) |
| `session-status --successor [--account DIR]` | A coordinator named NAME starts its successor: an interactive `claude --model M --effort E [--remote-control] -n NAME-next 'Act as a coordinator. You succeed "NAME" (ID8): …'` (M, E: what the caller runs on, from its transcript's last reply, `fable` included unless DIR's account is at its Fable limit; else `plan.models.coordinator` as DIR's account reads it: `fable/medium` where config `fable.accounts` lists DIR, `opus/medium` elsewhere, unless configured) from the project root, under DIR (default the caller's account), in a split of the caller's own tab (the terminal's `split_tty` on the caller's tty, or in the background the tab it was moved out of), else in a tab of the configured terminal (`open_view`): with the split, `--await done` closes only the caller's split and the successor fills the tab. Nothing opened (exit 2): prints `cd ROOT && … claude -n …` to hand the user. In Claude Code Desktop (`CLAUDE_CODE_ENTRYPOINT` `claude-desktop*`) without `--account`, it opens nothing and prints (exit 2) a `mcp__ccd_session__start_session` call: title NAME-next, a fresh context in this checkout, the same model and effort, `initiation` `user_asked` or `own_initiative`, a prompt whose first step is `--successor --started NAME`; the caller leaves its pin and never archives itself (the successor's `--await name` says to move the pin and archive it). Refused (exit 3, nothing started) while `<replies>/coordinator-handover.md` is missing or older than the caller's own start (a failed Write would hand the successor its predecessor's state). Refused when NAME-next is live already or (opening a tab) a tab titled NAME-next is open (the terminal would select it, starting nothing; exit 3), or the caller's name isn't a coordinator's own or has characters outside `[A-Za-z0-9._-]` (exit 2). A successor's `--await name` retitles its own tab NAME when it finds NAME free, and `--successor` retitles the caller's own tab NAME before it opens one, so a NAME-next title left from the caller's own start as a successor isn't taken for an open successor's; when that retitle failed, the refusal says the tab may be the caller's own. Prints the next step: arm `--await ready`, forward every message to the inbox |
| `session-status --successor --started NAME` | A Desktop successor's first step: writes its id to `NAME.next` in the handover stamps, so `--name-check`, `--await` and the old one's `--await ready` count it as NAME-next whatever name the app gave it (until it is listed as NAME), and `--successor` counts it as a live NAME-next. Refused while no other live session holds NAME (exit 2), or when another live successor is recorded (exit 3). `--await done` and the next `--successor` remove it |
| `session-status --successor --done` | The old coordinator, done forwarding, writes the done stamp the successor's `--await name` (or `--await done`) waits on: still holding NAME once NAME-next has finished its Start (its ready stamp names a live NAME-next; it then renames itself last), or renamed NAME-prev-K (the earlier steps). Refused while it holds NAME and no live NAME-next wrote the ready stamp (exit 3), or when its name is neither NAME nor NAME-prev-K (exit 2) |
| `session-status --approvals` | The approval answers clicked in this coordinator's pane that are still live (24h from the click, `MAX_AGE_H`, as long as `verify-approval.sh` takes the quote), in its own transcript and, back along `You succeed "NAME" (ID8)` first prompts, its predecessors' (`CLAUDE_CODE_SESSION_ID` unset: exit 2), newest first, one line each: the answer line without its `Approval pane answer for ` prefix, then `Nh left · not relayed` or `Nh left · relayed: ACTION to NAME; …`. A relay (the coordinator's SendMessage of a relay block) counts for an answer when its Quote is that answer and it was sent after it. `--start` prints only the answers still to act on, under `## Approvals still to act on`: not relayed, the newest on its key, not a No nor a request to explain (`Explain`, an answer ending in `?`), its task not gone (it speaks of the task's worktree, branch, start or landing, a session of this project is named KEY, none of them live, and no status row has its worktree; not judged when `--start` has args), not a start done since (it speaks of starting, and a session named KEY started after it), and when clicked before both the handover note and this session's start, its key named as a word in that note or the handoff file. At most 5, newest first, each cut to 200 characters, then `(and K more, H done or stale: session-status --approvals lists them all)`; nothing when none is left |
| `session-status --relay KEY [ACTION [--quote -]]` | The relay block ([approvals.md](approvals.md#the-relay-block)) for KEY's newest live pane answer, Source this session (its id and listed cwd), printed only once `verify-approval.sh` passes it as the worker will; send the output as is once its Quote approves ACTION. No ACTION: the one the answer ends with (`Action: …`, from ask_approval's `action`). A Yes that granted its action (an ask with `session`, [approvals.md](approvals.md#grants)) prints the go note instead, with no check or listing (KEY's newest answer only; when ACTION is given, only for the granted action). `--relay KEY ACTION --quote -`: the user's own words on stdin instead of a pane answer, same check and block, no grant looked up. A landing `merge TARGET (<session name>)` relayed under a key that isn't the session's own gets `, approved under KEY` added (not when the Action names a tracker key, such as `KEY-fix` or `KEY-cN`: the hook verifies those itself), and is refused when the answer's own words (not its `Asked:` question) don't speak of landing or merging; a yes asked under the session's name without the project prefix (`issue-templates` for `<project>-issue-templates`) counts as its own. The worker's check reads the Source's transcript for its send of the whole relay first, so a relay whose Source has since stopped still verifies. Other live answers for KEY: it says how many on stderr. Exit 1 with why: no live answer for KEY, KEY's newest live answer a `No, …` (it stands: an older yes isn't relayed), the check's rejection, this session not listed, or a Desktop successor recorded in `NAME.next` and listed under another name than NAME-next. Exit 2: no KEY, an ACTION over one line, no ACTION and none in the answer, `--quote -` without ACTION or with nothing on stdin, or `CLAUDE_CODE_SESSION_ID` unset |
| `session-status --await ready\|renamed\|name\|done [--timeout SECS]` | Waits (polls every `SESSION_STATUS_AWAIT_S`, 10s; default timeout 3600s, 86400s for `ready`, then exit 1) for a handover step, through stamps in `$XDG_CACHE_HOME/session-status/handover/` (no messages: the two may be under different accounts). `ready` (old): NAME-next wrote its ready stamp; it then forwards, runs `--successor --done` and renames itself last. `renamed` (old, the earlier steps, armed after its `name_session`): the listing shows it under a name other than NAME, since the rename lands only when its turn ends. `name` (successor, at the end of its Start, its one wait): writes the ready stamp, waits until no other live session holds NAME, retitles its tab NAME, then goes on as `done` in the same wait and ends its message with `Now call name_session with name NAME.` (a timeout after NAME was free says so). `done` (successor, named NAME, the earlier steps): the old one's done stamp is there and it is idle; closes its terminal (`close_tty` on its process's tty) and prints what it closed or left; in Desktop it closes nothing and says how to finish the old one (listed or exited: its sidebar row stays) with the app's tools: detach from it (`detach_session "self"`: archiving takes its side sessions with it; refused when the successor shares its worktree, and then never archive it), take its pin (`set_pinned`), archive it (`archive_session`; `stop_session` only interrupts a turn), and tell the user once when it stays. A successor's wait (`name`, `done`) ends only on its step (or a refusal or timeout); the unread inbox entries that came meanwhile print after its outcome, under `Inbox while you waited: act on each, then \`… --inbox --read N\`:` |
| `session-status --name-check NAME` | `free\|held next\|other [HOLDER_ID]`: whether a live session other than the caller holds NAME, and whether the caller is NAME-next (by its listed name, or its id in `NAME.next`). `open_pane` and `name_session` ask it before taking a `-coordinator` name |
| `session-status --inbox [--read N…\|all]` | The coordinator inbox (`<replies>/coordinator-inbox.md`): prints the unread entries; `--read` marks entries read. `--start` lists the unread ones and `--changes`/`--watch` report new ones under `Inbox` |
| `session-status --inbox-add [--from WHO] [--hold] [SENDER_ID] < TEXT` | Appends TEXT as an unread entry `## K · unread · MM-DD HH:MM · from WHO` (WHO: the sender's name and ID8 when SENDER_ID is given) and prints `FILE #K`. The reply tool's backstop when no live coordinator takes a message; an old coordinator forwards with it while it hands over. Exit 2 with no replies folder. `--hold` (the reply tool's `hold: true`): the heading ends ` · held`, and it is queued only while the coordinator's unscoped `--watch` runs (it touches `$ENC.watching` in the cache each tick and drops it on exit; none touched in 5 min: exit 4, and reply sends the message at once). The watcher wakes `SESSION_STATUS_CONFIRM_S` after the first held add with each one's text under `Held reports`, marked read, so reports held meanwhile join that wake; `--changes` never lists them. A held report from a worker whose key has a live sub-coordinator goes to the sub at once. Any other watcher wake carries the held ones too |
| `session-status --coordinators` | Every coordinator of the user's projects, newest `--start` first, under any account: `NAME · ROOT · ACCOUNT · running \| running under another account \| not running \| unknown · PURPOSE` (NAME is the live session's name: a `NAME-next` successor, or a Desktop one recorded in `NAME.next`, counts as running; `, this project` marks the caller's; `, no inbox` one whose CLAUDE.md names no replies folder, which `--inbox-add --root` refuses). Read from the person's registry (`coordinators.tsv` in the state folder; a coordinator registers at `--start`); a root no longer set up is skipped (none left: a `(none set up any more` line). Then, when `remote.tsv` holds any, `Remote`: `NAME · another computer (Remote Control): SendMessage by name while this session is connected to Remote Control · PURPOSE` per Remote Control row, and `PEER · a link to a coordinator on another account, held by the coordinator of ROOT: session-status --link send · PURPOSE` per link. sessions.md, Another project's matter |
| `session-status --remote add NAME --purpose 'LINE'` \| `--remote remove NAME` | Adds (or replaces) or removes one of the user's coordinators on another computer, same claude.ai account, in `remote.tsv` in the state folder (`NAME<TAB>rc<TAB>PURPOSE<TAB>EPOCH`); exit 2 on a bad name, a missing or overlong purpose, or removing a name that isn't there. features/remote.md |
| `session-status --link create PEER --github LOGIN --purpose 'LINE' [--accept ask\|work] [--self]` \| `--link join OWNER/REPO [--as PEER] [--purpose 'LINE'] [--accept ask\|work] [--self]` | Opens a link to a coordinator under another account (`--self`: yours) or another person's: `create` writes this side's config and prints the GitHub steps for the user and the joins; `join` fetches the repo, pushes this side's `peer.json` and adds the `remote.tsv` row (`PEER<TAB>link<TAB>PURPOSE<TAB>EPOCH<TAB>ROOT`). Coordinator only (exit 2 otherwise, 3 when a listing failed); exit 2 on a taken or Remote Control name, a purpose naming something local or another link protocol; 1 when the repo can't be fetched or pushed. features/remote.md, Links |
| `session-status --link send PEER --kind ask\|answer\|note [--re N] /abs/FILE [--check]` | Pushes FILE as this side's next `out/NNNN.md` and prints `sent to link PEER: KIND #NNNN`. Exit 2 (nothing sent): no such link, `task`/`result`, a relative or empty file, over 8 KB, a relay block, a scrub hit (the lines printed), the link not open (`waiting for the other side`, `closed by the other side`, `expired`, `expired on the other side`) or ended (closed or its repo gone, as fetched); 1: the repo unreachable. `--check` prints the action `send link message FILE to PEER (sha256 SHA)` and how it's approved, sending nothing. To another person's, the approval hook lets it run only on the user's pane Yes naming that action |
| `session-status --link list` \| `fetch` \| `renew PEER [DAYS]` \| `remove PEER` | `list`: `PEER · person LOGIN \| yours, another account · REPO · STATE [until DATE] · PURPOSE`, after fetching. `fetch`: each open link's new messages into the coordinator inbox, one line each, and one note when the other side closed it or its repo is gone (`--watch` runs it every 120 s). `renew`: a person link's expiry DAYS (14) from now, on the user's pane Yes naming `renew link PEER for DAYS days` (the approval hook). `remove`: pushes the close, drops the clone, config and row, and prints the user's GitHub step |
| `session-status --purpose 'LINE'` | Writes config `coordinator.purpose` (one line, at most 200 characters) to the project's `.claude/coordination.local.json`; exit 2 on an empty or longer line, 1 when that file is committed |
| `session-status --inbox-add --root DIR < TEXT` | Appends TEXT to DIR's project coordinator inbox, headed `from "<caller>" (<id8>) · <this root> · <account>`, and prints `FILE #K`. Exit 2: the caller isn't this project's coordinator, DIR isn't another project's root, its replies folder is in a git work tree that doesn't ignore it, TEXT holds a relay block, or `features.accounts` is off ([features/accounts.md](../../features/accounts.md), Messaging another project's coordinator) |
| `session-status --inbox --sent` | What this coordinator queued with `--inbox-add --root`, one line each: `unread\|read\|gone · DIR (its coordinator) #K · MM-DD HH:MM · text`. The plain sweep lists the unread ones under `Sent`, which the pane shows |
| `session-status --report-publish FILE --kind KIND [--allow-markers]` | May this session publish the report FILE as a private claude.ai page: `publish: yes`, or `publish: no (why)` with exit 1 ([features/report-artifacts.md](../../features/report-artifacts.md)) |
| `session-status --report-artifact SESSION_ID KEY KIND FILE URL VERSION_ID` | The reply tool's `artifact`: the page's row in `<replies>/report-artifacts.tsv`. The plain sweep lists the open rows of the last 14 days under `Report pages` (`KEY · KIND · TITLE · URL · ~ACCOUNT`, plus `· page behind the file` or `· file gone`), which the pane shows with an Open the page link (section slug `report-pages`) |
| `session-status --answers [--read NAME]` | With `features.answers` on, the folder the coordinator writes its answers to, made when missing; `--read NAME` (a `*.md` file there) moves it to the folder's `archive/` (`-<epoch>` added when the name is taken) and prints `archived NAME`: the pane's Mark as read. Exit 1 with nothing printed while the feature is off, 2 for a bad or missing NAME ([features/answers.md](../../features/answers.md)) |
| `session-status --plan FILE [--check \| --next \| --brief N \| --done N]` | A design's plan table (see [Plans and chunks](#plans-and-chunks) below) |
| `session-status --kind KIND[:S\|M\|L] [NAME [--anyway]]` | `--model M --effort E` from `plan.models.KIND` (KIND `design`, `build`, `mechanical`, `review`, `release`, `scan` or `coordinator`, sized by the `choosing-model-effort` skill; `retro`, a retro run (`features/retro.md`); `research`, a question answered from sources outside the project; a `fable` value falls back to the default unless config `fable.accounts` lists the caller's account, where `design`, `review`, `coordinator` and `retro` default to `fable` at their effort), to paste onto a plain task start's `claude --bg` line (run it as its own call: a failed one prints nothing to stdout); in Desktop with `start.sidebar` on it also prints the pair as `start_session` arguments (stderr); the app runs an effort the model doesn't offer at one it does, so `get_session` may show another. NAME is the start's `-n` session name. With `telemetry` `local` or `full` (the default) it logs `{"t":…,"k":"start","what":KIND,"model":M,"effort":E,"sess":H}` to the usage log, beside the chunk lines; `sess` (only with NAME) is the first 12 hex of NAME's sha256, so the name isn't in clear (someone who knows or guesses a name can confirm it). Run it once per task: a restart reuses the flags. Exit 2 on any other KIND, or a NAME its usage text rejects. **A size** (`build:L`: the `choosing-model-effort` skill's S, M or L) moves the effort one step: `S` down, `L` up, along `low medium high xhigh max`, held at the ends; `M` keeps it. A size needs NAME (exit 2 without it); the start line then also carries `"size":"S"|"M"|"L"`, and `retro.py kinds` groups an S or L start as `build:S`/`build:L` (M with the bare kind). **An advisor**: config `plan.advisor.KIND` (`fable`, `opus` or `sonnet`; unset, the default, is off) adds ` --advisor A` after the effort, and `"advisor":A` to the start line (`kinds` groups it as `build+fable`), only where it pairs with the model (lib.sh `advisor_ok`: opus takes fable or opus, sonnet and haiku any, fable none; fable only under an account `fable.accounts` lists); else it is left off with one stderr line saying why. `--successor` and `--handover` carry the old session's advisor (its last reply's `advisorModel`) where it still pairs with the successor's model, and a coordinator's start (`coord_start`) takes `plan.advisor.coordinator` the same way. **Tools a task goes without**: every KIND but `coordinator` ends with ` --disallowedTools=…` (lib.sh `denied_tools`; `--plan --next` puts the same on each chunk's line; a Desktop sidebar start, `start_session`, takes only the model and effort, so it keeps every tool): `AskUserQuestion` and `ScheduleWakeup` (a task asks through reply, and a background command or a message wakes it), `Agent` too except for `research` and `review`, and `EnterWorktree` where the project root has `.worktrees/` (worktrees made with `git worktree add`). Each would ride on every request of the session unused. The `=` form keeps a list from taking the brief that follows as one more tool. **Ownership on start**: a NAME starting with a task key runs `--claim` on it first, except for `review`, `retro`, `research` and `coordinator`, its lines on stderr; its exit 3 is `--kind`'s, with nothing on stdout: don't start, queue the ask it names. `--anyway` passes on to it |
| `session-status --claim KEY\|NAME [--anyway]` | Ownership on start, before a task's `claude --bg`; `--kind` runs it. KEY is the argument (`#N` for a GitHub issue, which no session name carries), or the task key a session name starts with (none: exit 0, nothing checked). **Stops** (exit 3, the reasons as `KEY: REASON` lines, then `not started: queue the ask (ask_approval: "KEY: REASON: start anyway on a separate branch / leave it"); on start anyway, run: …`, the rerun line, `--kind`'s own when it ran `--claim`) when the adapter's `owner KEY` says `other`, or a branch on origin whose key (the key pattern's first match in its name) is KEY, after `git fetch --prune` in each of the project's repos with an origin, has non-merge commits past the default branch, not all of them already in it (`git cherry`), by an author email other than the repo's `user.email` (named in the reason). When `owner` says `me`, such a branch is only noted (`KEY: note: …`): a web-UI merge, another address of yours or a reviewer's fixup. **`--anyway`** (the user's "start anyway"): the reasons, then `KEY: starting anyway, not claimed: …` and exit 0; brief the session to work on a new branch of its own; it never claims, even with nothing to stop. Otherwise `me` prints `KEY: yours`; `none` runs the adapter's `claim KEY` (the start is the user's yes to an unassigned task) and prints `KEY: claimed`, `KEY: unassigned (the adapter can't claim)` (exit 2) or `KEY: claim failed (exit N): …`, still exit 0. An `owner` the adapter doesn't answer (no adapter, exit 2) checks the branches only; a failed one prints `KEY: ownership not checked (…)` and claims nothing. A failed fetch says so and uses the branches of the last fetch |
| `session-status --launch NAME --kind KIND[:S\|M\|L] [--anyway] [--at WHEN \| --after-reset [ACCOUNT]] [--] 'WHAT' 'WHY' 'DONE-WHEN' \| --brief-file FILE` | A task start in one command. Runs `--kind KIND NAME [--anyway]` (the claim, the usage start line; its exit 3 and 2 are `--launch`'s, nothing started, and the ask's rerun line names `--launch`), builds the brief (`Work on KEY: WHAT. Why: WHY. Done when: DONE-WHEN. Read MEMORY first. Keep working until done or blocked. When finished: reply with done and the check that proves it.`; KEY: the task key NAME starts with, else NAME; MEMORY: the path CLAUDE.md or CLAUDE.local.md gives as `Project memory`, the sentence left out with none) and runs `claude --bg` with the flags, `-n NAME` and the brief, under the caller's account. Prints `started "NAME" (ID8) · KIND M/E`, or `"NAME" didn't start: …` (exit 1). In Desktop (`CLAUDE_CODE_ENTRYPOINT` `claude-desktop*`) with config `start.sidebar` true it starts nothing and prints `Desktop with start.sidebar: call mcp__ccd_session__start_session … with title "NAME", model "M", effort "E", prompt: BRIEF` (exit 0). **`--brief-file FILE`** in place of the three texts: FILE's text is the first prompt verbatim (no Read MEMORY line added), kept with a scheduled start. Exit 2: a wrong name, kind or count of texts, an empty or unreadable FILE; kind `review` for a name `KEY-<more>` unless `--brief-file` whose text starts `Session task: KEY review`; kind `coordinator` but for a `KEY-coordinator` name with `--brief-file` (a sub-coordinator; others start by `--successor`, `--coordinator-of`). **`--at 'HH:MM'`** (today, tomorrow when that is past) **or `'YYYY-MM-DD HH:MM'`**, local time, **or `--after-reset [ACCOUNT]`** (that account's weekly reset plus a minute, from its last reading; ACCOUNT is its config dir, starting with `/` or `~`, default the caller's; no reading: exit 2, pass `--at`): queued instead, in the person's own cache (never shared), printing `scheduled "NAME" · KIND · MM-DD HH:MM`. A running `--watch` starts it within a minute of its time (`--kind` runs then, so the model and the claim are that moment's) and wakes with `Scheduled start (due MM-DD HH:MM): started …`; one past due starts at the next tick, a successor's watcher included. A start that fails stays queued, marked `failed: REASON`: reported once, never retried by the watcher. The plain sweep lists the queued ones under `Scheduled starts` (`NAME · KIND · MM-DD HH:MM`, plus `· after ~ACCOUNT's weekly reset` and `· failed: REASON`), which the pane shows (section slug `scheduled-starts`); `--changes` doesn't |
| `session-status --launch --list \| --cancel NAME \| --now NAME [--anyway]` | The queued starts, one a line; drop one (`cancelled: …`); start one at once, a failed one too (`--anyway`: the user's "start anyway" after `--claim` stopped it). Exit 2 with no queued start of that name |
| `session-status --land BRANCH` | Fast-forwards BRANCH, checked out in another worktree (the main checkout), to HEAD, and that checkout's files with it (`git push --receive-pack='git -c receive.denyCurrentBranch=updateInstead receive-pack' . HEAD:BRANCH`): a worker's approved landing in a project that lands by fast-forward, from a worktree-isolated session; approved-action.sh gates it as `merge BRANCH`. No force; refused while that checkout has uncommitted changes ([worker.md](worker.md#posting-and-merging)) |
| `session-status --init [--check \| --write [--delegate] [--own] [KEY=VALUE…]]` | Sets the cwd up for coordination (skill `setting-up-coordination`); its `session-init` holds the details. `--check`: one line, exit 0 configured (plus the `active:` line, an indented start line per feature doc, the `review_inbox url:` open_pane watches, the `notify after: N min` its ask notification reads, and any config warnings) (its own adapter here and a "Replies folder" line in `CLAUDE.md`/`CLAUDE.local.md`), 1 unconfigured or partial, 3 covered by a parent's adapter. No flag: the numbered proposal. `--write`: the missing files from `templates/` and the config, never over an existing one, excluded through `.git/info/exclude`. One GitHub repo with `gh` gets `templates/github-adapter` (PR words from two `gh pr list` queries, open and merged, cached for a minute; `done`, `urls`; self-test `github-adapter.test.sh`), anything else the minimal adapter. `--team-memory`: the prune's gather of `[team]` memory lines into a team PR ([memory-rules.md](memory-rules.md), Team memory). No tracker or model call |
| `session-status --pending` | The adapter's `pending` text, nothing else. The coordinator pane shows it |
| `session-status --pending-done LABEL [--] REASON` | With config `pending.file` (the handoff file, FILE = `DIR/NAME.md`): archives the entry labelled LABEL (the text after its date up to the first ` (` or `:`; exact, else a unique prefix; exit 2 listing the labels otherwise). Its `NAME/SLUG.history.md` gets `resolved: REASON` and moves with `NAME/SLUG.md` (its detail, if any) to `NAME-archive/`; `NAME-archive.md` gets `- ADDED → RESOLVED TEXT · reason: REASON → NAME-archive/SLUG.history.md`, sorted by resolved time; then the line leaves FILE. Each file is a copy swapped in with `mv`, under a lock the hook shares |
| `session-status --pending-history LABEL [--last N] \| --find KEY \| --scan \| --seed` | An entry's history (open or archived), or its header and last N lines. `--find KEY`: the path of the history whose label names KEY (`--handover` names it in the successor's prompt, as on-demand reading). `--scan`: every version of FILE seen in the project's transcripts, every account, diffed oldest first as `TIME ID8 LABEL SLUG change\|gone LINE\|REASON` (REASON: the first sentence of that turn's text naming the label with a resolution word, else `unknown`); a fixture with the same header elsewhere doesn't count. A version is a full Read or Write, an Edit replayed onto the last one when that one holds the Edit's patch context, else the patch's lines before and after it (only hunks touching a known entry; an entry is gone once the patches removed all its lines). A Bash command that writes FILE (sed -i, a redirect, a script's write) prints `TIME ID8 gap COMMAND` with LABEL and SLUG empty, and marks the last version stale (as does an Edit whose patch context it lacks): what it wrote counts once a later version shows it. `--seed`, once when adopting: writes the scan out as histories and archive lines. Where FILE's folder has a local git history with FILE's commits (`--git-history` below), `--scan` and `--seed` take its versions from `git log` instead of the transcripts (a gone entry's reason is then `unknown`), and `history LABEL` merges those versions into the history file's lines. The **pending hook** (PostToolUse on Edit, Write and Bash) does the live part: when FILE's mtime or size moved, each new entry line goes onto its history as `- YYYY-MM-DD HH:MM (ID8) LINE`, the detail file's last line becomes `History: NAME/SLUG.history.md (N changes, K KB)`, and an entry gone from FILE is archived with reason `unknown`. Notices names a detail file past 4 KB. `--yesterday` shows archived entries as `resolved from pending: REASON` events. `pending`, `pending-versions.jq`, `pending-diff.jq`; self-test `pending.test.sh` |
| `session-status --git-history replies\|handoff [GIT ARGS…]` | git (default `log --stat`) on the local history repo holding the replies folder, or `pending.file` (the folder's `NAME*` files only). The **history-git Stop hook** keeps both, and each folder in config `history.dirs`: when a turn ends, whatever changed there (an Edit, a Bash write, another session's reply) becomes one commit per repo, `NAME: FILES` (NAME: the session's name from `$CLAUDE_CONFIG_DIR/sessions/*.json`, else its id8; a `Session: ID` trailer), under a fixed local author, retried for ~5 s while another git holds the index lock; the first run makes the repo. Its git dir is outside the folder, in `$XDG_STATE_HOME/session-orchestration/history/<the folder's path>.git`, so the folder holds no `.git` (a worktree-isolated session writes replies as before; a handoff folder inside a checkout isn't a nested repo). A repo set up by hand is used instead, keeping its history: the folder's own or its parent's, with no remote, never the project's repo or one holding it. One history per file: a folder inside a listed whole folder is committed only to the outer one's repo (a repo of its own in between keeps it separate, and out of the outer one; its earlier outside repo is no longer read), and `--pending-history` (`history-git versions`) and this command find a file's repo by the deepest folder holding it; a listed folder holding the root is skipped. Never pushed: no remote is added and its `pre-push` hook refuses every push. A file over 1 MB goes into the repo's `info/exclude` and out of the index. `history-git`; self-test `history-git.test.sh` |
| `session-status --root` | The project root (where the adapter and `.claude/coordinator-actions.json` are). The pane's project actions run there |
| `session-status --dismiss LINE` | Hides the message behind that Notices line (as printed; a leading `* ` is dropped) from every later sweep, in every session, through the messages module's `messages_dismiss` (Modules). It also takes the line out of the last good lines. A new message with the same words still shows. Pass LINE as one argument, quoted. Exit 1: no current message line is LINE; exit 2: the module can't dismiss (adapter and `(failed)` lines can't be dismissed). The pane's Dismiss runs it. Use it when the user says a notice is handled: a mail stays listed while Outlook has it unread |
| `session-status --urls` / `--agents` | The adapter's `urls` text; the sessions the last sweep saw (id, name, state, command prefix, started, cwd, kind, status, pid). The coordinator pane's links and attach commands |
| `session-status --activity` | What each live session is doing, read fresh from its transcript (no tracker calls, ~1s): id, name, state, transcript written, doing, since, last text line, context tokens, context window, status, kind (tabs; times in epoch seconds). Context tokens are the last main-thread reply's input + cache read + cache creation (of its last message iteration when its usage has iterations: an advisor call splits a turn in two), or a later `/compact`'s postTokens; the window is 1M when the session's model id has `[1m]` or its context already holds more than 200k tokens, else 200k. Doing is its `in_progress` todo (TodoWrite, TaskCreate/TaskUpdate), else its latest tool call's description, else that call in a few words, else its last text line. Since is when that activity started. Then cwd (where it started) and its command prefix. `--activity --all-projects`: every project's live sessions, in every account it asks. `session-activity.jq` |
| `session-status --peek ID [N]` | A session's last N (default 12) main-thread entries as markdown, without attaching: the prompts it got, its own text (each cut to 600 characters), its tool calls as `→ Tool: what` lines, then `_Now: …_` (what `--activity` says it does). ID may be a Claude Code Desktop sidebar id (`local_…`, from the app's session tools): the app's record of it names the session (macOS). `session-peek.jq`. The pane's **Peek** |
| `session-status --search TEXT [DAYS]` | Which session said something, without opening transcripts: one line per hit of TEXT (case- and whitespace-insensitive) in the last DAYS (default 7) of every project and account, newest first, as `NAME (ID8) · YYYY-MM-DD HH:MM · WHO: SNIPPET` (local time, as `--peek` shows it; a session found under two accounts is one session). WHO is `you` (a prompt), `msg` (a message from another session) or `claude` (the session's own text); tool calls and results, subagents and the calling session aren't searched. The snippet starts up to 80 characters before the hit and is capped at 220, with emails, credentials (`token=…`, `Bearer …`, known key prefixes), long opaque strings (keys, SHAs) masked and the home folder shown as `~` (search `~/…` for it). Masked text is never found. Masking is a heuristic: a secret in plain words (`the password is …`) isn't caught. At most 3 hits a session and 30 lines, then `… N more (sessions: M)`; exit 1 with no hit. `--peek ID` reads around a hit. `retro.py search` |
| `session-status --yesterday [DAY] [--json]` | The daily brief, from the start of DAY (YYYY-MM-DD; default the last working day: the latest weekday before today with a prompt of the user's in a project transcript or a commit of theirs, within 14 days) up to now, so Monday's covers Friday and the weekend. It is data first: `--json` prints it (The brief, below), the text is a view of that data. `Since: DAY WEEKDAY (HOW)`, a `Lookup failed: TEXT` line per failure, then the sections that have something: `MOVED`, `WAITS ON YOU`, `YOU WAIT ON`, `NEW FOR YOU`, `WORKED ON`, one line per task, the latest first (`KEY TITLE — what happened; …`: sessions as a count, of what moved or was said only the latest from each source, the people a text doesn't name in brackets; sessions under no task as one `N sessions on no task` line). When the adapter has a `standup-template`: `STANDUP` and the text `standup-summary` writes from the data (`not written: REASON` when that fails). `session-day.jq`, `session-brief.jq`. The pane's **brief** tab |
| `session-status --dir KEY\|ID…` / `--diff KEY\|ID…` | Where a task or session works: a KEY's worktree, else an ID's (a Desktop `local_…` id too, as `--peek`) latest transcript cwd (it follows `cd` and EnterWorktree) as its git top; the first argument that resolves. `--diff` prints `DIR · vs BASE`, `git diff --stat` against the merge-base with the first of `origin/HEAD`, `origin/main`, `origin/master`, `@{upstream}` (none: the uncommitted changes against HEAD), the untracked `?? FILE`s, a blank line, then the patch (cut at 200k; the pane draws 40k). A session that works in a worktree by absolute path (`git -C`) without `cd` resolves to its start folder: pass its task key. The pane's **Diff** |

### The brief

`session-status --yesterday --json` prints one JSON object; `jq --arg mode check -f session-brief.jq` checks one
against this format (exit 1 and what is wrong on stderr):

```
{since: "YYYY-MM-DD", from: EPOCH, how: "last working day" | "picked", notes: [TEXT], template: TEXT,
 failed: [TEXT], tasks: {KEY: {status, title}}, items: [ITEM]}
ITEM = {kind, key, people: [NAME], source, at: EPOCH, text}
```

`notes` and `template` are the adapter's `standup-notes` and `standup-template` (`""`: none, so no standup),
`failed` what couldn't be looked up, `tasks` the status and title of the keys the adapter knows. An item is one fact:
`key` its task (`""`: none; a session that names no key has `"NAME"`), `people` who else is in it, `source` where it
comes from as a lowercase word (`session`, `commit`, `pending`, `pr`, `jira`, `teams`, `mail`, `deploy`…), `at` when
(seconds), `text` one line. Its `kind` says what it is to the user:

| Kind | Meaning | Section |
|---|---|---|
| `worked` | The user worked on it: a session active in the window (`session "NAME" (from–to): its last text line`, keyed by its first prompt's key and its `Session task:` markers; the coordinator is left out), their own commits per branch, pushed or not | Worked on |
| `moved` | It changed state: merged, deployed, a status move, a pending entry resolved | Moved |
| `comment` | Someone else commented on or reviewed it | Moved |
| `discussed` | The user talked about it with `people` | (list and standup only) |
| `asked` | The user asked `people` for something | You wait on |
| `waiting` | It waits on someone else: a human review, a merge | You wait on |
| `todo` | It needs the user or their sessions: a ticket to start or continue, a question they were asked | Waits on you |
| `new` | New for the user: a direct message, a mention, a ticket assigned to them | New for you |

The plugin itself supplies the sessions and commits (`worked`), the resolved pending entries (`moved`, source
`pending`) and the messages module's current lines (`new`, source `teams` or `mail`). Everything else is the
adapter's `brief`.

### Plans and chunks

`--plan FILE` reads the first Markdown table under a heading matching `^## (Build )?[Pp]lan` (the table must sit in that
heading's own section). Columns, in order: `# | Chunk | Kind | Deps | Touches | Est | Model/effort | Done when`.
`#` is a number, a letter allowed (`3b`); Deps is `–` or a comma list (`1, 2` or `c1`); Touches a comma list of backticked
paths or globs; Est like `60K`, the growth in context the chunk is expected to add; Model/effort like `opus/medium`, or
`default` for `plan.models.<kind>`. Kind is `design`, `build`, `mechanical`, `review`, `release` or `scan`.

- **Alone**: the waves (a chunk's wave is 1 + the latest wave of its deps) and each chunk's state: `done` when
  `KEY-build.md` has any `## cN: done` (as `--handover`), else `running` while a live session (any listed account) is
  named `KEY-cN` (a `KEY-cN-prev-K` name isn't), else `handoff` when it has a `## cN: handoff` heading, else
  `ready`, `waiting` or `blocked`.
- **`--check`**: one line per problem, exit 1; errors go to stderr (exit 2). It reports: a row with the wrong number of
  cells, a duplicate `#`, an unknown dep, an unknown kind, an empty done-when, a model/effort that isn't a model and one of
  `low medium high xhigh max` (`fable` only under an account config `fable.accounts` lists: `config` and `--handover`'s flags use the same rule, lib.sh `model_ok`), an est
  that isn't like `60K`, an est over `handoff.at.chunk` minus 60K (the room a chunk starts with), a dependency cycle, and
  two chunks that may run at once (neither depends on the other, directly or not) whose touches overlap. A context window
  other than `compact.window` adds one info line on stderr, `window W from SOURCE; expected X`, and alone doesn't fail.
- **`--next`**: the waves, then a `claude --bg` line per runnable chunk (deps done, own state not done), up to
  `plan.max_parallel` (default 3). It takes 2 at most when chunks share a top-level directory in their touches (the first, then the first in other directories, looking past `plan.max_parallel`), a bare
  file name counting as the directory `.`; it skips a chunk whose touches overlap one already picked. A `running` chunk
  isn't listed; it counts against `plan.max_parallel`, the top-level-directory cap and the touch overlap. A chunk that
  was started but has no live `KEY-cN` session and no `## cN: done` (it died, or handed off) is listed again: that's its
  successor's launch. A listing that failed for an account adds a stderr line (`couldn't list an account's sessions: …`). It doesn't check that the briefs exist, and it skips a row whose model/effort `--check` reports.
  With `plan.enabled: false` it prints `plan.enabled is false: run tasks without a plan` and no `claude --bg` line. An account whose settings default to plan mode gets `--permission-mode default`, as `--handover`.
- **`--brief N`**: a skeleton for row N's brief (title, kind, model, est, deps, wave, touches, done-when) to finish by hand.
- **`--done N`**: run by chunk N once it landed. With `telemetry` `local` or `full` (the default) it appends a `chunk` line to the usage log
  (`{"k":"chunk","what":KIND,"model":…,"effort":…,"est":K,"act":K}`; act is the growth of this session and
  the predecessors its `Supersedes:` chain reaches, from `retro.py chunks 7 --session`, left out when there's no session id
  or retro fails); it prints the line, or why nothing was logged (telemetry off, a bad est or model/effort). `retro.py chunks`
  joins each line to the chunk whose own `--done` printed it (by its `t`), and reads them for its ratio.

State lives in `KEY-build.md` in the plan file's own folder (KEY: the plan file's name without `.md`): a chunk appends
`## cN: done` when it lands, or `## cN: handoff` when it stops early. Nothing else marks state. `--handover` and the
context-watch hook look for it in the replies folder, so keep plans in the replies folder.

A chunk session's own steps: [worker.md](worker.md#chunk-sessions).

## Context watch

`hooks/context-watch.sh` (PostToolUse, UserPromptSubmit, and SessionStart after a compaction or resume) asks a session
to hand off before it compacts. A session's context is read from its transcript's tail; the thresholds come from the
`handoff.*` and `compact.window` keys ([Config](../setting-up-coordination/SKILL.md#config)). Its kind comes from the first
prompt: `Chunk: KEY/N` is a chunk, `Act as a coordinator` a coordinator (so is a session whose tail ran the status
watcher or opened the pane), `Session task: KEY review` a review (no messages), a `Session task:` line or a
`Work on KEY` start a task.

- **Soft** (past `handoff.at.<kind>`): once, "hand off": reach your stop point, write the handoff (a chunk: `## cN: handoff ID8`
  appended to `KEY-build.md`; a task: `## Handoff` in its replies file; either, when its task changes files
  and it has edited none yet, with the edits it decided on as text), then hand itself over with
  `session-status --handover --self` (coordinator or not), rename itself to the `-prev-K` name it prints and end the
  turn. It doesn't hand over, and messages the coordinator `handoff ready: KEY[ cN]` instead, when the handoff makes no
  progress or a chunk is past 2× its est (the coordinator may escalate), and when `--self` fails. A coordinator is told to write its handover note and start its successor with
  `session-status --successor`, then follow what it prints ([handover.md](handover.md)): it hands itself over without the
  user, and the coordinator inbox holds what workers send meanwhile.
- **Hard** (past `handoff.hard_after` further, never closer than `handoff.stop_room` to the compaction): once, "stop now",
  from what's on disk, and a task or chunk's decided edits as the soft line asks.
- **Window mismatch**: the thresholds assume `compact.window`. The session's actual window is `$CLAUDE_CODE_AUTO_COMPACT_WINDOW`,
  else `autoCompactWindow` in the project's `.claude/settings.local.json`, its `.claude/settings.json`, then the user's
  `settings.json` (SOURCE `env`, `project`, `settings`); when it differs, one line (`This session's window is W from SOURCE; expected X.`)
  is added to the first message. When none of them sets it (SOURCE `config`), that line says no `autoCompactWindow` is
  set: the marks are a guess, and a 1M-context model compacts near 1M.
- **After a compaction**, chunks only: "you were compacted mid-chunk": write the handoff from what's on disk and stop, once
  per session. A compaction or resume clears the soft and hard stamps, and a resume the cached thresholds too.
- **Skipped**: a session with no `Session task:` line that isn't a coordinator, a subagent's calls, and a kind with its
  `handoff.at.<kind>` at 0. Thresholds are cached per session at its first firing, so a config change reaches the next one.
- **Edge cases**: a bare `KEY:` start is a task only in a coordinated project (an adapter or `key_pattern`); a window too
  small for `handoff.stop_room` hands off at 60% of what's left before compaction (window − 33000) and stops at 80%
  (the window line says so), and a window of 0 is
  unknown (config's thresholds); a keyless session that writes `Session task: KEY` becomes that task at its `name_session` call.

## The adapter

A project plugs in its tracker and code host with one executable, `.claude/session-status-adapter`
in the project root (found by walking up from the cwd). Without one, a committed
`.claude/coordination/session-status-adapter` (shared mode) runs once the person trusts it (Modules, below). It's
called with the cwd at the root:

| Call | Prints |
|------|--------|
| `tasks [ARG…]` | `KEY<TAB>STATUS<TAB>TITLE<TAB>EXTRA` per task, in display order. EXTRA (PRs, conflicts, hints) is printed as is before the worktree column, so it ends with its own separator (`\| `). The pane reads the words in the table below from it. On failure: exit non-zero, message on stdout; the board prints without tracker columns under `adapter tasks failed (exit N): MESSAGE` (none: the last stderr line), and `--changes` exits 1 with it instead. Exit 2 with nothing on stderr means not answered (a syntax error exits 2 too, but says so on stderr): rows come from session names and worktree branches, as with no adapter, so an adapter answering only `pending`, `urls` or `key-pattern` needs no `tasks`. After such a sweep, the keys sessions and worktrees point at are asked about: those `done` reports go to Leftovers, the rest are looked up with `tasks KEY…`, whose rows on exit 0 replace the bare ones. A `fix: LABEL → COMMAND` line, on success or failure, is printed after the rows and becomes a pane action (Project actions) |
| `done KEY…` | `KEY[<TAB>LABEL]` for the finished ones; drives Leftovers and Resolved. A key it names (or a `done` reply finishes, below) stays open while a worktree on branch `KEY-N` (N digits: the task's next PR) is neither named by `done` nor clean and all landed. A key `done` doesn't name that has no row, or whose row has no status or PR words when `tasks` with no keys doesn't answer (the rows are then the sessions' and branches' keys), is finished too once its owner's or a session named for it (not a review's, not under a sub-coordinator) last sent a `done` reply for that key that the reply tool let through: `done: report` with no prompt since (`KEY reported done`), or `done: pr`/`pushed` whose named worktree is clean, off the default branch and all landed (`KEY landed`; an open PR never is). So a PR on a branch without the key, or a no-code spike, still reaches Leftovers and the watcher's stop |
| `key-pattern` | One ERE for a task key. Default `[A-Z][A-Z0-9]+-[0-9]+` |
| `status-names` | Regex of the project's own status-command names (its wrapper), counted like `session-status` |
| `repos` | Git repos holding the worktrees, relative to the root. Default: the root if it's a repo, else its child repos |
| `pending` | The coordinator's handoff text (decisions waiting on the user, open requests), e.g. `cat` of the project's pending file. Shown in the coordinator pane |
| `urls` | Link templates for the coordinator pane, one per line: `ticket https://…/{key}` and `pr https://…/repos/{repo}/pull-requests/{id}` (a PR shows in EXTRA as `repo#id`) |
| `brief EPOCH KEY…` | The project's side of the daily brief (`--yesterday`) since EPOCH (seconds), for the given keys and whatever else concerns the user: the tracker, the code host, the chats. One JSON object per line: an item (The brief: `kind`, `source`, `at`, `text`, and `key` and `people` when it has them) or a task's head `{"task": KEY, "status": …, "title": …}`. A line that isn't JSON is a failure message: it shows as `Lookup failed: TEXT` and the rest still counts, so one source that is down doesn't lose the others. An object that is no item is named there too. Exit 1: the lookup failed, its message on stdout; any other non-zero: not supported, and `yesterday` is asked instead. Optional |
| `yesterday EPOCH KEY…` | The older form of `brief`, still read when `brief` isn't answered (and by the retro run for merges): per task `KEY<TAB>STATUS<TAB>TITLE`, then `  EPOCH<TAB>TEXT` events (PRs opened, merged, reviewed; status moves; comments). Its events become `moved` items of source `tracker`. Exit 1: the lookup failed, its message on stdout; any other non-zero: not supported |
| `standup-template` | The standup the user gives, as text with `<…>` placeholders that say what goes where (`Yesterday I worked on <tasks with commits>, discussed <tasks> with <people>. Today I will work on <tasks that need me>.`). With it, `--yesterday` and the pane's brief tab add a standup: `standup-summary` fills the template from the brief's items. Without it there is the brief only. Optional |
| `standup-notes` | Facts the standup should know about the project, one per line (e.g. a known-down environment it must not mention). They are the brief's `notes`; the standup follows them and never repeats them. Optional |
| `session-dirs` | More directories (absolute or `~/…`, one per line) whose sessions belong to the project, e.g. a tooling repo its coordinator starts sessions in. Their sessions never own a task: they show under Other sessions. Default: the root only |
| `mine` | The person's own task keys, one per line (whose messages the coordinator forwards: a messages module's `mine` field; default the keys of the last sweep's rows). The GitHub template lists the keys of your open PRs and `#N` of open issues assigned to you, or unassigned and closed by one of your PRs. Optional |
| `notices` | Short lines about things outside the tracker (a new chat message, a mention), one per item. Sweep only, run in parallel with `tasks`, printed under a **Notices** footer. Keep a line identical while its item is unchanged. `--changes` reports a new or changed notice but not one that went away, so reading a message doesn't wake the watcher. Chat and mail belong in a messages module (Modules), whose lines come first |
| `owner KEY…` | `KEY<TAB>me\|other\|none` per key: whose the task is (the tracker's assignee, or a PR's author for a task with no ticket). `session-status --claim` stops a start on `other` and claims on `none`. The GitHub template answers `#N` by the issue's assignees (an unreadable issue goes unanswered), any other key by the authors of its open PRs (`other` when any of them isn't you). Optional |
| `claim KEY` | Assigns KEY to the person (a state change, not a post); run by `--claim` on `none`. Exit 2: nothing to assign. The GitHub template assigns issue `#N` to `@me`, other keys exit 2. Optional |
| `pr-keys REPO#ID` | The task keys a PR refers to (its branch and title), one per line, for a messages module that finds a PR link in a message. Exit 1: not found. Optional |

A call it doesn't answer exits non-zero and the default applies (`tasks`: exit 2, above).

## Words the pane reads in EXTRA

Words and phrases set off by spaces; anything else shows only in a task's details.

| Word | Means | In the pane |
|------|-------|-------------|
| `REPO#ID OPEN` / `REPO#ID MERGED` | A PR and its state | OPEN: In review, or Landing once approved. MERGED with no open PR and the task not in a test/done status: Needs action |
| `+NAME` or `approved by NAME` | NAME approved the PR | Landing (when nothing needs fixing and no `no-human-approval`) |
| `!NAME` or `changes requested by NAME` | NAME asked for changes | Needs action, **Address comments** (its PR review comments) |
| `no-human-approval` | Open, waiting for a reviewer | In review |
| `CONFLICT` | Merge conflict | Needs action, **Resolve conflicts** |
| `CI-FAILED` | The PR's latest build failed | Needs action, **Fix CI** |
| `↩MM-DD NAME→STATUS` | The tracker sent the task back | Needs action (Ask the session why) |
| `(PRs as of HH:MM)` | The PR words are from that time (a lookup failed) | Shown as stale; `--changes` ignores it appearing or clearing |

The phrases `approved by NAME` and `changes requested by NAME` read without a legend and take any GitHub login; `+NAME` and `!NAME` need a letter first, so `+1` is no reviewer.

## Without an adapter, and task ownership

Without an adapter, rows are the keys in running sessions' names and worktree branches (no tracker
status; Leftovers only from the sessions' own done reports, below). Transcripts that ran `session-status` (or a `status-names` command) with
`--start`, `--changes`, `--watch` or `--owner`, or that called `open_pane`, are a coordinator's and never own a task; a plain run (a worker checking its
own task) or reading the docs doesn't count. **Owner:** the key a session's first prompt starts with
(`Work on KEY`, `Session task: KEY`, `KEY:` on its first line; a key further on, history or an
example, doesn't count), else a `Session task: KEY` marker. A first-prompt owner beats a marker owner
however recent the marker; among equals the newest transcript wins. With neither, the row reads
`sess:—`, and `sess:— (maybe ID: N mentions)` when one worker names the key at least 10 times in its
own text and the prompts it received (tool output doesn't count): a guess, never an owner, that the
pane shows as no session. `--changes` ignores the guess. `session-status --owner KEY` lists every
candidate with its rule. A `Session task: KEY` marker counts in a session's own text and in
the messages it received (its prompts, a SendMessage brief), never in its tool inputs (a brief it sends
names another session's task). A review session (`Session task: KEY review`, "review" ending the
marker) never owns KEY: it shows under Other sessions as `reviews KEY`. A session in a `session-dirs`
directory never owns a task. The `maybe` guess skips reviewers and any session whose first prompt names
another key. **Superseded:** a `Supersedes: <id>` line in a session's first prompt (`--handover` writes
it), or a brief's `You replace session <id>` (8 characters are enough when one transcript starts with
them), marks `<id>` replaced by that session. A superseded session never owns a task, not even when it is
resumed later and its transcript is the newest, nor shows as a leftover: under Other sessions it reads
`· superseded by <new id>`, and the pane tags it so. `bash session-status.test.sh` checks the no-adapter path.

## The pane in detail

The pane parses the status output and the pending text into groups, as Claude Code Projects'
Overview does: **Waiting on you** first (the sessions waiting on the user, then pending items on the
user that no session there covers but a live session is behind: the item names its id, or its task's
row has a live owner), then **Decisions** (the pending items on the user with no live session behind
them), both counted in the header; then **Answers** (with `features.answers` on, the coordinator's unread answers
to the user: [features/answers.md](../../features/answers.md)); then the tasks, each in one group:
**Needs action** (blocked on you, or a problem someone has to act on: conflict, failed CI, changes
asked, sent back, merged but not Ready for Test, unpushed commits), **In review** (an open PR waiting
on reviewers: Projects' Ready for review), **Working** (its session is running), **Landing** (an open
PR approved, nothing to fix: waiting for the merge decision), **Idle** (the rest). Each row is a chip
and a few plain words read from EXTRA (the table above). Every session row also shows its context
fill, `ctx 62%` (dim; amber from 80%, red from 90%), and an idle background session's card has
**Compact** (`z`, `--compact`). A task's working session says what it's doing and for how long
(`Running the tests · 5m`, from `--activity`, refreshed every minute) and is flagged `no output for
12m` once its transcript has been quiet over 10 minutes. **Other sessions** lists the sessions that
own no task (running first, a review led by its task key), with the same progress, or the last line
of an idle one; pressed, attach, the ticket link and Ask. Then the other status footers, the pending
file's `- ` items Waiting on you and Decisions don't already show, and **Resolved** last. Each section is open (its
rows, one line each: a pressed one opens as a card and wraps), one line (its title and count alone) or hidden (not
drawn; a dim `hidden: pending 15` line at the end names those, and a press on it shows them in this pane). Config
`pane.sections` sets them per project, by slug (the title in lowercase, `-` for spaces, without its `(…)`:
`waiting-on-you`, `other-sessions`, `resolved`); unset, every section is open but Resolved, one line. A press on a
title toggles open and one line and writes it (`session-status --pane-section SLUG STATE`; a section the config can't
name, an adapter's footer, folds for this pane only, as does a failed write, which says so in a toast). Once shown, a
hidden section's title press folds and writes it like any other, so it is no longer hidden, and the last line
(`shown: … · hide`) hides them again.
Waiting on you, Decisions and Needs action are never hidden: there `hidden` reads as one line, with a warning
from `--config pane.sections`. Folded to one line, they still draw the items new since their title was last pressed
(open or fold), Waiting on you's and Decisions' with their digit keys, and the title says `· N new` in the warning colour; a title press marks every
item there seen. An item is its session's name (Waiting on you), its pending entry's text (Waiting on you, Decisions) or its
key and chip (Needs action). The seen ids are kept per project root in `~/.cache/session-status/seen/`, like the
asks, so a new coordinator's pane doesn't show everything as new; a section folded before it has any (set in the
config, never pressed) takes what it holds when first drawn as seen. The rows a fold leaves out get no digit. Above the groups, **▶ RUN** lists
the commands sessions handed the user (`hand_command`), per task key, each counted on you under its
task, with Run, Copy and Dismiss buttons (no key): pane.md, Handed-over commands.

Both refresh every 10 minutes and on its refresh button (`r` while the pane has focus). Pressing an
item opens it as a card (a box with its details and actions): attach (copies the command), the
ticket and PR links (from the adapter's `urls`), the fixes that apply (Resolve conflicts, Fix CI,
Address comments: see pane.md, Card actions), refresh that row, dismiss a notice (for every
session), copy a leftover's cleanup command, and Ask. A session's card (a task's, a waiting or other
session's) also has **Peek** (`p`: its last turns and what it does now, under the card, without
attaching), **Diff** (`d`: its worktree's files and stat against the base; **▸ Patch** draws each
file's hunks, up to 40k characters, the rest named), and, with a `terminal` configured (not `plain`),
**Attach in tab** (`t`: `claude attach` under the session's account and in its folder; first on a card that waits on
the user) and **Logs in split** (`l`: `claude logs` beside it); neither on an interactive session. Both run
`session-status --open view|split …` (Modules, below): when the terminal opens nothing (exit 2) the pane copies the
command and says why, another failure shows as a toast. What the terminal does is in its doc
(`terminals/<name>.md`). A waiting card whose background session is on a permission prompt its hook still waits on
leads with **Allow this call** (`h`) under the call it runs, shown in full: the press answers that prompt for that
one call ([resuming.md](resuming.md#permission-prompts-and-trust)). One Peek or Diff shows at a time; a second press or closing the card hides it. The header's
**all projects** toggle (`w`) also reads every other project's live sessions, in every account it asks, into an
**Other projects** section (project folder, what it does, attach with its account prefix, Peek, Diff). The header's **brief** toggle (`y`) swaps the task board for the daily brief
(`session-status --yesterday --json`, about half a minute with the tracker and the chats; The brief, above): the
sections **Moved**, **Waits on you**, **You wait on**, **New for you** and **Worked on**, each a row per task saying
what happened to it, the latest first. A row opens to that task's own list: every item of it, oldest first, as
`WEEKDAY HH:MM source text (people)`, and its ticket link. `s` swaps the brief for the list of every task (**Tasks**:
key, status, title, then its items) and back. `b` and `n` step the start day a weekday back or on (on to today: the
last working day again); `r` reads it again. When the brief has a template (the adapter's `standup-template`),
`standup-summary` writes the standup from the brief's items after it (by `claude -p --model haiku` with no tools,
plugins or transcript: about $0.003 and 5–15s a run; another model with `SESSION_STATUS_SUMMARY_MODEL`), shown in a
box above the brief or the list. It names work in a few plain words (a tracker key may stay), never by session name or
task id, and follows the adapter's `standup-notes`. It's cached per start day under
`~/.cache/session-orchestration/standup/` and written again only when that day's data changes (sessions' spans and
last lines left out, they move at every refresh; the model, prompt and template count). While a refresh checks it,
the day's last standup stays up; when the call fails or passes 90s, the reason shows in its place. A project without
a template gets the brief alone, and no model runs. With the pane focused (ctrl+x tab), `1`–`9`
select the Waiting on you items, then the Decisions, in order. Once the pane is open, the status line under the prompt
carries the header's count (`◆ N on you`), so it shows while the pane is hidden. The pane only
exists in an interactive session that has the plugin loaded. The agent view (`claude agents`) can't
show plugin panes. In a terminal narrower than about 144 columns (110 once the user has opened the pane themselves)
the pane waits until the window is wider; `/coordinator close` closes it. Under the approvals, **Actions** holds the project's own
commands (below).

### Approval asks

How the pane shows an `ask_approval` ask ([approvals.md](approvals.md)): it reads
the `body_file` when the ask is queued and shows its text as markdown with its sha256 (as written,
if markdown would hide a link target or HTML). Asks are grouped per task key, one line each, until
the user opens one (NEW: never opened). An ask with a kind shows it as a coloured badge; a group
lists its other asks (a merge, a post with no kind) first, then issues, suggestions, questions, and
the group line counts each kind. `details`, `target`, `kind` and `session` (as `Runs in: <it>`, under the action; with no action, a start ask's,
`Starts, may land its PR: <it>`) show only in the pane. A Yes click on an ask with `action` and `session` (**Approve
all N merges…** included) writes its grant (`~/.cache/session-status/grants/act-*.json`; a start ask's land grant,
`land-*.json`, [approvals.md](approvals.md#grants)) before the answer is submitted, and removes it when the answer
isn't sent; any answer for the key removes the action grants of earlier answers for it, never a land grant. The pane refuses an ask whose
question names a sha256 that isn't its `body_file`'s, or names one with no `body_file`, and a `post comment`
question or action, or a close with a comment, with no `body_file`. Queuing the same key and
question again replaces the waiting ask (same id), never a second one. An ask's `still_applies: "OWNER/REPO#N"` (and
a board row's PR its question names) is looked up by every full status run (the pane's refresh, `--start`, the sweep,
`--stale`; 10 s cap), and the Stale section flags the ask `acme/app#45 merged (its still_applies)` once it is merged
or closed; a gh error or timeout flags nothing. An ask queued
over 24h ago stays, marked OLD with its age in the warning colour and, opened, a dim note to the user (not sent
with the answer) that it may be out of date and the coordinator can recheck it. The asks are kept per project root in `~/.cache/session-status/asks/` (one file, the store every
change goes through), so a new coordinator's pane shows what the last one queued; open_pane's result lists them.
With two or more merge asks waiting, the APPROVE box shows **Approve all N merges…**: a confirm naming each, then
one ordinary answer line per ask, as if each Yes were clicked, so each relay verifies for its own key. A merge ask
here: the whole question is the hook's action (`merge app#271`, a trailing `(KEY)` and `?` allowed), exactly one
option starts "Yes", and it has no `details`; OLD and stale ones are left out. The asks are rechecked after the
confirm and claimed together; a toast names any not sent (back in the pane) or changed meanwhile.
An ask the Stale section flags shows `STALE · WHY` on its line and, opened, the reason with **Cancel** (not for age
alone): the ask is dropped and the coordinator told (pane.md, Stale flags). A Pending entry flagged there gets the
same chip and, in its card, **Archive** (`e`; see Stale above for when it's left out). The Stale section itself keeps only the lines with no row of their own
(a session asking with no ask queued). A waiting session whose task has an ask queued says `→ ask N` and isn't
counted on you again. Leftovers' clean+merged worktrees (2 or more) fold into one row whose card copies every
removal (**Clean up all**); Other sessions' superseded ones and those idle a day or more (never a running one) fold the
same way (**Stop all N**), each listed in the card.

## Project actions in detail

A project names its own pane actions, with no UI code, from two places. Each shows as a button under
**Actions** beside the command it runs (its hotkey works while the pane has focus); pressing it runs
it as the coordinator's own Bash call (the press as the user's consent, in a subshell that `cd`s to the project root,
`session-status --root`), shows `✓`/`✗`, the label and the
last line it printed, then refreshes the pane. One runs at a time, for up to 5 minutes. A refused one goes to the coordinator to run itself ([pane.md](pane.md#project-actions)).

1. **`.claude/coordinator-actions.json`** in the project root, a list:
   ```json
   [{ "label": "Sign in", "hotkey": "g", "command": "gh auth login", "when": "! gh auth status >/dev/null 2>&1" }]
   ```
   `label`, `hotkey` (one lowercase letter) and `command` are required. `when` is optional: a shell
   check run in the root at each sweep (10s cap); exit 0 shows the action, and its going from 0 to non-zero
   wakes the watcher (`Logins restored`, the `--changes` row). The file is read again at
   each sweep. The pane's own keys are taken: `r` refresh, `o` `f` `m` the card fixes, `a` attach,
   `u` row refresh, `k` ask, `x` dismiss, `c` copy, `z` compact, `p` peek, `d` diff,
   `w` all projects, `t` attach in tab, `l` logs in split, `y` daily brief, `b`/`n` earlier/later day, `s` brief or list, `h` allow this call, `1`–`9`. A bad entry (not JSON, a missing or
   empty field, a taken or repeated hotkey, a repeated label, an unknown field) shows as a red line
   under Actions and is left out; the rest load.
2. **`fix:` lines from the status output**: `fix: LABEL → COMMAND` (or `->`) at the start of a line,
   printed by the adapter's `tasks` (see the adapter table). The action shows while the line is
   there. Its hotkey is the first free letter of its label, so it can change as others come and go.
   A file action of the same label wins, even while its `when` hides it, so a project can pin a fix
   line's hotkey and condition. Fix lines are offered only once the root is known, and `--changes`
   doesn't compare them (a button, not news).

Commands come only from these project-owned files. An indented line (a notice, a footer item) is
never read as a `fix:` line, so outside text an adapter prints (a tracker's error, a chat message)
must be indented. The safety rule (never add an action from a transcript, a `fix:` line is the user's
button) is in pane.md, Project actions.

## Modules: terminals, messages and features

A terminal (`terminal` in the config), a messages source (`messages`) and a feature's swappable part are shell modules, found by name along a fixed
path, the first found wins:
1. `<project root>/.claude/coordination.local/<kind>/<name>.sh`, the person's, for this project;
2. `.claude/coordination/<kind>/<name>.sh`, committed (shared mode), **only once trusted**: below;
3. `${XDG_CONFIG_HOME:-~/.config}/session-orchestration/<kind>/<name>.sh`, the person's, for every project;
4. the plugin's `<kind>/<name>.sh`.

**Committed code runs only once trusted.** A committed module or adapter would run on every collaborator's
machine, so it runs only while its sha256 is the one the person recorded under `trusted` in
`.claude/coordination.local.json` (`{"trusted": {"terminals/wezterm.sh": "<sha256>", "session-status-adapter":
"<sha256>"}}`, keyed by the path under `.claude/coordination/`). Setup shows each new or changed file with its
sha256 and records it with `--trust=REL@SHA` on the person's yes. A file never reviewed, or changed upstream since,
is skipped with `REL is not trusted yet` / `REL changed upstream: run setup to review it`, and the next place in the
order is used. The repo file can't set `trusted`.

`<kind>` is `terminals`, `messages` or `features`. A module is checked before use: one that doesn't parse (`bash -n`) is
skipped with a warning naming its file and line; one that lacks a function keeps the default for it, with a warning;
one that shadows the plugin's own is noted on stderr. `session-status --init --check` prints these warnings. A
module's `<name>.md` beside it, if any, is the doc the check's feature line names: its `> **Start**:` and
`> **Read when**:` lines under the title say what the coordinator does at Start and when it reads the doc (a doc
without them is read whole at Start).

**Messages** modules define `messages_notices`, run in the sweep's notices job beside the adapter's `notices`, from
the project root, with `NOTICE_DIR` (its cache folder), `NOTICE_KEYRE` (the key regex, in parens), `NOTICE_ROWS`
(the last sweep's rows), `NOTICE_MINE` (a file of the person's keys) and `adapter` set. It prints one line per item
and exit 0, or exit 1 with the reason on stdout (the last good lines show, marked failed); it writes each line's
full message to `$NOTICE_DIR/notices.jsonl` (`session-status --messages-file`; `--messages-forward LINE` prints it as a forward), with `mine`: the line's keys in
`NOTICE_MINE`. Optional `messages_dismiss LINE` (with `NOTICE_DIR`, for `--dismiss`): hide the messages behind
that line from later runs; exit 1 when no current line is LINE. The plugin ships `msgraph` (Teams and Outlook, `messages/msgraph.md`).

**Terminals** define two functions, the contract `session-status --open view|split ARGS… -- CMD…` calls:
- `open_view [--account DIR] TITLE DIR CMD…`: run CMD in a new tab or window titled TITLE, in DIR, under that
  Claude account (`CLAUDE_CONFIG_DIR`; absent or `~/.claude` is the default account). With `TERMINAL_QUIET=1` set
  (`--successor`), keep the user's frontmost app and tab: open it behind them, or give them focus back;
- `open_split [--account DIR] DIR CMD…`: run CMD in a split beside the current view.

Return 0 when it opened; 2 when nothing opened, with the reason on stderr (the pane copies CMD); anything else is an
error, shown with stderr. Three more are optional, for a coordinator's handover ([handover.md](handover.md)); a module
without them gets `plain`'s, which return 2:
- `split_tty [--account DIR] TTY DIR CMD…`: run CMD in a split of the tab holding the terminal on TTY, keeping the
  user's frontmost app and tab under `TERMINAL_QUIET=1` (`--successor`; any failure: it opens a tab with `open_view`);
- `title_tty TTY TITLE`: title the tab holding the terminal on TTY (`ttys012`, as `ps -o tty=` prints it), so the
  user sees which tab is the old coordinator (`--prev-name --title`);
- `close_tty TTY`: close that terminal, its whole tab when it is the tab's only one, else only its split; print
  `closed tab` or `closed split`; 1 when no tab holds TTY (`--await done`). `plain` (the default) opens nothing: it prints CMD and returns 2. A WezTerm module, say, as
`~/.config/session-orchestration/terminals/wezterm.sh` with `"terminal": "wezterm"` in the person file:

```bash
open_view() {
  local env=(); [ "$1" != --account ] || { env=(env "CLAUDE_CONFIG_DIR=$2"); shift 2; }
  wezterm cli spawn --cwd "$2" -- ${env[@]+"${env[@]}"} "${@:3}" >/dev/null || return 3
}
open_split() {
  local env=(); [ "$1" != --account ] || { env=(env "CLAUDE_CONFIG_DIR=$2"); shift 2; }
  wezterm cli split-pane --right --cwd "$1" -- ${env[@]+"${env[@]}"} "${@:2}" >/dev/null || return 3
}
```

**Features**: `features/accounts.sh` defines `list_accounts`, one `CLAUDE_CONFIG_DIR` per line, each account whose
`projects/` is this one's; a module of that name replaces the list when `features.accounts` is on.

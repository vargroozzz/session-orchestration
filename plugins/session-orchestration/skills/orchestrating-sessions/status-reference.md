# Status command and pane reference

Read when writing or debugging a project's `session-status-adapter`, editing
`.claude/coordinator-actions.json`, or when a status line, a pane group or a pane word is unclear. The
rules a coordinator acts on every day are in [coordinator.md](coordinator.md).

## Contents

- [Footers in detail](#footers-in-detail)
- [Commands in detail](#commands-in-detail)
- [The adapter](#the-adapter)
- [Words the pane reads in EXTRA](#words-the-pane-reads-in-extra)
- [Without an adapter, and task ownership](#without-an-adapter-and-task-ownership)
- [The pane in detail](#the-pane-in-detail)
- [Project actions in detail](#project-actions-in-detail)
- [Modules: terminals, messages and features](#modules-terminals-messages-and-features)

## Footers in detail

**Waiting on you** shows what a blocked session waits on from the plugin's hooks. A task's worker at rest
(Claude Code reports a background session `blocked` once its turn ends) whose row only waits on a reviewer
(`no-human-approval`, no CONFLICT, CI-FAILED, `!NAME`, `↩` or unpushed commits) isn't listed there: its row
shows it `idle`, so the pane puts the task under In review, not on the user (0.32.1, the user 2026-10-21).
On a prompt or question (status `waiting`, or a hooks/blocked.sh record), or while another row it owns still needs the user, it still is. A `+NAME` on any of the task's PRs makes it the user's
merge call.

The list keeps itself current (0.35.0, the user 2026-10-21: "it should update itself"). Any other blocked
session is on you only while it sits on an open prompt, or its last turn asks the user: a question, a
`! command` for them to run, or words like "your call", "blocked", "decision for you" (in its text or its
SendMessage summaries since the last prompt). A row with CONFLICT or `+NAME` keeps its session on you
regardless. Not on you, first match: busy (a session limit leaves it blocked mid-turn), superseded, a
reviewer at rest (its report is delivered; comments to post wait in the review inbox), its work landed (it
started in a clean worktree whose branch, with a commit made after it started, is merged into origin's
default), or a finished turn that asks nothing. Its row says `idle` or `busy`; one with no row is under Other sessions.
A question needs a `?`, a `! command` line or the words outside code (fenced blocks and `spans` are
skipped). Limits: a turn that asks while its branch has landed counts as landed; a squash-merged branch never
counts as landed; `--changes` still ignores a plain entry appearing (workers report questions by message).
A prompt unanswered for 6 hours (`SESSION_STATUS_STALE_HOURS`) moves to **Stale prompts**, with
`· unanswered Nh; stop: PREFIX stop ID`, and its row says `stale`: answer it or stop the session. The pane
doesn't count those on you and offers Stop on them; `--changes` doesn't compare that section.

**Other sessions**
lists live sessions that own no task row (no task, a reviewer, a session in one of the adapter's
`session-dirs`) and aren't on you (Waiting on you and Stale prompts list those), coordinators left out, one line each:
`"NAME" STATE AGE[ · reviews KEY][ · superseded by NEWID][ — LAST TEXT] (PREFIX attach ID)`. A superseded
session (below) at rest is listed here, not under Waiting on you; on a prompt it still waits on you. AGE counts from its start while
it works, else from its last transcript write; an idle or done one drops off after 3 hours
(`SESSION_STATUS_OTHER_HOURS`). `--changes` doesn't compare that section. A leftover idle a week whose
removal loses nothing (a session, a clean worktree whose commits are merged or on origin) moves to
**Resolved (idle a week)**, so Leftovers empties on its own; `--changes` ignores that section. One with
uncommitted or unpushed work stays a leftover.

**Plugin feedback** comes last, one line: `plugin feedback: N open (M seen ≥2×) — apply? (feedback.md)`, from
`feedback footer` ([feedback.md](feedback.md)). Only a coordinator's sweep shows it (the calling session ran
`--changes`, `--watch` or `--owner`, or opened the pane), at most once a day per person (the stamp
`.footer-shown` in the feedback folder), and only with open cases. Never in the `--changes` child (so the watcher
doesn't wake on it) or the pane's runs, which set `SESSION_STATUS_NO_FEEDBACK=1`.

## Commands in detail

| Command | Shows |
|---------|-------|
| `session-status --changes [args]` | Only lines changed since the last `--changes` run, or `no changes`; idle/busy and ages ignored, and so is a session only entering `working`, flipping between working, idle and blocked, or its worktree's dirty/unpushed counts changing while it works (entering done or closed counts, with the current counts). A plain "Waiting on you" entry appearing doesn't count, nor does one going away while its session lives on; one whose session ended does, and so does one saying what it's `blocked:` on. Emptied section headers aren't printed. State is kept per arg list: while a watcher runs, a manual run with its args consumes its change |
| `session-status --watch [--every SECS] [args]` | Blocks until a change shows at two polls in a row (120s apart, `SESSION_STATUS_CONFIRM_S`), prints it and exits. Checks every SECS (default 1800). A failed poll (Jira/Bitbucket timeout, a jq error) logs one line to stderr and is retried at the next check (120s while a change is being confirmed); 3 in a row (`SESSION_STATUS_WATCH_TRIES`) end it with "gave up after 3 failed polls in a row" and the last error |
| `session-status --handover ID [--] 'WHAT NEXT'` | Hands a task over from a session too big to resume (`--send-when-idle`'s exit 4 prints this command). ID's task key: the one its first prompt or own `Session task:` markers name (exactly one). Refuses (exit 3) while it is mid-turn, waiting on a prompt, or interactive and live; (exit 2) when the replies folder (the project `CLAUDE.md`'s "Replies folder … \`PATH\`" line) has no `KEY.md`. Then stops it (waits up to 30s for its process to end), and runs `claude --bg -n NAME 'Work on KEY: continue from <replies>/KEY.md. WHAT NEXT. Supersedes: ID (transcript PATH; read only the parts you need, never whole).'` from the project root under the same command prefix. NAME is the old name if it starts with KEY, else `KEY-<old name, slugged>`. Prints `handed KEY over: … superseded by "NAME" (NEWID)` |
| `session-status --init [--check \| --write [--delegate] [--own] [KEY=VALUE…]]` | Sets the cwd up for coordination (skill `setting-up-coordination`); its `session-init` holds the details. `--check`: one line, exit 0 configured (plus the `active:` line and any config warnings) (its own adapter here and a "Replies folder" line in `CLAUDE.md`/`CLAUDE.local.md`), 1 unconfigured or partial, 3 covered by a parent's adapter. No flag: the numbered proposal. `--write`: the missing files from `templates/` and the config, never over an existing one, excluded through `.git/info/exclude`. One GitHub repo with `gh` gets `templates/github-adapter` (PR words from two `gh pr list` queries, open and merged, cached for a minute; `done`, `urls`; self-test `github-adapter.test.sh`), anything else the minimal adapter. No tracker or model call |
| `session-status --pending` | The adapter's `pending` text, nothing else. The coordinator pane shows it |
| `session-status --root` | The project root (where the adapter and `.claude/coordinator-actions.json` are). The pane's project actions run there |
| `session-status --urls` / `--agents` | The adapter's `urls` text; the sessions the last sweep saw (id, name, state, command prefix, started, cwd, kind, status, pid). The coordinator pane's links and attach commands |
| `session-status --activity` | What each live session is doing, read fresh from its transcript (no tracker calls, ~1s): id, name, state, transcript written, doing, since, last text line, context tokens, context window, status, kind (tabs; times in epoch seconds). Context tokens are the last main-thread reply's input + cache read + cache creation, or a later `/compact`'s postTokens; the window is 1M when the session's model id has `[1m]` or its context already holds more than 200k tokens, else 200k. Doing is its `in_progress` todo (TodoWrite, TaskCreate/TaskUpdate), else its latest tool call's description, else that call in a few words, else its last text line. Since is when that activity started. Then cwd (where it started) and its command prefix. `--activity --all-projects`: every project's live sessions, in every account it asks. `session-activity.jq` |
| `session-status --peek ID [N]` | A session's last N (default 12) main-thread entries as markdown, without attaching: the prompts it got, its own text (each cut to 600 characters), its tool calls as `→ Tool: what` lines, then `_Now: …_` (what `--activity` says it does). `session-peek.jq`. The pane's **Peek** |
| `session-status --yesterday [DAY]` | What was worked on from the start of DAY (YYYY-MM-DD; default the last working day: the latest weekday before today with a prompt of the user's in a project transcript or a commit of theirs, within 14 days) up to now, so Monday's covers Friday and the weekend. `Since: DAY WEEKDAY (HOW)`, the adapter's `standup-notes` as `Note: TEXT` lines, then per task `KEY<TAB>STATUS<TAB>TITLE` and its events `  WEEKDAY HH:MM<TAB>TEXT` oldest first, the task with the latest event first. Events: each session active in the window (`session "NAME" (from–to): its last text line`, keyed by its first prompt's key and its `Session task:` markers; a keyless session shows as `"NAME"`; the coordinator is left out), the user's own commits per branch (pushed or not), and the adapter's `yesterday` rows. `session-day.jq`. The pane's **Yesterday** tab |
| `session-status --dir KEY\|ID…` / `--diff KEY\|ID…` | Where a task or session works: a KEY's worktree, else an ID's latest transcript cwd (it follows `cd` and EnterWorktree) as its git top; the first argument that resolves. `--diff` prints `DIR · vs BASE`, `git diff --stat` against the merge-base with the first of `origin/HEAD`, `origin/main`, `origin/master`, `@{upstream}` (none: the uncommitted changes against HEAD), the untracked `?? FILE`s, a blank line, then the patch (cut at 200k; the pane draws 40k). A session that works in a worktree by absolute path (`git -C`) without `cd` resolves to its start folder: pass its task key. The pane's **Diff** |

## The adapter

A project plugs in its tracker and code host with one executable, `.claude/session-status-adapter`
in the project root (found by walking up from the cwd). Without one, a committed
`.claude/coordination/session-status-adapter` (shared mode) runs once the person trusts it (Modules, below). It's
called with the cwd at the root:

| Call | Prints |
|------|--------|
| `tasks [ARG…]` | `KEY<TAB>STATUS<TAB>TITLE<TAB>EXTRA` per task, in display order. EXTRA (PRs, conflicts, hints) is printed as is before the worktree column, so it ends with its own separator (`\| `). The pane reads the words in the table below from it. On failure: exit non-zero, message on stdout (none: `adapter tasks failed (exit N)` and the last stderr line). Exit 2 with nothing on stderr means not answered (a syntax error exits 2 too, but says so on stderr): rows come from session names and worktree branches, as with no adapter, so an adapter answering only `pending`, `urls` or `key-pattern` needs no `tasks`. After such a sweep, the keys sessions and worktrees point at are asked about: those `done` reports go to Leftovers, the rest are looked up with `tasks KEY…`, whose rows on exit 0 replace the bare ones. A `fix: LABEL → COMMAND` line, on success or failure, is printed after the rows and becomes a pane action (Project actions) |
| `done KEY…` | `KEY[<TAB>LABEL]` for the finished ones; drives Leftovers and Resolved |
| `key-pattern` | One ERE for a task key. Default `[A-Z][A-Z0-9]+-[0-9]+` |
| `status-names` | Regex of the project's own status-command names (its wrapper), counted like `session-status` |
| `repos` | Git repos holding the worktrees, relative to the root. Default: the root if it's a repo, else its child repos |
| `pending` | The coordinator's handoff text (decisions waiting on the user, open requests), e.g. `cat` of the project's pending file. Shown in the coordinator pane |
| `urls` | Link templates for the coordinator pane, one per line: `ticket https://…/{key}` and `pr https://…/repos/{repo}/pull-requests/{id}` (a PR shows in EXTRA as `repo#id`) |
| `yesterday EPOCH KEY…` | The tracker's and code host's side of `--yesterday` since EPOCH (seconds), for the given keys and whatever else the user touched: per task `KEY<TAB>STATUS<TAB>TITLE`, then `  EPOCH<TAB>TEXT` events (PRs opened, merged, reviewed; status moves; comments). Exit 1: the lookup failed, its message on stdout (shown under `Tracker lookup failed:`); any other non-zero: not supported |
| `standup-notes` | Facts the standup summary should know about the project, one per line (e.g. a known-down environment it must not mention). `--yesterday` prints them as `Note: TEXT`; the summary follows them and never repeats them, the list leaves them out. Optional |
| `session-dirs` | More directories (absolute or `~/…`, one per line) whose sessions belong to the project, e.g. a tooling repo its coordinator starts sessions in. Their sessions never own a task: they show under Other sessions. Default: the root only |
| `mine` | The person's own task keys, one per line (whose messages the coordinator forwards: a messages module's `mine` field; default the keys of the last sweep's rows). The GitHub template lists the keys of your open PRs and `#N` of open issues assigned to you, or unassigned and closed by one of your PRs. Optional |
| `notices` | Short lines about things outside the tracker (a new chat message, a mention), one per item. Sweep only, run in parallel with `tasks`, printed under a **Notices** footer. Keep a line identical while its item is unchanged. `--changes` reports a new or changed notice but not one that went away, so reading a message doesn't wake the watcher. Chat and mail belong in a messages module (Modules), whose lines come first |
| `pr-keys REPO#ID` | The task keys a PR refers to (its branch and title), one per line, for a messages module that finds a PR link in a message. Exit 1: not found. Optional |

A call it doesn't answer exits non-zero and the default applies (`tasks`: exit 2, above).

## Words the pane reads in EXTRA

Whitespace-separated; anything else shows only in a task's details.

| Word | Means | In the pane |
|------|-------|-------------|
| `REPO#ID OPEN` / `REPO#ID MERGED` | A PR and its state | OPEN: In review, or Landing once approved. MERGED with no open PR and the task not in a test/done status: Needs action |
| `+NAME` | NAME approved the PR | Landing (when nothing needs fixing and no `no-human-approval`) |
| `!NAME` | NAME asked for changes | Needs action, **Address comments** (its PR review comments) |
| `no-human-approval` | Open, waiting for a reviewer | In review |
| `CONFLICT` | Merge conflict | Needs action, **Resolve conflicts** |
| `CI-FAILED` | The PR's latest build failed | Needs action, **Fix CI** |
| `↩MM-DD NAME→STATUS` | The tracker sent the task back | Needs action (Ask the session why) |
| `(PRs as of HH:MM)` | The PR words are from that time (a lookup failed) | Shown as stale |

## Without an adapter, and task ownership

Without an adapter, rows are the keys in running sessions' names and worktree branches (no tracker
status, no Leftovers). Transcripts that ran `session-status` (or a `status-names` command) with
`--changes` or `--watch` are a coordinator's and never own a task; a plain run (a worker checking its
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
them), both counted in the header; then the tasks, each in one group:
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
file's `- ` items, and **Resolved** last, collapsed until pressed. Above the groups, **▶ RUN** lists
the commands sessions handed the user (`hand_command`), per task key, each counted on you under its
task, with Run, Copy and Dismiss buttons (no key): coordinator.md, Handed-over commands.

Both refresh every 10 minutes and on its refresh button (`r` while the pane has focus). Pressing an
item opens it as a card (a box with its details and actions): attach (copies the command), the
ticket and PR links (from the adapter's `urls`), the fixes that apply (Resolve conflicts, Fix CI,
Address comments: see coordinator.md, Card actions), refresh that row, dismiss a notice (for this
session), copy a leftover's cleanup command, and Ask. A session's card (a task's, a waiting or other
session's) also has **Peek** (`p`: its last turns and what it does now, under the card, without
attaching), **Diff** (`d`: its worktree's files and stat against the base; **▸ Patch** draws each
file's hunks, up to 40k characters, the rest named), and, with a `terminal` configured (not `plain`),
**Attach in tab** (`t`: `claude attach` under the session's account and in its folder; first on a card that waits on
the user) and **Logs in split** (`l`: `claude logs` beside it); neither on an interactive session. Both run
`session-status --open view|split …` (Modules, below): when the terminal opens nothing (exit 2) the pane copies the
command and says why, another failure shows as a toast. What the terminal does is in its doc
(`terminals/<name>.md`). One Peek or Diff shows at a time; a second press or closing the card hides it. The header's
**all projects** toggle (`w`) also reads every other project's live sessions, in every account it asks, into an
**Other projects** section (project folder, what it does, attach with its account prefix, Peek, Diff). The header's **yesterday** toggle (`y`) swaps the task board for the Yesterday tab
(`session-status --yesterday`, about half a minute with the tracker): **Worked on** lists each task with
its status, title (the key links to the ticket) and events, **Other work** the keyless sessions. `b` and
`n` step the start day a weekday back or on (on to today: the last working day again); `r` reads it again.
Once read, `standup-summary` turns the reading into what you'd say at the daily (3–5 spoken sentences, by
`claude -p --model haiku` with no tools, plugins or transcript: about $0.003 and 5–15s a run; another model with
`SESSION_STATUS_SUMMARY_MODEL`). It names work in a few plain words (a tracker key may stay), never by session name or
task id, and follows the adapter's `standup-notes`. It shows in place of the lists; `s` swaps to the list and back. It's cached per start
day under `~/.cache/session-orchestration/standup/` and written again only when that day's data changes (sessions'
spans and last lines left out, they move at every refresh; the model and prompt count). While a refresh checks it,
the day's last summary stays up; while a first one is written, or when the call fails or passes 90s, the list shows,
with the reason. With the list chosen, no summary runs until `s` switches back. With the pane focused (ctrl+x tab), `1`–`9`
select the Waiting on you items, then the Decisions, in order. Once the pane is open, the status line under the prompt
carries the header's count (`◆ N on you`), so it shows while the pane is hidden. The pane only
exists in an interactive session that has the plugin loaded. The agent view (`claude agents`) can't
show plugin panes. In a terminal narrower than about 144 columns (110 once the user has opened the pane themselves)
the pane waits until the window is wider; `/coordinator close` closes it. Under the approvals, **Actions** holds the project's own
commands (below).

## Project actions in detail

A project names its own pane actions, with no UI code, from two places. Each shows as a button under
**Actions** beside the command it runs (its hotkey works while the pane has focus); pressing it runs
it with `bash -c` in the project root (`session-status --root`), shows `✓`/`✗`, the label and the
last line it printed, then refreshes the pane. One runs at a time, for up to 5 minutes.

1. **`.claude/coordinator-actions.json`** in the project root, a list:
   ```json
   [{ "label": "Sign in", "hotkey": "g", "command": "gh auth login", "when": "! gh auth status >/dev/null 2>&1" }]
   ```
   `label`, `hotkey` (one lowercase letter) and `command` are required. `when` is optional: a shell
   check run in the root at each sweep (10s cap); exit 0 shows the action. The file is read again at
   each sweep. The pane's own keys are taken: `r` refresh, `o` `f` `m` the card fixes, `a` attach,
   `u` row refresh, `k` ask, `x` dismiss, `c` copy, `z` compact, `p` peek, `d` diff,
   `w` all projects, `t` attach in tab, `l` logs in split, `y` yesterday, `b`/`n` earlier/later day, `s` summary or list, `1`–`9`. A bad entry (not JSON, a missing or
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
button) is in coordinator.md, Project actions.

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
module's `<name>.md` beside it, if any, is the doc the check's `active:` line names.

**Messages** modules define `messages_notices`, run in the sweep's notices job beside the adapter's `notices`, from
the project root, with `NOTICE_DIR` (its cache folder), `NOTICE_KEYRE` (the key regex, in parens), `NOTICE_ROWS`
(the last sweep's rows), `NOTICE_MINE` (a file of the person's keys) and `adapter` set. It prints one line per item
and exit 0, or exit 1 with the reason on stdout (the last good lines show, marked failed); it writes each line's
full message to `$NOTICE_DIR/notices.jsonl` (`session-status --messages-file`), with `mine`: the line's keys in
`NOTICE_MINE`. The plugin ships `msgraph` (Teams and Outlook, `messages/msgraph.md`).

**Terminals** define two functions, the contract `session-status --open view|split ARGS… -- CMD…` calls:
- `open_view [--account DIR] TITLE DIR CMD…`: run CMD in a new tab or window titled TITLE, in DIR, under that
  Claude account (`CLAUDE_CONFIG_DIR`; absent or `~/.claude` is the default account);
- `open_split [--account DIR] DIR CMD…`: run CMD in a split beside the current view.

Return 0 when it opened; 2 when nothing opened, with the reason on stderr (the pane copies CMD); anything else is an
error, shown with stderr. `plain` (the default) opens nothing: it prints CMD and returns 2. A WezTerm module, say, as
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

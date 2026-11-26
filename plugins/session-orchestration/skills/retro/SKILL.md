---
name: retro
description: Measure how efficiently sessions turn tokens into finished work (cost per merged PR, context size, waste, time to done) for one project or the plugin, check last run's proposals, rank the next changes. Use for /retro [project|plugin|both], a scheduled retro (retro-run), or when asked how the sessions perform.
---

# retro

The user runs many Claude Code sessions in parallel. A run measures how efficiently they turn tokens
into finished work, checks whether the last run's proposals landed, and ranks the next few changes.
Efficiency is **per unit of work**, not weekly spend: the user spends saved tokens on more work, so a
weekly total stays flat.

This file is the default brief. A project adds to it in `retro-brief.md` beside its project memory file (its units'
CLI commands, its own checks; a setup from before the state folder: `.claude/retro-brief.md`); where the two
disagree, the project's brief wins. The brief applies to project scope only. Started by `retro-run` (launchd) or by
hand as `/retro`: same steps either way. It's opt-in: nothing runs until someone invokes it or schedules it.

## Scope

A run measures **one scope**, and the scope sets whose sessions are read and which sections exist:

- `project`: this project's sessions, its worktrees included, and what the project can change (its docs, scripts,
  settings, memory).
- `plugin`: every project and account, and only what the plugin can change.

`/retro project` or `/retro plugin` picks one, as does `scope project` or `scope plugin` in the first prompt (how
`retro-run` starts each scope's session). `/retro` alone takes `session-status --config retro.scope` (run from
the project root; default `project`). `both` (an argument or the setting) runs the project scope and then the plugin
scope, one after the other in this session, each a whole run with its own report: never one report for two scopes.

Plugin scope has one home, `feedback.repo_dir`'s root when that is set: from any other root `--config retro.scope`
and `retro.py sections plugin` fall back to the project scope with a warning; put it in the report.

## Sections

`python3 -I retro.py sections <scope> $(session-status --config retro.sections)` prints the sections this run
writes, in order: the scope's own, narrowed to the ones `retro.sections` lists (a listed one the scope lacks is
named on stderr: say so in the report). Measure and write only those; a section it doesn't print has no data run
and no heading.

| Section | `project` scope | `plugin` scope |
|---------|-----------------|----------------|
| `units` | $ and tokens per merged PR, finished ticket, review posted; time to done; quality per merged PR (first-try CI green, changes requested, follow-ups) per kind | the same over all projects, default commands only |
| `context` | base context, average per request, requests over 200K, resume forks | the same over all projects |
| `waste` | refusals, retries, `!` handoffs, wrong relayed claims, lost reports, long waits | the same over all projects; the hook's split hints counted apart |
| `spend` | no | where the week's spend goes by account, project, session, kind, model and trigger; rebuilds of big contexts, wakes, test runs, gh calls, handovers |
| `feedback` | this project's friction cases, grouped into patterns, one fix proposed per pattern | the plugin's case store: open cases most seen first, and which of last run's cases landed |
| `coordinator` | this coordinator's wakes and cost by trigger; handoff entries (`pending.file`) | no |
| `memory` | memory size; the graduate pass's Gather and Propose | no |
| `protocol` | no | Start cost by part against its targets, skill and card loads, reply cost |
| `features` | no | feature use over 30 days, unused candidates |
| `sizing` | no | planner ratio per kind, the trial's arms, cost and done share per kind |

Each section's commands (step 2) and what it measures (step 3) are in `sections/<name>.md` next to this file (their
paths are relative to this file's folder): read the file of each section this run writes, and no other.

`python3 -I retro.py sections --groups <scope> $(session-status --config retro.sections)` prints the same sections as
a group plan: one `GROUP: SECTION…` line per group (config `retro.groups`, else the defaults), then a `writer:` line
for the sections no group lists. Run by hand (`/retro`), one session runs every group's sections: step 2 for all of
them, then step 3, in the order `retro.py sections` prints (a section's commands may read another's files), and the
report lists the headings in that order too. A `retro-run` start splits them: one session per group, then a writer
([Split run](#split-run)).

## Rules

- Read-only outside the replies folder. Change nothing else: no settings, hooks, scripts, CLAUDE.md,
  Jira, PRs. Proposals go in the report; the user approves them.
- Never print transcript bodies; `retro.py` caps snippets. No Claude attribution anywhere.
- Report only this run. Don't sweep or report other sessions' tickets.
- Don't arm watchers or ScheduleWakeup. Finish in one pass.
- No web searches or fetches: the other-tools scan is the `research` skill's (`/research other-tools`); a plugin
  run only reports how old the last scan is.
- A proposal to disable or remove a plugin, skill or connector needs a **30-day window**
  (`retro.py events 30 P > events30.tsv`, or a 30-day tool tally; in project scope too, though only the plugin's
  `features` section collects it), even though the rest of the run is weekly. Seven days
  missed real use once (a plugin called unused had 4 skill calls in 30 days). Hook-only plugins and
  passive LSPs count as in use.

## Where things are

- `retro.py`, next to this file: `python3 -I retro.py` prints its usage. It reads every account's
  transcripts (`$CLAUDE_CONFIG_DIR`, `~/.claude`, `~/.claude-*`; a `projects/` tree shared by symlink
  is read once) and all projects. **In project scope every call carries `--project <root>`** (the project root's
  absolute path: its transcripts and its worktrees', nothing else); in plugin scope none does. `--until <UTC time>`
  reruns an old window.
- Two commands read the planner's work: `chunks [days] [--session PREFIX]` gives one row per chunk (growth,
  peak, cost, compactions, handoff before or after one) and a per-kind `ratio` line; `trial [days=28]` gives the
  planner arm against the off arm.
- `kinds [days]` reads the usage log's `start` lines (`session-status --kind KIND NAME`), joins each to its session
  by hashed name (and the successors it handed over to), and gives per kind, model and effort: starts, joined, cost,
  share reaching `reply … done`, handovers, nudges (every cross-session message in, answers and approvals too),
  minutes to done and escalations (`--handover --escalate`); an S or L start (`--kind build:L`) is its own row, and
  so is a start with an advisor (config `plan.advisor.KIND`, as `build+fable`), with `advisor_calls_median` and
  `advisor_usd` (its subagents' calls too, which `usd` leaves out: it isn't a share of `usd`).
  Every command's cost uses each request's model's list rates (an older run used Opus rates for all): to compare with
  one, rerun its window with `--until`.
- Replies folder: the one the project's `CLAUDE.md` names (its "Replies folder" line). None named: stop and
  say so. Below, `<R>` is that folder.
- Reports, one series per scope, each with its own number, baselines and "Next run" section:
  `<R>/retro-project-<N>.md` and `<R>/retro-plugin-<N>.md`, an `.html` beside each. Data:
  `<R>/retro/<scope>-<N>/*.tsv`, a fresh folder per run.
- A scheduled run's task key is `retro-<scope>` (one per scope, so `both` keeps two): its writer's `reply` key, and
  its handoff in `<R>/retro-<scope>.md`. A section session hands nothing over (Split run).
- Numbering: the project series continues the old mixed reports. Its run is 1 + the highest N among
  `retro-project-<N>.md` and `rnd-run-<N>.md`, and its baseline is that highest report (an `rnd-run-<N>` is never
  renamed). The plugin series starts at 1 with no baseline: its first run measures two windows (Steps, 2) so
  its table still has a "last run" column. Its baseline after that is the highest `retro-plugin-<N>.md`. In
  either series N also counts the run folders `<R>/retro/<scope>-<N>/`, an open split run's included.
- Refusals logged by the plugin's hook: `~/.cache/session-status/denied.jsonl`, one JSON line per
  refusal with `time`, `session` and `cwd`.

## Steps

1. Read the project's `CLAUDE.md`, its project memory if it names one (retro or R&D entries there override the
   section files' yardsticks; with an index, read the topic files whose trigger is retro or R&D), and the baseline
   report with its "Next run" section. Project scope also reads the project's `retro-brief.md` (beside the memory file,
   else `.claude/retro-brief.md`) if present. Settle the scope, the
   sections and their groups (`retro.py sections --groups`) and N as above.
2. Run `retro.py` over 7 days into `<R>/retro/<scope>-<N>/`, only for the sections this run writes, by each
   one's `sections/<name>.md` (`P` there is `--project <root>` in project scope, nothing in plugin scope). Look at
   three raw rows of each TSV before tallying it. These commands are the analysis: tally from their output, and
   write no ad-hoc script for it (a count they lack is a `retro.py` change to propose).
   - The plugin series' first run (no `retro-plugin-<N>.md` yet) also runs every section's commands again with
     `--until <this window's start>` into `<R>/retro/plugin-1/prev/`: the "last run" column. Its rnd-run reports
     mixed both scopes, so they are not its baseline.
3. Measure each section this run writes, by its `sections/<name>.md`, with last run's number beside each:
   - Project scope: run the project brief's own checks.
   - Plugin scope: one line, "Other tools: last scanned <date>", the newest `last_checked` in
     `<R>/research/competitors.tsv` (else `<R>/rnd/competitors.tsv`, its old place; neither: "never"). Over 28 days
     ago or never: propose a research run (`/research other-tools`, started as kind `research`) outside the 5
     ranked proposals.
4. For each of last run's ranked proposals, say whether it landed (look at the file or setting it targets) and
   whether its waste count moved. A baseline `rnd-run-<N>`'s "Other tools" proposals: landed or not only.
5. Write `<R>/retro-<scope>-<N>.md`: scope, window and totals (a fallen-back scope's warning line first), a heading
   per section this run writes with its yardstick rows (last run beside this one), landed / not landed, at most 5
   new ranked proposals (problem, evidence with session ids, change, target, gain, risk), and a "Next run" section
   with the baselines to compare against.
   - Project scope: the proposals are project fixes (doc, script, setting, memory). A finding whose fix is in the
     plugin itself becomes a plugin feedback case instead (`../orchestrating-sessions/feedback add`, in the plugin's
     terms; [feedback.md](../orchestrating-sessions/feedback.md)), named in the report by its title: the plugin run
     reads the case store, so it sees every project's findings without reading their reports.
   - Plugin scope: the proposals are plugin changes, each filed as a feedback case (`feedback add`, or `feedback
     seen` on the open one it matches) and ranked by name. The report ends with `feedback list --plugin` (open
     cases, most seen first) and offers the apply (feedback.md, "Applying"). With a plugin coordinator (`feedback
     coordinator` exits other than 2), it names them as that coordinator's instead, with no offer.

   Then `python3 -I retro.py html <R>/retro-<scope>-<N>.md <R>/retro-<scope>-<N>.html`; step 6's
   message names the `.html` and goes with `done: report`, which opens it (once) and says `opened: yes|no`. When `session-status
   --config features.report_artifacts` lists `retro`, publish the `.md` as a private page by
   [report-artifacts.md](../../features/report-artifacts.md) and pass its link in step 6's message (`reply`'s `artifact`).
   A published page always gets its own message, even when nobody would get it (`reply` then queues it) and under
   `both` (one message per page): `artifact` records one page per reply.
6. Send the coordinator at most 5 lines with the `reply` tool, no `to` (ToolSearch
   `mcp__session-orchestration__reply`, `done: report`; it finds the live coordinator at send time): the report paths, the top 2–3
   proposals, a research run when the scan is due, and anything that needs the user. With `both`, one message after
   both runs, naming both reports. Nobody gets it: skip the message; the report is enough, unless step 5 published a page (its reply records it).

## Done when

`retro-<scope>-<N>.md` and `.html` exist for each scope this run took, every section `retro.py sections` printed
has its rows filled (or "no data" and why) and no other section appears, a plugin run has its "Other tools: last
scanned" line, and the coordinator message is sent or skipped for a stated reason (never skipped when a page was published).
That is the writer's and a by-hand run's; a section session is done when `sections/G.md` and `G.status` exist and its
`retro-run --join` ran.

## Split run

`retro-run` makes the run's folder `<R>/retro/<scope>-<N>/` with `run.json` (scope, `n`, `root`, `until` the window's
end, `split` last run's end, `baseline`, `groups` each with its `sections`, session `name` and `id`, and `writer` with
its name and `sections`), then starts one session per group and, once every group has ended, one writer.

**Section session** (first prompt `Session task: retro run, scope S, section group G, run DIR`): read `DIR/run.json`
(its N, baseline and `until` are the run's: don't settle them again) and do steps 1 to 4 for `groups[G].sections` only, with `--until <run.json's until>` as the first argument of every `retro.py` call
(`python3 -I retro.py --until <until> <command> …`; anywhere else it is ignored) and its
data in DIR. Write `DIR/sections/G.md`, in report order: each section's heading and yardstick rows (last run beside
this one); last run's proposals in its area, landed (with the commit) or not; up to 3 candidate proposals (problem,
evidence with session ids, change, target, gain, risk); its "Next run" baseline lines; feedback drafts as the exact
`feedback add` arguments, not run. It sends no message, writes no report and files no case. Last, write
`DIR/sections/G.status` (`done`, `done: cut at mark` or `failed: WHY`) and run `retro-run --join DIR` (next to this
file), then end the turn. At the context mark the hook says to cut it short: write `G.md` from what it has, what's left
as one candidate (a research task), the status `done: cut at mark`, then the join; no handover.

**Writer** (first prompt `Session task: retro run, scope S, write the report, run DIR`): its N and baseline are
`run.json`'s `n` and `baseline` (the report is `retro-<scope>-<n>.md`, whatever the Numbering rule would give now). Read `run.json`, every
`sections/*.md` and `*.status`, and the baseline report. Measure `run.json`'s `writer.sections` itself (steps 2 to 4,
`--until` as above), then steps 3's Other tools line to 6 from the section files: the ranked proposals come from their
candidates, the feedback drafts are filed in step 5. A group whose status is `failed: WHY`, or which has none (its
session ended without one: name the session id from `run.json`), gets `no data: WHY` under each of its headings.

`retro-run --join DIR` starts the writer once: under `DIR/join.lock`, when no group is running and `writer.started`
doesn't exist yet. It prints `writer waits for: …`, `writer "NAME" started already` or the writer's start line. A
group whose session ended without its join is caught by the next `retro-run` call for the scope, or by hand with
`retro-run --join DIR` (`--status` lists the open runs).

## Scheduling the weekly run

`retro-run`, next to this file, starts one background session per section group of each scope
(`retro-<scope>-<date>-<group>`, on `plan.models.retro`) and later its writer (`retro-<scope>-<date>`, [Split
run](#split-run)) in a project root when a run is due, and logs to `retro-run.log` in `~/Library/Logs` on macOS,
else in `${XDG_STATE_HOME:-~/.local/state}` (`RETRO_LOG` overrides). It reads the person's `features.retro` and
`retro` block (`features/retro.md`); the session needs the plugin enabled in `retro.account`.

| Call | Does |
|------|------|
| `retro-run ROOT [--scope S] [--now] [--dry-run]` | for each scope whose run is due (its last start is older than `retro.schedule`'s most recent time; `--now` skips the check): writes the run's folder and `run.json`, starts one session per group, and prints `writer: starts when K groups are done`; first it joins the scope's open runs whose sessions have all ended. `--dry-run` prints the verdict, the run's folder, the group plan and each start line, and starts nothing. Each start prints `started "NAME" (ID8) · retro M/E` on stdout, or `"NAME" didn't start: WHY` (that group's status becomes `failed: didn't start`); exit 1 when any didn't start. None started: no folder, the stamp given back |
| `retro-run --join DIR` | the writer's start, once every group of the run in DIR has ended ([Split run](#split-run)) |
| `retro-run --install ROOT` | writes `~/Library/LaunchAgents/session-orchestration.retro.<slug>-<6 hex>.plist` (needs `features.retro` true and `retro.schedule`) and loads it; again after changing `retro.schedule` or `retro.account`. Prints the command that removes an old cron line; it never edits the crontab |
| `retro-run --uninstall ROOT` | unloads and deletes it |
| `retro-run --status [ROOT]` | label, loaded or not, schedule, account, last start and next due per scope, and `SCOPE: retro overdue: …` when its newest report is over 8 days old; then each open run (no report yet): `run S-N: GROUP STATE · … · writer not started (retro-run --join DIR)` or `writer started (ID8), no report yet`, a group's state its status line, `running (ID8)` or `missing (session ended)` (no ROOT: every agent) |

- **Missed runs**: launchd starts a calendar time missed in sleep at wake; `RunAtLoad` calls the launcher at each
  login, for a time missed while off or logged out. The due check (a stamp per root and scope in the project's state
  folder) makes extra calls no-ops. The first stamp is the newest report's time (`retro-<scope>-<N>.md`,
  `rnd-run-<N>.md`), else now: a missed run starts at once, a new project waits for its first time.
- **Path**: installed from the plugin cache, the agent looks up the plugin's current `installPath` in the account's
  `installed_plugins.json` at each start (a versioned path would run old code forever); from a checkout, it names it.
- **Linux**: no installer. Set `retro.schedule` (without it there is no due check), then a cron line at its time
  plus an `@reboot` line, both
  `<checkout>/plugins/session-orchestration/skills/retro/retro-run <root>` (prefix `CLAUDE_CONFIG_DIR=…` for another
  account): the due check makes the reboot call start only a missed run. A systemd user timer with
  `Persistent=true` does the same.
- **The old cron line** (`retro-weekly`) still works: both call `retro-run ROOT` and log the install
  command. `--install` prints the command that removes that root's line.

Self-tests: `bash retro.test.sh` and `bash retro-run.test.sh` (each prints `ok`).

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
| `units` | $ and tokens per merged PR, finished ticket, review posted; time to done | the same over all projects, default commands only |
| `context` | base context, average per request, requests over 200K, resume forks | the same over all projects |
| `waste` | refusals, retries, `!` handoffs, wrong relayed claims, lost reports, long waits | the same over all projects; the hook's split hints counted apart |
| `spend` | no | where the week's spend goes by account, project, session, kind, model and trigger; rebuilds of big contexts, wakes, test runs, gh calls, handovers |
| `feedback` | this project's friction cases, grouped into patterns, one fix proposed per pattern | the plugin's case store: open cases most seen first, and which of last run's cases landed |
| `coordinator` | this coordinator's wakes and cost by trigger; handoff entries (`pending.file`) | no |
| `memory` | memory size; the graduate pass's Gather and Propose | no |
| `protocol` | no | Start cost by part against its targets, skill and card loads, reply cost |
| `features` | no | feature use over 30 days, unused candidates |
| `sizing` | no | planner ratio per kind, the trial's arms, cost and done share per kind |

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
- A scheduled run's task key is `retro-<scope>` (one per scope, so `both` keeps two): its `reply` key, and its
  handoff in `<R>/retro-<scope>.md`.
- Numbering: the project series continues the old mixed reports. Its run is 1 + the highest N among
  `retro-project-<N>.md` and `rnd-run-<N>.md`, and its baseline is that highest report (an `rnd-run-<N>` is never
  renamed). The plugin series starts at 1 with no baseline: its first run measures two windows (Steps, 2) so
  its table still has a "last run" column. Its baseline after that is the highest `retro-plugin-<N>.md`.
- Refusals logged by the plugin's hook: `~/.cache/session-status/denied.jsonl`, one JSON line per
  refusal with `time`, `session` and `cwd`.

## Steps

1. Read the project's `CLAUDE.md`, its project memory if it names one (retro or R&D entries there override the
   yardstick below; with an index, read the topic files whose trigger is retro or R&D), and the baseline report
   with its "Next run" section. Project scope also reads the project's `retro-brief.md` (beside the memory file,
   else `.claude/retro-brief.md`) if present. Settle the scope, the
   sections (`retro.py sections`) and N as above.
2. Run `retro.py` over 7 days into `<R>/retro/<scope>-<N>/`, only for the sections this run writes (`P` below is
   `--project <root>` in project scope, nothing in plugin scope). Look at three raw rows of each TSV before
   tallying it. These commands are the analysis: tally from their output, and write no ad-hoc script for it (a
   count they lack is a `retro.py` change to propose).
   - `units`: `units 7 P > units.tsv 2> units.txt`, adding `units <slice days> P` for the slice after last run's
     end. Project scope only: pass the brief's regexes with `--merge`/`--done`/`--post` when its commands differ
     from the defaults (`retro.py` usage). Where reviewers press merge, a session's merge command never runs: write
     the window's task keys with `units 7 P --keys keys.txt > /dev/null 2>&1`, then from the project root the
     adapter's merges for them to `merged.txt` (`.claude/session-status-adapter yesterday <window start, epoch s>
     $(cat keys.txt)`), and pass `--merged merged.txt` to both `units` calls. An adapter without `yesterday`, or a
     non-zero exit: leave it out and say merges count only the ones sessions ran (`merge_ran`). Time to merge, with
     a GitHub host: the PR list to `prs.json` (`gh pr list --state all --limit 1000 --json
     number,createdAt,mergedAt -R OWNER/REPO`), then `merges <dir> prs.json 7 OWNER/REPO P > merges.txt` (`waste`'s
     `sessions.tsv` first: it reads it for $ per PR).
   - `context`: `context 7 <split> P > context.tsv` (split: last run's end, so the slice after it gets its own row).
   - `waste`: `sessions 7 P > sessions.tsv`, `events 7 P > events.tsv 2> events.txt`, `waits 7 5 P > waits.tsv 2> waits.txt`,
     `bgtasks 'session-status.*--watch' 7 P > bg-watch.tsv`, plus any `bgtasks` regex the project brief names
     (project scope), `replies 7 P > replies.tsv` (lost reports), and once they are written `waste <dir> 7 P >
     waste.txt` (the counts below, tallied from them and `denied.jsonl`). Refusals: count them from `denied.jsonl` for
     the window when it covers it (project scope: the lines whose `cwd` is the root or under it), else from `deny`
     rows in `events.tsv` whose `test` column is empty (`-p`/`dontAsk`: headless permission tests); say which
     source was used. A denial whose text (a deny row's `detail2`, after `source/reasonType: `) starts "Background
     session: this compound command" is project-memory's split hint, not a refusal: count those separately,
     and leave them and the retry after each out of the refusal and retry-waste counts, so runs stay comparable.
     The classifier's no-verdict denials (`denied.jsonl` logs them as "Classifier unavailable") get their cause from
     `events.txt`'s `noverdict` line: report it beside the count. `hook_changed` and `sibling_changed` come from a
     PreToolUse hook that rewrites a call's input (`updatedInput`), which the user can fix in their own hooks;
     `ended` is the classifier's side.
   - `feedback`: project scope, `../orchestrating-sessions/feedback list --project` from the project root; plugin
     scope, `feedback list --plugin` and `feedback list --all --plugin` (the cases last run filed or named, and
     whether they are `fixed` now).
   - `coordinator`: `triggers <coordinator> 7 P`: the coordinator is the first name (not a `uds:` line)
     `bash <orchestrating-sessions skill folder>/session-status --coordinator` prints (only `uds:` lines: it runs under
     another account; take its name from `session-status --activity`'s coordinator row), run from the project root
     (`triggers` takes a session name or an id prefix). Add an earlier coordinator's id when last run's "Next run"
     names one. Then `handoff 28 P > handoff.tsv 2> handoff.txt` (config `pending.file`, else the state folder's
     `pending.md`; an entry with no history file has rewordings `-`).
   - `protocol`: `start 7 > start.tsv` (each coordinator's Start by part, the medians last) and `loads 7 > loads.tsv`
     (messages, skill, `worker.md`, card and reply loads by session kind).
   - `spend`: `spend 7 <dir> > spend.md` (it writes `spend-*.tsv` into `<dir>` too, and reads `protocol`'s
     `start.tsv` when `<dir>` has it, for the Coordinator Starts lines).
   - `features`: `usage 30 > usage.tsv` and `events 30 > events30.tsv`.
   - `sizing`: `chunks 7 > chunks.tsv` and `trial > trial.tsv` when the usage log has chunk lines; `kinds 7 >
     kinds.tsv` when it has start lines. Exit 2 with `unmeasured: WHY` on stderr (no usage log, or one starting after
     the window's end) is no measurement: write that line in the report, never a zero.
   - The plugin series' first run (no `retro-plugin-<N>.md` yet) also runs every command above again with
     `--until <this window's start>` into `<R>/retro/plugin-1/prev/`: the "last run" column. Its rnd-run reports
     mixed both scopes, so they are not its baseline.
3. Measure each section this run writes, with last run's number beside each:
   - `units`: $ and tokens (output + cache write + cache read) per merged PR, per finished ticket and per review
     posted: `units.tsv` and its totals line, counted from the sessions' own transcripts (only commands that ran),
     not a tracker sweep. Time to done: review written → posted, "merge it" → merged. Weekly $ only as context, one
     line.
   - `context`: base context per session (first request, median) and average context per request; requests above
     200K and their excess tokens; resume forks (`fork` rows): `context.tsv`.
   - `waste`: classifier refusals, retries after a denial (same command opening, ≤5 min), `!`/`claude attach`
     handoffs to the user (`bang` rows are a session's suggestion, one per distinct session and command; `ran` rows
     are the user running one), wrong relayed claims (`self` rows plus corrections), lost reports (bg tasks SILENT,
     `replies.tsv` rows; a `NO NOTICE YET` task was still running at the window's end: not lost), waits over 5
     minutes, those tagged `sleep` (the machine woke: the same end minute in 3+ sessions) counted apart (`waits.txt`
     totals). Not counted yet (known gaps, so figures stay comparable run to run): subagent transcripts
     (`<session>/subagents/*.jsonl`), and history a fork copied from its parent is counted again in the fork's row.
     Name them when a figure hinges on them.
   - `spend`: from `spend.md`, the week's $ by account and the three largest shares by project, kind, model and
     trigger; the cost of rebuilding big contexts (cache writes after a gap), wakes that did nothing, test runs (full
     suites against sections), gh calls and handovers; each beside last run's, and one proposal for the largest
     share that is waste rather than work.
   - `feedback`, project scope: group this project's cases (friction from its hosts, sign-ins, docs and scripts)
     into patterns (the same cause, place or fix; one case seen ≥2× is a pattern of its own) and propose one project
     fix per pattern (a doc, script or setting), naming its case files; the followups session applies the approved
     ones and marks those cases fixed. Plugin scope: the open cases, most seen first, and for each case last run
     filed or named, landed (`fixed`) or not.
   - `coordinator`: the coordinator's wakes, requests and $ by trigger. Handoff entries: the on-you wait per blocker
     bucket, entries with reason `unknown`, recurring entries (rounds > 1), and detail and history bytes beside
     last run's. Read the top 5 rows by `wait_d` and the top 5 by `rewordings` (their history files, by
     `session-status --pending-history LABEL --last 10`, not whole) and name the issues that recur; one proposal at
     most. `history read` against `unread` in `handoff.txt` says whether sessions that opened a history file did
     better: report it, and say when either side is under 5 entries.
   - `memory`: memory's size (index plus topic files, bytes / 4) beside last run's, also in "Next run". If the
     project memory index has a graduation rule and the brief has no graduation check of its own, run
     project-memory's `graduate` skill's Gather and Propose steps (no Apply) and put its numbered list in as one
     proposal outside the 5 below.
   - `protocol`, against its targets: `start.tsv`'s median and `target` rows (per entrypoint when there are several:
     the app's harness base runs ~30K above the CLI's; the base itself is the harness's, no target) and `loads.tsv`'s
     workers' skill loads (0 to reply: the card replaces them) and `reply_target`. Name the part furthest over.
   - `features`: each `unused` row of `usage.tsv` (0 uses in 30 days, there all window) is a candidate to drop or
     merge: at most one proposal listing them, never a removal on the run's own say. Pane buttons show `-` under
     `telemetry: off` (setting-up-coordination, Config; the default `full` and `local` log them): say so, and judge
     them not at all. `block`, `refuse`, `relay`, `error` and the `wake poll-failed`/`gave-up` rows (telemetry `full`; `wake wake` is a watcher's normal wake, counted, not a fault) are the plugin's faults:
     count them in `waste`, and a row that grew since last run (a hook line, a --flag, an exit code) is a fix to
     propose. `fold-SECTION` (a
     section's title pressed to one line), `unfold-SECTION` (pressed open) and `card-SECTION` (a row opened there)
     say which pane sections the user opens and which never: report them. A section folded and never unfolded is one
     nobody reads (a candidate for `hidden` in config pane.sections).
   - `sizing`: the `ratio` per kind (median act/est) from `chunks.tsv`, and a new size multiplier for a kind whose
     median strays past 1.0 ± 0.3; `trial.tsv`'s arms week over week against last run's; from `kinds.tsv`, cost per
     start and done share per kind beside last run's, and a plan.models change for a kind that costs more than the
     next kind up or reaches done less than the one below it, or escalates in more than one start in four (its
     default is too low).
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

## Scheduling the weekly run

`retro-run`, next to this file, starts one background session per scope (`retro-<scope>-<date>`, on
`plan.models.retro`) in a project root when a run is due, and logs to `retro-run.log` in `~/Library/Logs` on macOS,
else in `${XDG_STATE_HOME:-~/.local/state}` (`RETRO_LOG` overrides). It reads the person's `features.retro` and
`retro` block (`features/retro.md`); the session needs the plugin enabled in `retro.account`.

| Call | Does |
|------|------|
| `retro-run ROOT [--scope S] [--now] [--dry-run]` | starts the scope's session(s) whose run is due: its last start is older than `retro.schedule`'s most recent time. `--now` skips the check; `--dry-run` prints the verdict and the start line. Each start prints `started "NAME" (ID8) · retro M/E` on stdout, or `"NAME" didn't start: WHY`, one line per scope; exit 1 when any scope didn't start |
| `retro-run --install ROOT` | writes `~/Library/LaunchAgents/session-orchestration.retro.<slug>-<6 hex>.plist` (needs `features.retro` true and `retro.schedule`) and loads it; again after changing `retro.schedule` or `retro.account`. Prints the command that removes an old cron line; it never edits the crontab |
| `retro-run --uninstall ROOT` | unloads and deletes it |
| `retro-run --status [ROOT]` | label, loaded or not, schedule, account, last start and next due per scope, and `SCOPE: retro overdue: …` when its newest report is over 8 days old (no ROOT: every agent) |

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

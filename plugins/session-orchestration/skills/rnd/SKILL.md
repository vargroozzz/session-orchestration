---
name: rnd
description: R&D run over the multi-session setup — measure how efficiently Claude Code sessions turn tokens into finished work (cost per merged PR, finished ticket and review, context size, waste counts, time to done), check whether last run's proposals landed, and rank the next changes. Use when invoked as /rnd, when started as the weekly R&D run (rnd-weekly), or when asked to measure how the sessions perform.
---

# R&D run

The user runs many Claude Code sessions in parallel. A run measures how efficiently they turn tokens
into finished work, checks whether the last run's proposals landed, and ranks the next few changes.
Efficiency is **per unit of work**, not weekly spend: the user spends saved tokens on more work, so a
weekly total stays flat.

This file is the default brief. A project adds to it in `.claude/rnd-brief.md` (its units' CLI
commands, its own checks); where the two disagree, the project's brief wins. Started by `rnd-weekly`
(cron) or by hand as `/rnd`: same steps either way. It's opt-in: nothing runs until someone invokes it or
schedules it.

## Rules

- Read-only outside the replies folder. Change nothing else: no settings, hooks, scripts, CLAUDE.md,
  Jira, PRs. Proposals go in the report; the user approves them.
- Never print transcript bodies; `rnd.py` caps snippets. No Claude attribution anywhere.
- Report only this run. Don't sweep or report other sessions' tickets.
- Don't arm watchers or ScheduleWakeup. Finish in one pass.
- A proposal to disable or remove a plugin, skill or connector needs a **30-day window**
  (`rnd.py events 30`, or a 30-day tool tally), even though the rest of the run is weekly. Seven days
  missed real use once (a plugin called unused had 4 skill calls in 30 days). Hook-only plugins and
  passive LSPs count as in use.

## Where things are

- `rnd.py`, next to this file: `python3 -I rnd.py` prints its usage. It reads every account's
  transcripts (`$CLAUDE_CONFIG_DIR`, `~/.claude`, `~/.claude-*`; a `projects/` tree shared by symlink
  is read once) and all projects. `--until <UTC time>` reruns an old window.
- Two commands read the planner's work: `chunks [days] [--session PREFIX]` gives one row per chunk (growth,
  peak, cost, compactions, handoff before or after one) and a per-kind `ratio` line; `trial [days=28]` gives the
  planner arm against the off arm.
- Replies folder: the one the project's `CLAUDE.md` names (the orchestrating-sessions skill's "folder
  for this"). None named: stop and say so. Below, `<R>` is that folder.
- Reports: `<R>/rnd-run-<N>.md` and `.html`. Data: `<R>/rnd/run-<N>/*.tsv`, a fresh folder per run.
- Refusals logged by the plugin's hook: `~/.cache/session-status/denied.jsonl` (from 0.22.0 on).

## Steps

1. Read the project's `CLAUDE.md`, its project memory if it names one (R&D entries there override the
   yardstick below; with an index, read the topic files whose trigger is R&D), `.claude/rnd-brief.md`
   if present, and the highest-numbered `<R>/rnd-run-<N>.md`
   with its "Next run" section. This run is `N+1` (1 if none).
2. Run `rnd.py` over 7 days into `<R>/rnd/run-<N+1>/`. Look at three raw rows of each TSV before
   tallying it.
   - `sessions 7 > sessions.tsv`, `events 7 > events.tsv`, `events 30 > events30.tsv`,
     `waits 7 5 > waits.tsv`, `bgtasks 'session-status.*--watch' 7 > bg-watch.tsv`, plus any
     `bgtasks` regex the project brief names, and `replies 7 > replies.tsv` (lost reports).
   - `context 7 <split> <project> > context.tsv` (split: last run's end, so the slice after it gets its own
     row; project: the regex for the project's folder, e.g. `myproj`) and `units 7 --project <project>
     > units.tsv 2> units.txt`, adding `units <slice days>` for the slice. Pass the brief's regexes with
     `--merge`/`--done`/`--post` when its commands differ from the defaults (`rnd.py` usage).
   - `triggers <coordinator> 7`: the coordinator is the first name
     `bash <orchestrating-sessions skill folder>/session-status --coordinator` prints, run from the
     project root (`triggers` takes a session name or an id prefix). Add an earlier coordinator's id
     when last run's "Next run" names one.
   - Refusals: count them from `denied.jsonl` for the window when it covers it, else from `deny` rows
     in `events.tsv` whose `test` column is empty (`-p`/`dontAsk`: headless permission tests); say which
     source was used. A denial whose text (a deny row's `detail2`, after `source/reasonType: `) starts "Background session: this compound command" is the
     plugin's split hint (0.36.0+), not a refusal: count those separately, and leave them and the retry
     after each out of the refusal and retry-waste counts, so runs stay comparable.
3. Measure the yardstick, with last run's number beside each:
   - $ and tokens (output + cache write + cache read) per merged PR, per finished ticket and per
     review posted: `units.tsv` and its totals line, counted from the sessions' own transcripts (only
     commands that ran), not a tracker sweep.
   - Base context per session (first request, median) and average context per request; requests
     above 200K and their excess tokens: `context.tsv`.
   - Waste counts: classifier refusals, retries after a denial (same command opening, ≤5 min),
     `!`/`claude attach` handoffs to the user (`bang` rows are a session's suggestion, one per distinct
     session and command; `ran` rows are the user running one), wrong relayed claims (`self` rows plus corrections),
     resume forks (`fork` rows in `context.tsv`), lost reports (bg tasks SILENT, `replies.tsv`
     rows). A `NO NOTICE YET` task was still running at the window's end: not lost.
   - Not counted yet (known gaps, so figures stay comparable run to run): subagent transcripts
     (`<session>/subagents/*.jsonl`), and history a fork copied from its parent is counted again in
     the fork's row. Name them when a figure hinges on them.
   - Time to done: review written → posted, "merge it" → merged.
   - Weekly $ only as context, one line.
   - Feature use: `usage 30 > usage.tsv`. Each `unused` row (0 uses in 30 days, there all window) is a
     candidate to drop or merge: at most one proposal listing them, never a removal on the run's own say. Pane
     buttons show `-` without `telemetry: local` (setting-up-coordination, Config): say so, and judge them not at all.
     The same log holds `chunk` lines (`session-status --plan … --done N` writes one per landed chunk, under
     `telemetry: local`).
   - Planner sizing, when the usage log has chunk lines: `chunks 7 > chunks.tsv`. Report the `ratio` per kind
     (median act/est), and propose a new size multiplier for a kind whose median strays past 1.0 ± 0.3. Add
     `trial > trial.tsv`: it prints the arms, and the run compares them week over week against last run's.
   - Handoff entries, when the project sets `pending.file`: `handoff 28 > handoff.tsv 2> handoff.txt`. Give
     the on-you wait per blocker bucket, entries with reason `unknown`, recurring entries (rounds > 1), and
     detail and history bytes beside last run's. Read the top 5 rows by `wait_d` and the top 5 by `rewordings`
     (their history files, by `session-status --pending-history LABEL --last 10`, not whole) and name the
     issues that recur; one proposal at most. `history read` against `unread` in `handoff.txt` says whether
     sessions that opened a history file did better: report it, and say when either side is under 5 entries.
4. Run the project brief's own checks. If the project memory index has a graduation rule and the
   brief has no graduation check of its own, read every topic file, apply the rule to each entry, and
   list the ones to graduate (entry, target doc and section, why) and to drop, as one proposal outside
   the 5 below. Either way, give memory's size (index plus topic files, bytes / 4) beside last run's,
   and put it in "Next run".
5. For each of last run's ranked proposals, say whether it landed (look at the file or setting it
   targets) and whether its waste count moved.
6. Write `<R>/rnd-run-<N+1>.md`: window and totals, yardstick table (last run beside this one),
   landed / not landed, at most 5 new ranked proposals (problem, evidence with session ids, change,
   target, gain, risk), and a "Next run" section with the baselines to compare against. A proposal
   whose change is in this plugin itself becomes a feedback case instead (`../orchestrating-sessions/feedback
   add`, in the plugin's terms; [feedback.md](../orchestrating-sessions/feedback.md)), named in the report by
   its title. The report ends with `feedback list` (open cases, most seen first) and offers the apply
   (feedback.md, "Applying"). Then
   `python3 -I rnd.py html <R>/rnd-run-<N+1>.md <R>/rnd-run-<N+1>.html`.
7. Send the coordinator at most 5 lines by SendMessage: the report path, the top 2–3 proposals and
   anything that needs the user. Resolve it at send time (step 2's command). None running: skip the
   message; the report is enough.

## Done when

`rnd-run-<N+1>.md` and `.html` exist with every yardstick row filled (or "no data" and why), and the
coordinator message is sent or skipped for a stated reason.

## Scheduling the weekly run

`rnd-weekly`, next to this file, starts `claude --bg -n rnd-weekly-<date>` in a project root with this
skill as its brief, and logs to `~/Library/Logs/rnd-weekly.log` (`RND_LOG` overrides). It needs the
plugin enabled in the account it runs under. `rnd-weekly <root> --dry-run` prints the command without
starting it. Point the schedule at a stable checkout of the plugin, not the versioned install cache.

- cron (`crontab -e`), Mondays 12:00 local:

  ```
  0 12 * * 1 <plugin checkout>/plugins/session-orchestration/skills/rnd/rnd-weekly <project root>
  ```

  Prefix `CLAUDE_CONFIG_DIR=<config dir>` to run it under another account.
- launchd, when cron can't run it (macOS without Full Disk Access for cron): a
  `~/Library/LaunchAgents/rnd-weekly.plist` with `ProgramArguments` = [launcher, project root],
  `EnvironmentVariables` for `CLAUDE_CONFIG_DIR`, and `StartCalendarInterval` {Weekday 1, Hour 12,
  Minute 0}; then `launchctl load ~/Library/LaunchAgents/rnd-weekly.plist`.

Self-test: `bash rnd.test.sh` (prints `ok`).

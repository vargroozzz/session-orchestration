---
name: graduate
description: The graduate pass over a project's memory, friction cases, deferred tasks and skill drafts - proven entries into their docs, the rest pruned, cases fixed, task files resolved, drafts made skills or archived, each on the user's yes. Use for /graduate, when asked to graduate, prune or tidy project memory or review deferred tasks or cases, or when an R&D run's approved proposals include graduation.
---

# Graduate

Memory, cases, deferred tasks and skill drafts are inboxes: things land there cheaply and leave once acted on. This pass proposes
where each one goes, applies what the user approves, and empties what it resolved. Nothing moves without a yes.

## 1. Gather

- **Memory**: the index the project's `CLAUDE.md` names (`Project memory: …`) and every topic file. The index's
  Graduation section states the thresholds (default: 7+ days old and still true, or cited by 3+ sessions) and how to
  count citations (a `grep -l` over the project's transcripts). Then the other way round, with no LLM call:
  `unused memory INDEX` (beside the project-memory skill) lists each entry no session cited in 14 days (`stale`), or
  in 30 (`archive`), with the words it was matched on; check those words before you trust a `stale`.
- **Project cases**: `cases list` (beside the project-memory skill; with session-orchestration, `feedback list
  --project`). Each line: times seen, status, path, title.
- **Deferred tasks** ([defer-task](../defer-task/SKILL.md)): every file in `bugfixes/`, `features/` and
  `refactorings/` of the tasks folder `cases tasks` prints (`${XDG_STATE_HOME:-~/.local/state}/session-orchestration/projects/<root, encoded>/tasks/`).
  Older setups kept them in `.claude/tasks/` of the main checkout or a worktree: sweep those too (with
  session-orchestration, `session-status --init --write --move` moves them).
- **Skill drafts** ([project-memory](../project-memory/SKILL.md#skill-drafts)): `skill-drafts sweep` (beside the
  project-memory skill), then `skill-drafts list`. The sweep is the one move without a yes: it archives the drafts no
  session saw in 30 days and names them. Name them in the proposal too, so the user can ask for one back (`restore`).
  Memory entries that are the steps of one procedure: write them up as a draft (`skill-drafts add FILE graduate`) and
  propose it with the rest, the entries as drops once it's a skill.
- **The tracker**: does the project have one? The project's `CLAUDE.md` or config names it (session-orchestration's
  `tracker`: `jira` or `github`), or a GitHub remote with issues on. Note the CLI that files a ticket; none found: no
  tracker.

## 2. Propose

Check each item against the code and docs before you propose (an entry may be stale, a task already done). Write the
proposal to a file (the replies folder the project's `CLAUDE.md` names, else `.claude/graduate-<date>.md`) and give
the user the path and the counts. One numbered line per item, so the user can answer "yes to all but 4":

```
Memory
 1. graduate  memory/deploys.md "dev DB resets at 02:00 UTC" (12 days, 4 sessions) → docs/dev-env.md, Databases
 2. drop      memory/misc.md "PROJ-12 waits on review" (resolved)
 3. merge     memory/deploys.md lines 4 and 9 (the same trap)
 4. archive   memory/misc.md "the CI cache key is the lockfile hash" (unused 34 days)
Project cases
 5. fix       2 cases, "sign-in expires hourly" (seen 5×) → scripts/login.sh refreshes the token first
Deferred tasks
 6. ticket    bugfixes/2026-10-28-retry-loop.md → Jira PROJ, Bug "Retry loop never backs off"
 7. fix       refactorings/2026-10-30-dup-parser.md → in this pass (small: one function)
 8. drop      features/2026-09-02-dark-mode.md (done in 4f2c1a0)
Skill drafts
 9. skill     cut-release (seen 3×, last 2026-10-29) → .claude/skills/cut-release/
10. drop      preview-deploy (seen once; docs/deploy.md covers it) → archived
```

- **graduate** names the doc and section that owns the situation (a `CLAUDE.md`, a doc, a skill); a topic past ~15
  entries can become its own doc. **drop**: wrong, superseded, about a resolved task state, or already in a doc.
  **merge**: two entries about the same trap. **archive**: an `unused memory` line that is still true but nobody reads
  (a `stale` one is "drop?" unless you graduate it): it moves to the `archive/` folder beside its file, out of every
  session's reading, never deleted.
- **fix** (cases): group the open cases into patterns; one fix per pattern (a doc, script or setting), naming the
  cases it closes.
- **Deferred tasks**, one of three each:
  - **ticket it**: worth doing, not now. With a tracker: the project, type and title it will be filed under. Without
    one: say so, and propose **fix it** or **drop it** instead, or keep it as a file only if the user asks to (never
    by default: the pass empties the folder).
  - **fix it**: small and clear enough to do in this pass, or in its own session/branch when it isn't (say which).
  - **drop it**: done already (name the commit), no longer true, or not worth doing.
- **Skill drafts**: **skill** (a procedure worth having, its steps still right) or **drop** (covered elsewhere, wrong,
  or a one-off). The yes is to the text that will ship: put each proposed skill's SKILL.md whole in the proposal file,
  after `skill-drafts scrub NAME` passes (reword a hit first). It goes to the project's `.claude/skills/`, committed, so
  every session and collaborator gets it.

## 3. Apply, on the user's yes

Only the numbers the user approved; ask again for anything new you find on the way.

- **Graduate and fix**: edit the docs, scripts or settings as the project's rules say (a branch and PR where the
  project works that way; the release checks its `CLAUDE.md` names). Delete a graduated entry from memory only once
  its doc change is in (merged, or committed where the project commits directly).
- **Archive**: `unused archive TOPIC_FILE 'LINE'` (the entry's whole line); `unused restore TOPIC_FILE 'LINE'` puts it
  back at the end, on the user's ask.
- **Drop and merge**: edit the memory files. Other sessions append meanwhile: edit only the lines you named, never
  rewrite a whole file from an old copy.
- **Cases**: `cases mark FILE fixed '<what changed>'` for each case the fix closes, `cases mark FILE dropped` for a
  dropped one (with session-orchestration: `feedback mark …`).
- **Ticket it**: file the ticket with the tracker's CLI (an outward-facing step: the user's yes to this pass's line
  covers exactly that ticket), then delete the task file and note the ticket's key or URL in your report.
- **Fix it**: fix it as the project's rules say, then delete the task file. Its own session: start or hand it over
  with the task file's content as the brief, and delete the file once that session has it.
- **Drop it**: delete the task file.
- **Skill**: in the checkout or worktree the change goes in, `skill-drafts promote NAME .claude/skills` (it archives the
  draft); a scrub hit: reword the draft and promote again, never copy it by hand. Then the project's checks and commit,
  as for a doc. Its PR turned down: `skill-drafts restore NAME`. **Drop** (a draft): `skill-drafts archive NAME`.

Every task file the pass resolved is deleted; the tasks folder holds only what the user chose to keep.

## 4. Report

What moved where (doc and section), what was dropped, cases marked, tickets filed (keys or URLs), files deleted, skills added and drafts archived, and
anything left for the user. With session-orchestration, the R&D run proposes graduation and a followups session
applies it with this skill.

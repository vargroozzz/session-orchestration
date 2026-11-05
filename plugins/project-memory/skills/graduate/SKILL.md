---
name: graduate
description: The graduate pass over a project's memory, friction cases and deferred tasks - moves proven memory entries into the docs that own them, prunes the rest, turns open project cases into fixes, and resolves .claude/tasks/ files (ticket it, fix it or drop it), each on the user's yes. Use when invoked as /graduate, when asked to graduate, prune or tidy project memory, review deferred tasks or project cases, or when an R&D run's approved proposals include graduation.
---

# Graduate

Memory, cases and deferred tasks are inboxes: things land there cheaply and leave once acted on. This pass proposes
where each one goes, applies what the user approves, and empties what it resolved. Nothing moves without a yes.

## 1. Gather

- **Memory**: the index the project's `CLAUDE.md` names (`Project memory: …`) and every topic file. The index's
  Graduation section states the thresholds (default: 7+ days old and still true, or cited by 3+ sessions) and how to
  count citations (a `grep -l` over the project's transcripts).
- **Project cases**: `cases list` (beside the project-memory skill; with session-orchestration, `feedback list
  --project`). Each line: times seen, status, path, title.
- **Deferred tasks**: every file in `.claude/tasks/bugfixes/`, `.claude/tasks/features/` and
  `.claude/tasks/refactorings/` ([defer-task](../defer-task/SKILL.md)), in the main checkout and in any worktree
  that still has its own.
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
Project cases
 4. fix       2 cases, "sign-in expires hourly" (seen 5×) → scripts/login.sh refreshes the token first
Deferred tasks
 5. ticket    bugfixes/2026-10-28-retry-loop.md → Jira PROJ, Bug "Retry loop never backs off"
 6. fix       refactorings/2026-10-30-dup-parser.md → in this pass (small: one function)
 7. drop      features/2026-09-02-dark-mode.md (done in 4f2c1a0)
```

- **graduate** names the doc and section that owns the situation (a `CLAUDE.md`, a doc, a skill); a topic past ~15
  entries can become its own doc. **drop**: wrong, superseded, about a resolved task state, or already in a doc.
  **merge**: two entries about the same trap.
- **fix** (cases): group the open cases into patterns; one fix per pattern (a doc, script or setting), naming the
  cases it closes.
- **Deferred tasks**, one of three each:
  - **ticket it**: worth doing, not now. With a tracker: the project, type and title it will be filed under. Without
    one: say so, and propose **fix it** or **drop it** instead, or keep it as a file only if the user asks to (never
    by default: the pass empties the folder).
  - **fix it**: small and clear enough to do in this pass, or in its own session/branch when it isn't (say which).
  - **drop it**: done already (name the commit), no longer true, or not worth doing.

## 3. Apply, on the user's yes

Only the numbers the user approved; ask again for anything new you find on the way.

- **Graduate and fix**: edit the docs, scripts or settings as the project's rules say (a branch and PR where the
  project works that way; the release checks its `CLAUDE.md` names). Delete a graduated entry from memory only once
  its doc change is in (merged, or committed where the project commits directly).
- **Drop and merge**: edit the memory files. Other sessions append meanwhile: edit only the lines you named, never
  rewrite a whole file from an old copy.
- **Cases**: `cases mark FILE fixed '<what changed>'` for each case the fix closes, `cases mark FILE dropped` for a
  dropped one (with session-orchestration: `feedback mark …`).
- **Ticket it**: file the ticket with the tracker's CLI (an outward-facing step: the user's yes to this pass's line
  covers exactly that ticket), then delete the task file and note the ticket's key or URL in your report.
- **Fix it**: fix it as the project's rules say, then delete the task file. Its own session: start or hand it over
  with the task file's content as the brief, and delete the file once that session has it.
- **Drop it**: delete the task file.

Every task file the pass resolved is deleted; `.claude/tasks/` holds only what the user chose to keep.

## 4. Report

What moved where (doc and section), what was dropped, cases marked, tickets filed (keys or URLs), files deleted, and
anything left for the user. With session-orchestration, the R&D run proposes graduation and a followups session
applies it with this skill.

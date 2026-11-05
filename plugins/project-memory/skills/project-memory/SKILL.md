---
name: project-memory
description: A project's shared memory across Claude Code sessions, and its friction cases. Use when the project's CLAUDE.md names a project memory file (read it when you start a task; append what another task would need), when the user says "remember this" about the project, when asked to set up project memory, or the moment the project itself (its hosts, sign-ins, docs, scripts) cost you a workaround, an extra round trip or the user's help.
---

# Project memory

What one task learned that another needs: decisions the user made, pitfalls, conventions found the hard way. It lives
in the project as an index (`memory.md`) over topic files (`memory/*.md`), and the project's `CLAUDE.md` names the
index with a line like ``Project memory: `docs/claude/memory.md` ``.

## Reading and appending (any session)

Read the index when you start a task. Each topic has a "read when" trigger: read the topic files whose trigger
matches your task, whole, and skip the rest; read one later when the work reaches it. (A project with a single flat
file: read it whole.) When you learn something another task's session would need, append it to the matching topic
file, one line per entry:

```
- <YYYY-MM-DD> <TASK>: <the decision or pitfall, and why, in one line>
```

- Worth an entry: a decision the user made that outlives the task ("feature flags go in config, not env"), a pitfall
  that cost time ("the dev DB resets at 02:00 UTC"), a convention found the hard way. Not: your task's progress, or
  what a `CLAUDE.md` or doc already says.
- No topic fits: the catch-all topic the index names (`misc.md`), never the index itself.
- Append only, with `>>` or an edit at the end; never rewrite or delete other lines. Other sessions write it too.
  Deleting, merging and moving entries is the prune's and the [graduate](../graduate/SKILL.md) pass's.
- The user says "remember this" about the project: append it the same way.
- In a repo with a committed `.claude/coordination/memory.md` (session-orchestration's shared mode), read it too, and
  tag an entry true and useful to a collaborator on another machine `[team]` (`- <date> <TASK>: [team] …`); in doubt,
  leave it untagged. Never write to the committed file yourself.

## Setting it up

`memory-init DIR [--topic FILE TITLE TRIGGER]…` (beside this file) writes the index and a topic file per `--topic`,
plus the catch-all `misc.md`, only where missing; `--dry-run` lists them first. Propose a folder (`docs/claude/` or
wherever the project keeps notes for Claude) and two or three topics from the project's areas, write on the user's
yes, then add the `Project memory:` line to the project's `CLAUDE.md` (or `CLAUDE.local.md` when the memory is
personal). session-orchestration's setup does this for you.

## Pruning

Memory is an inbox, not the home: every session start pays for it, so the index stays short and entries leave once
they've proved themselves. On the user's ask (with session-orchestration, the coordinator does it in passing):
delete an entry that is wrong, superseded, about a task state that has since resolved, or already in a `CLAUDE.md`,
a doc or a skill; merge two about the same trap. A flat file past a screen or so gets split into topics: build the
topic files and the new index as copies, re-check for lines appended meanwhile, and swap the index in with one `mv`,
so no session's append is lost. Moving entries into the docs is the [graduate](../graduate/SKILL.md) pass.

## Project cases (friction)

File a case the moment you tell the user about friction the project caused (its hosts, sign-ins, docs, scripts): you
worked around it, took an extra round trip, misreported because of a file or a script's output, or the user had to
step in. Then carry on with your task.

```
cases add bugfixes 'Dev host sign-in expires hourly' --where scripts/login.sh:12 \
  --found 'a task session; deploying' --evidence 'deploy failed with 401 after an hour' \
  --suggested 'refresh the token before deploying'
```

- `cases` is beside this file; `cases` alone prints its usage. Category: `bugfixes`, `features` or `refactorings`.
  `--where` is the project file at fault, or the step's name. Write it in the project's own terms.
- Exit 3 lists open cases that look the same. If one is, `cases seen FILE` adds today to its `seen:` line (that count
  ranks it); otherwise rerun with `--new`.
- With session-orchestration, use its `feedback add --project …` instead: the same cases, in the store its config
  names.

A case file, in `${XDG_STATE_HOME:-~/.local/state}/session-orchestration/feedback-projects/<project root, encoded>/`
(outside the repo, so a worktree-isolated session can write it, and never committed):

```markdown
# Dev host sign-in expires hourly
- where: scripts/login.sh:12
- found while: a task session; deploying
- project: /home/u/app
- evidence: deploy failed with 401 after an hour
suggested: refresh the token before deploying
- seen: 2026-10-25, 2026-10-27
- status: open
```

`cases list`, `cases count`, `cases mark FILE fixed '<what changed>' | dropped`. The graduate pass turns open cases
into fixes.

## Deferred tasks

An out-of-scope bug, feature or refactor you notice goes to `.claude/tasks/` ([defer-task](../defer-task/SKILL.md));
the graduate pass sweeps them too.

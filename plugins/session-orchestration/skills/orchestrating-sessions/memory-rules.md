# Handoff file and project memory: the details

The coordinator's rules beyond the core's short form. Read this when you resolve a handoff entry while config
`pending.file` is set, need an entry's past, split or prune project memory, carry `[team]` lines, graduate an entry,
or act on an R&D run's approved proposals.

## Handoff file with `pending.file`

- Without config `pending.file`, delete an entry the moment it's resolved. With it (the file is `DIR/NAME.md`),
  resolve it with `session-status --pending-done LABEL -- REASON` instead of deleting the line: the entry moves to
  the archive (`NAME-archive.md`, one line each, with its dates and REASON) with its files. LABEL is the entry's
  text after its date, up to the first ` (` or `:` (`PROJ-12 (abc): …` → `PROJ-12`). Adding or rewording an entry
  stays a plain edit, but keep its LABEL: a new LABEL is a new entry, and the old one is archived with reason
  `unknown`.
- Detail that doesn't fit the line goes in `NAME/SLUG.md` beside the file. SLUG is LABEL with each run of characters
  other than `A-Za-z0-9._-` turned into `-` (`deploy window` → `deploy-window`). Keep it under 4 KB, with only
  what's current (Notices says when it grows past).
- A hook records every wording of every entry in `NAME/SLUG.history.md` as the file changes. `--pending-history
  LABEL [--last N]` prints it. It's for R&D and for the rare entry whose past you need: don't read history files by
  default.

## Project memory

The project's `CLAUDE.md` may name a project memory file, e.g. `Project memory: docs/claude/orchestration/memory.md`,
as it names the replies folder. It holds what one task learned that another needs: decisions the user made,
pitfalls, conventions found the hard way. Any session appends to it and every new session reads it
([worker.md](worker.md), Project memory).

Memory is an inbox, not the home: every session start pays for it, so it stays an index over topic files read on
demand, and entries leave once they've proved themselves. A flat file past a screen or so gets split that way by a
session you start: it builds the topic files and the new index as copies, re-checks for lines appended meanwhile,
and swaps the index in with one `mv`, so no worker's append is lost.

- Prune in passing, as [SKILL.md](SKILL.md) (Project memory) says. You and whoever the index names for graduation
  are the only ones who delete or rewrite entries; sessions only append.
- **Team memory** (shared mode): a line true and useful to a collaborator on another machine, with another account
  and coordinator, is tagged `[team]` (`- <date> <TASK>: [team] …`); in doubt, it's personal. Read the repo's
  `.claude/coordination/memory.md` too when it exists. `[team]` lines never go into it directly: when you prune,
  have a session gather them into one PR that adds them to `.claude/coordination/memory.md` (created by that PR if
  missing), then delete them from your memory once it's merged. Without shared mode they stay in yours.
- **Graduation** moves an entry into the project doc that owns its situation once it has proved itself: old enough
  and still true, or cited by several sessions. The index states the project's thresholds and who runs it (e.g. the
  weekly R&D run proposes, a followups session applies). It edits a doc, so it's a session's job, not yours: the
  session runs project-memory's `graduate` skill (`/graduate`), which also resolves open project cases and
  `.claude/tasks/` files.
- **An R&D run only measures and proposes** (the `rnd` skill). When the user approves some of its proposals, start a
  fresh followups session for them (`claude --bg -n rnd-<N>-followups`, N the run's number; brief: that run's report
  in the replies folder plus the approved numbers, reporting in `replies/rnd-<N>-followups.md`). Never resume the
  R&D session for it. A proposal built from project feedback cases names them: the followups session marks each
  `feedback mark FILE fixed '<what changed>'` once its fix lands ([feedback.md](feedback.md)).

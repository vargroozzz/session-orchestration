# Handoff file and project memory: the details

The coordinator's rules beyond the core's short form. Read this when you resolve a handoff entry while config
`pending.file` is set, need an entry's past, append to, split or prune project memory, file a lesson the user gives you, carry `[team]` lines, graduate an entry,
or act on a retro's approved proposals.

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
  LABEL [--last N]` prints it. It's for retro and for the rare entry whose past you need: don't read history files by
  default.

## Project memory

The project's `CLAUDE.md` may name a project memory file, e.g. ``Project memory: `~/.local/state/session-orchestration/projects/-home-u-app/memory.md` ``,
as it names the replies folder. It holds what one task learned that another needs: decisions the user made,
pitfalls, conventions found the hard way. Any session appends to it and every new session reads it
([worker.md](worker.md), Project memory).

Memory is an inbox, not the home: every session start pays for it, so it stays an index over topic files read on
demand, and entries leave once they've proved themselves. A flat file past a screen or so gets split that way by a
session you start: it builds the topic files and the new index as copies, re-checks for lines appended meanwhile,
and swaps the index in with one `mv`, so no worker's append is lost.

Sessions append to it; you prune it.
- **Friction is feedback, not memory.** A step you missed or worked around because of this plugin (its docs,
  scripts, tools) goes to `feedback add`, and one the project caused to `feedback add --project`
  ([feedback.md](feedback.md)), never a memory line. Memory holds project facts and the user's preferences.
- **A lesson the user gives you** that comes from a missing plugin step is filed with `feedback add`, and from a
  missing project-script step with `feedback add --project`, in addition to any memory line. When it's unclear which
  of plugin feedback, project feedback or memory it is, queue one `ask_approval` with those three before writing.
- When the user tells you to remember something for the project, or a preference about how you coordinate, append
  it to the coordinator topic file (a flat file: append there). A preference a config key holds (`start.mode`,
  [sessions.md](sessions.md)) goes in that key instead.
- Prune in passing: delete an entry that is wrong, superseded, about a task state that has since resolved, already
  in a `CLAUDE.md`, a doc or a skill, or a caution whose reason no longer holds; merge two about the same trap; and
  rewrite an absolute rule ("never X") with its scope and reason. Splitting a flat file, `[team]`
  lines, graduation and retro follow-ups: below.
- You and whoever the index names for graduation are the only ones who delete or rewrite entries; sessions only
  append.
- **Team memory** (shared mode): a line true and useful to a collaborator on another machine, with another account
  and coordinator, is tagged `[team]` (`- <date> <TASK>: [team] …`); in doubt, it's personal. Sessions read the repo's
  `.claude/coordination/memory.md` (and its `memory/<topic>.md`, P's topic names) before yours ([worker.md](worker.md),
  Project memory). `[team]` lines never go into it directly: when you prune, run `session-status --init
  --team-memory` (the gather). It drops from your memory the `[team]` lines origin's team memory has already, then
  commits the rest verbatim to the same topic (`.claude/coordination/memory/<topic>.md`, a flat memory's to
  `misc.md`, the index row added), deduped and scrubbed, on `coordination/memory-<date>-<time>` in a worktree from
  origin/<default>, and prints a `Team PR:` line: one pane ask with its diff, as `--shared`'s. Its lines leave your
  memory on the first gather after the merge; while it's open (`Team PR open:`) no second one opens. A line it
  keeps (`Kept in your memory`: a home path, an email) stays personal until reworded. `merge=union` on the topic
  files lets two people's gathers rebase cleanly. Without shared mode they stay in yours.
- **Graduation** moves an entry into the project doc that owns its situation once it has proved itself: old enough
  and still true, or cited by several sessions. The index states the project's thresholds and who runs it (e.g. the
  weekly retro proposes, a followups session applies). It edits a doc, so it's a session's job, not yours: the
  session runs project-memory's `graduate` skill (`/graduate`), which also resolves open project cases and
  deferred task files (in the folder `cases tasks` prints).
- **A retro only measures and proposes** (the `retro` skill). When the user approves some of its proposals, start a
  fresh followups session for them (`session-status --launch retro-<scope>-<N>-followups --kind build --brief-file
  FILE`, from the report's name `retro-<scope>-<N>`; FILE's brief: that report in the replies folder plus the approved numbers, reporting in
  `replies/retro-<scope>-<N>-followups.md`; a proposal that edits an untracked person file is yours to
  make, since no `--bg` session may edit the main checkout: SKILL.md Rules). Never resume the
  retro session for it. A proposal built from project feedback cases names them: the followups session marks each
  `feedback mark FILE fixed '<what changed>'` once its fix lands ([feedback.md](feedback.md)).

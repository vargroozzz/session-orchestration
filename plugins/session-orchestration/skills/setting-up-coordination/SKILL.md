---
name: setting-up-coordination
description: Sets a project up for coordinated sessions (one coordinator, parallel task sessions) - detects tracker, host and task keys, writes the adapter, CLAUDE.md section and config. Use for "coordinate this project", setting up or checking coordination, when open_pane says the folder isn't set up, or to change a coordination config value (tracker, host, key_pattern, terminal, approvals.*, start.*, features.*, retro.*, docs_watch.*, report_artifacts.*).
---

# Setting up coordination

A folder not set up for coordination has no adapter and no `CLAUDE.md` section naming a replies folder, so the
coordinator has nothing to read. `open_pane` checks (`session-status --init --check`) and says so in its result.
`session-status` is in the `orchestrating-sessions` skill's folder; `--init` runs `session-init`, next to this file.

## Check

`session-status --init --check`, from the folder: one line, exit 0 configured, 1 unconfigured or partial, 3 covered
by a parent. Configured adds:
- `active: tracker=… host=… delegate=on|off pr_create=on|off start=…[,feedback_apply:…][,sidebar] terminal=… messages=… features=…|none`: the config in effect, then an
  indented line per doc of the terminal, the messages module and each feature that's on: `  <name>: <start step> Read
  <doc> when <events>`, from the doc's `> **Start**:` and `> **Read when**:` lines (`  <name>: read <doc> now` when
  it has none). `session-status --start` shows them to the coordinator. With review_inbox on, `  review_inbox url:
  <url>` follows: this account's inbox (the one URL the docs name, else the one on the line naming this account's
  config dir), which open_pane watches;
- `detected <terminal>: run setup to record it (…)` when it runs in a terminal it has a module for and `terminal` is
  unset;
- `[m2 ask] second account found, accounts off: …` when another Claude account shares
  this one's transcripts and `features.accounts` is off;
- `committed code new or changed upstream: REL…: run setup to review it` (shared mode, below);
- `team[ (DIR)]: section, memory, review-brief, adapter (trusted|not trusted[, local wins])`: not a warning, the team files git
  tracks in the team folder, which sessions read before the person's (worker.md, Project memory); `section`: the
  committed `CLAUDE.md` has the team section (one repo only). DIR, in a
  workspace, is that folder (relative to the root when inside it); without it, `.claude/coordination/`;
- `pending.file and history.dirs are ignored in the repo file (…)` when the repo file still sets them: move them to
  `.claude/coordination.local.json`;
- a warning per config value that isn't valid (the default is used), per terminal or feature module that doesn't
  load (see status-reference.md, Modules), and, when `CLAUDE.md` still delegates approvals
  in words with no `approvals.delegate` key, `delegation found in CLAUDE.md: run setup to move it`;
- `coordinator files outside <P> (FILES): run session-status --init --write --move` when the replies folder, the memory,
  the handoff file, a brief or `.claude/tasks/` isn't in the project's state folder P,
  `${XDG_STATE_HOME:-~/.local/state}/session-orchestration/projects/<root, as Claude names its projects folder>/`
  (a task session isolated in a worktree can't write into a checkout). Setup puts every new file there: `replies/`,
  `memory.md` and `memory/`, `pending.md`, the briefs. Run the command as printed, in this folder (no `cd`): it
  moves an older setup's replies, memory, handoff (with `<name>/`, `<name>-archive*` beside it), briefs and
  `.claude/tasks/` into P, rewrites their lines in `CLAUDE.local.md` (or an untracked `CLAUDE.md`), the adapter's
  paths, quoted or not (its `pending)` line), then runs the plain `--write`. A handoff file config `pending.file`
  names is the person's choice: it stays where it is. It moves only from inside the root or the old state replies
  folder, never what git tracks there (a remote-less nested repo's files do move), and nothing at all when a target exists in P or the committed `CLAUDE.md`
  or adapter names such a path (it names them). A second run says
  `nothing to move`. `--link` adds a `.coordinator` symlink to P in the root, kept out of git. When the tracked
  `CLAUDE.md` holds those files' path lines, the line says so and lists them (`--move` refuses until they're in
  `CLAUDE.local.md`): that edit changes a tracked file, so it's the user's call or a task session's PR;
- `project Stop hook commits a folder (COMMAND): …` when a Stop hook in the project's `.claude/settings*.json` runs a
  script that git-commits (a hand-made auto-history). See Propose's **Hand-made history hook**;
- `[m4 auto] old brief name …` (an `rnd-brief.md` left beside the memory), `[m5 ask] the crontab still runs
  rnd-weekly …`, `[m6 ask] a start mode in memory …` (a start-mode line in memory while `start.mode` is unset),
  `[m9 auto] .claude/session-status-adapter names files already moved to <P> …` (an earlier move left the local
  adapter's unquoted or double-quoted paths behind: a missing path whose name is in P) and `[m10 ask] FILE has lines
  from an older setup template …` (the section or local adapter as an older template wrote it).

Each line that names an older layout starts with `[mN CLASS] ` (m1 delegation, m2 terminal, second account or review
inbox, m3 Stop hook, m4 brief name, m5 crontab, m6 start mode, m7 files outside P, m8 repo-file keys, m9 adapter
paths, m10 template drift). CLASS `auto`: `session-status --init --migrate` fixes it unasked; `ask`: it needs the user's yes (m8 asks when
the repo file is tracked, m7 while other sessions of the project run; m7 is `hand` when the tracked `CLAUDE.md` holds the path lines). The move rewrites every word of a local adapter that names a moved path, quoted or not.
`--migrate [--dry-run]` runs the check, then fixes each auto one in the order m1–m6, m8, m7, m9, backing up the
files it rewrites to `P/migrate-backup/<date>/` and logging each step to `P/migrate.log` (a run after one that
stopped midway resumes from it), lists the ask ones as open, and stamps `P/setup.json` with the layout once none is
left (`current: layout N` on the next run). `--dry-run` prints what it would do and writes nothing. Each open ask or
hand line comes with what its answer changes; `--apply=ID [--dry-run]` runs one ask id's fix, `--decline=ID` puts an
ask or hand id away (kept in `P/setup.json`'s `declined`, which the stamp then ignores; `--check` still names it). m7
asks instead of moving while other sessions of the project run (`--decline=m7` only puts it off). Two runs at once:
the second prints `busy: …` and does nothing. A stamp from a newer plugin's layout: `--migrate` prints which and
stops, `--write` refuses; update this account's plugin (so too a committed repo file's `layout`). A fix to a file git
tracks goes to a team PR on `coordination/migrate-<id>`, never the checkout: hand its `Team PR:` line as `--shared`'s
(below); while it's open, `--migrate` lists `[ID wait]` and stamps once it merges and you pull. `session-status --start` runs `--migrate` first (a
`## Migration` section when it asks or fails), and `open_pane` turns each open ask or hand id into a pane ask
`migrate-<id>`. Details per id: [migrations.md](migrations.md).

## Propose, then write

- **Unconfigured** (or partial): run `session-status --init`. It reads only the folder, its repos and their remotes
  (no tracker call) and prints a numbered proposal: task keys, code host, the files it would write and the config,
  approvals, worktrees. Show it to the user as one plain-text round, unchanged, and wait. Never write before a
  "yes". The round holds the proposal's two questions, plus one you add after it (3, Purpose), each with the detected
  answer as the default:
  1. **Tracker**: `none` (a task is a short name), `github` (issues and PRs through `gh`), `jira` (task keys only:
     the adapter setup writes, GitHub's for code on GitHub with `gh` (PRs, CI) or else a stub, makes no Jira calls,
     so the board shows no ticket status until the user adds those for their own Jira CLI; status-reference.md, the adapter contract). Say so when proposing `jira`.
  2. **Approvals**: may a coordinator's message stand in for the user's in task sessions? Default **no**.
  3. **Purpose**: one line on what this project's coordinator is for (e.g. "this machine's setup", "requests to the
     IT team"); other coordinators route a matter to it by that line (`session-status --coordinators`). Default: none.
- **On "yes"**: `session-status --init --write`, plus `--delegate` only if the user said so (delegation is theirs to
  give: it makes the coordinator's messages count as theirs), and each correction as `KEY=VALUE` (the names on the
  proposal's `Facts:` line; `tracker=` and `host=` among them), then `session-status --purpose 'LINE'` when they gave a
  purpose. It writes only missing files, appends the section to
  an existing `CLAUDE.md`/`CLAUDE.local.md` that lacks one, and keeps the new ones out of git through
  `.git/info/exclude`, the config files first. Then `session-status --init --check` (expect `configured`), call
  `open_pane` again (it names the session `<folder>-coordinator` only now), and carry on with the coordinator's start.
- **Covered by a parent**: a folder above this one has an adapter and its coordinator covers this folder. Tell the
  user and ask whether this folder gets a coordinator of its own; write nothing unless they say yes, then
  `--init --own` (proposal) and `--init --write --own`. A folder with its own adapter is its own project even under a
  parent's: its coordinator's pane shows only its own tasks.
- **Committed code to review** (a repo in shared mode with a committed adapter or module): the proposal lists each
  file with its sha256 and the `--trust=REL@SHA` arguments. Show the user each file whole and ask in the same round;
  pass the `--trust` arguments only on their yes. `--trust` refuses a file that changed since it was shown. A trusted
  committed adapter is used instead of writing a local one; declined, a local adapter is written as usual.
- **Hand-made history hook** (the `--check` line above): read the script, find the folder it commits, and ask the user
  in one plain-text round whether the plugin's history hook takes it over: the folder goes into `history.dirs` in
  `.claude/coordination.local.json` (Config), the hook entry leaves `.claude/settings*.json`, and the script goes if
  nothing else runs it. Its repo, at the top of the folder with no remote, is adopted with its history; one commit per
  repo per turn, the session's name in the message, as such a hook does. Change nothing before their yes; a folder
  with a remote isn't adopted (its history would start over in an outside repo): say so and leave the hook.
- **Optional briefs**, on the user's request (`--init` lists the missing ones, also once set up): `--write
  --review-brief` writes `review-brief.md` beside the memory, or beside a handoff file setup wrote (P for a new setup, and P while the memory is outside the project); name it in each PR reviewer's
  first prompt (`Review <repo>#<id> (<KEY>). Brief: <path>`). A repo that commits the team's conventions in
  `.claude/coordination/review-brief.md` (`--check`'s `team:` line lists `review-brief`; a workspace's says
  `team (DIR):`, the team repo's folder (relative to the root when inside it), so the path is `DIR/review-brief.md`) gets both, the team's first:
  `Brief: .claude/coordination/review-brief.md, then <path>`; the personal one wins where they differ. `--write
  --retro-brief` writes `retro-brief.md` beside the memory file (older setups: `.claude/retro-brief.md`),
  which the `retro` skill reads.
- **Retro schedule**, when the user wants scheduled retro runs or a `--check` shows `features.retro` on with no
  agent (`skills/retro/retro-run --status ROOT` in the plugin says `not installed`): propose, in one plain-text round,
  `features.retro: true` and a `retro` block in the person file (`schedule` `mon 12:00` unless they name another,
  `scope` `project` (`both` in the plugin's own repo), `account` when it's not the current one; Config).
  On their yes write it and run `retro-run --install ROOT`, or hand it as one command when that's refused; it prints a
  crontab line to remove when an old `retro-weekly` one still runs: hand that too, never edit the crontab.

## Migrations

A project set up by an older plugin version may need a step the newer layout expects. `migrations.md`, next to this
file, lists each one: id, the release it follows, class (auto, ask or hand), the `--check` line that detects it
(prefixed with its id, `[m7 auto] …`) and the fix. When you change what setup writes, or where a project's files live,
add the migration in the same PR; its "Adding a migration" section has the steps, and `migrations.test.sh` fails on
an id in the code with no row or no fixture.

## Shared mode

The rules for two or more people on one project (what is shared, what never is, approvals, ownership, what a team
file may hold): `team.md`, next to this file.

Off by default: setup writes nothing a collaborator sees (everything goes to `.git/info/exclude`d files and
`CLAUDE.local.md` when `CLAUDE.md` is tracked; it never edits a tracked `CLAUDE.md` or `AGENTS.md`). Only when the
repo's owner wants it, on the user's request. When git shows other authors, the proposal says so in one line and
names "shared"; it never asks. `session-status --init --write --shared` writes the personal files as usual (this
checkout's copy of the repo file stays excluded too) and commits the team files that `origin/<default>` lacks on
`coordination/setup-<date>`, in a worktree of its own (`<repo>/.worktrees/coordination/setup-<date>`, `/.worktrees/`
excluded) with the person's git identity, so the main checkout stays clean:
- **A newcomer's clone** (the repo file is committed): `--check` says `shared coordination found: run setup`, and the
  proposal asks no repo key (tracker and host come from the committed file), names the team files found and asks only
  trust, delegation and terminal; `--write` writes personal files only, and excludes `/.worktrees/` when the worktree
  command uses it, so `git status` stays clean. `--shared --plugin` also puts `.claude/settings.json` (the plugin
  enabled, its marketplace added) in the team PR: off by default, since it offers the plugin to every collaborator.
- **Shared** (read by every collaborator once merged): `.claude/coordination/coordination.json` (repo keys only:
  tracker, host, features.review_inbox, plus any repo key set in this checkout's file) and the `.gitattributes` lines
  `/.claude/coordination/memory.md merge=union` and `/.claude/coordination/memory/*.md merge=union`, so two people's
  team memory appends merge on rebase (the coordinator's prune adds them with `--team-memory`, memory topic by topic:
  orchestrating-sessions' memory-rules.md). This checkout's exclude hides only the repo file, not the folder, so team
  files added there later show in `git status`. In one repo (not a workspace, whose sessions start above the team
  repo), also the team section `## Coordinated sessions (team)` appended to `CLAUDE.md`: the section template's rule
  lines (approvals, the reserved list, task names, branches, worktrees), no path, name or coordinator.
- **Personal** (out of git, this machine only): everything else it writes, as in a solo setup; the section goes to
  `CLAUDE.local.md`, whole until the team PR merges (no session goes without the rules). A clone whose committed
  `CLAUDE.md` has the team section gets a personal section with only its own lines (coordinator name, replies
  folder, memory, handoff) and a pointer to the team section. A whole section written earlier keeps its rule lines
  (a duplicate, harmless; delete them by hand).

Before writing anything it refuses a repo file with a person key or a line naming a home path, an email, a session
ID or a coordinator session name, and names each line. Its `Team PR:` line gives the diff command and the push + PR
command: put it on the pane as one ask with the diff (the coordinator: `ask_approval`, the diff in `details`; any
other session: `hand_command` with that command), and run it only on the user's yes: in a team repo colleagues see
the PR, so it's asked each time. Once it merges, a pull replaces this checkout's ignored repo file with the
committed one. A setup branch exists already (any day's, local or on origin): open its PR, or remove the worktree
and branch as the refusal says. A failed write or commit removes its own worktree and branch.
What may be committed there: `coordination.json`; `memory.md` and `memory/` (team memory, reached through the
coordinator's prune PR); `review-brief.md` (how the team reviews, read before each person's brief); a shared adapter
(`session-status-adapter`) and modules (`<kind>/<name>.sh`), each run by a person only once trusted. Never committed:
anything in `coordination.local.json` (delegation, terminal, accounts, `trusted`, `team`), your adapter, your memory
and replies.

Team memory's gather (`session-status --init --team-memory`, run at the coordinator's prune) drops from its memory
the `[team]` lines origin's team memory has already, then commits the rest verbatim to the same topic
(`.claude/coordination/memory/<topic>.md`, a flat memory's to `misc.md`, the index row added), deduped and scrubbed,
on `coordination/memory-<date>-<time>` in a worktree from origin/<default>, and prints a `Team PR:` line. Its lines
leave the coordinator's memory on the first gather after the merge; while it's open (`Team PR open:`) no second one
opens. A line it keeps (`Kept in your memory`: a home path, an email) stays personal until reworded.

A folder that isn't a repo itself (a workspace of repos) uses the `team` person key: the path, relative to the
folder, of the repo holding `.claude/coordination/`. Setup finds it one level down and proposes it; with several,
say `team=<folder>`. The team's `coordination.json` then supplies the repo keys, and its committed code is offered
for trust.

## Config

Two JSON files, each the nearest one up from the cwd within the project (a folder with its own adapter ends the
walk, so a subproject never reads its parent's), merged key by key (the person's file wins); a session in a worktree
below reads the project's:
- `.claude/coordination/coordination.json`, the repo's: `tracker`, `host`, `key_pattern`, `features.review_inbox`;
- `.claude/coordination.local.json`, the person's: `approvals.*`, `start.*`, `terminal`, `messages` and its module's block
  (e.g. `msgraph`), `features.accounts`, `features.accounts_weekly_switch`, `features.notify`, `features.answers`, `features.remote`, `features.retro` and the `retro` block, `pane.sections`, `features.report_artifacts` and the `report_artifacts` block, `trusted`, `team`, `feedback` (ignored in the repo file: a
  committed file never delegates or trusts for anyone, nor starts a scheduled retro, and the terminal, messages, accounts, notifications and feedback
  are the person's own);
- below both, `${XDG_CONFIG_HOME:-~/.config}/session-orchestration/config.json`, the person's for every project:
  any key but `team` (the project's file only), meant for the person-wide ones (`feedback`, `telemetry`). Setup
  doesn't write it.

Both person files are the user's to change: a session's edit of either asks the user, or is refused in a background
session (`hooks/coordinator-guard.sh`), so run setup in a session you attend to have it write them.

`handoff.*`, `compact.window`, `pending.file` and `history.dirs` are person-only too: dropped from the repo file (the
last two name personal state), and setup never writes `pending.file`.
Set `autoCompactWindow` in Claude Code settings to `compact.window` (220000). An env
`CLAUDE_CODE_AUTO_COMPACT_WINDOW` (a background daemon's included) overrides it, and the context-watch hook's
mismatch line says so.

Both are excluded from git, the repo file until shared mode commits it. `session-status --config KEY` prints a key's value in effect.

| Key | Values | Default |
|---|---|---|
| `tracker` | `none` \| `github` \| `jira` (keys only; ticket status needs your own adapter) | detected at setup: `jira` for Jira-style keys, `github` for a GitHub remote with `#123` refs, else `none` |
| `host` | `github` \| `bitbucket` \| `forgejo` \| `none` | from the `origin` remote |
| `key_pattern` | an extended regex matching a task key | not written by setup (your override); unset: the adapter's `key-pattern`, else `[A-Z][A-Z0-9]+-[0-9]+` |
| `approvals.delegate` | `true` \| `false` | `false` |
| `approvals.pr_create` | `true` \| `false`: a session opens its own task's PR (`gh`, `forgejo-cli` or `bitbucketdc-cli pr create`) without an ask; issues and fork PRs still ask (`../orchestrating-sessions/worker.md`, Approvals) | `true` in the plugin coordinator's project (`feedback.repo_dir`'s), else `false`; person-only; setup doesn't write it |
| `start.mode` | `read_only` \| `propose` \| `at_once`: when the coordinator starts a session for new work without the user's yes (`../orchestrating-sessions/sessions.md`, Starting a session) | `read_only`; person-only; `--write` doesn't write it: edit the file when the user names a start mode (below) |
| `start.kinds.feedback_apply` | the same values, for a plugin feedback apply session (`features/plugin-coordinator.md`) | `start.mode`'s value; person-only; `--write` doesn't write it: edit the file (below). An apply session pushes, so `read_only` proposes it like `propose` |
| `start.sidebar` | `true` \| `false`: a Claude Code Desktop coordinator may start a task as a sidebar session (`start_session`) the user watches and answers in the app; such a task gets no status row, idle notice, `--resume-ended` or `--stop` (README, Claude Code Desktop); it runs no higher than the coordinator's own model, where `claude --bg` has no cap | `false`; person-only; setup doesn't write it |
| `terminal` | a terminal module's name: `plain` (the pane copies commands), one the plugin ships (`terminals/<name>.md` beside its module), or your own (status-reference.md, Modules) | `plain`; setup proposes a shipped module when it runs in that terminal (in tmux: `plain`, with a note) |
| `messages` | `none`, `msgraph` (Teams and Outlook; its config block and routing in `messages/msgraph.md`) or your own messages module (status-reference.md, Modules) | `none`; setup doesn't write it: set it by hand per the module's doc |
| `features.accounts` | `true` \| `false`: ask every Claude account sharing this one's transcripts (`features/accounts.md`) | `false`; setup writes `true` when it finds a second account |
| `features.accounts_weekly_switch` | `true` \| `false`: with `features.accounts` on, a coordinator past 90% of its account's weekly limit hands over to a coordinator under an account below it (`features/accounts.md`, Weekly limits); off, the weekly use is information only | `false`; person-only; setup doesn't write it |
| `features.review_inbox` | `true` \| `false`: PR findings go to the review inbox page (`features/review-inbox.md`); Bitbucket or Forgejo, GitHub is a TODO | `false`; setup writes `true` when the project's docs name an inbox URL and the host is Bitbucket or Forgejo |
| `features.notify` | integer minutes, `0` = off: an ask left unseen on the pane that long shows one local macOS notification with a count only (`features/notify.md`) | `0`; person-only; setup doesn't write it |
| `features.answers` | `true` \| `false`: the coordinator writes each answer it gives you to the project's answers folder; the pane's Answers section lists the unread ones (Mark as read, Explain) (`features/answers.md`) | `false`; person-only; setup doesn't write it |
| `features.remote` | `true` \| `false`: coordinators start with Remote Control, so the person's coordinators on their other computers (same claude.ai account) reach them, and `--check` warns about a setting that keeps those out (`features/remote.md`) | `false`; person-only; setup doesn't write it |
| `features.retro` | `true` \| `false`: scheduled retro runs, and `--check` names `features/retro.md` (what to do with a report, an overdue run). `/retro` by hand works either way | `false`; person-only; setup doesn't write it |
| `features.docs_watch` | `true` \| `false`: once a day, a Notices line per watched docs page neither of a `docs_watch.files` doc's lists has (`features/docs-watch.md`) | `true` when `docs_watch.files` names a doc, else `false`; person-only; setup doesn't write it |
| `docs_watch.files` | JSON list of docs (relative to the root, or `~/…`), each with a `Last reviewed YYYY-MM-DD against:` list (and optionally a `Skipped …:` one) | the plugin's `writing-instructions.md` in the plugin repo's project, else unset; person-only; setup doesn't write it |
| `docs_watch.pattern` | an extended regex over page slugs: which docs pages are watched | `DOCS_WATCH_PATTERN` in `lib.sh` (`session-status --config docs_watch.pattern` prints it); person-only; setup doesn't write it |
| `retro.scope` | `project` \| `plugin` \| `both`: whose sessions a retro run reads, this project's or every project's (`features/retro.md`) | `project`; person-only |
| `retro.schedule` | `<day> HH:MM`, local time, day `mon`…`sun` (e.g. `mon 12:00`): when a scheduled run starts | unset: by hand only; person-only |
| `retro.account` | the Claude config dir a scheduled run starts under (absolute or `~`; must exist) | the current account; person-only |
| `retro.sections` | non-empty JSON list of section names (`units`, `context`, `waste`, `spend`, `feedback`, `coordinator`, `memory`, `protocol`, `features`, `sizing`); one the scope lacks is skipped | unset: every section of the scope; person-only |
| `retro.groups` | JSON object of each scope's section groups, `{"project": {"units": ["units", "context"], …}}` (`features/retro.md`) | unset: `retro.py`'s defaults; person-only |
| `feedback.send` | `ask` \| `auto`: `auto` lets an apply session open its plugin-feedback PR or issue on the plugin's own repo without a relay once `feedback scrub` passes its title and body (`../orchestrating-sessions/feedback.md`) | `ask`; person-only; setup doesn't write it |
| `feedback.mode` | `auto` \| `pr` \| `fork-pr` \| `issue` \| `local`: how plugin feedback cases are sent (`../orchestrating-sessions/feedback.md`) | `auto`: `pr` with `feedback.repo_dir` set, else `fork-pr` when `gh` is signed in, else `issue`; setup doesn't write it |
| `feedback.repo_dir` | a clone of the plugin repo you can push to (`~` expanded); its coordinator is the plugin coordinator, which owns every plugin feedback case (`features/plugin-coordinator.md`) | unset; person key; setup doesn't write it |
| `feedback.project_dir` | where this project's own feedback cases go (`feedback add --project`; `~` expanded, relative to the root; keep it out of git). A project key: never in the person-wide config.json | unset: `${XDG_STATE_HOME:-~/.local/state}/session-orchestration/feedback-projects/<root, encoded>`; setup doesn't write it |
| `pending.file` | the coordinator's handoff file, `*.md`: relative to the root (e.g. `docs/pending.md`), `~/…` or absolute: turns on its per-entry history hook and archive (`--pending-done`, `--pending-history`; status-reference.md). With it or a replies folder, a Stop hook keeps that folder's local git history (`--git-history`; more folders: `history.dirs`). Person only | unset; setup never writes it, and `--move` leaves the file it names where it is |
| `history.dirs` | a JSON list of folders (relative to the root, `~` or absolute) whose changes the history-git Stop hook commits when a turn ends, besides the replies folder and handoff files it always keeps. A folder that is (or whose parent is) the top of a repo with no remote is adopted with its history; else its git dir sits outside it. A folder inside another listed one (the replies folder inside `docs/notes`) is committed only to the outer repo, unless a repo of its own lies between them; its earlier history stays in its old repo, which `--git-history` and `--pending-history` no longer read. A folder holding the root is skipped (status-reference.md, `--git-history`). A folder git tracks (team files, a committed docs folder; one tracked file, a `.gitkeep`, is enough) is skipped: its history is the project's git. Person only | unset; setup writes it only on the user's yes to taking over a hand-made history hook |
| `coordinator.purpose` | one line, at most 200 characters: what this project's coordinator is for. `session-status --coordinators` lists it for every coordinator of the person, and a coordinator routes a matter outside its project by it (`../orchestrating-sessions/sessions.md`, Another project's matter). Read from the project's `.claude/coordination.local.json` only; `session-status --purpose 'LINE'` writes it there | unset: `--start` asks for it under `## Purpose`; person-only, per project; setup writes it from the Purpose question it adds after the proposal's two |
| `pane.sections` | a JSON object, a coordinator pane section's slug to `open` \| `line` \| `hidden` (e.g. `{"pending": "hidden", "idle": "line"}`; slugs and states: `../orchestrating-sessions/status-reference.md`, The pane in detail). Read from the project's `.claude/coordination.local.json` only, never the repo file or the person-wide one; a press on a section's title writes it there (`session-status --pane-section SLUG STATE`) | unset: every section open, Resolved one line; a folded Waiting on you, Decisions or Needs action still draws its new items; person-only; setup doesn't write it |
| `features.report_artifacts` | JSON list of report kinds (`research`, `retro`, `design`, `review`) a session may publish as a private claude.ai page after `session-status --report-publish` says yes (`features/report-artifacts.md`). Read from the project's `.claude/coordination.local.json` only, never the repo file or the person-wide one | unset: off; person-only, per project; setup doesn't write it |
| `report_artifacts.account` | the Claude config dir (absolute or `~`; must exist) whose sessions publish those pages; needed when `features.accounts` is on. The same file only | unset; person-only, per project; setup doesn't write it |
| `telemetry` | `full` \| `local` \| `off`: what goes to `${XDG_STATE_HOME:-~/.local/state}/session-orchestration/usage.jsonl`, read only by `retro.py`; nothing leaves the machine. Lines hold fixed names, counts, exit codes and plugin paths, never command or message text, task keys or project paths. `local`: pane presses, path counts, task starts (`--kind`), chunk ends (`--plan --done`), escalations and the watcher's own stops and worktree removals (`auto`). `full`: those, plus the faults, each with the plugin's version: `block` (a hook's deny or ask: `approved-action-deny`/`-ask`, `coordinator-guard-cd`/`-edit`/`-sidebar`, with the hook's file:line), `refuse` (a tool call Claude Code refused: the tool's name, another server's MCP tool as `mcp`), `relay` (a relayed approval the hook passed over: `used-once`, `no-key`, `not-landing`, `unverified`), `wake` (`--watch`: `wake` with the lines it reports, `poll-failed` and `gave-up` with the exit code) and `error` (a non-zero exit of session-status, with its `--flag`, or of the approval hook, with the code). `off`: nothing | `full` (the plugin is shared with a few known people, so faults are caught early); setup doesn't write it, and an explicit `local` or `off` stays as set (set it in the person-wide file) |
| `plan.enabled` | `true` \| `false`: `session-status --plan` splits a design into chunks | `true`; setup doesn't write it |
| `plan.max_parallel` | integer ≥ 1: chunks `session-status --plan` lets run at once | `3`; setup doesn't write it |
| `fable.accounts` | JSON list of Claude config dirs (`~` expanded) whose account has the `fable` model; person only. Nothing tells reliably which accounts have fable, so the person lists them. An account at its weekly Fable limit (a session got "You've hit your Fable limit") counts as unlisted until the limit resets | empty: fable nowhere |
| `plan.models.<kind>` | `model/effort` (`fable` only under an account `fable.accounts` lists, else the default), per kind `design` \| `build` \| `mechanical` \| `review` \| `release` \| `scan` \| `coordinator` \| `retro` \| `research`: what `session-status --plan` starts a chunk of that kind on, `session-status --kind` a plain task start, and (`coordinator`) a coordinator's start and a successor whose predecessor's model is unknown | `design` `opus/xhigh`, `build` `opus/medium`, `mechanical` `sonnet/medium`, `review` `opus/xhigh`, `release` `sonnet/medium`, `scan` `haiku/low`, `coordinator` `opus/medium`, `retro` `opus/xhigh`, `research` `opus/high`; under an account `fable.accounts` lists, `design`, `review` and `retro` `fable/xhigh`, `coordinator` `fable/medium`; setup doesn't write them |
| `plan.advisor.<kind>` | `fable` \| `opus` \| `sonnet`, per kind as `plan.models`: the advisor trial. `session-status --kind` (and a coordinator's start) adds `--advisor A` where it pairs with the kind's model (the `choosing-model-effort` skill) | unset: off; setup doesn't write them |
| `handoff.at.<chunk\|task\|coordinator>` | integer tokens of context, `0` = off: the context-watch hook's soft line for that kind of session, where it asks for a handoff | `chunk` 125000, `task` 145000, `coordinator` 145000; person-only |
| `handoff.hard_after` | integer tokens: the hook's hard line, this far past the soft line | `25000`; person-only |
| `handoff.stop_room` | integer tokens: room the hook keeps under the compaction ceiling (the hard line never passes it) | `15000`; person-only |
| `compact.window` | integer tokens: the auto-compact window the hook expects | `220000`; person-only |

A value outside its set falls back to the default, with one warning line. A GitLab remote gives `host=none` and a
Linear tracker `tracker=none`, each with a warning or a note in the proposal: neither is supported yet.

To change a value, edit the file (keep it one JSON object). A start mode the user names ("start apply sessions at
once, propose the rest") goes in the person's file of that project, merged into what's there:
`{"start":{"mode":"propose","kinds":{"feedback_apply":"at_once"}}}`. It is a person key, so in a shared project
each person's coordinator follows their own; the next `--start` prints it. A plain `--write` in a folder set up already adds only
the keys a file lacks, never changing one that's there. To turn delegation on in a folder set up already:
`session-status --init --write --delegate`. A plain `--write` in a folder whose `CLAUDE.md` still delegates in
words leaves the key unset (and `--check` keeps naming it), so it never revokes a delegation unasked. What stays reserved even with delegation on is the `CLAUDE.md`
section's **Reserved** list, text the project edits.

---
name: setting-up-coordination
description: Sets a project folder up for coordinated Claude Code sessions (one coordinator, task sessions in parallel) — detects the tracker, code host and task keys, asks the few questions it can't detect, and writes the adapter, the CLAUDE.md section and the config. Use when asked to "coordinate this project", set up or check coordination, when open_pane says the folder isn't set up, or to change a coordination config value (tracker, host, key_pattern, approvals.delegate, terminal, features.accounts, features.review_inbox).
---

# Setting up coordination

A folder not set up for coordination has no adapter and no `CLAUDE.md` section naming a replies folder, so the
coordinator has nothing to read. `open_pane` checks (`session-status --init --check`) and says so in its result.
`session-status` is in the `orchestrating-sessions` skill's folder; `--init` runs `session-init`, next to this file.

## Check

`session-status --init --check`, from the folder: one line, exit 0 configured, 1 unconfigured or partial, 3 covered
by a parent. Configured adds:
- `active: tracker=… host=… delegate=on|off terminal=… messages=… features=…|none → read <doc>, …`: the config in
  effect, and the doc to read for the terminal, the messages module and each feature that's on (the coordinator reads them at start);
- `detected <terminal>: run setup to record it (…)` when it runs in a terminal it has a module for and `terminal` is
  unset;
- `second account found, accounts off: run setup (session-status --init --write)` when another Claude account shares
  this one's transcripts and `features.accounts` is off;
- `committed code new or changed upstream: REL…: run setup to review it` (shared mode, below);
- a warning per config value that isn't valid (the default is used), per terminal or feature module that doesn't
  load (see status-reference.md, Modules), and, when `CLAUDE.md` still delegates approvals
  in words with no `approvals.delegate` key, `delegation found in CLAUDE.md: run setup to move it`.

## Propose, then write

- **Unconfigured** (or partial): run `session-status --init`. It reads only the folder, its repos and their remotes
  (no tracker call) and prints a numbered proposal: task keys, code host, the files it would write and the config,
  approvals, worktrees. Show it to the user as one plain-text round, unchanged, and wait. Never write before a
  "yes". The round always holds two questions, each with the detected answer as the default:
  1. **Tracker**: `none` (a task is a short name), `github` (issues and PRs through `gh`), `jira`.
  2. **Approvals**: may a coordinator's message stand in for the user's in task sessions? Default **no**.
- **On "yes"**: `session-status --init --write`, plus `--delegate` only if the user said so (delegation is theirs to
  give: it makes the coordinator's messages count as theirs), and each correction as `KEY=VALUE` (the names on the
  proposal's `Facts:` line; `tracker=` and `host=` among them). It writes only missing files, appends the section to
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
- **Optional briefs**, on the user's request (`--init` lists the missing ones, also once set up): `--write
  --review-brief` writes `<orch>/review-brief.md`; name it in each PR reviewer's first prompt (`Review
  <repo>#<id> (<KEY>). Brief: <path>`). `--write --rnd-brief` writes `.claude/rnd-brief.md`, which the `rnd` skill
  reads.

## Shared mode

Off by default: setup writes nothing a collaborator sees (everything goes to `.git/info/exclude`d files and
`CLAUDE.local.md` when `CLAUDE.md` is tracked; it never edits a tracked `CLAUDE.md` or `AGENTS.md`). Only when the
repo's owner wants it, on the user's request: `session-status --init --write --shared` keeps
`.claude/coordination/coordination.json` (repo keys only) out of the exclude and, when an ignore rule still hides it
(an exclude with `.claude/*`), adds `!/.claude/coordination/` and says so. The user commits it, with their usual PR.
What may be committed there: `coordination.json`; `memory.md` and `memory/` (team memory, reached through the
coordinator's prune PR); a shared adapter (`session-status-adapter`) and modules (`<kind>/<name>.sh`), each run by a
person only once trusted. Never committed: anything in `coordination.local.json` (delegation, terminal, accounts,
`trusted`, `team`), your adapter, your memory and replies.

A folder that isn't a repo itself (a workspace of repos) uses the `team` person key: the path, relative to the
folder, of the repo holding `.claude/coordination/`. Setup finds it one level down and proposes it; with several,
say `team=<folder>`. The team's `coordination.json` then supplies the repo keys, and its committed code is offered
for trust.

## Config

Two JSON files, each the nearest one up from the cwd within the project (a folder with its own adapter ends the
walk, so a subproject never reads its parent's), merged key by key (the person's file wins); a session in a worktree
below reads the project's:
- `.claude/coordination/coordination.json`, the repo's: `tracker`, `host`, `key_pattern`, `features.review_inbox`;
- `.claude/coordination.local.json`, the person's: `approvals.delegate`, `terminal`, `messages` and its module's block
  (e.g. `msgraph`), `features.accounts`, `trusted`, `team`, `feedback` (ignored in the repo file: a committed file never
  delegates or trusts for anyone, and the terminal, messages, accounts and feedback are the person's own);
- below both, `${XDG_CONFIG_HOME:-~/.config}/session-orchestration/config.json`, the person's for every project:
  any key but `team` (the project's file only), meant for the person-wide ones (`feedback`, `telemetry`). Setup
  doesn't write it.

Both are excluded from git, the repo file until shared mode commits it. `session-status --config KEY` prints a key's value in effect.

| Key | Values | Default |
|---|---|---|
| `tracker` | `none` \| `github` \| `jira` | detected at setup: `jira` for Jira-style keys, `github` for a GitHub remote with `#123` refs, else `none` |
| `host` | `github` \| `bitbucket` \| `none` | from the `origin` remote |
| `key_pattern` | an extended regex matching a task key | not written by setup (your override); unset: the adapter's `key-pattern`, else `[A-Z][A-Z0-9]+-[0-9]+` |
| `approvals.delegate` | `true` \| `false` | `false` |
| `terminal` | a terminal module's name: `plain` (the pane copies commands), one the plugin ships (`terminals/<name>.md` beside its module), or your own (status-reference.md, Modules) | `plain`; setup proposes a shipped module when it runs in that terminal (in tmux: `plain`, with a note) |
| `messages` | `none`, `msgraph` (Teams and Outlook; its config block and routing in `messages/msgraph.md`) or your own messages module (status-reference.md, Modules) | `none`; setup doesn't write it: set it by hand per the module's doc |
| `features.accounts` | `true` \| `false`: ask every Claude account sharing this one's transcripts (`features/accounts.md`) | `false`; setup writes `true` when it finds a second account |
| `features.review_inbox` | `true` \| `false`: PR findings go to the review inbox page (`features/review-inbox.md`); Bitbucket only, GitHub is a TODO | `false`; setup writes `true` when the project's docs name an inbox URL and the host is Bitbucket |
| `feedback.mode` | `auto` \| `pr` \| `fork-pr` \| `issue` \| `local`: how plugin feedback cases are sent (`../orchestrating-sessions/feedback.md`) | `auto`: `pr` with `feedback.repo_dir` set, else `fork-pr` when `gh` is signed in, else `issue`; setup doesn't write it |
| `feedback.repo_dir` | a clone of the plugin repo you can push to (`~` expanded) | unset; setup doesn't write it |
| `telemetry` | `local` \| `off`: with `local`, each pane press appends a fixed name to `${XDG_STATE_HOME:-~/.local/state}/session-orchestration/usage.jsonl`, read only by `rnd.py usage`; nothing leaves the machine | `off`; setup doesn't write it (set it in the person-wide file to measure your own use) |

A value outside its set falls back to the default, with one warning line. A GitLab remote gives `host=none` and a
Linear tracker `tracker=none`, each with a warning or a note in the proposal: neither is supported yet.

To change a value, edit the file (keep it one JSON object). A plain `--write` in a folder set up already adds only
the keys a file lacks, never changing one that's there. To turn delegation on in a folder set up already:
`session-status --init --write --delegate`. A plain `--write` in a folder whose `CLAUDE.md` still delegates in
words leaves the key unset (and `--check` keeps naming it), so it never revokes a delegation unasked. What stays reserved even with delegation on is the `CLAUDE.md`
section's **Reserved** list, text the project edits.

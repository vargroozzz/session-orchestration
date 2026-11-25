# session-orchestration

Run several Claude Code sessions in parallel, one per task, with one **coordinator** session that keeps track of
them: it starts task sessions, passes on your answers, and shows what each one is doing and waiting on. Task
sessions reply to it in short, structured status reports, so its context stays small.

What you get:
- a reply protocol for sessions that receive cross-session messages, put in their context by a hook as a short card
  and enforced by hooks, with a `reply` tool that finds the project's live coordinator;
- a playbook for the coordinator, with a status command (`session-status`) and a pane beside the chat: tasks,
  their sessions, PRs and pending decisions, and approvals as buttons;
- a hook that lets a PR merge or a comment post through only with your approval (see [Hooks](#hooks));
- through [project-memory](../project-memory/README.md), installed with it: project memory read by every session,
  a `/graduate` pass into the docs, project friction cases, deferred tasks, and guards that keep background
  sessions from stalling on a prompt nobody can answer;
- optional: a review inbox for proposed PR comments, a `retro` skill that measures how efficiently the sessions work, and a `research` skill that answers a question from outside sources and scans similar tools for ideas (`/research other-tools`; web searches with no personal details).

**GitHub works out of the box** (tracker `github`, `gh`). Jira, Bitbucket and Forgejo need your own adapter and CLI
(`skills/orchestrating-sessions/status-reference.md`, the adapter contract): with tracker `jira`, the adapter setup
writes knows task keys but not ticket status (the GitHub adapter when the code is on GitHub: PRs and CI; else a stub). CLI names in the docs, such as `jiradc-cli`,
`bitbucketdc-cli` and `forgejo-cli`, are examples of what such a CLI is called, not packages this plugin ships or
installs; the review inbox posts only through the command you set in `BITBUCKETDC` or `FORGEJO`.

## Requirements

- bash, `jq`, `git`; macOS or Linux (Windows through WSL);
- `gh`, signed in, if your tasks are GitHub issues and PRs;
- for the coordinator pane and the `reply`, `ask_approval` and `hand_command` tools: a Claude Code that loads a
  plugin's hooks module (`hooks/register.tsx`; an early-access feature, so check after install: run
  `/reload-plugins`, then ask for the coordinator pane, or look for the `session-orchestration` tools in `/mcp`).
  Without it you lose the pane (the board, approvals as buttons, the Run box for handed commands) and those tools;
  the status command, the skills and the shell hooks still work: the coordinator asks in plain text, workers reply
  with `SendMessage`.

### Claude Code Desktop

The coordinator can be a session in Claude Code Desktop's Code tab. Install the CLI too: the plugin's commands run
`claude` in the session's shell (task sessions start with `claude --bg`, the status lists them with `claude agents`),
and Desktop's own binary usually isn't on its PATH (`curl -fsSL https://claude.ai/install.sh | bash`; setup and
`session-status --init --check` say when it's missing). Install the plugin with the CLI commands below; Desktop reads
the same settings. Then:

- The pane opens beside the chat as in a terminal (Desktop 2.1.286 or later, not over WSL). Where it doesn't, the
  coordinator asks in plain text, as for a terminal without the hooks module.
- Task sessions are background sessions, so they show in the pane and in `claude agents`, not in Desktop's sidebar.
  To watch one, run the `claude attach <id>` the pane's Attach copies in the session's Terminal (Ctrl+`). Start tasks
  that way, not as sidebar sessions: a sidebar session gets no status row, idle notice or resume after a restart,
  and the watcher doesn't stop it when its task is done. `session-status --peek`, `--dir` and `--diff` take a sidebar session's
  `local_…` id too.
- The coordinator hands over to a successor at 145K tokens of context (config `handoff.at.coordinator`), on a 1M
  window too. Ask it to raise that to hand over less often; each wake then re-reads a larger context.
  `/retro project` shows what the coordinator costs, by what woke it.
- Messages, `reply`, the hooks and the approval gate work as in a terminal; a Desktop coordinator shows in
  `claude agents` as an interactive session.
- Desktop opens no tabs: with the terminal setting `plain` (the default; it's per person, so a terminal recorded by an
  earlier setup still opens its tabs) Attach and Logs copy their command.
- A coordinator handover starts the successor as a Desktop session (`start_session`), so it shows in the sidebar and
  takes the old one's pin; a handover the coordinator starts on its own shows a New task card for you to start. Each
  coordinator's sidebar title follows its name (`NAME-prev-K` for the old one), and once the successor holds the name
  it archives the old one (the app asks you first, except in auto and bypass permissions modes) or says why it can't. The old one first
  detaches the sessions it started, since the app archives a session's idle side sessions with it; one it still holds
  keeps it unarchived, for you to archive.
  The successor is the only sidebar session the coordinator starts: a hook refuses `start_session` for a task, which
  then starts with `claude --bg` like every task. To watch and answer tasks in the app instead, set
  `"start": {"sidebar": true}` in `.claude/coordination.local.json`: the hook
  lets the coordinator start tasks as sidebar sessions, which then get no status row, idle notice, resume after a
  restart or stop, and you answer their questions in the app rather than through the coordinator.
  A sidebar session also cannot run above the coordinator's own model: `start_session` takes the same family or a
  cheaper one, and a higher `plan.models` kind (opus under a sonnet coordinator) silently starts at the coordinator's
  model. `claude --bg` (`session-status --launch`) has no such cap, so a task that needs the bigger model starts that way.

## Install

From the public marketplace:

```
claude plugin marketplace add vargroozzz/session-orchestration
claude plugin install session-orchestration@session-orchestration
```

That installs [project-memory](../project-memory/README.md) too (a dependency). For memory, `/graduate` and the
background guards without a coordinator, install only `project-memory@session-orchestration`.

Updating an install from before project-memory split off: `claude plugin install project-memory@session-orchestration`
too if `session-status --init --check` says it isn't installed (until then, background sessions have no guards).

## Update

```
claude plugin marketplace update session-orchestration
claude plugin update session-orchestration@session-orchestration
claude plugin update project-memory@session-orchestration
```

The first refreshes the marketplace from its source, the others install the newest version it lists;
`claude plugin list` shows the installed one. Releases carry no tags: each change lands on `main` as a commit titled
`session-orchestration <version>: <what changed>`, so the commit list is the changelog and `version` in
`plugins/session-orchestration/.claude-plugin/plugin.json` on `main` is the newest.

A running session keeps the hooks and tools it started with until its plugins reload: ask the coordinator to reload
(it calls `reload_plugins`, which runs `/reload-plugins` when its turn ends, and messages a worker to do the same).
Where the reload fails (the turn ends with `Reloading plugins failed`) or `/reload-plugins` can't run in that
session, only a new session has the new version: ask the coordinator to hand over to a successor.

## Start

In a project folder, start Claude Code and say *coordinate this project*. Setup reads the folder, its repos and
remotes (no tracker call) and asks, in one round, with what it detected preselected:

1. **Tracker**: `none` (a task is a short name), `github` (issues and PRs through `gh`) or `jira` (keys only, see
   above).
2. **Approvals**: may a coordinator's message stand in for yours in task sessions? Default no.
3. **Terminal**: asked only when it detected one the plugin can open tabs in; otherwise commands are
   printed for you to copy.

On your yes it writes a small adapter for your tracker, a section in `CLAUDE.local.md` (or `CLAUDE.md` when that
isn't tracked) and `.claude/coordination.local.json`, all kept out of git. The replies, project memory, handoff file
and briefs go in the project's state folder, `~/.local/state/session-orchestration/projects/<project path, encoded>/`,
outside the checkout; a project set up before that moves them there with `session-status --init --write --move`.
Then the session is your coordinator:
ask it to start a task (`work on #12: …`), what's going on, or to pass on an answer.

## Solo or shared

**Solo** (the default): nothing setup writes is visible to anyone else. Each person who uses the plugin on a
project runs their own coordinator.

**Shared**: a repo's owner can commit `.claude/coordination/` (`session-status --init --write --shared` commits the
repo's tracker settings and a `merge=union` line for team memory in a worktree of its own, for one team PR the user
approves; personal files stay out of git): the repo's tracker settings, team memory (lines a session tags `[team]`,
carried by the coordinator's prune in one team PR per prune), and optionally a shared adapter or terminal modules. Each collaborator's setup reads
it; committed code runs on a person's machine only after they've reviewed it and recorded its hash, and again after
every change. Delegation, accounts, terminal and personal memory always stay per person.

## Hooks

Installing the plugin adds these to every Claude Code session, in every project:

- **Approval gate** (`hooks/approved-action.sh`, its header lists each command): a PR merge, review or comment post,
  a PR or issue opened (unless `approvals.pr_create` lets a PR through) and an issue or Jira comment (gh and the
  Bitbucket, Forgejo and Jira CLIs named above), a Teams or mail send, and a
  `--link send` to another person's coordinator need your approval, relayed by the coordinator (a link send: your Yes
  on the pane); without it an interactive session asks you and a background one is denied. So is a call it can't
  name as one action (a writing `gh api` call; msgraph calendar, mail rule and file grant writes), and a read-only gh call
  that could run code: `--web` or `gh browse`, `gh config set`, a variable set in its command (`PATH=…`, `export`),
  or its output piped into anything but a plain filter (`jq`, `grep`, `head`, …). It acts only on
  coordinated work: a project setup has written files for (an adapter, `.claude/coordination.local.json` or
  `.claude/coordination/`, in the folder or one above), or a session a coordinator started or messaged. Elsewhere,
  `claude -p` and `--bg` runs included, those commands run as without the plugin.
- **Context watch** (`hooks/context-watch.sh`): asks a task or coordinator session to hand off before it compacts;
  a session that isn't coordinated gets nothing.
- **Coordinator guard** (`hooks/coordinator-guard.sh`): in a coordinator session only, refuses a Bash command that
  starts with `cd`, and an edit of a project file outside `.claude/`, the replies folder, the handoff file and the
  project memory: those belong to a task session. It also refuses Claude Code Desktop's `start_session` (a sidebar
  session), from the coordinator or any of its subagents, for anything but the coordinator's successor: tasks start
  with `claude --bg`, unless config `start.sidebar` is `true`. In a task session it refuses every `start_session` that
  would start one (a card you start yourself goes through) and every `hand_off_to_session`: a task that needs another
  session says so in its report. In every session it guards the person config files (`.claude/coordination.local.json`,
  `~/.config/session-orchestration/config.json`), which hold your approvals: an edit of either, or a Bash command that
  writes one, asks you in a session you attend and is refused in a background one, so no session grants itself an
  approval.
- **Local history** (`skills/orchestrating-sessions/history-git`, Stop): when a turn ends, commits what changed in the
  project's state folder, replies folder, handoff files and the folders in config `history.dirs`, one commit per repo named after
  the session. A folder's git dir sits outside it, unless the folder (or its parent) is the top of a repo with no
  remote, which is adopted with its history (so it replaces a hand-made auto-commit hook); a folder inside another
  is committed only to the outer repo, unless a repo of its own lies between them; a folder git tracks (the team
  folder; one tracked file is enough) is skipped. Never pushed, files over 1 MB left out. `session-status --git-history replies|handoff` reads it.
  A project with none of them configured gets nothing.

The background-session guards (no question box, plan mode or stray `EnterWorktree` in a `--bg` session; a compound
Bash command split instead of raising a prompt) come with [project-memory](../project-memory/README.md), which this
plugin depends on.

## More

- `skills/setting-up-coordination/SKILL.md`: setup, the config keys, shared mode.
- `skills/orchestrating-sessions/SKILL.md`: the coordinator's playbook, with `approvals.md`, `resuming.md`,
  `sessions.md`, `handover.md`, `plans.md`, `pane.md`, `memory-rules.md`, `feedback.md`, `subcoordinator.md` and `review-inbox.md` beside it, each read when its event comes up; `worker.md`: the rules
  for a session that receives messages (`hooks/reply-card.txt` is its short form); `status-reference.md`: the status
  command, the adapter contract, writing your own terminal module.
- `features/`, `terminals/` and `messages/`: one doc per optional feature, terminal module and messages module, each
  named by `session-status --start` when it's on.
- `skills/retro/SKILL.md` and `skills/research/SKILL.md`: the retro run and the research run.
- `skills/choosing-model-effort/SKILL.md`: sizing work into a `plan.models` kind, for a session start, a subagent or
  a retro.
- Tests: every `*.test.sh` prints `ok`.

# session-orchestration

Run several Claude Code sessions in parallel, one per task, with one **coordinator** session that keeps track of
them: it starts task sessions, passes on your answers, and shows what each one is doing and waiting on. Task
sessions reply to it in short, structured status reports, so its context stays small.

What you get:
- a reply protocol for sessions that receive cross-session messages, enforced by hooks;
- a playbook for the coordinator, with a status command (`session-status`) and a pane beside the chat: tasks,
  their sessions, PRs and pending decisions, and approvals as buttons;
- hooks that keep background sessions from stalling on a prompt nobody can answer, and that let a PR merge or a
  comment post through only with your approval (`gh`, plus Jira/Bitbucket Data Center CLIs);
- optional: a review inbox for proposed PR comments, an `rnd` skill that measures how efficiently the sessions work.

## Requirements

- bash, `jq`, `git`; macOS or Linux (Windows through WSL);
- `gh`, signed in, if your tasks are GitHub issues and PRs;
- Claude Code with mods enabled, for the coordinator pane (everything else works without it).

## Install

From the public marketplace:

```
claude plugin marketplace add vargroozzz/session-orchestration
claude plugin install session-orchestration@session-orchestration
```

## Start

In a project folder, start Claude Code and say *coordinate this project*. Setup reads the folder, its repos and
remotes (no tracker call) and asks, in one round, with what it detected preselected:

1. **Tracker**: `none` (a task is a short name), `github` (issues and PRs through `gh`) or `jira`.
2. **Approvals**: may a coordinator's message stand in for yours in task sessions? Default no.
3. **Terminal**: asked only when it detected one the plugin can open tabs in; otherwise commands are
   printed for you to copy.

On your yes it writes a small adapter for your tracker, a section in `CLAUDE.local.md` (or `CLAUDE.md` when that
isn't tracked) and `.claude/coordination.local.json`, all kept out of git. Then the session is your coordinator:
ask it to start a task (`work on #12: …`), what's going on, or to pass on an answer.

## Solo or shared

**Solo** (the default): nothing setup writes is visible to anyone else. Each person who uses the plugin on a
project runs their own coordinator.

**Shared**: a repo's owner can commit `.claude/coordination/` (`session-status --init --write --shared`): the repo's
tracker settings, team memory, and optionally a shared adapter or terminal modules. Each collaborator's setup reads
it; committed code runs on a person's machine only after they've reviewed it and recorded its hash, and again after
every change. Delegation, accounts, terminal and personal memory always stay per person.

## More

- `skills/setting-up-coordination/SKILL.md`: setup, the config keys, shared mode.
- `skills/orchestrating-sessions/SKILL.md`: the reply protocol; `coordinator.md`: the coordinator's playbook;
  `status-reference.md`: the status command, the adapter contract, writing your own terminal module.
- Tests: every `*.test.sh` prints `ok`.

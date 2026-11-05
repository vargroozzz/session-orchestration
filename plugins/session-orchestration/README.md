# session-orchestration

Run several Claude Code sessions in parallel, one per task, with one **coordinator** session that keeps track of
them: it starts task sessions, passes on your answers, and shows what each one is doing and waiting on. Task
sessions reply to it in short, structured status reports, so its context stays small.

What you get:
- a reply protocol for sessions that receive cross-session messages, put in their context by a hook as a short card
  and enforced by hooks, with a `reply` tool that finds the project's live coordinator;
- a playbook for the coordinator, with a status command (`session-status`) and a pane beside the chat: tasks,
  their sessions, PRs and pending decisions, and approvals as buttons;
- hooks that keep background sessions from stalling on a prompt nobody can answer, and that let a PR merge or a
  comment post through only with your approval (see [Hooks](#hooks));
- optional: a review inbox for proposed PR comments, an `rnd` skill that measures how efficiently the sessions work and scans similar tools for ideas (web searches with no personal details).

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

## Install

From the public marketplace:

```
claude plugin marketplace add vargroozzz/session-orchestration
claude plugin install session-orchestration@session-orchestration
```

## Start

In a project folder, start Claude Code and say *coordinate this project*. Setup reads the folder, its repos and
remotes (no tracker call) and asks, in one round, with what it detected preselected:

1. **Tracker**: `none` (a task is a short name), `github` (issues and PRs through `gh`) or `jira` (keys only, see
   above).
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

## Hooks

Installing the plugin adds these to every Claude Code session, in every project:

- **Approval gate** (`hooks/approved-action.sh`): a PR merge, review or comment post (`gh pr merge|comment|review`,
  `gh issue comment`, and the Bitbucket, Forgejo and Jira CLIs named above) needs your approval, relayed by the
  coordinator; without it an interactive session asks you and a background one is denied. It acts only on
  coordinated work: a project setup has written files for (an adapter, `.claude/coordination.local.json` or
  `.claude/coordination/`, in the folder or one above), or a session a coordinator started or messaged. Elsewhere,
  `claude -p` and `--bg` runs included, those commands run as without the plugin.
- **Background-session guards** (`hooks/no-question-box.sh`, `hooks/bg-compound.sh`): in a `--bg` session, in any
  project, the question box, plan mode, an `EnterWorktree` outside the session's own worktrees, and a compound Bash
  command that would raise a permission dialog are denied with a hint (ask in plain text; split the command). A
  prompt nobody sees would stall the session. Interactive sessions are left alone.
- **Context watch** (`hooks/context-watch.sh`): asks a task or coordinator session to hand off before it compacts;
  a session that isn't coordinated gets nothing.

## More

- `skills/setting-up-coordination/SKILL.md`: setup, the config keys, shared mode.
- `skills/orchestrating-sessions/SKILL.md`: the coordinator's playbook, with `approvals.md`, `resuming.md`,
  `plans.md`, `pane.md` and `memory-rules.md` beside it, each read when its event comes up; `worker.md`: the rules
  for a session that receives messages (`hooks/reply-card.txt` is its short form); `status-reference.md`: the status
  command, the adapter contract, writing your own terminal module.
- Tests: every `*.test.sh` prints `ok`.

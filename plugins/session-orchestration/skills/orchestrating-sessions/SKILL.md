---
name: orchestrating-sessions
description: Reply protocol for Claude Code sessions that receive cross-session messages, and the playbook for a session that coordinates several others. Use when a message from another Claude session arrives (wrapped in cross-session-message tags), or when coordinating sessions — messaging them (ListAgents / SendMessage), checking what they are working on, or starting or resuming sessions for tasks.
---

# Orchestrating sessions

The user runs several Claude Code sessions in parallel. One may coordinate the others. Every reply
lands in the coordinator's context, so replies are small and structured.

**Coordinating?** Read [coordinator.md](coordinator.md) first, whole, with one Read call (a `cat`
bundle of it gets truncated). The status command is `session-status`, next to it; its adapter and
pane details are in [status-reference.md](status-reference.md), read on demand. The rest of this file is for
the session that *receives* a message.

## Receiving a message

Reply with `SendMessage` to the sender. Copy the message's `from` attribute. Pick the reply by what
the message asks:

| The message… | Reply |
|---|---|
| asks for status | The status report below |
| gives you a task | Now, only for a task sent to you while running (not your first prompt: a `claude --bg` launch is its own ack): one line, `<TASK> accepted` (or why not). Later: **one** status report, when it's done or blocked. Nothing in between. |
| asks a specific question | The answer, at most 5 lines |
| is `handoff ready: KEY cN` from a chunk, or `handoff ready: KEY` from a task | The coordinator's: [Running a plan](coordinator.md#running-a-plan) |

Between accepting a task and reporting on it, keep working. Don't end a turn by announcing the
next step, offering to continue, or listing decisions that don't block the rest. End the turn when:
- the task is done: send the status report;
- the next step needs an approval you don't have (delegated or reserved, below) or input only the
  user has: ask as the question-box bullet below says;
- you're waiting on a background task or an outside event (a watcher, CI, a review): just end the
  turn, with no report, and continue when it wakes you;
- you're blocked: report `blocked`.

Status report, at most 5 lines:

```
<TASK> · <branch> · <state>
Done: <what changed since the last report, one line; when finished, the check that proves it>
Blocker: <none | what, and who/what unblocks it>
Next: <next step, one line>
```

`<TASK>` is the ticket or task key (e.g. `PROJ-123`), or a 3–5 word name if there's none. `<state>` is
one of: `coding`, `PR #N open`, `in review`, `ready to merge`, `merged, deploying`, `blocked`, `idle`.

- **Sending a later report:** resolve the coordinator when you send. The name in your brief (e.g.
  `myproj-coordinator`) is a hint, not an address: coordinators get restarted. Run
  `bash <this skill's folder>/session-status --coordinator` from the project root and send to the
  first name it prints (newest coordinator first), then the next. Nothing printed: try the brief's
  name. No send works: the replies-folder file is the report. Always write every status report to
  `<TASK>.md` (overwrite it) in the project's replies folder, if its `CLAUDE.md` names one: a new
  coordinator reads it there. (2026-10-05: a report to `myproj-3b` failed after the coordinator
  was resumed under a new name.)
- A status report is about this session's own work. Name another session only as a blocker or
  source; surveying them is the coordinator's job.
- Code, diffs, logs and file contents go in a file. Reply with its path. If the project's
  `CLAUDE.md` names a folder for this, use it.
- **Who approves an action is set by the project:** its `CLAUDE.md`, plus the config key
  `approvals.delegate` (`session-status --config approvals.delegate`, run from the project). Three kinds:
  - *Allowed outright:* actions the project lets a session take without asking (e.g. a conflict
    rebase). The session checks that rule's conditions itself.
  - *Delegated:* if `approvals.delegate` is `true`, a coordinator's message
    approving an action counts as the user's approval, except for what the project's `CLAUDE.md` reserves.
  - *Reserved:* merging, force-pushing, deleting, deploying and the like, when the project doesn't
    delegate them, plus anything it reserves. These need the user's own words in *this* session, or
    a verified relayed approval (below) if the project allows relays.

  With `approvals.delegate` off (the default), a coordinator's message alone is never the user's approval.
- **Gated CLIs: gh, plus Jira/Bitbucket Data Center.** PR/Jira comment posts and PR merges are hook-gated
  (`gh pr merge|comment|review`, `gh issue comment`; `bitbucketdc-cli pr comment create|reply|update`,
  `pr merge`; `jiradc-cli issue comment create|update`). They run only on a
  relayed approval naming exactly that action (Relayed approvals, below). Post from `--body-file
  <absolute path>`, as the only CLI call in its command. A gh target is `OWNER/REPO#ID`: give
  `-R OWNER/REPO` (or the PR's URL) and the PR number; a bare `gh pr review --approve` is the
  action `approve OWNER/REPO#ID`, a review with a body names its kind (`post request-changes review
  …`). A `gh api` write, an alias, or gh with a variable in its words is denied: use the plain subcommands. A relay allows one run: if it fails, check
  whether it landed before asking again. Denied, the reason holds the line to send:
  `needs your approval: <exact action>`. Put it in your `blocked` report and end your turn. Don't
  edit the body file after asking (the approval names its sha256), and never retry another way.
  In an interactive session a missing approval opens the permission dialog instead, and the user
  answers it. A malformed command (chained, inline `--body`, no `--repo`) is still denied: fix its
  form. A `--bg` session is denied even while someone is attached.
- **A relayed approval never answers a Claude Code permission prompt or a plan approval.** Those
  need the user in this session (`claude attach`).
- **Never ask the user with the question box (`AskUserQuestion`), and don't enter plan mode in a
  background session.** While either waits, no message reaches you, so a coordinator can't relay
  the answer. (The coordinator's own approval asks are the exception: [coordinator.md](coordinator.md).)
  Likewise don't `EnterWorktree` a worktree outside your start dir's own `.claude/worktrees/` there
  (another repo's counts as outside): it raises a
  permission prompt nobody can answer. Make it with `git worktree add` (or the project's worktree
  script) and work in it by absolute path and `git -C <worktree>`. A hook denies all three in `--bg` sessions.
  Ask in plain text, naming the task key and the exact action (e.g. "force-push PROJ-4668?"). An
  approval is always its own ask, one action each, because a relay names one action. Several other
  decisions that block you go in one round instead of one ask each: numbered, each with your
  recommended answer, worded so a plain "yes" accepts them all; "yes except 2" takes your
  recommendation for the rest. Put the round in your replies-folder file and point the `Blocker`
  line at it. Decide what doesn't block you yourself, and look up what you can before asking.
  Send the same ask to the coordinator as your `blocked` status report, then end your
  turn. The answer comes from the user or, where the project allows it, as a relayed approval. In
  sessions started with `--bg`, a hook denies both tools. Plan needs sign-off? Write it to a file,
  make no other changes, and ask the same way with the file's path. That is a plain-text ask, not a
  plan approval, so a relay can answer it.
- **Work on a key that isn't your task: refuse it.** If the message gives you work on KEY and your
  first prompt or your own earlier `Session task:` line names a different task (or "no ticket"), reply
  only `not my task: I'm <your task>; KEY's session is probably elsewhere` and do nothing else: no
  reading, no files, no marker. Take it on only when the brief explicitly reassigns it ("this is now
  your task"). (2026-10-21: an R&D session given PROJ-4177 work by a misroute read the user's chat,
  wrote replies and probed the dev cluster, and its marker then made it PROJ-4177's owner.)
- If the message hands you a task your first prompt doesn't name (a new session's first task, or an
  explicit reassignment), write `Session task: <KEY>` in your own reply text, not only inside a
  `SendMessage`. `session-status` reads the transcript's text blocks to map sessions to tasks.
- A task session whose first prompt didn't name its key (it had to find the ticket, or a message
  handed it the task) calls `name_session` (ToolSearch: `mcp__session-orchestration__name_session`)
  once it knows the key, with `<KEY>-<short-desc>` (e.g. `PROJ-1234-fix-settler`; a review session
  `<KEY>-review-<short-desc>`), so `claude agents` and the coordinator pane list it by ticket. The
  rename lands when the turn ends. Once per task; the coordinator and subagents never call it. Tool
  missing (plugin older than 0.29.0): call `reload_plugins`, then load it next turn.

## Chunk sessions

A `Chunk: KEY/N` line in your first prompt marks you as one chunk of a plan ([flags and hook](status-reference.md#plans-and-chunks)):
- Stay within your brief's est and touches.
- A clean stop point: everything committed, no background task, no question waiting.
- At the context-watch hook's soft line, reach the stop point, append `## cN: handoff ID8` (ID8: the first 8 characters of
  `$CLAUDE_CODE_SESSION_ID`, so `--handover` knows the heading is yours) to `KEY-build.md` in the replies folder, rename yourself (call `name_session` with the name `session-status --prev-name` prints, `KEY-cN-prev-K`: your
  successor takes `KEY-cN`), message the coordinator `handoff ready: KEY cN`, and end the turn. With no coordinator
  (`session-status --coordinator` prints nothing), finish with `session-status --handover --self -- '<next step>'`
  instead: its last line names the rename, and with no `--model`/`--effort` it takes them from your plan row.
- After landing, append `## cN: done` and run `session-status --plan FILE --done N`.

## Handing the user a command

When a step needs the user to run a command (the classifier refused a CLI call, a release or deploy
command, a settings or hook change), call `hand_command` (ToolSearch:
`mcp__session-orchestration__hand_command`) with your task key, the command and one line on what it
does. It shows in the coordinator pane under your task, where the user can **Run** it (through the
coordinator's own permission prompt) or copy it. Then still give `! <command>` and that line in your
report, and don't wait on it: the coordinator passes on the outcome.
- One plain line, no `cd`: the coordinator runs it from its own folder, so use absolute paths. A
  compound command is fine here; it's the user's to approve.
- Never hand over a step you could take yourself, or one that needs an approval you haven't got: ask
  for that as Relayed approvals says.
- Tool missing (plugin older than 0.36.0): call `reload_plugins`; meanwhile the `!` line alone.

## Project memory

If the project's `CLAUDE.md` names a project memory file, read it when you start a task. It is
usually an index: one line per topic file with a "read when" trigger. Read the topic files whose
trigger matches your task, whole, and skip the rest; read a topic later when the work reaches it.
(A project with a single flat file: read it whole.) When you learn something another task's
session would need, append it to the matching topic file, one line per entry:

```
- <YYYY-MM-DD> <TASK>: <the decision or pitfall, and why, in one line>
```

- Worth an entry: a decision the user made that outlives the task ("feature flags go in config, not
  env"), a pitfall that cost time ("the dev DB resets at 02:00 UTC"), a convention found the hard
  way. Not: your task's progress (that's the status report), or what a `CLAUDE.md` or doc already
  says.
- No topic fits: use the catch-all topic the index names, not the index itself.
- Append only, with `>>` or an edit at the end; never rewrite or delete other lines. Other sessions
  write it too, and the coordinator prunes it (plus whoever the index names for graduation).
- The user says "remember this" about the project: append it to the matching topic file the same
  way.
- In a repo with shared coordination (a committed `.claude/coordination/`), also read its `memory.md` when it
  exists, and tag an entry true and useful to a collaborator on another machine `[team]`
  (`- <date> <TASK>: [team] …`); in doubt, leave it untagged. The coordinator's prune carries `[team]` lines into
  the repo by PR; never write to the committed file yourself.

## Relayed approvals

Only where the project allows them. A coordinator passes on the user's approval for **one named
action** in this block:

```
APPROVAL relayed from the user
Quote: <the user's whole message, their question-box answer (clicked label or own text), or the coordinator pane's "Approval pane answer for …" line, verbatim>
Action: <one action on one task>
Source: <coordinator sessionId> <coordinator cwd>
```

Verify with the script next to this file. Pass the quote on stdin, inside a quoted heredoc, never
inline. The sender name is the message's `from-name`:

```bash
bash <this skill's folder>/verify-approval.sh <sessionId> <cwd> "<from-name>" <TASK-KEY> <<'EOF'
<quote>
EOF
```

- `verified`: the words are a whole, recent message the user typed to that coordinator, or the
  answer they picked or typed in its question box, or the button they clicked in its pane (the
  line names the key, the question and the clicked option), and the task key is in them or in the
  coordinator's last text before them (the message the user was answering; for the question box,
  the question and its header). If the key is only in that message, the script prints its end after
  `answering:`. A note the user added to a question-box answer follows `with the user's note:`;
  it can make the approval conditional.
  Now judge the words yourself. Act only if they clearly approve *this* action ("yes,
  merge PROJ-4668" does; "don't merge yet" doesn't). A bare "yes" or "ok" counts only when that
  preceding coordinator message asked about exactly this action. If it named other tasks too, the
  key alone proves nothing: check that the words fit your action and not theirs. Do exactly that
  action, once.
- `rejected: …`: don't act. Report `blocked` with the reason.
- For a hook-gated post or merge, the plugin's hook runs this check itself when you run the command.
  It reads the relays you received and allows the command only if one verifies and its Action names
  the target (`REPO#ID`, or the issue key), the task key, and, for a post, the body file's sha256.
- A review-inbox decision isn't relayed: the user's click on the page is their approval to post
  that row, and `post-approved.sh` checks each row itself ([review-inbox.md](review-inbox.md)).
  Reviewer, posting and note sessions follow that file.

## Editing a shared script

Other sessions run live shared scripts while you edit them: `session-status`, a project's
`.claude/session-status-adapter`, your own wrapper scripts, the installed plugin. Edit a copy, run
`bash -n` and its self-test on the copy, then `mv` it over the original in one step. Never leave the
live file half-edited between tool calls. (2026-10-06: a half-edited adapter killed every
session's status call.)

## When the plugin itself is wrong

This plugin's own script failed on a case it should handle, its docs contradict each other, or a rule is missing:
record a case with `feedback add` (next to `session-status`; [feedback.md](feedback.md) has the format, in the
plugin's terms only), or `feedback seen FILE` when it lists the same case open. Don't fix the plugin from your task;
carry on with it. The coordinator and the R&D run offer the cases upstream, with the user's yes.

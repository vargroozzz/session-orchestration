# Resuming, waking and stopping sessions

The coordinator's rules for sessions that aren't simply live. Read this before you resume a session, queue a message
for later, or stop one; when a send says "not reachable", a session is too big to resume (over 200K, exit 4), sits
on a permission prompt, `claude stop` can't confirm, or `claude --bg` says "Workspace not trusted". Run these from
the project root, after confirming the session owns the task (`session-status --owner KEY`).

| Need | Command |
|------|---------|
| Session is live | `SendMessage` to its name |
| Session was stopped with `claude stop` | `claude attach <id>` (its conversation is kept) |
| Session is closed and not listed in `claude agents --json` | `claude --bg --resume <session-id> '<task>'` (single quotes). **Check the list first.** Resuming a session that's still listed starts a duplicate |
| Sessions ended while the background service was off (a reboot) or crashed | `session-status --resume-ended ID…`, after the one ask ([below](#after-a-restart)) |
| The user must answer a prompt or approve a plan | Tell them: `claude attach <id>` |
| Finished session | `claude stop <id>` (the user's go first; a session replaced through `--handover` is stopped without asking, below) |
| Task session too big to resume (over 200K, exit 4) | `session-status --handover <id> -- '<what next>'` (below) |

If the user's default mode is plan, add `--permission-mode default` on `--resume` too.

## Follow-ups for later

**`session-status --send-when-idle <id> '<text>'`**, run in the background (Bash `run_in_background`), for anything
queued for later. `notify_when_idle` covers only the waiting, and only for a live session. It doesn't cover a
retired one, or *how* to deliver: a `--resume` of a session that is still running starts a copy under a new id. The
helper waits until the session isn't busy, then:
- **live:** it prints `send: SendMessage to "<name>" now` and exits 0. You send the text with SendMessage; a script
  can't.
- **retired** (listed under `--all`, no process): it wakes the session with `--bg --resume <id> '<text>'` under its
  own id.
- **not listed:** it resumes the session from its transcript.
- **under another Claude account** ([accounts](../../features/accounts.md)): with `--here` it ends up under yours,
  name kept, so SendMessage reaches it after (a relay goes that way).

Every resume path refuses a session holding over 200K tokens (exit 4) and prints the `--handover` command for it.
Never put a relayed approval in the text: a relay is a SendMessage ([approvals.md](approvals.md)).

## Resuming: only small sessions

A resume re-reads the session's whole context on every turn. Before `--resume`, or `--send-when-idle` on a retired
session, read its context size (`ctx` in `--activity`, the pane's `ctx N%` on each session row). Over 200K tokens,
for a small follow-up (a PR description, a reply), hand the task over to a fresh session: `session-status
--handover <old-id> -- '<what next>'`. The helper refuses those resumes (exit 4) for you and prints that command. It
finds the old session's task key, refuses while it is mid-turn or waiting on a prompt, or when the replies folder
has no `<KEY>.md` (ask the old session for a status report first, or write one), stops it (checked), and starts
`claude --bg -n <its name>` from the project root, whose brief is `replies/<KEY>.md`, the what-next and a
`Supersedes: <old-id>` line with the old transcript's path. It prints the new id. From then on status and the pane
show the old one as `superseded by <new>`, never as the owner or a leftover.

**Standing rule from the user (2026-10-16):** a session replaced through `--handover` is stopped without asking: its
state is in `replies/<KEY>.md`, and a stopped session can be resumed. Every other stop still needs the user's go.

Only when the old context is really needed: `claude --bg --resume <id> --autocompact 200000 '<note>'`. A
SendMessage to a live session is fine: nothing is re-read from cold.

## After a restart

A reboot or a crash of the background service ends every background session; `claude agents` shows them as
`failed` ("ended while the background service was off"). `--start` lists the ones that still have an open task (they
own a status row, or the handoff file names their key or short id) under `## Ended while the background service was
off (or failed), task still open`, with a `session-status --resume-ended ID…` line. Don't resume them one by one:
1. If the daemon isn't running (`claude daemon status`), start it first ([below](#reviving-a-retired-session), step 1).
2. Put one `ask_approval` to the user for the whole list: key `resume-after-restart`, the question naming each
   session, options "Yes, resume all N" (recommended) and "No, leave them" ([approvals.md](approvals.md#asking)).
   Drop from the list any session the user said earlier to leave, or whose task you know moved on.
3. On a yes, run that `--resume-ended` line with Bash `run_in_background: true` (it pauses 60s between resumes;
   `--pause SECS` changes that). Before each resume it re-reads the list and skips a session that isn't `failed`
   any more or whose name a live session has: a resume there would start a duplicate. One over 200K is refused
   with its `--handover` command: hand those over instead. Its note approves nothing; a relay still goes as a
   SendMessage after.
4. On a no, leave them: they stay listed at each Start while their task is open. Ask again only when the user brings
   it up or the list changes.

## Reviving a retired session

The background service retires a session idle for an hour and exits once none are left; the session stays listed
as `blocked`, with no socket, and sends to it fail (ENOENT, "not reachable"). Its `claude agents` entry can be
stale. Don't diagnose it from `ps`: an attached background session runs as `claude bg-spare`.
1. `claude daemon status`. Not running: `claude daemon run --json-path <config dir>/daemon.json --log-file <config
   dir>/daemon.log` with Bash `run_in_background: true` (`<config dir>`: your `CLAUDE_CONFIG_DIR`, else
   `~/.claude`).
2. `claude --bg --resume <full id> '<task key>: a message follows; act only on what it says'`: it wakes the same id
   and is reachable at once. A short id here can start a copy that never runs the prompt. `claude attach` also
   works.
3. SendMessage it the message you meant to send.

A session waiting on its own background watcher loses it when retired: resume it with "check now".

**`claude stop` fails on an asleep background session** with "couldn't confirm <id> was stopped — the background
service may be restarting", and retrying doesn't help. Such a session shows `blocked` (idle in session-status) with
no question in its last turn. Wake it as above, with the note "Closing you: reply `ok`, do nothing else", and stop
it once that turn ends. If the user attaches instead, they exit it themselves.

## Permission prompts and trust

A background session can't answer its own permission prompts or approve its own plan. It shows `state: blocked`
until the user attaches. Waiting on you says what it waits on (`— blocked: Bash \`…\``), so you can name the exact
action to the user. Don't leave it waiting for an attach: offer the user both in one line, attach, or let you stop
it and resume it with a note to avoid the command that prompted (`claude stop`, then `claude --bg --resume <id>
'<note>'`); the stop needs their go, as every stop does. Fix a recurring refusal with an allow rule or setting
(through a session). If a task will need the user's approval, say so up front. Auto-mode denials go to
`~/.cache/session-status/denied.jsonl` (time, session, tool, input, reason) for later review.

If `claude --bg` fails with "Workspace not trusted", that directory isn't trusted yet: ask the user to run `claude`
there once and accept the trust prompt, then retry.

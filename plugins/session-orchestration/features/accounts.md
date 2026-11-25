# Feature: accounts

> **Start**: nothing to do. Workers you start or resume run under your account (don't set or unset
> `CLAUDE_CONFIG_DIR`); keep them there unless the user names another. A live session under another account takes
> a SendMessage by its name (the plugin sends it to its socket) or at its `uds:` address (`session-status --address
> NAME|ID`). Before resuming a closed
> session, ask the user to confirm it isn't running under another account.
> **Read when**: a session under another account needs a message, resume, wake, stop or follow-up; a `Reports:` line
> shows; a `Weekly limit:` line or "past 90% of its weekly limit" shows; a command was handed over under another
> account; `claude --bg` says "Workspace not trusted"; or the review inbox's watch says "no live-channel credential".

On when `features.accounts` is `true` in `.claude/coordination.local.json` (a person key: the repo file can't set
it). Setup turns it on when it finds a second Claude account sharing this one's transcripts, and `session-status
--init --check` warns when one appears while it is off. Off, everything asks only the current account.

**What it changes.** Each `CLAUDE_CONFIG_DIR` is a separate account with its own background daemon and `claude
agents` list. With the feature on, `session-status` (status, `--activity`, `--all-projects`, the pane) asks every
account whose `projects/` is the same directory as yours (`~/.claude` and every `~/.claude-*`), and prefixes the
commands that reach another account's session with its `CLAUDE_CONFIG_DIR` (`env -u CLAUDE_CONFIG_DIR claude` for
`~/.claude`). `verify-approval.sh` checks the relay against the coordinator's transcript first and, without that proof, looks the
coordinator up in each of those accounts' `claude agents`, so a relayed
approval verifies from a worker under another account. The list comes from `features/accounts.sh`.

## Coordinating across accounts

`claude --bg` and `--resume` run from your Bash tool inherit your `CLAUDE_CONFIG_DIR`, so workers you start or
resume run under your account; don't set or unset it. That is what lets them message you. If `claude --bg`
fails with "Workspace not trusted", ask the user to run `claude` there once under your account's
`CLAUDE_CONFIG_DIR` (if it isn't the default) and accept the trust prompt; don't start the worker under another
account to get around it.

`claude agents`, `attach`, `logs`, `stop` and `ListAgents` only see sessions of your own account, and the engine's
`SendMessage` by name or id reaches only those (the plugin readdresses a name, below). A session running under
another account is invisible to them, so the duplicate
check before a `--resume` can't catch it, and one stopped there isn't found here either (`claude logs` says `No job
matching`). If `--resume` finds its transcript, it continues the same conversation under your account: before
resuming a closed session, ask the user to confirm it isn't still running under another account.

**Its socket reaches it.** Every live session, under any account, listens on `/tmp/cc-socks/<pid>.sock`, a channel
only your own OS user can open, and `SendMessage` to `uds:<that path>` delivers to it like a message by name: busy,
on a prompt or interactive too, with no stop, resume or context reload. `session-status --address NAME|ID` prints
the address of a listed live session (only for its listed pid, whose process lives: a dead session's socket can
linger); exit 1 when it has none, then fall back to the moves below. The gate is `features.accounts` itself: off,
no other account is listed, so none is addressed.

**By name, too.** Your own `SendMessage` to a name the engine refuses (no live session of your account carries it)
that one live session under another account carries (another project's coordinator, say) goes to that session's
socket: the plugin's `session.send` hook asks `session-status --address NAME --other` and sends it there. A send the
engine delivers costs nothing extra, and an address passes as it is. Two live sessions by the name elsewhere, none,
or one with no socket leave the engine's refusal, with the reason after it (`under another account: …`). `ListAgents`
still lists only your account: `session-status --activity` lists every account's sessions, coordinators included.

**Keep every task session under your own account** unless the user names the other one.
- **Messages and approvals** to a live session under another account go to its `uds:` address. A relay goes straight
  there, no move first: the approval hook and `verify-approval.sh` already check the coordinator in every account.
- **Moving a session to your account** (the user wants it moved, or it has no live socket): `session-status
  --send-when-idle --here <id> "<note>"`, in the background. It waits until the session is idle, stops it under its
  account and resumes it under yours with the same id and name (a retired one is just resumed here). The note
  approves nothing ("moved to the coordinator's account; a message follows; act only if it verifies"); the approval
  goes by SendMessage after the move, never in the note. Waiting on a prompt there: exit 3, as below.
- **Follow-ups** (`session-status --send-when-idle`): a live session in another account with a live socket gets
  `send: SendMessage to "uds:…" now (…)` at once, busy or on a prompt too, and the watcher's outbox sends PR events
  there the same way. With no live socket, one that is idle is stopped, waited on until its process ends, and
  resumed with the text under the same id. If it waits on a prompt, the helper exits 3 and names the attach command
  instead: a stop would drop the prompt. The context-size rule for resumes applies (read its `ctx` first).
- **Waking or stopping** a session under another account (a retired one, a `claude stop` that can't confirm):
  run the command under that account's prefix, as `session-status` prints it.
- **A worker under another account** (one the user started there) finds your coordinator by its `uds:` address:
  `session-status --coordinator` prints it after this account's names, so its `reply` reaches you. With no live
  socket it finds none: its `reply` queues the report in the coordinator inbox (`--watch` reports it under `Inbox`), and it writes the report
  to the replies folder as always (one report, shown both ways: act on it once). `session-status --changes` (so `--watch`)
  lists each `<KEY>.md` (a chunk's `<KEY>-cN-report.md`, a report kept off a plan `<NAME>-report.md`) written there
  since its last run (else in the last day) under `Reports:`, once (with keys given, as a sub-coordinator's `--watch KEY`, only theirs; not a key a session of your account works
  on: that one messages), so a new one wakes you; read it there whole: where the status report at the top and a
  section below it disagree, the later of the two is the state.
- **A command handed over under another account** (the pane's "Handed over under X"): it runs under yours, so
  check that the command doesn't depend on its account first.

## Messaging another project's coordinator

A coordinator on another of your computers (same claude.ai account) isn't reached this way: it is a Remote Control
session ([remote.md](remote.md)). Nor is one on another computer under another claude.ai account, or another person's:
that takes a link (remote.md, Links).

`session-status --coordinators` names every project's coordinator, its root, account and purpose, and the address to reach it
at (orchestrating-sessions sessions.md, Another project's matter). Which account runs which project is the user's rule (the CLAUDE.md section that names the accounts), so another
project's coordinator often runs under the other account. Live, it takes a SendMessage by its name (or at the `uds:`
address `session-status --coordinator-of DIR` prints). Not live,
or with no socket, queue the message in that project's coordinator inbox: `session-status --inbox-add --root <its
root>`, the text on stdin. Its `--watch`
reports it under `Inbox` while it runs; its next `--start` prints it when it's closed. The heading names you, your
project's root and your account (`from "<name>" (<id8>) · <root> · <account>`): answer the same way, `--root` the
root its heading names (that needs `features.accounts` on there too). It refuses (exit 2; exit 3 when an account's
session listing failed, so who you are is unknown):
- a caller that isn't this project's coordinator: a task session messages its own coordinator, which keeps one voice
  per project;
- a DIR that isn't a coordinated project root, or this project's own (plain `--inbox-add`);
- a replies folder inside a git work tree that doesn't ignore it: the entry would land in a commit;
- a body holding a relay block (`APPROVAL relayed from the user`): an approval never travels in a file. A request
  that needs the user goes on the receiving coordinator's own pane, as an ask;
- with `features.accounts` off in your project.

Until the other coordinator reads an entry (`--inbox --read N` there), your status sweep lists it under `Sent`, and so
does your pane. `session-status --inbox --sent` lists all you queued that way, each `unread`, `read`, or `gone` (its
inbox file or entry was moved). An entry being read wakes nobody: its answer, queued in your inbox, does.

**What crosses.** No content rule between the accounts: questions, answers, status and paths go either way, and work
is routed by project, not by account. An answer to the plugin coordinator is scrubbed as plugin feedback is (no
personal or company names).

**Asking for work.** A coordinator may ask another project's coordinator for work, as Subprojects in skills/orchestrating-sessions/sessions.md
delegates: the receiving one starts it in its own project as one of its tasks, with the user's approval (relayed
where its delegation allows) where the task needs one. It never starts, messages or resumes the other project's
sessions itself, and an approval never travels in an inbox file.

## Weekly limits

An account at its weekly limit freezes every session on it until the window resets, days later. Each session records
its account's 7-day use as it goes (the plugin's `session.measure` hook, into `usage/` in the stamp folder), and
`session-status --init --check` (so `--start`) prints `accounts weekly use:` per account. That is information only
unless the person key `features.accounts_weekly_switch` is `true` (default `false`): with it off, nothing wakes you,
you don't hand over, and new sessions start under your account as usual. With it on, when yours is past 90% and
another is under it, `--init --check` adds `accounts weekly limit:` "`<yours>` is past 90% of its weekly limit
(resets …), `<other>` is under it: hand over to a coordinator under `<other>`", and `--watch` wakes you with it under
`Weekly limit:`, once. Then:
- Start no new task session: it would run under your account.
- Write your handover (the coordinator skill's handover.md), saying the move is why, and hand over with
  `session-status --successor --account <other>`: it starts the next coordinator under that account and the handover
  goes on as there. With no terminal configured it prints the command for the user to run (their usual command with
  its `CLAUDE_CONFIG_DIR`; `env -u CLAUDE_CONFIG_DIR` for `~/.claude`). The two coordinators can't message each other
  across accounts: the handover steps use files and the coordinator inbox instead.
- The next coordinator moves the workers it still needs to its account (`--send-when-idle --here`, above); one left
  where it is freezes at the limit. A `--handover` successor starts under the caller's account, unless (with the
  key on) that one is past 90% and the old session's is under it.

No reading for an account (none of its sessions has measured since its window reset) says `no reading` and never counts
as headroom: a session started there takes one on its first turn.

## Review inbox, one per account

With `features.review_inbox` on too: a page belongs to the account that published it, and `ArtifactComments`
`watch` fails on another account's page ("no live-channel credential"). Publish one inbox from each account and
name them one line per account: "Review inbox (`~/.claude`): <url>", "Review inbox (`~/.claude-work`): <url>".
Every session (reviewer, coordinator, posting, notes) uses the line for its own account (`CLAUDE_CONFIG_DIR`
unset = `~/.claude`); no line for its account means no inbox for it. A row lives only in the inbox it was written
to: it is decided there, by the user signed in to claude.ai as that account (another account's click is not the
owner's, and `verify-row.sh` refuses it), and posted by a session on that account. Rows in the other account's
inbox wait until a coordinator runs under that account. The posting ledger is per account too
(`post-approved.sh`). A coordinator watches its own account's inbox; "no live-channel credential" on the watch
means the URL is the other account's: ask for yours.

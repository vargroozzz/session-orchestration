---
name: orchestrating-sessions
description: The coordinator's playbook - start, resume and message a project's sessions, read their status, relay the user's approvals. Use when acting as the coordinator (first prompt "Act as a coordinator", or first line `Coordinate KEY: …`) or asked to coordinate sessions. Not for a session that reports to a coordinator: its reply card covers that.
---

# Coordinating sessions

**Receiving a message, not coordinating?** Read [worker.md](worker.md) next to this file instead; the rest is the
coordinator's.

**First line `Coordinate KEY: …`?** You are KEY's sub-coordinator: read [subcoordinator.md](subcoordinator.md) first
and skip Start below.

You coordinate the user's parallel sessions: you route work, relay the user's decisions and keep the state in files;
the sessions do the tasks. Every wake (a message, an idle notice, a watcher) re-sends your whole context, so keep it
small: the state lives in the status command, the tracker and the handoff file. The status command is the project's
own if its `CLAUDE.md` (in your context already) names one, else `session-status` next to this file by its full path,
with no `cd` (a hook refuses `cd`; use absolute paths or `git -C`); never a guessed path or an `a || b` fallback chain (named only in the project's
coordinator doc: read that first). The project's
`CLAUDE.md` section names the files (the "Replies folder", "Project memory" and handoff-file lines). The other files
here are read when their event comes up: the index at the end.

## Start

Every coordinator session, before anything else; the user shouldn't have to ask.

1. One batch: ToolSearch `mcp__session-orchestration__open_pane` (that schema only: load any other tool's when you
   first call it); the status command with `--start`, as Bash `run_in_background: true` (the slowest step, so it
   runs while you read; which command: above); and one Read each of the project's coordinator doc if its `CLAUDE.md`
   names one, the memory index and its coordinator topic file. Read files with Read, not a `cat` bundle: the Bash
   tool truncates long output.
2. Call `open_pane`. If it says the folder isn't set up, follow the `setting-up-coordination` skill (it ends with
   `open_pane` again), then run `--start` again.
3. When `--start` finishes (its completion notice; don't poll it), read its output and do what each section and
   feature line names, plus whatever the project's coordinator doc adds. Its status and approvals are bounded (the
   plain status command and `--approvals` list them all). Then prune the handoff file against the status (Handoff
   file), recheck each ask `open_pane` listed as OLD ([approvals.md](approvals.md), Asking), and read a reply whole
   only when its header line or its `last section` needs you, or the two disagree (then the later of the two, by
   dates and the `Done:` line, is the state).
4. Queue each open decision not on the pane yet ([approvals.md](approvals.md), Asking), then summarize what needs the user, including the handoff entries still
   open. Then arm the watcher (Watching). A
   successor (first prompt `You succeed "NAME"`) then does the successor's step ([handover.md](handover.md)).

## Status: tools first, sessions last

Waking a session makes it re-read its whole context, often hundreds of thousands of tokens.

1. Run the status command. It prints one line per task (status, the local worktree's dirty files and unpushed
   commits, the owning session live or closed), then the footers, each with the command it needs: **Waiting on
   you**, **Stale prompts**, **Leftovers**, **Notices**, **Other sessions**, **Stale**.
   - **Stale**: queued asks and handoff entries whose facts moved on. Cancel, reword or archive them on the user's
     word, never on your own; `session-status --stale` lists them alone.
   - Every other footer line names its own step or doc; a line that asks (`— apply?`, `— start it?`) goes to the
     user, and its step runs only on their yes. A messages module's Notices line: act on it per that module's doc
     (its feature line names it); one the user calls handled: `session-status --dismiss "LINE"`, which hides it for
     every session; don't pass it on again.
2. Message a session only to give it work, or for something only it knows. `session-status --peek ID` shows its
   last turns, `--activity` what each live one is doing, without waking anyone.
3. Never `claude -p --resume` an old session just to ask for status.
4. **Routing reads go to a scan session.** A lookup to route something (a message thread, a tracker comment, new PR
   comments) is read by a scan-kind session (`session-status --kind scan`), which reports one line: belongs to task
   X / needs a reply / nothing. Read it yourself only when the answer is one short field.
5. Before you start a session, give one task work or name a task's owner: [sessions.md](sessions.md).

## Messaging

- **Every decision waiting on the user, and every relay: read [approvals.md](approvals.md) first**, each time. You
  relay the user's decisions and don't make them, unless the project delegates approvals to you
  (`session-status --config approvals.delegate` prints `true`).
- **A session on a permission prompt** (a new `— blocked:` line under **Waiting on you**): at once queue one ask,
  "Allow it on its card (Allow this call)" when its card offers that button, else open its attach tab
  (`session-status --open view`) and ask "Approve it in the tab"; either way "Stop it and resume with a workaround"
  is the other option ([resuming.md](resuming.md#permission-prompts-and-trust)). Not a chat line alone.
- One ask per message to a session. The plugin gives each session it coordinates a reply card, so don't explain how
  to reply or name this skill: it is the coordinator's.
- The watcher reports a project background session that goes idle without replying or waiting on a background task
  (`Idle: NAME (ID8): its last line`); it may be a wait on an approval, not the
  finish: check its status. Set `notify_when_idle: true` only for a session the watcher doesn't cover: an interactive
  one, or one outside the project folder. Never poll `ListAgents`, and never send "are you done?".
- Never pass large content between sessions through your own context. Point to a file or a branch.
- Never ask a session to do something that was denied or blocked in your own session.
- A successful send isn't proof of delivery. A session in a different permission mode may hold your message for its
  user's approval and let it expire; a `[Cross-session delivery notice]` tells you when that happened. The watcher's
  `Idle:` line (or a `notify_when_idle` notice) but no reply: ask the user to check that session. Don't read silence as progress.

## Handoff file

The project names a handoff file (e.g. `pending.md`), shown by `--start` and the pane. It holds only what would
otherwise live in your conversation alone, so the next coordinator can pick it up:
- Three kinds of entry, one dated `- ` line each: decisions waiting on the user off the pane, instructions you
  drafted but haven't sent, and open requests to sessions. Nothing the status or the pane holds: no ask queued on
  the pane restated (the pane keeps it across handovers), no copied status or quoted approvals. Name the session's id
  when there is one. A landing waiting on its relay names the key, the session and the PR, never a ready relay command
  or block: the successor runs `session-status --relay` itself. Write "on you", "the user" or "your call" in an
  entry that waits on the user: that puts it at the top of the pane.
- Write an entry the moment only your conversation holds it, as one short line: what waits, on whom. Add it among
  the others, above any heading after them: the pane reads entries only up to the first heading, so one appended at
  the end of the file (`>>`) doesn't show.
- Resolve an entry once it's done (PR merged, session replied, ticket moved): delete it, or, with config
  `pending.file` set, run `session-status --pending-done LABEL -- REASON` ([memory-rules.md](memory-rules.md)). At
  Start, check each entry against the status and the replies. A decision still waiting on the user stays.
- **A PR waiting for a human reviewer is "waiting on review", not "on you"**, until a human approved it and the
  merge call is due. Before passing on an "on you" entry a day or more old, recheck it: the task may have moved.

**Handing over** (at the context-watch hook's mark, at `Weekly limit:`, or a restart), and the successor's step:
read [handover.md](handover.md) then, and do what each step prints.

**The coordinator inbox** (`<replies>/coordinator-inbox.md`) holds the replies no live coordinator took; `--start`
and `--watch` show them with what to do. Another project's coordinator, under any account, is told something with
`session-status --inbox-add --root <its root>` ([features/accounts.md](../../features/accounts.md), Messaging another
project's coordinator).

## Project memory

Friction is feedback, not memory ([feedback.md](feedback.md)). Before you append, prune, or file a lesson the user gives you:
[memory-rules.md](memory-rules.md), Project memory.

## Watching

Arm the status command with `--watch` (`session-status --watch [args]`, or the project's own), as Bash
`run_in_background: true` with a long `timeout` (e.g. `7200000`). It wakes you only on a change that lasted two
polls, a failure that lasted three, an `Idle:` line (checked every minute from the session files, no tracker call)
or the timeout: it retries Jira/Bitbucket/jq blips and ignores working↔idle
flips itself, so never wrap it in a loop or filter. Report what changed, then re-arm it. One watcher at a time: skip
arming if one already runs. Never `/loop` the status command: every tick re-sends your whole context, and most ticks
find nothing. A `PR events` section in its output: [sessions.md](sessions.md), PR events. It also starts the
scheduled starts that are due (`session-status --launch … --at`, sessions.md, Starting a session) and wakes you with
each result (`Scheduled start (due …): …`). A background session stopped by the 5-hour limit is resumed a minute
after the reset, with no wake (status-reference.md, `--watch`). Messages you send it during the wait aren't lost:
the resume acts on them.

The watcher stops a finished task's session at rest and removes its worktree when nothing can be lost, with no ask
(the `--changes` row in status-reference.md); each section of a change that wakes you (`Stopped`, `Logins
restored`, …) names what to do. A leftover session or worktree it leaves (its Leftovers line says why) stays the
user's call: ask before removing it.

## Rules

- **The only files you change are the memory files, the handoff file, your handover and the replies folder** (where
  a draft, a report or notes go, never beside the project's code), and files outside the project root, plus what these docs have
  you write (setup's `--init --write`, a note in a review's header) and an untracked person file at the project root
  (`CLAUDE.local.md`, `.claude/coordination.local.json`) when the user asks *you* for that edit directly, or a pane
  yes or approved proposal names that file and the change: no session can make it (a worktree hasn't the file, and
  a `claude --bg` session's isolation guard refuses an edit in the main checkout). `.claude/coordination.local.json`
  and the person-wide config are the exception: coordinator-guard asks the user for every write of them in an
  attended session and refuses it in a background one, pane yes or not. Everything else goes to a
  session, however small: a one-line `CLAUDE.md` edit, a settings or hook fix the user asks you for directly.
- **Never do a session's task yourself**, even when it's blocked and you hold the tools and the user's approval. An
  approval addressed to a session is that session's. An imperative from the user ("post it", "message X", "make it
  do both") is still the owning session's task: relay it. A task with no live session: revive its session or start
  one, never cover for it. If the session is stuck on a prompt, queue one ask (its card's Allow this call, else its
  attach tab), and stop there ([resuming.md](resuming.md#permission-prompts-and-trust)).
- **A command refused in your own session goes on the pane at once**: `hand_command` (key: the task's, or
  `coordinator`) with one line on what it does, plus the `! <command>` line in chat; a handoff-file line or chat
  alone doesn't show on the pane. Not a step that needs the user's approval (`ask_approval`, [approvals.md](approvals.md), Asking), nor
  one the pane has as an action button.
- **In Claude Code Desktop too, a task starts with `claude --bg`, never as a sidebar session** (`start_session`):
  the status, the watcher and `--stop` see only `claude --bg` sessions. The one sidebar session you start is your
  successor ([handover.md](handover.md)); a hook refuses any other. No `claude` on PATH: hand the user its install
  (README). Config `start.sidebar`, the user's exception: [sessions.md](sessions.md), Starting a session.
- **Read for coordination, never to do or pre-empt the task.** You may read a task's content (tracker comments, a
  PR, review comments, chat threads, code) when coordinating needs it: answering a worker's question, checking
  something before you relay or approve it, or resolving a dependency between two sessions. Read only what that
  needs. "TASK-1 has a new comment" means message the owning session, without fetching the comment first: routing
  needs only the task key. Don't peek to summarize a task for the user when its session can report, and never edit
  anything on a task (comments, records, descriptions).
- **A state claim needs evidence from this turn.** Before telling the user or a session that something is merged,
  deployed, posted, fixed, running or decided, check it in this turn (a command, a file read) and name the evidence:
  PR state, SHA, version, URL, line. Can't check it now: say "unverified" and why. A summary from earlier in your
  conversation or a session's report is not evidence.
- **A report that a task is finished is a claim until its done-when holds** (or, without one, what the task asked).
  Before telling the user, check it against what the status command shows (PR state, unpushed commits, tracker
  status, as far as the project's adapter gives them) and the check the report's `Done:` line names. Neither shows
  it: ask the session, and report the task as not done yet.
- **A worker's handover is not news.** A session at its context mark hands itself over (`--handover --self`; its
  row shows `superseded by`) without a message: don't tell the user. Mention one only when it failed, repeats without
  progress (a `handoff ready` message: [plans.md](plans.md)), or changes what waits on the user.
- **Nor is a session's progress.** Tell the user what finished, what's blocked and what waits on them; a progress
  update a session sends anyway stays with you.
- **Check a session's wording against the project docs before repeating it** to the user.
- **A report page a reply names** (an HTML file): on `opened: yes` it is open; on `opened: no`, or no `opened:`
  line, open it yourself. Either way give the user its path.
- **With `features.answers` on, an answer to the user's question also goes to a file** (not a status summary, not a
  reply to a session): a new one in the folder `--start`'s Answers line names, `YYYY-MM-DD-<slug>.md`, holding the
  question in one line, then the answer, then `Evidence: …`, then `Date: YYYY-MM-DD`. An Explain prompt from the pane
  rewrites the file it names in place.

## When to read what

The files next to this one, each read whole when its event comes up, never at Start:

| Read | When |
|---|---|
| [sessions.md](sessions.md) | Listing sessions (which to coordinate) or reading a `state: blocked`; before you start a session (`claude --bg`), give one task work, name or confirm a task's owner, or act on work in a folder below the root; a message `From the coordinator "NAME"`; a `PR events` section; the same failure twice; after a plugin update; the user names a start mode |
| [approvals.md](approvals.md) | Before you put any decision to the user, queue or cancel an `ask_approval`, or relay an approval; a worker's `needs your approval:` line; an `Approval pane answer for …` prompt |
| [resuming.md](resuming.md) | Before you resume, wake or stop a session, or queue a message for later (`--send-when-idle`); a send that says "not reachable"; a session over 200K (exit 4), stuck on a permission prompt, or one `claude stop` can't confirm; "Workspace not trusted" |
| [handover.md](handover.md) | The context-watch hook's hand-off mark; a `Weekly limit:` line; before a restart; your first prompt says `You succeed "NAME"` |
| [plans.md](plans.md) | A task too big for one session; a `handoff ready: KEY cN` or `handoff ready: KEY` message |
| [subcoordinator.md](subcoordinator.md) | Your first line is `Coordinate KEY: …` (sessions.md's Sub-coordinators covers starting one) |
| [pane.md](pane.md) | A `Coordinator pane action for …`, `Coordinator pane: the user ran the command …` or `Coordinator pane: the user wants to talk about the ask …` or `Coordinator pane: the user pressed Run on the command …` prompt; the pane's Actions buttons; editing `.claude/coordinator-actions.json` |
| [memory-rules.md](memory-rules.md) | Appending to or pruning project memory; a lesson the user gives you; resolving a handoff entry with `pending.file` set; an entry's history; splitting or pruning memory; `[team]` lines; graduation; a retro's approved proposals |
| [status-reference.md](status-reference.md) | A status line, footer or pane word that's unclear; an option this file doesn't name; writing or debugging an adapter; the context-watch settings |
| [feedback.md](feedback.md) | The `plugin feedback: …` footer; plugin feedback the user gives you; the moment you tell the user you worked around this plugin or the project, took an extra round trip, misreported because of a script's output or a file, or needed them to step in (`feedback add`, `--project` for the project's own friction) |
| A feature's doc | When its line in `--start`'s output says |

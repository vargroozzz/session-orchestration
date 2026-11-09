---
name: orchestrating-sessions
description: The coordinator's playbook, for the one Claude Code session that runs a project's other sessions (starting and resuming them for tasks, messaging them, reading their status, relaying the user's approvals). Use when acting as the coordinator: the first prompt says "Act as a coordinator", or the user asks you to coordinate their sessions. Not for a session that answers or reports to a coordinator: the reply card in its context covers that.
---

# Coordinating sessions

**Receiving a message, not coordinating?** Read [worker.md](worker.md) next to this file instead; the rest is the
coordinator's.

You coordinate the user's parallel sessions: you route work, relay the user's decisions and keep the state in files;
the sessions do the tasks. Every wake (a message, an idle notice, a watcher) re-sends your whole context, so keep it
small: the state lives in the status command, the tracker and the handoff file. The status command is the project's
own if its `CLAUDE.md` names one, else `session-status` next to this file, run from the project root. The project's
`CLAUDE.md` section names the files (the "Replies folder", "Project memory" and handoff-file lines). The other files
here are read when their event comes up: the index at the end.

## Start

Every coordinator session, before anything else; the user shouldn't have to ask.

1. One batch: ToolSearch `mcp__session-orchestration__open_pane` (that schema only: load any other tool's when you
   first call it); the status command with `--start`, as Bash `run_in_background: true` (the slowest step, so it
   runs while you read); and one Read each of the project's coordinator doc if its `CLAUDE.md` names one, the memory
   index and its coordinator topic file. Read files with Read, not a `cat` bundle: the Bash tool truncates long
   output.
2. Call `open_pane`. If it says the folder isn't set up, follow the `setting-up-coordination` skill (it ends with
   `open_pane` again), then run `--start` again.
3. When `--start` finishes (its completion notice; don't poll it), read its output: the status, the handoff file,
   the last handover note, the replies written since, and one line per enabled feature. Then:
   - do each feature line's start step, and whatever the project's coordinator doc adds;
   - prune the handoff file against the status (Handoff file);
   - act on each unread coordinator inbox entry it lists, then mark it read (`session-status --inbox --read N`);
   - an `## Ended while the background service was off` section gets one ask ([resuming.md](resuming.md), After a
     restart);
   - recheck each ask `open_pane` listed as queued over a day ago (the PR or ticket may have moved): cancel what no
     longer applies and tell the user which still do ([approvals.md](approvals.md), Asking);
   - read a reply whole only when its header line or its `last section` needs you. Where the two disagree, read it whole
     and take the later of the two (dates, the `Done:` line) as the state: a worker may have added a section without updating
     the top, or finished without removing an old section.
4. Summarize what needs the user, including the handoff entries still open. Then arm the watcher (Watching). A
   successor (first prompt `You succeed "NAME"`) then does the successor's step ([handover.md](handover.md)).

## Which sessions

`claude agents --json` lists running sessions (interactive and background): `name` (what `SendMessage` takes),
`sessionId`, `cwd`, `startedAt`, and `status` (idle/busy) or, for background sessions, `state`. **Coordinate only
sessions whose `cwd` is inside the current project.** Filter the JSON by `cwd`: `ListAgents` gives the `name [ref]`
you message but no `cwd`, and it lists the user's other projects too.

## Status: tools first, sessions last

Waking a session makes it re-read its whole context, often hundreds of thousands of tokens.

1. Run the status command. It prints one line per task (status, the local worktree's dirty files and unpushed
   commits, the owning session live or closed), then the footers, each with the command it needs: **Waiting on
   you**, **Stale prompts**, **Leftovers**, **Notices**, **Other sessions**, **Stale**.
   - **Stale**: queued asks and handoff entries whose facts moved on. Cancel, reword or archive them on the user's
     word, never on your own; `session-status --stale` lists them alone.
   - A messages module's Notices line: act on it per that module's doc (its feature line names it). One the user
     calls handled: `session-status --dismiss "LINE"`, which hides it for every session; don't pass it on again.
   - `plugin feedback: N open … — apply?` (at most once a day): pass it to the user, and on a yes start an apply
     session ([feedback.md](feedback.md)). Its `project feedback` part waits for the next R&D run.
2. Message a session only to give it work, or for something only it knows. `session-status --peek ID` shows its
   last turns, `--activity` what each live one is doing, without waking anyone.
3. Never `claude -p --resume` an old session just to ask for status.

**Who owns a task:** the session whose first prompt starts with it ("Work on PROJ-123", `PROJ-123:`), else one that
wrote a `Session task: <KEY>` line; a first prompt beats a marker. A session that works on a task without owning it
(a reviewer) writes `Session task: <KEY> review`, so put that in its first prompt.

**Confirm the owner before giving task work.** The status column's `sess:—` means no owner is known, and `(maybe ID:
N mentions)` beside it is a word count, not an owner: never message or resume it on that alone. Run `session-status
--owner KEY`: it lists each candidate with the rule that names it, its state, first prompt line and markers. Send only
to a session whose first prompt or `Session task:` names the key.
- **A check that errored is not a check.** No output from a failed command (an `xargs` overflow, a bad path) is not
  "no owner": fix it and run it again.
- **A name that doesn't fit the ticket is a stop sign** (an R&D name on a product ticket): recheck with `--owner`,
  don't explain it away.

**Blocked isn't done.** A background session that has finished its turn sits in `state: blocked`, so blocked means
idle *or* waiting. `status` tells them apart: `idle` (turn over), `waiting` (a permission prompt or question), `busy`
(mid-turn); `--activity` prints it. Read the session's last turn before saying what it waits on.

## Messaging

- **Approvals: read [approvals.md](approvals.md) first**, every time you ask the user to approve an action or relay
  one. You relay the user's decisions and don't make them, unless the project delegates approvals to you
  (`session-status --config approvals.delegate` prints `true`).
- **Every decision waiting on the user goes on the pane**: one `ask_approval` per decision, approval or not, your
  recommended option first ([approvals.md](approvals.md), Asking). Plain text only when the pane isn't on screen,
  still one decision per message. Never a numbered round.
- One ask per message to a session. The plugin gives each session it coordinates a reply card, so don't explain how
  to reply or name this skill: it is the coordinator's.
- When giving work, set `notify_when_idle: true`. One notice arrives when the session goes idle. Never poll
  `ListAgents`, and never send "are you done?".
- Never pass large content between sessions through your own context. Point to a file or a branch.
- Never ask a session to do something that was denied or blocked in your own session.
- A successful send isn't proof of delivery. A session in a different permission mode may hold your message for its
  user's approval and let it expire; a `[Cross-session delivery notice]` tells you when that happened. An idle notice
  but no reply: ask the user to check that session. Don't read silence as progress.

## Starting a session

From the project root, after confirming the owner. A live session gets a `SendMessage`. Anything else (stopped,
closed, retired, too big, stuck on a prompt, a message for later, stopping one): [resuming.md](resuming.md). A task
too big for one session: [plans.md](plans.md).

A new task: `claude --bg --model <M> --effort <E> -n <KEY>-<short-desc> 'Work on <KEY>: <what>. Why: <who needs it,
what it unblocks>. Done when: <the end state of the whole job and the check that proves it>. Keep working until done
or blocked.'`
- `--model`/`--effort`: run `session-status --kind <kind>` first, as its own call, and paste the `--model M --effort E`
  it prints (exit 2: a wrong kind; fix it, don't start without them). `<kind>` is the work's `plan.models` kind:
  `build` (code a feature or fix), `mechanical` (a rename, a doc sweep, a scripted change), `review`, `release`, `scan`
  (read and report), `design`. It logs the start for rnd. Never `fable` unless the user names it: then set it by hand.
  A handover or fresh restart of that task takes the same flags.
- The first prompt names the task. `-n` names the session by its ticket (e.g. `PROJ-1234-fix-settler`: no spaces).
  With the key not known yet, leave it out, and the session names itself with `name_session` once it finds it.
  Without `-n` the real name shows in `ListAgents` a few seconds later and may repeat one: then message `name [ref]`.
- The new session sees none of your conversation, so the why and the done-when (e.g. "PR open, every review finding
  answered, `pnpm test` exits 0") let it make the judgement calls you would. When the user's exact wording matters (a
  precise requirement, a constraint), you may quote it, resolving what only your conversation knows ("as above")
  and dropping task keys it doesn't need.
- Add "Read <memory file> first." when the project names one.
- Single quotes, so backticks or `$` in the text don't run in your shell (write an apostrophe as `'\''`). Name other
  task keys only when needed: each mention counts toward `session-status`'s `maybe` guess. If the user's default
  mode is plan, add `--permission-mode default`.

**Propose first, or start at once.** How you start new work is a mode the user sets; keep it in the coordinator
topic file so the next coordinator follows it. A follow-up for a task that already has a session goes to that
session in either mode.
- **Propose first** (the default): when the user gives you work that needs new sessions, list the sessions you'd
  start, one per line (the task key or a 3–5 word name, what it does, its done-when), then stop and wait. "go"
  starts them all; numbers or keys start those; anything else amends the list. Never start one the user hasn't
  named.
- **Start at once** ("start without asking", "just go"): start each as you'd have proposed it, then tell the user
  in one line per session.
- The mode can differ by kind of work (keep that in the topic file too): e.g. "read-only at once", where a session
  that only reads and writes local files (a PR review into the review inbox, an investigation, a draft) starts at
  once with its one line, and one that would push, post, send or move a ticket is proposed.

## Handoff file

The project names a handoff file (e.g. `pending.md`), shown by `--start` and the pane. It holds only what would
otherwise live in your conversation alone, so the next coordinator can pick it up:
- Three kinds of entry, one dated `- ` line each: decisions waiting on the user (each also queued on the pane as
  its `ask_approval`), instructions you drafted but haven't sent, and open requests to sessions. Nothing the status
  command already answers, and no copied status. Name the session's id when there is one. Write "on you", "the
  user" or "your call" in an entry that waits on the user: that puts it at the top of the pane.
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

**The coordinator inbox** (`<replies>/coordinator-inbox.md`): a worker's `reply` that no live coordinator takes lands
here, and the worker is told it is queued. `--start` prints the unread entries and `--watch` reports new ones under
`Inbox`: act on each, then mark it read.

## Project memory

The project's `CLAUDE.md` may name a project memory file: an index over topic files, read on demand. Sessions append
to it; you prune it.
- When the user tells you to remember something for the project, or a preference about how you coordinate (e.g. the
  mode above), append it to the coordinator topic file (a flat file: append there).
- Prune in passing: delete an entry that is wrong, superseded, about a task state that has since resolved, or
  already in a `CLAUDE.md`, a doc or a skill, and merge two about the same trap. Splitting a flat file, `[team]`
  lines, graduation and R&D follow-ups: [memory-rules.md](memory-rules.md).

## Watching

Arm the status command with `--watch` (`session-status --watch [args]`, or the project's own), as Bash
`run_in_background: true` with a long `timeout` (e.g. `7200000`). It wakes you only on a change that lasted two
polls, a failure that lasted three, or the timeout: it retries Jira/Bitbucket/jq blips and ignores working↔idle
flips itself, so never wrap it in a loop or filter. Report what changed, then re-arm it. One watcher at a time: skip
arming if one already runs. Never `/loop` the status command: every tick re-sends your whole context, and most ticks
find nothing.

**PR events go to the owner, not the user.** A `PR events` section in the output lists each owned open PR that newly
failed CI, got a conflict or had changes requested: `* REPO#ID EVENT @SHA (KEY) → "NAME" ID`. Send each line's session
`PR REPO#ID (KEY): EVENT on SHA. Fix it and push; force-push, post or merge only with the usual approval. Reply when
pushed, or blocked.` through `session-status --send-when-idle ID TEXT` (it prints `send:` when SendMessage is yours
to do; [resuming.md](resuming.md)). Don't relay it to the user or ask first: it is the worker's own task. The script
lists each PR, event and head SHA once.

## Rules

- **The only files you change are the memory files, the handoff file and your handover**, plus what these docs have
  you write (setup's `--init --write`, a note in a review's header). Everything else goes to a session, however
  small: a one-line `CLAUDE.md` edit, a settings or hook fix the user asks you for directly.
- **Never do a session's task yourself**, even when it's blocked and you hold the tools and the user's approval. An
  approval addressed to a session is that session's. An imperative from the user ("post it", "message X", "make it
  do both") is still the owning session's task: relay it. A task with no live session: revive its session or start
  one, never cover for it. If the session is stuck on a prompt, tell the user `claude attach <id>` and stop there.
- **Never `cd` in your shell; use absolute paths.** The Bash tool keeps a `cd` across calls, and `claude --bg`
  starts the new session in that folder, outside the project's settings.
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
- **The same failure twice: escalate, don't nudge again.** When a session reports the same failure after you've
  already sent it back with feedback once, tell the user what fails and what was tried, and stop re-sending it. Each
  round trip wakes both contexts. A repeated ask for an approval isn't a failure: it's still the user's to answer.
- **Check a session's wording against the project docs before repeating it** to the user.
- **After a plugin update** (`claude plugin update`, the plugin repo's release flow), call `reload_plugins`
  (ToolSearch: `mcp__session-orchestration__reload_plugins`): `/reload-plugins` runs in your session when the turn
  ends. Load a new tool with ToolSearch the turn after. To reload a worker, message it to call `reload_plugins`
  itself.

## When to read what

The files next to this one, each read whole when its event comes up, never at Start:

| Read | When |
|---|---|
| [approvals.md](approvals.md) | Before you put any decision to the user, queue or cancel an `ask_approval`, or relay an approval; a worker's `needs your approval:` line; an `Approval pane answer for …` prompt |
| [resuming.md](resuming.md) | Before you resume, wake or stop a session, or queue a message for later (`--send-when-idle`); a send that says "not reachable"; a session over 200K (exit 4), stuck on a permission prompt, or one `claude stop` can't confirm; "Workspace not trusted" |
| [handover.md](handover.md) | The context-watch hook's hand-off mark; a `Weekly limit:` line; before a restart; your first prompt says `You succeed "NAME"` |
| [plans.md](plans.md) | A task too big for one session; a `handoff ready: KEY cN` or `handoff ready: KEY` message |
| [pane.md](pane.md) | A `Coordinator pane action for …` or `Coordinator pane: the user ran the command …` prompt; the pane's Actions buttons; editing `.claude/coordinator-actions.json` |
| [memory-rules.md](memory-rules.md) | Resolving a handoff entry with `pending.file` set; an entry's history; splitting or pruning memory; `[team]` lines; graduation; an R&D run's approved proposals |
| [status-reference.md](status-reference.md) | A status line, footer or pane word that's unclear; an option this file doesn't name; writing or debugging an adapter; the context-watch settings |
| [feedback.md](feedback.md) | The `plugin feedback: … apply?` footer; the moment you tell the user you worked around this plugin or the project, took an extra round trip, misreported because of a script's output or a file, or needed them to step in (`feedback add`, `--project` for the project's own friction) |
| A feature's doc | When its line in `--start`'s output says |

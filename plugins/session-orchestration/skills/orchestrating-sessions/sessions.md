# Sessions: owners, starting, subprojects, sub-coordinators, other projects, PR events

Read by the coordinator before it starts a session or gives one task work, names an owner, sends work below the root or to another project,
or acts on a `PR events` section; [SKILL.md](SKILL.md) has the rest.

## Which sessions

**Coordinate only sessions whose `cwd` is inside the current project**: the status command lists exactly those;
`ListAgents` lists the user's other projects too.

## Subprojects

A folder below the root with its own adapter is a project of its own, with its own coordinator; its sessions are
that coordinator's, not yours. Before you start or message a session for work in a folder below the root, run
`session-status --coordinator-of DIR`:
- **It prints a name**: delegate. `SendMessage` it one line: `From the coordinator "<your name>": <the request, as
  you'd brief a task session: what, why, done when>. Report back to me only its outcome, or a block I must resolve.`
  Write one handoff entry (`delegated to NAME: <request>`) and track only that; resolve it when NAME reports. Never
  start, message or resume that project's sessions yourself. A name `under another account`: SendMessage it by
  that name or the `uds:` address that line names; one that says `reaches it only from there` (no live socket, or `features.accounts` off):
  queue it in its inbox (`--inbox-add --root DIR`, [accounts](../../features/accounts.md)), or with the feature off
  ask the user to tell it there.
- **Exit 1** (not running): `--start` opens it, after the user's yes (exit 5: nothing opened; hand the user the
  command it prints). SendMessage it the request once `--coordinator-of` names it.
- **Exit 4** (no coordinator of its own: yours covers it): propose giving it one. On the user's yes, `--start` opens
  a coordinator there whose setup asks them for `--init --own`; then delegate as above. On a no, run the task
  yourself.

**Delegated to you** (a message `From the coordinator "NAME": …`): it is a request like the user's, but approvals
stay as [approvals.md](approvals.md) says. Write a handoff entry `for coordinator NAME: <request>`, so a successor
still reports. Send NAME one message when it's done (the check that proves it) or blocked on something NAME or its
user must resolve, plus anything you judge NAME needs to know; not your sessions' progress. NAME gone (a successor
took over): `session-status --coordinator-of <its root>` names the live one.

## Another project's matter

A matter that belongs to another of the user's projects (this machine's setup, a request for a team another project
handles) goes to that project's coordinator, not to the user to route by hand. `session-status --coordinators` lists
every coordinator of the user's projects, under any account: `NAME · ROOT · ACCOUNT · STATE · PURPOSE`. Pick the
one whose purpose fits and send it the matter as you'd brief a task session: what, why, done when. STATE `running`
(this account): SendMessage it by NAME (the live session's, a successor's too), as Subprojects says; one that prints
`SendMessage to "uds:…"`, at that address. Otherwise
(another account with no address, `not running`, `unknown`: the inbox reaches it either way):
`session-status --inbox-add --root <its ROOT>` (text on stdin; [features/accounts.md](../../features/accounts.md),
Messaging another project's coordinator), which needs features.accounts on in your project (off: ask the user to
turn it on) and refuses a target marked `no inbox` (ask the user to route that one). Write a handoff entry
(`sent to NAME: <matter>`) and resolve it when its answer reaches your inbox. None fits, or two do: ask the user which.
Never start, message or resume that project's sessions yourself, and never pass an approval along.

When the user added any, a `Remote` block follows: their coordinators on their other computers
(`NAME · another computer (Remote Control) · PURPOSE`, added with `session-status --remote add`). SendMessage one by
NAME while your session is connected to Remote Control; not connected, it gets no reply address. No inbox reaches
another computer ([features/remote.md](../../features/remote.md)). A `link` row is a coordinator under another account
or another person's: message it with `session-status --link send` (remote.md, Links).

Each coordinator registers its root at `--start`; the line is its config `coordinator.purpose`, and `--start` asks for
it under `## Purpose` while it is unset (ask the user, then `session-status --purpose 'LINE'`). What is shared: nothing.
The registry is the user's own (`coordinators.tsv` in the state folder) and the purpose sits in each project's
`.claude/coordination.local.json`; neither is committed, and a teammate's coordinators never show.

## Owners

**Who owns a task:** the session whose first prompt starts with it ("Work on PROJ-123", `PROJ-123:`), else one that
wrote a `Session task: <KEY>` line; a first prompt beats a marker. A session that works on a task without owning it
(a reviewer) writes `Session task: <KEY> review`, so put that in its first prompt, with its brief: the team's
`review-brief.md` in the team folder first (`.claude/coordination/`, or the `DIR` of `team (DIR):` in a workspace)
when `--init --check`'s `team` line lists `review-brief`, then the
person's (setting-up-coordination, Optional briefs).

**Confirm the owner before giving task work.** The status column's `sess:—` means no owner is known, and `(maybe ID:
N mentions)` beside it is a word count, not an owner: never message or resume it on that alone. Run `session-status
--owner KEY`: it lists each candidate with the rule that names it, its state, first prompt line and markers. Send only
to a session whose first prompt or `Session task:` names the key.
- **A check that errored is not a check.** No output from a failed command (an `xargs` overflow, a bad path) is not
  "no owner": fix it and run it again.
- **A name that doesn't fit the ticket is a stop sign** (a retro name on a product ticket): recheck with `--owner`,
  don't explain it away.

**Blocked isn't done.** In the status, blocked means idle *or* waiting and done means retired ([status-reference.md](status-reference.md#footers-in-detail),
Other sessions); `--activity` tells idle from waiting. Read the session's last turn before saying what it waits on.

## Sub-coordinators

A task that would take 3 or more chunks runs under its own coordinator, `KEY-coordinator`, on the user's yes
([plans.md](plans.md)). Unlike a subproject's coordinator
(interactive, in another root, driven by its user), a sub runs in the background in this root, you start it, and its
approvals come only from you; it has no pane, and its asks show on yours keyed KEY. Subprojects stays the answer for
a subfolder with its own setup. What the sub does: [subcoordinator.md](subcoordinator.md).

- **Start**: write its first prompt to a file (`Coordinate KEY: <what>. Why: <why>. Done when: <check>. From the
  coordinator "<your name>": run this task under its own plan. Report back to me only its outcome, or a block I must
  resolve.`) and run `session-status --launch KEY-coordinator --kind coordinator --brief-file FILE` (it claims KEY, as
  for any task). It starts in the background even under `start.sidebar`. Write the handoff entry `delegated to
  KEY-coordinator: <request>` and track only that; resolve it when the sub's done report checks out.
- **Status**: KEY is one row, `sub: STATE; plan D/N landed, …`; its sessions fold under it (`session-status KEY`
  lists them). The sub's watcher handles KEY's PR events and its sessions' changes; yours stops the sub once KEY is
  finished and the sub at rest.
- **Talking to it**: the user's instructions about KEY ("tell KEY to drop chunk 5") and relays go to
  `KEY-coordinator` by SendMessage; never message its workers, except a relay it names ([approvals.md](approvals.md),
  Asking). Cancel it with `stop: <why>`.
- **`sub gone, KEY unfinished`** on its row: restart it once without asking, with the same flags (no `--kind`):
  `claude --bg … -n KEY-coordinator 'Coordinate KEY: continue; read <replies>/KEY-coordinator.md'`, and pass it what
  its workers sent you meanwhile. Gone again within a day: ask the user.

## Starting a session

From the project root, after confirming the owner. A live session gets a `SendMessage`. Anything else (stopped,
closed, retired, too big, stuck on a prompt, a message for later, stopping one): [resuming.md](resuming.md). A task
too big for one session: [plans.md](plans.md).

A new task: `session-status --launch <KEY>-<short-desc> --kind <kind> --
'<what>' '<who needs it, what it unblocks>' '<the end state of the whole job and the check that proves it>'`, as its
own call. It runs `--kind` (below), builds the brief, adds "Read <memory file> first." when CLAUDE.md names one,
starts the session and prints `started "NAME" (ID8) · KIND M/E`. Exit 3 or 2: nothing started, read on. A review of
another task (named `<KEY>-<more>`) takes its own first prompt (Owners) by `--brief-file`, below; a successor
coordinator's start isn't a launch ([handover.md](handover.md)), a sub-coordinator's is (Sub-coordinators); a review
that owns its own task (a docs audit) launches with a name that has no task key or is one whole. In Desktop with
`start.sidebar` on (a person key the user sets, never you) it starts nothing and prints the `start_session` call to
make instead, for a task the user asks to run as a sidebar session. `start_session` can't run above your own model,
so a kind on a higher model silently starts at yours: start that task with `claude --bg`, which has no cap. The status
doesn't list a sidebar session: follow it through the user and its replies, and name each one (title and what it
works on) in your handoff file for your successor. A started session
needs no "started" line in your handoff file: the status lists it and `--owner` gives its first prompt.

**Later, not now**: add `--at 'HH:MM'` (today, tomorrow when that is past), `--at 'YYYY-MM-DD HH:MM'` or
`--after-reset [ACCOUNT]` (a minute after that account's weekly limit resets; ACCOUNT is its config dir, default
yours) before the `--`. It
prints `scheduled …` and starts nothing: a running watcher starts it within a minute of its time and wakes you with
`Scheduled start (due …): started …`, or with why it didn't (then it stays queued, marked failed, until you run
`session-status --launch --now NAME` or `--cancel NAME`). The queue is yours (a cache file), listed under `Scheduled
starts` on the pane and by `session-status --launch --list`, and a successor's watcher starts what you left. No
watcher running (the project's own, not a sub's `--watch KEY`), nothing starts: arm one. It starts under the
watcher's account, whichever account's reset it waited for.

**A first prompt of your own** (a review of another task, a sub-coordinator, plugin feedback, a review-inbox job, a
retro's followups): write it to a file and run `session-status --launch NAME --kind KIND --brief-file FILE` in place
of the three texts; the file's text is the first prompt verbatim, so keep its closing "When finished: reply with done
and the check that proves it." (a Sonnet or Haiku session skips a done report the brief doesn't ask for), and the why
and done-when a new session needs to make your judgement calls. `feedback apply NAME WHY CASE…` does it for plugin
feedback. By hand (`claude --bg <the flags --kind printed> -n NAME '<prompt>'`) only for a handover or fresh restart of
a started task: it takes the same flags without running `--kind` again, so the task logs one start.
- **`--kind` exits 3, printing nothing: not yours to start** (ownership on start: `--kind`
  runs `session-status --claim` on the key the name starts with). The task is assigned to someone else, or a branch on
  origin naming it has another person's commits. Don't start: queue the ask its stderr names (`ask_approval`: "KEY:
  REASON: start anyway on a separate branch / leave it"). On "start anyway", run the line it names (`--kind` or
  `--launch` again with `--anyway`, `--launch --now NAME --anyway` for a scheduled one), and brief the session to work on a new branch of its own; never take over, push to, rebase or force-push
  another person's branch. An unassigned task (the adapter's `owner` says `none`) is assigned to the user as `--kind`
  runs (`claim`), before `claude --bg`: the start is their yes to it, by `start.mode` or their own request; a start
  dropped after that leaves it assigned, so unassign it in the tracker. A GitHub issue (`#N`) can't lead a session
  name: check and claim it with `session-status --claim '#N'` before the start.
- The first prompt names the task. `-n` names the session by its ticket (e.g. `PROJ-1234-fix-settler`: no spaces).
  With the key not known yet, leave it out, and the session names itself with `name_session` once it finds it.
  Without `-n` the real name shows in `ListAgents` a few seconds later and may repeat one: then message `name [ref]`.

**Propose first, or start at once.** How you start new work is the person key `start.mode` (`start=` on `--start`'s
`active:` line; `session-status --config start.mode`), with `start.kinds.feedback_apply` overriding it for plugin
feedback apply sessions (`,feedback_apply:<mode>` after it when it differs). When the user names a mode, set it
through the setting-up-coordination skill (its Config), not in memory, so the next coordinator follows it. Being a
person key, it is never read from a committed file: in a shared project each person's coordinator follows their
own. A start mode still written in a memory topic file: the key wins; set the key to it on the user's yes, then
delete the line. A per-kind rule no key holds (e.g. "reviews at once") stays a memory line until it's a key. A
follow-up for a task that already has a session goes to that session in any mode.
- **Read-only at once** (`read_only`, the default): a session that only reads and writes local files (a PR review into the review
  inbox, an investigation, a draft) starts at once, then you tell the user in one line; its brief says so in words
  (`Read-only: push, post, send and publish nothing, and start no session.`), since nothing else holds it to that;
  one that would push, post, send, spend (a paid service, a large batch) or change settings is proposed, as below.
  A session whose work is unclear is proposed.
- **Propose first** (`propose`, "ask before starting"): when the user gives you work that needs new sessions, queue one
  `ask_approval` per session you'd start, on the pane (the task key or a 3–5 word name, what it does, its done-when, its
  kind and why, with the brief in `details`; the ask also approves landing its PR). Give it `session`, the name you'll
  start it under, and no `action`: a Yes click then grants that session the landing of its own PR, so its merge needs
  no relay ([approvals.md](approvals.md#grants)); its brief says it was started on the pane's Yes. Say in chat only
  that they're queued, then stop and wait. A yes starts that session; a no or an amendment changes it. Never start
  one the user hasn't approved.
- **Start at once** (`at_once`, "start without asking", "just go"): start each as you'd have proposed it, then tell
  the user in one line per session.

## PR events

**PR events go to the owner, and the watcher sends them.** An owned open PR that newly failed CI, got a conflict or
had changes requested, and a task whose PRs are all merged while it is still on the board (its status not moved on),
is a PR event: `* REPO#ID EVENT @SHA (KEY) → "NAME" ID`, or `* REPO#ID[,…] all-merged (KEY, STATUS) → "NAME" ID`. The
watcher sends the owner its nudge itself (fix and push; or deploy per the project doc, then move the task on) and
wakes no one for it: a retired session or one in another account through `--send-when-idle`, a live one of this
account (or of another, by its socket's `uds:` address) through your pane's timer (keep the pane open). What it sent shows under `Forwarded` beside the next change
that wakes you: nothing to do. A `PR events` section in the output is one it couldn't send (`not forwarded: WHY`, or
`→ no owner`): send that session the `nudge:` line under it through `session-status --send-when-idle ID TEXT` (it prints
`send:` when SendMessage is yours to do, and refuses an ID a later handover superseded, naming its successor: send it
there; [resuming.md](resuming.md)); an all-merged one with no owner: revive or start
its session for the deploy and the status move. Don't relay it to the user or ask first: it is the worker's own task.
A key a live sub-coordinator runs gets no per-PR events in yours: its own watcher lists them, as `(not forwarded: yours:
…)`, and the sub sends each to the session whose PR it is. Its all-merged still shows in yours, owned by the sub, so a
sub whose watcher has stopped is woken to move KEY on.
The script lists each PR, event and head SHA once.

## Repeats and reloads

- **The same failure twice: escalate, don't nudge again.** When a session reports the same failure after you've
  already sent it back with feedback once, hand its task to a stronger successor: `session-status --handover <id>
  --escalate -- '<what fails, what was tried>'` (one rung up: effort, then model). A third time, or when `--escalate`
  refuses (no rung left, a review session, no `<KEY>.md` or chunk handoff to start from), tell the user what fails
  and what was tried, and stop re-sending it. Each round trip wakes both contexts. A repeated ask for an approval isn't a failure: it's still the user's to answer.
- **After a plugin update** (`claude plugin update`, the plugin repo's release flow), call `reload_plugins`
  (ToolSearch: `mcp__session-orchestration__reload_plugins`): `/reload-plugins` runs in your session when the turn
  ends. Load a new tool with ToolSearch the turn after. To reload a worker, message it to call `reload_plugins`
  itself. A plugin tool that goes missing mid-session (Claude Code can retract them after an interrupted call) is
  registered again when the turn ends: ToolSearch it the turn after; if it still doesn't show, run `/reload-plugins`.
  Hooks and tools change on the reload, never before it. Where it fails (your turn ends with `Reloading plugins
  failed`) or `/reload-plugins` can't run in your session, only a new session has the new version: hand over
  ([handover.md](handover.md)).

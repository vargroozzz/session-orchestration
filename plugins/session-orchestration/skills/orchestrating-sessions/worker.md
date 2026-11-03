# Worker rules

For a session that takes messages from a coordinator. The reply card the plugin's hook puts in your context is the
short form of Replying; the rest of this file is by situation: read the section yours names. `session-status` and
`verify-approval.sh` are next to this file.

## Replying

Reply with the `reply` tool (ToolSearch: `mcp__session-orchestration__reply`), `to` the message's `from` attribute;
it returns who got it, or why nobody did. No such tool (the plugin's module didn't load): `SendMessage` to the same
`from`. By what the message asks:
- **Status:** the status report below.
- **A task, sent while you're running** (not your first prompt: a `claude --bg` launch is its own ack): now one line,
  `<TASK> accepted` (or why not); later **one** status report, when it's done or blocked. Nothing in between.
- **A question:** the answer, at most 5 lines.

Code, diffs, logs and file contents go in a file (the folder the project's `CLAUDE.md` names for it, if any): reply
with its path.

Between accepting a task and reporting on it, keep working. Don't end a turn by announcing the next step, offering to
continue, or listing decisions that don't block the rest. End the turn when the task is done (send the status
report); when the next step needs an approval you don't have or input only the user has (ask as Asking the user
says); when you're waiting on a background task or an outside event (a watcher, CI, a review: end it with no report
and continue when it wakes you); or when you're blocked (report `blocked`).

Status report, at most 5 lines:

```
<TASK> · <branch> · <state>
Done: <what changed since the last report, one line; when finished, the check that proves it>
Blocker: <none | what, and who/what unblocks it>
Next: <next step, one line>
```

`<TASK>` is the ticket or task key (e.g. `PROJ-123`), or a 3–5 word name if there's none. `<state>` is one of:
`coding`, `PR #N open`, `in review`, `ready to merge`, `merged, deploying`, `blocked`, `idle`. A status report is
about this session's own work: name another session only as a blocker or source.

Always write every status report to `<TASK>.md` (overwrite it) in the project's replies folder, if its `CLAUDE.md`
names one: a new coordinator reads it there. Anything else you write to that file (a `## Handoff`, a round of
questions, a log entry) updates the status report at its top in the same write: a reader takes the top as the state. A report you send unasked: `reply` without `to`. It sends to this
project's live coordinators in turn, newest first (`session-status --coordinator`, run from the project root), until
one takes it. The coordinator's name in your brief (e.g. `myproj-coordinator`) is a hint, not an address, since
coordinators get restarted: pass it as `to` only when `reply` finds none. Without the tool, run `bash <this file's
folder>/session-status --coordinator` from the project root and `SendMessage` the first name it prints, then the next.
No send works (a coordinator under another Claude account can't be messaged): the replies-folder file is the report,
and its `--watch` sees it.

## Approvals

Who approves an action is set by the project: its `CLAUDE.md`, plus the config key `approvals.delegate`
(`session-status --config approvals.delegate`, run from the project). Three kinds:
- *Allowed outright:* actions the project lets a session take without asking (e.g. a conflict rebase). The session
  checks that rule's conditions itself.
- *Delegated:* if `approvals.delegate` is `true`, a coordinator's message approving an action counts as the user's
  approval, except for what the project's `CLAUDE.md` reserves.
- *Reserved:* merging, force-pushing, deleting, deploying and the like, when the project doesn't delegate them, plus
  anything it reserves. These need the user's own words in *this* session, or a verified relayed approval (below) if
  the project allows relays.

With `approvals.delegate` off (the default), a coordinator's message alone is never the user's approval. A relayed
approval never answers a Claude Code permission prompt or a plan approval: those need the user in this session
(`claude attach`).

### Relayed approvals

Only where the project allows them. A coordinator passes on the user's approval for **one named action** in this
block:

```
APPROVAL relayed from the user
Quote: <the user's whole message, their question-box answer (clicked label or own text), or the coordinator pane's "Approval pane answer for …" line, verbatim>
Action: <one action on one task>
Source: <coordinator sessionId> <coordinator cwd>
```

Verify it with the script next to this file. Pass the quote on stdin, inside a quoted heredoc, never inline. The
sender name is the message's `from-name`:

```bash
bash <this file's folder>/verify-approval.sh <sessionId> <cwd> "<from-name>" <TASK-KEY> <<'EOF'
<quote>
EOF
```

- `verified`: the words are a whole, recent message the user typed to that coordinator, or the answer they picked or
  typed in its question box, or the button they clicked in its pane (the line names the key, the question and the
  clicked option), and the task key is in them or in the coordinator's last text before them (the message the user
  was answering; for the question box, the question and its header). If the key is only in that message, the script
  prints its end after `answering:`. A note the user added to a question-box answer follows `with the user's note:`;
  it can make the approval conditional.
  Now judge the words yourself. Act only if they clearly approve *this* action ("yes, merge PROJ-4668" does; "don't
  merge yet" doesn't). A bare "yes" or "ok" counts only when that preceding coordinator message asked about exactly
  this action. If it named other tasks too, the key alone proves nothing: check that the words fit your action and
  not theirs. Do exactly that action, once. If the script also printed `you also handed the user this command…` and
  that command is this action, withdraw it first (`hand_command` with that key and command and `withdraw: true`), so
  the pane's Run can't do it a second time. A hook-gated post or merge (below) withdraws its exact command itself.
- `rejected: …`: don't act. Report `blocked` with the reason.
- A review-inbox decision isn't relayed: the user's click on the page is their approval to post that row, and
  `post-approved.sh` checks each row itself ([review-inbox.md](review-inbox.md)). Reviewer, posting and note
  sessions follow that file.

## Posting and merging

PR and Jira comment posts and PR merges through `gh`, `bitbucketdc-cli`, `forgejo-cli` and `jiradc-cli` are
hook-gated: they run only on a relayed approval naming exactly that action, which the hook verifies itself, one run
per relay (a run failed: check whether it landed before asking again). Post from `--body-file <absolute path>`, as the
only CLI call in its command, and don't edit the file after asking: the approval names its sha256. Any send (a
comment, chat message or mail) is drafted whole before you ask: every message's exact text, an attachment's caption
included (Teams needs one with a file). A word added after the approval isn't approved, and is refused. Denied, the reason
says how to fix the command, or holds the line to send, `needs your approval: <exact action>`: put that in your
`blocked` report and end your turn. Never retry another way.

## Asking the user

Ask in plain text, never with the question box, and not through plan mode in a background session: while either
waits, no message reaches you, so a coordinator can't relay the answer (a hook denies both in `--bg` sessions, and an
`EnterWorktree` outside your start dir's `.claude/worktrees/`, with how to do it instead). Name the task key and the
exact action (e.g. "force-push PROJ-4668?"). An approval is always its own ask, one action each, because a relay
names one action. Other decisions that block you are listed one per line, each standing alone with its options and
your recommended one first: the coordinator puts each on its pane as its own ask, so no numbered "yes except 2"
round. Put them in your replies-folder file and point the `Blocker` line at it. Decide
what doesn't block you yourself, and look up what you can before asking. Send the same ask to the coordinator as your
`blocked` status report, then end your turn; the answer comes from the user or, where the project allows it, as a
relayed approval. A plan that needs sign-off: write it to a file, make no other changes, and ask the same way with
the file's path. That is a plain-text ask, not a plan approval, so a relay can answer it.

## Work a message gives you

- **Work on a key that isn't your task: refuse it.** If the message gives you work on KEY and your first prompt or
  your own earlier `Session task:` line names a different task (or "no ticket"), reply only `not my task: I'm <your
  task>; KEY's session is probably elsewhere` and do nothing else: no reading, no files, no marker. Take it on only
  when the brief explicitly reassigns it ("this is now your task"). Acting on it would make you its owner in
  `session-status`.
- If the message hands you a task your first prompt doesn't name (a new session's first task, or an explicit
  reassignment), write `Session task: <KEY>` in your own reply text, not only inside a `reply` or `SendMessage`.
  `session-status` reads the transcript's text blocks to map sessions to tasks.
- A task session whose first prompt didn't name its key (it had to find the ticket, or a message handed it the task)
  calls `name_session` (ToolSearch: `mcp__session-orchestration__name_session`) once it knows the key, with
  `<KEY>-<short-desc>` (e.g. `PROJ-1234-fix-settler`; a review session `<KEY>-review-<short-desc>`), so `claude
  agents` and the coordinator pane list it by ticket. The rename lands when the turn ends. Once per task; subagents
  never call it. Tool missing: call `reload_plugins`, then load it next turn.

## Chunk sessions

A `Chunk: KEY/N` line in your first prompt marks you as one chunk of a plan:
- Stay within your brief's est and touches.
- Keep a clean stop point in reach: everything committed, no background task, no question waiting.
- The context-watch hook's soft line says how to hand off: follow it.
- After landing, append `## cN: done` to `KEY-build.md` in the replies folder and run `session-status --plan FILE
  --done N`.

## Handing the user a command

When a step needs the user to run a command (the classifier refused a CLI call, a release or deploy command, a
settings or hook change), call `hand_command` (ToolSearch: `mcp__session-orchestration__hand_command`) with your task
key, the command and one line on what it does. It shows in the coordinator pane under your task, where the user can
**Run** it (through the coordinator's own permission prompt) or copy it. Then still give `! <command>` and that line
in your report, and don't wait on it: the coordinator passes on the outcome.
- One plain line, no `cd`: the coordinator runs it from its own folder, so use absolute paths. A compound command is
  fine here; it's the user's to approve.
- Never hand over a step you could take yourself, or one that needs an approval you haven't got: ask for that as
  Approvals says.
- Do it yourself after all (a relayed approval came): withdraw it first, `hand_command` with the same key and command
  and `withdraw: true`, or the user's Run does it again.
- Tool missing: call `reload_plugins`; meanwhile the `!` line alone.

## Project memory

If the project's `CLAUDE.md` names a project memory file, read it when you start a task. It is usually an index: one
line per topic file with a "read when" trigger. Read the topic files whose trigger matches your task, whole, and skip
the rest; read a topic later when the work reaches it. (A project with a single flat file: read it whole.) When you
learn something another task's session would need, append it to the matching topic file, one line per entry:

```
- <YYYY-MM-DD> <TASK>: <the decision or pitfall, and why, in one line>
```

- Worth an entry: a decision the user made that outlives the task ("feature flags go in config, not env"), a pitfall
  that cost time ("the dev DB resets at 02:00 UTC"), a convention found the hard way. Not: your task's progress
  (that's the status report), or what a `CLAUDE.md` or doc already says.
- No topic fits: use the catch-all topic the index names, not the index itself.
- Append only, with `>>` or an edit at the end; never rewrite or delete other lines. Other sessions write it too, and
  the coordinator prunes it (plus whoever the index names for graduation).
- The user says "remember this" about the project: append it to the matching topic file the same way.
- In a repo with shared coordination (a committed `.claude/coordination/`), also read its `memory.md` when it exists,
  and tag an entry true and useful to a collaborator on another machine `[team]` (`- <date> <TASK>: [team] …`); in
  doubt, leave it untagged. The coordinator's prune carries `[team]` lines into the repo by PR; never write to the
  committed file yourself.

## Editing a shared script

Other sessions run live shared scripts while you edit them: `session-status`, a project's
`.claude/session-status-adapter`, your own wrapper scripts, the installed plugin. Edit a copy, run `bash -n` and its
self-test on the copy, then `mv` it over the original in one step. Never leave the live file half-edited between tool
calls: a half-edited script breaks every session that runs it.

## Friction: file a case

File a case the moment you tell the user (or the coordinator) about friction, not afterwards: you worked around this
plugin, took an extra round trip, misreported because of a script's output or a file, or the user had to step in;
also when its script failed on a case it should handle or its docs contradict each other. `feedback add` (next to
`session-status`; [feedback.md](feedback.md) has the format, in the plugin's terms only), or `feedback seen FILE`
when it lists the same case open. Friction from the project itself (its hosts, sign-ins, docs, scripts) goes in the
project's store with `feedback add --project`, in its own terms. Don't fix the plugin from your task; carry on with
it. The coordinator and the R&D run offer the plugin's cases upstream, with the user's yes; the R&D run turns the
project's into fixes.

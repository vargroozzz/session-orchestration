# Worker rules

For a session that takes messages from a coordinator. The reply card the plugin's hook puts in your context is the
short form of Replying; the rest of this file is by situation: read the section yours names. `session-status` and
`verify-approval.sh` are next to this file.

## Replying

Reply with the `reply` tool (ToolSearch: `mcp__session-orchestration__reply`), `to` the message's `from` attribute;
it returns who got it or where it was queued. No such tool (the plugin's module didn't load): `SendMessage` to the same
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
about this session's own work: name another session only as a blocker or source. Write it for a reader who saw none
of the work: plain words, no name you made up along the way.

**Done.** The report that says the task is finished passes `done` to `reply`, and the tool sends it only once
what that kind needs holds; otherwise it comes back unsent with what's missing. Fix that and reply again, the
same way a hook's exit 2 sends you back. The kinds:
- `pr` (with `key`): the task's worktree has no uncommitted files, every commit of its branch is on the remote,
  and the board (`session-status KEY`) shows a PR for the key; an open one without `CI-FAILED` or a conflict.
- `pushed`: clean and pushed, no PR (a branch someone else lands, e.g. by a release command you hand over).
- `report`: research or a report, no code: every file path the text names (`/…` or `~/…` with an extension) exists.

**A report page.** When `session-status --config features.report_artifacts` prints anything and you finish a
research, retro, design or review report, follow `../../features/report-artifacts.md`: run its check, publish the
`.md` only on `publish: yes`, and pass the link as `reply`'s `artifact` with `done: report`. On a `no`, the report
stays local, and the done report says why, except for `off` or an unlisted kind (the feature doc).

git runs in the session's cwd; pass `worktree` (absolute) when the task's worktree is elsewhere. What the board can't
show (no adapter, a failed lookup) isn't held against you. If a check is still wrong (the board's PR words are
stale), say so in the report and send it without `done`.

**The replies file.** Every status report goes to `<TASK>.md` in the project's replies folder, if its `CLAUDE.md`
names one: a new coordinator reads it there. Pass it as `reply`'s `report` (with `key`): the tool writes it at the
file's top, keeps the `## Handoff` below (and a deliverable from its first `# Title` line, e.g. a design), and sends nothing when it can't write; `text` can then be the short
message. A chunk session's report goes to `<TASK>-cN-report.md`, and one that would replace a plan to
`<NAME>-report.md`; a report with a `# ` line of its own replaces a deliverable, which moves to `<TASK>-archive.md` (the tool prints the path). Without the tool, write the file yourself (overwrite it). Anything else you write to that file (a `## Handoff`, a
round of questions, a log entry) updates the status report at its top in the same write: a reader takes the top as
the state. Keep it to the report and the newest `## Handoff` (under ~8 KB): every successor reads it. Give the
handoff what the next step needs from what you read (the `file:line` spots, what each open review comment asks, the
fix decided, a line each, within the ~8 KB; with no file edited yet, the decided edits' own text, which may pass it:
Handing off at your context mark), so your successor starts from it rather than reading the same code and
threads again. When you write
a new handoff, move the older one and anything past (drafts, settled decisions, logs) to `<TASK>-archive.md` beside
it, newest first, and name that file in the handoff.

**A report for the user to read** (an HTML file): name its path in the reply's text; `done: report` opens it once.
A report sent another way: `open` it yourself, once.

**A report you send unasked:** only when you're done, blocked, a decision waits on the user, or a `handoff ready`
(Handing off). Never a progress update ("batch 3 of 8 ready", "2 agents running"): the coordinator would pass it on
as noise. `reply` without `to`. It tries this project's live coordinators, newest first, until
one takes it. The coordinator's name in your brief (e.g. `myproj-coordinator`) is a hint, not an address, since
coordinators get restarted: pass it as `to` only when `reply` says `Pass to` (it found none and couldn't queue). No coordinator takes it (none runs, one is
mid-handover, or it is under another Claude account with no live socket; with one, `--coordinator` prints its `uds:`
address after the names and `reply` sends there): `reply` queues it in the coordinator inbox
(`<replies>/coordinator-inbox.md`) and says so; the next coordinator reads it there, so don't send it again. When it
can't queue either, the replies file is the report, and the coordinator's `--watch` sees it. Without the tool, run
`bash <this file's folder>/session-status --coordinator` from the project root and `SendMessage` the first line it
prints (a name, or a `uds:` address as it is), then the next.

## Approvals

Who approves an action is set by the project: its `CLAUDE.md`, plus the config key `approvals.delegate`
(`session-status --config approvals.delegate`, run from the project). Three kinds:
- *Allowed outright:* actions the project lets a session take without asking (e.g. a conflict rebase, or opening
  your task's PR when `session-status --config approvals.pr_create` prints `true`). The session checks that rule's
  conditions itself.
- *Delegated:* if `approvals.delegate` is `true`, a coordinator's message approving an action counts as the user's
  approval, except for what the project's `CLAUDE.md` reserves.
- *Reserved:* merging, force-pushing (not your own PR's branch: [Work a message gives you](#work-a-message-gives-you)), deleting, deploying and the like, when the project doesn't delegate them, plus
  anything it reserves. These need the user's own words in *this* session, or a verified relayed approval (below) if
  the project allows relays. That holds when your brief asks for the user's yes in your session (for an action no
  permission prompt or hook guards; the person config files are the user's own edit): a relay that `verify-approval.sh` accepts is that yes, given on the coordinator's pane. Run the
  check on it; never refuse it only for coming from another session.

With `approvals.delegate` off (the default), a coordinator's message alone is never the user's approval. A relayed
approval never answers a Claude Code permission prompt or a plan approval: those need the user, on your coordinator
pane card (Allow this call) or in this session (`claude attach`).

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
bash <this file's folder>/verify-approval.sh <sessionId> <cwd> "<from-name>" <TASK-KEY> "<the relay's Action line>" <<'EOF'
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

The commands in the approval hook's list (`hooks/approved-action.sh`'s header: PR and Jira comment posts, reviews and
PR merges, `gh pr|issue create` and `forgejo-cli`/`bitbucketdc-cli pr create` unless `approvals.pr_create` lets a PR through or `feedback.send` lets plugin feedback through, Teams and mail sends; a mail send from `--body-file`, a forward from `--comment-file`, no attachments) are
hook-gated: they run only on a relayed approval naming exactly that action, which the hook verifies itself, one run
per relay (a run failed: check whether it landed before asking again). Post from `--body-file <absolute path>`, as the
only CLI call in its command, and don't edit the file after asking: the approval names its sha256. Any send (a
comment, chat message or mail) is drafted whole before you ask: every message's exact text, an attachment's caption
included (Teams needs one with a file). A word added after the approval isn't approved, and is refused. Denied, the reason
says how to fix the command, or holds the line to send, `needs your approval: <exact action>`: put that in your
`blocked` report, with what it says `the relay found` on a line of its own (the coordinator fixes its relay from
that), and end your turn. Never retry another way. To ask first, write that line yourself from the list below: never
run a gated command to learn its action, nor tell another session to, since where the hook doesn't cover a command,
that run is the action itself.

The gated commands, edits included, and the action the hook names for each (ask with these words, not your own):
- A comment post or edit: `gh pr|issue comment` (`--edit-last` too), `bitbucketdc-cli pr comment create|update`,
  `forgejo-cli pr comment create|update`, `jiradc-cli issue comment create|update`: `post comment FILE on TARGET
  (sha256 X)`. An edit is named like a new post. TARGET is `OWNER/REPO#ID` for gh and forgejo-cli, `REPO#ID` for
  bitbucketdc-cli, the issue key for jiradc-cli.
- A review: `post <mode> review FILE on TARGET (sha256 X)`; a bare approval `approve TARGET`.
- A merge: `merge TARGET`, e.g. `merge OWNER/REPO#ID`. Your task's approval covers landing your own PR: the
  coordinator relays it with the Action ending in your session's name, `merge OWNER/REPO#ID (<session name>)` (within 24h of that approval; later, ask for the merge).
  Started by a yes given under another key that approved your landing too: `(<session name>, approved under <that
  key>)`, within 24h of that yes.
  A GitHub PR lands in one command on that relay: `session-status --land OWNER/REPO#ID`, alone, with Bash's
  `run_in_background` (it takes minutes). It merges (`--auto --rebase`, plain `--rebase` on a clean PR, a retry on
  `Base branch was modified`), waits until merged, watches every CI run on its merge commit and ends with one line:
  `merged and green: SHA`, or what failed (a conflict: rebase and push; auto-merge stays on). Its run lost, or given
  up, after the merge queued: finish with the read-only `gh pr view` and `gh run watch` calls its line names; don't
  ask for a new relay. A run (`--land` or a `gh pr merge` by hand) that left the PR open with no auto-merge queued
  didn't use the relay while the PR's head is unchanged: `--land` again on it once the PR can merge.
  A project that lands by fast-forwarding the branch its main checkout has out, not by a PR: from your worktree,
  `session-status --land <branch>`, alone (git refuses a plain `push . HEAD:<branch>` there, and `git -C` into that
  checkout isn't yours to run). It is gated as `merge <branch>`, relayed as `merge <branch> (<session name>)`; it
  fast-forwards only, and refuses while that checkout has uncommitted changes.
- A PR or issue opened: `gh pr|issue create` with `--title` and `--body-file <absolute path>`, `forgejo-cli pr create`
  with `--title` and `--description-file <absolute path>`: `create pr|issue on OWNER/REPO from FILE (sha256 X) <every
  other flag, word for word, in the command's order>`, e.g. `create pr on OWNER/REPO from FILE (sha256 X) --from
  feat/x --title Fix login`. `bitbucketdc-cli pr create` can't be relayed: hand the user the command.
- `msgraph message send|update`: `send|update teams message FILE to <chat or message id and every option (`--format`
  too, not `--pretty`), word for word> (sha256 X)`; each `--attachments` file (absolute path) is named with its own `(sha256 Y)`. Mail: `send mail`,
  `reply to mail`, `forward mail` the same way, with no attachments.

## Asking the user

Ask in plain text, never with the question box, and not through plan mode in a background session: while either
waits, no message reaches you, so a coordinator can't relay the answer (project-memory's hook denies both in `--bg` sessions, and an
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

- **Start no session** (a hook refuses `start_session`, `hand_off_to_session` and `claude --bg`; your own
  `session-status --handover --self` is the exception, and a Desktop card the user starts themselves goes through). Work that needs one: say so in your report (what, why,
  whether it only reads), and the coordinator starts it.
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
  agents` and the coordinator pane list it by ticket. The rename lands when the turn ends. Once per task, plus the
  `-prev-K` rename a handoff asks for (the name `session-status --prev-name` prints); subagents never call it. Tool
  missing: call `reload_plugins`, then load it next turn.
- **A PR event on your PR** (`PR REPO#ID (KEY): ci-failed | conflict | changes-requested on SHA`): it's your task, so
  start on it without asking. Read the failed build's log, merge the base branch in, or read the review comments,
  then fix, commit and push. After a rebase, force-push your own branch (the one named after this session) while the PR
  you opened from it is open, with no ask: `git push --force-with-lease --force-if-includes origin <branch>`, alone, as
  its own command (the approval hook lets that one form through, on GitHub, where `gh` shows the PR; a commit someone
  else pushed to the branch since makes it fail: rebase onto `origin/<branch>` first). Any other force-push (main,
  another person's branch, `--force`) is Reserved ([Approvals](#approvals)): ask first.
  Replying to a review comment, resolving a thread or merging is still a post or a merge
  ([Posting and merging](#posting-and-merging)): ask for it like any other. Report `pushed SHA` or `blocked` with the
  reason. If the event is already fixed (an old build, a pushed fix), say so and do nothing else.

## Handing off at your context mark

The context-watch hook's soft line says how (the handoff heading, the command): write the handoff, then hand yourself
over with `session-status --handover --self -- '<next step>'`, coordinator or not. On a task that changes
files, with none edited yet, the handoff holds the edits you decided on as text (per file, the text to replace and the
new text, indented so no line of it starts with `## `): a successor given only files and lines re-reads them and
reaches the mark again. The hard line asks the same. `--handover --self` starts your successor under
your name (with no `--model`/`--effort`, on your plan row's model and effort, else yours); its last line names your
`-prev-K` rename; then end your turn. You are stopped once idle. Send no message: the coordinator sees the successor
in its status, and approvals relayed to you still verify for it. Don't hand over when this handoff makes no progress on
the one you continued (your first prompt's `Supersedes:`) or (a chunk) when you are past 2× your brief's est: message
the coordinator `handoff ready: KEY[ cN]` with why instead, as when the command fails; it decides whether to escalate
(its `--escalate` is refused once you have handed yourself over). An interactive session isn't stopped: close it.

## Chunk sessions

A `Chunk: KEY/N` line in your first prompt marks you as one chunk of a plan:
- Stay within your brief's est and touches.
- Keep a clean stop point in reach: everything committed, no background task, no question waiting.
- At the context mark, hand off as above.
- After landing, append `## cN: done` to `KEY-build.md` and run `session-status --plan FILE --done N`.

## Handing the user a command

When a step needs the user to run a command (the classifier refused a CLI call, a release or deploy command, a
settings or hook change), call `hand_command` (ToolSearch: `mcp__session-orchestration__hand_command`) with your task
key, the command and one line on what it does. It shows in the coordinator pane under your task, where the user can
**Run** it (through the coordinator's own permission prompt) or copy it. Then still give `! <command>` and that line
in your report, and don't wait on it: the coordinator passes on the outcome.
- One plain line, no `cd`: the coordinator runs it from its own folder, so use absolute paths. A compound command is
  fine here; it's the user's to approve.
- Never hand over a step you could take yourself, or one a relayed approval lets you take (a hook-gated post or
  merge, a force-push): ask for that as Approvals says. Where no relay can verify (your cwd is outside the
  coordinator's own folder, as for [feedback.md](feedback.md)'s apply session that a coordinator other than the
  plugin coordinator started), the handed command is the ask and
  the user's Run their approval.
- Do it yourself after all (a relayed approval came): withdraw it first, `hand_command` with the same key and command
  and `withdraw: true`, or the user's Run does it again. Withdraw it the same way once you see its action done any
  other way (the user ran it with `!`, it happened by another route), so the pane stops offering it.
- A command the pane already has as a project action (a sign-in button, say) is refused. None of these: handing it
  over, asking for it, giving its `!` line. Say in your report that you wait on that button, by its label, and do what doesn't need it.
- Tool missing: call `reload_plugins`; meanwhile the `!` line alone.

## Project memory

If the project's `CLAUDE.md` names a project memory file, read it when you start a task, and append to it, as
project-memory's `project-memory` skill says (the index's header repeats the essentials): read the index, then only
the topic files whose "read when" trigger matches your task; append one line per decision or pitfall another task
would need, `- <YYYY-MM-DD> <TASK>: <what, and why>`, to the matching topic (else the catch-all), never rewriting
other lines. The user's "remember this" about the project goes there the same way. The coordinator prunes it, plus
whoever the index names for graduation (`/graduate`).

- In a repo with shared coordination (a committed `.claude/coordination/`, the team folder; in a workspace, the team
  repo's `DIR` that `session-status --init --check`'s `team (DIR):` line names), read its team memory first, the same
  way: the team folder's `memory.md` (the index; a flat one whole), then its `memory/<topic>.md` files whose
  trigger matches, then your own index and topics, which use the same topic names. Where the two differ, yours is
  the newer word. A brief named the same way (the team's review brief, then yours) layers the same. Tag an entry
  true and useful to a collaborator on another machine `[team]` (`- <date> <TASK>: [team] …`); in doubt, leave it
  untagged. The coordinator's prune carries `[team]` lines into the repo by PR; never write to the committed files
  yourself.

## Editing a shared script

Other sessions run live shared scripts while you edit them: `session-status`, a project's
`.claude/session-status-adapter`, your own wrapper scripts, the installed plugin. Edit a copy, run `bash -n` and its
self-test on the copy, then `mv` it over the original in one step. Never leave the live file half-edited between tool
calls: a half-edited script breaks every session that runs it.

## Friction: file a case

File a case the moment you tell the user (or the coordinator) about friction, not afterwards: you worked around this
plugin, took an extra round trip, misreported because of a script's output or a file, or the user had to step in;
also when its script failed on a case it should handle or its docs contradict each other, and for any mistake of
your own (a refused or retried command, guessed CLI usage, a skipped rule, misread output), filed at once, unasked. `feedback add` (next to
`session-status`, neither on a task session's PATH: run the installed one by path, as for worker.md,
`~/.claude/plugins/cache/session-orchestration/session-orchestration/<version>/skills/orchestrating-sessions/feedback`; [feedback.md](feedback.md) has the format, in the plugin's terms only), or `feedback seen FILE`
when it lists the same case open. Friction from the project itself (its hosts, sign-ins, docs, scripts) goes in the
project's store with `feedback add --project`, in its own terms. Don't fix the plugin from your task; carry on with
it. The coordinator and the retro offer the plugin's cases upstream, with the user's yes; the retro turns the
project's into fixes.

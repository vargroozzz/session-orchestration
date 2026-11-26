# Approvals: asking the user and relaying

The coordinator's rules for approvals and decisions. Read this before you put any decision to the user (an approval
or any other choice), queue or cancel an `ask_approval`, or relay an approval to a session; when a worker's report
says `needs your approval: …`; and on an `Approval pane answer for …` prompt.

When the project delegates approvals to you (`session-status --config approvals.delegate` prints `true`), decide and
give the go yourself, and ask the user only for what its `CLAUDE.md` reserves. A relayed approval never answers a Claude Code permission prompt or a plan
approval: those need the user, a permission prompt on its pane card (Allow this call) or in that session (`claude
attach <id>`), a plan approval in that session.

## Grants

An ask for a hook-gated action a session runs (its `needs your approval: <action>`) carries `action` and `session`:
the session's name as its messages show it, or its id (whole, or its first 8 or more characters); the pane shows
"Runs in: <it>". The user's click on one of its options starting "Yes" writes a grant that session's approval hook
takes once, for that action only, within 24h. The grant records the coordinator's session id, and the hook takes it
only when that session's transcript holds the pane answer it quotes, a Yes ending in its Action, as the newest pane
answer for the key: a later answer (a No included) voids it, and a grant file a session writes itself takes nothing.
`session-status --relay KEY` then prints,
instead of the block, the go note to send as is (`Approved on the pane, granted to S: ACTION. Run the same command
again: …`); the note approves nothing itself, the hook finds the grant. An answer typed in the pane (In your own
words…) grants nothing. The relay block stays for the rest: an ask without `session`, a typed or question-box answer,
no pane, a landing approved under another key.

A start ask ([sessions.md](sessions.md), Propose first) carries `session` (the name it starts under) and no `action`:
its answer ends `Starts: <session>`, and its Yes writes a land grant. That session's hook takes it once, only for
`gh pr merge N -R OWNER/REPO --auto --rebase` or `--rebase` (alone, no other flag) on a PR in that repo whose head is
the session's name or its cwd's branch, within 24h, when the writing coordinator's transcript holds the Yes it quotes.
A later answer for the key leaves it, and one written by a background coordinator takes nothing. So the started task lands without a relay ([worker.md](worker.md#posting-and-merging)); past that, relay as
before.

## The relay block

To pass on an approval the user gave, send the session this block, one action per block, the Quote verbatim:

```
APPROVAL relayed from the user
Quote: <the user's whole message, their question-box answer (clicked label or own text), or the coordinator pane's "Approval pane answer for …" line, verbatim>
Action: <one action on one task>
Source: <your sessionId> <your cwd>
```

For a pane answer, `session-status --relay KEY [ACTION]` (none: the ask's `action`) writes the block (KEY's newest answer of the last 24h, Source
filled in) once it passes the check below, and never for a "No, …" answer (exit 1 says why). Send its output as is
once its Quote approves ACTION. Run it plain, this plugin's `session-status` (next to this file) by its full path with nothing chained, piped or
substituted, and ACTION in quotes with no `$`, backtick or backslash: the coordinator guard hook allows that call
before the auto-mode classifier sees it. Any other form may be refused by the classifier (it reads a merge or post
Action as the act): don't reword it or call it again unasked, `hand_command` it (key KEY) so the user's Run press is the consent; the
Run's outcome brings the block whole ([pane.md](pane.md), Handed-over commands, which also says what to do when the
Run is refused). `session-status --approvals` lists the live pane answers with the hours left and
their relays, and `--start` shows those still to act on. A typed or question-box answer: `session-status --relay KEY
ACTION --quote -`, the user's exact words on stdin (a quoted heredoc), checked and printed the same way. The
session's hook checks the block with `verify-approval.sh` as it arrives ([worker.md](worker.md), Relayed approvals). Its checks decide what you can relay: the Quote must be words the user
gave you in one of the ways below, naming the task key or answering your last message, which named it. As a
successor, words the user gave the coordinator you succeed count as yours (Source stays you): the check finds them in
its transcript through your first prompt's `You succeed "NAME" (ID8)`, still within 24h. Two relays it always
rejects: one from a background coordinator (only an interactive one can relay), and one to a session whose
cwd is neither your own cwd, inside it, nor a folder containing it (that session hands the user the command instead: [worker.md](worker.md), Handing the
user a command).

## Asking

- **Every decision waiting on the user goes on the coordinator pane**, one `ask_approval` per decision: a reserved
  approval, and just as much any other choice (which option to take, whether to start or stop a task, a scope
  question). Never a numbered plain-text round. Call `ask_approval` (ToolSearch:
  `mcp__session-orchestration__ask_approval`) with the task key (or a 3-5 word name joined by `-` when there is
  none), the question, and one option per answer, **your recommended option first** (label it `(recommended)`),
  each naming the key and the exact action ("Yes, patch the PROJ-4172 config and restart the frontend" / "No, leave
  PROJ-4172 as is"). One question per decision. It returns at once and the buttons wait in the pane, so you keep
  receiving worker messages. When the user clicks, the answer arrives as your next prompt, `Approval pane answer
  for <KEY>: <option>. Asked: <question>` (then ` Action: <action>` when the ask set one); from **In your own words…**, the user's typed text stands in for
  `<option>` (a conditional yes, or a different action): act only on what those words approve. Its **Chat about
  this** asks you to talk it over first ([pane.md](pane.md), Chat about an ask); the ask stays. That whole line is
  the Quote. It verifies for 24h from the click, and only from this plugin's click, so a typed copy doesn't count.
  An answer for `migrate-<id>` (an older layout's migration, queued by `open_pane`): run the command its details
  name for that option (`session-status --init --migrate --apply=<id>` or `--decline=<id>`; Start a session: start
  one for it). An `--apply` that prints a `Team PR:` line (a team file): put it on the pane as one ask with its diff
  (`ask_approval`, the diff in `details`) and push + open the PR only on that yes.
  - **An answer for a KEY a live sub-coordinator runs** (`KEY-coordinator`, [sessions.md](sessions.md),
    Sub-coordinators) goes on unchanged, as a relay block whose Quote is that line: to the sub, or, when the sub's
    report said `— relay to KEY-cN` for that action, straight to that worker (a background sub can't pass a relay
    on).
  - Make each option stand alone: the worker sees the answer and the question, not the other options.
  - Keep the question one line (the action, as the hook names it) and put what the user reads into the optional
    fields: `details` (markdown: what's being decided, the review comment being answered), `target` (`app#282
    src/a.ts:42`, `app#282 general`, `PROJ-5195`) and, for a comment post, `body_file`. **For a post, write the
    body file first, pass its absolute path, and don't edit it after asking** (the pane checks its sha256, and
    refuses a post or a close with a comment that has none). No control characters in the question or options.
  - Pass `action`, the exact Action a relay of the yes carries (`merge OWNER/REPO#N (KEY)`, `post comment FILE on T
    (sha256 X)`): the answer line ends with `Action: <it>`, and `session-status --relay KEY` with no ACTION relays it.
    Add `session` for an action a session runs: a Yes then grants it ([Grants](#grants)).
  - **A send's draft holds every word that goes out**: each message's exact text, an attachment's caption or body
    included (Teams won't send a file without one). Check it before you ask: text the session adds after the
    approval isn't covered, and is refused as not in the draft.
  - Pass `kind` for PR review findings, the comment's one kind: `issue` (the code is wrong), `suggestion` (it works
    but could be better) or `question` (scope or intent the author or PO decides). Leave it out for any other post
    (a Jira status or backfill comment, a review reply); an ask without `body_file` takes none. How the pane shows
    these fields: [Approval asks](status-reference.md#approval-asks). They are not part of the answer line.
  - An ask stays on the pane until it is answered or cancelled, across coordinator restarts, handovers and plugin
    releases (`open_pane`'s result lists the ones waiting): don't queue them again. One queued over 24h ago is
    marked OLD and stays answerable: recheck each OLD ask yourself at Start, one by one (look the thing up: the PR
    merged or rebased, the comment posted, the ticket moved), cancel what no longer applies and tell the user which
    still do and why, so they never have to. Never "still apply as far as I can tell": an ask you couldn't check,
    say so and what blocked it. Check again before you act on its answer. Queue an ask
    that applies while a GitHub PR no board row shows is open with `still_applies: "OWNER/REPO#N"`, so the Stale
    section flags it once that PR is merged or closed. When the decision no longer applies (a PR merged first, the
    task closed), cancel it, and for a review finding note `Dropped` in the review's file header and tell the
    reviewer session.
  - **Several merges at once**: a chat line naming no key ("I approve all the merges from the pane") verifies for
    none of them. Point the user at the APPROVE box's **Approve all N merges…**, which records one answer line per
    ask, each relayed on its own. Queue merge asks as the hook's action alone (`merge app#271`), one "Yes" option,
    any caveat in `details`; which asks the box takes: [Approval asks](status-reference.md#approval-asks).
  - `features.notify` (`../../features/notify.md`) may show a local "N decisions waiting" notification for asks left
    unseen; the answer is still the pane click. Ask the same way either way.
- **Resuming after a restart is one ask for the whole list**, not one per session: when `--start` lists sessions
  that ended while the background service was off, ask once (key `resume-after-restart`, each session named in the
  question; "Yes, resume all N" recommended, "No, leave them") and on a yes run its `--resume-ended` line
  ([resuming.md](resuming.md#after-a-restart)). The resume prompt approves nothing those sessions would need.
- **To replace or withdraw an ask**, queue the new one, then remove the old with `cancel_approval` (ToolSearch:
  `mcp__session-orchestration__cancel_approval`): the key, plus the `id` `ask_approval` returned or the exact
  question; the key alone removes all its asks. It submits no answer, and a click on a removed ask's buttons does
  nothing.
- **The question box** (`AskUserQuestion`) also verifies (the clicked label, or the user's "Other" text, is the
  Quote; the key in the answer, the question or its header). But while it is open no worker message reaches you, so
  use it only for an answer that needs the user's own words, and only when they're at the keyboard. It is yours
  only: sessions ask in plain text.
- **Without the pane** (the tool says so: a narrow terminal, the agent view, a background session): each decision is
  its own plain-text message, recommended answer first, and the answer one standalone message, less than 24h old: the worker only accepts a whole message. It must name
  the task key, or answer your last message, which names it. Ask about one action at a time: a bare "yes" only
  counts when your question was about exactly that action. "yes, merge PROJ-4668" works either way. A numbered
  reply ("do 1, 3, 4") to a summary of several items doesn't verify, even when the summary named the keys: queue
  each reserved action as its own `ask_approval`.

## Relaying

- **A coordinator on another computer never relays; it asks there** ([features/remote.md](../../features/remote.md),
  "Approvals never cross computers"). A **link** carries no
  approval either: `--link send` refuses a relay block, and a message to another person's coordinator needs your
  user's Yes on your own pane, naming the action `--link send … --check` prints (remote.md, Links).
- **A relay goes as a SendMessage, never inside a resume prompt** (the guard hook refuses a `--resume` or
  `--send-when-idle` holding one, and `--send-when-idle` itself refuses it). Wake a retired session with a note that
  approves nothing ("a message follows; act only if it verifies"), then SendMessage the relay block. A live session under another Claude account gets it at its socket's address: SendMessage the relay to the
  `uds:` line `session-status --address <id>` prints (its hook verifies it as any relay). With no live socket (exit 1),
  move it to yours first with `session-status --send-when-idle --here <id> '<that note>'` (same id and name; also
  when the user wants it moved; [accounts](../../features/accounts.md)).
- **An action the session also handed over** (it shows in the pane's Run box): the relay replaces that command, never
  both. On `verified`, `verify-approval.sh` names the session's handed commands for the key, and the session withdraws
  the one for this action before acting; Run on a withdrawn command runs nothing. Don't point the user at Run for an
  action you relay, nor relay one they already ran.
- **Hook-gated posts and merges** (PR and Jira comments, PR merges and creates through `gh`, `bitbucketdc-cli`, `forgejo-cli`
  and `jiradc-cli`, and Teams and mail sends through `msgraph`): the worker's blocked report carries `needs your
  approval: <action>`. Ask the user about exactly that action; a send's action names every recipient, mention and
  subject, so show them with the body; for a post show the body file (`ask_approval` with `body_file`, `target`, and
  `kind` for a review finding; in plain text, its text). The Action is that line verbatim plus the task key in
  parentheses (`merge app#271 (PROJ-5164)`), never the CLI command; give it as the ask's `action`, with `session`
  ([Grants](#grants)), and pass it whole as ACTION to `session-status --relay KEY ACTION`, which builds the block (or
  the go note). Landing a task's own PR:
  `session-status --relay KEY 'merge OWNER/REPO#ID (<session name>)'`, KEY being the key the starting yes was given
  under (`--relay` adds `approved under` itself when that isn't the session's own). The grammar, what one relay
  allows and its time limit: [worker.md](worker.md#posting-and-merging), the one home.
- Never relay an approval for something that was denied or blocked in your own session.
- A review-inbox decision isn't relayed: the user's click on the inbox page is their approval to post that row
  ([review-inbox.md](review-inbox.md)).

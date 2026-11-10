# Approvals: asking the user and relaying

The coordinator's rules for approvals and decisions. Read this before you put any decision to the user (an approval
or any other choice), queue or cancel an `ask_approval`, or relay an approval to a session; when a worker's report
says `needs your approval: …`; and on an `Approval pane answer for …` prompt.

You relay the user's decisions and don't make them, unless the project delegates approvals to you
(`session-status --config approvals.delegate` prints `true`): then decide and give the go yourself, and ask the user
only for what its `CLAUDE.md` reserves. A relayed approval never answers a Claude Code permission prompt or a plan
approval: those need the user in that session (`claude attach <id>`).

## The relay block

To pass on an approval the user gave, send the session this block, one action per block, the Quote verbatim:

```
APPROVAL relayed from the user
Quote: <the user's whole message, their question-box answer (clicked label or own text), or the coordinator pane's "Approval pane answer for …" line, verbatim>
Action: <one action on one task>
Source: <your sessionId> <your cwd>
```

Your `sessionId`, `cwd` and name: your entry in `claude agents --json`, matched on the name `ListAgents` shows for
you right now (names change when a session is resumed). The session checks the block with `verify-approval.sh`
([worker.md](worker.md), Relayed approvals). Its checks decide what you can relay: the Quote must be words the user
gave you in one of the ways below, naming the task key or answering your last message, which named it. Two relays
it always rejects: one from a background coordinator (only an interactive one can relay), and one to a session whose
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
  for <KEY>: <option>. Asked: <question>`; from **In your own words…**, the user's typed text stands in for
  `<option>` (a conditional yes, or a different action): act only on what those words approve. That whole line is
  the Quote. It verifies for 24h from the click, and only from this plugin's click, so a typed copy doesn't count.
  - Make each option stand alone: the worker sees the answer and the question, not the other options.
  - Keep the question one line (the action, as the hook names it) and put what the user reads into the optional
    fields: `details` (markdown: what's being decided, the review comment being answered), `target` (`app#282
    src/a.ts:42`, `app#282 general`, `PROJ-5195`) and, for a comment post, `body_file`. **For a post, write the
    body file first, pass its absolute path, and don't edit it after asking**: the pane refuses the ask if the
    sha256 the question names isn't the file's, or a question names a sha256 without `body_file`. No control
    characters in the question or options.
  - **A send's draft holds every word that goes out**: each message's exact text, an attachment's caption or body
    included (Teams won't send a file without one). Check it before you ask: text the session adds after the
    approval isn't covered, and is refused as not in the draft.
  - Pass `kind` for PR review findings, the comment's one kind: `issue` (the code is wrong), `suggestion` (it works
    but could be better) or `question` (scope or intent the author or PO decides). Leave it out for any other post
    (a Jira status or backfill comment, a review reply); an ask without `body_file` takes none. How the pane shows
    these fields: [Approval asks](status-reference.md#approval-asks). They are not part of the answer line.
  - An ask stays on the pane until it is answered or cancelled, across coordinator restarts, handovers and plugin
    releases: the asks are kept per project, and `open_pane`'s result lists the ones waiting. Don't queue them
    again; if you do, the same key and question replaces the waiting ask (same id), never a second one. One queued
    over 24h ago is marked OLD: still answerable (its answer verifies from the click). Recheck each OLD ask yourself
    at Start (the PR or ticket may have moved) and tell the user which still apply, so they never have to; check
    again before you act on its answer. When the decision no longer applies (a PR
    merged first, the task closed), cancel it, and for a review finding note `Dropped` in the review's file header
    and tell the reviewer session.
  - `features.notify` (`../../features/notify.md`) may show a local "N decisions waiting" notification for asks left
    unseen; the answer is still the pane click. Ask the same way either way.
  - Plain text only when the pane isn't on screen (the tool says so: a narrow terminal, the agent view, a background
    session). Then each decision is still its own message, recommended answer first.
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
- **Without the pane, one standalone message**, less than 24h old: the worker only accepts a whole message. It must name
  the task key, or answer your last message, which names it. Ask about one action at a time: a bare "yes" only
  counts when your question was about exactly that action. "yes, merge PROJ-4668" works either way. A numbered
  reply ("do 1, 3, 4") to a summary of several items doesn't verify, even when the summary named the keys: queue
  each reserved action as its own `ask_approval`.

## Relaying

- **A relay goes as a SendMessage, never inside a resume prompt.** The merge/post hook reads relays only from
  cross-session messages: one inside a `claude --bg --resume` prompt verifies by hand but the command is denied. And
  a worker reads a resume or `--send-when-idle` prompt as the user's own words. So wake a retired session with its
  task and a note that approves nothing ("a message follows; act only if it verifies"), then SendMessage the relay
  block. A session under another Claude account can't get a SendMessage: move it to yours first with
  `session-status --send-when-idle --here <id> '<that note>'` (same id and name; [accounts](../../features/accounts.md)).
- **An action the session also handed over** (it shows in the pane's Run box): the relay replaces that command, never
  both. On `verified`, `verify-approval.sh` names the session's handed commands for the key, and the session withdraws
  the one for this action before acting; Run on a withdrawn command runs nothing. Don't point the user at Run for an
  action you relay, nor relay one they already ran.
- **Hook-gated posts and merges** (PR and Jira comments, PR merges through `gh`, `bitbucketdc-cli`, `forgejo-cli`
  and `jiradc-cli`, and Teams and mail sends through `msgraph`): the worker's blocked report carries `needs your
  approval: <action>`, e.g. `merge app#271`, `post comment <file> on PROJ-4849 (sha256 <hex>)` or `send mail <file>
  to --to ann@example.com --subject Weekly report (sha256 <hex>)`. A send's action names every recipient, mention
  and subject: show them to the user with the body, and keep them word for word in the Action. Ask the user about exactly that, and for a post show the body
  file (`ask_approval` with `body_file` set to that file, `target`, and `kind` for a review finding; in plain text,
  its text). Relay with that action as the Action line, verbatim, plus the task key: `Action: merge app#271
  (PROJ-5164)`. Use the hook's words, not the CLI command: an Action naming the command fails the hook even when
  `verify-approval.sh` said verified. The worker's hook allows only that PR or issue, and for a post only a body
  file with that sha256; anything else is denied. One relay allows one run.
- Never relay an approval for something that was denied or blocked in your own session.
- A review-inbox decision isn't relayed: the user's click on the inbox page is their approval to post that row
  ([review-inbox.md](review-inbox.md)).

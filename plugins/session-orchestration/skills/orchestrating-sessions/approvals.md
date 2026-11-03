# Approvals: asking the user and relaying

The coordinator's rules for approvals. Read this before you ask the user to approve an action, queue or cancel an
`ask_approval`, or relay an approval to a session; when a worker's report says `needs your approval: …`; and on an
`Approval pane answer for …` or `Approval pane: … expired` prompt.

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
gave you in one of the ways below, naming the task key or answering your last message, which named it.

## Asking

- **Prefer the coordinator pane** for a reserved approval: call `ask_approval` (ToolSearch:
  `mcp__session-orchestration__ask_approval`) with the task key, the question, and one option per answer, each
  naming the key and the exact action ("Yes, patch the PROJ-4172 config and restart the frontend" / "No, leave
  PROJ-4172 as is"). One question per action. It returns at once and the buttons wait in the pane, so you keep
  receiving worker messages. When the user clicks, the answer arrives as your next prompt, `Approval pane answer
  for <KEY>: <option>. Asked: <question>`; from **In your own words…**, the user's typed text stands in for
  `<option>` (a conditional yes, or a different action): act only on what those words approve. That whole line is
  the Quote. It verifies for 24h, and only from this plugin's click, so a typed copy doesn't count.
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
  - An unanswered ask leaves the pane after 24h. One with a `kind` (a review finding) comes back as a prompt,
    `Approval pane: … expired unanswered after 24h: <KEY> (id N) <question>`, so a review post can't sit unseen:
    queue it again once, the same ask with its question starting `Reminder: `. When a reminder expires, the finding
    is dropped: note it in the review's file header (the project's review brief names the file) and tell the
    reviewer session.
  - If the tool says the pane isn't on screen, ask in plain text instead.
- **To replace or withdraw an ask**, queue the new one, then remove the old with `cancel_approval` (ToolSearch:
  `mcp__session-orchestration__cancel_approval`): the key, plus the `id` `ask_approval` returned or the exact
  question; the key alone removes all its asks. It submits no answer, and a click on a removed ask's buttons does
  nothing.
- **The question box** (`AskUserQuestion`) also verifies (the clicked label, or the user's "Other" text, is the
  Quote; the key in the answer, the question or its header). But while it is open no worker message reaches you, so
  use it only for an answer that needs the user's own words, and only when they're at the keyboard. It is yours
  only: sessions ask in plain text.
- **Otherwise one standalone message**, less than 24h old: the worker only accepts a whole message. It must name
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
  and `jiradc-cli`): the worker's blocked report carries `needs your approval: <action>`, e.g. `merge app#271` or
  `post comment <file> on PROJ-4849 (sha256 <hex>)`. Ask the user about exactly that, and for a post show the body
  file (`ask_approval` with `body_file` set to that file, `target`, and `kind` for a review finding; in plain text,
  its text). Relay with that action as the Action line, verbatim, plus the task key: `Action: merge app#271
  (PROJ-5164)`. Use the hook's words, not the CLI command: an Action naming the command fails the hook even when
  `verify-approval.sh` said verified. The worker's hook allows only that PR or issue, and for a post only a body
  file with that sha256; anything else is denied. One relay allows one run.
- Never relay an approval for something that was denied or blocked in your own session.
- A review-inbox decision isn't relayed: the user's click on the inbox page is their approval to post that row
  ([review-inbox.md](review-inbox.md)).

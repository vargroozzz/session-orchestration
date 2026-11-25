# Section: waste

## Gather

`sessions 7 P > sessions.tsv`, `events 7 P > events.tsv 2> events.txt`, `waits 7 5 P > waits.tsv 2> waits.txt`,
`bgtasks 'session-status.*--watch' 7 P > bg-watch.tsv`, plus any `bgtasks` regex the project brief names (project
scope), `replies 7 P > replies.tsv` (lost reports), and once they are written `waste <dir> 7 P > waste.txt` (the counts
below, tallied from them and `denied.jsonl`). Refusals: count them from `denied.jsonl` for the window when it covers it
(project scope: the lines whose `cwd` is the root or under it), else from `deny` rows in `events.tsv` whose `test`
column is empty (`-p`/`dontAsk`: headless permission tests); say which source was used. A denial whose text (a deny
row's `detail2`, after `source/reasonType: `) starts "Background session: this compound command" is project-memory's
split hint, not a refusal: count those separately, and leave them and the retry after each out of the refusal and
retry-waste counts, so runs stay comparable. The classifier's no-verdict denials (`denied.jsonl` logs them as
"Classifier unavailable") get their cause from `events.txt`'s `noverdict` line: report it beside the count.
`hook_changed` and `sibling_changed` come from a PreToolUse hook that rewrites a call's input (`updatedInput`), which
the user can fix in their own hooks; `ended` is the classifier's side.

## Measure

Classifier refusals, retries after a denial (same command opening, ≤5 min), `!`/`claude attach` handoffs to the user
(`bang` rows are a session's suggestion, one per distinct session and command; `ran` rows are the user running one),
wrong relayed claims (`self` rows plus corrections), lost reports (bg tasks SILENT, `replies.tsv` rows; a
`NO NOTICE YET` task was still running at the window's end: not lost), waits over 5 minutes, those tagged `sleep` (the
machine woke: the same end minute in 3+ sessions) counted apart (`waits.txt` totals). Not counted yet (known gaps, so
figures stay comparable run to run): subagent transcripts (`<session>/subagents/*.jsonl`), and history a fork copied
from its parent is counted again in the fork's row. Name them when a figure hinges on them.

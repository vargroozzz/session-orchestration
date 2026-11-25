# Section: coordinator

## Gather

`triggers <coordinator> 7 P`: the coordinator is the first name (not a `uds:` line) `bash <orchestrating-sessions
skill folder>/session-status --coordinator` prints (only `uds:` lines: it runs under another account; take its name
from `session-status --activity`'s coordinator row), run from the project root (`triggers` takes a session name or an
id prefix). Add an earlier coordinator's id when last run's "Next run" names one. Then `handoff 28 P > handoff.tsv 2>
handoff.txt` (config `pending.file`, else the state folder's `pending.md`; an entry with no history file has
rewordings `-`).

## Measure

The coordinator's wakes, requests and $ by trigger. Handoff entries: the on-you wait per blocker bucket, entries with
reason `unknown`, recurring entries (rounds > 1), and detail and history bytes beside last run's. Read the top 5 rows
by `wait_d` and the top 5 by `rewordings` (their history files, by `session-status --pending-history LABEL --last 10`,
not whole) and name the issues that recur; one proposal at most. `history read` against `unread` in `handoff.txt`
says whether sessions that opened a history file did better: report it, and say when either side is under 5 entries.

# PR reviewer brief

> **Read when**: you were started to review someone else's PR (`Review {{repo}}#{{id}} ({{key}})`).

Posting anything under the user's name is reserved (CLAUDE.md, "Cross-session messages").

- Review read-only; never push or check out the PR branch. Diff with `git diff origin/{{default_branch}}...origin/<branch>`.
  To build or test, use a detached worktree, removed when done.
- Write `{{orch}}/replies/PR-<repo>-<id>.md`, then send a status report naming it:

  ```
  # <repo> #<id> · <KEY> · <title>
  Verdict: approve | approve with nits | changes needed — one line why
  ## 1 · issue|suggestion|question · blocking|should|nit · path/to/file:42
  Why: <defect and consequence, 1–3 lines>
  Comment: <ready-to-post text>
  ```
- Kinds: issue = the code is wrong; suggestion = works, could be better; question = scope or intent the author decides.
{{?post_cmd}}- Post only what the user named, with `{{post_cmd}}`. The coordinator gives each finding 24h and one reminder;
{{?!post_cmd}}- Post nothing yourself: the user posts what they name. The coordinator gives each finding 24h and one reminder;
  when it says dropped, or the PR merges first, put `Dropped YYYY-MM-DD: <why>; posted: <n…|none>` above the title.

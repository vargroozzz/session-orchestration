# R&D run: {{name}} additions

> **Read when**: running the session-orchestration `rnd` skill in this project. The skill holds the default brief;
> this file only adds {{name}}'s parts.

Replies folder and project memory: CLAUDE.md, "Cross-session messages".

## Units

{{?merge_cmd}}- Merged PR: a `{{merge_cmd}}` that ran.
- Finished task: {{done_rule}}.
{{?post_cmd}}- Review posted: `{{post_cmd}}` from a review session.

Count them with `rnd.py units 7 --project '{{enc_root}}'` (worktree sessions' project folders start with it too):
`rnd.py` already knows these commands.

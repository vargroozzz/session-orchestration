# Project memory

What one task learned that another needs: decisions, pitfalls, conventions. Read this index when you start a task,
then the topic file whose trigger matches your work, whole. Append one line to that file's end
(`- YYYY-MM-DD KEY: …`, the rule first, then the incident); none fits: `misc.md`. Never add entries here. Sessions
only append; deleting, merging and moving entries is the prune's and the graduate pass's (project-memory's
`graduate` skill; with session-orchestration, its coordinator prunes too).

| Topic file (`memory/`) | Read when |
|------------------------|-----------|
{{topic_rows}}

## Graduation

An entry moves into the doc that owns its situation when it is 7+ days old and still true, or 3+ sessions cited it:
`grep -l '"role":"assistant".*<phrase>' ~/.claude/projects/{{enc_root}}*/*.jsonl | wc -l`. Drop it when it's wrong,
superseded, about a resolved task state, or already in a doc. A topic past ~15 entries becomes its own doc.

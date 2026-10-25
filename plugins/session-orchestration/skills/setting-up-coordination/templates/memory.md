# Project memory

What one task learned that another needs: decisions, pitfalls, conventions. Read this index when you start a task,
then the topic file whose trigger matches your work, whole. Append one line to that file's end
(`- YYYY-MM-DD KEY: …`, the rule first, then the incident); none fits: `misc.md`. Never add entries here. Only the
coordinator deletes, merges or moves entries (session-orchestration `coordinator.md`, "Project memory").

| Topic file (`memory/`) | Read when |
|------------------------|-----------|
| `coordinator.md` | Acting as the coordinator, or messaging, resuming or handing work to another session |
| `misc.md` | Nothing above fits |

## Graduation

An entry moves into the doc that owns its situation when it is 7+ days old and still true, or 3+ sessions cited it:
`grep -l '"role":"assistant".*<phrase>' ~/.claude/projects/{{enc_root}}*/*.jsonl | wc -l`. Drop it when it's wrong,
superseded, about a resolved task state, or already in a doc. A topic past ~15 entries becomes its own doc.

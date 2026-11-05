# project-memory

What one Claude Code session learns, the next one knows. Works in any project, with or without a coordinator
([session-orchestration](../session-orchestration/README.md) depends on it and uses it for all of this).

- **Project memory** (`project-memory` skill): an index (`memory.md`) over topic files, each with a "read when"
  trigger. Sessions read the index when they start a task, read only the topics that match, and append one line per
  decision or pitfall another task would need. `memory-init` sets it up.
- **`/graduate`** (`graduate` skill): proposes, item by item, moving proven memory entries into the docs that own
  them, dropping stale ones, turning open project cases into fixes and resolving deferred tasks (ticket it, fix it or
  drop it), then applies what you approve.
- **Project cases** (`cases`): friction the project caused a session (a host's sign-in, a misleading doc, a script
  that fails on a case it should handle), filed the moment it happens, deduplicated and counted, kept outside the
  repo in `~/.local/state` until a fix lands.
- **Deferred tasks** (`defer-task` skill): an out-of-scope bug, feature or refactor noticed mid-task goes to
  `.claude/tasks/<bugfixes|features|refactorings>/` instead of derailing the task.
- **Background-session guards** (hooks): in every `--bg` session, in every project, the question box, plan mode, an
  `EnterWorktree` outside the session's own `.claude/worktrees/`, and a compound Bash command about to raise a
  permission prompt are denied with what to do instead ([hooks/background-sessions.md](hooks/background-sessions.md)).
  Each would otherwise wait on a dialog nobody sees. Interactive sessions are never affected
  (`CLAUDE_CODE_SESSION_ATTENDED` is 1 there).

## Install

```
claude plugin marketplace add vargroozzz/session-orchestration
claude plugin install project-memory@session-orchestration
```

Then ask a session to "set up project memory": it proposes a folder and topics, writes them on your yes, and adds the
`Project memory:` line to your `CLAUDE.md`.

## Requirements

bash, git, jq; macOS or Linux.

## License

MIT

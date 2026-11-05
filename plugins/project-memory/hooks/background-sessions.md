# Background sessions: asking and handing over

A `--bg` session has nobody watching its dialogs. A question box, a plan approval or a permission prompt waits until
someone attaches, and while it waits no cross-session message (an answer, a relayed approval) reaches the session.
The hooks beside this file deny those dialogs in background sessions (`CLAUDE_CODE_SESSION_ATTENDED=0`) and say
what to do instead. Interactive sessions are never affected.

## Asking the user

Ask in plain text, never with the question box or plan mode. Name the task and the exact action ("force-push
PROJ-4668?"), one action per ask. List other blocking decisions one per line, each with its options and your
recommended one first. Decide what doesn't block you yourself. Then end your turn: the answer arrives as a prompt or
a message. A plan that needs sign-off goes in a file, with no other changes made, and you ask with its path.

With session-orchestration, a task session also sends the same ask to its coordinator as a `blocked` status report
(its worker.md, Asking the user).

## Running commands

A compound command (a pipe, `;`, `&&`, `||`, `$(…)`, backticks, several lines) is not covered by allow rules, which
match plain commands only, so in a background session it waits on a prompt nobody sees. Run each part as its own
plain command, one per call. A command that can't be split (a script on stdin) or still needs the user is handed
over.

## Handing the user a command

Give it as one line, `! <command>`, with absolute paths and one line on what it does, in your report, and don't
wait on it. With session-orchestration, also call its `hand_command` tool (ToolSearch:
`mcp__session-orchestration__hand_command`) with your task key, so the command shows in the coordinator pane with
a Run button (its worker.md, Handing the user a command).

## Worktrees

`EnterWorktree` with a name, or a path under the start folder's `.claude/worktrees/`, raises no prompt. Any other
path does, so create the worktree with `git worktree add` (or the project's own script) and work in it by absolute
path.

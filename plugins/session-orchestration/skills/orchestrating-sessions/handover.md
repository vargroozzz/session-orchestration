# Handing over the coordinator

The coordinator's rules for replacing itself. Read this at the context-watch hook's mark, at a `Weekly limit:` line,
before a restart, and as a successor (your first prompt says `You succeed "NAME"`). The status command here is
`session-status`; each step prints the next. Flags in detail: [status-reference.md](status-reference.md#commands-in-detail).

## The old coordinator

Overwrite `<replies>/coordinator-handover.md` with the state that's in no file: live sessions worth knowing and what
each waits on, why the restart (pane asks carry over by themselves). No rules and no files to read: the next
coordinator's Start reads those, and each restated rule is re-sent on its every wake. Then start your successor:

1. `session-status --successor` (`--account DIR` for the weekly-limit move): it opens a tab running an interactive
   `claude -n NAME-next 'Act as a coordinator. You succeed …'`. Nothing opened: hand the user the command it prints
   (`hand_command`, key `coordinator`). Then arm `--await ready` (Bash, background) and end your turn. From here act
   on no message: forward each, text on stdin, with `session-status --inbox-add --from '<name> (<id8>)'`.
2. When `--await ready` wakes you, call `name_session` with what `session-status --prev-name --title` prints
   (`NAME-prev-K`; it titles your tab too), arm `--await renamed` (background) and end your turn: the rename lands
   then.
3. When `--await renamed` wakes you, stop your watcher (TaskStop), forward what came meanwhile, run
   `session-status --successor --done` and end. Your terminal closes once you are idle.

## The successor

Your name is `NAME-next`. Run Start as usual (`open_pane` keeps your name while the old one holds `NAME`), then:

1. Arm `--await name`. It wakes you when `NAME` is free: call `name_session` with `NAME`.
2. Arm `--await done`. It closes the old coordinator's tab (only its split, when the tab has others) once that one is
   idle and done forwarding. Tell the user what was left open, if anything.

- Any `--await` also wakes you on an unread coordinator inbox entry: act on each, mark it read (`session-status
  --inbox --read N`), and arm the same `--await` again.
- A live session other than the one you succeed holds `NAME` (`open_pane` says so): stop and ask the user.
- An `--await` that times out: check the other coordinator (`--activity`), then re-arm or finish by hand.

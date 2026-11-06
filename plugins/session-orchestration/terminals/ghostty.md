# Terminal: ghostty

> **Start**: nothing to do.
> **Read when**: you hand the user a running view (`session-status --open`), or Attach in tab or Logs in split fails.

On when `terminal` is `ghostty` in `.claude/coordination.local.json` (a person key). Setup proposes it when it runs
inside Ghostty (`TERM_PROGRAM=ghostty`); `session-status --init --check` names it while it is unset there. macOS only:
it drives Ghostty through AppleScript (`osascript`).

**What it changes.** A session card's **Attach in tab** (`t`) opens `claude attach` in a Ghostty tab titled
`<name> attach`, under the session's account (`CLAUDE_CONFIG_DIR`) and in its folder (`$HOME` when the folder is
gone); a tab with that title is reused rather than opened twice. **Logs in split** (`l`) opens `claude logs` in a
split to the right of the front window. Neither shows on an interactive session. Both go through
`session-status --open view|split …`, which a session can run itself to hand the user a running view.

**Coordinator handover.** `session-status --successor` opens the successor coordinator in a new tab titled
`<name>-next`. The old coordinator's tab is retitled `<name>-prev-K` when it renames itself (a fixed title: what the
program sets no longer shows), and the successor closes it once the old one is idle: the whole tab when it holds that
terminal alone, else only that split, with no confirmation. A tab it can't find (the old one ran in another terminal
app) is left, and the successor says so.

**Quirks.**
- Ghostty not running: nothing opens, the pane copies the command and says so.
- A reused tab whose attach has exited shows a shell: close it and press again.
- An AppleScript error (Ghostty's automation permission refused, say) shows as a toast with the error; grant the
  coordinator's terminal Automation access to Ghostty in System Settings → Privacy & Security.

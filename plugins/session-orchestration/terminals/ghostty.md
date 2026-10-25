# Terminal: ghostty

On when `terminal` is `ghostty` in `.claude/coordination.local.json` (a person key). Setup proposes it when it runs
inside Ghostty (`TERM_PROGRAM=ghostty`); `session-status --init --check` names it while it is unset there. macOS only:
it drives Ghostty through AppleScript (`osascript`).

**What it changes.** A session card's **Attach in tab** (`t`) opens `claude attach` in a Ghostty tab titled
`<name> attach`, under the session's account (`CLAUDE_CONFIG_DIR`) and in its folder (`$HOME` when the folder is
gone); a tab with that title is reused rather than opened twice. **Logs in split** (`l`) opens `claude logs` in a
split to the right of the front window. Neither shows on an interactive session. Both go through
`session-status --open view|split …`, which a session can run itself to hand the user a running view.

**Quirks.**
- Ghostty not running: nothing opens, the pane copies the command and says so.
- A reused tab whose attach has exited shows a shell: close it and press again.
- An AppleScript error (Ghostty's automation permission refused, say) shows as a toast with the error; grant the
  coordinator's terminal Automation access to Ghostty in System Settings → Privacy & Security.

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

**Coordinator handover.** `session-status --successor` opens the successor coordinator in a split right of the old
coordinator's own terminal, in its tab (found by its tty; in the background, the tab it was moved out of), so no tab
opens. That tab not found (the old one runs in another terminal app, or has no terminal): a new tab titled
`<name>-next` instead. Either way the user's screen stays put: Ghostty brings itself to the front on any new split or
tab, so the frontmost app and Ghostty's selected tab are recorded first and given back once it is open (`open -a`, so
no Automation prompt for that app); a split gives the keyboard back to the old pane. The tab is retitled `<name>-prev-K` when the old one renames itself (a fixed
title: what the program sets no longer shows), then `<name>` when the successor takes the name, and the successor
closes the old one once it is idle: only its split, so the successor fills the tab (the whole tab when the old one is
alone in it, as with a new tab), with no confirmation. A tab it can't find is left, and the successor says so.

**Quirks.**
- Ghostty's AppleScript activates Ghostty on every new tab or window, with no option against it. To keep the user's
  focus, record the frontmost app and tab and give them back with `open -a` (an Apple Event to their app asks for
  Automation consent); `TERMINAL_QUIET=1` in ghostty.sh does this.
- Ghostty not running: nothing opens, the pane copies the command and says so.
- A reused tab whose attach has exited shows a shell: close it and press again.
- An AppleScript error (Ghostty's automation permission refused, say) shows as a toast with the error; grant the
  coordinator's terminal Automation access to Ghostty in System Settings → Privacy & Security.

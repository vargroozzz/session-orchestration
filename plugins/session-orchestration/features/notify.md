# Feature: ask notification

> **Start**: nothing to do: the pane notifies by itself.
> **Read when**: the user asks about the "decision waiting" notification, or wants it on, off or at another delay.

Off by default. On when `features.notify` is a number of minutes above 0, in the person's
`.claude/coordination.local.json` or the person-wide `~/.config/session-orchestration/config.json` (a person key: the
repo file can't set it). For example `{"features": {"notify": 10}}`. `0` turns it off, and so does a key left unset. A change takes effect the next time the coordinator calls
`open_pane` (or after a plugin reload).

**What it does.** The coordinator's pane checks its queued asks each minute. Once an ask has waited that many minutes
and the user hasn't pressed it open on the pane, the pane shows one macOS notification (`osascript`, Notification
Center), titled "Coordinator", saying "1 decision waiting" (or "N decisions waiting"). Each ask notifies once. When
another ask passes the limit, it notifies again, counting every unseen ask past the limit. A plugin reload or a second coordinator
can notify the same ask once more.

**What it never does.**
- It shows no project, task key, ticket, PR, person or question text: only the count.
- It sends nothing off the machine. There's no phone push, ntfy or any other relay, because a queued ask's content
  must not leave the machine.
- It doesn't answer anything. Approvals stay a press on the pane: the click is the Quote that verifies
  (the orchestrating-sessions skill's `approvals.md`). The notification only brings the user to the pane.

It works only while a coordinator has its pane open (the pane's 1-minute check runs it), and only on macOS.
Elsewhere, or when `osascript` fails (notifications turned off for the terminal app, say), nothing is shown and
nothing else changes.

You (the coordinator) never call it and never mention it in asks. It needs nothing from you beyond queuing asks
with `ask_approval` as usual.

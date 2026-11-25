# Terminal plain, the default (lib.sh's load_terminal sources it before any other): opens nothing. Each function
# prints the command and returns 2, so the pane copies it for the user to paste. The contract every terminal module
# keeps is in skills/orchestrating-sessions/status-reference.md (Terminals).
open_view() { [ "${1:-}" != --account ] || shift 2; shift 2; echo "$*"; return 2; }
open_split() { [ "${1:-}" != --account ] || shift 2; shift; echo "$*"; return 2; }
# The old coordinator's terminal at a handover (session-status --successor, --prev-name --title, --await name or done),
# found by its tty (ttys005): split_tty [--account DIR] TTY DIR CMD… opens the successor in a split of its tab,
# title_tty TTY TITLE titles that tab, close_tty TTY closes it. Plain does none: 2.
split_tty() { return 2; }
title_tty() { return 2; }
close_tty() { return 2; }

# Terminal plain, the default (lib.sh's load_terminal sources it before any other): opens nothing. Each function
# prints the command and returns 2, so the pane copies it for the user to paste. The contract every terminal module
# keeps is in skills/orchestrating-sessions/status-reference.md (Terminals).
open_view() { [ "${1:-}" != --account ] || shift 2; shift 2; echo "$*"; return 2; }
open_split() { [ "${1:-}" != --account ] || shift 2; shift; echo "$*"; return 2; }

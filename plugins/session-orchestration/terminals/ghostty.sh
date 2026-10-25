# Terminal ghostty (macOS): a tab or a split in Ghostty through its AppleScript (terminals/ghostty.md).
#   open_view [--account DIR] TITLE DIR CMD…   a tab titled TITLE (its open tab selected instead, if one has that
#                                              title), starting in DIR, CMD typed into its shell
#   open_split [--account DIR] DIR CMD…        a split right of the front window's focused pane
# --account: the pane's CLAUDE_CONFIG_DIR, so the shell left when CMD exits stays in that account (~/.claude: unset,
# as claude then reads ~/.claude.json). A DIR that's gone (a removed worktree) opens in $HOME.
# Prints: [reused ]window <id> tab <id> terminal <id>. Returns 0 opened, 2 Ghostty not running (the pane copies CMD),
# 3 AppleScript error (message on stderr).
open_view() { _ghostty tab 1 "$@"; }
open_split() { _ghostty right 0 "$@"; }

_ghostty() {
  local mode=$1 reuse=$2 account= title= dir out; shift 2
  [ "${1:-}" != --account ] || { account=${2/#\~/$HOME}; shift 2; }
  [ "$mode" = right ] || { title=$1; shift; }
  dir=$([ -n "$1" ] && cd "${1/#\~/$HOME}" 2>/dev/null && pwd) || dir=$HOME; shift
  [ "${account%/}" != "$HOME/.claude" ] || account=
  # ps, not pgrep: pgrep missed the running Ghostty from a background session (2026-10-19)
  command -v osascript >/dev/null || { echo "no osascript: the ghostty terminal is macOS only" >&2; return 2; }
  ps -axo ucomm= | grep -q '^ghostty *$' || { echo "Ghostty is not running" >&2; return 2; }
  out=$(osascript -e "$_ghostty_script" "$mode" "$dir" "$title" "$account" "$reuse" "$*" 2>&1) ||
    { echo "AppleScript error: $(head -1 <<<"$out")" >&2; return 3; }
  echo "$out"
}

read -r -d '' _ghostty_script <<'APPLESCRIPT' || true
on run argv
	set {mode, dir, title, account, reuse, cmd} to argv
	tell application "Ghostty"
		if reuse is "1" and title is not "" then
			repeat with w in windows
				repeat with t in tabs of w
					if (name of t) is title then
						select tab t
						activate window w
						return "reused window " & (id of w) & " tab " & (id of t) & " terminal " & (id of focused terminal of t)
					end if
				end repeat
			end repeat
		end if
		set cfg to new surface configuration
		set initial working directory of cfg to dir
		if account is not "" then set environment variables of cfg to {"CLAUDE_CONFIG_DIR=" & account}
		if cmd is not "" then set initial input of cfg to cmd & linefeed
		-- delays: a `new tab` sent straight after `new window` while a Ghostty window was in full screen hit an AppKit
		-- NSInternalInconsistencyException and Ghostty quit (2026-10-18).
		-- ponytail: fixed delays, not a readiness check; Ghostty's dictionary has no full-screen or ready state
		if (count of windows) is 0 then
			set w to new window with configuration cfg
			delay 1
			set t to selected tab of w
		else
			set w to front window
			if mode is "tab" then
				set t to new tab in w with configuration cfg
				delay 0.5
			else
				set t to selected tab of w
				split (focused terminal of t) direction right with configuration cfg
				delay 0.3
			end if
		end if
		set term to focused terminal of t
		if title is not "" then perform action ("set_tab_title:" & title) on term
		return "window " & (id of w) & " tab " & (id of t) & " terminal " & (id of term)
	end tell
end run
APPLESCRIPT

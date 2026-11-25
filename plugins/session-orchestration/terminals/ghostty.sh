# Terminal ghostty (macOS): a tab or a split in Ghostty through its AppleScript (terminals/ghostty.md).
#   open_view [--account DIR] TITLE DIR CMD…   a tab titled TITLE (its open tab selected instead, if one has that
#                                              title), starting in DIR, CMD typed into its shell
#   open_split [--account DIR] DIR CMD…        a split right of the front window's focused pane
#   split_tty [--account DIR] TTY DIR CMD…     a split right of the terminal on TTY (ttys005), in its own tab; 1 when no
#                                              Ghostty terminal is on TTY (a coordinator's handover)
# --account: the pane's CLAUDE_CONFIG_DIR, so the shell left when CMD exits stays in that account (~/.claude: unset,
# as claude then reads ~/.claude.json). A DIR that's gone (a removed worktree) opens in $HOME.
# Prints: [reused ]window <id> tab <id> terminal <id>. Returns 0 opened, 2 Ghostty not running (the pane copies CMD),
# 3 AppleScript error (message on stderr). TERMINAL_QUIET=1 (a shell variable, not exported, so the opened shell
# never inherits it): the user keeps their frontmost app and Ghostty's selected tab (a coordinator's handover).
# grep without -q: -q stops at the match, ps then dies of SIGPIPE, and under the caller's pipefail (session-status)
# the check failed 14 times in 20 (2026-11-06)
_ghostty_running() { ps -axo ucomm= | grep '^ghostty *$' >/dev/null; }
open_view() { _ghostty tab 1 "$@"; }
open_split() { _ghostty right 0 "$@"; }
split_tty() { _ghostty tty 0 "$@"; }

_ghostty() {
  local mode=$1 reuse=$2 account= title= dir out; shift 2
  [ "${1:-}" != --account ] || { account=${2/#\~/$HOME}; shift 2; }
  # tty mode: the TTY rides in title's slot (the AppleScript swaps it out), /dev/ dropped as ps prints it
  [ "$mode" = right ] || { title=${1#/dev/}; shift; }
  dir=$([ -n "${1:-}" ] && cd "${1/#\~/$HOME}" 2>/dev/null && pwd) || dir=$HOME; shift || true
  [ "${account%/}" != "$HOME/.claude" ] || account=
  # ps, not pgrep: pgrep missed the running Ghostty from a background session (2026-10-19)
  command -v osascript >/dev/null || { echo "no osascript: the ghostty terminal is macOS only" >&2; return 2; }
  _ghostty_running || { echo "Ghostty is not running" >&2; return 2; }
  out=$(osascript -e "$_ghostty_script" "$mode" "$dir" "$title" "$account" "$reuse" "$*" "${TERMINAL_QUIET:-0}" 2>&1) ||
    { echo "AppleScript error: $(head -1 <<<"$out")" >&2; return 3; }
  [ "$out" != none ] || { echo "no Ghostty terminal on $title" >&2; return 1; }
  echo "$out"
}

read -r -d '' _ghostty_script <<'APPLESCRIPT' || true
on run argv
	set {mode, dir, title, account, reuse, cmd, quiet} to argv
	-- quiet: Ghostty activates itself on every new tab, window or split (its dictionary has no way not to), so record the
	-- frontmost app and Ghostty's front window and selected tab, and give them back once it is open. Both steps
	-- in try: focus is cosmetic, a failure there must not report a started successor as not started.
	set prev to {"", "", ""}
	if quiet is "1" then
		try
			set item 1 of prev to POSIX path of (path to frontmost application)
			tell application "Ghostty" to set prev to {item 1 of prev, id of front window, id of selected tab of front window}
		end try
	end if
	set tname to ""
	if mode is "tty" then set {tname, title} to {title, ""}
	tell application "Ghostty"
		if reuse is "1" and title is not "" then
			repeat with w in windows
				repeat with t in tabs of w
					if (name of t) is title then
						select tab t
						activate window w
						my restore(prev)
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
		if mode is "tty" then
			-- the split goes into the tab holding TTY, wherever it is; none: nothing opened, the caller opens a tab
			repeat with w in windows
				repeat with t in tabs of w
					repeat with x in terminals of t
						set y to tty of x
						if y is tname or y is ("/dev/" & tname) then
							set term to split x direction right with configuration cfg
							delay 0.3
							-- the new split takes the keyboard: give it back to the old pane, the user may be typing there
							try
								focus x
							end try
							my restore(prev)
							return "window " & (id of w) & " tab " & (id of t) & " terminal " & (id of term)
						end if
					end repeat
				end repeat
			end repeat
			return "none"
		end if
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
		my restore(prev)
		return "window " & (id of w) & " tab " & (id of t) & " terminal " & (id of term)
	end tell
end run

on restore(prev)
	set {app_, wid, tid} to prev
	try
		if wid is not "" then
			tell application "Ghostty"
				repeat with w in windows
					if (id of w) is wid then
						repeat with t in tabs of w
							if (id of t) is tid then select tab t
						end repeat
					end if
				end repeat
			end tell
		end if
		-- open -a, not tell … to activate: an Apple Event to the user's app would ask them for Automation consent
		if app_ is not "" then do shell script "open -a " & quoted form of app_
	end try
end restore
APPLESCRIPT

# title_tty TTY TITLE: the tab holding the terminal on TTY (ttys005) gets TITLE as its name override (a title the
# program in it sets doesn't replace it). close_tty TTY: that terminal's tab closed when it is the tab's only
# terminal, else only that split; prints `closed tab` or `closed split`. Both: 0 done, 1 no Ghostty terminal on TTY,
# 2 Ghostty not running, 3 AppleScript error.
title_tty() { _ghostty_tty title "$1" "$2"; }
close_tty() { _ghostty_tty close "$1" ""; }
_ghostty_tty() {
  local out
  command -v osascript >/dev/null || { echo "no osascript: the ghostty terminal is macOS only" >&2; return 2; }
  _ghostty_running || { echo "Ghostty is not running" >&2; return 2; }
  out=$(osascript -e "$_ghostty_tty_script" "$1" "${2#/dev/}" "$3" 2>&1) || { echo "AppleScript error: $(head -1 <<<"$out")" >&2; return 3; }
  [ "$out" != none ] || { echo "no Ghostty terminal on $2" >&2; return 1; }
  echo "$out"
}
read -r -d '' _ghostty_tty_script <<'APPLESCRIPT' || true
on run argv
	set {op, tname, title} to argv
	tell application "Ghostty"
		repeat with w in windows
			repeat with t in tabs of w
				repeat with term in terminals of t
					set y to tty of term
					if y is tname or y is ("/dev/" & tname) then
						if op is "title" then
							set name override of t to title
							return "titled tab " & (id of t)
						end if
						if (count of terminals of t) is 1 then
							close tab t
							return "closed tab"
						end if
						close term
						return "closed split"
					end if
				end repeat
			end repeat
		end repeat
	end tell
	return "none"
end run
APPLESCRIPT

#!/usr/bin/env bash
# Terminal modules through `session-status --open` and lib.sh's module lookup: plain, ghostty (osascript and ps
# stubbed, so nothing opens), and a person's own modules, and committed ones trusted by hash. Prints "ok" or the failures.
set -u
P=$(cd "$(dirname "$0")/.." && pwd)
SS=$P/skills/orchestrating-sessions/session-status
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/proj/.claude" "$T/home/.claude-work"
printf '#!/bin/sh\necho "${PS_OUT-ghostty}"\n' > "$T/bin/ps"
printf '#!/bin/sh\nshift 2; printf "%%s|" "$@"\n' > "$T/bin/osascript"   # drops -e SCRIPT, prints the argv
printf '#!/bin/sh\n' > "$T/proj/.claude/session-status-adapter"
chmod +x "$T/bin/"* "$T/proj/.claude/session-status-adapter"
cd "$T/proj" || exit 1
export HOME=$T/home XDG_CONFIG_HOME=$T/xdg PATH=$T/bin:$PATH
fails=0
# check NAME WANT_RC WANT_OUT ARGS…: stdout and stderr together, the exit code after them.
check() {
  local name=$1 rc=$2 want=$3 out got; shift 3
  out=$(bash "$SS" "$@" 2>&1); got=$?
  [ "$got" = "$rc" ] && [[ $out == *"$want"* ]] || { echo "FAIL $name: rc=$got (want $rc) out=$out (want *$want*)"; fails=$((fails + 1)); }
}
cfg() { echo "$1" > .claude/coordination.local.json; }

check "plain by default" 0 plain --config terminal
check "plain copies" 2 "claude attach ab" --open view --account ~/.claude-work 'x attach' /tmp -- claude attach ab
check "plain split copies" 2 "claude logs ab" --open split /tmp -- claude logs ab
cfg '{"terminal":"ghostty"}'
check "ghostty tab, its account" 0 "tab|/tmp|x attach|$HOME/.claude-work|1|claude attach ab|" --open view --account ~/.claude-work 'x attach' /tmp -- claude attach ab
check "ghostty: the default account sets none, a gone folder opens in HOME" 0 "tab|$HOME|t||1|" --open view --account "$HOME/.claude/" t /nonexistent -- claude attach ab
check "ghostty: no folder known opens in HOME" 0 "right|$HOME|" --open split "" -- claude logs ab
check "ghostty split" 0 "right|/tmp|||0|claude logs ab|" --open split /tmp -- claude logs ab
check "ghostty split, its account" 0 "right|/tmp||$HOME/.claude-work|0|" --open split --account "$HOME/.claude-work" /tmp -- claude logs ab
PS_OUT= check "Ghostty not running" 2 "Ghostty is not running" --open split /tmp -- claude logs ab
check "bad mode" 1 usage --open tab /tmp -- x

rm .claude/coordination.local.json; mkdir -p .claude/coordination && echo '{"terminal":"ghostty"}' > .claude/coordination/coordination.json
check "the repo file can't pick it" 0 plain --config terminal
cfg '{"terminal":"wezterm"}'
check "found nowhere: plain" 0 "no terminals/wezterm.sh found" --config terminal
check "found nowhere: plain opens" 2 "a b" --open view T /tmp -- a b
mkdir -p .claude/coordination.local/terminals "$XDG_CONFIG_HOME/session-orchestration/terminals"
echo 'open_view() { echo "wez $*"; }' > .claude/coordination.local/terminals/wezterm.sh
check "project-local module" 0 wezterm --config terminal
check "its open_view" 0 "wez T /tmp a b" --open view T /tmp -- a b
check "no open_split: plain's, warned" 2 "terminals/wezterm.sh: no open_split, using the default" --open split /tmp -- a b
echo 'open_view() { if; }' > .claude/coordination.local/terminals/wezterm.sh
check "syntax error: skipped, file and line named" 2 "wezterm.sh skipped: line 1: syntax error" --open view T /tmp -- a b
rm .claude/coordination.local/terminals/wezterm.sh
echo 'open_view() { echo xdg; }; open_split() { echo xdg; }' > "$XDG_CONFIG_HOME/session-orchestration/terminals/wezterm.sh"
check "person module" 0 xdg --open split /tmp -- a b
echo 'open_view() { echo local; }; open_split() { echo local; }' > .claude/coordination.local/terminals/wezterm.sh
check "project-local wins over the person's" 0 local --open split /tmp -- a b
echo 'open_view() { echo mine; }; open_split() { echo mine; }' > "$XDG_CONFIG_HOME/session-orchestration/terminals/ghostty.sh"
cfg '{"terminal":"ghostty"}'
check "shadowing the plugin's: noted" 0 "note: ghostty: using" --open view T /tmp -- a b
cfg '{"terminal":"../x"}'
check "a name that isn't one: plain" 0 "is not valid" --config terminal

# The committed tier (shared mode): runs only while its sha256 is the one the person file trusts.
rm -rf .claude/coordination.local "$XDG_CONFIG_HOME/session-orchestration"
mkdir -p .claude/coordination/terminals
echo 'open_view() { echo team; }; open_split() { echo team; }' > .claude/coordination/terminals/wezterm.sh
sha=$(shasum -a 256 .claude/coordination/terminals/wezterm.sh | cut -d' ' -f1)
cfg '{"terminal":"wezterm"}'
check "committed, not trusted: skipped, warned" 0 "terminals/wezterm.sh is not trusted yet: run setup to review it" --config terminal
check "committed, not trusted: the next tier opens" 2 "a b" --open split /tmp -- a b
echo "{\"trusted\":{\"terminals/wezterm.sh\":\"$sha\"}}" > .claude/coordination/coordination.json
check "the repo file can't trust it" 2 "not trusted yet" --open split /tmp -- a b
cfg "{\"terminal\":\"wezterm\",\"trusted\":{\"terminals/wezterm.sh\":\"$sha\"}}"
check "committed and trusted: runs" 0 team --open split /tmp -- a b
echo '# changed' >> .claude/coordination/terminals/wezterm.sh
check "changed upstream: skipped" 2 "terminals/wezterm.sh changed upstream: run setup to review it" --open split /tmp -- a b
mkdir -p .claude/coordination.local/terminals && echo 'open_view() { echo local; }; open_split() { echo local; }' > .claude/coordination.local/terminals/wezterm.sh
check "project-local wins over the committed one, unasked" 0 local --open split /tmp -- a b

[ "$fails" = 0 ] && echo ok || { echo "$fails failed"; exit 1; }

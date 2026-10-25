#!/usr/bin/env bash
# The stranger test: someone else's machine (a temp HOME, no config of ours, `claude` stubbed) and a fresh repo.
# Setup with defaults, then the check line, the status command and the config, as a coordinator would run them.
# Nothing the coordinator reads may name us (the deny pattern below; CLAUDE_CONFIG_DIR is core and allowed), and
# outside the repo only ~/.cache/session-status/ and the plugin's state folder (left empty) may be written.
# Prints "ok" or the failures.
set -u
P=$(cd "$(dirname "$0")" && pwd)
SS=$P/skills/orchestrating-sessions/session-status
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/bin" "$T/tmp" "$T/repo"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/claude"; chmod +x "$T/bin/claude"
export HOME=$T/home TMPDIR=$T/tmp PATH=$T/bin:$PATH
unset XDG_CONFIG_HOME XDG_STATE_HOME XDG_CACHE_HOME CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR TERM_PROGRAM GHOSTTY_RESOURCES_DIR
cd "$T/repo" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init || { echo "FAIL git init"; exit 1; }
fails=0
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

out=$T/out; : > "$out"
{ bash "$SS" --init; bash "$SS" --init --write; } >> "$out" 2>&1 || fail "setup: $(tail -3 "$out")"
c=$(bash "$SS" --init --check 2>&1); echo "$c" >> "$out"
[[ $c == configured* ]] || fail "check: $c"
bash "$SS" >> "$out" 2>&1 || fail "status: $(tail -3 "$out")"
bash "$SS" --config terminal >> "$out" 2>&1

# Everything the coordinator reads: the command output, what setup wrote, the skill docs it reads at start, and
# the docs the check line names (`→ read …`).
docs=("$P/skills/orchestrating-sessions/SKILL.md" "$P/skills/orchestrating-sessions/coordinator.md"
  "$P/skills/orchestrating-sessions/status-reference.md" "$P/skills/setting-up-coordination/SKILL.md" "$P/README.md")
while IFS= read -r d; do docs+=("$(find "$P" -path "*/$d" | head -1)"); done < <(grep -oE '[a-z-]+/[a-z-]+\.md' <<<"$c")
written=$(git ls-files -o --exclude-standard; git ls-files -o -i --exclude-standard)
deny='eduard|btigroup|sdm-|@first/|~/bin|(^|[^[:alnum:]_])(vpn|greg|ghostty)([^[:alnum:]_]|$)'
hits=$(grep -HinE "$deny" "$out" "${docs[@]}" $written 2>/dev/null | grep -v CLAUDE_CONFIG_DIR)
[ -z "$hits" ] || fail "personal strings: $hits"

# Writes outside the repo.
outside=$(cd "$T" && find home tmp -type f | grep -vE '^home/\.cache/session-status/' | grep -v '^tmp/')
[ -z "$outside" ] || fail "written outside the repo: $outside"
[ -z "$(find "$HOME/.local/state/session-orchestration" -type f 2>/dev/null)" ] || fail "state folder not empty"

[ "$fails" = 0 ] && echo ok || { echo "$fails failed"; exit 1; }

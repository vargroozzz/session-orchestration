#!/usr/bin/env bash
# Self-check for start-inject.sh. Run: bash start-inject.test.sh  (prints "ok" or the failure).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
root=$(mkdir -p "$tmp/proj/.claude" "$tmp/proj/mem/memory" && cd "$tmp/proj" && pwd -P)
echo '{}' > "$root/.claude/coordination.local.json"
printf -- '- Project memory: `mem/memory.md`.\n' > "$root/CLAUDE.md"
echo 'MEMORY INDEX' > "$root/mem/memory.md"; echo 'COORD TOPIC' > "$root/mem/memory/coordinator.md"
# a fake --start: STATUS LINES lines of 100 characters, after SLEEP seconds
cat > "$tmp/ss" <<'EOF'
sleep "${SLEEP:-0}"; echo "sid=$CLAUDE_CODE_SESSION_ID"
i=0; while [ "$i" -lt "${LINES_N:-3}" ]; do printf 'row %04d %s\n' "$i" "$(printf '%090d' 0)"; i=$((i + 1)); done
EOF
echo '{"type":"user","message":{"content":"x"}}' > "$tmp/new.jsonl"
printf '{"type":"user"}\n{"type":"assistant"}\n' > "$tmp/old.jsonl"
fail() { echo "FAIL $1"; exit 1; }
# run SID TRANSCRIPT PROMPT: parts 1-3 in parallel, as hooks.json runs them; each part's context in $tmp/out.N
run() {
  local i; for i in 1 2 3; do
    jq -nc --arg s "$1" --arg t "$tmp/$2" --arg p "$3" --arg c "$root" '{session_id: $s, transcript_path: $t, prompt: $p, cwd: $c, hook_event_name: "UserPromptSubmit"}' |
      XDG_CACHE_HOME=$tmp/.cache START_INJECT_SS=$tmp/ss bash "$here/start-inject.sh" "$i" > "$tmp/raw.$i" &
  done; wait
  for i in 1 2 3; do jq -r '.hookSpecificOutput.additionalContext // empty' "$tmp/raw.$i" > "$tmp/out.$i" 2>/dev/null || : > "$tmp/out.$i"; done
}
run s1 new.jsonl 'Act as a coordinator.'
grep -q 'sid=s1' "$tmp/out.1" || fail 'status in part 1, run as the session'
grep -q 'MEMORY INDEX' "$tmp/out.1" && grep -q 'COORD TOPIC' "$tmp/out.1" || fail 'memory index and coordinator topic'
grep -q 'part 1 of 1' "$tmp/out.1" || fail 'one part when it fits'
[ ! -s "$tmp/out.2" ] && [ ! -s "$tmp/out.3" ] || fail 'parts 2 and 3 silent when one fits'
run s2 new.jsonl 'Fix the bug. Act as a coordinator.'
[ ! -s "$tmp/out.1" ] || fail 'a task prompt'
run s3 old.jsonl 'Act as a coordinator.'
[ ! -s "$tmp/out.1" ] || fail 'a resumed session'
LINES_N=150 run s4 new.jsonl 'Act as a coordinator. You succeed "c" (12345678).'
for i in 1 2; do grep -q "part $i of 2" "$tmp/out.$i" || fail "two parts: part $i"; done
[ "$(LC_ALL=C wc -c < "$tmp/out.1")" -lt 10000 ] || fail 'a part under the 10,000 cap'
[ "$(cat "$tmp/out.1" "$tmp/out.2" | grep -c '^row ')" = 150 ] || fail 'no row lost or doubled across parts'
LINES_N=400 run s5 new.jsonl 'Act as a coordinator.'
grep -q 'Read .*start-s5.md from line [0-9]' "$tmp/out.3" || fail 'part 3 points to the file when more pieces are needed'
SLEEP=5 START_INJECT_BUDGET=1 run s6 new.jsonl 'Act as a coordinator.'
grep -q 'not finished in 1 s' "$tmp/out.1" && grep -q 'MEMORY INDEX' "$tmp/out.1" || fail 'a slow --start: the cheap part and what still runs'
run s7 new.jsonl 'Coordinate PROJ-12: run the plan.'
grep -q "PROJ-12's sub-coordinator" "$tmp/out.1" && ! grep -q 'sid=' "$tmp/out.1" || fail 'a sub-coordinator: header, no --start'
echo ok

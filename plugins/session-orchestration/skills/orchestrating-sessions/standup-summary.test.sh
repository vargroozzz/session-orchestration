#!/bin/bash
# Tests for standup-summary against a stub claude: cached per day, a session's moving text doesn't rerun it, failures
# and a hung call exit 1 with the cache untouched. Run: bash standup-summary.test.sh  (prints "ok" or the failure).
set -uo pipefail
s=$(cd "$(dirname "$0")" && pwd)/standup-summary
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir "$t/bin"
cat > "$t/bin/claude" <<STUB
#!/bin/bash
echo run >> "$t/runs"; cat > "$t/stdin"; printf '%s\n' "\$*" > "$t/args"
[ -z "\${STUB_FAIL:-}" ] || { echo '{"is_error":true,"result":"rate limited"}'; exit 1; }
[ -z "\${STUB_HANG:-}" ] || exec sleep 30
echo 'warning: an update is available' >&2
echo '{"result":"Yesterday I finished ABC-1."}'
STUB
chmod +x "$t/bin/claude"
export XDG_CACHE_HOME=$t/cache PATH=$t/bin:$PATH
sum() { bash "$s"; }
log=$'Since: 2030-01-03 Thu (last working day)\nABC-1\tDone\tFix it\n  Thu 10:00\tsession "a" (09:00–10:00): working on it'
out=$(sum <<<"$log") && [ "$out" = "Yesterday I finished ABC-1." ] || { echo "first run: $out"; exit 1; }
# The model gets today's date, then the log; haiku by default, no tools.
[ "$(head -1 "$t/stdin")" = "Today: $(date '+%a %F')" ] && [ "$(tail -n +2 "$t/stdin")" = "$log" ] &&
  grep -q -- '--model haiku --tools  --safe-mode' "$t/args" || { echo "the model's input or flags"; cat "$t/stdin" "$t/args"; exit 1; }
# A session's span and last text moved: cached, no second run.
out=$(sum <<<"${log/10:00): working on it/11:00): done}") && [ "$out" = "Yesterday I finished ABC-1." ] &&
  [ "$(grep -c . "$t/runs")" = 1 ] || { echo "a session's new text ran the model again"; exit 1; }
# A new event: run again.
sum <<<"$log"$'\n  Thu 12:00\tapp#1 merged' >/dev/null && [ "$(grep -c . "$t/runs")" = 2 ] || { echo "a new event didn't run the model"; exit 1; }
# A failure: exit 1 and the reason, the cache untouched.
out=$(STUB_FAIL=1 sum <<<"$log"$'\n  Thu 13:00\tJira: A → B') && { echo "a failed call exited 0"; exit 1; }
grep -q 'rate limited' <<<"$out" || { echo "failure reason missing: $out"; exit 1; }
[ "$(sed -n 2p "$t/cache/session-orchestration/standup/2030-01-03.txt")" = "Yesterday I finished ABC-1." ] ||
  { echo "a failure changed the cache"; exit 1; }
out=$(sum <<<"no since line") && { echo "no Since: line exited 0"; exit 1; }
[ "$out" = "no Since: line in the input" ] || { echo "no Since: line: $out"; exit 1; }
# A hung call: killed at the cap, not waited out.
st=$SECONDS
out=$(STUB_HANG=1 STANDUP_SUMMARY_CAP_S=1 sum <<<"$log"$'\n  Thu 14:00\tJira: B → C') && { echo "a hung call exited 0"; exit 1; }
[ $((SECONDS - st)) -lt 10 ] || { echo "a hung call took $((SECONDS - st))s"; exit 1; }
# Another model: written again, though the data is the same; another day has its own cache.
SESSION_STATUS_SUMMARY_MODEL=sonnet sum <<<"$log" >/dev/null && [ "$(grep -c . "$t/runs")" = 5 ] &&
  grep -q -- '--model sonnet' "$t/args" || { echo "another model reused the cache"; exit 1; }
sum <<<"${log/2030-01-03/2030-01-06}" >/dev/null && [ "$(grep -c . "$t/runs")" = 6 ] &&
  [ -f "$t/cache/session-orchestration/standup/2030-01-06.txt" ] || { echo "another day reused the cache"; exit 1; }
echo ok

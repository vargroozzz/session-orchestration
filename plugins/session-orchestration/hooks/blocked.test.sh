#!/usr/bin/env bash
# Self-check for blocked.sh. Run: bash blocked.test.sh  (prints "ok" or the failure).
set -euo pipefail; unset XDG_STATE_HOME   # the usage log under the test's HOME, never the real one
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
h() { HOME=$tmp SESSION_STATUS_GRANT_WAIT=0 bash "$here/blocked.sh" "$@"; }
jq -nc '{session_id: "s1", tool_name: "Bash", tool_input: {command: "touch\n  /tmp/a"}}' | h request
jq -nc '{session_id: "s1", notification_type: "permission_prompt", message: "Claude needs your permission"}' | h notify
got=$(jq -c '{type, tool, input}' "$tmp/.cache/session-status/blocked/s1.json")
[ "$got" = '{"type":"permission_prompt","tool":"Bash","input":"touch /tmp/a"}' ] || { echo "FAIL notify: $got"; exit 1; }
# A question after an answered permission prompt isn't labelled with that prompt's call.
jq -nc '{session_id: "s2", tool_name: "Bash", tool_input: {command: "rm -rf build"}}' | h request
jq -nc '{session_id: "s2", notification_type: "elicitation_dialog", message: "Question"}' | h notify
got=$(jq -c '{type, tool}' "$tmp/.cache/session-status/blocked/s2.json")
[ "$got" = '{"type":"elicitation_dialog","tool":null}' ] || { echo "FAIL elicitation: $got"; exit 1; }
jq -nc '{session_id: "s1", cwd: "/p", tool_name: "Bash", tool_input: {command: "rm -rf /x"}, reason: "[Irreversible]"}' | h denied
got=$(jq -c '{session, tool, input, reason}' "$tmp/.cache/session-status/denied.jsonl")
[ "$got" = '{"session":"s1","tool":"Bash","input":"rm -rf /x","reason":"[Irreversible]"}' ] || { echo "FAIL denied: $got"; exit 1; }

# A pane grant (register.tsx's Allow this call). run SID [WAIT] [TOOL] [TRANSCRIPT]: the request hook of a CLI
# session in the background, its output in $tmp/out-SID. hash_of SID: the hash its record holds, once written.
# grant FILESID SESSION HASH AT [CALL] [SHA256]: a grant for Bash CALL (mkfifo f), sha256 SHA256 (HASH).
b=$tmp/.cache/session-status/blocked g=$tmp/.cache/session-status/grants tr=$tmp/t.jsonl; echo '{}' > "$tr"
run() { jq -nc --arg s "$1" --arg t "${3:-Bash}" --arg tp "${4:-$tr}" '{session_id: $s, transcript_path: $tp, tool_name: $t,
  tool_input: {command: "mkfifo f", description: "make it"}}' |
  HOME=$tmp SESSION_STATUS_GRANT_WAIT=${2:-6} CLAUDE_CODE_ENTRYPOINT=cli bash "$here/blocked.sh" request > "$tmp/out-$1" & }
hash_of() { for _ in $(seq 1 40); do [ -s "$b/$1.call" ] && break; sleep 0.1; done; jq -r '.hash // empty' "$b/$1.call"; }
grant() { mkdir -p "$g"; jq -nc --arg s "$2" --arg h "${6:-$3}" --argjson at "$4" --arg c "${5:-mkfifo f}" \
  '{kind: "permission", session: $s, sha256: $h, at: $at, tool: "Bash", call: $c}' > "$g/$1.$3"; }
allow='{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
# A grant left from an earlier prompt of the same call (written before this request) never counts.
run s7 1; wait; h7=$(hash_of s7); [ -n "$h7" ] || { echo "FAIL no hash"; exit 1; }; grant s7 s7 "$h7" $(( $(date +%s) - 2 )); sleep 1
run s3; h3=$(hash_of s3)
got=$(jq -c --arg h "$h3" '{call, wait: (.until - .time), hash: (.hash == $h and ($h | test("^[0-9a-f]{64}$")))}' "$b/s3.call")
[ "$got" = '{"call":"mkfifo f","wait":6,"hash":true}' ] || { echo "FAIL request record: $got"; exit 1; }
grant s3 s3 "$h3" "$(date +%s)"
run s4; grant s4 s9 "$(hash_of s4)" "$(date +%s)"                               # another session's
run s5; grant s5 s5 "$(hash_of s5)" "$(date +%s)" "mkfifo f" ab                # another call's sha256
run s6; grant s6 s6 "$(hash_of s6)" $(( $(date +%s) - 200 ))                   # stale
run s11; grant s11 s11 "$(hash_of s11)" "$(date +%s)" ls                         # the card showed another call
run s7
wait
[ "$(cat "$tmp/out-s3")" = "$allow" ] && [ ! -e "$g/s3.$h3" ] || { echo "FAIL valid grant: $(cat "$tmp/out-s3")"; exit 1; }
for s in s4 s5 s6 s7 s11; do [ ! -s "$tmp/out-$s" ] || { echo "FAIL $s granted: $(cat "$tmp/out-$s")"; exit 1; }; done
# Each request's cleanup: a permission grant goes after an hour, an action grant (an ask's Yes) after 25 hours.
: > "$g/old.perm"; : > "$g/act-old-1.json"; : > "$g/act-stale-1.json"
perl -e 'utime(time - 7200, time - 7200, @ARGV)' "$g/old.perm" "$g/act-old-1.json"; perl -e 'utime(time - 93600, time - 93600, @ARGV)' "$g/act-stale-1.json"
run s20 1; wait
[ ! -e "$g/old.perm" ] && [ -e "$g/act-old-1.json" ] && [ ! -e "$g/act-stale-1.json" ] || { echo "FAIL grant cleanup: $(ls "$g")"; exit 1; }
# The no-wait cases below wait 20 s if they wait at all; under 10 s is no wait even on a loaded machine.
# AskUserQuestion: nothing for the pane to grant, so no hash and no wait.
SECONDS=0; run s8 20 AskUserQuestion; wait
[ -z "$(hash_of s8)" ] && [ "$SECONDS" -lt 10 ] || { echo "FAIL AskUserQuestion waited ${SECONDS}s or got a hash"; exit 1; }
# No dialog alongside the wait: claude -p or the SDK (sdk-cli), no entrypoint, a subagent's call. No hash, no wait.
req_in() { jq -nc --arg s "$1" --arg tp "$tr" '{session_id: $s, transcript_path: $tp, tool_name: "Bash", tool_input: {command: "mkfifo f"}}'; }
SECONDS=0
req_in s10 | HOME=$tmp SESSION_STATUS_GRANT_WAIT=20 CLAUDE_CODE_ENTRYPOINT=sdk-cli bash "$here/blocked.sh" request &
req_in s12 | HOME=$tmp SESSION_STATUS_GRANT_WAIT=20 env -u CLAUDE_CODE_ENTRYPOINT bash "$here/blocked.sh" request &
req_in s13 | jq -c '.agent_id = "a1"' | HOME=$tmp SESSION_STATUS_GRANT_WAIT=20 CLAUDE_CODE_ENTRYPOINT=cli bash "$here/blocked.sh" request &
wait
for s in s10 s12 s13; do [ -z "$(hash_of $s)" ] || { echo "FAIL $s got a hash"; exit 1; }; done
[ "$SECONDS" -lt 10 ] || { echo "FAIL a request with no dialog alongside waited ${SECONDS}s"; exit 1; }
# Answered in the tab: a user entry (the call's tool_result) ends the wait at once with no answer; a bookkeeping line
# (queue-operation: a message typed meanwhile) doesn't.
echo '{}' > "$tmp/t9.jsonl"; SECONDS=0; run s9 20 Bash "$tmp/t9.jsonl"; p9=$!; hash_of s9 >/dev/null
echo '{"type":"queue-operation"}' >> "$tmp/t9.jsonl"; sleep 1.5
kill -0 "$p9" 2>/dev/null || { echo "FAIL a queue-operation line ended the wait"; exit 1; }
echo '{"parentUuid":"x","type":"user"}' >> "$tmp/t9.jsonl"; wait
[ "$SECONDS" -lt 12 ] && [ ! -s "$tmp/out-s9" ] || { echo "FAIL transcript moved: ${SECONDS}s, $(cat "$tmp/out-s9")"; exit 1; }
# request, then notify: the record the pane reads carries the call, its hash and the end of the wait.
run s14 3; h14=$(hash_of s14)
jq -nc '{session_id: "s14", notification_type: "permission_prompt", message: "Claude needs your permission"}' | h notify
got=$(jq -c --arg h "$h14" '{call, hash: (.hash == $h and ($h | test("^[0-9a-f]{64}$"))), wait: (.until > .time)}' "$b/s14.json")
[ "$got" = '{"call":"mkfifo f","hash":true,"wait":true}' ] || { echo "FAIL request then notify: $got"; exit 1; }
wait
echo ok

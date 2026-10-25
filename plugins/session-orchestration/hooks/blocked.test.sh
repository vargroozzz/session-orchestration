#!/usr/bin/env bash
# Self-check for blocked.sh. Run: bash blocked.test.sh  (prints "ok" or the failure).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
h() { HOME=$tmp bash "$here/blocked.sh" "$@"; }
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
echo ok

#!/usr/bin/env bash
# Side effects only, so a coordinator sees what a background session waits on without `claude attach`:
#  request (PermissionRequest: a permission dialog is about to show) keeps the call it asks about in
#          ~/.cache/session-status/blocked/<session_id>.call: the transcript doesn't hold it while it waits. With
#          it, what the coordinator pane's Allow this call needs: the call's hash, the end of the wait (until), the
#          call as the pane shows it. Then, in a CLI session's main thread (the only place a dialog shows alongside
#          the wait), it waits (SESSION_STATUS_GRANT_WAIT, 1800 s) for that press's grant in
#          ~/.cache/session-status/grants/, for this call as the card showed it, and answers allow, or stops once the
#          transcript gets a new user entry (answered in the tab).
#  notify  (Notification: permission_prompt|agent_needs_input|elicitation_dialog) writes
#          ~/.cache/session-status/blocked/<session_id>.json: time, type, message, and, for a permission prompt,
#          that call (tool, input's first 300 chars; used up) when it's from the last 2 minutes. session-status
#          shows it while the session waits (status waiting, or not idle and its transcript no newer).
#  denied  (PermissionDenied: an auto-mode denial) appends time, session, cwd, tool, input, reason to
#          ~/.cache/session-status/denied.jsonl.
d=~/.cache/session-status; mkdir -p "$d/blocked" 2>/dev/null
in=$(cat)
call='{tool: .tool_name, input: ((.tool_input.command // (.tool_input | tojson)) | gsub("\\s+"; " ") | .[:300])}'
sid=$(jq -r '.session_id // empty' <<<"$in" 2>/dev/null); [ -n "$sid" ] || exit 0
case "${1:-}" in
  request)
    # A grant binds to the sha256 of the tool's name and its whole input, and to the tool and call the card showed.
    # The pane shows the call in full: a Bash command alone when its other keys are description and timeout, else the
    # input as JSON. Nothing to show or grant (AskUserQuestion, ExitPlanMode, a call over 4000 chars, no sha256 tool):
    # no hash, no wait.
    w=${SESSION_STATUS_GRANT_WAIT:-1800} t0=$(date +%s)
    # Only a CLI session's own dialog shows while this hook waits: claude -p and the SDK wait on the hook, and a
    # subagent's call has no card. Elsewhere no hash and no wait, as before.
    { [ "${CLAUDE_CODE_ENTRYPOINT:-}" = cli ] && [ -z "$(jq -r '.agent_id // empty' <<<"$in")" ]; } || w=0
    h=$(jq -j '.tool_name, "\n", (.tool_input | tojson)' <<<"$in" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -d' ' -f1)
    rec=$(jq -c --arg h "$h" --argjson w "$w" "{time: (now | floor)} + $call + "'((.tool_name == "Bash") as $b
      | (.tool_input | if $b then del(.description) else . end) as $i
      | (if $b and ($i | keys - ["command", "timeout"] == []) then $i.command else $i | tojson end) as $c
      | if $w > 0 and ($c | length) <= 4000 and (.tool_name | IN("AskUserQuestion", "ExitPlanMode") | not)
          and ($h | test("^[0-9a-f]{64}$"))
        then {hash: $h, until: ((now | floor) + $w), call: $c} else {} end)' <<<"$in" 2>/dev/null)
    printf '%s\n' "$rec" > "$d/blocked/$sid.call"
    jq -e 'has("hash")' <<<"$rec" >/dev/null 2>&1 || exit 0
    c=$(jq -c '.call' <<<"$rec") t=$(jq -r '.tool_name' <<<"$in")
    g=$d/grants f=$d/grants/$sid.$h; mkdir -p "$g" 2>/dev/null; find "$g" -type f ! -name 'act-*' ! -name 'land-*' -mmin +60 -delete 2>/dev/null
    find "$g" -type f \( -name 'act-*' -o -name 'land-*' \) -mmin +1500 -delete 2>/dev/null   # an ask's action or land grant holds a day (approved-action.sh)
    tp=$(jq -r '.transcript_path // empty' <<<"$in") n0=; [ ! -f "$tp" ] || n0=$(wc -c < "$tp")
    # This session and call, as the card showed it (a record rewritten to show another call gets nothing), written
    # during this wait (a grant left from an earlier prompt never counts), fresh.
    ok='.kind == "permission" and .session == $s and .sha256 == $h and .tool == $t and .call == $c
      and (.at | type == "number") and .at >= $t0 and .at >= now - 120 and .at <= now + 5'
    while [ "$(date +%s)" -lt $(( t0 + w )) ]; do
      # answered in the tab: a user entry after the baseline (the call's tool_result); queue-operation and other
      # bookkeeping lines don't count
      [ -z "$n0" ] || ! tail -c +$((n0 + 1)) "$tp" 2>/dev/null | grep -q '"type":"user"' || exit 0
      # checked before the claim (a half-written grant waits for the next look) and after it (the file claimed)
      if [ -f "$f" ] && jq -e --arg s "$sid" --arg h "$h" --arg t "$t" --argjson c "$c" --argjson t0 "$t0" "$ok" "$f" >/dev/null 2>&1 &&
        mv "$f" "$f.$$" 2>/dev/null; then
        r=; jq -e --arg s "$sid" --arg h "$h" --arg t "$t" --argjson c "$c" --argjson t0 "$t0" "$ok" "$f.$$" >/dev/null 2>&1 && r=1
        rm -f "$f.$$"
        [ -z "$r" ] || { echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'; exit 0; }
      fi
      sleep 1
    done ;;
  notify)
    c=
    if [ "$(jq -r .notification_type <<<"$in")" = permission_prompt ]; then
      c=$(jq -c 'select(.time >= (now - 120)) | del(.time)' "$d/blocked/$sid.call" 2>/dev/null); rm -f "$d/blocked/$sid.call"
    fi
    [ -n "$c" ] || c='{}'
    jq -c --argjson c "$c" '{time: (now | floor), type: .notification_type, message} + $c' <<<"$in" > "$d/blocked/$sid.json.tmp" &&
      mv "$d/blocked/$sid.json.tmp" "$d/blocked/$sid.json" ;;
  denied)
    jq -c "{time: (now | floor), session: .session_id, cwd} + $call + {reason}" <<<"$in" >> "$d/denied.jsonl" 2>/dev/null
    # telemetry=full: a refuse line naming the tool (lib.sh usage); another server's MCP tool only as mcp, its name may
    # name a company.
    { read -r t; read -r cwd; } < <(jq -r '(.tool_name // "" | if startswith("mcp__session-orchestration__") then "mcp-" + .[28:]
      elif startswith("mcp__") then "mcp" else . end | ascii_downcase | gsub("[^a-z0-9-]"; "-") | .[:40]), (.cwd // ".")' <<<"$in")
    ( l=$(cd "${0%/*}/.." 2>/dev/null && pwd)/lib.sh; cd "$cwd" 2>/dev/null; . "$l" && usage "$t" refuse ) >/dev/null 2>&1 ;;
esac
exit 0

#!/usr/bin/env bash
# Side effects only, so a coordinator sees what a background session waits on without `claude attach`:
#  request (PermissionRequest: a permission dialog is about to show) keeps the call it asks about in
#          ~/.cache/session-status/blocked/<session_id>.call: the transcript doesn't hold it while it waits.
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
    jq -c "{time: (now | floor)} + $call" <<<"$in" > "$d/blocked/$sid.call" 2>/dev/null ;;
  notify)
    c=
    if [ "$(jq -r .notification_type <<<"$in")" = permission_prompt ]; then
      c=$(jq -c 'select(.time >= (now - 120)) | del(.time)' "$d/blocked/$sid.call" 2>/dev/null); rm -f "$d/blocked/$sid.call"
    fi
    [ -n "$c" ] || c='{}'
    jq -c --argjson c "$c" '{time: (now | floor), type: .notification_type, message} + $c' <<<"$in" > "$d/blocked/$sid.json.tmp" &&
      mv "$d/blocked/$sid.json.tmp" "$d/blocked/$sid.json" ;;
  denied)
    jq -c "{time: (now | floor), session: .session_id, cwd} + $call + {reason}" <<<"$in" >> "$d/denied.jsonl" 2>/dev/null ;;
esac
exit 0

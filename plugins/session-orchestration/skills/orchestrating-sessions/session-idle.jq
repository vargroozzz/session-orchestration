# session-idle.jq: why a background session's turn ended, for session-status --watch's idle check. Input (jq -Rn, with
# --argjson since MS, the session's start): its transcript. Output, one word: replied (its last turn sent the reply tool
# or SendMessage, or a retro section's retro-run --join), waiting (a background task it started since `since` hasn't notified its end yet), else idle.
def ms: try (capture("^(?<s>[^.Z]+)(?<f>\\.[0-9]+)?Z$") | ((.s + "Z") | fromdateiso8601) * 1000
  + ((("0" + (.f // "")) | tonumber) * 1000 | round)) catch 0;
def text: if type == "string" then . else [.[]? | .text? // empty] | join(" ") end;
# A prompt starts a turn; a task notification, a compact summary or a slash command (/reload-plugins) doesn't.
def started: .type == "user" and (.isMeta | not) and (.isCompactSummary | not) and .origin.kind? != "task-notification"
  and (.message.content | (type == "string" and (startswith("<command-") or startswith("<local-command-") | not))
    or (type == "array" and all(.[]; .type? != "tool_result")));
def ok($r): ($r.is_error // false | not) and ($r.content | text | contains("\"success\":false") | not);
[inputs | fromjson? | objects] as $rows
| ([$rows | to_entries[] | select(.value | started) | .key] | last // 0) as $turn
| [$rows[] | select(.type == "assistant") | (.timestamp | ms) as $ts | .message.content[]? | select(.type? == "tool_use")
   | . + {ts: $ts}] as $uses
| [$rows[] | select(.type == "user") | .message.content | arrays[] | select(.type? == "tool_result")
   | {key: .tool_use_id, value: .}] | from_entries as $results
| ([$rows[] | select((.type == "queue-operation" and .operation == "enqueue") or .origin.kind? == "task-notification")
    | (.content // .message.content) | strings | scan("<task-notification>[\\s\\S]*?</task-notification>")
    | capture("<tool-use-id>(?<id>[^<]+)</tool-use-id>[\\s\\S]*<status>(?<s>completed|failed|killed|stopped)</status>")
    | .id]
   + [$uses[] | select(.name == "TaskStop" or .name == "KillShell") | select(ok($results[.id]))
      | "task:" + ((.input.task_id // .input.shell_id) | tostring)]) as $ended
# a notification resumes the turn: a reply before it doesn't cover what the session did after it
| ([$rows | to_entries[] | select(.key >= $turn and .value.type == "user"
    and (.value.origin.kind? == "task-notification" or (.value.message.content | strings | startswith("<task-notification>"))))
    | .key] | last // $turn) as $seg
| ([$rows[$seg:][] | select(.type == "assistant") | .message.content[]?
    # a retro section session ends with `retro-run --join`, never a reply
    | select(.type? == "tool_use" and (.name == "mcp__session-orchestration__reply" or .name == "SendMessage"
        or (.name == "Bash" and (.input.command // "" | test("retro-run\"? +--join ")))))
    | select(ok($results[.id]))] | length > 0) as $replied
| ([$uses[] | select(.ts >= $since) | $results[.id] as $r | select($r.is_error // false | not)
    # a Bash past its timeout is moved to the background with no run_in_background flag
    | select((.name == "Bash" and (.input.run_in_background == true
          or ($r.content | text | test("moved to (the )?background"; "i")))) or .name == "Monitor"
        or ((.name == "Agent" or .name == "Skill")
          and (.input.run_in_background == true or ($r.content | text | test("running in the background"; "i")))))
    # ended: notified by its tool_use id, or stopped by the task id its launch result names
    | select(.id as $id | $ended | index($id) | not)
    | select(($r.content | text | [capture("(?:ID|agentId): (?<t>[A-Za-z0-9]+)").t] | first) as $t
        | $t == null or ($ended | index("task:" + $t) | not))] | length > 0) as $waiting
| if $replied then "replied" elif $waiting then "waiting" else "idle" end

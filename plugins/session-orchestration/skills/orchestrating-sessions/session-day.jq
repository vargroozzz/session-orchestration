# What one transcript did since $from (epoch seconds), for session-status --yesterday: one tab-separated line,
# or nothing when it wrote no prompt or reply since. Fields: name (its latest), first prompt's key ("" none),
# its `Session task: KEY[ review]` markers (own text and the messages it received, comma-separated), coordinator
# (1: it ran a status watcher, $status: session-status or the adapter's status-names, with --changes or --watch;
# stricter than the board's any-run, so a session that only tested or read the script still shows),
# first and last entry since $from (epoch s), its last text line since then (one line, 200 characters).
# Run over the transcript's raw lines (a broken one is skipped): jq -rRn--argjson from N --arg keyre ERE --arg status RE -f session-day.jq FILE
def ts: (.timestamp // "") | sub("\\.[0-9]+Z$"; "Z") | try fromdate catch 0;
def texts: if (.message.content | type) == "string" then .message.content
  else .message.content[]? | select(.type == "text") | .text end;
def prompt: select(.type == "user" and (.message.content | type) == "string") | .message.content;
reduce (inputs | fromjson? | select(type == "object")) as $e ({name: "", first: null, marks: [], coord: 0, a: 0, b: 0, last: ""};
  ($e | ts) as $t
  | if $e.agentName then .name = $e.agentName else . end
  | if .first == null then (($e | prompt | select(startswith("This session is being continued") | not)) // null) as $p
      | if $p then .first = $p else . end else . end
  | if $e.type == "assistant" or ($e.type == "user" and ($e.message.content | type) == "string"
        and $e.origin.kind != "task-notification") then   # a subagent's result quotes, it doesn't brief
      .marks += [$e | texts | match("Session task: (?:\($keyre))(?: review(?=[.,;:!)]|$))?"; "g").string] else . end
  | if $e.type == "assistant" and any($e.message.content[]?; .type == "tool_use"
        and (.input.command // "" | test("(\($status)) +--(changes|watch)"))) then .coord = 1 else . end
  | if $t >= $from and ($e.type == "assistant" or $e.type == "user") then .a = (if .a == 0 then $t else .a end) | .b = $t
      | ([$e | select(.type == "assistant") | texts | gsub("\\s+"; " ") | select(test("\\S"))] | last) as $x
      | if $x then .last = $x else . end
    else . end)
| select(.b > 0)
| [.name, ((.first // "") | [match($keyre; "g").string] | first // ""), (.marks | unique | map(sub("^Session task: "; "")) | join(",")),
   .coord, .a, .b, (.last | .[0:200])] | @tsv

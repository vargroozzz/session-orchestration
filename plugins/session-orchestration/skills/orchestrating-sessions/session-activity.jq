# What a session is doing, from the tail of its transcript (session-status --activity and "Other sessions").
# Run: tail -n 2000 FILE | jq -rRn -f session-activity.jq   prints DOING<TAB>SINCE<TAB>LAST<TAB>CTX<TAB>MODEL
#   DOING  its in_progress todo (TodoWrite, or TaskCreate/TaskUpdate), else its latest tool call's description,
#          else that call in a few words ("Read register.tsx"), else its last text line; tabs/newlines flattened
#   SINCE  epoch seconds when that activity started (consecutive calls with the same text count as one); 0 unknown
#   LAST   the last line of its own text
#   MODEL  the latest model id its model attachments name ("" when the tail has none)
#   CTX    tokens in its context: the last main-thread reply's input + cache read + cache creation, or a later
#          /compact's postTokens; 0 unknown
# The approach is flightdeck's agent cards (github.com/scasella/claude-flightdeck): a card's title is its task
# description, its clock counts from when that started, and a call without one is described by its input.
def flat: tostring | gsub("[\t\r\n]+"; " ") | gsub("^ +| +$"; "") | .[0:120];
def epoch: (. // "") | sub("\\.[0-9]+Z$"; "Z") | (fromdate? // 0);
def lastline: [split("\n")[] | select(test("\\S"))] | last // null;
def describe($n; $i):
  if ($i.description | type) == "string" then $i.description
  elif ($i.command | type) == "string" then "\($n): \($i.command)"
  elif ($i.file_path | type) == "string" then "\($n) \($i.file_path | split("/") | last)"
  elif ($i.pattern | type) == "string" then "\($n) \($i.pattern)"
  elif ($i.url | type) == "string" then "\($n) \($i.url)"
  elif ($i.subject | type) == "string" then "\($n): \($i.subject)"
  elif ($i.summary | type) == "string" then "\($n): \($i.summary)"
  else $n end;
# Moves activity slot $k (todo or tool) to $v at $ts, keeping the start time while the text is unchanged.
def set($k; $v; $ts): if .[$k] == $v then . else .[$k] = $v | .["\($k)At"] = $ts end;

reduce (inputs | fromjson? | select(type == "object" and .isSidechain != true)) as $e (
  {todo: null, todoAt: 0, tool: null, toolAt: 0, text: null, pend: {}, tasks: {}, ctx: 0, model: ""};
  ($e.timestamp | epoch) as $ts
  | if $e.type == "assistant" and ($e.message.usage | type) == "object" then
      # A synthetic or failed reply (all zero) leaves the last real reading.
      ([$e.message.usage | .input_tokens, .cache_read_input_tokens, .cache_creation_input_tokens | numbers] | add // 0) as $n
      | if $n > 0 then .ctx = $n else . end
    elif $e.type == "system" and $e.subtype == "compact_boundary" then .ctx = ($e.compactMetadata.postTokens // 0)
    else . end
  | if ($e.attachment?.identity?.modelId? | type) == "string" then .model = $e.attachment.identity.modelId else . end
  | if $e.type == "assistant" and ($e.message.content | type) == "array" then
      reduce $e.message.content[] as $c (.;
        if $c.type == "text" then .text = (($c.text | lastline) // .text)
        elif $c.type != "tool_use" then .
        elif $c.name == "TodoWrite" then
          set("todo"; [$c.input.todos[]? | select(.status == "in_progress") | .activeForm // .content] | first; $ts)
        elif $c.name == "TaskCreate" then .pend[$c.id] = ($c.input.activeForm // $c.input.subject)
        elif $c.name == "TaskUpdate" then
          ($c.input.taskId | tostring) as $id
          | (.tasks[$id] // $c.input.activeForm // $c.input.subject) as $t
          | if $c.input.status == "in_progress" and $t then set("todo"; $t; $ts)
            elif ($c.input.status == "completed" or $c.input.status == "deleted") and .tasks[$id] == .todo then .todo = null
            else . end
        else set("tool"; describe($c.name; $c.input // {}); $ts) end)
    elif $e.type == "user" and ($e.message.content | type) == "array" then
      # A TaskCreate's result names its id: "Task #3 created successfully: …".
      reduce ($e.message.content[] | select(type == "object" and .type == "tool_result")) as $r (.;
        if .pend[$r.tool_use_id] == null then .
        else ([$r.content | if type == "array" then map(.text? // "") | join("") else tostring end
               | capture("Task #(?<n>[0-9]+) created")? | .n] | first) as $n
          | if $n then .tasks[$n] = .pend[$r.tool_use_id] else . end end)
    else . end)
| [ (.todo // .tool // .text // "" | flat),
    (if .todo then .todoAt elif .tool then .toolAt else 0 end),
    (.text // "" | flat),
    .ctx,
    .model ]
| @tsv

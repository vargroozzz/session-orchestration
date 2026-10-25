# A session's recent activity as Markdown, for session-status --peek and the coordinator pane's Peek.
# Run: tail -n 2000 FILE | jq -rRn --argjson n 12 -f session-peek.jq
# The last $n entries of its main thread: a prompt it received (`**prompt** · HH:MM`), its own text
# (`**claude** · HH:MM`), and each tool call as a `→ ` line under them. Meta entries (system reminders, command
# wrappers) and tool results are left out; each text is cut to 600 characters.
def cut($k): if length > $k then .[0:$k] + " …" else . end;
# A text cut inside a code fence gets it closed, so what follows isn't drawn as code.
def fenced: if ([match("```"; "g")] | length) % 2 == 1 then . + "\n```" else . end;
def flat: tostring | gsub("[\t\r\n]+"; " ") | gsub("^ +| +$"; "") | cut(100);
def hhmm: (. // "") | sub("\\.[0-9]+Z$"; "Z") | (fromdate? // null) | if . then strflocaltime("%H:%M") else "" end;
# A tool call in a few words, as session-activity.jq's describe reads it.
def call($n; $i):
  "→ \($n)" + ([$i.description, $i.command, ($i.file_path | strings | split("/") | last), $i.pattern, $i.url, $i.subject, $i.skill, $i.to, $i.prompt]
    | map(strings) | first // "" | if . == "" then "" else ": " + flat end);
def text: if type == "string" then . elif type == "array" then [.[] | select(.type? == "text") | .text] | join("\n") else "" end;

[ inputs | fromjson? | select(type == "object" and .isSidechain != true and .isMeta != true)
  | .timestamp as $ts
  | if .type == "user" then
      (.message.content | text) as $t
      | select(($t | test("\\S")) and ($t | test("^\\s*<(local-command|command-|system-reminder)") | not))
      | {who: "prompt", ts: $ts, text: $t}
    elif .type == "assistant" and (.message.content | type) == "array" then
      .message.content[]
      | if .type == "text" and (.text | test("\\S")) then {who: "claude", ts: $ts, text: .text}
        elif .type == "tool_use" then {who: "tool", ts: $ts, text: call(.name; .input // {})}
        else empty end
    else empty end ]
| .[-$n:]
# A tool line right after another entry joins it; a block gets its heading.
| reduce .[] as $e ({out: [], prev: null};
    if $e.who == "tool" then .out += [(if .prev == "tool" then "" else "\n" end) + $e.text + "  "]
    else .out += ["\n**\($e.who)** · \($e.ts | hhmm)\n\n\($e.text | cut(600) | fenced)\n"] end
    | .prev = $e.who)
| .out | join("\n") | sub("^\n+"; "")

# One transcript (jq -nR, args $header, $rel, $abs, $sid) → the handoff file's versions it shows, one JSON per line:
# {t, i, s, n, k, v} (n: the turn), and per turn {k: "x", s, n, text}: its assistant text, where a removal's reason is
# looked up (said before or after the call; the last 8000 characters). k "v": a whole version: a full Read or a Write of the file, an Edit's file before it and
# after it, or a copy written elsewhere at the moment a Bash `mv` swaps it in. "b": one cut from the output of a Bash
# command naming the file (cat, cat -n, an adapter's `pending`), maybe mixed with other output. "e": an Edit whose
# file before it isn't in the transcript (old/new/all), applied to the last known version, with its patch's hunks
# (each one's lines before and after it) to check that version against. "g": a Bash command that writes the file
# (sed/perl -i, a redirect or mv/cp onto it, tee, a script's write): reported, as what it wrote isn't in the
# transcript. A version starts with $header. A path counts when it is $abs (the root's file), a command when it names $rel: a test fixture with the
# same header, or another project's file of that name, doesn't.
def applied($o; $n; $all): if $all then split($o) | join($n)
  else split($o) as $p | if ($p | length) < 2 then null else $p[0] + $n + ($p[1:] | join($o)) end end;
def whole: select(type == "string" and (split("\n")[0] == $header));
def ours: type == "string" and . == $abs;
# an Edit's structuredPatch hunks: each one's lines before the edit (" " and "-") and after it (" " and "+")
def hunks($p): [$p[]? | [.lines[]? | select(.[:1] != "\\")] | {pre: [.[] | select(.[:1] == " " or .[:1] == "-") | .[1:]],
  post: [.[] | select(.[:1] == " " or .[:1] == "+") | .[1:]]}];
# a command that writes FILE: in place, a script's write, or a redirect, tee, mv or cp onto FILE's name or a variable
# the command sets to it. ponytail: a write through a path built elsewhere isn't seen; an Edit whose patch doesn't fit
# the last version is what marks it stale then
($rel | split("/") | last | gsub("(?<c>[.^$*+?()\\[\\]{}|\\\\])"; "\\\(.c)")) as $name |
def writes: [match("(\\w+)=[\"']?\\S*" + $name; "g").captures[0].string] as $v
  | ("(\\S*" + $name + ([$v[] | "|\\$\\{?" + . + "\\b\\}?"] | add // "") + ")") as $to
  | test("\\b(sed|perl)\\b[^;&|]*\\s(-[a-zA-Z]*i|--in-place)\\b|\\.write(_text)?\\(|>>?\\s*[\"']?" + $to
    + "|\\btee\\s+(-a\\s+)?[\"']?" + $to + "|\\b(mv|cp)\\s[^;&|]*\\s[\"']?" + $to + "[\"']?\\s*($|[;&|)])");
# cut from mixed output: from the header line on; numbered (cat -n) lines are unnumbered, up to the first unnumbered one
def cut: split("\n") as $l
  | ([range(0; $l | length) | select($l[.] | sub("^ *[0-9]+\t"; "") == $header)] | first) as $h
  | if $h == null then empty else ($l[$h] | test("^ *[0-9]+\t")) as $num
    | [$l[$h:][] ] | if $num then [label $out | .[] | if test("^ *[0-9]+\t") then sub("^ *[0-9]+\t"; "") else break $out end]
      else . end | join("\n") end;
foreach ((inputs | fromjson? // empty), null) as $l ({turn: "", n: 0, i: 0, cmds: {}, tmp: {}};
  .i += 1 | .out = [] |
  if $l == null then .out = [{k: "x", text: .turn, t: ""}]
  elif $l.type == "assistant" then
    [$l.message.content[]? | select(.type == "tool_use" and .name == "Bash") | {id, c: (.input.command // "")}] as $b
    | .turn = ((.turn + "\n" + ([$l.message.content[]? | select(.type == "text") | .text] | join("\n"))) | .[-8000:])
    | [$b[] | select(.c | contains($rel) and (contains(".test.sh") | not))] as $named
    | .cmds += ([$named[] | {key: .id, value: true}] | from_entries)
    | .tmp as $tmp
    # per command: the copies it swaps in with mv (whole versions); one naming FILE that swaps none in, a write of its own
    | [$b[] | .c as $c | {c: $c, named: ([$named[] | .c == $c] | any),
        swap: [$tmp | keys[] | select(. as $p | $c | contains("mv ") and contains($p))]}] as $cs
    | .out = [$cs[] | .swap[] | {k: "v", v: $tmp[.]}]
      + [$cs[] | select(.named and (.swap | length) == 0 and (.c | writes)) | {k: "g", c: (.c | gsub("\\s+"; " ") | .[:200])}]
    | .tmp = ($tmp | with_entries(select(.key as $p | any($b[]; .c | contains("mv ") and contains($p)) | not)))
  elif $l.type == "user" and ($l.toolUseResult | type) != "object" then
    # a prompt (not a tool result) starts a turn
    if ([$l.message.content | if type == "string" then . else .[]? | select(.type == "text") end] | length) > 0
    then .out = [{k: "x", text: .turn, t: ""}] | .turn = "" | .n += 1 else . end
  elif $l.type == "user" then
    $l.toolUseResult as $r | ([$l.message.content[]? | .tool_use_id? // empty] | first) as $tid |
    .out = [
      (if ($r.file | type) == "object" and ($r.file.filePath | ours) and $r.file.numLines == $r.file.totalLines
         and ($r.file.startLine // 1) == 1 then $r.file.content | whole | {k: "v", v: .} else empty end),
      (if ($r.oldString | type) == "string" and ($r.filePath | ours) then
         if ($r.originalFile | type) == "string" and $r.originalFile != "" then
           {k: "v", v: $r.originalFile, o: true},
           ($r.originalFile | applied($r.oldString; $r.newString; $r.replaceAll == true) | select(. != null) | {k: "v", v: .})
         else {k: "e", old: $r.oldString, new: $r.newString, all: ($r.replaceAll == true),
           hunks: hunks($r.structuredPatch)} end
       else empty end),
      (if ($r.type == "create" or $r.type == "update") and ($r.filePath | ours) and ($r.content | type) == "string"
       then $r.content | whole | {k: "v", v: .} else empty end),
      (if ($r.stdout | type) == "string" and .cmds[$tid // ""] and ($r.stdout | contains($header))
       then $r.stdout | cut | {k: "b", v: .} else empty end)
    ]
    # a copy written elsewhere: a version once a mv swaps it in
    | if ($r.type == "create" or $r.type == "update") and ($r.filePath | type) == "string" and ($r.filePath | ours | not)
        and ($r.content | type) == "string" and ($r.content | split("\n")[0] == $header)
      then .tmp[$r.filePath] = $r.content else . end
  else . end;
  .n as $n | .i as $i | .out[] | . + {t: (.t // $l.timestamp), i: (if .o then $i - 0.5 else $i end), s: $sid, n: (if .k == "x" and $l != null and $l.type == "user" then $n - 1 else $n end)} | del(.o))

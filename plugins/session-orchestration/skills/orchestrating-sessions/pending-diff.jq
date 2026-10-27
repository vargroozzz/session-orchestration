# pending-versions.jq's records of every transcript (jq -s), diffed in time order: one TSV line per event,
# TIME<TAB>ID8<TAB>LABEL<TAB>SLUG<TAB>change|gone<TAB>LINE (change) or REASON (gone). TIME is local YYYY-MM-DD HH:MM.
# A version cut from Bash output ("b") may be cut short, so it adds and rewords entries but never removes one; so does
# an Edit's patch ("e" when the version it applies to is stale, unknown or lacks the patch's context). A Bash write
# ("g") prints TIME<TAB>ID8<TAB><TAB><TAB>gap<TAB>COMMAND (LABEL and SLUG empty): what it wrote counts once a later
# version shows it.
# LABEL and SLUG follow `pending`'s awk (entries): keep the two in step.
def entries: reduce (split("\n")[1:][]) as $x ({started: false, stop: false, e: []};
    if .stop then .
    elif $x | startswith("- ") then .started = true | .e += [$x[2:]]
    elif .started and ($x | test("^#") or test("\\S")) then .stop = true
    else . end) | .e;
def lab: sub("^[0-9]{4}-[0-9]{2}-[0-9]{2} "; "") | if test(" \\(|:") then capture("^(?<l>.*?)(?: \\(|:)").l else . end;
def slug: gsub("[^A-Za-z0-9._-]+"; "-") | gsub("^-+|-+$"; "") | .[:60];
def bylabel: reduce (entries[]) as $e ({}; ($e | lab) as $l | ($l | slug) as $s
  | .[$s] = {label: $l, lines: ((.[$s].lines // []) + [$e])});
def when: sub("\\.[0-9]+Z$"; "Z") | fromdate | strflocaltime("%Y-%m-%d %H:%M");
# the first sentence of the turn's text naming the label and saying it's resolved, else unknown
def reason($l): [splits("(?<=[.!?])\\s+|\\n") | select(contains($l) and test("(?i)\\b(remov|drop|delet|done|merged|resolv|gone|closed|finished|landed|released|shipped|no longer|out of date|stale\\b|superseded|answered|approved|stopped)"))]
  | first // "unknown"
  | gsub("[\\t\\n]+"; " ") | gsub("^\\s+|\\s+$"; "") | .[:200];
(map(select(.k == "x") | {key: "\(.s) \(.n)", value: .text}) | from_entries) as $turns |
# $v seen at $r's time: its new wordings are changes; a whole version also ends the entries it lacks, a part ($part:
# Bash output, an Edit's patch) doesn't, and adds its lines to the ones known
def gone($r; $s; $l): [($r.t | when), $r.s[:8], $l, $s, "gone", ($turns["\($r.s) \($r.n)"] // "" | reason($l))];
def seen($r; $v; $part): ($v | bylabel) as $n | .m as $p | ($r.t | when) as $t
  | .out += [$n | to_entries[] | .key as $s | .value as $e | $e.lines[] | select(. as $x | ($p[$s].lines // []) | any(. == $x) | not)
      | [$t, $r.s[:8], $e.label, $s, "change", .]]
  | if $part then .m = reduce ($n | to_entries[]) as $e ($p; .[$e.key] = {label: $e.value.label,
      lines: ((.[$e.key].lines // []) + $e.value.lines | unique)})
    else .out += [$p | to_entries[] | select($n[.key] == null) | gone($r; .key; .value.label)] | .m = $n | .cur = $v | .stale = false end;
map(select(.k != "x")) | sort_by(.t, .i) | reduce .[] as $r ({cur: null, m: {}, out: []};
  # a Bash write: reported, and the last version is stale until the next whole one; Edits until then count by their patch
  if $r.k == "g" then .out += [[($r.t | when), $r.s[:8], "", "", "gap", $r.c]] | .stale = true
  elif $r.k == "e" then
    .cur as $c | ($r.hunks // []) as $h
    | (if $c != null and (.stale | not) and all($h[]; .pre | join("\n") as $p | $c | contains($p)) then $c | (split($r.old) as $q
        | if ($q | length) < 2 then null elif $r.all then $q | join($r.new) else $q[0] + $r.new + ($q[1:] | join($r.old)) end)
      else null end) as $v
    | if $v != null then seen($r; $v; false)
      else
        # stale, unknown or not fitting it (which makes it stale): the patch's hunks that touch a known entry, their
        # lines before and after it as parts; a line in the first and not the second is one the Edit removed, and an
        # entry all of whose known lines it removed is gone. ponytail: before any entry is known no hunk counts, as one
        # below the entries can't be told apart; the next whole version shows them
        .stale = true | [.m[].lines[]] as $k
        | [$h[] | select(any(.pre[]; startswith("- ") and (.[2:] as $x | $k | index([$x]) != null)))] as $u
        | ("\n" + ([$u[].pre[]] | join("\n"))) as $pre | ("\n" + ([$u[].post[]] | join("\n"))) as $post
        | ($pre | bylabel) as $a | ($post | bylabel) as $b
        | seen($r; $pre; true) | seen($r; $post; true)
        | reduce ($a | to_entries[] | {s: .key, label: .value.label, rm: (.value.lines - ($b[.key].lines // []))}
            | select(.rm != [])) as $d (.;
            (.m[$d.s].lines - $d.rm) as $left
            | if $left == [] and $b[$d.s] == null then .out += [gone($r; $d.s; $d.label)] | .m |= del(.[$d.s])
              else .m[$d.s].lines = $left end) end
  elif $r.k == "b" then seen($r; $r.v; true) | (if .cur == null then .cur = $r.v else . end)
  else seen($r; $r.v; false) end) | .out[] | @tsv

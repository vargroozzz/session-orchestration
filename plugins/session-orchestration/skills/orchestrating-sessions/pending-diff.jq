# pending-versions.jq's records of every transcript (jq -s), diffed in time order: one TSV line per event,
# TIME<TAB>ID8<TAB>LABEL<TAB>SLUG<TAB>change|gone<TAB>LINE (change) or REASON (gone). TIME is local YYYY-MM-DD HH:MM.
# A version cut from Bash output ("b") may be cut short, so it adds and rewords entries but never removes one.
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
map(select(.k != "x")) | sort_by(.t, .i) | reduce .[] as $r ({cur: null, m: {}, out: []};
  (if $r.k == "e" then (if .cur != null then .cur | (split($r.old) as $q | if ($q | length) < 2 then null
      elif $r.all then $q | join($r.new) else $q[0] + $r.new + ($q[1:] | join($r.old)) end)
    else null end) else $r.v end) as $v
  | if $v == null then . else
    ($v | bylabel) as $n | .m as $p | ($r.t | when) as $t
    | .out += [$n | to_entries[] | .key as $s | .value as $e | $e.lines[] | select(. as $x | ($p[$s].lines // []) | any(. == $x) | not)
        | [$t, $r.s[:8], $e.label, $s, "change", .]]
    | if $r.k == "b" then .m = ($p + $n) | (if .cur == null then .cur = $v else . end)
      else .out += [$p | to_entries[] | select($n[.key] == null) | .value.label as $l | [$t, $r.s[:8], $l, .key, "gone", ($turns["\($r.s) \($r.n)"] // "" | reason($l))]]
        | .m = $n | .cur = $v end
    end) | .out[] | @tsv

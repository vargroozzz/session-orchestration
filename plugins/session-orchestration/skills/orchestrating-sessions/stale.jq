# stale.jq: the sweep's Stale section (session-status): queued asks and handoff entries whose facts moved on, and
# sessions asking the user with no ask queued. One line per item, its reasons joined by "; ":
#   ask ID KEY: REASONS            a queued ask (the pane's Cancel)
#   pending "LABEL": REASONS       a handoff entry (the pane's Archive: --pending-done LABEL)
#   session "NAME" (ID8)[ KEY]: decision not on the pane
# A reason starting "recheck:" is age alone: the weakest signal, never a cancel or archive by itself.
# shortcut: age ignores whether the key's row changed since (the design's 7th signal in full); add once it misfires.
# shortcut: PR states come from the rows only, no lookup of a PR no row names; add an adapter call if they're missed.
# jq -nr, every input a string:
#   $asks    the asks store (JSON list; "" none)
#   $entries pending entries, LABEL<TAB>SLUG<TAB>LINE<TAB>LAST (the entry history's last change, YYYY-MM-DD HH:MM)
#   $rows    the tasks, KEY<TAB>STATUS<TAB>TITLE<TAB>EXTRA      $done   keys the tracker says are finished, one a line
#   $gone    8-hex session ids named somewhere and gone (stopped, done or unlisted, with a transcript), one a line
#   $wtgone  worktree paths named somewhere that don't exist    $asking ID8<TAB>NAME<TAB>KEY whose last turn asks the user
#   $keyre   the task key ERE    $now   epoch seconds
def ls($s): $s | split("\n") | map(select(length > 0));
def tsv($s): ls($s) | map(split("\t"));
def keys_in: [scan("(?<![A-Za-z0-9])(" + $keyre + ")(?![0-9])") | .[0]];
def ago($t): ($now | tonumber) - $t;

(try ($asks | fromjson) catch [] | if type == "array" then . else [] end) as $A
| (tsv($rows) | map({key: .[0], status: (.[1] // ""), extra: (.[3] // "")})) as $R
| (ls($done)) as $D | (ls($gone)) as $G | (ls($wtgone)) as $W
# The PR states the rows name: REPO#ID STATE.
| ([$R[].extra | scan("([\\w.-]+)#(\\d+) (OPEN|MERGED|DECLINED|CLOSED)\\b") | {repo: .[0], id: .[1], state: .[2]}]) as $P
| def row($k): first($R[] | select(.key == $k)) // null;
  def open_pr($k): (row($k).extra // "") | test("#\\d+ OPEN\\b");
  # 1. ticket closed: the tracker calls it finished (done, or a done-like status on its row), and no PR of it is open.
  def r_done($k): if $k != null and (($D | index([$k])) or ((row($k).status // "") | test("^(done|released|cancell?ed|closed|resolved)$"; "i")))
    and (open_pr($k) | not) then ["ticket done"] else [] end;
  # 2. PRs settled: every PR the text names (#N, REPO#N) whose state a row shows; a bare #N only when its state is one.
  def r_prs: [scan("(?<![\\w&])([\\w.-]*)#(\\d+)\\b") as [$r, $n]
      | [$P[] | select(.id == $n and ($r == "" or .repo == $r or (.repo | endswith("/" + $r))))] | map(.state) | unique
      | select(length == 1) | {label: (if $r == "" then "#" + $n else $r + "#" + $n end), state: .[0]}] | unique_by(.label)
    | (map(select(.state != "OPEN"))) as $s
    | if ($s | length) == 0 then [] else [(if length > ($s | length) then "reword: " else "" end)
        + ($s | map("\(.label) \(.state | ascii_downcase)") | join(", "))] end;
  # 3. session gone: an 8-hex id the text names that is a session no longer running.
  def r_gone: [scan("\\b[0-9a-f]{8}\\b") | select(. as $i | $G | index([$i]))] | unique
    | if length > 0 then ["names \(join(", ")), gone"] else [] end;
  # 4. worktree gone: a worktree path the text names doesn't exist.
  #    The whole path: .../fix gone doesn't flag a text naming .../fix-ui.
  def r_wt: . as $t | [$W[] | . as $w
    | select([$t | indices($w)[] | $t[. + ($w | length):. + ($w | length) + 1] | test("^[A-Za-z0-9._-]") | not] | any)
    | "worktree \(.) gone"];
  ($A | map(.id)) as $ids
  | [ ($A[] | . as $a | ([.question, .target // ""] | join(" ")) as $t
        | (r_done($a.key) + ($t | r_prs) + ($t | r_gone) + ($t | r_wt)
           + (if ($a.at | type) == "number" and ago($a.at / 1000) > 72 * 3600 then ["recheck: queued over 3d"] else [] end)) as $why
        | select($why | length > 0) | "ask \($a.id) \($a.key): \($why | join("; "))"),
      (tsv($entries)[] | . as [$label, $slug, $line, $last]
        | (($label | keys_in) + ($line | keys_in) | first // null) as $k
        # 5. wrong cross-reference: "ask N", "asks N and M", "pane id N" naming no queued ask. A reword, never an
        #    Archive by itself: prose ("ask 2 reviewers") matches too.
        # shortcut: any "ask N" counts, prose included; tell the two apart if the chip misleads.
        | ([$line | scan("(?i)\\b(?:pane ids?|asks?(?: ids?)?)\\s+#?(\\d+(?:\\s*(?:,|/|and|&)\\s*\\d+)*)") | .[0] | scan("\\d+")]
            | unique | map(select(. as $n | $ids | index([$n]) | not))) as $bad
        # 6. duplicate: its key has a queued ask.
        | ([$A[] | select($k != null and .key == $k) | .id]) as $dup
        | (r_done($k) + ($line | r_prs) + ($line | r_gone) + ($line | r_wt)
           + (if ($bad | length) > 0 then ["reword: names ask \($bad | join(", ")), not queued"] else [] end)
           + (if ($dup | length) > 0 then ["= ask \($dup | join(", "))"] else [] end)
           # A history line without a readable time (hand-edited) skips this reason, not every flag.
           + (if (try (ago($last | strptime("%Y-%m-%d %H:%M") | mktime) > 7 * 86400) catch false)
              then ["recheck: unchanged over 7d"] else [] end)) as $why
        | select($why | length > 0) | "pending \"\($label)\": \($why | join("; "))"),
      # 8. decision not queued: a session asking the user whose key (else name) has no queued ask.
      (tsv($asking)[] | . as [$id, $name, $k]
        | select([$A[] | select(.key == (if ($k // "") != "" then $k else $name end))] | length == 0)
        | "session \"\($name)\" (\($id))\(if ($k // "") != "" then " " + $k else "" end): decision not on the pane")
    ]
  | .[]

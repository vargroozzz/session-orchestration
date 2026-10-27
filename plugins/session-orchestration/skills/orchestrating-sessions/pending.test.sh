#!/usr/bin/env bash
# Self-check for pending: the hook's history and auto-archive, done (exact, prefix, ambiguous, none), history --last
# and --find, notices, yesterday, and --scan/--seed over a fixture transcript (a full Read, an Edit without its
# file, a copy swapped in with mv, a test fixture with the same header elsewhere). Run: bash pending.test.sh
set -euo pipefail; unset XDG_CONFIG_HOME CLAUDE_CODE_SESSION_ID
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; trap 'echo "failed at line $LINENO: $BASH_COMMAND" >&2' ERR
export HOME=$tmp CLAUDE_CONFIG_DIR=$tmp/cfg XDG_CACHE_HOME=$tmp/cache
fail() { echo "pending.test: $*"; exit 1; }
mkroot() {
  local r; r=$(mkdir -p "$tmp/$1/.claude" "$tmp/$1/notes" && cd "$tmp/$1" && pwd -P)
  echo '{"pending": {"file": "notes/pending.md"}}' > "$r/.claude/coordination.local.json"; echo "$r"
}
root=$(mkroot proj); P=$root/notes/pending.md
run() { (cd "$root" && bash "$here/pending" "$@"); }
hook() { printf '{"session_id":"aaaabbbb-1111","cwd":"%s"}' "$root" | bash "$here/pending" hook; }

cat > "$P" <<'EOF'
# Pending

- 2026-10-01 ABC-1 (waits on review): first wording
- 2026-10-02 deploy window: ask ops
- 2026-10-03 ABC-2: something
- 2026-10-03 ABC-3a: one
- 2026-10-03 ABC-3b: two

## Log
- not an entry
EOF
hook
[ "$(grep -c '^- ' "$root/notes/pending/ABC-1.history.md")" = 1 ] && [ ! -f "$root/notes/pending/not-an-entry.history.md" ] ||
  fail "first hook run didn't record the entries"
grep -qF '(aaaabbbb) 2026-10-01 ABC-1 (waits on review): first wording' "$root/notes/pending/ABC-1.history.md" || fail "history line"
hook   # unchanged: nothing more
[ "$(grep -c '^- ' "$root/notes/pending/ABC-1.history.md")" = 1 ] || fail "an unchanged file was recorded again"

# a new wording, a detail file's pointer, an entry gone → archived with reason unknown
printf 'Detail.\nHistory: old\n' > "$root/notes/pending/ABC-1.md"
sed -i.bak -e 's/first wording/second, longer wording/' -e '/ABC-2:/d' "$P"; rm "$P.bak"
hook
[ "$(grep -c '^- ' "$root/notes/pending/ABC-1.history.md")" = 2 ] || fail "a new wording wasn't recorded"
[ "$(tail -1 "$root/notes/pending/ABC-1.md")" = "History: pending/ABC-1.history.md (2 changes, 1 KB)" ] || fail "pointer: $(tail -1 "$root/notes/pending/ABC-1.md")"
grep -q 'resolved: unknown' "$root/notes/pending-archive/ABC-2.history.md" && [ ! -f "$root/notes/pending/ABC-2.history.md" ] ||
  fail "a removed entry wasn't archived"
grep -qE '^- 2026-10-03 → [0-9-]+ [0-9:]+ ABC-2: something · reason: unknown → pending-archive/ABC-2.history.md$' "$root/notes/pending-archive.md" ||
  fail "index line: $(cat "$root/notes/pending-archive.md")"

# done: none, ambiguous, a unique prefix
rc=0; out=$(run done nope -- why) || rc=$?
[ $rc = 2 ] && grep -q 'no entry labelled nope' <<<"$out" || fail "done with no match: $rc $out"
rc=0; out=$(run done ABC-3 -- why) || rc=$?
[ $rc = 2 ] && grep -q 'ABC-3a' <<<"$out" && grep -q 'ABC-3b' <<<"$out" || fail "done ambiguous: $rc $out"
run done deploy -- ops said yes >/dev/null
! grep -q 'deploy window' "$P" && grep -q 'Log' "$P" || fail "done didn't drop the line"
grep -q '(user) resolved: ops said yes' "$root/notes/pending-archive/deploy-window.history.md" || fail "done's history"
[ "$(grep -c '^- ' "$root/notes/pending-archive.md")" = 2 ] && tail -1 "$root/notes/pending-archive.md" | grep -q 'deploy window: ask ops · reason: ops said yes' ||
  fail "done's index: $(cat "$root/notes/pending-archive.md")"
hook   # the hook after done: nothing archived twice
[ "$(grep -c 'resolved:' "$root/notes/pending-archive/deploy-window.history.md")" = 1 ] || fail "archived twice"
# a prefix stops at a word: ABC-3 isn't ABC-30; an entry already archived by the hook says so; a log copy stays
awk '{ print } /ABC-3b:/ { print "- 2026-10-04 ABC-30: thirty" } /^## Log/ { print "- 2026-10-04 ABC-30: thirty" }' "$P" > "$P.n"; mv "$P.n" "$P"
hook; rc=0; out=$(run done ABC-30x -- why) || rc=$?; [ $rc = 2 ] || fail "done ABC-30x"
grep -v 'ABC-3b:' "$P" > "$P.n"; mv "$P.n" "$P"
rc=0; out=$(run done ABC-3b -- why) || rc=$?
[ $rc = 2 ] && grep -q 'archived already' <<<"$out" || fail "done on an entry the hook archived: $rc $out"
run done ABC-30 -- thirty done >/dev/null
[ "$(grep -c 'ABC-30: thirty' "$P")" = 1 ] && sed -n '/^## Log/,$p' "$P" | grep -q 'ABC-30' || fail "done dropped the log's copy"
before=$(ls -l "$root/notes/pending/ABC-1.md"); sleep 1
awk '{ print } NR == 2 { print "- 2026-10-05 ABC-4: new" }' "$P" > "$P.n"; mv "$P.n" "$P"; hook
[ "$(ls -l "$root/notes/pending/ABC-1.md")" = "$before" ] || fail "an unchanged detail file was rewritten"
run done ABC-1 -- reviewed >/dev/null
[ ! -f "$root/notes/pending/ABC-1.md" ] && [ "$(tail -1 "$root/notes/pending-archive/ABC-1.md")" = "History: pending-archive/ABC-1.history.md" ] ||
  fail "detail not archived"

# history
[ "$(run history ABC-1 --last 1)" = "$(printf '# ABC-1: history\n%s' "$(tail -1 "$root/notes/pending-archive/ABC-1.history.md")")" ] || fail "--last"
[ "$(run history --find ABC-3a)" = notes/pending/ABC-3a.history.md ] && [ "$(run history --find ABC-2)" = notes/pending-archive/ABC-2.history.md ] ||
  fail "--find"
[ "$(cd "$root" && bash "$here/session-status" --pending-history --find ABC-2)" = notes/pending-archive/ABC-2.history.md ] ||
  fail "session-status --pending-history"

# notices and yesterday
awk 'BEGIN { for (i = 0; i < 100; i++) print "a line of detail, fifty characters long, near enough" }' > "$root/notes/pending/ABC-3a.md"
grep -q 'notes/pending/ABC-3a.md is 6 KB' <<<"$(run notices)" || fail "notices: $(run notices)"
y=$(run yesterday 0 'ABC-[0-9]+')
[ "$(cut -f1 <<<"$y" | sort | tr '\n' ' ')" = '"deploy window" ABC-1 ABC-2 ABC-3 ABC-30 ' ] && grep -q $'\tresolved from pending: ops said yes$' <<<"$y" ||
  fail "yesterday: $y"
[ -z "$(run yesterday "$(( $(date +%s) + 3600 ))" 'ABC-[0-9]+')" ] || fail "yesterday since later"

# --scan and --seed: a fixture transcript in the project's transcript folder
root=$(mkroot seed); P=$root/notes/pending.md
d=$CLAUDE_CONFIG_DIR/projects/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$root"); mkdir -p "$d"
v1=$'# Pending\n\n- 2026-10-01 OLD-9: will go\n- 2026-10-02 KEEP-1: stays'
v2=$'# Pending\n\n- 2026-10-02 KEEP-1: stays, reworded'
fx=$'# Pending\n\n- 2026-10-02 FIXTURE-1: a test file elsewhere'
{ jq -nc '{type: "user", message: {content: "start"}, timestamp: "2026-10-05T10:00:00Z"}'
  jq -nc --arg f "$P" --arg c "$v1" '{type: "user", message: {content: [{type: "tool_result", tool_use_id: "r1"}]},
    toolUseResult: {file: {filePath: $f, content: $c, numLines: 4, totalLines: 4, startLine: 1}}, timestamp: "2026-10-05T10:01:00Z"}'
  jq -nc --arg c "$fx" '{type: "user", message: {content: [{type: "tool_result", tool_use_id: "r2"}]},
    toolUseResult: {file: {filePath: "/x/test/notes/pending.md.fixture", content: $c, numLines: 3, totalLines: 3, startLine: 1}}, timestamp: "2026-10-05T10:02:00Z"}'
  jq -nc --arg f "$P" '{type: "user", message: {content: [{type: "tool_result", tool_use_id: "e1"}]},
    toolUseResult: {filePath: $f, oldString: "stays", newString: "stays, reworded", originalFile: "", replaceAll: false}, timestamp: "2026-10-05T10:03:00Z"}'
  jq -nc --arg c "$v2" '{type: "user", message: {content: [{type: "tool_result", tool_use_id: "w1"}]},
    toolUseResult: {type: "create", filePath: "/tmp/pending.new", content: $c}, timestamp: "2026-10-05T10:04:00Z"}'
  jq -nc '{type: "assistant", message: {content: [{type: "text", text: "OLD-9 is done, so I removed it."},
    {type: "tool_use", id: "b1", name: "Bash", input: {command: "mv /tmp/pending.new notes/pending.md"}}]}, timestamp: "2026-10-05T10:05:00Z"}'
} > "$d/11112222-aaaa.jsonl"
printf '%s\n\n## Log\n' "$v2" > "$P"
scan=$(run history --scan)
grep -q $'\t11112222\tOLD-9\tOLD-9\tgone\tOLD-9 is done, so I removed it.$' <<<"$scan" || fail "scan's gone event: $scan"
grep -q $'\tKEEP-1\tKEEP-1\tchange\t2026-10-02 KEEP-1: stays, reworded$' <<<"$scan" && ! grep -q FIXTURE <<<"$scan" ||
  fail "scan's change events: $scan"
grep -q 'seeded from transcripts: 1 open' <<<"$(run history --seed)" || fail "seed"
[ "$(grep -c '^- ' "$root/notes/pending/KEEP-1.history.md")" = 2 ] || fail "seeded history: $(cat "$root/notes/pending/KEEP-1.history.md")"
grep -qE '^- 2026-10-01 → 2026-10-05 [0-9:]+ OLD-9: will go · reason: OLD-9 is done, so I removed it\. → pending-archive/OLD-9.history.md$' "$root/notes/pending-archive.md" ||
  fail "seeded index: $(cat "$root/notes/pending-archive.md")"
echo ok

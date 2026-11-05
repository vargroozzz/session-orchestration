#!/usr/bin/env bash
# Self-test for cases and memory-init, under a temp HOME and XDG_STATE_HOME. Prints "ok" or the failures.
set -u
here=$(cd "$(dirname "$0")" && pwd); C=$here/cases M=$here/memory-init
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; T=$(cd "$T" && pwd -P)
export HOME=$T/home XDG_STATE_HOME=$T/state GIT_CONFIG_GLOBAL=$T/home/.gitconfig
mkdir -p "$HOME" "$T/app/sub"
git config --global user.name t; git config --global user.email t@example.org
cd "$T/app" && git init -q && git commit -q --allow-empty -m x || { echo "FAIL git setup"; exit 1; }
fails=0; fail() { echo "FAIL $*"; fails=$((fails + 1)); }
today=$(date +%F)

# cases: the default store is the git root's, from a subfolder and from a worktree outside it.
S=$XDG_STATE_HOME/session-orchestration/feedback-projects/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$T/app")
a=$(cd sub && "$C" add bugfixes 'Dev host sign-in expires hourly' --where login.sh:3 --found 'a task; deploy' --evidence e --suggested 'refresh first')
[[ $a == "$S/bugfixes/$today-dev-host-sign-in-expires-hourly.md" ]] && grep -qx -- "- project: $T/app" "$a" &&
  grep -qx 'suggested: refresh first' "$a" && grep -qx -- '- status: open' "$a" || fail "add: $a $(cat "$a" 2>/dev/null)"
git worktree add -q "$T/wt" 2>/dev/null || fail "worktree setup"
[ "$(cd "$T/wt" && "$C" store)" = "$S" ] || fail "worktree store: $(cd "$T/wt" && "$C" store)"
# Dedup by place, then by two title words; --new overrides.
out=$("$C" add bugfixes Other --where login.sh:3 --found f --evidence e); [ $? = 3 ] && grep -qF "$a" <<<"$out" || fail "dedup by place"
"$C" add features 'Hourly sign-in expiry' --where x --found f --evidence e >/dev/null; [ $? = 3 ] || fail "dedup by words"
b=$("$C" add features 'Hourly sign-in expiry' --where x --found f --evidence e --new) && [ -f "$b" ] || fail "--new"
# Bad input.
"$C" add misc t --where x --found f --evidence e 2>/dev/null; [ $? = 2 ] || fail "bad category"
"$C" add bugfixes t --where x --found f --evidence $'1\n2\n3\n4' 2>/dev/null; [ $? = 2 ] || fail "4-line evidence"
"$C" add bugfixes t --where x --found f --evidence e --suggested $'x\n- status: dropped' 2>/dev/null; [ $? = 2 ] || fail "newline in --suggested"
# seen, list, count, mark.
"$C" seen "$b"; "$C" seen "$b"; sed -i.bak "s/^- seen: .*/- seen: 2026-01-01, $today/" "$b" && rm -f "$b.bak"
[ "$("$C" list | head -1 | cut -f3)" = "$b" ] || fail "list order: $("$C" list)"
[ "$("$C" count)" = "2 open (1 seen ≥2×)" ] || fail "count: $("$C" count)"
"$C" mark "$a" fixed 'the login doc says to refresh first' && "$C" mark "$b" dropped
grep -qx -- '- status: fixed the login doc says to refresh first' "$a" || fail "mark: $(grep status "$a")"
[ -z "$("$C" count)" ] && [ "$("$C" list --all | wc -l | tr -d ' ')" = 2 ] || fail "after mark"
# --store and --origin.
o=$("$C" --store "$T/s2" --origin 'plugin: 1.2.3' add refactorings 'Split it' --where lib.sh --found f --evidence e)
[[ $o == "$T/s2/refactorings/"* ]] && grep -qx -- '- plugin: 1.2.3' "$o" || fail "--store/--origin: $o"
# A session-orchestration root above the repo wins over the git root.
mkdir -p "$T/ws/.claude" "$T/ws/repo" && echo '{}' > "$T/ws/.claude/coordination.local.json"
[ "$(cd "$T/ws/repo" && "$C" store)" = "$XDG_STATE_HOME/session-orchestration/feedback-projects/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$T/ws")" ] ||
  fail "coordinated root: $(cd "$T/ws/repo" && "$C" store)"
# ... also from a worktree outside it (the main checkout's set-up folder); root names it.
(cd "$T/ws/repo" && git init -q && git commit -q --allow-empty -m x && git worktree add -q "$T/wt2" 2>/dev/null) || fail "worktree 2 setup"
[ "$(cd "$T/wt2" && "$C" root)" = "$T/ws" ] || fail "worktree of a set-up repo: $(cd "$T/wt2" && "$C" root)"

# memory-init: the index with a row per topic and misc last, a topic file each; a dry run writes nothing; existing
# files are kept.
d=$("$M" docs/mem --dry-run --topic deploys.md deploys 'deploying or touching CI')
[ "$d" = $'docs/mem/memory.md\ndocs/mem/memory/deploys.md\ndocs/mem/memory/misc.md' ] && [ ! -e docs ] || fail "dry run: $d"
w=$("$M" docs/mem --topic deploys.md deploys 'deploying or touching CI'); [ "$w" = "$d" ] || fail "write: $w"
grep -qxF '| `deploys.md` | Deploying or touching CI |' docs/mem/memory.md && grep -qxF '| `misc.md` | Nothing above fits |' docs/mem/memory.md &&
  grep -qF "projects/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$T/app")*/" docs/mem/memory.md && ! grep -q '{{' docs/mem/memory.md ||
  fail "index: $(cat docs/mem/memory.md)"
grep -qxF '# Memory: deploys' docs/mem/memory/deploys.md && grep -qxF '> **Read when**: deploying or touching CI.' docs/mem/memory/deploys.md ||
  fail "topic: $(cat docs/mem/memory/deploys.md)"
echo '- 2026-01-01 X: keep' >> docs/mem/memory/misc.md
[ -z "$("$M" docs/mem)" ] && grep -q keep docs/mem/memory/misc.md || fail "existing files rewritten"
# A topic new to an existing index: its file, and its row after the table's last row (a dry run only says so); an &
# stays literal (bash 5.2's patsub_replacement); --root sets the transcripts grep.
d=$("$M" docs/mem --dry-run --topic ci.md 'build & ship' 'touching CI \ & deploys')
[ "$d" = $'docs/mem/memory/ci.md\ndocs/mem/memory.md (row: ci.md)' ] && [ ! -e docs/mem/memory/ci.md ] || fail "dry run, new topic: $d"
w=$("$M" docs/mem --topic ci.md 'build & ship' 'touching CI \ & deploys'); [ "$w" = "$d" ] || fail "new topic: $w"
[ "$(grep -A1 -F '| `misc.md` |' docs/mem/memory.md | tail -1)" = '| `ci.md` | Touching CI \ & deploys |' ] &&
  grep -qxF '# Memory: build & ship' docs/mem/memory/ci.md && [ -z "$("$M" docs/mem --topic ci.md a b)" ] &&
  [ "$(grep -c 'ci\.md' docs/mem/memory.md)" = 1 ] || fail "new topic row: $(cat docs/mem/memory.md docs/mem/memory/ci.md)"
"$M" r/mem --root /w/x >/dev/null && grep -qF 'projects/-w-x*/' r/mem/memory.md || fail "--root"
"$M" docs/mem --topic misc.md a b 2>/dev/null; [ $? = 2 ] || fail "misc.md as a --topic"
"$M" docs/mem --topic ../x.md a b 2>/dev/null; [ $? = 2 ] || fail "a path as a --topic"

[ "$fails" = 0 ] && echo ok || { echo "$fails failed"; exit 1; }

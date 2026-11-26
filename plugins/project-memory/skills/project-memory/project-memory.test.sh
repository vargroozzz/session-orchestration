#!/usr/bin/env bash
# Self-test for cases, skill-drafts and memory-init, under a temp HOME and XDG_STATE_HOME. Prints "ok" or the failures.
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
c=$("$C" add --new features 'Hourly sign-in expiry' --where x --found f --evidence e) && [ -f "$c" ] || fail "--new before the category"; rm -f "$c"
d=$("$C" add features --new 'Hourly sign-in expiry' --where x --found f --evidence e) && [ -f "$d" ] || fail "--new before the title"; rm -f "$d"
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
[ "$(cd "$T/ws/repo" && "$C" tasks)" = "$XDG_STATE_HOME/session-orchestration/projects/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$T/ws")/tasks" ] ||
  fail "tasks: $(cd "$T/ws/repo" && "$C" tasks)"
# ... also from a worktree outside it (the main checkout's set-up folder); root names it.
(cd "$T/ws/repo" && git init -q && git commit -q --allow-empty -m x && git worktree add -q "$T/wt2" 2>/dev/null) || fail "worktree 2 setup"
[ "$(cd "$T/wt2" && "$C" root)" = "$T/ws" ] || fail "worktree of a set-up repo: $(cd "$T/wt2" && "$C" root)"

# skill-drafts: a draft lands beside the tasks folder, named by its frontmatter; a taken or bad name is refused;
# sightings count; sweep archives the unused and restore brings one back; a scrub hit blocks promote, which copies the
# draft without its seen file and archives it.
unset SCRUB_DENY; export XDG_CONFIG_HOME=$T/config   # no real deny pattern
SD=$here/skill-drafts D=$XDG_STATE_HOME/session-orchestration/projects/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$T/app")/skill-drafts
printf -- '---\nname: cut-release\ndescription: Use when cutting a release\n---\n\n1. Tag it.\n2. Push the tag.\n3. Announce it.\n' > "$T/d.md"
p=$("$SD" add "$T/d.md" PROJ-1) && [ "$p" = "$D/cut-release/SKILL.md" ] && cmp -s "$T/d.md" "$p" || fail "drafts add: $p"
"$SD" add "$T/d.md" PROJ-2 2>/dev/null; [ $? = 3 ] || fail "drafts add, a taken name"
printf -- '---\nname: ../x\ndescription: d\n---\n' > "$T/bad.md"; "$SD" add "$T/bad.md" PROJ-2 2>/dev/null; [ $? = 2 ] || fail "drafts add, a path as a name"
printf -- '---\nname: folded\ndescription: >-\n  d\n---\n' > "$T/bad.md"; "$SD" add "$T/bad.md" PROJ-2 2>/dev/null; [ $? = 2 ] || fail "drafts add, a folded description"
"$SD" seen cut-release PROJ-2 && "$SD" seen cut-release PROJ-2
[ "$("$SD" list)" = "2"$'\t'"$today"$'\t'"$p"$'\t''Use when cutting a release' ] || fail "drafts list: $("$SD" list)"
printf -- '---\nname: old-one\ndescription: x\n---\n' > "$T/o.md" && "$SD" add "$T/o.md" PROJ-3 >/dev/null && echo '2026-01-01 PROJ-3' > "$D/old-one/seen"
[ "$("$SD" sweep)" = old-one ] && [ "$("$SD" list | cut -f3)" = "$p" ] && [ "$("$SD" list --archived | cut -f3)" = "$D/archive/old-one/SKILL.md" ] ||
  fail "drafts sweep: $("$SD" list --archived)"
"$SD" restore old-one && [ -f "$D/old-one/SKILL.md" ] && [ -z "$("$SD" sweep)" ] && [ "$("$SD" list | grep old-one | cut -f1)" = 1 ] ||
  fail "drafts restore: $("$SD" list)"
# A draft with no sighting: - for its last seen, and sweep archives that one (a / in its description is no path).
printf -- '---\nname: never-seen\ndescription: deploys/staging steps\n---\n' > "$T/n.md" && "$SD" add "$T/n.md" PROJ-4 >/dev/null && : > "$D/never-seen/seen"
[ "$("$SD" list | grep never-seen | cut -f1,2)" = "0"$'\t''-' ] && [ "$("$SD" sweep 2>&1)" = never-seen ] && [ -d "$D/archive/never-seen" ] ||
  fail "sweep, a draft never seen: $("$SD" list --archived)"
echo "Run it from $HOME/app." >> "$p"
"$SD" promote cut-release "$T/app/.claude/skills" >/dev/null 2>&1; [ $? = 1 ] && [ ! -e "$T/app/.claude/skills" ] || fail "promote past a scrub hit"
sed -i.bak '$d' "$p" && rm -f "$p.bak"
echo 'Ask Acme first.' >> "$D/old-one/SKILL.md"; SCRUB_DENY='acme' "$SD" scrub old-one >/dev/null; [ $? = 1 ] || fail "scrub, SCRUB_DENY"
# A deny pattern grep can't read fails the scrub, and promote with it.
SCRUB_DENY='hi(' "$SD" promote cut-release "$T/app/.claude/skills" >/dev/null 2>&1; [ $? = 2 ] && [ ! -e "$T/app/.claude/skills" ] || fail "promote, a bad deny pattern"
s=$("$SD" promote cut-release "$T/app/.claude/skills") && [ "$s" = "$T/app/.claude/skills/cut-release/SKILL.md" ] && cmp -s "$T/d.md" "$s" &&
  [ ! -e "$T/app/.claude/skills/cut-release/seen" ] && [ ! -e "$D/cut-release" ] && grep -q 'promoted to' "$D/archive/cut-release/seen" || fail "promote: $s"

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
# A flat index (no table, an older setup's): the new rows go under a table header of their own at its end.
mkdir -p flat && printf '# Memory\n\n- 2026-01-01 X: a flat entry\n' > flat/memory.md
"$M" flat >/dev/null && [ "$(tail -4 flat/memory.md)" = "$(printf '\n| Topic file (`memory/`) | Read when |\n|---|---|\n| `misc.md` | Nothing above fits |')" ] &&
  "$M" flat --topic ci.md ci 'touching CI' >/dev/null && [ "$(tail -1 flat/memory.md)" = '| `ci.md` | Touching CI |' ] &&
  [ "$(grep -c '^| Topic file' flat/memory.md)" = 1 ] && grep -qxF -- '- 2026-01-01 X: a flat entry' flat/memory.md || fail "flat index: $(cat flat/memory.md)"
"$M" r/mem --root /w/x >/dev/null && grep -qF 'projects/-w-x*/' r/mem/memory.md || fail "--root"
"$M" docs/mem --topic misc.md a b 2>/dev/null; [ $? = 2 ] || fail "misc.md as a --topic"
"$M" docs/mem --topic ../x.md a b 2>/dev/null; [ $? = 2 ] || fail "a path as a --topic"

# unused memory: an entry past --stale with no assistant line citing it in the window is listed (archive past
# --archive); a recent citation, a new entry, a user line and a word every session has don't count.
U=$here/unused; mkdir -p um/memory tr
printf '# Memory\n\n- 2026-01-01 T0: index entry `cited.sh` here\n' > um/memory.md
printf '%s\n' '# Memory: misc' '- 2026-01-01 T1: run `foo-bar.sh "x"` first' '- 2026-01-01 T2: the dev_db resets nightly' \
  '- 2026-01-25 T3: plain words only here' '- 2026-02-10 T4: new entry x_y' '- 2026-01-01 T5: uses x_common' \
  '- 2026-01-01 T6: [team] the `café→bar` map' '- 2026-01-01 T7: the `edit_only` rule' > um/memory/misc.md
printf '%s\n' '{"message":{"role":"assistant","content":"ran foo-bar.sh \"x\" and cited.sh"}}' \
  '{"message":{"role":"user","content":"dev_db"}}' \
  '{"message":{"role":"assistant","content":[{"type":"text","text":"the café→bar map"}]}}' \
  '{"message":{"role":"assistant","content":[{"type":"tool_use","input":{"file_path":"/m/memory/misc.md","old_string":"edit_only"}}]}}' > tr/s1.jsonl
for i in 2 3 4 5 6 7 8 9; do echo '{"message":{"role":"assistant","content":"x_common"}}' > tr/s$i.jsonl; done
echo '{"message":{"role":"assistant","content":"plain words only here"}}' > tr/old.jsonl
touch -t 202602100000 tr/s*.jsonl; touch -t 202512010000 tr/old.jsonl
out=$("$U" memory um/memory.md --today 2026-02-15 --transcripts "$T/app/tr/*.jsonl" | cut -f1-3)
[ "$out" = $'archive\t45\t'"$T/app/um/memory/misc.md:3"$'\narchive\t45\t'"$T/app/um/memory/misc.md:8"$'\nstale\t21\t'"$T/app/um/memory/misc.md:4" ] ||
  fail "unused memory: $out"
"$U" memory um/memory.md --today 2026-02-15 --transcripts "$T/app/none/*.jsonl" >/dev/null 2>&1; [ $? = 1 ] || fail "no transcripts"
[ "$("$U" cited dev_db foo-bar.sh --days 10 --today 2026-02-15 --transcripts "$T/app/tr/*.jsonl")" = $'0\t-\tdev_db\n1\t5\tfoo-bar.sh' ] ||
  fail "unused cited: $("$U" cited dev_db foo-bar.sh --days 10 --today 2026-02-15 --transcripts "$T/app/tr/*.jsonl")"
# archive and restore: a line to archive/NAME and back to the end, a folder to archive/ and back; nothing is lost.
l='- 2026-01-01 T2: the dev_db resets nightly'
[ "$("$U" archive um/memory/misc.md "$l")" = "$T/app/um/memory/archive/misc.md" ] && ! grep -qxF -- "$l" um/memory/misc.md &&
  grep -qxF -- "$l" um/memory/archive/misc.md && [ "$(wc -l < um/memory/misc.md | tr -d ' ')" = 7 ] || fail "archive line"
"$U" restore um/memory/misc.md "$l" >/dev/null && [ "$(tail -1 um/memory/misc.md)" = "$l" ] && [ ! -s um/memory/archive/misc.md ] ||
  fail "restore line"
"$U" archive um/memory/misc.md 'no such line' 2>/dev/null; [ $? = 1 ] || fail "archive a missing line"
mkdir -p drafts/one && echo x > drafts/one/SKILL.md && "$U" archive drafts/one >/dev/null && [ -f drafts/archive/one/SKILL.md ] &&
  [ ! -e drafts/one ] && "$U" restore drafts/one >/dev/null && [ -f drafts/one/SKILL.md ] || fail "archive and restore a folder"
mkdir -p drafts/archive/one && "$U" archive drafts/one 2>/dev/null; [ $? = 2 ] && [ -d drafts/one ] || fail "archive over an archived one"

[ "$fails" = 0 ] && echo ok || { echo "$fails failed"; exit 1; }

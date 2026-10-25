#!/usr/bin/env bash
# feedback's self-test, under a temp HOME and XDG_STATE_HOME (`claude` and `gh` stubbed). Prints "ok" or the failures.
set -u
FB=$(cd "$(dirname "$0")" && pwd)/feedback
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/bin" "$T/acme-widgets/.claude" "$T/plugin-clone"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/claude"
printf '#!/bin/sh\nexit "${GH_RC:-1}"\n' > "$T/bin/gh"; chmod +x "$T/bin/claude" "$T/bin/gh"
export HOME=$T/home XDG_STATE_HOME=$T/state PATH=$T/bin:$PATH
export GIT_CONFIG_GLOBAL=$T/home/.gitconfig   # it outranks HOME: never touch the real one
unset XDG_CONFIG_HOME CLAUDE_CONFIG_DIR
git config --global user.name 'Pat Doe'; git config --global user.email pat@example.org
cd "$T/acme-widgets" && git init -q || { echo "FAIL git init"; exit 1; }
D=$XDG_STATE_HOME/session-orchestration/feedback
fails=0
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
today=$(date +%F)

a=$("$FB" add bugfixes 'Status exits when the adapter prints nothing' --where skills/x/session-status:206 \
  --found 'coordinating; a status sweep' --evidence 'empty line, status failed' --suggested 'treat it as none')
[ -f "$a" ] && [[ $a == "$D/bugfixes/$today-status-exits-when-the-adapter-prints-nothing.md" ]] || fail "add: $a"
grep -qx -- '- status: open' "$a" && grep -qx -- "- seen: $today" "$a" && grep -qx 'suggested: treat it as none' "$a" || fail "case body: $(cat "$a")"

# Dedup: the same place, the same file and a title word, or two title words; the plugin's own names don't count.
out=$("$FB" add bugfixes 'Other thing' --where skills/x/session-status:206 --found f --evidence e); rc=$?
[ "$rc" = 3 ] && grep -qF "$a" <<<"$out" || fail "dedup by place: rc=$rc $out"
"$FB" add bugfixes 'The adapter times out' --where skills/x/session-status:9 --found f --evidence e >/dev/null; rc=$?
[ "$rc" = 3 ] || fail "dedup by file and word: rc=$rc"
o=$("$FB" add bugfixes 'session-status sessions plugin when' --where skills/x/session-status:9 --found f --evidence e); rc=$?
[ "$rc" = 0 ] && rm -f "$o" || fail "dedup on the plugin's own names: rc=$rc"
"$FB" add features 'Adapter prints nothing useful' --where lib.sh --found f --evidence e >/dev/null; rc=$?
[ "$rc" = 3 ] || fail "dedup by title words: rc=$rc"
b=$("$FB" add features 'Adapter prints nothing useful' --where lib.sh --found f --evidence e --new) && [ -f "$b" ] || fail "--new: $b"

"$FB" add bugfixes t --where /abs/path --found f --evidence e 2>/dev/null; [ $? = 2 ] || fail "absolute --where accepted"
"$FB" add bugfixes t --where x --found f --evidence $'1\n2\n3\n4' 2>/dev/null; [ $? = 2 ] || fail "4-line evidence accepted"
"$FB" add misc t --where x --found f --evidence e 2>/dev/null; [ $? = 2 ] || fail "bad category accepted"
"$FB" add bugfixes t --found f --evidence e --where 2>/dev/null; [ $? = 2 ] || fail "a flag without its value"
"$FB" add bugfixes t --where x --found f --evidence e --suggested $'x\n- status: dropped' 2>/dev/null; [ $? = 2 ] || fail "a newline in --suggested"

# seen: once a day; list sorts by it; count.
"$FB" seen "$b"; "$FB" seen "$b"
[ "$(grep -c "$today" <<<"$(grep '^- seen:' "$b")")" = 1 ] || fail "seen twice in a day: $(grep seen "$b")"
sed -i.bak "s/^- seen: .*/- seen: 2026-01-01, $today/" "$b" && rm -f "$b.bak"
[ "$(cut -f3 <<<"$("$FB" list)" | head -1)" = "$b" ] || fail "list order: $("$FB" list)"
[ "$("$FB" count)" = "2 open (1 seen ≥2×)" ] || fail "count: $("$FB" count)"

# footer: once a day.
f1=$("$FB" footer); f2=$("$FB" footer)
[[ $f1 == "plugin feedback: 2 open (1 seen ≥2×)"* ]] && [ -z "$f2" ] || fail "footer: '$f1' then '$f2'"
echo 2026-01-01 > "$D/.footer-shown"; [ -n "$("$FB" footer)" ] || fail "footer not shown on a new day"

# mark; count and footer go quiet with nothing open.
"$FB" mark "$a" sent 'https://github.com/o/r/issues/1#c-2&x=1' && "$FB" mark "$b" dropped
grep -qxF -- '- status: sent https://github.com/o/r/issues/1#c-2&x=1' "$a" || fail "mark sent: $(grep status "$a")"
[ -z "$("$FB" count)" ] && [ -z "$("$FB" list)" ] && [ "$("$FB" list --all | wc -l | tr -d ' ')" = 2 ] || fail "after mark: count/list"
rm -f "$D/.footer-shown"; [ -z "$("$FB" footer)" ] || fail "footer with nothing open"

# mode: config, then repo_dir, then gh.
[ "$("$FB" mode)" = issue ] || fail "mode without gh: $("$FB" mode)"
[ "$(GH_RC=0 "$FB" mode)" = fork-pr ] || fail "mode with gh: $(GH_RC=0 "$FB" mode)"
echo "{\"feedback\": {\"repo_dir\": \"$T/plugin-clone\"}}" > .claude/coordination.local.json
[ "$("$FB" mode)" = pr ] || fail "mode with repo_dir: $("$FB" mode)"
echo '{"feedback": {"mode": "local", "repo_dir": "~/nowhere"}}' > .claude/coordination.local.json
[ "$("$FB" mode)" = local ] || fail "mode from config: $("$FB" mode)"
[[ $("$FB" repo) =~ ^[^/]+/[^/]+$ ]] || fail "repo: $("$FB" repo)"
[ "$("$FB" label)" = todo ] || fail "label: $("$FB" label)"

# scrub: a clean case passes; each kind of hit is caught.
echo '{"key_pattern": "WID-[0-9]+"}' > .claude/coordination.local.json
clean=$(GH_RC=0 "$FB" add refactorings 'Split the sweep' --where lib.sh --found 'a task session; status' \
  --evidence $'config runs twice; ~/.cache/session-status/x.last stays\nsee https://github.com/'"$("$FB" repo)"'/issues/1' --new)
out=$("$FB" scrub "$clean"); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] || fail "clean case flagged: $out"
dirty=$T/dirty.md
# One kind per line: scrub names one reason per line.
printf '%s\n' '# x' '- evidence: /opt/data/notes.txt' '- by sam@other.example' '- in acme-widgets' '- see WID-42' \
  '- https://intranet.example.net/x' '- id 0123456789abcdef0123' '```' "make_widgets_$$ --nightly" '```' > "$dirty"   # built here: this file is plugin code
out=$("$FB" scrub "$dirty"); rc=$?
[ "$rc" = 1 ] || fail "dirty case passed (rc=$rc)"
for why in 'an absolute path' 'an email address' 'names a local name' 'a task key' "a URL other than the plugin's" 'a long hex string' 'code not from the plugin'; do
  grep -qF ": $why:" <<<"$out" || fail "scrub missed: $why"
done
# The default task key, with no key_pattern anywhere.
rm .claude/coordination.local.json; printf '# x\n- broke on ABC-4654 rows\n' > "$dirty"
grep -qF ': a task key:' <<<"$("$FB" scrub "$dirty")" || fail "scrub missed the default task key"
printf '# x\n- Pat saw it fail\n' > "$dirty"
grep -qF ': names a local name:' <<<"$("$FB" scrub "$dirty")" || fail "scrub missed a part of the name"
# A case added in another project keeps that project on the deny list once its sessions are gone.
mkdir -p "$T/other-proj/.claude" && echo '{}' > "$T/other-proj/.claude/coordination.local.json"
(cd "$T/other-proj" && "$FB" add features 'Привіт' --where lib.sh --found f --evidence e --new) | grep -q -- '-case\.md$' || fail "empty slug"
printf '# x\n- in other-proj\n' > "$dirty"
grep -qF ': names a local name:' <<<"$("$FB" scrub "$dirty")" || fail "scrub missed a project a case was added in"

[ "$fails" = 0 ] && echo ok || { echo "$fails failed"; exit 1; }

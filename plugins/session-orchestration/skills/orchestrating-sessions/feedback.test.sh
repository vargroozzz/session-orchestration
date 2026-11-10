#!/usr/bin/env bash
# feedback's self-test, under a temp HOME and XDG_STATE_HOME (`claude` and `gh` stubbed). Prints "ok" or the failures.
set -u
FB=$(cd "$(dirname "$0")" && pwd)/feedback
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/bin" "$T/acme-widgets/.claude" "$T/plugin-clone"
printf '#!/bin/sh\n[ "$1" != agents ] || echo "${AGENTS_JSON:-[]}"\n' > "$T/bin/claude"
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
# The person-wide file counts in every project; the project's person file outranks it.
mkdir -p "$HOME/.config/session-orchestration"
echo "{\"feedback\": {\"mode\": \"issue\", \"repo_dir\": \"$T/plugin-clone\"}}" > "$HOME/.config/session-orchestration/config.json"
[ "$("$FB" mode)" = local ] || fail "project file under the person-wide one: $("$FB" mode)"
echo '{}' > .claude/coordination.local.json
[ "$("$FB" mode)" = issue ] || fail "mode from the person-wide file: $("$FB" mode)"
rm "$HOME/.config/session-orchestration/config.json"
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
# Project cases: this project's own store, any --where, deduped within it; list, count and footer show both scopes.
P=$XDG_STATE_HOME/session-orchestration/feedback-projects/$(pwd -P | sed 's/[^A-Za-z0-9]/-/g')
pc=$("$FB" add features 'Sign-in to the dev host expires hourly' --where /opt/x/login.sh --found 'a task session; deploy' --evidence e --project)
[[ $pc == "$P/features/$today-sign-in-to-the-dev-host-expires-hourly.md" ]] && grep -qx -- "- project: $(pwd -P)" "$pc" &&
  ! grep -q '^- plugin:' "$pc" || fail "project add: $pc"
"$FB" add features 'Sign-in to the dev host expires hourly' --where x --found f --evidence e --project >/dev/null; [ $? = 3 ] || fail "project dedup"
[ "$("$FB" list --project | cut -f3)" = "$pc" ] && [ "$("$FB" list --plugin | cut -f3)" = "$clean" ] &&
  [ "$("$FB" list | wc -l | tr -d ' ')" = 2 ] || fail "list scopes: $("$FB" list)"
[ "$("$FB" count)" = "1 open (0 seen ≥2×); project: 1 open (0 seen ≥2×)" ] || fail "count both: $("$FB" count)"
rm -f "$D/.footer-shown"
[ "$("$FB" footer)" = "plugin feedback: 1 open (0 seen ≥2×) — apply? (feedback.md) · project feedback: 1 open (0 seen ≥2×), for the next R&D run" ] ||
  fail "footer both: $(rm -f "$D/.footer-shown" "$P/.footer-shown"; "$FB" footer)"
# Each part once a day: the project's stamp is its own, so another project's footer doesn't hide it.
rm -f "$P/.footer-shown"
[ "$("$FB" footer)" = "project feedback: 1 open (0 seen ≥2×), for the next R&D run" ] || fail "project footer stamp: $("$FB" footer)"
[ -z "$("$FB" footer)" ] || fail "project footer twice"
"$FB" mark "$pc" fixed 'the login doc says to refresh first' && grep -qx -- '- status: fixed the login doc says to refresh first' "$pc" &&
  [ -z "$("$FB" count --project)" ] && [ "$("$FB" count)" = "1 open (0 seen ≥2×)" ] || fail "mark fixed: $(grep status "$pc")"
echo '{"feedback": {"project_dir": ".fb"}}' > .claude/coordination.local.json
q=$("$FB" add bugfixes 'Deploy script needs a flag' --where deploy.sh --found f --evidence e --project)
[[ $q == "$(pwd -P)/.fb/bugfixes/"* ]] || fail "feedback.project_dir: $q"
rm .claude/coordination.local.json

# The plugin coordinator (feedback.repo_dir's root): `coordinator` names it while it runs; another root's footer shows
# the plugin's cases only while it doesn't, its own root's as before.
"$FB" coordinator 2>/dev/null; [ $? = 2 ] || fail "coordinator with no repo_dir"
mkdir -p "$T/plugin-clone/.claude" "$HOME/.config/session-orchestration" && echo '{}' > "$T/plugin-clone/.claude/coordination.local.json"
echo "{\"feedback\": {\"repo_dir\": \"$T/plugin-clone\"}}" > "$HOME/.config/session-orchestration/config.json"
R=$(cd "$T/plugin-clone" && pwd -P)
agent() { export AGENTS_JSON="[{\"sessionId\":\"s1\",\"name\":\"plugin-clone-coordinator\",\"state\":\"$1\",\"cwd\":\"$R\"}]"; }
agent done; out=$("$FB" coordinator 2>&1); rc=$?
[ "$rc" = 1 ] && [[ $out == *"(plugin-clone-coordinator) isn't running"* ]] || fail "coordinator not running: rc=$rc $out"
out=$("$FB" coordinator --start); rc=$?
[ "$rc" = 1 ] && [ "$out" = "no terminal opens it here (config terminal): run in a new terminal: cd $(printf %q "$R") && claude -n plugin-clone-coordinator 'Act as a coordinator'" ] ||
  fail "coordinator --start, plain terminal: rc=$rc $out"
# The plugin coordinator's own footer has its own stamp, so it doesn't hide the offer elsewhere.
rm -f "$D/.footer-shown"; [ -n "$(cd "$T/plugin-clone" && "$FB" footer)" ] || fail "footer in the plugin coordinator's root, first"
[ "$("$FB" footer)" = "plugin feedback: 1 open (0 seen ≥2×), for the plugin coordinator, which isn't running — start it? (feedback coordinator --start)" ] ||
  fail "footer, plugin coordinator not running: $(rm -f "$D/.footer-elsewhere"; "$FB" footer)"
# A failed listing is no answer: exit 3, and no footer or stamp.
rm -f "$D/.footer-elsewhere"; AGENTS_JSON=garbled "$FB" coordinator 2>/dev/null; [ $? = 3 ] || fail "coordinator with a failed listing"
[ -z "$(AGENTS_JSON=garbled "$FB" footer)" ] && [ ! -e "$D/.footer-elsewhere" ] || fail "footer with a failed listing"
agent blocked
[ "$("$FB" coordinator)" = plugin-clone-coordinator ] || fail "coordinator running: $("$FB" coordinator 2>&1)"
[ -z "$("$FB" footer)" ] && [ "$(cat "$D/.footer-elsewhere")" = "$(date '+%F %H')" ] || fail "footer with the plugin coordinator running"
rm -f "$D/.footer-shown"
[ "$(cd "$T/plugin-clone" && "$FB" footer)" = "plugin feedback: 1 open (0 seen ≥2×) — apply? (feedback.md)" ] || fail "footer in the plugin coordinator's root"
unset AGENTS_JSON; rm "$HOME/.config/session-orchestration/config.json" "$T/plugin-clone/.claude/coordination.local.json"
# A git worktree outside the project files into the main checkout's store.
git commit -q --allow-empty -m x && git worktree add -q "$T/wt-out" 2>/dev/null || fail "worktree setup"
w=$(cd "$T/wt-out" && "$FB" add bugfixes 'Worktree case' --where x --found f --evidence e --project)
[[ $w == "$P/bugfixes/"* ]] || fail "worktree outside the project: $w"

# A case added in another project keeps that project on the deny list once its sessions are gone.
mkdir -p "$T/other-proj/.claude" && echo '{}' > "$T/other-proj/.claude/coordination.local.json"
(cd "$T/other-proj" && "$FB" add features 'Привіт' --where lib.sh --found f --evidence e --new) | grep -q -- '-case\.md$' || fail "empty slug"
printf '# x\n- in other-proj\n' > "$dirty"
grep -qF ': names a local name:' <<<"$("$FB" scrub "$dirty")" || fail "scrub missed a project a case was added in"

# usage (lib.sh): nothing with telemetry off (the default); with local, fixed names only.
U=$XDG_STATE_HOME/session-orchestration/usage.jsonl LIB=${FB%/skills/*}/lib.sh
use() { (cd "$T/other-proj" && bash -c '. "$0" && usage "$@"' "$LIB" "$@"); }
use peek press; [ ! -e "$U" ] || fail "usage logged with telemetry off"
echo '{"telemetry": "local"}' > "$T/other-proj/.claude/coordination.local.json"
use peek press; use 'PROJ-1 /x' press; use fallback; use peek bogus
[ "$(wc -l < "$U" | tr -d ' ')" = 2 ] && grep -q '"k":"press","what":"peek"}$' "$U" && grep -q '"k":"path","what":"fallback"}$' "$U" ||
  fail "usage log: $(cat "$U")"

# pm_dir: the sibling in a checkout; else the installed copy installed_plugins.json names; else a failure.
[ "$(bash -c '. "$0" && pm_dir' "$LIB")" = "$(cd "${LIB%/*}/../project-memory" && pwd)" ] || fail "pm_dir sibling"
# Only a copy with the scripts counts, and this marketplace's beats another's (listed last or not).
mkdir -p "$T/inst/so" "$T/inst/pm-1.0/skills/project-memory" "$T/inst/other/skills/project-memory" "$T/inst/old" "$HOME/.claude/plugins" &&
  cp "$LIB" "$T/inst/so/lib.sh" && touch "$T/inst/pm-1.0/skills/project-memory/cases" "$T/inst/other/skills/project-memory/cases" &&
  chmod +x "$T/inst/pm-1.0/skills/project-memory/cases" "$T/inst/other/skills/project-memory/cases"
jq -nc --arg p "$T/inst/pm-1.0" --arg o "$T/inst/other" --arg x "$T/inst/old" \
  '{plugins: {"project-memory@session-orchestration": [{installPath: "/gone"}, {installPath: $p}, {installPath: $x}], "project-memory@zz": [{installPath: $o}]}}' > "$HOME/.claude/plugins/installed_plugins.json"
[ "$(bash -c '. "$0" && pm_dir' "$T/inst/so/lib.sh")" = "$T/inst/pm-1.0" ] || fail "pm_dir installed: $(bash -c '. "$0" && pm_dir' "$T/inst/so/lib.sh" 2>&1)"
rm "$HOME/.claude/plugins/installed_plugins.json"
bash -c '. "$0" && pm_dir' "$T/inst/so/lib.sh" 2>/dev/null && fail "pm_dir with no copy"

# A messages module named only in the person-wide file still has its block dropped from the repo file.
mkdir -p "$HOME/.config/session-orchestration" "$T/other-proj/.claude/coordination"
echo '{"messages": "slack"}' > "$HOME/.config/session-orchestration/config.json"
echo '{"slack": {"cmd": "evil"}, "tracker": "none"}' > "$T/other-proj/.claude/coordination/coordination.json"
j=$(cd "$T/other-proj" && bash -c '. "$0" && coord_json' "$LIB")
[ "$(jq -c '[.slack, .tracker]' <<<"$j")" = '[null,"none"]' ] || fail "repo file's module block kept: $j"

[ "$fails" = 0 ] && echo ok || { echo "$fails failed"; exit 1; }

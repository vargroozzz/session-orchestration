#!/usr/bin/env bash
# Self-check for session-status without an adapter: a throwaway repo with one worktree, a worker and a coordinator
# transcript, and a stubbed `claude agents`. Also --coordinator, --watch, an adapter's notices in --changes, and
# --changes skipping a session that only started working. Run: bash session-status.test.sh  (prints "ok" or the diff).
set -euo pipefail; unset XDG_CONFIG_HOME   # the person-wide config.json: never the real one
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; trap 'echo "failed at line $LINENO: $BASH_COMMAND" >&2' ERR
root=$(mkdir -p "$tmp/proj" && cd "$tmp/proj" && pwd -P)
sid=11111111-2222-3333-4444-555555555555 cid=99999999-2222-3333-4444-555555555555

git -C "$root" init -q && git -C "$root" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$root" worktree add -q -b feature/ABC-12-fix "$root/wt" && touch "$root/wt/dirty"
proj=$tmp/cfg/projects/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$root"); mkdir -p "$proj" "$tmp/bin"
echo '{"type":"user","message":{"content":"Work on ABC-12"}}' > "$proj/$sid.jsonl"
echo '{"type":"assistant","input":{"command":"bash x/session-status --coordinator"}}' >> "$proj/$sid.jsonl"  # still a worker
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Should I use A or B?"}]}}' >> "$proj/$sid.jsonl"  # asks: on you
echo '{"type":"assistant","input":{"command":"session-status --changes"}} ABC-12 ABC-12 ABC-12 ABC-12 ABC-12 ABC-12 ABC-12 ABC-12 ABC-12 ABC-12' > "$proj/$cid.jsonl"
printf '#!/bin/sh\necho %s\n' "'[{\"sessionId\":\"$sid\",\"name\":\"fix it\",\"cwd\":\"$root\",\"state\":\"blocked\"},{\"sessionId\":\"$cid\",\"name\":\"coord\",\"cwd\":\"$root\",\"status\":\"idle\"}]'" > "$tmp/bin/claude"
chmod +x "$tmp/bin/claude"

run() { (cd "$root" && HOME=$tmp XDG_STATE_HOME=$tmp/state CLAUDE_CONFIG_DIR=$tmp/cfg PATH=$tmp/bin:$PATH "$here/session-status" "$@"); }
[ "$(run --coordinator)" = coord ] && [ -z "$(CLAUDE_CODE_SESSION_ID=$cid run --coordinator)" ] || { echo "--coordinator failed"; exit 1; }
run --changes >/dev/null; (sleep 2; touch "$root/wt/dirty2") & toucher=$!; trap 'kill $toucher 2>/dev/null || true; rm -rf "$tmp"' EXIT
[ "$(run --watch --every x)" = "--every needs a positive number of seconds" ] && [ "$(run --watch --every 1)" = "$(printf 'was: %s\nnow: %s' "$(run ABC-12 | sed 's/dirty:2/dirty:1/')" "$(run ABC-12)")" ] ||
  { echo "--watch failed"; exit 1; }
rm "$root/wt/dirty2"
diff <(run) - <<EOF && diff <(run ABC-12) - <<EOF2
ABC-12    -              wt dirty:1 unpushed:? | sess:"fix it" blocked

Waiting on you:
  "fix it" (claude attach 11111111)
EOF
ABC-12    -              wt dirty:1 unpushed:? | sess:"fix it" blocked
EOF2

# Notices: a new one is a change, one going away isn't; a failure keeps the last good ones; exit 2 = unsupported.
mkdir -p "$root/.claude"; cat > "$root/.claude/session-status-adapter" <<EOF
#!/bin/sh
case \$1 in
  tasks) [ -f $tmp/fail ] && { echo boom; exit 1; }; printf 'ABC-12\t-\t\t\n'; [ ! -f $tmp/fix ] || echo 'fix: Sign in → gh auth login' ;;
  notices) cat $tmp/notices; exit \$(cat $tmp/rc) ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$root/.claude/session-status-adapter"; : > "$tmp/notices"; echo 0 > "$tmp/rc"
run --changes >/dev/null; echo "DM from Ann: hi" > "$tmp/notices"
[ "$(run --changes)" = "now:   * DM from Ann: hi" ] && [ "$(run ABC-12 | grep -c Notices)" = 0 ] &&
  echo "no login" > "$tmp/notices" && echo 1 > "$tmp/rc" && [ "$(run --changes)" = "now:   * (failed) no login" ] && [ "$(run | grep -c 'Ann: hi')" = 1 ] &&
  : > "$tmp/notices" && echo 0 > "$tmp/rc" && [ "$(run --changes)" = "no changes" ] &&
  echo junk > "$tmp/notices" && echo 2 > "$tmp/rc" && [ "$(run | grep -c Notices)" = 0 ] || { echo "notices failed"; exit 1; }
# The plugin-feedback footer: on a coordinator's board once a day, never a worker's, the --changes child's or the pane's.
mkdir -p "$tmp/state/session-orchestration/feedback/bugfixes"
printf '# t\n- seen: 2026-01-01\n- status: open\n' > "$tmp/state/session-orchestration/feedback/bugfixes/t.md"
export CLAUDE_CODE_SESSION_ID=$cid
run --changes >/dev/null; [ "$(run --changes)" = "no changes" ] && [ "$(SESSION_STATUS_NO_FEEDBACK=1 run | grep -c 'plugin feedback')" = 0 ] &&
  [ "$(CLAUDE_CODE_SESSION_ID=$sid run | grep -c 'plugin feedback')" = 0 ] &&
  [ "$(run | grep -c 'plugin feedback: 1 open')" = 1 ] && [ "$(run | grep -c 'plugin feedback')" = 0 ] && unset CLAUDE_CODE_SESSION_ID &&
  rm -r "$tmp/state" || { echo "feedback footer failed"; exit 1; }
# A messages module (the person's config) runs beside the adapter's notices, its lines first; each source keeps its
# own last good lines. Its NOTICE_MINE defaults to the last sweep's keys.
mkdir -p "$root/.claude/coordination.local/messages"
cat > "$root/.claude/coordination.local/messages/fake.sh" <<EOF
messages_notices() { cat $tmp/msg; cp "\$NOTICE_MINE" $tmp/mine.seen; return \$(cat $tmp/msgrc); }
EOF
echo '{"messages": "fake"}' > "$root/.claude/coordination.local.json"
echo "chat: ping" > "$tmp/msg"; echo 0 > "$tmp/msgrc"; echo "DM from Ann: hi" > "$tmp/notices"; echo 0 > "$tmp/rc"
[ "$(run | sed -n '/^Notices:/,$p')" = "$(printf 'Notices:\n  * chat: ping\n  * DM from Ann: hi')" ] &&
  echo "graph down" > "$tmp/msg" && echo 1 > "$tmp/msgrc" &&
  [ "$(run | sed -n '/^Notices:/,$p')" = "$(printf 'Notices:\n  * chat: ping\n  * (failed) graph down\n  * DM from Ann: hi')" ] &&
  [ "$(cat "$tmp/mine.seen")" = ABC-12 ] && [ "$(run --messages-file)" = "$tmp/.cache/session-status/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$root").messages/notices.jsonl" ] ||
  { echo "messages module failed: $(run | sed -n '/^Notices:/,$p')"; exit 1; }
rm -r "$root/.claude/coordination.local.json" "$root/.claude/coordination.local"; : > "$tmp/notices"

# A `fix:` line from tasks follows the rows, not parsed as one; --root names the project root.
touch "$tmp/fix"
[ "$(run ABC-12)" = "$(printf '%s\nfix: Sign in → gh auth login' "$(rm "$tmp/fix"; run ABC-12)")" ] || { echo "fix line failed"; exit 1; }
[ "$(run --root)" = "$root" ] || { echo "--root failed"; exit 1; }

# An adapter with only `pending` (tasks exits 2): the no-adapter rows, and its pending text. A tasks failure with no
# output names the adapter and its exit code.
cp "$root/.claude/session-status-adapter" "$tmp/adapter.keep"
printf '#!/bin/sh\ncase $1 in pending) echo "- carry ABC-12" ;; *) exit 2 ;; esac\n' > "$root/.claude/session-status-adapter"
[ "$(run ABC-12)" = 'ABC-12    -              wt dirty:1 unpushed:? | sess:"fix it" blocked' ] &&
  grep -qx 'ABC-12    -              wt dirty:1 unpushed:? | sess:"fix it" blocked' <<<"$(run)" &&
  [ "$(run --pending)" = "- carry ABC-12" ] && [ "$(run some-arg)" = "Arguments other than task keys need an adapter that answers tasks ($root/.claude/session-status-adapter)" ] ||
  { echo "pending-only adapter failed: $(run)"; exit 1; }
printf '#!/bin/sh\n[ "$1" = tasks ] && exit 3; exit 2\n' > "$root/.claude/session-status-adapter"
out=$(run) && { echo "silent tasks failure exited 0"; exit 1; }
[ "$out" = "adapter tasks failed (exit 3)" ] || { echo "silent tasks failure: $out"; exit 1; }
# Not answering the sweep (its fix line kept), the keys found are looked up and its row is used; a key `done`
# reports isn't a row (Leftovers has it).
cat > "$root/.claude/session-status-adapter" <<'EOF'
#!/bin/sh
case "$*" in
  tasks) echo "fix: Sign in → gh auth login"; exit 2 ;;
  "tasks ABC-12") printf 'ABC-12\tIn review\tFix\tapp#3 OPEN | \n' ;;
  "done ABC-12") [ -e "$(dirname "$0")/merged" ] && printf 'ABC-12\tmerged #3\n' ;;
  *) exit 2 ;;
esac
EOF
out=$(run)
[ "$(head -1 <<<"$out")" = 'ABC-12    In review      app#3 OPEN | wt dirty:1 unpushed:? | sess:"fix it" blocked | Fix' ] &&
  grep -qx 'fix: Sign in → gh auth login' <<<"$out" || { echo "lookup of pointed keys: $out"; exit 1; }
touch "$root/.claude/merged"
run | grep -q '^ABC-12 ' && { echo "a done key is still a row: $(run)"; exit 1; }
rm "$root/.claude/merged"
# Exit 2 that says why on stderr (a syntax error) is a failure, not "not answered"; a quiet exit 2 keeps its fix line.
printf '#!/bin/sh\necho "oops: bad" >&2; exit 2\n' > "$root/.claude/session-status-adapter"
out=$(run) && { echo "noisy exit 2 exited 0"; exit 1; }
[ "$out" = "$(printf 'adapter tasks failed (exit 2)\n  oops: bad')" ] || { echo "noisy exit 2: $out"; exit 1; }
printf '#!/bin/sh\necho "fix: Sign in → gh auth login"; exit 2\n' > "$root/.claude/session-status-adapter"
[ "$(run ABC-12 | tail -1)" = "fix: Sign in → gh auth login" ] || { echo "exit 2 fix line: $(run ABC-12)"; exit 1; }
mv "$tmp/adapter.keep" "$root/.claude/session-status-adapter"

# A worker at rest whose task only waits on a reviewer isn't waiting on you: idle on its row, no Waiting on you.
# Approved (the merge call) or with something to fix, it still is.
cp "$root/.claude/session-status-adapter" "$tmp/adapter.keep"
printf '#!/bin/sh\n[ "$1" = tasks ] || exit 2; printf "ABC-12\\t-\\t\\t%%s  " "$(cat %s)"\n' "$tmp/extra" > "$root/.claude/session-status-adapter"
row() { echo "$1" > "$tmp/extra"; out=$(run); }
row 'r#1 OPEN no-human-approval'; grep -q 'no-human-approval  wt dirty:1 unpushed:? | sess:"fix it" idle$' <<<"$out" && ! grep -q 'Waiting on you' <<<"$out" &&
  row 'r#1 OPEN +Ann' && grep -q 'sess:"fix it" blocked$' <<<"$out" && grep -q '^  "fix it" (claude attach' <<<"$out" &&
  row 'r#1 OPEN no-human-approval CONFLICT' && grep -q 'sess:"fix it" blocked$' <<<"$out" &&
  row 'r#1 OPEN no-human-approval  s#2 OPEN +Ann' && grep -q 'sess:"fix it" blocked$' <<<"$out" &&
  row 'r#1 OPEN no-human-approval  s#2 OPEN approved by 8bob' && grep -q 'sess:"fix it" blocked$' <<<"$out" &&
  row 'r#1 OPEN no-human-approval  s#2 OPEN changes requested by 8bob' && grep -q 'sess:"fix it" blocked$' <<<"$out" ||
  { echo "review-only failed: $out"; exit 1; }
# Status idle (its turn ended) is in review too; status waiting (a prompt or question) is still on you.
cp "$tmp/bin/claude" "$tmp/claude.keep"
for s in idle waiting; do
  printf '#!/bin/sh\necho %s\n' "'[{\"sessionId\":\"$sid\",\"name\":\"fix it\",\"cwd\":\"$root\",\"state\":\"blocked\",\"status\":\"$s\"}]'" > "$tmp/bin/claude"
  row 'r#1 OPEN no-human-approval'; echo "$s $(grep -c 'Waiting on you' <<<"$out")"
done > "$tmp/st"
[ "$(cat "$tmp/st")" = "$(printf 'idle 0\nwaiting 1')" ] || { echo "review-only by status failed: $(cat "$tmp/st")"; exit 1; }
mv "$tmp/claude.keep" "$tmp/bin/claude"
mv "$tmp/adapter.keep" "$root/.claude/session-status-adapter"

# Entering `working` doesn't wake (blocked → working, done → working); entering done does.
echo blocked > "$tmp/state"
printf '#!/bin/sh\nprintf %s "$(cat %s/state)"\n' "'[{\"sessionId\":\"$sid\",\"name\":\"fix it\",\"cwd\":\"$root\",\"state\":\"%s\"}]'" "$tmp" > "$tmp/bin/claude"
run --changes >/dev/null; echo working > "$tmp/state"; [ "$(run --changes)" = "no changes" ] &&
  echo done > "$tmp/state" && [ "$(run --changes)" = "$(printf 'was: %s\nnow: %s' "$(run ABC-12 | sed 's/" done/" working/')" "$(run ABC-12)")" ] &&
  echo working > "$tmp/state" && [ "$(run --changes)" = "no changes" ] || { echo "working filter failed"; exit 1; }
# While working, the worktree's counts changing doesn't wake; leaving `working` shows the current counts.
touch "$root/wt/dirty3"; [ "$(run --changes)" = "no changes" ] && echo done > "$tmp/state" &&
  [ "$(run --changes)" = "$(printf 'was: %s\nnow: %s' "$(run ABC-12 | sed 's/" done/" working/')" "$(run ABC-12)")" ] &&
  run ABC-12 | grep -q 'dirty:2' || { echo "working counts filter failed"; exit 1; }
rm "$root/wt/dirty3"
# A failing run: --changes exits 1 with the error and leaves the saved state alone.
cp "$tmp/.cache/session-status/"*.last "$tmp/before"; touch "$tmp/fail"
out=$(run --changes) && { echo "failure not reported"; exit 1; }
[ "$out" = boom ] && cmp -s "$tmp/before" "$tmp/.cache/session-status/"*.last || { echo "failure branch failed"; exit 1; }
rm "$tmp/fail"
# A working <-> idle flip doesn't wake: working -> blocked (its turn is over) and back.
echo working > "$tmp/state"; run --changes >/dev/null; echo blocked > "$tmp/state"
[ "$(run --changes)" = "no changes" ] && echo working > "$tmp/state" && [ "$(run --changes)" = "no changes" ] || { echo "idle flip woke --changes"; exit 1; }
# A blocked session hooks/blocked.sh saw on a prompt: Waiting on you says on what, and that wakes --changes. Gone
# once its transcript is newer (the prompt was answered).
echo blocked > "$tmp/state"; run --changes >/dev/null; mkdir -p "$tmp/.cache/session-status/blocked"; sleep 1
echo '{"type":"permission_prompt","tool":"Bash","input":"rm -rf build"}' > "$tmp/.cache/session-status/blocked/$sid.json"
out=$(run --changes); [ "$out" = 'now:   "fix it" (claude attach 11111111) — blocked: Bash `rm -rf build`' ] || { echo "blocked line failed: $out"; exit 1; }
sleep 1; touch "$proj/$sid.jsonl"; [ "$(run --changes)" = "no changes" ] && ! run | grep -q 'blocked: Bash' || { echo "answered prompt still shown"; exit 1; }
# --watch: a flicker (a title changed for one poll) and a failed poll (Jira not responding) wake no one; a change
# that lasts two polls does.
cp "$root/.claude/session-status-adapter" "$tmp/adapter.keep"; echo 0 > "$tmp/n"
cat > "$root/.claude/session-status-adapter" <<EOF
#!/bin/sh
[ "\$1" = tasks ] || exit 2
n=\$((\$(cat $tmp/n) + 1)); echo \$n > $tmp/n
case \$n in 2) printf 'ABC-12\t-\tflicker\t\n' ;; 3) echo 'Jira did not respond'; exit 1 ;; 1|4) printf 'ABC-12\t-\t\t\n' ;; *) printf 'ABC-12\t-\tlasting\t\n' ;; esac
EOF
run --changes >/dev/null; out=$(SESSION_STATUS_CONFIRM_S=1 run --watch --every 1 2>/dev/null)
[ "$out" = "$(printf 'was: %s\nnow: %s' "$(echo 0 > "$tmp/n"; run ABC-12)" "$(echo 9 > "$tmp/n"; run ABC-12)")" ] || { echo "--watch debounce failed: $out"; exit 1; }
echo 2 > "$tmp/n"; out=$(SESSION_STATUS_CONFIRM_S=1 SESSION_STATUS_WATCH_TRIES=1 run --watch --every 1) && { echo "--watch hid a lasting failure"; exit 1; }
[ "$out" = "$(printf 'session-status --watch: gave up after 1 failed polls in a row; last error:\nJira did not respond')" ] || { echo "--watch failure output: $out"; exit 1; }
# One failed poll logs a line to stderr and the watch carries on (default 3 tries).
echo 0 > "$tmp/n"; run --changes >/dev/null   # state back to poll 1's rows: poll 3 fails, 4 matches, 5-6 change
echo 2 > "$tmp/n"; out=$(SESSION_STATUS_CONFIRM_S=1 run --watch --every 1 2>"$tmp/err") &&
  [ "$out" = "$(printf 'was: %s\nnow: %s' "$(echo 0 > "$tmp/n"; run ABC-12)" "$(echo 9 > "$tmp/n"; run ABC-12)")" ] &&
  [ "$(cat "$tmp/err")" = "session-status --watch: poll failed (1/3), retrying in 1s: Jira did not respond" ] ||
  { echo "--watch retry failed: $out / $(cat "$tmp/err")"; exit 1; }
mv "$tmp/adapter.keep" "$root/.claude/session-status-adapter"
# A session with no row (no task) going busy and idle doesn't wake ("Waiting on you" churn); one that ends does.
printf '#!/bin/sh\nprintf %s "$(cat %s/state)"\n' "'[{\"sessionId\":\"$sid\",\"name\":\"fix it\",\"cwd\":\"$root\",\"state\":\"working\"},{\"sessionId\":\"$cid\",\"name\":\"docs\",\"cwd\":\"$root\",\"state\":\"%s\"}]'" "$tmp" > "$tmp/bin/claude"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Your call: keep it?"}]}}' >> "$proj/$cid.jsonl"
echo blocked > "$tmp/state"; run --changes >/dev/null
echo working > "$tmp/state"; [ "$(run --changes)" = "no changes" ] && echo blocked > "$tmp/state" &&
  [ "$(run --changes)" = "no changes" ] || { echo "row-less busy/idle filter failed"; exit 1; }
echo done > "$tmp/state"
[ "$(run --changes)" = 'was:   "docs" (claude attach 99999999)' ] || { echo "row-less session filter failed"; exit 1; }
# One that vanishes from the session list (closed) counts too.
echo blocked > "$tmp/state"; run --changes >/dev/null
printf '#!/bin/sh\nprintf %s\n' "'[{\"sessionId\":\"$sid\",\"name\":\"fix it\",\"cwd\":\"$root\",\"state\":\"working\"}]'" > "$tmp/bin/claude"
[ "$(run --changes)" = 'was:   "docs" (claude attach 99999999)' ] || { echo "gone session filter failed"; exit 1; }
# A finished task's clean, merged worktree is a leftover; idle past the resolve age it moves to Resolved, and
# that move wakes no one.
git -C "$root" update-ref refs/remotes/origin/main HEAD && git -C "$root" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git -C "$root" worktree add -q -b feature/ABC-34-old "$root/wt2" && touch -t 202001010000 "$root/wt2"
sed -i.bak 's/^  \*) exit 2 ;;/  done) shift; for k; do [ "$k" = ABC-34 ] \&\& printf "ABC-34\\tDone\\n"; done ;;\n  *) exit 2 ;;/' "$root/.claude/session-status-adapter"
rm -f "$root/.claude/session-status-adapter.bak"
left='  ABC-34 Done — worktree clean+merged: git -C . worktree remove wt2 && git -C . branch -d feature/ABC-34-old'
run --changes >/dev/null
[ "$(run | sed -n '/^Leftovers/,$p')" = "$(printf 'Leftovers (task finished):\n%s' "$left")" ] &&
  [ "$(SESSION_STATUS_RESOLVE_DAYS=0 run | sed -n '/^Resolved/,$p')" = "$(printf 'Resolved (idle a week):\n%s' "$left")" ] &&
  [ "$(SESSION_STATUS_RESOLVE_DAYS=0 run | grep -c Leftovers)" = 0 ] &&
  [ "$(SESSION_STATUS_RESOLVE_DAYS=0 run --changes)" = "no changes" ] || { echo "resolved failed"; exit 1; }

# Owners: a review session (newest, `Session task: ABC-12 review`) doesn't take ABC-12 from its worker; a brief sent
# through a tool (`Session task: ABC-77` in a SendMessage) names no owner, nor does the ~ guess count a session whose
# first prompt names another key (ABC-56), however often it mentions ABC-77. No adapter: rows are the keys asked.
rm "$root/.claude/session-status-adapter"
rid=22222222-2222-3333-4444-555555555555 bid=33333333-2222-3333-4444-555555555555
printf '%s\n' '{"type":"user","message":{"content":"Session task: ABC-12 review. Review the PR"}}' \
  '{"type":"assistant","timestamp":"2026-10-13T10:00:00.000Z","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"git diff","description":"Read the diff"}},{"type":"text","text":"Reading.\nLooks fine so far"}]}}' > "$proj/$rid.jsonl"
many=$(printf 'ABC-77 %.0s' {1..12})
printf '%s\n' '{"type":"user","message":{"content":"Work on ABC-56"}}' \
  "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"id\":\"t2\",\"name\":\"SendMessage\",\"input\":{\"to\":\"w\",\"message\":\"Session task: ABC-77. $many\"}}]}}" > "$proj/$bid.jsonl"
printf '#!/bin/sh\necho %s\n' "'[{\"sessionId\":\"$sid\",\"name\":\"fix it\",\"cwd\":\"$root\",\"state\":\"idle\"},{\"sessionId\":\"$rid\",\"name\":\"ABC-12 review\",\"cwd\":\"$root\",\"state\":\"working\"}]'" > "$tmp/bin/claude"
run ABC-12 | grep -q 'sess:"fix it" idle' || { echo "review session took the owner"; exit 1; }
run ABC-77 | grep -q 'sess:—' || { echo "a brief or a first prompt for another key gave an owner"; exit 1; }
# It shows under Other sessions instead, linked to its task, with its last line; --changes doesn't compare it.
[ "$(run | sed -n '/^Other sessions:/,$p')" = "$(printf 'Other sessions:\n  "ABC-12 review" working 0m · reviews ABC-12 — Looks fine so far (claude attach 22222222)')" ] ||
  { echo "other sessions failed"; run; exit 1; }
run --changes >/dev/null; echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Now this"}]}}' >> "$proj/$rid.jsonl"
[ "$(run --changes)" = "no changes" ] || { echo "other sessions woke --changes"; exit 1; }
# --activity: what it's doing (its latest call's description) since when, and its last text line.
since=1791885600   # 2026-10-13T10:00:00Z
[ "$(run --activity | awk -F'\t' -v id="$rid" '$1 == id {print $2 "|" $3 "|" $5 "|" $6 "|" $7}')" = "ABC-12 review|working|Read the diff|$since|Now this" ] ||
  { echo "activity failed"; run --activity; exit 1; }
# An in_progress todo outranks a later call; a TaskUpdate takes its TaskCreate's activeForm.
act() { printf '%s\n' "$@" | jq -rRn -f "$here/session-activity.jq" | cut -f1; }
tw='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"a","name":"TodoWrite","input":{"todos":[{"content":"Fix","activeForm":"Fixing the bug","status":"in_progress"}]}}]}}'
rd='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b","name":"Read","input":{"file_path":"/x/y/z.ts"}}]}}'
tc='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"c","name":"TaskCreate","input":{"subject":"Ship","activeForm":"Shipping it"}}]}}'
tr='{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"c","content":"Task #4 created successfully: Ship"}]}}'
tu='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"d","name":"TaskUpdate","input":{"taskId":"4","status":"in_progress"}}]}}'
[ "$(act "$tw" "$rd")" = "Fixing the bug" ] && [ "$(act "$rd")" = "Read z.ts" ] && [ "$(act "$tc" "$tr" "$tu" "$rd")" = "Shipping it" ] ||
  { echo "activity sources failed"; exit 1; }
# "review" counts only as the marker's last word ("review fixes" is the worker's own task); a marker in a message
# the session received (a SendMessage brief) counts.
wid=44444444-2222-3333-4444-555555555555 xid=55555555-2222-3333-4444-555555555555
printf '%s\n' '{"type":"user","message":{"content":"Work on ABC-90"}}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"Session task: ABC-90 review fixes"}]}}' > "$proj/$wid.jsonl"
printf '%s\n' '{"type":"user","message":{"content":"hello"}}' '{"type":"user","message":{"content":"Session task: ABC-91. Take it"}}' > "$proj/$xid.jsonl"
run ABC-90 | grep -q 'sess:44444444 closed' && run ABC-91 | grep -q 'sess:55555555 closed' || { echo "marker rules failed"; run ABC-90 ABC-91; exit 1; }
# The five wrong rows of 2026-10-21 (PROJ-4177, 4850, 4849, 4157, 5227 → ABC-101…105). A worker that ran the status
# command for its own task still owns it (only --changes/--watch make a coordinator). A first prompt names a key
# only at its start, and beats a newer misrouted session's marker. The guess counts only a session's own text and
# prompts, and prints as `sess:— (maybe …)`, never as an owner.
tj() { printf '%s\n' "$@" > "$proj/$tid.jsonl"; touch -t "$(date -d "-$ago hours" +%Y%m%d%H%M 2>/dev/null || date -v-"$ago"H +%Y%m%d%H%M)" "$proj/$tid.jsonl"; }
up() { printf '{"type":"user","message":{"content":"%s"}}' "$1"; }
said() { printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}' "$1"; }
ran() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"r","name":"Bash","input":{"command":"%s"}}]}}' "$1"; }
res() { printf '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"r","content":"%s"}]}}' "$1"; }
tid=f1000001-2222-3333-4444-555555555555 ago=360; tj "$(up 'Work on ABC-101: it is In Development')" "$(ran 'cat proj-status.md')" "$(ran 'session-status ABC-101')"
tid=f1000002-2222-3333-4444-555555555555 ago=1; tj "$(up 'Session task: rnd-skills (no ticket). Study skills')" "$(ran 'bash x/session-status --coordinator')" \
  "$(res "$(printf 'ABC-101-x %.0s' {1..12})")" "$(up 'Work on ABC-101: reply to Ann')" "$(said 'Session task: ABC-101')"
tid=f1000003-2222-3333-4444-555555555555 ago=150; tj "$(up 'Work on ABC-102')" "$(ran 'session-status ABC-102')"
tid=f1000004-2222-3333-4444-555555555555 ago=140; tj "$(up 'Work on pr-review')" "$(res "$(printf 'ABC-102 %.0s' {1..17})")"
tid=f1000005-2222-3333-4444-555555555555 ago=360; tj "$(up 'work on ABC-103')"
tid=f1000006-2222-3333-4444-555555555555 ago=140; tj "$(up 'Work on bg-no-enterworktree. History: 2026-10-06 ABC-103/104 worked')"
tid=f1000007-2222-3333-4444-555555555555 ago=340; tj "$(up 'Work on ABC-104')" "$(ran 'session-status ABC-104')"
tid=f1000008-2222-3333-4444-555555555555 ago=48; tj "$(up 'Task: traders-support')" "$(said 'Session task: ABC-105')" "$(ran 'session-status ABC-105')"
tid=f1000009-2222-3333-4444-555555555555 ago=72; tj "$(up 'Look into the automap')" "$(said "$(printf 'ABC-106 %.0s' {1..11})")"
# A coordinator that only opened the pane (no watcher) quoting a marker owns nothing.
tid=f100000a-2222-3333-4444-555555555555 ago=1
tj '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"p","name":"mcp__session-orchestration__open_pane","input":{}}]}}' "$(said 'it wrote Session task: ABC-105')"
want=$'ABC-101 f1000001\nABC-102 f1000003\nABC-103 f1000005\nABC-104 f1000007\nABC-105 f1000008\nABC-106 — (maybe f1000009: 11 mentions)'
got=$(run ABC-101 ABC-102 ABC-103 ABC-104 ABC-105 ABC-106 | sed -E 's/^(ABC-[0-9]+).*sess:([0-9a-f]{8}|—.*)( closed.*)?$/\1 \2/; s/ closed [0-9]+h$//')
[ "$got" = "$want" ] || { echo "misroute owners failed:"; diff <(echo "$want") <(echo "$got"); exit 1; }
# --owner: the row, then each candidate with its rule, state, first prompt line and markers, the owner first.
out=$(run --owner ABC-101)
[ "$(head -1 <<<"$out" | sed 's/ closed [0-9]*h$//')" = 'ABC-101: sess:f1000001' ] &&
  grep -q '^  f1000001 first-prompt · closed [0-9]*h · first: Work on ABC-101: it is In Development · marks: —$' <<<"$out" &&
  grep -q '^  f1000002 marker · closed [0-9]*h · first: Session task: rnd-skills (no ticket). Study skills · marks: ABC-101$' <<<"$out" &&
  [ "$(sed -n 2p <<<"$out" | cut -c3-10)" = f1000001 ] && [ "$(run --owner x; echo $?)" = "$(printf 'usage: session-status --owner KEY [KEY…]\n2')" ] ||
  { echo "--owner failed: $out"; exit 1; }
rm "$proj"/f100000*.jsonl
# A session in one of the adapter's session-dirs shows under Other sessions and never owns a task.
mkdir -p "$tmp/tools"; tools=$(cd "$tmp/tools" && pwd -P)
printf '#!/bin/sh\ncase $1 in tasks) shift; for k; do printf "%%s\\t-\\t\\t\\n" "$k"; done ;; session-dirs) echo %s ;; *) exit 2 ;; esac\n' "$tools" > "$root/.claude/session-status-adapter"
chmod +x "$root/.claude/session-status-adapter"
printf '#!/bin/sh\necho %s\n' "'[{\"sessionId\":\"66666666-2222-3333-4444-555555555555\",\"name\":\"ABC-90 tooling\",\"cwd\":\"$tools\",\"state\":\"idle\"}]'" > "$tmp/bin/claude"
run | grep -q '^  "ABC-90 tooling" idle 0m (claude attach 66666666)$' && run ABC-90 | grep -q 'sess:44444444 closed' ||
  { echo "session-dirs failed"; run; exit 1; }

# Context fill: the last reply's input + cache tokens, then a /compact's postTokens; the window from the model id.
u='{"type":"assistant","message":{"usage":{"input_tokens":2,"cache_read_input_tokens":600000,"cache_creation_input_tokens":20000},"content":[{"type":"text","text":"hi"}]}}'
cb='{"type":"system","subtype":"compact_boundary","compactMetadata":{"postTokens":4286}}'
ctx() { printf '%s\n' "$@" | jq -rRn -f "$here/session-activity.jq" | cut -f4; }
[ "$(ctx "$u")" = 620002 ] && [ "$(ctx "$u" "$cb")" = 4286 ] || { echo "ctx failed"; exit 1; }
printf '%s\n' '{"type":"attachment","attachment":{"type":"model","identity":{"modelId":"claude-opus-5-5[1m]"}}}' "$u" >> "$proj/$rid.jsonl"
printf '#!/bin/sh\necho %s\n' "'[{\"sessionId\":\"$rid\",\"name\":\"ABC-12 review\",\"cwd\":\"$root\",\"state\":\"blocked\",\"status\":\"idle\",\"kind\":\"background\",\"pid\":1}]'" > "$tmp/bin/claude"
[ "$(run --activity | awk -F'\t' -v id="$rid" '$1 == id {print $8 "|" $9 "|" $10 "|" $11}')" = "620002|1000000|idle|background" ] ||
  { echo "activity ctx failed"; run --activity; exit 1; }

# --compact and --send-when-idle, against a stub claude that logs its calls and answers per account: this one
# (cfg) and another sharing its transcript store (.claude-work). Retired sessions (pid null) show only with --all.
# The other account is asked only with features.accounts on (the person file); off, it isn't.
mkdir -p "$tmp/.claude-work"; ln -s "$tmp/cfg/projects" "$tmp/.claude-work/projects"
cat > "$tmp/bin/claude" <<EOF
#!/bin/sh
acct=\$(basename "\${CLAUDE_CONFIG_DIR:-none}")
echo "\$acct \$*" >> "$tmp/calls"
case "\$1" in
  agents) f="$tmp/agents-\$acct.json"; [ -f "\$f" ] || { echo '[]'; exit 0; }
    if echo "\$*" | grep -q -- --all; then cat "\$f"; else jq '[.[]? | select(.pid != null)]' "\$f"; fi ;;
  stop) f="$tmp/agents-\$acct.json"   # its process ends: no pid from now on
    jq --arg id "\$2" '[.[]? | if (.sessionId | startswith(\$id)) then .pid = null else . end]' "\$f" > "\$f.t" && mv "\$f.t" "\$f"
    echo "stopped \$2" ;;
  --bg) [ "\$2" != --resume ] && echo "backgrounded · abcdef12 · x" || echo "backgrounded · \$(printf %s "\$3" | cut -c1-8) · x" ;;
esac
EOF
chmod +x "$tmp/bin/claude"
sess() { printf '{"sessionId":"%s","name":"%s","cwd":"%s","kind":"%s","status":"%s","state":"blocked","pid":%s}' "$1" "$2" "$root" "${5:-background}" "$3" "$4"; }
setacct() { echo "[$2]" > "$tmp/agents-$1.json"; }
calls() { cat "$tmp/calls" 2>/dev/null; : > "$tmp/calls"; }
: > "$tmp/calls"
# Compact: idle → stopped, then resumed under its id with /compact. Busy, waiting or interactive: refused, untouched.
setacct cfg "$(sess "$rid" rev idle 1)"
run --compact "${rid:0:8}" | grep -q 'is compacting' && [ "$(calls | grep -v ' agents ')" = "$(printf 'cfg stop 22222222\ncfg --bg --resume %s /compact' "$rid")" ] ||
  { echo "compact idle failed"; exit 1; }
# A --compact already running for the session (any caller) holds its lock: a second one is refused, untouched.
setacct cfg "$(sess "$rid" rev idle 1)"; mkdir -p "$tmp/.cache/session-status/compact-$rid"
[ "$(run --compact "$rid"; echo $?)" = "$(printf '"rev" is already being compacted\n3')" ] && ! calls | grep -q 'stop\|--bg' ||
  { echo "compact lock failed"; exit 1; }
rmdir "$tmp/.cache/session-status/compact-$rid"
# --activity: no [1m] model but over 200k tokens means a 1M window; an unreadable transcript keeps all 13 fields.
xid2=77777777-2222-3333-4444-555555555555
echo "$u" > "$proj/$xid2.jsonl"; echo 'not json' > "$proj/$sid.jsonl.bad"
setacct cfg "$(sess "$xid2" big idle 1),$(sess "$rid" rev idle 1)"
[ "$(run --activity | awk -F'\t' -v id="$xid2" '$1 == id {print $8 "|" $9}')" = "620002|1000000" ] || { echo "window guess failed"; exit 1; }
cp "$proj/$rid.jsonl" "$tmp/rid.keep"; echo 'not json' > "$proj/$rid.jsonl"
[ "$(run --activity | awk -F'\t' -v id="$rid" '$1 == id {print NF "|" $6 "|" $8 "|" $9}')" = "13|0|0|200000" ] || { echo "placeholder fields failed"; run --activity; exit 1; }
mv "$tmp/rid.keep" "$proj/$rid.jsonl"; rm -f "$proj/$xid2.jsonl" "$proj/$sid.jsonl.bad"
for st in busy waiting; do setacct cfg "$(sess "$rid" rev $st 1)"
  rc=0; out=$(run --compact "$rid") || rc=$?; [ $rc = 3 ] && ! calls | grep -q 'stop\|--bg' || { echo "compact $st not refused: $out"; exit 1; }; done
setacct cfg "$(sess "$rid" rev idle 1 interactive)"
[ "$(run --compact "$rid"; echo $?)" = "$(printf '"rev" is interactive: run /compact in its terminal\n3')" ] || { echo "compact interactive failed"; exit 1; }
# Send when idle: busy → waits; then live here → SendMessage (nothing run); live in the other account → stop and
# resume with the text; retired → woken by a resume; unlisted → resumed from its transcript.
setacct cfg "$(sess "$rid" rev busy 1)"; calls >/dev/null
(sleep 2; setacct cfg "$(sess "$rid" rev idle 1)") &
out=$(SESSION_STATUS_POLL_S=1 run --send-when-idle "$rid" "Follow up: X"); wait
[ "$out" = 'send: SendMessage to "rev" now (idle, live in this account); the text is yours to send' ] && ! calls | grep -q 'stop\|--bg' ||
  { echo "send live failed: $out"; exit 1; }
setacct cfg ""; setacct .claude-work "$(sess "$rid" rev idle 1)"
run --activity | grep -q "$rid" && { echo "accounts off still asked the other account"; exit 1; }
echo '{"features":{"accounts":true}}' > "$root/.claude/coordination.local.json"
# Its 620k context is over the resume limit: refused (exit 4), nothing stopped. The rest lift the limit.
out=$(run --send-when-idle "$rid" x) && rc=0 || rc=$?
[ "$rc" = 4 ] && grep -q 'holds 620002 tokens' <<<"$out" && grep -qF -- "--handover $rid -- '<what next>'" <<<"$out" && ! calls | grep -q 'stop\|--bg' || { echo "send over the resume limit failed: $out"; exit 1; }
export SESSION_STATUS_MAX_RESUME=1000000
run --send-when-idle "$rid" "Follow up: X" | grep -q '^delivered to "rev"' &&
  [ "$(calls | grep -v ' agents ')" = "$(printf '.claude-work stop 22222222\n.claude-work --bg --resume %s Follow up: X' "$rid")" ] || { echo "send other account failed"; exit 1; }
setacct .claude-work "$(sess "$rid" rev waiting 1)"
[ "$(run --send-when-idle "$rid" x >/dev/null; echo $?)" = 3 ] && ! calls | grep -q 'stop\|--bg' || { echo "send waiting other account failed"; exit 1; }
setacct .claude-work "$(sess "$rid" rev '' null)"
run --send-when-idle "$rid" "Wake up" | grep -q '^woke "rev"' && [ "$(calls | grep -v ' agents ')" = ".claude-work --bg --resume $rid Wake up" ] ||
  { echo "send retired failed"; exit 1; }
setacct .claude-work ""
run --send-when-idle "${rid:0:8}" "Back" | grep -q '^resumed 22222222' && [ "$(calls | grep -v ' agents ')" = "cfg --bg --resume $rid Back" ] ||
  { echo "send unlisted failed"; exit 1; }
# accounts off with a second account sharing the transcripts: an unlisted session may be live there, so no resume
rm "$root/.claude/coordination.local.json"
[ "$(run --send-when-idle "${rid:0:8}" "Back" >/dev/null; echo $?)" = 2 ] && ! calls | grep -q -- '--bg' || { echo "send unlisted, accounts off, resumed"; exit 1; }

# --handover: refused with no replies/KEY.md, mid-turn, or on a prompt; else stopped, and a fresh session named
# KEY-<old name> started with a brief that supersedes the old one.
hid=88888888-2222-3333-4444-555555555555 nid=aaaaaaaa-2222-3333-4444-555555555555
echo '{"type":"user","message":{"content":"Work on ABC-40"}}' > "$proj/$hid.jsonl"
printf -- '- Replies folder (for reports): `replies/`.\n' > "$root/CLAUDE.md"; mkdir -p "$root/replies"
setacct cfg "$(sess "$hid" "fix it" idle 1)"; calls >/dev/null
out=$(run --handover "$hid" -- 'Do X.') && rc=0 || rc=$?
[ "$rc" = 2 ] && [ "$out" = 'no replies/ABC-40.md: ask "fix it" for a status report first, or write one' ] && ! calls | grep -q 'stop\|--bg' ||
  { echo "handover without a report failed: $out"; exit 1; }
echo report > "$root/replies/ABC-40.md"
for st in busy waiting; do setacct cfg "$(sess "$hid" "fix it" $st 1)"
  out=$(run --handover "$hid" 'Do X.') && rc=0 || rc=$?
  [ "$rc" = 3 ] && grep -q "$( [ $st = busy ] && echo mid-turn || echo 'waiting on a prompt')" <<<"$out" && ! calls | grep -q 'stop\|--bg' ||
    { echo "handover $st not refused: $out"; exit 1; }; done
setacct cfg "$(sess "$hid" "fix it" idle 1)"
[ "$(run --handover "${hid:0:8}" -- 'Do X.')" = 'handed ABC-40 over: "fix it" (88888888) stopped, superseded by "ABC-40-fix-it" (abcdef12)' ] &&
  [ "$(calls | grep -v ' agents ')" = "$(printf 'cfg stop 88888888\ncfg --bg -n ABC-40-fix-it Work on ABC-40: continue from replies/ABC-40.md. Do X. Supersedes: %s (transcript %s; read only the parts you need, never whole).' "$hid" "$proj/$hid.jsonl")" ] ||
  { echo "handover failed"; calls; exit 1; }
# The new session owns ABC-40, even after the old one is resumed (its transcript newest); the old one shows under
# Other sessions as superseded, not as a leftover or an owner.
echo '{"type":"user","message":{"content":"Work on ABC-40: continue from replies/ABC-40.md. Do X. Supersedes: '"$hid"' (transcript x)"}}' > "$proj/$nid.jsonl"
sleep 1; touch "$proj/$hid.jsonl"
setacct cfg "$(sess "$hid" "fix it" idle 1)"
run ABC-40 | grep -q 'sess:aaaaaaaa closed' && run | grep -q '^  "fix it" idle 0m · superseded by aaaaaaaa (claude attach 88888888)$' ||
  { echo "superseded mapping failed"; run; exit 1; }
# A retry is refused: it would start a second successor. A successor that ran a status command still supersedes.
out=$(run --handover "$hid" 'Do X.') && rc=0 || rc=$?
[ "$rc" = 2 ] && grep -q 'superseded by aaaaaaaa already' <<<"$out" && ! calls | grep -q 'stop\|--bg' || { echo "handover retry not refused: $out"; exit 1; }
echo '{"type":"assistant","input":{"command":"session-status ABC-40"}}' >> "$proj/$nid.jsonl"
run | grep -q '· superseded by aaaaaaaa' || { echo "successor running a status command lost the superseded mark"; run; exit 1; }
# The old session ran a status command itself (a worker checking its PR): its key still comes from its first
# prompt. A name starting with the key in another case is kept; an account defaulting to plan gets
# --permission-mode default.
gid=bbbbbbbb-2222-3333-4444-555555555555
printf '%s\n' '{"type":"user","message":{"content":"Work on ABC-41"}}' '{"type":"assistant","input":{"command":"session-status ABC-41"}}' > "$proj/$gid.jsonl"
echo report > "$root/replies/ABC-41.md"; echo '{"permissions":{"defaultMode":"plan"}}' > "$tmp/cfg/settings.json"
setacct cfg "$(sess "$gid" "abc-41 thing" idle 1)"; calls >/dev/null
out=$(run --handover "$gid" 'Go on'); grep -q 'superseded by "abc-41 thing" (abcdef12)' <<<"$out" &&
  calls | grep -qF "cfg --bg --permission-mode default -n abc-41 thing Work on ABC-41: continue from replies/ABC-41.md. Go on. Supersedes: $gid" ||
  { echo "handover of a status-running worker failed"; calls; exit 1; }
rm "$tmp/cfg/settings.json"
# A chunk session: no KEY.md needed; --model/--effort and the four chunk lines reach `claude --bg`, named KEY-cN.
kid=dddddddd-2222-3333-4444-555555555555
jq -nc '{type: "user", message: {content: "Session task: PROJ-9\nChunk: PROJ-9/3b\nRead the brief."}}' > "$proj/$kid.jsonl"
setacct cfg "$(sess "$kid" "PROJ-9-c3b" idle 1)"; calls >/dev/null
out=$(run --handover "$kid" -- 'x') && rc=0 || rc=$?
[ "$rc" = 2 ] && [[ $out == *'no `## c3b: handoff` in replies/PROJ-9-build.md'* ]] && [ -z "$(calls | grep -v ' agents ')" ] ||
  { echo "chunk handover without its handoff not refused: $rc $out"; exit 1; }
printf '## c3b: handoff\nstate\n' > "$root/replies/PROJ-9-build.md"
# It kept its name (no -prev-K rename): started anyway, with a line saying so.
[ "$(run --handover "$kid" --model opus --effort high -- 'Then land it.')" = 'handed PROJ-9 c3b over: "PROJ-9-c3b" (dddddddd) stopped, superseded by "PROJ-9-c3b" (abcdef12)
"PROJ-9-c3b" (old) wasn'"'"'t renamed: two sessions share PROJ-9-c3b until it is' ] &&
  [ "$(calls | grep -v ' agents ')" = "$(printf 'cfg stop dddddddd\ncfg --bg --model opus --effort high -n PROJ-9-c3b Session task: PROJ-9\nChunk: PROJ-9/3b\nSupersedes: %s\nContinue from the last "## c3b: handoff" in %s/replies/PROJ-9-build.md, then follow %s/replies/PROJ-9-c3b.md.\nThen land it.' "$kid" "$root" "$root")" ] ||
  { echo "chunk handover failed"; calls; exit 1; }
for bad in '--model fable' '--model claude-fable-5-1' '--effort ultra' '--model'; do
  out=$(run --handover "$kid" $bad -- 'x') && rc=0 || rc=$?
  [ "$rc" = 2 ] && ! calls | grep -q 'stop\|--bg' || { echo "handover $bad not refused: $out"; exit 1; }; done
# --self: refused while a coordinator is live; else the successor starts and the caller, mid-turn, isn't stopped.
setacct cfg "$(sess "$kid" "PROJ-9-c3b" busy 1),$(sess "$cid" coord idle 1)"; calls >/dev/null
out=$(CLAUDE_CODE_SESSION_ID=$kid run --handover --self -- 'Go on.') && rc=0 || rc=$?
[ "$rc" = 3 ] && grep -q 'coordinator "coord" is running' <<<"$out" && ! calls | grep -q 'stop\|--bg' || { echo "self handover beside a coordinator: $out"; exit 1; }
setacct cfg "$(sess "$kid" "PROJ-9-c3b" busy 1)"
out=$(CLAUDE_CODE_SESSION_ID=$kid run --handover --self -- 'Go on.')
c=$(calls)
[ "$out" = 'handed over; rename yourself (call name_session with "PROJ-9-c3b-prev-1"), then end your turn now ("PROJ-9-c3b" (abcdef12) supersedes this session)' ] && ! grep -q ' stop ' <<<"$c" &&
  grep -q '^cfg --bg -n PROJ-9-c3b Session task: PROJ-9$' <<<"$c" || { echo "self handover: $out"; echo "$c"; exit 1; }
# A successor (Supersedes: kid) that grew too: the one `## c3b: handoff` is its predecessor's, so it's refused until it
# writes its own; then the new session continues from the last one. A renamed predecessor gets no shared-name line.
k2=eeeeeeee-2222-3333-4444-555555555555
jq -nc --arg k "$kid" '{type: "user", message: {content: ("Session task: PROJ-9\nChunk: PROJ-9/3b\nSupersedes: " + $k + "\nContinue.")}}' > "$proj/$k2.jsonl"
setacct cfg "$(sess "$k2" "PROJ-9-c3b" idle 1),$(sess "$kid" "PROJ-9-c3b-prev-1" idle null)"; calls >/dev/null
out=$(run --handover "$k2" -- 'x') && rc=0 || rc=$?
[ "$rc" = 2 ] && [[ $out == *'no new `## c3b: handoff`'*"1 predecessors"* ]] && [ -z "$(calls | grep -v ' agents ')" ] ||
  { echo "handover on a stale handoff not refused: $rc $out"; exit 1; }
printf '## c3b: handoff\nmore\n' >> "$root/replies/PROJ-9-build.md"
[ "$(run --handover "$k2" -- 'x')" = 'handed PROJ-9 c3b over: "PROJ-9-c3b" (eeeeeeee) stopped, superseded by "PROJ-9-c3b" (abcdef12)
"PROJ-9-c3b" (old) wasn'"'"'t renamed: two sessions share PROJ-9-c3b until it is' ] || { echo "handover after the second handoff"; exit 1; }
rm "$proj/$k2.jsonl"
# --prev-name: the lowest free K over every listed name, live or retired; NAME defaults to the caller's own.
setacct cfg "$(sess "$k2" "PROJ-9-c3b" idle 1),$(sess "$kid" "PROJ-9-c3b-prev-1" idle null),$(sess "$hid" "PROJ-9-c3b-prev-3" idle null)"
[ "$(CLAUDE_CODE_SESSION_ID=$k2 run --prev-name)" = PROJ-9-c3b-prev-2 ] && [ "$(run --prev-name PROJ-9-c3b-prev-3)" = PROJ-9-c3b-prev-2 ] &&
  [ "$(run --prev-name other)" = other-prev-1 ] && ! run --prev-name 2>/dev/null || { echo "--prev-name failed"; exit 1; }

# --peek: the main thread's last turns as markdown (no sidechain, no system reminder), then what it does now.
pid=cccccccc-2222-3333-4444-555555555555
printf '%s\n' '{"type":"user","timestamp":"2026-10-18T10:00:00Z","message":{"content":"Work on ABC-50"}}' \
  '{"type":"user","message":{"content":"<system-reminder>x</system-reminder>"}}' \
  '{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"text","text":"subagent text"}]}}' \
  '{"type":"assistant","cwd":"'"$root/wt"'","message":{"content":[{"type":"text","text":"Running them."},{"type":"tool_use","name":"Bash","input":{"command":"npm test","description":"Run the tests"}}]}}' > "$proj/$pid.jsonl"
out=$(run --peek "${pid:0:8}")
grep -q '^Work on ABC-50$' <<<"$out" && grep -q '^Running them\.$' <<<"$out" && grep -q '^→ Bash: Run the tests' <<<"$out" &&
  ! grep -q 'subagent\|system-reminder' <<<"$out" && grep -q '^_Now: ' <<<"$out" || { echo "peek failed: $out"; exit 1; }
[ "$(run --peek 'x*'; echo $?)" != 0 ] || { echo "peek took a bad id"; exit 1; }
# --dir: a session's latest cwd, as its git top; a task key, its worktree. --diff: against its merge-base with origin/HEAD,
# with the untracked files, then the patch.
[ "$(run --dir "${pid:0:8}")" = "$root/wt" ] && [ "$(run --dir ABC-12)" = "$root/wt" ] || { echo "dir failed"; run --dir "$pid"; exit 1; }
echo a > "$root/wt/f"; git -C "$root/wt" add f; git -C "$root/wt" -c user.name=t -c user.email=t@t commit -qm f; echo b > "$root/wt/f"
out=$(run --diff ABC-12 "$pid")
[ "$(head -1 <<<"$out")" = "$root/wt · vs origin/main" ] && grep -q "^ f | 1 +$" <<<"$out" && grep -q '^?? dirty$' <<<"$out" && grep -q '^+b$' <<<"$out" ||
  { echo "diff failed: $out"; exit 1; }
# --activity lists this project's sessions; --all-projects also another project's.
sess "$gid" elsewhere idle 1 | sed "s#$root#$tmp/elsewhere#" > "$tmp/e.json"
setacct cfg "$(sess "$pid" here idle 1),$(cat "$tmp/e.json")"
[ "$(run --activity | cut -f2)" = here ] && [ "$(run --activity --all-projects | cut -f2 | sort | tr '\n' ' ')" = 'elsewhere here ' ] &&
  [ "$(run --activity | awk -F'\t' '{print NF "|" $12}')" = "13|$root" ] || { echo "all projects failed"; run --activity --all-projects; exit 1; }

# --yesterday on Monday 2030-01-07: Friday has no prompt of the user's (a day off), so it starts Thursday, and
# Saturday's work is in. Wednesday's isn't, nor a coordinator's, nor a keyless session that wrote nothing. The
# adapter's rows give ABC-60 its status and title and add ABC-70; tasks order by their latest event.
y1=dddddddd-0001-3333-4444-555555555555 y2=dddddddd-0002-3333-4444-555555555555 y3=dddddddd-0003-3333-4444-555555555555
y4=dddddddd-0004-3333-4444-555555555555 y5=dddddddd-0005-3333-4444-555555555555
hu() { printf '{"type":"user","origin":{"kind":"human"},"timestamp":"%s","message":{"content":"%s"}}\n' "$1" "$2"; }
as() { printf '{"type":"assistant","timestamp":"%s","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$1" "$2"; }
{ hu 2030-01-02T10:00:00Z 'Work on ABC-60'; as 2030-01-02T10:05:00Z 'Wed work.'; hu 2030-01-03T10:00:00Z 'go on'; as 2030-01-03T10:30:00Z 'Pushed the fix.'; } > "$proj/$y1.jsonl"
{ hu 2030-01-05T10:00:00Z 'Work on ABC-61'; as 2030-01-05T10:00:00Z 'Weekend fix.'; } > "$proj/$y2.jsonl"
{ hu 2030-01-03T08:00:00Z 'coordinate'; printf '{"type":"assistant","timestamp":"2030-01-03T08:01:00Z","message":{"content":[{"type":"tool_use","input":{"command":"session-status --changes"}}]}}\n'; as 2030-01-03T08:02:00Z 'Session task: ABC-60'; } > "$proj/$y3.jsonl"
{ echo '{"type":"agent-name","agentName":"probe"}'; hu 2030-01-03T09:00:00Z 'look into it'; as 2030-01-03T09:00:00Z 'Probe done.'; } > "$proj/$y4.jsonl"
hu 2030-01-03T09:00:00Z 'ping' > "$proj/$y5.jsonl"
touch -t 203001071000 "$proj"/dddddddd-*.jsonl   # written on that Monday: newer than the window's start
cat > "$root/.claude/session-status-adapter" <<EOF
#!/bin/sh
[ "\$1" != standup-notes ] || { echo 'Staging is unreachable by design: never mention it.'; exit 0; }
[ "\$1" = yesterday ] || exit 2
echo "\$*" > $tmp/yargs
printf 'ABC-60\tIn Review\tFix it\n  %s\tJira: A → B\nABC-70\tDone\tOther\n  %s\tJira: moved\n' \$((\$2 + 3600)) \$((\$2 + 7200))
EOF
out=$(SESSION_STATUS_TODAY=2030-01-07 TZ=UTC run --yesterday | sed $'s/\t*$//')
diff <(echo "$out") - <<EOF || { echo "yesterday failed"; exit 1; }
Since: 2030-01-03 Thu (last working day)
Note: Staging is unreachable by design: never mention it.
ABC-61
  Sat 10:00	session "${y2:0:8}" (10:00–10:00): Weekend fix.
ABC-60	In Review	Fix it
  Thu 01:00	Jira: A → B
  Thu 10:30	session "${y1:0:8}" (10:00–10:30): Pushed the fix.
"probe"
  Thu 09:00	session "probe" (09:00–09:00): Probe done.
ABC-70	Done	Other
  Thu 02:00	Jira: moved
EOF
[ "$(cat "$tmp/yargs")" = "yesterday 1893628800 ABC-60 ABC-61" ] || { echo "yesterday adapter args: $(cat "$tmp/yargs")"; exit 1; }
# A picked day: Wednesday's work comes in; a failing adapter is shown, indented, and the rest still is.
printf '#!/bin/sh\necho "signed out"; exit 1\n' > "$root/.claude/session-status-adapter"
out=$(SESSION_STATUS_TODAY=2030-01-07 TZ=UTC run --yesterday 2030-01-02)
[ "$(head -3 <<<"$out")" = "$(printf 'Since: 2030-01-02 Wed (picked)\nTracker lookup failed:\n  signed out')" ] &&
  grep -qF '(Wed 10:00–Thu 10:30): Pushed the fix.' <<<"$out" && [ "$(run --yesterday 2030-13-01; echo "rc $?")" = "$(printf 'usage: session-status --yesterday [YYYY-MM-DD]\nrc 2')" ] ||
  { echo "yesterday picked day failed: $out"; exit 1; }

# Waiting on you keeps itself current: of blocked sessions, only one whose last turn asks the user (q1) or that
# sits on a fresh prompt (p1) is on you. Not on you: a finished turn asking nothing (i1, idle), busy past a session
# limit (b1), superseded by a brief's "You replace session" (o1 by n2), a reviewer at rest (r2), a worktree whose
# work landed (l1). A prompt unanswered 7h (s1) is listed apart under Stale prompts with its stop command.
rm "$root/.claude/session-status-adapter"
txt() { printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$1"; }
q1=a1000001-2222-3333-4444-555555555555 i1=a2000002-2222-3333-4444-555555555555 b1=a3000003-2222-3333-4444-555555555555
s1=a4000004-2222-3333-4444-555555555555 p1=a5000005-2222-3333-4444-555555555555 o1=a6000006-2222-3333-4444-555555555555
n2=a7000007-2222-3333-4444-555555555555 r2=a8000008-2222-3333-4444-555555555555 l1=a9000009-2222-3333-4444-555555555555
{ hu x 'Work on ABC-80'; txt 'Which approach do you want, A or B?'; } > "$proj/$q1.jsonl"
{ hu x 'Work on ABC-81'; txt 'Which file?'; hu x 'that one'; txt 'Done and pushed. The report is in replies/ABC-81.md.'; } > "$proj/$i1.jsonl"
{ hu x 'Work on ABC-82'; txt 'Checking the build.'; } > "$proj/$b1.jsonl"
{ hu x 'Run curl -sI https://example.com'; } > "$proj/$s1.jsonl"; { hu x 'Work on ABC-83'; } > "$proj/$p1.jsonl"
{ hu x 'Work on ABC-84'; txt 'Should I rebase?'; } > "$proj/$o1.jsonl"
{ hu x "Work on ABC-84. You replace session ${o1:0:8}, too big to resume."; txt 'Picked it up.'; } > "$proj/$n2.jsonl"
{ hu x 'Session task: ABC-85 review. Review the PR'; txt 'Posting the comments waits on your go-ahead.'; } > "$proj/$r2.jsonl"
{ hu x 'Work on ABC-86'; txt 'To release: run this?'; } > "$proj/$l1.jsonl"
git -C "$root" worktree add -q -b feature/ABC-86-done "$root/wt3"
git -C "$root/wt3" -c user.name=t -c user.email=t@t commit -q --allow-empty -m done && git -C "$root" update-ref refs/remotes/origin/main feature/ABC-86-done
ago7=$(( $(date +%s) - 7 * 3600 ))
echo "{\"time\":$ago7,\"tool\":\"Bash\",\"input\":\"curl -sI https://example.com\"}" > "$tmp/.cache/session-status/blocked/$s1.json"
echo "{\"time\":$(date +%s),\"tool\":\"Bash\",\"input\":\"npm test\"}" > "$tmp/.cache/session-status/blocked/$p1.json"
setacct cfg "$(sess "$q1" asks '' 1),$(sess "$i1" done-turn idle 1),$(sess "$b1" limited busy 1),$(sess "$s1" probe waiting 1),$(sess "$p1" prompt waiting 1),$(sess "$o1" replaced '' 1),$(sess "$n2" successor busy 1),$(sess "$r2" ABC-85-review '' 1),$(sess "$l1" landed idle 1 | sed "s#$root\"#$root/wt3\"#")"
out=$(run)
[ "$(sed -n '/^Waiting on you:/,/^$/p' <<<"$out" | grep .)" = "$(printf 'Waiting on you:\n  "asks" (claude attach a1000001)\n  "prompt" (claude attach a5000005) — blocked: Bash `npm test`')" ] ||
  { echo "waiting rules failed: $out"; exit 1; }
# Rows say idle or busy for their owners; the rest are under Other sessions.
grep -qxF '  "probe" (claude attach a4000004) — blocked: Bash `curl -sI https://example.com` · unanswered 7h; stop: claude stop a4000004' <<<"$out" &&
  grep -q 'sess:"done-turn" idle$' <<<"$out" && grep -q 'sess:"limited" busy$' <<<"$out" && grep -q 'sess:"landed" idle$' <<<"$out" &&
  grep -q '^  "replaced" idle .* · superseded by a7000007' <<<"$out" && grep -q '^  "ABC-85-review" idle .* · reviews ABC-85' <<<"$out" ||
  { echo "not-on-you rules failed: $out"; exit 1; }
# A conflict on its row keeps it on you however its turn ended.
printf '#!/bin/sh\ncase $1 in tasks) printf "ABC-81\\t-\\t\\t%%s  \\n" "$(cat %s)" ;; *) exit 2 ;; esac\n' "$tmp/extra" > "$root/.claude/session-status-adapter"
chmod +x "$root/.claude/session-status-adapter"; : > "$tmp/extra"
grep -q '^ABC-81 .*sess:"done-turn" idle$' <<<"$(run)" && echo 'r#3 OPEN CONFLICT' > "$tmp/extra" && out=$(run) &&
  grep -q '^ABC-81 .*sess:"done-turn" blocked$' <<<"$out" && grep -q '^  "done-turn" (claude attach a2000002)$' <<<"$out" || { echo "row verdict failed: $out"; exit 1; }
# On you: status waiting with no hooks record (u1), a question above a long report (g1), a session whose other
# row only waits on a reviewer (m1: ABC-88 review-only, ABC-89 asks). Not: a `?` or "blocked" only in code (c1).
# A conflict doesn't keep a stale prompt (s2, ABC-87) under Waiting on you.
u1=b1000001-2222-3333-4444-555555555555 g1=b2000002-2222-3333-4444-555555555555 c1=b3000003-2222-3333-4444-555555555555
s2=b4000004-2222-3333-4444-555555555555 m1=b5000005-2222-3333-4444-555555555555
{ hu x 'Work on ABC-90'; txt 'Done.'; } > "$proj/$u1.jsonl"
{ hu x 'Work on ABC-91'; txt "Shall I merge it?\n$(printf 'line of the report %.0s\\n' {1..3000})"; } > "$proj/$g1.jsonl"
{ hu x 'Work on ABC-92'; txt 'Done. Ran `x ? y : z` and hooks/blocked.sh.\n```\nconst a = b ? c : d\n```\nAll green.'; } > "$proj/$c1.jsonl"
{ hu x 'Work on ABC-87'; } > "$proj/$s2.jsonl"
echo "{\"time\":$ago7,\"tool\":\"Bash\",\"input\":\"rm x\"}" > "$tmp/.cache/session-status/blocked/$s2.json"
{ hu x 'Session task: ABC-88. Go'; txt 'Session task: ABC-89 too. Shall I go on?'; } > "$proj/$m1.jsonl"
printf '#!/bin/sh\ncase $1 in tasks) printf "ABC-87\\t-\\t\\tr#6 OPEN CONFLICT  \\nABC-88\\t-\\t\\tr#5 OPEN no-human-approval  \\nABC-89\\t-\\t\\t\\n" ;; *) exit 2 ;; esac\n' > "$root/.claude/session-status-adapter"
setacct cfg "$(sess "$u1" unrecorded waiting 1),$(sess "$g1" long '' 1),$(sess "$c1" code idle 1),$(sess "$s2" stale-conflict waiting 1),$(sess "$m1" two-rows idle 1)"
out=$(run)
[ "$(sed -n '/^Waiting on you:/,/^$/p' <<<"$out" | grep .)" = "$(printf 'Waiting on you:\n  "unrecorded" (claude attach b1000001)\n  "long" (claude attach b2000002)\n  "two-rows" (claude attach b5000005)')" ] &&
  grep -q '^  "stale-conflict" (claude attach b4000004) — blocked: Bash `rm x` · unanswered 7h; stop: ' <<<"$out" &&
  grep -q '^ABC-87 .*sess:"stale-conflict" stale$' <<<"$out" && grep -q '^  "code" idle ' <<<"$out" || { echo "review fixes failed: $out"; exit 1; }

# --init (session-init): (a) a GitHub repo with ACME keys and a tracked CLAUDE.md, proposed then written; (b) a
# workspace of 2 repos with no keys; (c) a folder under an adapter; (d) a configured folder. Outside $root's adapter.
rm -rf "$tmp/.claude-work"   # one account until the accounts case below
# The terminal it runs in: none, unless T_PROG (TERM_PROGRAM) or T_MUX (TMUX) says.
init() { (cd "$1" && shift && HOME=$tmp CLAUDE_CONFIG_DIR=$tmp/cfg PATH=$tmp/bin:$PATH TERM_PROGRAM=${T_PROG:-} TMUX=${T_MUX:-} "$here/session-status" --init "$@"); }
gc() { git -C "$1" -c user.name=t -c user.email=t@t commit -q "${@:2}"; }
printf '#!/bin/sh\nexit 1\n' > "$tmp/bin/gh" && chmod +x "$tmp/bin/gh"   # gh present, offline: the GitHub adapter, no PRs
a=$(mkdir -p "$tmp/init/acme" && cd "$tmp/init/acme" && pwd -P)
git -C "$a" init -q -b main && git -C "$a" remote add origin git@github.com:acme/app.git && echo '# app' > "$a/CLAUDE.md"
git -C "$a" add CLAUDE.md && gc "$a" -m 'ACME-1: init' && gc "$a" --allow-empty -m 'ACME-12: work' && gc "$a" --allow-empty -m typo
out=$(init "$a") && grep -q '^1\. Task keys: ACME-123 (in 66% ' <<<"$out" && grep -q "^2\. Code host: git@github.com:acme/app.git (github, one repo), gh installed → GitHub adapter: " <<<"$out" &&
  grep -q '^3\. Files: CLAUDE.local.md, .claude/session-status-adapter, ' <<<"$out" || { echo "init (a) failed: $out"; exit 1; }
init "$a" --check >/dev/null && { echo "init (a) --check exited 0 before --write"; exit 1; }
out=$(init "$a" --write) && [ "$(init "$a" --check)" = "$(printf 'configured: %s (acme-coordinator)\nactive: tracker=jira host=github delegate=off terminal=plain messages=none features=none' "$a")" ] && [ -z "$(git -C "$a" status --short)" ] &&
  grep -q '^- Replies folder (the plugin.s "folder for this"): `.claude/orchestration/replies/`\.$' "$a/CLAUDE.local.md" &&
  grep -qF '`approvals.delegate` in' "$a/CLAUDE.local.md" && [ "$(jq -c . "$a/.claude/coordination.local.json")" = '{"features":{"accounts":false},"approvals":{"delegate":false}}' ] &&
  [ "$(jq -c . "$a/.claude/coordination/coordination.json")" = '{"tracker":"jira","host":"github","features":{"review_inbox":false}}' ] && [ "$(cd "$a" && .claude/session-status-adapter urls)" = 'pr https://github.com/acme/{repo}/pull/{id}' ] &&
  [ "$(init "$a" | sed -n '1p;2p;3s/:.*//p;4s/:.*//p')" = "$(printf 'This folder is set up for coordination already (%s, acme-coordinator): nothing to propose.\nOptional, on request (session-status --init --write FLAG):\n  --review-brief\n  --rnd-brief' "$a")" ] ||
  { echo "init (a) --write failed: $out / $(git -C "$a" status --short)"; exit 1; }
(cd "$a" && HOME=$tmp CLAUDE_CONFIG_DIR=$tmp/cfg PATH=$tmp/bin:$PATH "$here/session-status" >/dev/null) || { echo "session-status after --init --write failed"; exit 1; }
cl=$(shasum "$a/CLAUDE.local.md"); init "$a" --write >/dev/null; [ "$(shasum "$a/CLAUDE.local.md")" = "$cl" ] || { echo "init rewrote a file"; exit 1; }
# the optional briefs, on request into the configured folder: the R&D brief's merge regex is the host's merge command
out=$(init "$a" --write --review-brief --rnd-brief) && [ "$out" = "$(printf 'Wrote:\n  .claude/orchestration/review-brief.md\n  .claude/rnd-brief.md\nNext: session-status --init --check (expect configured), then open_pane.')" ] &&
  grep -qF -- "units 7 --project '$(sed 's/[^A-Za-z0-9]/-/g' <<<"$a")'" "$a/.claude/rnd-brief.md" &&
  grep -qF 'git diff origin/main...origin/<branch>' "$a/.claude/orchestration/review-brief.md" &&
  [ "$(init "$a")" = "This folder is set up for coordination already ($a, acme-coordinator): nothing to propose." ] &&
  [ -z "$(git -C "$a" status --short)" ] || { echo "init briefs: $out"; exit 1; }
w=$(mkdir -p "$tmp/init/ws/r1" "$tmp/init/ws/r2" && cd "$tmp/init/ws" && pwd -P)
git -C "$w/r1" init -q && git -C "$w/r2" init -q && gc "$w/r1" --allow-empty -m hello
out=$(init "$w") && grep -q '^1\. Task keys: session names, ws-<short-desc> ' <<<"$out" && grep -q '(none, workspace of 2 repos)' <<<"$out" &&
  grep -q '^3\. Files: CLAUDE.md, .claude/session-status-adapter, .claude/orchestration/pending.md' <<<"$out" || { echo "init (b) failed: $out"; exit 1; }
[ "$(grep -v '^#' "$a/.git/info/exclude")" = "$(printf '/.claude/coordination/\n/.claude/coordination.local.json\n/.claude/coordination.local/\n/CLAUDE.local.md\n/.claude/session-status-adapter\n/.claude/orchestration/\n/.claude/rnd-brief.md')" ] || { echo "init excludes: $(cat "$a/.git/info/exclude")"; exit 1; }
# Files the user had (an uncommitted CLAUDE.md, an adapter) stay visible to git; a non-executable adapter is named.
u=$(mkdir -p "$tmp/init/u" && cd "$tmp/init/u" && pwd -P); git -C "$u" init -q && echo '# mine' > "$u/CLAUDE.md"
mkdir "$u/.claude" && echo '#!/bin/sh' > "$u/.claude/session-status-adapter"
rc=0; out=$(init "$u" --check) || rc=$?
[ "$rc:$out" = "1:partial: .claude/session-status-adapter is not executable: chmod +x it" ] || { echo "init noexec: $rc:$out"; exit 1; }
chmod +x "$u/.claude/session-status-adapter"; init "$u" --write >/dev/null
[ "$(git -C "$u" status --short)" = "$(printf '?? .claude/\n?? CLAUDE.md')" ] && grep -q '^# mine$' "$u/CLAUDE.md" && grep -q 'Replies folder' "$u/CLAUDE.md" ||
  { echo "init untracked CLAUDE.md: $(git -C "$u" status --short)"; exit 1; }
mkdir -p "$a/sub"; rc=0; out=$(init "$a/sub" --check) || rc=$?
[ "$rc:$out" = "3:covered by a parent: $a (acme-coordinator) covers this folder" ] || { echo "init (c) failed: $rc:$out"; exit 1; }
# --config: read from a subfolder (walking up to the config), a bad value falls back with a warning, --delegate turns
# it on; a delegation line left in CLAUDE.md with no key is named by --check.
cfg() { (cd "$1" && "$here/session-status" --config "$2"); }
[ "$(cfg "$a/sub" approvals.delegate):$(cfg "$a/sub" key_pattern)" = 'false:' ] || { echo "config read: $(cfg "$a/sub" approvals.delegate)"; exit 1; }
cp "$a/.claude/coordination/coordination.json" "$tmp/cfg.json"; echo '{"tracker":"trello","approvals":{"delegate":true}}' > "$a/.claude/coordination/coordination.json"
[ "$(cfg "$a" approvals.delegate)" = false ] || { echo "config: the repo file set approvals.delegate"; exit 1; }
[ "$(cfg "$a" tracker 2>&1)" = "$(printf 'warning: config tracker=trello is not valid: using the default\nnone')" ] || { echo "config fallback: $(cfg "$a" tracker 2>&1)"; exit 1; }
grep -x 'warning: config tracker=trello is not valid: using the default' <<<"$(init "$a" --check)" >/dev/null || { echo "check warning: $(init "$a" --check)"; exit 1; }
mv "$tmp/cfg.json" "$a/.claude/coordination/coordination.json"
rc=0; cfg "$a" nope 2>/dev/null || rc=$?; [ $rc = 2 ] || { echo "config: an unknown key didn't exit 2"; exit 1; }
init "$a" --write --delegate >/dev/null && [ "$(cfg "$a/sub" approvals.delegate)" = true ] &&
  grep -x 'active: .* delegate=on terminal=plain messages=none features=none' <<<"$(init "$a" --check)" >/dev/null || { echo "init --delegate: $(init "$a" --check)"; exit 1; }
# messages: a module that exists is active with its doc; one that doesn't falls back to none with a warning. The
# repo file can't set it.
cp "$a/.claude/coordination.local.json" "$tmp/person.json"
jq '.messages = "msgraph"' "$tmp/person.json" > "$a/.claude/coordination.local.json"
grep -x "active: .* messages=msgraph features=none → read $(cd "$here/../.." && pwd)/messages/msgraph.md" <<<"$(init "$a" --check)" >/dev/null &&
  jq '.messages = "irc"' "$tmp/person.json" > "$a/.claude/coordination.local.json" &&
  [ "$(cfg "$a" messages 2>&1)" = "$(printf 'warning: config messages=irc is not valid (no messages/irc.sh found): using the default\nnone')" ] &&
  cp "$tmp/person.json" "$a/.claude/coordination.local.json" && cp "$a/.claude/coordination/coordination.json" "$tmp/cfg.json" &&
  jq '.messages = "msgraph"' "$tmp/cfg.json" > "$a/.claude/coordination/coordination.json" && [ "$(cfg "$a" messages)" = none ] ||
  { echo "config messages: $(init "$a" --check)"; exit 1; }
mv "$tmp/cfg.json" "$a/.claude/coordination/coordination.json"
# Nor the block of the person's module: its settings can name a command (irc.cli from the repo file is dropped).
cp "$a/.claude/coordination/coordination.json" "$tmp/cfg.json"
jq '.messages = "irc" | .irc = {"cli": "theirs", "x": 1}' "$tmp/person.json" > "$a/.claude/coordination.local.json"
jq '.irc = {"cli": "evil", "y": 2}' "$tmp/cfg.json" > "$a/.claude/coordination/coordination.json"
[ "$(cd "$a" && . "$here/../../lib.sh" && coord_json | jq -c .irc)" = '{"cli":"theirs","x":1}' ] || { echo "config: the repo file set the module's block"; exit 1; }
mv "$tmp/cfg.json" "$a/.claude/coordination/coordination.json"; cp "$tmp/person.json" "$a/.claude/coordination.local.json"
rm "$a/.claude/coordination.local.json"; echo '- **The user delegates approvals to the coordinator.**' >> "$a/CLAUDE.local.md"
grep -x 'delegation found in CLAUDE.md: run setup to move it (session-status --init --write --delegate)' <<<"$(init "$a" --check)" >/dev/null &&
  grep -F 'approvals.delegate=true (CLAUDE.md delegates; write with --delegate)' <<<"$(init "$a")" >/dev/null || { echo "init delegation line: $(init "$a" --check)"; exit 1; }
init "$a" --write >/dev/null; [ "$(jq -c .approvals "$a/.claude/coordination.local.json")" = null ] || { echo "init --write revoked a delegation line"; exit 1; }
# a subproject with its own adapter reads its own config only, not its parent's
mkdir -p "$a/subp/.claude" && cp "$a/.claude/session-status-adapter" "$a/subp/.claude/" && echo '{"approvals":{"delegate":true}}' > "$a/.claude/coordination.local.json"
[ "$(cfg "$a/sub" approvals.delegate):$(cfg "$a/subp" approvals.delegate)" = true:false ] || { echo "config: subproject boundary"; exit 1; }
g=$(mkdir -p "$tmp/init/gl" && cd "$tmp/init/gl" && pwd -P); git -C "$g" init -q && git -C "$g" remote add origin git@gitlab.com:x/y.git
grep -F 'host=none features.review_inbox=false features.accounts=false terminal=plain (host=none: GitLab support is a TODO)' <<<"$(init "$g")" >/dev/null &&
  [ "$(cfg "$g" host 2>&1)" = "$(printf 'warning: a GitLab remote: host=none until GitLab support (a TODO)\nnone')" ] ||
  { echo "init gitlab: $(cfg "$g" host 2>&1)"; exit 1; }
# features: a second account sharing the transcript store is named while accounts is off, and its doc once it's on;
# setup turns it on in a new folder. A review inbox named in CLAUDE.md turns review_inbox on, on Bitbucket only.
mkdir -p "$tmp/.claude-work" && ln -s "$tmp/cfg/projects" "$tmp/.claude-work/projects"
echo '{"features":{"accounts":false}}' > "$a/.claude/coordination.local.json"
grep -F 'second account found, accounts off: set features.accounts to true' <<<"$(init "$a" --check)" >/dev/null || { echo "check second account: $(init "$a" --check)"; exit 1; }
echo '{"features":{"accounts":true}}' > "$a/.claude/coordination.local.json"
grep -x "active: .* features=accounts → read $(cd "$here/../.." && pwd)/features/accounts.md" <<<"$(init "$a" --check)" >/dev/null &&
  ! grep -q 'second account' <<<"$(init "$a" --check)" || { echo "check accounts on: $(init "$a" --check)"; exit 1; }
b=$(mkdir -p "$tmp/init/bb" && cd "$tmp/init/bb" && pwd -P); git -C "$b" init -q && git -C "$b" remote add origin ssh://git@bitbucket.example.com/x/y.git
echo 'Review inbox: https://claude.ai/artifact/abc' > "$b/CLAUDE.md"
init "$b" --write >/dev/null && [ "$(jq -c .features "$b/.claude/coordination/coordination.json"):$(jq -c .features "$b/.claude/coordination.local.json")" = '{"review_inbox":true}:{"accounts":true}' ] &&
  grep -x 'active: .* features=accounts,review_inbox → read .*/features/accounts.md, .*/features/review-inbox.md' <<<"$(init "$b" --check)" >/dev/null ||
  { echo "init features: $(init "$b" --check)"; exit 1; }
echo 'Review inbox: https://claude.ai/artifact/abc' >> "$a/CLAUDE.local.md"; rm "$a/.claude/coordination/coordination.json"
grep -F 'review inbox found: off, it needs host=bitbucket' <<<"$(init "$a")" >/dev/null || { echo "init inbox on github: $(init "$a")"; exit 1; }
jq '.features.review_inbox = false' "$b/.claude/coordination/coordination.json" > "$b/x" && mv "$b/x" "$b/.claude/coordination/coordination.json"
grep -F 'review inbox found, review_inbox off' <<<"$(init "$b" --check)" >/dev/null || { echo "check inbox off: $(init "$b" --check)"; exit 1; }
echo '{"tracker":"jira","features":true}' > "$b/.claude/coordination/coordination.json"
[ "$(cfg "$b" tracker 2>/dev/null)" = jira ] || { echo "config: non-object features dropped the repo file"; exit 1; }
# terminal: Ghostty found by TERM_PROGRAM is proposed, named by --check until recorded, then active with its doc; tmux
# is noted and plain.
echo '{"features":{"accounts":true}}' > "$a/.claude/coordination.local.json"
if [ "$(uname)" = Darwin ]; then   # the Ghostty module is macOS-only: elsewhere it is not proposed
T_PROG=ghostty init "$a" | grep -F 'terminal=ghostty' >/dev/null &&
  T_PROG=ghostty init "$a" --check | grep -xF 'detected ghostty: run setup to record it (session-status --init --write adds terminal=ghostty)' >/dev/null &&
  ! init "$a" --check | grep -q 'detected' || { echo "init terminal detected: $(T_PROG=ghostty init "$a" --check)"; exit 1; }
T_PROG=ghostty init "$a" --write >/dev/null && [ "$(jq -r .terminal "$a/.claude/coordination.local.json")" = ghostty ] &&
  grep -x "active: .* terminal=ghostty messages=none features=accounts → read $(cd "$here/../.." && pwd)/terminals/ghostty.md, .*/features/accounts.md" <<<"$(T_PROG=ghostty init "$a" --check)" >/dev/null &&
  ! T_PROG=ghostty init "$a" --check | grep -q detected || { echo "init terminal recorded: $(T_PROG=ghostty init "$a" --check)"; exit 1; }
else ! T_PROG=ghostty init "$a" --check | grep ghostty >/dev/null || { echo "init ghostty proposed off macOS"; exit 1; }; fi
T_MUX=/tmp/tmux-1/default init "$g" | grep -F 'terminal=plain (host=none: GitLab support is a TODO) (tmux found: no tmux terminal yet, so plain)' >/dev/null ||
  { echo "init tmux: $(T_MUX=x init "$g")"; exit 1; }
echo '{"terminal":"wezterm"}' > "$a/.claude/coordination.local.json"
mkdir -p "$a/.claude/coordination.local/terminals" && echo 'open_view() { :; }' > "$a/.claude/coordination.local/terminals/wezterm.sh"
init "$a" --check | grep -xF 'warning: terminals/wezterm.sh: no open_split, using the default' >/dev/null ||
  { echo "check own terminal module: $(init "$a" --check)"; exit 1; }
# Shared mode. (s1) a repo that isn't yours, whose exclude hides .claude/* (SAIL's): setup writes nothing tracked;
# --shared makes the repo file visible to commit, with a negation.
s=$(mkdir -p "$tmp/init/sail" && cd "$tmp/init/sail" && pwd -P); git -C "$s" init -q && git -C "$s" remote add origin https://github.com/o/sail.git
printf '# a\n' > "$s/AGENTS.md" && printf '# c\n' > "$s/CLAUDE.md" && git -C "$s" add . && gc "$s" -m 'add docs'
echo '.claude/*' >> "$s/.git/info/exclude"
grep -F 'Config: tracker=none host=github ' <<<"$(init "$s")" >/dev/null && init "$s" --write >/dev/null && [ -z "$(git -C "$s" status --short)" ] &&
  [ "$(git -C "$s" diff --stat)" = "" ] || { echo "init (s1) wrote something tracked: $(git -C "$s" status --short)"; exit 1; }
out=$(init "$s" --write --shared) && grep -F '.git/info/exclude (!/.claude/coordination/: .claude/coordination/coordination.json was ignored)' <<<"$out" >/dev/null &&
  [ "$(git -C "$s" status --short --untracked-files=all)" = "?? .claude/coordination/coordination.json" ] || { echo "init (s1) --shared: $out / $(git -C "$s" status --short)"; exit 1; }
init "$s" --write >/dev/null; [ "$(git -C "$s" status --short --untracked-files=all)" = "?? .claude/coordination/coordination.json" ] ||
  { echo "init (s1) a later --write hid the shared file: $(tail -3 "$s/.git/info/exclude")"; exit 1; }
# (s2) a committed adapter: proposed for review with its sha256, not run until trusted, then used instead of a
# local one; a change upstream (or since it was shown) needs a new review.
git -C "$s" add .claude/coordination && gc "$s" -m 'coordination'
c=$(mkdir -p "$tmp/init/team" && cd "$tmp/init/team" && pwd -P); git clone -q "$s" "$c"
printf '#!/bin/sh\n[ "$1" = urls ] && echo "team-urls"\n' > "$c/.claude/coordination/session-status-adapter"; chmod +x "$c/.claude/coordination/session-status-adapter"
git -C "$c" add -f .claude/coordination/session-status-adapter && gc "$c" -m 'team adapter'
sha=$(shasum -a 256 "$c/.claude/coordination/session-status-adapter" | cut -d' ' -f1)
out=$(init "$c") && grep -F "     .claude/coordination/session-status-adapter (sha256 $sha)" <<<"$out" >/dev/null &&
  grep -F "To trust them as they are now: --trust=session-status-adapter@$sha (the committed adapter is then used, no local one written)" <<<"$out" >/dev/null &&
  grep -F "repo keys: the committed .claude/coordination/coordination.json" <<<"$out" >/dev/null || { echo "init (s2) proposal: $out"; exit 1; }
[ "$(init "$c" --write --trust=session-status-adapter@0000)" = "--trust=session-status-adapter@0000: session-status-adapter changed since it was shown: run session-status --init again and review it" ] ||
  { echo "init (s2) stale trust: $(init "$c" --write --trust=session-status-adapter@0000)"; exit 1; }
init "$c" --write >/dev/null; rm -f "$c/.claude/session-status-adapter"   # declined: the local one is written; drop it
[ "$(init "$c" --check)" = "partial: the committed .claude/coordination/session-status-adapter isn't trusted yet: run setup to review it" ] ||
  { echo "init (s2) untrusted check: $(init "$c" --check)"; exit 1; }
out=$(init "$c" --write --trust=session-status-adapter@"$sha") && [ ! -e "$c/.claude/session-status-adapter" ] &&
  [ "$(jq -r '.trusted["session-status-adapter"]' "$c/.claude/coordination.local.json")" = "$sha" ] &&
  grep -q "^configured: " <<<"$(init "$c" --check)" && [ "$(cd "$c" && HOME=$tmp "$here/session-status" --urls)" = team-urls ] &&
  [ -z "$(git -C "$c" status --short)" ] || { echo "init (s2) trusted: urls=$(cd "$c" && HOME=$tmp "$here/session-status" --urls 2>&1) / $(git -C "$c" status --short)"; exit 1; }
echo '# changed' >> "$c/.claude/coordination/session-status-adapter"
[ -z "$(cd "$c" && HOME=$tmp "$here/session-status" --urls 2>/dev/null)" ] &&
  [ "$(cd "$c" && HOME=$tmp "$here/session-status" --urls 2>&1)" = "warning: session-status-adapter changed upstream: run setup to review it" ] ||
  { echo "init (s2) changed upstream ran: $(cd "$c" && HOME=$tmp "$here/session-status" --urls 2>&1)"; exit 1; }
# (s3) a workspace: the repo one level down with a committed .claude/coordination/ becomes the team key, and its
# repo keys apply; no repo file is written in the workspace.
t=$(mkdir -p "$tmp/init/tws" && cd "$tmp/init/tws" && pwd -P); git clone -q "$s" "$t/sail"; mkdir -p "$t/other" && git -C "$t/other" init -q
jq '.tracker = "github"' "$t/sail/.claude/coordination/coordination.json" > "$t/x.json" && mv "$t/x.json" "$t/sail/.claude/coordination/coordination.json"
out=$(init "$t") && grep -F 'Team: sail/.claude/coordination/ is committed there, so its repo keys apply here (team=sail).' <<<"$out" >/dev/null &&
  init "$t" --write >/dev/null && [ "$(jq -r .team "$t/.claude/coordination.local.json")" = sail ] && [ ! -e "$t/.claude/coordination" ] &&
  [ "$(cd "$t" && "$here/session-status" --config tracker)" = github ] || { echo "init (s3) team: $out / $(cat "$t/.claude/coordination.local.json")"; exit 1; }
# (s4) two team repos: team= picks one, and its committed code is shown for review.
t2=$(mkdir -p "$tmp/init/tws2" && cd "$tmp/init/tws2" && pwd -P); git clone -q "$s" "$t2/one"; git clone -q "$c" "$t2/two"
out=$(init "$t2" team=two) && grep -F "     two/.claude/coordination/session-status-adapter (sha256 " <<<"$out" >/dev/null ||
  { echo "init (s4) team= override: $out"; exit 1; }
# (s5) personal files are never taken from a commit: a committed person file delegates nothing and isn't written to.
k=$(mkdir -p "$tmp/init/leak" && cd "$tmp/init/leak" && pwd -P); git -C "$k" init -q; mkdir -p "$k/.claude"
echo '{"approvals":{"delegate":true}}' > "$k/.claude/coordination.local.json"; printf '#!/bin/sh\n' > "$k/.claude/session-status-adapter"
chmod +x "$k/.claude/session-status-adapter"; git -C "$k" add -f .claude && gc "$k" -m leak
[ "$(cd "$k" && "$here/session-status" --config approvals.delegate 2>/dev/null)" = false ] &&
  (cd "$k" && "$here/session-status" --config approvals.delegate 2>&1 >/dev/null) | grep -qF 'is committed: a personal file is never read from git: ignored' &&
  [ "$(init "$k" --write 2>/dev/null)" = "refused: .claude/coordination.local.json is committed: git rm --cached it first" ] &&
  [ -z "$(git -C "$k" status --short)" ] || { echo "init (s5) committed person file: $(cd "$k" && "$here/session-status" --config approvals.delegate 2>&1)"; exit 1; }
# (s6) under a parent: --trust writes nothing until --own, and --own never writes the parent's repo file.
p=$(cd "$a" && pwd -P); mkdir -p "$p/sub1" "$p/sub2"; before=$(cat "$p/.claude/coordination/coordination.json" 2>/dev/null || :)
rc=0; init "$p/sub1" --write --trust=session-status-adapter@0000 >/dev/null || rc=$?
[ "$rc" = 3 ] && [ ! -e "$p/sub1/.claude" ] &&
  init "$p/sub2" --write --own tracker=github >/dev/null && [ "$(cat "$p/.claude/coordination/coordination.json" 2>/dev/null)" = "$before" ] &&
  [ "$(jq -r .tracker "$p/sub2/.claude/coordination/coordination.json")" = github ] || { echo "init (s6) under a parent: $(ls -a "$p/sub1" "$p/sub2/.claude")"; exit 1; }

# --plan: three waves, an overlap and an oversize est in wave 1, a self-cycle with an unknown dep, unknown kind and
# no done-when or effort in c6. c1 and c4 are done (c2's handoff isn't), so c2, c3 and c5 can run: c3 overlaps c2, so c2 and c5.
pd=$(mkdir -p "$tmp/plan" && cd "$tmp/plan" && pwd -P); plan=$pd/PROJ-123.md
cat > "$plan" <<'EOF'
# PROJ-123

## Plan

| # | Chunk | Kind | Deps | Touches | Est | Model/effort | Done when |
|---|---|---|---|---|---|---|---|
| 1 | parser | build | – | `src/a.sh` | 30K | opus/medium | suite green |
| 2 | docs | mechanical | – | `docs/*.md` | 20K | default | scrub ok |
| 3 | guide | scan | – | `docs/guide.md` | 70K | haiku/low | listed |
| 4 | hook | build | 1 | `lib/x.sh` | 40K | opus/medium | test green |
| 5 | review | review | c4 | `tests/`, `lib/` | 40K | opus/xhigh | findings file |
| 6 | loop | planning | 6, 9 | `notes/` | 10K | opus |  |
EOF
printf '## c1: done\nok\n## c2: handoff\nwip\n## c4: done\n' > "$pd/PROJ-123-build.md"
rc=0; out=$(run --plan "$plan" --check) || rc=$?
[ $rc = 1 ] && diff <(echo "$out") - <<'EOF' || { echo "--plan --check (rc $rc)"; exit 1; }
c3: est 70K over the 65K budget
c6: unknown dep 9
c6: unknown kind planning
c6: no done-when
c6: model/effort opus is not like opus/medium (efforts: low medium high xhigh max; no fable)
cycle: c6 → c6
c2 and c3 both touch docs/*.md ~ docs/guide.md
EOF
diff <(run --plan "$plan" --next) - <<EOF || { echo "--plan --next"; exit 1; }
waves: {1,2,3} → {4} → {5}
claude --bg --model sonnet --effort medium -n PROJ-123-c2 'Session task: PROJ-123
Chunk: PROJ-123/2
Read $pd/PROJ-123-c2.md and do it.'
claude --bg --model opus --effort xhigh -n PROJ-123-c5 'Session task: PROJ-123
Chunk: PROJ-123/5
Read $pd/PROJ-123-c5.md and do it.'
EOF
diff <(run --plan "$plan" | sed -n '5,7p') - <<'EOF' || { echo "--plan rows"; exit 1; }
c4   done     build      hook
c5   ready    review     review
c6   blocked  planning   loop
EOF
# One model/effort rule (lib.sh model_ok): no fable anywhere, efforts the CLI takes. --check reports a bad row, --next
# doesn't start it, config falls back to the default. plan.enabled false: --next starts nothing.
sed -e '/^| [2-6] /d' -e 's#| opus/medium | suite#| fable/high | suite#' "$plan" > "$pd/PROJ-8.md"
printf '| 2 | b | build | – | `b/` | 9K | claude-fable-5-1/high | x |\n| 3 | c | build | – | `c/` | 9K | opus/ultra | x |\n| 4 | d | build | – | `d/` | 9K | default | x |\n' >> "$pd/PROJ-8.md"
rc=0; out=$(run --plan "$pd/PROJ-8.md" --check) || rc=$?
[ $rc = 1 ] && [ "$(grep -c 'is not like opus/medium' <<<"$out")" = 3 ] || { echo "--check took fable or a bad effort: $out"; exit 1; }
mkdir -p "$tmp/.config/session-orchestration"; echo '{"plan": {"max_parallel": 5, "models": {"build": "claude-fable-5-1/high"}}}' > "$tmp/.config/session-orchestration/config.json"
out=$(run --plan "$pd/PROJ-8.md" --next 2>/dev/null)
! grep -q fable <<<"$(grep '^claude' <<<"$out")" && grep -q '^c1: model/effort fable/high not allowed' <<<"$out" &&
  grep -q '^claude --bg --model opus --effort medium -n PROJ-8-c4 ' <<<"$out" || { echo "--next started fable: $out"; exit 1; }
echo '{"plan": {"enabled": false}}' > "$tmp/.config/session-orchestration/config.json"
[ "$(run --plan "$plan" --next | tail -1)" = 'plan.enabled is false: run tasks without a plan' ] && ! run --plan "$plan" --next | grep -q '^claude' ||
  { echo "--next ran with plan.enabled false"; exit 1; }
rm "$tmp/.config/session-orchestration/config.json"
out=$(run --plan "$plan" --brief 2)
grep -qxF 'Kind: mechanical · Model: sonnet/medium · Est: 20K growth · Deps: none · Wave 1' <<<"$out" &&
  grep -qxF "**First:** read \`$pd/PROJ-123-chunk-rules.md\` (paths, setup, interface, landing). N = 2." <<<"$out" &&
  grep -qxF '**Touches:** `docs/*.md`.' <<<"$out" && grep -qxF '**Done when:** scrub ok' <<<"$out" &&
  [ "$(run --plan "$plan" --brief 9 2>&1)" = "no row 9 in $plan" ] || { echo "--plan --brief: $out"; exit 1; }
# --plan --done N: row 2 (mechanical, default: sonnet/medium, 20K) with this session's act from rnd.py (growth: 20K + 35K,
# the first request not counted). telemetry off: nothing logged, and why. usage refuses a malformed chunk line.
rm -f "$tmp/state"   # the stub's state file from above: the usage log lives under it
did=eeeeeeee-2222-3333-4444-555555555555 now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
{ jq -nc --arg t "$now" '{type: "user", timestamp: $t, message: {content: "Session task: PROJ-123\nChunk: PROJ-123/2\nGo."}}'
  for c in 1:10000 2:30000 3:25000 4:60000; do
    jq -nc --arg t "$now" --arg i "m${c%%:*}" --argjson x "${c#*:}" '{type: "assistant", timestamp: $t, message: {id: $i, model: "claude-sonnet", usage: {input_tokens: $x}}}'; done
} > "$proj/$did.jsonl"
[ "$(CLAUDE_CODE_SESSION_ID=$did run --plan "$plan" --done 2)" = 'nothing logged: telemetry is off, not local (config telemetry)' ] || { echo "--plan --done, telemetry off"; exit 1; }
mkdir -p "$tmp/.config/session-orchestration"; echo '{"telemetry": "local"}' > "$tmp/.config/session-orchestration/config.json"
out=$(CLAUDE_CODE_SESSION_ID=$did run --plan "$plan" --done c2)
[ "$(sed -E 's/"t":[0-9]+/"t":T/' <<<"$out")" = '{"t":T,"k":"chunk","what":"mechanical","model":"sonnet","effort":"medium","est":20,"act":55}' ] &&
  [ "$(tail -1 "$tmp/state/session-orchestration/usage.jsonl")" = "$out" ] || { echo "--plan --done: $out"; exit 1; }
n0=$(wc -l < "$tmp/state/session-orchestration/usage.jsonl")
(cd "$root" && HOME=$tmp XDG_STATE_HOME=$tmp/state bash -c '. "$0"; usage build chunk opus loud 60 1; usage build chunk opus medium 6x; usage build chunk opus medium 60 1 extra
  usage PROJ-9 chunk opus medium 60; usage build chunk /home/u medium 60' "$here/../../lib.sh")
[ "$(wc -l < "$tmp/state/session-orchestration/usage.jsonl")" = "$n0" ] || { echo "usage took a malformed chunk line"; tail -2 "$tmp/state/session-orchestration/usage.jsonl"; exit 1; }
rm "$tmp/.config/session-orchestration/config.json"
# Plan cells: a lone `|` row is skipped; Deps `—`/`none`/`None` and Touches `—` name nothing. --check: a window other
# than compact.window is one info line on stderr, exit 0. --next: of four ready rows, three under hooks/, the cap keeps
# c1 and skills/'s c4, past max_parallel 3; an account defaulting to plan gets --permission-mode default before --model.
cat > "$pd/PROJ-9.md" <<'EOF'
## Plan

| # | Chunk | Kind | Deps | Touches | Est | Model/effort | Done when |
|---|---|---|---|---|---|---|---|
| 1 | a | build | — | `hooks/a.sh` | 9K | default | x |
|
| 2 | b | build | none | `hooks/b.sh` | 9K | default | x |
| 3 | c | build | None | `hooks/c.sh` | 9K | default | x |
| 4 | d | build | — | `skills/d.sh` | 9K | default | x |
| 5 | e | build | 1 | — | 9K | default | x |
EOF
out=$(CLAUDE_CODE_AUTO_COMPACT_WINDOW= run --plan "$pd/PROJ-9.md" --check 2>&1) && [ -z "$out" ] || { echo "--plan --check, clean plan: $out"; exit 1; }
out=$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=180000 run --plan "$pd/PROJ-9.md" --check 2>&1) &&
  [ "$out" = 'window 180000 from env; expected 220000' ] || { echo "--plan --check, window: $out"; exit 1; }
echo '{"permissions":{"defaultMode":"plan"}}' > "$tmp/cfg/settings.json"
out=$(run --plan "$pd/PROJ-9.md" --next | grep '^claude' | sed "s/ 'Session.*//")
[ "$out" = 'claude --bg --permission-mode default --model opus --effort medium -n PROJ-9-c1
claude --bg --permission-mode default --model opus --effort medium -n PROJ-9-c4' ] || { echo "--plan --next, cap and plan mode: $out"; exit 1; }
echo '{}' > "$tmp/cfg/settings.json"
run --plan "$pd/PROJ-9.md" --next | grep -q '^claude --bg --model opus --effort medium -n PROJ-9-c1 ' || { echo "--plan --next, plain account"; exit 1; }
echo ok

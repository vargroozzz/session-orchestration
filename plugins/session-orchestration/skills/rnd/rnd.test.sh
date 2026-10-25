#!/usr/bin/env bash
# Self-check for rnd.py and rnd-weekly: synthetic transcripts in three accounts (~/.claude, ~/.claude-work sharing its
# projects/ by symlink, ~/.claude-other with its own), a fixed --until window, and a stubbed claude for the launcher.
# Run: bash rnd.test.sh  (prints "ok" or the failed check).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
home=$tmp/home; a=$home/.claude/projects/-x-proj b=$home/.claude-other/projects/-x-other
mkdir -p "$a" "$b" "$home/.claude-work" "$tmp/bin"
ln -s "$home/.claude/projects" "$home/.claude-work/projects"

# In the window (until 2026-10-13T12:00:00, 7 days): one human message, two requests, a `!` handoff, an admitted
# mistake, a refused Bash call, a background watcher whose notice comes after the window, and a cron wake.
# Outside it: a 2020 request and one a second after the window.
cat > "$a/aaaaaaaa-1111.jsonl" <<'EOF'
{"type":"agent-name","agentName":"worker"}
{"type":"user","timestamp":"2020-01-01T00:00:00.000Z","message":{"content":"old prompt"}}
{"type":"assistant","timestamp":"2020-01-01T00:00:01.000Z","requestId":"r0","message":{"usage":{"output_tokens":999999}}}
{"type":"user","timestamp":"2026-10-12T10:00:00.000Z","message":{"content":"Work on ABC-1"}}
{"type":"assistant","timestamp":"2026-10-12T10:00:05.000Z","requestId":"r1","message":{"usage":{"input_tokens":10,"output_tokens":1000,"cache_read_input_tokens":40000,"cache_creation_input_tokens":2000},"content":[{"type":"text","text":"Run `! gh auth login` please. My mistake earlier."},{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"gh pr merge 7"}}]}}
{"type":"user","timestamp":"2026-10-12T10:20:00.000Z","permissionDecision":{"decision":"reject","source":"classifier","reasonType":"x"},"message":{"content":[{"type":"tool_result","tool_use_id":"t1","is_error":true,"content":"denied"}]}}
{"type":"assistant","timestamp":"2026-10-12T10:21:00.000Z","requestId":"r2","message":{"usage":{"input_tokens":5,"output_tokens":100,"cache_read_input_tokens":50000},"content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"pr-watch 5","run_in_background":true}}]}}
{"type":"user","timestamp":"2026-10-12T10:21:01.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"t2","content":"Command running in background with ID: bg1"}]}}
{"type":"system","subtype":"scheduled_task_fire","timestamp":"2026-10-13T11:00:00.000Z"}
{"type":"assistant","timestamp":"2026-10-13T11:00:01.000Z","requestId":"r3","message":{"usage":{"output_tokens":10}}}
{"type":"user","timestamp":"2026-10-13T12:00:01.000Z","message":{"content":"<task-notification><task-id>bg1</task-id><status>completed</status> exit code 0</task-notification>"}}
{"type":"assistant","timestamp":"2026-10-13T12:00:02.000Z","requestId":"r4","message":{"usage":{"output_tokens":555555}}}
EOF
# Two watchers whose notices arrive batched in one line (one failed), and a third with no notice in a session active
# 10 minutes before the window's end: still running, not lost.
cat > "$a/cccccccc-3333.jsonl" <<'EOF'
{"type":"assistant","timestamp":"2026-10-13T09:00:00.000Z","requestId":"c1","message":{"usage":{"output_tokens":1},"content":[{"type":"tool_use","id":"u2","name":"Bash","input":{"command":"pr-watch 6","run_in_background":true}},{"type":"tool_use","id":"u3","name":"Bash","input":{"command":"pr-watch 7","run_in_background":true}},{"type":"tool_use","id":"u4","name":"Bash","input":{"command":"pr-watch 8","run_in_background":true}}]}}
{"type":"user","timestamp":"2026-10-13T09:00:01.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"u2","content":"with ID: bg2"},{"type":"tool_result","tool_use_id":"u3","content":"with ID: bg3"},{"type":"tool_result","tool_use_id":"u4","content":"with ID: bg4"}]}}
{"type":"user","timestamp":"2026-10-13T09:30:00.000Z","message":{"content":"<task-notification><task-id>bg2</task-id><status>completed</status> exit code 0</task-notification>\n<task-notification><task-id>bg3</task-id><status>failed</status> exit code 1</task-notification>"}}
{"type":"user","timestamp":"2026-10-13T11:50:00.000Z","message":{"content":"still here"}}
EOF
cat > "$b/bbbbbbbb-2222.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-10-10T09:00:00.000Z","message":{"content":"other account"}}
{"type":"assistant","timestamp":"2026-10-10T09:00:01.000Z","requestId":"q1","message":{"usage":{"output_tokens":40000}}}
EOF

rnd() { HOME=$home CLAUDE_CONFIG_DIR=$home/.claude-work python3 -I "$here/rnd.py" --until 2026-10-13T12:00:00 "$@"; }
fail() { echo "FAIL: $1"; echo "$2"; exit 1; }
row() { awk -F'\t' -v s="$1" '$2 == s' <<<"$out"; }

out=$(rnd sessions 7)
[ "$(wc -l <<<"$out")" -eq 4 ] || fail "sessions: header + 3 sessions, the shared tree read once" "$out"
[ "$(row aaaaaaaa | cut -f1-9,12-16)" = $'-x-proj\taaaaaaaa\tworker\t2026-10-12T10:00\t2026-10-13T11:00\t3\t50005\t0\t1110\t0.09\t1\t1\t1\t0' ] \
  || fail "sessions: window, peak, usd, human, denial, bang" "$out"
[ "$(row bbbbbbbb | cut -f6,9)" = $'1\t40000' ] || fail "sessions: the other account's tree" "$out"

out=$(rnd events 7)
for k in human bang self deny bash; do grep -q $'\t'"$k"$'\t' <<<"$out" || fail "events: a $k row" "$out"; done
grep -q 'old prompt' <<<"$out" && fail "events: the 2020 line is outside the window" "$out"
grep -q $'deny\tBash: gh pr merge 7\tclassifier/x' <<<"$out" || fail "events: deny row with source/reason" "$out"

out=$(rnd waits 7 5)
grep -q $'aaaaaaaa\t2026-10-12T10:00\t20\tBash' <<<"$out" || fail "waits: the 20-minute refused call" "$out"

out=$(rnd bgtasks pr-watch 7 2>&1)
grep -q $'aaaaaaaa\t2026-10-12T10:21\tSILENT' <<<"$out" || fail "bgtasks: a notice after the window leaves the task silent" "$out"
grep -q $'cccccccc\t2026-10-13T09:00\tcompleted/exit 0\t30m\tpr-watch 6' <<<"$out" \
  && grep -q $'cccccccc\t2026-10-13T09:00\tfailed/exit 1\t30m\tpr-watch 7' <<<"$out" || fail "bgtasks: batched notices read one by one" "$out"
grep -q $'cccccccc\t2026-10-13T09:00\tNO NOTICE YET.*pr-watch 8' <<<"$out" || fail "bgtasks: a task in a live session isn't lost" "$out"
grep -q "{'launched': 4, 'notified': 2, 'silent': 1, 'running': 1}" <<<"$out" || fail "bgtasks: totals" "$out"
out=$(HOME=$home CLAUDE_CONFIG_DIR=$home/.claude-work python3 -I "$here/rnd.py" --until 2026-10-13T12:00:05 bgtasks pr-watch 7 2>&1)
grep -q $'aaaaaaaa\t2026-10-12T10:21\tcompleted/exit 0' <<<"$out" || fail "bgtasks: notified once the window covers it" "$out"

out=$(rnd triggers aaaaaaaa 7)
grep -q $'aaaaaaaa\tcron\twakes=1\trequests=1' <<<"$out" || fail "triggers: the cron wake" "$out"
grep -q $'aaaaaaaa\thuman\twakes=1\trequests=2' <<<"$out" || fail "triggers: the human wake" "$out"
[ "$(rnd triggers worker 7 | cut -f2,3)" = "$(cut -f2,3 <<<"$out")" ] || fail "triggers: by session name" "$(rnd triggers worker 7)"
rnd triggers nobody 7 2>/dev/null && fail "triggers: an unknown session fails" ""

# Added after the checks above so their session counts stay put: a watcher notice line with no timestamp, a task
# session that wrote its reply, and one that went idle without writing it (opened with /clear; it wrote only a
# lookalike key's file, and its own reply after the window's end).
cat > "$a/dddddddd-4444.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-10-11T08:00:00.000Z","message":{"content":"Work on DEF-2"}}
{"type":"assistant","timestamp":"2026-10-11T08:00:05.000Z","requestId":"d1","message":{"content":[{"type":"tool_use","id":"w1","name":"Write","input":{"file_path":"/p/replies/DEF-2.md"}},{"type":"tool_use","id":"w2","name":"Bash","input":{"command":"pr-watch 9","run_in_background":true}}]}}
{"type":"user","timestamp":"2026-10-11T08:00:06.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"w2","content":"with ID: bg9"}]}}
{"type":"user","message":{"content":"<task-notification><task-id>bg9</task-id><status>completed</status> exit code 0</task-notification>"}}
EOF
cat > "$a/eeeeeeee-5555.jsonl" <<'EOF'
{"type":"agent-name","agentName":"quiet"}
{"type":"user","timestamp":"2026-10-11T08:59:00.000Z","message":{"content":"<command-name>/clear</command-name>"}}
{"type":"user","timestamp":"2026-10-11T09:00:00.000Z","message":{"content":"Work on https://jira.example/browse/GHI-3"}}
{"type":"assistant","timestamp":"2026-10-11T09:00:05.000Z","requestId":"e1","message":{"content":[{"type":"tool_use","id":"e2","name":"Write","input":{"file_path":"/p/replies/GHI-33.md"}}]}}
{"type":"assistant","timestamp":"2026-10-13T12:30:00.000Z","requestId":"e3","message":{"content":[{"type":"tool_use","id":"e4","name":"Write","input":{"file_path":"/p/replies/GHI-3.md"}}]}}
EOF
out=$(rnd bgtasks pr-watch 7 2>&1)
grep -q $'dddddddd\t2026-10-11T08:00\tcompleted/exit 0\t0m\tpr-watch 9' <<<"$out" || fail "bgtasks: a notice with no timestamp" "$out"
out=$(rnd replies 7 2>&1)
grep -q $'eeeeeeee\tGHI-3\t2026-10-11T09:00\tquiet' <<<"$out" || fail "replies: the lost one" "$out"
grep -q 'DEF-2' <<<"$out" && fail "replies: a written reply isn't lost" "$out"
grep -q "{'task': 2, 'wrote': 1, 'lost': 1, 'open': 0}" <<<"$out" || fail "replies: totals" "$out"

# Added after the counts above too: a headless permission test (-p) with a denial; a review session that posted a
# comment and whose user ran a `!` command; a task session with a merge that ran, one that was denied, and a heredoc
# that only mentions one (an api-request-blob repeats its call with no timestamp); and a fork sharing 10 messages.
cat > "$a/ffffffff-6666.jsonl" <<'EOF'
{"type":"user","entrypoint":"sdk-cli","timestamp":"2026-10-12T08:00:00.000Z","message":{"content":"try rm"}}
{"type":"assistant","timestamp":"2026-10-12T08:00:01.000Z","requestId":"f1","message":{"usage":{"output_tokens":1},"content":[{"type":"tool_use","id":"f2","name":"Bash","input":{"command":"rm -rf x"}}]}}
{"type":"user","timestamp":"2026-10-12T08:00:02.000Z","permissionDecision":{"decision":"reject","source":"config","reasonType":"mode"},"message":{"content":[{"type":"tool_result","tool_use_id":"f2","is_error":true,"content":"denied"}]}}
EOF
cat > "$a/gggggggg-7777.jsonl" <<'EOF'
{"type":"agent-name","agentName":"pr-review-proj-9"}
{"type":"user","timestamp":"2026-10-12T09:00:00.000Z","message":{"content":"Review PR 9"}}
{"type":"assistant","timestamp":"2026-10-12T09:00:01.000Z","requestId":"g1","message":{"usage":{"input_tokens":1000000},"content":[{"type":"tool_use","id":"g2","name":"Bash","input":{"command":"npx bitbucketdc-cli@latest pr comment create 9 --repo app --body-file /p/b.md"}}]}}
{"type":"user","timestamp":"2026-10-12T09:00:02.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"g2","content":"posted"}]}}
{"type":"user","timestamp":"2026-10-12T09:05:00.000Z","message":{"content":"<bash-input>plugin-release rnd-x</bash-input>"}}
EOF
cat > "$a/hhhhhhhh-8888.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-10-12T11:00:00.000Z","message":{"content":"Work on ABC-9"}}
{"type":"assistant","timestamp":"2026-10-12T11:00:01.000Z","requestId":"h1","message":{"usage":{"input_tokens":250000},"content":[{"type":"tool_use","id":"h2","name":"Bash","input":{"command":"npx bitbucketdc-cli@latest pr merge 11 --repo app"}},{"type":"tool_use","id":"h3","name":"Bash","input":{"command":"npx bitbucketdc-cli@latest pr merge 12 --repo app"}},{"type":"tool_use","id":"h4","name":"Bash","input":{"command":"cat > notes.md <<'X'\nnext: pr merge 13\nX"}}]}}
{"type":"user","timestamp":"2026-10-12T11:00:02.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"h2","content":"merged"},{"type":"tool_result","tool_use_id":"h4","content":""}]}}
{"type":"user","timestamp":"2026-10-12T11:00:03.000Z","permissionDecision":{"decision":"reject","source":"hook","reasonType":"hook"},"message":{"content":[{"type":"tool_result","tool_use_id":"h3","is_error":true,"content":"denied"}]}}
{"type":"api-request-blob","message":{"role":"assistant","content":[{"type":"tool_use","id":"h5","name":"Bash","input":{"command":"npx jiradc-cli@latest issue transition ABC-9 --to \"Ready for Test\""}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"h5","content":"ok"}]}}
EOF
# Other hosts: a gh merge with -R before the number, a glab merge, and a gh review posted from a review session.
cat > "$a/kkkkkkkk-1111.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-10-12T12:00:00.000Z","message":{"content":"Work on ABC-10"}}
{"type":"assistant","timestamp":"2026-10-12T12:00:01.000Z","message":{"content":[{"type":"tool_use","id":"k1","name":"Bash","input":{"command":"gh pr merge -R acme/app 21 --squash"}},{"type":"tool_use","id":"k2","name":"Bash","input":{"command":"glab mr merge 22"}}]}}
{"type":"user","timestamp":"2026-10-12T12:00:02.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"k1","content":"merged"},{"type":"tool_result","tool_use_id":"k2","content":"merged"}]}}
EOF
cat > "$a/llllllll-2222.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-10-12T12:10:00.000Z","message":{"content":"Review acme/app#23"}}
{"type":"assistant","timestamp":"2026-10-12T12:10:01.000Z","message":{"content":[{"type":"tool_use","id":"l1","name":"Bash","input":{"command":"gh pr review 23 -R acme/app --request-changes --body-file /p/r.md"}}]}}
{"type":"user","timestamp":"2026-10-12T12:10:02.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"l1","content":"ok"}]}}
EOF
uu() { for i in 0 1 2 3 4 5 6 7 8 9; do printf '{"type":"user","uuid":"u%s","message":{"content":"x"}}\n' "$i"; done; }
uu > "$a/iiiiiiii-9999.jsonl"; uu > "$a/jjjjjjjj-0000.jsonl"
out=$(rnd events 7)
grep -q $'ffffffff\t2026-10-12T08:00\tdeny\tBash: rm -rf x\tconfig/mode\t-p' <<<"$out" || fail "events: a -p session's deny is tagged test" "$out"
grep -q $'aaaaaaaa\t2026-10-12T10:20\tdeny\tBash: gh pr merge 7\tclassifier/x\t$' <<<"$out" || fail "events: a real deny has an empty test column" "$out"
grep -q $'gggggggg\t2026-10-12T09:05\tran\tplugin-release rnd-x' <<<"$out" || fail "events: a ran row for the user's ! command" "$out"
out=$(rnd units 7 2>&1)
grep -q $'^merge\tapp#11\thhhhhhhh\t2026-10-12T11:00' <<<"$out" || fail "units: the merge that ran" "$out"
grep -qE $'^merge\t([^\t]*#)?7\t' <<<"$out" && fail "units: a denied merge (gh) doesn't count" "$out"
grep -qE $'^merge\t([^\t]*#)?1[23]\t' <<<"$out" && fail "units: a denied merge or a heredoc mention doesn't count" "$out"
grep -q $'^done\t' <<<"$out" && fail "units: an api-request-blob's call isn't a unit" "$out"
grep -q $'^post\tapp#9\tgggggggg' <<<"$out" || fail "units: a review session's post" "$out"
grep -q $'^merge\tacme/app#21\tkkkkkkkk' <<<"$out" && grep -q $'^merge\t22\tkkkkkkkk' <<<"$out" &&
  grep -q $'^post\tacme/app#23\tllllllll' <<<"$out" || fail "units: gh -R, glab, gh pr review" "$out"
grep -q 'merge=3 .*post=2 per_post=2.5' <<<"$out" || fail "units: totals, per post over review sessions" "$out"
[ "$(rnd units 7 --project nomatch 2>&1 >/dev/null)" = 'usd=0 review_usd=0.0 merge=0 done=0 post=0' ] || fail "units: --project filters" "$(rnd units 7 --project nomatch 2>&1)"
out=$(rnd context 7 2026-10-12T10:30 other)
grep -q $'^over\thhhhhhhh\t1\t50000\t250000' <<<"$out" || fail "context: the session over 200K" "$out"
grep -q $'^fork\tiiiiiiii\tjjjjjjjj\t10' <<<"$out" || fail "context: the fork" "$out"
grep -qE $'^all\t[0-9]+\t' <<<"$out" && grep -qE $'^since 2026-10-12T10:30\t3\t83333\t0\t1\t50000\t250000\t2$' <<<"$out" && grep -qE $'^project other\t1\t0\t0\t0\t0\t0\t1$' <<<"$out" \
  || fail "context: scopes" "$out"

printf '# T\n\n| a | b |\n|---|---|\n| `x` | **y** |\n\n- one\n  - two\n\n1. first\n   more\n2. second\n\n```\na < b\n  c\n```\n' > "$tmp/r.md"
rnd html "$tmp/r.md" "$tmp/r.html"
grep -q '<title>T</title>' "$tmp/r.html" && grep -q '<td><code>x</code></td><td><strong>y</strong></td>' "$tmp/r.html" \
  && grep -q '<ul><li>one<ul><li>two</li></ul></li></ul>' "$tmp/r.html" \
  && grep -q '<ol><li>first more</li><li>second</li></ol>' "$tmp/r.html" \
  && grep -q '<pre><code>a &lt; b' "$tmp/r.html" || fail "html" "$(cat "$tmp/r.html")"
# a line starting with `#` that isn't a heading: once looped forever
printf 'see PRs\n#3879 and #4490\n\n#3879 alone\n' > "$tmp/h.md"
rnd html "$tmp/h.md" "$tmp/h.html"
grep -q '<p>see PRs #3879 and #4490</p><p>#3879 alone</p>' "$tmp/h.html" || fail "html: # line in a paragraph" "$(cat "$tmp/h.html")"

printf '#!/bin/sh\necho "$@" > %q\n' "$tmp/claude.args" > "$tmp/bin/claude"; chmod +x "$tmp/bin/claude"
out=$(HOME=$tmp RND_LOG=$tmp/log "$here/rnd-weekly" "$tmp" --dry-run)
grep -q 'claude --bg -n rnd-weekly-' <<<"$out" && [ ! -e "$tmp/claude.args" ] || fail "rnd-weekly --dry-run starts nothing" "$out"
HOME=$tmp RND_LOG=$tmp/log "$here/rnd-weekly" "$tmp"
grep -q 'session-orchestration:rnd' "$tmp/claude.args" && grep -q "start in $tmp" "$tmp/log" || fail "rnd-weekly starts the run" "$(cat "$tmp/log")"
HOME=$tmp RND_LOG=$tmp/log "$here/rnd-weekly" "$tmp/nope" && fail "rnd-weekly: a missing root fails" ""
grep -q "no project root $tmp/nope" "$tmp/log" || fail "rnd-weekly logs a missing root" "$(cat "$tmp/log")"
echo ok

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
{"type":"assistant","timestamp":"2026-10-12T11:00:01.000Z","requestId":"h1","message":{"usage":{"input_tokens":250000},"content":[{"type":"tool_use","id":"h2","name":"Bash","input":{"command":"npx bitbucketdc-cli@latest pr merge 11 --repo app"}},{"type":"tool_use","id":"h3","name":"Bash","input":{"command":"npx bitbucketdc-cli@latest pr merge 12 --repo app"}},{"type":"tool_use","id":"h4","name":"Bash","input":{"command":"cat > notes.md <<'X'\nnext: npx bitbucketdc-cli@latest pr merge 13 --repo app\nX\ngrep -n 'glab mr merge 13' notes.md"}}]}}
{"type":"user","timestamp":"2026-10-12T11:00:02.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"h2","content":"merged"},{"type":"tool_result","tool_use_id":"h4","content":""}]}}
{"type":"user","timestamp":"2026-10-12T11:00:03.000Z","permissionDecision":{"decision":"reject","source":"hook","reasonType":"hook"},"message":{"content":[{"type":"tool_result","tool_use_id":"h3","is_error":true,"content":"Background session: this compound command\nwill wait on a prompt; split it"}]}}
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
grep -q $'ffffffff\t2026-10-12T08:00\tdeny\tBash: rm -rf x\tconfig/mode: denied\t-p' <<<"$out" || fail "events: a -p session's deny is tagged test" "$out"
grep -q $'aaaaaaaa\t2026-10-12T10:20\tdeny\tBash: gh pr merge 7\tclassifier/x: denied\t$' <<<"$out" || fail "events: a real deny has an empty test column" "$out"
grep -q $'gggggggg\t2026-10-12T09:05\tran\tplugin-release rnd-x' <<<"$out" || fail "events: a ran row for the user's ! command" "$out"
grep -q $'hhhhhhhh\t2026-10-12T11:00\tdeny\tBash: npx bitbucketdc-cli@latest pr merge 12 --repo app\thook/hook: Background session: this compound command will wait' <<<"$out" ||
  fail "events: a deny row carries the hook's message" "$out"
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

# usage: a press in the window counts; one there since 09-01 with none is unused; a 2026-01-01 line is trimmed.
st=$tmp/state/session-orchestration; mkdir -p "$st/inventory"
echo '[["press","attach"],["press","compact"]]' > "$st/inventory/2026-09-01.json"
printf '%s\n' '{"t":1791799200,"k":"press","what":"attach"}' '{"t":1767225600,"k":"press","what":"compact"}' 'junk' > "$st/usage.jsonl"
out=$(XDG_STATE_HOME=$tmp/state rnd usage)
grep -qx $'press\tattach\t1\t2026-09-01\t' <<<"$out" && grep -qx $'press\tcompact\t0\t2026-09-01\tunused' <<<"$out" \
  && grep -q $'^press\tcopy-command\t0\t'"$(date -u +%F)"$'\t$' <<<"$out" && grep -q $'^flag\t--peek\t.*[0-9-]\t$' <<<"$out" \
  && [ "$(wc -l < "$st/usage.jsonl" | tr -d ' ')" = 1 ] && [ -e "$st/inventory/$(date -u +%F).json" ] || fail "usage" "$out"
# every config() key line, not only the tracker one
grep -q $'^config\ttracker\t' <<<"$out" && grep -q $'^config\tplan.max_parallel\t' <<<"$out" && grep -q $'^config\thandoff.at.chunk\t' <<<"$out" ||
  fail "usage: config keys" "$(grep '^config' <<<"$out")"

# chunks and trial: chunk PROJ-1/1 in two sessions, the first compacted before it handed off (growth 20K, then 10K
# after the compaction; the jump across it doesn't count, nor its summary as a step-in), with a /plug:code-review run
# whose subagent's ReportFindings call has 2 findings, a human message, a `!` command and a merge; its successor
# joins through Supersedes: (+5K). PROJ-2 is the off arm, one $5 session with a merge. Usage log: this chunk's line
# (14:10) and an older build chunk for the ratio.
cat > "$a/abcdef01-1111.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-10-12T13:00:00.000Z","message":{"content":"Session task: PROJ-1\nChunk: PROJ-1/1\nRead the brief."}}
{"type":"assistant","timestamp":"2026-10-12T13:00:01.000Z","requestId":"m1","message":{"model":"claude-opus-5-5","usage":{"input_tokens":10000},"content":[{"type":"tool_use","id":"m9","name":"Bash","input":{"command":"gh pr merge 31"}}]}}
{"type":"user","timestamp":"2026-10-12T13:00:02.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"m9","content":"merged"}]}}
{"type":"assistant","timestamp":"2026-10-12T13:01:00.000Z","requestId":"m2","message":{"model":"claude-opus-5-5","usage":{"input_tokens":10,"cache_read_input_tokens":20000,"cache_creation_input_tokens":9990}}}
{"type":"user","timestamp":"2026-10-12T13:02:00.000Z","message":{"content":"<command-name>/plug:code-review</command-name>"}}
{"type":"user","timestamp":"2026-10-12T13:03:00.000Z","message":{"content":"also fix the tests"}}
{"type":"user","timestamp":"2026-10-12T13:04:00.000Z","message":{"content":"<bash-input>git status</bash-input>"}}
{"type":"system","subtype":"compact_boundary","timestamp":"2026-10-12T13:10:00.000Z"}
{"type":"user","isCompactSummary":true,"timestamp":"2026-10-12T13:10:01.000Z","message":{"content":"This session is being continued from a previous conversation."}}
{"type":"assistant","timestamp":"2026-10-12T13:11:00.000Z","requestId":"m3","message":{"model":"claude-opus-5-5","usage":{"input_tokens":50000}}}
{"type":"assistant","timestamp":"2026-10-12T13:12:00.000Z","requestId":"m4","message":{"model":"claude-opus-5-5","usage":{"input_tokens":60000}}}
EOF
mkdir -p "$a/abcdef01-1111/subagents"
cat > "$a/abcdef01-1111/subagents/agent-r.jsonl" <<'EOF'
{"type":"assistant","timestamp":"2026-10-12T13:05:00.000Z","message":{"content":[{"type":"tool_use","id":"m8","name":"ReportFindings","input":{"findings":[{"file":"a"},{"file":"b"}]}}]}}
EOF
# A fork review that returns its finding as a JSON block in its last message.
cat > "$a/abcdef01-1111/subagents/agent-s.jsonl" <<'EOF'
{"type":"assistant","timestamp":"2026-10-12T13:06:00.000Z","message":{"content":[{"type":"text","text":"One finding.\n\n```json\n[{\"file\":\"c\",\"failure_scenario\":\"x\"}]\n```"}]}}
EOF
cat > "$a/nnnnnnnn-2222.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-10-12T13:30:00.000Z","message":{"content":"Work on PROJ-1: continue. Supersedes: abcdef01 (transcript x)"}}
{"type":"assistant","timestamp":"2026-10-12T13:30:01.000Z","requestId":"n1","message":{"model":"claude-opus-5-5","usage":{"input_tokens":20000}}}
{"type":"assistant","timestamp":"2026-10-12T14:00:00.000Z","requestId":"n2","message":{"model":"claude-opus-5-5","usage":{"input_tokens":25000}}}
EOF
cat > "$a/oooooooo-3333.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-10-12T15:00:00.000Z","message":{"content":"Session task: PROJ-2\nDo it."}}
{"type":"assistant","timestamp":"2026-10-12T15:00:01.000Z","requestId":"o1","message":{"model":"claude-opus-5-5","usage":{"input_tokens":1000000},"content":[{"type":"tool_use","id":"o9","name":"Bash","input":{"command":"gh pr merge 41"}}]}}
{"type":"user","timestamp":"2026-10-12T15:00:02.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"o9","content":"merged"}]}}
EOF
printf '%s\n' '{"t":1791814200,"k":"chunk","what":"build","model":"opus","effort":"medium","est":50,"act":35}' \
  '{"t":1791795600,"k":"chunk","what":"build","model":"opus","effort":"medium","est":20,"act":20}' >> "$st/usage.jsonl"
out=$(XDG_STATE_HOME=$tmp/state rnd chunks 7)
[ "$(grep -v '^key' <<<"$out")" = $'PROJ-1\t1\tbuild/opus/medium\t50\t35\t60000\t20000\t0\t0.93\t6\t1\tafter\t60\nratio\tbuild\t0.85\tn=2' ] \
  || fail "chunks: two sessions summed, the log line matched, handoff after a compaction, ratio" "$out"
out=$(rnd chunks 7 --session nnnnnnnn)
grep -q $'^-\tnnnnnnnn\t?/opus/?\t?\t35\t60000\t' <<<"$out" || fail "chunks --session: summed over its Supersedes: chain, no log" "$out"
out=$(rnd trial 7)
# The off arm also has the `Work on ABC-n` sessions above (ABC-1, ABC-9 with merge 11; kkkkkkkk has no requests).
for m in $'tasks\t1\t3' $'units\t1\t2' $'usd_per_unit_median\t0.93\t3.12' $'usd_per_unit_total\t0.93\t' $'compacts_per_session\t0.5\t' \
  $'handoffs_after\t1\t0' $'findings_per_unit\t3.0\t0.0' $'reviews_per_unit\t1.0\t0.0' $'stepins_per_unit\t2.0\t'; do
  grep -q "^$m" <<<"$out" || fail "trial: $m" "$out"
done

# chunks joins a log line by the t the session's own `--plan --done` printed: PROJ-3/1 (growth 10K) printed A, PROJ-3/2
# (30K, starting inside c1's time window) printed B and quoted A in another tool result. By time and closest act,
# c1 would take B (act 10).
cat > "$a/pppppppp-1111.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-10-12T16:00:00.000Z","message":{"content":"Session task: PROJ-3\nChunk: PROJ-3/1\nGo."}}
{"type":"assistant","timestamp":"2026-10-12T16:00:01.000Z","requestId":"p1","message":{"model":"claude-opus-5-5","usage":{"input_tokens":10000}}}
{"type":"assistant","timestamp":"2026-10-12T16:10:00.000Z","requestId":"p2","message":{"model":"claude-opus-5-5","usage":{"input_tokens":20000},"content":[{"type":"tool_use","id":"pd","name":"Bash","input":{"command":"session-status --plan R/PROJ-3.md --done 1"}}]}}
{"type":"user","timestamp":"2026-10-12T16:10:01.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"pd","content":"{\"t\":1791821400,\"k\":\"chunk\",\"what\":\"scan\",\"model\":\"opus\",\"effort\":\"low\",\"est\":11,\"act\":30}"}]}}
EOF
cat > "$a/qqqqqqqq-1111.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-10-12T16:20:00.000Z","message":{"content":"Session task: PROJ-3\nChunk: PROJ-3/2\nGo."}}
{"type":"assistant","timestamp":"2026-10-12T16:20:01.000Z","requestId":"q1","message":{"model":"claude-opus-5-5","usage":{"input_tokens":10000},"content":[{"type":"tool_use","id":"qc","name":"Bash","input":{"command":"cat R/PROJ-3-build.md"}}]}}
{"type":"user","timestamp":"2026-10-12T16:20:02.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"qc","content":"{\"t\":1791821400,\"k\":\"chunk\",\"what\":\"scan\"}"}]}}
{"type":"assistant","timestamp":"2026-10-12T16:30:00.000Z","requestId":"q2","message":{"model":"claude-opus-5-5","usage":{"input_tokens":40000},"content":[{"type":"tool_use","id":"qd","name":"Bash","input":{"command":"session-status --plan R/PROJ-3.md --done 2"}}]}}
{"type":"user","timestamp":"2026-10-12T16:30:01.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"qd","content":[{"type":"text","text":"{\"t\":1791822600,\"k\":\"chunk\",\"what\":\"scan\",\"model\":\"opus\",\"effort\":\"low\",\"est\":22,\"act\":10}"}]}]}}
EOF
printf '%s\n' '{"t":1791821400,"k":"chunk","what":"scan","model":"opus","effort":"low","est":11,"act":30}' \
  '{"t":1791822600,"k":"chunk","what":"scan","model":"opus","effort":"low","est":22,"act":10}' >> "$st/usage.jsonl"
out=$(XDG_STATE_HOME=$tmp/state rnd chunks 7)
grep -q $'^PROJ-3\t1\tscan/opus/low\t11\t10\t' <<<"$out" && grep -q $'^PROJ-3\t2\tscan/opus/low\t22\t30\t' <<<"$out" ||
  fail "chunks: each log line on the chunk whose --done printed it" "$out"

# handoff: a coordinated root with one open entry (reworded once) and one resolved twice (recurring), whose history
# one session read
hr=$tmp/hroot; mkdir -p "$hr/.claude" "$hr/n/p" "$hr/n/p-archive" "$home/.claude/projects/-x-hroot"
echo '{"pending": {"file": "n/p.md"}}' > "$hr/.claude/coordination.local.json"
printf '# OPEN-1: history\n\n- 2026-10-10 09:00 (aaaaaaaa) 2026-10-10 OPEN-1: decide A or B\n- 2026-10-11 09:00 (aaaaaaaa) 2026-10-10 OPEN-1: decide A or B, your call\n' > "$hr/n/p/OPEN-1.history.md"
printf 'Detail.\n' > "$hr/n/p/OPEN-1.md"
printf '# GONE-2: history\n\n- 2026-10-01 10:00 (u) 2026-10-01 GONE-2: release 0.1\n- 2026-10-02 10:00 (u) resolved: released\n- 2026-10-05 10:00 (u) 2026-10-05 GONE-2: release 0.2\n- 2026-10-07 10:00 (u) resolved: unknown\n' > "$hr/n/p-archive/GONE-2.history.md"
jq -nc --arg c "$hr" '{type: "user", cwd: $c, timestamp: "2026-10-12T09:00:00.000Z", message: {content: "go"}}' > "$home/.claude/projects/-x-hroot/cccccccc-1.jsonl"
jq -nc --arg p "$hr/n/p/OPEN-1.history.md" '{type: "assistant", timestamp: "2026-10-12T09:00:01.000Z", message: {content: [{type: "tool_use", id: "h1", name: "Read", input: {file_path: $p}}]}}' >> "$home/.claude/projects/-x-hroot/cccccccc-1.jsonl"
jq -nc '{type: "user", timestamp: "2026-10-12T09:00:02.000Z", toolUseResult: {file: {content: "0123456789abcdefghijklmnopqrstuvwxyz0123"}}, message: {content: [{type: "tool_result", tool_use_id: "h1"}]}}' >> "$home/.claude/projects/-x-hroot/cccccccc-1.jsonl"
# resolved before the window: left out; resolved and back open: one row, two rounds, read by --pending-history
printf '# OLD-3: history\n\n- 2026-09-01 10:00 (u) OLD-3: x\n- 2026-09-02 10:00 (u) resolved: done\n' > "$hr/n/p-archive/OLD-3.history.md"
printf '# REC-4: history\n\n- 2026-10-07 10:00 (u) REC-4: on you\n- 2026-10-08 10:00 (u) resolved: done\n' > "$hr/n/p-archive/REC-4.history.md"
printf '# REC-4: history\n\n- 2026-10-09 10:00 (u) REC-4: on you again\n- 2026-10-14 10:00 (u) REC-4: after the window\n' > "$hr/n/p/REC-4.history.md"
jq -nc '{type: "assistant", timestamp: "2026-10-12T09:01:00.000Z", message: {content: [{type: "tool_use", id: "h2", name: "Bash", input: {command: "session-status --pending-history REC-4 --last 5"}}]}}' >> "$home/.claude/projects/-x-hroot/cccccccc-1.jsonl"
jq -nc '{type: "user", timestamp: "2026-10-12T09:01:01.000Z", toolUseResult: {stdout: "01234567"}, message: {content: [{type: "tool_result", tool_use_id: "h2"}]}}' >> "$home/.claude/projects/-x-hroot/cccccccc-1.jsonl"
out=$(TZ=UTC rnd handoff 7 2> "$tmp/handoff.err")
! grep -q OLD-3 <<<"$out" && [ "$(grep -c REC-4 <<<"$out")" = 1 ] &&
  grep -q $'^hroot\topen\tREC-4\t2026-10-07\t\t5.1\tuser decision\t0\t2\t\t0\t[0-9]*\t1\t2\tcccccccc$' <<<"$out" || fail "handoff window and rounds" "$out"
grep -q $'^hroot\topen\tOPEN-1\t2026-10-10\t\t3.1\tuser decision\t1\t1\t\t8\t[0-9]*\t1\t10\tcccccccc$' <<<"$out" &&
  grep -q $'^hroot\tresolved\tGONE-2\t2026-10-01\t2026-10-07 10:00\t3.0\trelease\t0\t2\tunknown\t0\t' <<<"$out" ||
  fail "handoff rows" "$out"
grep -q "'recurring': 2" "$tmp/handoff.err" && grep -q $'^history read\t2 entries' "$tmp/handoff.err" || fail "handoff totals" "$(cat "$tmp/handoff.err")"

printf '#!/bin/sh\necho "$@" > %q\n' "$tmp/claude.args" > "$tmp/bin/claude"; chmod +x "$tmp/bin/claude"
out=$(HOME=$tmp RND_LOG=$tmp/log "$here/rnd-weekly" "$tmp" --dry-run)
grep -q 'claude --bg -n rnd-weekly-' <<<"$out" && [ ! -e "$tmp/claude.args" ] || fail "rnd-weekly --dry-run starts nothing" "$out"
HOME=$tmp RND_LOG=$tmp/log "$here/rnd-weekly" "$tmp"
grep -q 'session-orchestration:rnd' "$tmp/claude.args" && grep -q "start in $tmp" "$tmp/log" || fail "rnd-weekly starts the run" "$(cat "$tmp/log")"
HOME=$tmp RND_LOG=$tmp/log "$here/rnd-weekly" "$tmp/nope" && fail "rnd-weekly: a missing root fails" ""
grep -q "no project root $tmp/nope" "$tmp/log" || fail "rnd-weekly logs a missing root" "$(cat "$tmp/log")"
echo ok

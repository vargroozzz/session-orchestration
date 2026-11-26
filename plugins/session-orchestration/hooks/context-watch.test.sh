#!/usr/bin/env bash
# Self-check for context-watch.sh and the config keys it reads. Run: bash context-watch.test.sh  (prints "ok" or the failure).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; t=$(cd "$t" && pwd -P)
export HOME=$t/home XDG_CACHE_HOME=$t/cache XDG_CONFIG_HOME=$t/config CLAUDE_CONFIG_DIR=$t/claude
unset CLAUDE_CODE_AUTO_COMPACT_WINDOW CLAUDE_PROJECT_DIR
mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR" "$t/proj/.claude/coordination" "$XDG_CONFIG_HOME/session-orchestration"
echo '{"autoCompactWindow": 220000}' > "$CLAUDE_CONFIG_DIR/settings.json"
fail() { echo "FAIL $*"; exit 1; }

# fire SID PROMPT CTX [EVENT]: the hook's additionalContext for a transcript whose first prompt is PROMPT and whose
# last request had CTX tokens of context (split over input, cache read and cache write). The reply card is cut from
# it unless CARD is set.
fire() {
  local f=$t/$1.jsonl
  { jq -nc --arg p "$2" '{type: "user", message: {role: "user", content: $p}}'
    jq -nc '{type: "assistant", message: {usage: {input_tokens: 5, cache_read_input_tokens: 1000, cache_creation_input_tokens: 10}}}'
    [ -z "${LINE:-}" ] || echo "$LINE"
    jq -nc --argjson c "$3" '{type: "assistant", message: {usage: {input_tokens: 5, cache_read_input_tokens: ($c - 1005), cache_creation_input_tokens: 1000}}}'
  } > "$f"
  jq -nc --arg s "$1" --arg f "$f" --arg e "${4:-PostToolUse}" --arg c "$t/proj" --argjson x "${EXTRA:-null}" \
    '{session_id: $s, transcript_path: $f, hook_event_name: $e, cwd: $c, source: "compact"} + ($x // {})' |
    bash "$here/context-watch.sh" | jq -r '.hookSpecificOutput.additionalContext // empty' |
    if [ -n "${CARD:-}" ]; then cat; else sed '/^Coordinated session (session-orchestration)/,/^$/d'; fi
}
# expect SID PROMPT CTX PATTERN ('' = nothing) [EVENT]
expect() {
  local out; out=$(fire "$1" "$2" "$3" "${5:-}")
  if [ -z "$4" ]; then [ -z "$out" ] || fail "$1 at $3: want nothing, got: $out"
  else grep -qE -- "$4" <<<"$out" || fail "$1 at $3: want /$4/, got: ${out:-nothing}"; fi
}
# waitkind SID: the detached classification of a first prompt has written SID's .kind (up to 30 s)
waitkind() { local i; for i in $(seq 150); do [ -f "$XDG_CACHE_HOME/session-status/handoff-$1.kind" ] && return 0; sleep 0.2; done; fail "$1: no .kind"; }
chunk=$'Session task: PROJ-123\nChunk: PROJ-123/2\nRead the brief.'
task=$'Session task: PROJ-123\nFix the bug.'
coord='Act as a coordinator for this project.'

# Each kind: nothing, then the soft message, then the hard one, each once. A task's line is the coordinator's.
expect chunk "$chunk" 120000 ''
expect chunk "$chunk" 126000 'at 126K: hand off.*you have edited none yet, write the edits you decided on into it as text'
expect chunk "$chunk" 127000 ''
expect chunk "$chunk" 151000 'Stop now'
expect chunk "$chunk" 160000 ''
expect task "$task" 144000 ''
expect task "$task" 146000 'at 146K: hand off.*you have edited none yet, write the edits you decided on into it as text.*hand yourself over'
expect task "$task" 147000 ''
expect task "$task" 171000 'Stop now.*you have edited none yet, write the edits you decided on'
expect task "$task" 180000 ''
grep -q 'handoff ready: PROJ-123 c2' <<<"$(fire chunk2 "$chunk" 126000)" || fail 'chunk message names PROJ-123 c2'
grep -q '## c2: handoff chunklon' <<<"$(fire chunklong9 "$chunk" 126000)" || fail 'chunk message names its build section'
grep -qE "unless .*past 2× your brief's est, hand yourself over: \`.*session-status --handover --self -- '<next step>'\`, and do what it prints.*needs no message\. In those cases, or when that command fails, don't hand over: message it \"handoff ready: PROJ-123 c2\"" <<<"$(fire chunk5 "$chunk" 151000)" ||
  fail 'chunk hard text: the self-handover, the coordinator message only on a failure'
out=$(fire task2 "$task" 146000); grep -q 'handoff ready: PROJ-123"' <<<"$out" && grep -q '## Handoff' <<<"$out" || fail "task message: $out"
expect coord "$coord" 144000 ''
out=$(fire coord "$coord" 146000); grep -q 'handover file' <<<"$out" && ! grep -q 'handoff ready' <<<"$out" &&
  grep -q 'session-status --successor` and do what it prints' <<<"$out" || fail "coordinator soft: $out"
expect coord "$coord" 171000 'Stop now'
# A coordinator by what it did (lib.sh coord_re: an open_pane tool use), without `Act as a coordinator`, with or
# without a Session task line: the coordinator's thresholds and text. Chunk and task texts carry the self-handover.
# Without a key, by its own tool call (stdin), not the tail.
pane='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__session-orchestration__open_pane","input":{}}]}}'
LINE=$pane expect pane0 'Fix the bug.' 190000 ''
EXTRA='{"tool_name": "mcp__session-orchestration__open_pane", "tool_input": {}}' expect pane1 'Fix the bug.' 144000 ''
out=$(LINE=$pane fire pane1 'Fix the bug.' 146000); grep -q 'handover file' <<<"$out" && ! grep -qF -- '--self' <<<"$out" || fail "open_pane session: $out"
LINE=$pane expect pane2 "$task" 130000 ''
out=$(fire pane3 "$task" 146000); grep -q 'handover file' <<<"$(LINE=$pane fire pane3 "$task" 150000)" || fail 'task turned coordinator'
grep -qF -- "orchestrating-sessions/session-status --handover --self -- '<next step>'" <<<"$out" || fail "task self-handover: $out"
# A keyed task running session-status --start (testing or measuring it) stays a task; a keyless one turns coordinator.
start='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"bash ./session-status --start"}}]}}'
out=$(LINE=$start fire start1 "$task" 146000); grep -qF -- '--handover --self' <<<"$out" && ! grep -q 'handover file' <<<"$out" ||
  fail "keyed task turned coordinator by --start: $out"
grep -q '^task PROJ-123 ' "$t/cache/session-status/handoff-start1.kind" || fail "keyed task .kind: $(cat "$t/cache/session-status/handoff-start1.kind")"
EXTRA='{"tool_name": "Bash", "tool_input": {"command": "bash ./session-status --start"}}' expect start2 'Fix the bug.' 144000 ''
grep -q 'handover file' <<<"$(fire start2 'Fix the bug.' 146000)" || fail 'keyless --start run: not a coordinator'
out=$(fire chunk4 "$chunk" 151000); grep -qF -- '--handover --self' <<<"$out" && ! grep -qF -- '--coordinator' <<<"$out" || fail "chunk hard self-handover: $out"
[ -z "$(grep -l window "$t"/cache/session-status/* 2>/dev/null)" ] || fail 'window line under the expected window'

# A sub-coordinator (`Coordinate KEY`): the coordinator's mark, a worker's self-handover from KEY-coordinator.md, and
# its coordinator commands (a --watch, open_pane) never make it the project's coordinator.
sc='Coordinate PROJ-123: run the plan.'
watch='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"session-status --watch PROJ-123"}}]}}'
LINE=$watch expect subc "$sc" 144000 ''
out=$(LINE=$watch fire subc "$sc" 146000)
grep -q '## Handoff` in PROJ-123-coordinator.md' <<<"$out" && grep -qF -- '--handover --self' <<<"$out" &&
  grep -q 'handoff ready: PROJ-123"' <<<"$out" && ! grep -q 'handover file' <<<"$out" || fail "sub-coordinator soft: $out"
grep -q '^subcoordinator PROJ-123 ' "$t/cache/session-status/handoff-subc.kind" || fail "sub-coordinator .kind: $(cat "$t/cache/session-status/handoff-subc.kind")"
EXTRA='{"tool_name": "mcp__session-orchestration__open_pane", "tool_input": {}}' LINE=$pane expect subc "$sc" 171000 'Stop now.*PROJ-123-coordinator.md'
# Window 200000 from env: the mismatch line once, and a lower hard (ceiling 167K - 15K = 152K; at 142K).
export CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000
expect cw "$coord" 143000 "at 143K: hand off.*window is 200000 from env; expected 220000"
expect cw "$coord" 153000 'Stop now'
grep -q window <<<"$(fire cw2 "$coord" 160000)" || fail 'window line on a first firing that is the hard one'
out=$(fire cw3 "$chunk" 126000); fire cw3 "$chunk" 151000 | grep -q window && fail 'window line twice'
unset CLAUDE_CODE_AUTO_COMPACT_WINDOW
# No autoCompactWindow anywhere (config's guess; a 1M model compacts far later): the note says so, marks unchanged.
mv "$CLAUDE_CONFIG_DIR/settings.json" "$t/settings.bak"
expect nw "$coord" 146000 'at 146K: hand off.*No autoCompactWindow found in env, project or user settings: these marks assume compact.window 220000'
mv "$t/settings.bak" "$CLAUDE_CONFIG_DIR/settings.json"

# Not coordinated (no Session task line), or a subagent's tool call: nothing. Keyless: the transcript isn't read again.
expect plain 'Fix the bug.' 190000 ''
chmod 000 "$t/plain.jsonl"
out=$(jq -nc --arg f "$t/plain.jsonl" '{session_id: "plain", transcript_path: $f, hook_event_name: "PostToolUse", tool_name: "Bash"}' |
  bash "$here/context-watch.sh" 2>&1); chmod 600 "$t/plain.jsonl"; [ -z "$out" ] || fail "keyless session read its transcript: $out"
# `Work on KEY:` (the coordinator's launch, a task successor) is a task; a review gets nothing; `Chunk: foo` isn't a chunk.
grep -q 'handoff ready: PROJ-123"' <<<"$(fire work "Work on PROJ-123: fix the bug." 146000)" || fail 'Work on KEY: task'
# No key match: `Work on NAME` naming its own -n name (agent-name) is keyed by it; another name stays keyless.
grep -q 'handoff ready: proj-fix-bug"' <<<"$(LINE='{"type":"agent-name","agentName":"proj-fix-bug"}' fire named "Work on proj-fix-bug: fix the bug." 146000)" || fail 'Work on NAME: task'
LINE='{"type":"agent-name","agentName":"proj-fix"}' expect unnamed "Work on proj-fix-bug: fix the bug." 190000 ''
expect review 'Session task: PROJ-123 review' 160000 ''
expect nochunk $'Chunk: foo\nRead the brief.' 160000 ''
EXTRA='{"agent_id": "a1"}' expect sub "$task" 190000 ''
expect sub "$task" 190000 'Stop now'
# A compaction clears the stamps; a resume clears the thresholds too (here: a new window).
expect sub "$task" 1000 '' SessionStart
expect sub "$task" 146000 'hand off'
CLAUDE_CODE_AUTO_COMPACT_WINDOW=150000 EXTRA='{"source": "resume"}' expect sub "$task" 1000 '' SessionStart
waitkind sub   # a resume classifies detached
CLAUDE_CODE_AUTO_COMPACT_WINDOW=150000 expect sub "$task" 103000 'Stop now.*window is 150000'
# An all-zero (synthetic) reply after the real one doesn't hide the context.
jq -nc '{type: "assistant", message: {usage: {input_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0}}}' >> "$t/sub.jsonl"
rm "$t"/cache/session-status/handoff-sub.hard
out=$(jq -nc --arg f "$t/sub.jsonl" --arg c "$t/proj" '{session_id: "sub", transcript_path: $f, hook_event_name: "PostToolUse", cwd: $c}' |
  bash "$here/context-watch.sh"); grep -q 'at 103K' <<<"$out" || fail "zero usage counted: $out"

# handoff.at.task=0 silences it.
echo '{"handoff": {"at": {"task": 0}}}' > "$XDG_CONFIG_HOME/session-orchestration/config.json"
expect off "$task" 146000 ''
expect off "$task" 190000 ''

# SessionStart (compact): chunk only, once.
expect sc "$chunk" 1000 'compacted mid-chunk.*c2: handoff' SessionStart
expect sc "$chunk" 1000 '' SessionStart
expect st "$task" 1000 '' SessionStart
expect so "$coord" 1000 '' SessionStart
# A resume clears the compacted-mid-chunk stamp: the next compaction says it again.
EXTRA='{"source": "resume"}' expect sc "$chunk" 1000 '' SessionStart
expect sc "$chunk" 1000 'compacted mid-chunk' SessionStart
# A manual /compact: boundary, summary, then a prompt with no assistant line yet. The 160K before the boundary is
# stale: nothing, and the soft line still comes later.
echo {} > "$XDG_CONFIG_HOME/session-orchestration/config.json"
expect mc "$task" 100000 ''
{ echo '{"type":"system","subtype":"compact_boundary","content":"Conversation compacted"}'
  jq -nc '{type: "user", isCompactSummary: true, message: {role: "user", content: "summary"}}'; } >> "$t/mc.jsonl"
sed 's/"cache_read_input_tokens":98995/"cache_read_input_tokens":158995/' "$t/mc.jsonl" > "$t/mc.t" && mv "$t/mc.t" "$t/mc.jsonl"
out=$(jq -nc --arg f "$t/mc.jsonl" --arg c "$t/proj" '{session_id: "mc", transcript_path: $f, hook_event_name: "UserPromptSubmit", cwd: $c}' |
  bash "$here/context-watch.sh"); [ -z "$out" ] || fail "stale ctx after /compact: $out"
expect mc "$task" 150000 'at 150K: hand off'
# An advisor call splits a turn into two message iterations whose totals add up to 181K; the context is the last one's 95K.
expect adv "$task" 100000 ''
jq -nc '{type: "assistant", message: {usage: {input_tokens: 6, cache_read_input_tokens: 175985, cache_creation_input_tokens: 4828,
  iterations: [{type: "message", input_tokens: 4, cache_read_input_tokens: 82411, cache_creation_input_tokens: 3404},
    {type: "advisor_message", input_tokens: 86381, cache_read_input_tokens: 0, cache_creation_input_tokens: 0},
    {type: "message", input_tokens: 2, cache_read_input_tokens: 93574, cache_creation_input_tokens: 1424}]}}}' >> "$t/adv.jsonl"
out=$(jq -nc --arg f "$t/adv.jsonl" --arg c "$t/proj" '{session_id: "adv", transcript_path: $f, hook_event_name: "PostToolUse", cwd: $c}' |
  bash "$here/context-watch.sh"); [ -z "$out" ] || fail "advisor iterations counted as context: $out"
# The same in a coordinator: iterations adding up to 155K (past its line) while the last message holds 78K: nothing.
expect advc "$coord" 100000 ''
jq -nc '{type: "assistant", message: {usage: {input_tokens: 4, cache_read_input_tokens: 150000, cache_creation_input_tokens: 4996,
  iterations: [{type: "message", input_tokens: 2, cache_read_input_tokens: 72000, cache_creation_input_tokens: 2000},
    {type: "advisor_message", input_tokens: 80000, cache_read_input_tokens: 0, cache_creation_input_tokens: 0},
    {type: "message", input_tokens: 2, cache_read_input_tokens: 76000, cache_creation_input_tokens: 2000}]}}}' >> "$t/advc.jsonl"
for ev in PostToolUse UserPromptSubmit; do
  out=$(jq -nc --arg f "$t/advc.jsonl" --arg c "$t/proj" --arg e "$ev" '{session_id: "advc", transcript_path: $f, hook_event_name: $e, cwd: $c}' |
    bash "$here/context-watch.sh"); [ -z "$out" ] || fail "coordinator: advisor iterations counted as context ($ev): $out"
done

# A first prompt on a 30 MB transcript returns at once though classifying takes over 5 s (a slow git: a loaded
# machine; first_prompt's head stands in), and writes .kind for the next prompt, which reads only the tail: both well
# under the hook's 5 s timeout.
mkdir -p "$t/slow"; printf '#!/bin/sh\nsleep 6; exec %s "$@"\n' "$(command -v head)" > "$t/slow/head"; chmod +x "$t/slow/head"
{ jq -nc --arg p "$coord" '{type: "user", message: {role: "user", content: $p}}'
  awk -v l="$(printf '%01000d' 0)" 'BEGIN { for (i = 0; i < 30000; i++) print l }'
  jq -nc '{type: "assistant", message: {usage: {input_tokens: 5, cache_read_input_tokens: 150000, cache_creation_input_tokens: 0}}}'; } > "$t/long.jsonl"
ups() { jq -nc --arg f "$t/long.jsonl" --arg c "$t/proj" --arg e "${EV:-UserPromptSubmit}" '{session_id: "long", transcript_path: $f, hook_event_name: $e, cwd: $c}' |
  PATH=$t/slow:$PATH bash "$here/context-watch.sh"; }
s=$SECONDS; out=$(ups); (( SECONDS - s <= 2 )) && [ -z "$out" ] || fail "first prompt took $(( SECONDS - s )) s: $out"
# a tool call while it classifies skips, no second classification inline
s=$SECONDS; out=$(EV=PostToolUse ups); (( SECONDS - s <= 2 )) && [ -z "$out" ] || fail "tool call while classifying: $out"
s=$SECONDS; waitkind long; (( SECONDS - s >= 3 )) || fail 'the slow classification was not slow'
# the detached copy writes .kind, then its EXIT trap drops the stamp: wait for that, as for .kind
for i in $(seq 50); do [ -e "$XDG_CACHE_HOME/session-status/handoff-long.classifying" ] || break; sleep 0.2; done
[ ! -e "$XDG_CACHE_HOME/session-status/handoff-long.classifying" ] || fail 'classifying stamp left'
s=$SECONDS; out=$(ups); (( SECONDS - s <= 2 )) && grep -q 'at 150K: hand off' <<<"$out" || fail "cached prompt took $(( SECONDS - s )) s: $out"

# The reply card: a keyed task, chunk or review at its first firing, once, its paths filled in; again after a
# compaction (a chunk's with its compacted text), not after a resume; never a coordinator's. A keyless session gets
# it at its first message: the module's .msg stamp, or a prompt holding one; not when that call makes it a coordinator.
c='^Coordinated session \(session-orchestration\)'
CARD=1 expect card1 "$task" 1000 '' UserPromptSubmit   # its first prompt classifies detached: the card comes next
waitkind card1
CARD=1 expect card1 "$task" 1000 "$c"
CARD=1 expect card1 "$task" 1000 ''
out=$(CARD=1 fire card2 "$chunk" 1000); grep -qF "worker.md: ${here%/hooks}/skills/orchestrating-sessions/worker.md." <<<"$out" &&
  grep -qF "no such tool: worker.md's Replying" <<<"$out" && ! grep -qF '{dir}' <<<"$out" || fail "card paths: $out"
CARD=1 expect card3 'Session task: PROJ-123 review' 1000 "$c"
CARD=1 expect card4 "$coord" 1000 ''
CARD=1 expect card1 "$task" 1000 "$c" SessionStart
CARD=1 expect card1 "$task" 1000 ''
out=$(CARD=1 fire card2 "$chunk" 1000 SessionStart); grep -qE "$c" <<<"$out" && grep -q 'compacted mid-chunk' <<<"$out" || fail "chunk card after compaction: $out"
EXTRA='{"source": "resume"}' CARD=1 expect card1 "$task" 1000 '' SessionStart
CARD=1 expect card1 "$task" 1000 ''
CARD=1 expect card5 'Fix the bug.' 1000 ''
touch "$t/cache/session-status/handoff-card5.msg"
CARD=1 expect card5 'Fix the bug.' 1000 "$c"
CARD=1 expect card5 'Fix the bug.' 1000 ''
CARD=1 expect card6 'Fix the bug.' 1000 ''
EXTRA='{"prompt": "<cross-session-message from=\"uds:/s\" from-name=\"x-coordinator\">status?</cross-session-message>"}' \
  CARD=1 expect card6 'Fix the bug.' 1000 "$c" UserPromptSubmit
touch "$t/cache/session-status/handoff-card7.msg"
EXTRA='{"tool_name": "mcp__session-orchestration__open_pane", "tool_input": {}}' CARD=1 expect card7 'Fix the bug.' 1000 ''
# Past the hard stop, a card still due goes out (nothing else does).
touch "$t/cache/session-status/handoff-card9.msg" "$t/cache/session-status/handoff-card9.hard"
CARD=1 expect card9 'Fix the bug.' 1000 "$c"

# A peer message relaying approvals: one line per block, from verify-approval.sh, before anything else; the card waits
# for the next firing. Verified: the source (x-coordinator) has the pane answer and sent the relay.
src=11111111-2222-3333-4444-555555555555 q='Approval pane answer for PROJ-7: Yes. Asked: Land PROJ-7?'
blk() { printf 'APPROVAL relayed from the user\nQuote: %s\nAction: %s\nSource: %s %s' "$q" "$1" "$2" "$t/proj"; }
mkdir -p "$CLAUDE_CONFIG_DIR/projects/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$t/proj")"
{ echo '{"type":"agent-name","agentName":"x-coordinator"}'
  jq -nc --arg q "$q" '{type: "user", origin: {kind: "plugin", name: "session-orchestration"}, timestamp: (now - 60 | todate), message: {content: $q}}'
  jq -nc --arg m "$(blk 'merge acme/app#3 (PROJ-7)' "$src")" '{type: "assistant", timestamp: (now - 30 | todate), message: {content: [{type: "tool_use", name: "SendMessage", input: {to: "w", message: $m}}]}}'
} > "$CLAUDE_CONFIG_DIR/projects/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$t/proj")/$src.jsonl"
rp=$(printf '<cross-session-message from="uds:/s" from-name="x-coordinator">\nGo.\n\n%s\n\n%s\n</cross-session-message>' \
  "$(blk 'merge acme/app#3 (PROJ-7)' "$src")" "$(blk 'merge acme/app#4 (PROJ-8)' aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa)")
out=$(EXTRA=$(jq -nc --arg p "$rp" '{prompt: $p}') CARD=1 fire relay "$task" 1000 UserPromptSubmit)
[ "$out" = 'relay verified: merge acme/app#3 (PROJ-7)
relay rejected: sessionId is not a UUID (merge acme/app#4 (PROJ-8))' ] || fail "relay lines: $out"
CARD=1 expect relay "$task" 1000 "$c"
CARD=1 expect card9 'Fix the bug.' 1000 ''
# With the soft text in the same firing: both, the card first.
out=$(CARD=1 fire card8 "$task" 146000); grep -qE "$c" <<<"$out" && grep -q 'at 146K: hand off' <<<"$(sed -n '/^$/,$p' <<<"$out")" ||
  fail "card with the soft text: $out"

# The project's settings come before the user's.
echo '{"autoCompactWindow": 180000}' > "$t/proj/.claude/settings.local.json"
expect pw "$chunk" 126000 'window is 180000 from project; expected 220000'
rm "$t/proj/.claude/settings.local.json"

# coord_re: the status command as a command word (at the start, or after ; && || |, with bash and a path), not a mention.
cre=$(cd "$t/proj" && . "$here/../lib.sh" && coord_re)
m() { [[ "\"command\":\"$1\"" =~ $cre ]]; }
! m "grep 'session-status --watch' x" && m 'bash /p/session-status --watch' && m 'cd x && session-status --changes' &&
  m 'a || /p/session-status --owner PROJ-1' && ! m 'session-status PROJ-1' && m 'X=10 session-status --watch' &&
  m 'cd /p\nsession-status --changes' && m 'out=$(session-status --changes)' && ! m "echo 'x session-status --watch'" &&
  [[ '"name":"mcp__session-orchestration__open_pane"' =~ $cre ]] || fail coord_re
# A bare `KEY:` start is a task only in a coordinated project (an adapter, or key_pattern).
expect bare 'PROJ-1: fix it' 126000 ''
mkdir -p "$t/proj2/.claude"; printf '#!/bin/sh\nexit 0\n' > "$t/proj2/.claude/session-status-adapter"
chmod +x "$t/proj2/.claude/session-status-adapter"
EXTRA="{\"cwd\": \"$t/proj2\"}" expect bare2 'PROJ-1: fix it' 146000 'handoff ready: PROJ-1"'
# `Session task: KEY.` drops the period.
fire dot $'Session task: PROJ-123.\nFix it.' 1000 >/dev/null; read -r _ k _ < "$t/cache/session-status/handoff-dot.kind"
[ "$k" = PROJ-123 ] || fail "key kept its period: $k"
# retro-run's two scopes at once: one key, so one handoff file, per scope.
fire rp 'Session task: retro run, scope project. Use the retro skill.' 1000 >/dev/null
fire rg 'Session task: retro run, scope plugin. Use the retro skill.' 1000 >/dev/null
read -r _ k _ < "$t/cache/session-status/handoff-rp.kind"; read -r _ k2 _ < "$t/cache/session-status/handoff-rg.kind"
[ "$k $k2" = 'retro-project retro-plugin' ] || fail "retro scopes keyed $k $k2"
# A retro section: keyed by scope and group, a task's mark, its own text: cut the section short, no handover.
sec='Session task: retro run, scope project, section group units, run /r/retro/project-7. Use the retro skill.'
out=$(fire rs "$sec" 146000); read -r kd k _ < "$t/cache/session-status/handoff-rs.kind"
[ "$kd $k" = 'section retro-project-units' ] && grep -q 'at 146K: your retro section ends here.*done: cut at mark' <<<"$out" && ! grep -q -- --handover <<<"$out" && ! grep -q 'cross-session-message' <<<"$out" ||
  fail "retro section: $kd $k $out"
expect rs2 "$sec" 999000 'past the hard stop. Stop now: your retro section ends here'
# A coordinator's .kind: no key (`-`), a `Coordinate …` that names none isn't a sub.
fire ck "$coord" 1000 >/dev/null; fire ck2 'Coordinate the release.' 1000 >/dev/null
read -r kd k _ < "$t/cache/session-status/handoff-ck.kind"; [ "$kd $k" = 'coordinator -' ] || fail "coordinator .kind: $kd $k"
read -r kd k _ < "$t/cache/session-status/handoff-ck2.kind"; [ "$kd $k" = 'task -' ] || fail "keyless Coordinate .kind: $kd $k"
# A new session's first prompt: no transcript file yet (Claude Code writes it after UserPromptSubmit), classified from
# the transcript once it appears (a second later here), its agent-name line too.
for c in "nofile|$coord|coordinator -" "nofile2|Work on fix-login|task fix-login"; do
  IFS='|' read -r sid p want <<<"$c"
  jq -nc --arg s "$sid" --arg f "$t/$sid.jsonl" --arg c "$t/proj" --arg p "$p" '{session_id: $s, transcript_path: $f, hook_event_name: "UserPromptSubmit", cwd: $c, prompt: $p}' |
    bash "$here/context-watch.sh" >/dev/null
  [ ! -f "$t/cache/session-status/handoff-$sid.kind" ] || fail "$sid: classified before its transcript"
  sleep 1; { echo '{"type":"agent-name","agentName":"fix-login"}'; jq -nc --arg p "$p" '{type: "user", message: {role: "user", content: $p}}'; } > "$t/$sid.jsonl"
  waitkind "$sid"; read -r kd k _ < "$t/cache/session-status/handoff-$sid.kind"; [ "$kd $k" = "$want" ] || fail "$sid, no transcript yet: $kd $k"
done
# A window too small for the stop room: 60% and 80% of it; a window of 0 is unknown: config's at and hard.
CLAUDE_CODE_AUTO_COMPACT_WINDOW=40000 expect w40 "$task" 4500 'at 4K: hand off.*too small for handoff.stop_room'
CLAUDE_CODE_AUTO_COMPACT_WINDOW=40000 expect w40 "$task" 5700 'Stop now'
CLAUDE_CODE_AUTO_COMPACT_WINDOW=0 expect w0 "$task" 146000 'at 146K: hand off'
# No prompt in a transcript past 50 lines: cached keyless after one call.
for i in $(seq 60); do echo '{"type":"user","isMeta":true,"message":{"content":"x"}}'; done > "$t/meta.jsonl"
jq -nc --arg f "$t/meta.jsonl" --arg c "$t/proj" '{session_id: "meta", transcript_path: $f, hook_event_name: "PostToolUse", cwd: $c}' |
  bash "$here/context-watch.sh"; [ -f "$t/cache/session-status/handoff-meta.kind" ] || fail 'meta-only transcript not cached'
# A prompt past line 50 is still found once.
{ cat "$t/meta.jsonl"; jq -nc --arg p "$chunk" '{type: "user", message: {role: "user", content: $p}}'; } > "$t/meta2.jsonl"
jq -nc --arg f "$t/meta2.jsonl" --arg c "$t/proj" '{session_id: "meta2", transcript_path: $f, hook_event_name: "PostToolUse", cwd: $c}' |
  bash "$here/context-watch.sh" >/dev/null; grep -q '^chunk PROJ-123 2 ' "$t/cache/session-status/handoff-meta2.kind" || fail 'prompt past line 50 missed'
# A keyless session that writes `Session task: KEY`: still keyless until it calls name_session, then that task.
late='{"type":"assistant","message":{"content":[{"type":"text","text":"Session task: PROJ-9\nOn it."}]}}'
expect late 'Fix the bug.' 126000 ''
LINE=$late expect late 'Fix the bug.' 126000 ''
# A tool input that mentions it (a brief written for another session) doesn't count.
LINE='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"cat <<EOF\nSession task: PROJ-8\nEOF"}}]}}' \
  EXTRA='{"tool_name": "mcp__session-orchestration__name_session"}' expect late2 'Fix the bug.' 126000 ''
LINE=$late EXTRA='{"tool_name": "mcp__session-orchestration__name_session"}' expect late 'Fix the bug.' 146000 'handoff ready: PROJ-9"'
# keyed now: a session-status --start run (testing it) no longer makes it a coordinator, nor a review
LINE="$late"$'\n'"$start" expect late 'Fix the bug.' 150000 ''
EXTRA='{"tool_name": "Bash", "tool_input": {"command": "bash ./session-status --start"}}' expect review2 'Session task: PROJ-123 review' 146000 ''

# Config: defaults, a bad value, and a repo file can't set the person keys.
rm "$XDG_CONFIG_HOME/session-orchestration/config.json"
cd "$t/proj"; . "$here/../lib.sh"
chunk_of 'Chunk: foo' && fail 'Chunk: foo is a chunk'
[ "$(chunk_of $'Session task: PROJ-123\nChunk: PROJ-123/3b')" = 'PROJ-123 3b' ] || fail 'chunk_of PROJ-123/3b'
# first_key takes `Coordinate KEY`; sub_key only that, on the first line, and fails on anything else.
KEYRE=$(key_re)
[ "$(first_key 'Coordinate PROJ-12: x')" = PROJ-12 ] && [ "$(first_key 'Work on PROJ-3.')" = PROJ-3 ] || fail first_key
[ "$(sub_key $'Coordinate PROJ-12: continue\nSupersedes: x')" = PROJ-12 ] || fail 'sub_key Coordinate PROJ-12'
! sub_key 'Work on PROJ-12' && ! sub_key $'Fix it.\nCoordinate PROJ-12' && ! sub_key 'Coordinate the release' &&
  ! sub_key 'Act as a coordinator' || fail 'sub_key on a non-sub'
[ "$(config handoff.at.chunk)" = 125000 ] || fail "handoff.at.chunk default"
[ "$(config compact.window)" = 220000 ] && [ "$(config plan.models.scan)" = haiku/low ] && [ "$(config plan.max_parallel)" = 3 ] || fail defaults
echo '{"handoff": {"at": {"chunk": 90000}}, "plan": {"max_parallel": 0, "models": {"build": "fable/high", "review": "opus/ultra", "design": "sonnet/max"}}}' > "$XDG_CONFIG_HOME/session-orchestration/config.json"
[ "$(config handoff.at.chunk)" = 90000 ] || fail 'person-wide handoff.at.chunk'
[ "$(config plan.models.design)" = sonnet/max ] || fail 'plan.models.design'
[ "$(config plan.max_parallel 2>/dev/null)" = 3 ] && [ "$(config plan.models.build 2>/dev/null)" = opus/medium ] &&
  [ "$(config plan.models.review 2>/dev/null)" = opus/xhigh ] || fail 'bad values rejected'
config plan.max_parallel 2>&1 >/dev/null | grep -q 'not valid' || fail 'bad value warns'
echo '{"handoff": {"at": {"chunk": "090000"}}}' > "$XDG_CONFIG_HOME/session-orchestration/config.json"
[ "$(config handoff.at.chunk 2>/dev/null)" = 125000 ] || fail 'leading-zero handoff.at.chunk'
echo '{"handoff": {"at": {"chunk": "lots"}}}' > "$XDG_CONFIG_HOME/session-orchestration/config.json"
[ "$(config handoff.at.chunk 2>/dev/null)" = 125000 ] || fail 'non-integer handoff.at.chunk'
rm "$XDG_CONFIG_HOME/session-orchestration/config.json"
echo '{"handoff": {"at": {"chunk": 1}, "hard_after": 1}, "compact": {"window": 1}, "plan": {"max_parallel": 5}}' > "$t/proj/.claude/coordination/coordination.json"
[ "$(config handoff.at.chunk)" = 125000 ] && [ "$(config handoff.hard_after)" = 25000 ] && [ "$(config compact.window)" = 220000 ] ||
  fail 'repo file set a person key'
[ "$(config plan.max_parallel)" = 5 ] || fail 'repo file plan.max_parallel'
{ config handoff.at.nobody 2>&1 || :; } | grep -q 'unknown config key' || fail 'unknown handoff kind'
echo ok

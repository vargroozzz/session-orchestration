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
# last request had CTX tokens of context (split over input, cache read and cache write).
fire() {
  local f=$t/$1.jsonl
  { jq -nc --arg p "$2" '{type: "user", message: {role: "user", content: $p}}'
    jq -nc '{type: "assistant", message: {usage: {input_tokens: 5, cache_read_input_tokens: 1000, cache_creation_input_tokens: 10}}}'
    [ -z "${LINE:-}" ] || echo "$LINE"
    jq -nc --argjson c "$3" '{type: "assistant", message: {usage: {input_tokens: 5, cache_read_input_tokens: ($c - 1005), cache_creation_input_tokens: 1000}}}'
  } > "$f"
  jq -nc --arg s "$1" --arg f "$f" --arg e "${4:-PostToolUse}" --arg c "$t/proj" --argjson x "${EXTRA:-null}" \
    '{session_id: $s, transcript_path: $f, hook_event_name: $e, cwd: $c, source: "compact"} + ($x // {})' |
    bash "$here/context-watch.sh" | jq -r '.hookSpecificOutput.additionalContext // empty'
}
# expect SID PROMPT CTX PATTERN ('' = nothing) [EVENT]
expect() {
  local out; out=$(fire "$1" "$2" "$3" "${5:-}")
  if [ -z "$4" ]; then [ -z "$out" ] || fail "$1 at $3: want nothing, got: $out"
  else grep -qE -- "$4" <<<"$out" || fail "$1 at $3: want /$4/, got: ${out:-nothing}"; fi
}
chunk=$'Session task: PROJ-123\nChunk: PROJ-123/2\nRead the brief.'
task=$'Session task: PROJ-123\nFix the bug.'
coord='Act as a coordinator for this project.'

# Each kind: nothing, then the soft message, then the hard one, each once.
for k in chunk task; do
  p=${!k}
  expect "$k" "$p" 120000 ''
  expect "$k" "$p" 126000 'at 126K: hand off'
  expect "$k" "$p" 127000 ''
  expect "$k" "$p" 151000 'Stop now'
  expect "$k" "$p" 160000 ''
done
grep -q 'handoff ready: PROJ-123 c2' <<<"$(fire chunk2 "$chunk" 126000)" || fail 'chunk message names PROJ-123 c2'
grep -q '## c2: handoff' <<<"$(fire chunk3 "$chunk" 126000)" || fail 'chunk message names its build section'
grep -qE 'Rename yourself: call name_session with the name `.*session-status --prev-name` prints.* Message the coordinator' <<<"$(fire chunk5 "$chunk" 151000)" || fail 'chunk hard text: rename before the coordinator message'
out=$(fire task2 "$task" 126000); grep -q 'handoff ready: PROJ-123"' <<<"$out" && grep -q '## Handoff' <<<"$out" || fail "task message: $out"
expect coord "$coord" 144000 ''
out=$(fire coord "$coord" 146000); grep -q 'handover file' <<<"$out" && ! grep -q 'handoff ready' <<<"$out" || fail "coordinator soft: $out"
expect coord "$coord" 171000 'Stop now'
# A coordinator by what it did (lib.sh coord_re: an open_pane tool use), without `Act as a coordinator`, with or
# without a Session task line: the coordinator's thresholds and text. Chunk and task texts carry the self-handover.
# Without a key, by its own tool call (stdin), not the tail.
pane='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__session-orchestration__open_pane","input":{}}]}}'
LINE=$pane expect pane0 'Fix the bug.' 190000 ''
EXTRA='{"tool_name": "mcp__session-orchestration__open_pane", "tool_input": {}}' expect pane1 'Fix the bug.' 144000 ''
out=$(LINE=$pane fire pane1 'Fix the bug.' 146000); grep -q 'handover file' <<<"$out" && ! grep -q 'self' <<<"$out" || fail "open_pane session: $out"
LINE=$pane expect pane2 "$task" 130000 ''
out=$(fire pane3 "$task" 130000); grep -q 'handover file' <<<"$(LINE=$pane fire pane3 "$task" 146000)" || fail 'task turned coordinator'
grep -qF -- "orchestrating-sessions/session-status --handover --self -- '<next step>'" <<<"$out" || fail "task self-handover: $out"
grep -qF -- 'session-status --coordinator` prints nothing' <<<"$(fire chunk4 "$chunk" 151000)" || fail 'chunk hard self-handover'
[ -z "$(grep -l window "$t"/cache/session-status/* 2>/dev/null)" ] || fail 'window line under the expected window'

# Window 200000 from env: the mismatch line once, and a lower hard (ceiling 167K - 15K = 152K; at 142K).
export CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000
expect cw "$coord" 143000 "at 143K: hand off.*window is 200000 from env; expected 220000"
expect cw "$coord" 153000 'Stop now'
grep -q window <<<"$(fire cw2 "$coord" 160000)" || fail 'window line on a first firing that is the hard one'
out=$(fire cw3 "$chunk" 126000); fire cw3 "$chunk" 151000 | grep -q window && fail 'window line twice'
unset CLAUDE_CODE_AUTO_COMPACT_WINDOW

# Not coordinated (no Session task line), or a subagent's tool call: nothing. Keyless: the transcript isn't read again.
expect plain 'Fix the bug.' 190000 ''
chmod 000 "$t/plain.jsonl"
out=$(jq -nc --arg f "$t/plain.jsonl" '{session_id: "plain", transcript_path: $f, hook_event_name: "PostToolUse", tool_name: "Bash"}' |
  bash "$here/context-watch.sh" 2>&1); chmod 600 "$t/plain.jsonl"; [ -z "$out" ] || fail "keyless session read its transcript: $out"
# `Work on KEY:` (coordinator.md's launch, a task successor) is a task; a review gets nothing; `Chunk: foo` isn't a chunk.
grep -q 'handoff ready: PROJ-123"' <<<"$(fire work "Work on PROJ-123: fix the bug." 126000)" || fail 'Work on KEY: task'
expect review 'Session task: PROJ-123 review' 160000 ''
expect nochunk $'Chunk: foo\nRead the brief.' 160000 ''
EXTRA='{"agent_id": "a1"}' expect sub "$task" 190000 ''
expect sub "$task" 190000 'Stop now'
# A compaction clears the stamps; a resume clears the thresholds too (here: a new window).
expect sub "$task" 1000 '' SessionStart
expect sub "$task" 126000 'hand off'
CLAUDE_CODE_AUTO_COMPACT_WINDOW=150000 EXTRA='{"source": "resume"}' expect sub "$task" 1000 '' SessionStart
CLAUDE_CODE_AUTO_COMPACT_WINDOW=150000 expect sub "$task" 103000 'Stop now.*window is 150000'
# An all-zero (synthetic) reply after the real one doesn't hide the context.
jq -nc '{type: "assistant", message: {usage: {input_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0}}}' >> "$t/sub.jsonl"
rm "$t"/cache/session-status/handoff-sub.hard
out=$(jq -nc --arg f "$t/sub.jsonl" --arg c "$t/proj" '{session_id: "sub", transcript_path: $f, hook_event_name: "PostToolUse", cwd: $c}' |
  bash "$here/context-watch.sh"); grep -q 'at 103K' <<<"$out" || fail "zero usage counted: $out"

# handoff.at.task=0 silences it.
echo '{"handoff": {"at": {"task": 0}}}' > "$XDG_CONFIG_HOME/session-orchestration/config.json"
expect off "$task" 126000 ''
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
expect mc "$task" 130000 'at 130K: hand off'

# The project's settings come before the user's.
echo '{"autoCompactWindow": 180000}' > "$t/proj/.claude/settings.local.json"
expect pw "$chunk" 126000 'window is 180000 from project; expected 220000'
rm "$t/proj/.claude/settings.local.json"

# Config: defaults, a bad value, and a repo file can't set the person keys.
rm "$XDG_CONFIG_HOME/session-orchestration/config.json"
cd "$t/proj"; . "$here/../lib.sh"
chunk_of 'Chunk: foo' && fail 'Chunk: foo is a chunk'
[ "$(chunk_of $'Session task: PROJ-123\nChunk: PROJ-123/3b')" = 'PROJ-123 3b' ] || fail 'chunk_of PROJ-123/3b'
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

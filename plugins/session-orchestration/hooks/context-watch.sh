#!/usr/bin/env bash
# PostToolUse (every tool), UserPromptSubmit and SessionStart (compact): asks a session to hand off before it
# compacts. ctx = input + cache read + cache write of the last assistant line with usage in the transcript's tail
# (its last 256K, else its last 300 lines).
# - Kind, from the first user prompt: a `Chunk: KEY/N` line is a chunk, `Act as a coordinator` a coordinator, else
#   a task (its `Session task: KEY` line names it; a session without one isn't coordinated: left alone).
# - Window: $CLAUDE_CODE_AUTO_COMPACT_WINDOW, else autoCompactWindow in settings.json, else config compact.window.
#   ceiling = window - 33000; hard = min(at + handoff.hard_after, ceiling - handoff.stop_room);
#   at = min(handoff.at.KIND, hard - 10000). handoff.at.KIND = 0: off.
# - Past at: one additionalContext (reach the stop point, write the handoff, tell the coordinator, end the turn);
#   past hard: one more (stop now). A window other than compact.window adds one line to the first one.
# - SessionStart after a compaction, chunk sessions only: write the handoff from what's on disk and stop. A
#   compaction or resume also clears the stamps (a resume may bring another window: the thresholds too).
# Subagents' tool calls (agent_id set) are skipped: they carry the parent's transcript.
# Stamps: ${XDG_CACHE_HOME:-~/.cache}/session-status/handoff-<sid>.<level>; .kind caches the kind and thresholds.
# ponytail: thresholds cached per session at its first firing; a config change reaches the next session.
# Self-test: bash context-watch.test.sh
here=$(cd "$(dirname "$0")" && pwd); input=$(cat)
{ read -r sid; read -r tp; read -r ev; read -r cwd; read -r src; read -r agent; } < <(jq -r '.session_id // "", .transcript_path // "",
  .hook_event_name // "", .cwd // "", .source // "", .agent_id // ""' <<<"$input" 2>/dev/null)
[[ ${sid:-} =~ ^[A-Za-z0-9_-]+$ ]] && [ -f "${tp:-}" ] && [ -z "${agent:-}" ] || exit 0
d=${XDG_CACHE_HOME:-$HOME/.cache}/session-status; s=$d/handoff-$sid
claim() { (set -C; : > "$1") 2>/dev/null; }   # atomic: parallel tool calls fire the hook at once
if [ "$ev" = SessionStart ]; then
  rm -f "$s.soft" "$s.hard" "$s.noted"; [ "$src" = compact ] || { rm -f "$s.kind"; exit 0; }
  [ -e "$s.compact" ] && exit 0
elif [ -e "$s.hard" ]; then exit 0
fi

if ! read -r kind key n at hard note 2>/dev/null < "$s.kind"; then
  first=$(head -n 50 "$tp" | jq -Rrn 'first(inputs | fromjson? | select(.type == "user" and (.isMeta | not)) | .message.content
    | if type == "string" then . else (map(select(.type == "text") | .text) | join("\n")) end | select(length > 0)) // ""')
  [ -n "$first" ] || exit 0   # no prompt yet: decide later
  key=-; n=-
  if c=$(grep -m1 -E '^Chunk: ' <<<"$first"); then
    kind=chunk; c=${c#Chunk: }; key=${c%%/*}; n=${c##*/}
  elif grep -q '^Act as a coordinator' <<<"$first"; then kind=coordinator
  else kind=task; c=$(grep -m1 -E '^Session task: ' <<<"$first") && key=${c#Session task: } && key=${key%% *}
  fi
  key=${key//[^A-Za-z0-9_.-]/}; n=${n//[^A-Za-z0-9]/}; key=${key:--}
  [ "$kind" = task ] && [ "$key" = - ] && { mkdir -p "$d" && echo "task - - 0 0" > "$s.kind"; exit 0; }
  cd "${cwd:-.}" 2>/dev/null; . "$here/../lib.sh"
  at=$(config "handoff.at.$kind" 2>/dev/null); after=$(config handoff.hard_after 2>/dev/null)
  room=$(config handoff.stop_room 2>/dev/null); expect=$(config compact.window 2>/dev/null)
  w=${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}; from=env
  [[ $w =~ ^[0-9]+$ ]] || { w=$(jq -r '.autoCompactWindow // empty' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" 2>/dev/null); from=settings; }
  [[ $w =~ ^[0-9]+$ ]] || { w=$expect; from=config; }
  hard=$(( at + after )); (( w - 33000 - room < hard )) && hard=$(( w - 33000 - room ))
  (( at > 0 && hard - 10000 < at )) && at=$(( hard - 10000 ))
  note=; [ "$w" = "$expect" ] || note="This session's window is $w from $from; expected $expect."
  mkdir -p "$d" && echo "$kind $key ${n:--} $at $hard $note" > "$s.kind"
fi
(( at > 0 )) || exit 0

say() {
  [ -e "$s.noted" ] || { [ -z "$note" ] || set -- "$1 $note"; touch "$s.noted"; }
  jq -nc --arg e "$ev" --arg m "$1" '{hookSpecificOutput: {hookEventName: $e, additionalContext: $m}}'
}
case $kind in
  chunk) where="\`## c$n: handoff\` appended to $key-build.md in the replies folder"
         tell=" Message the coordinator \"handoff ready: $key c$n\"." ;;
  task) where="\`## Handoff\` in your replies file"; tell=" Message the coordinator \"handoff ready: $key\"." ;;
  *) where="the handover file your coordinator doc names"; tell= ;;
esac

if [ "$ev" = SessionStart ]; then
  [ "$kind" = chunk ] || exit 0
  claim "$s.compact" || exit 0; say "You were compacted mid-chunk. Write the handoff ($where) from what's on disk and stop.$tell"
  exit 0
fi

# The last 256K first: BSD tail -n 300 on a transcript of large tool results reads ~10 MB (150 ms); 256K takes 20 ms.
# ponytail: the last 300 lines only when 256K holds no usage (a tool result bigger than that).
# Subagent (sidechain) lines and all-zero usage (a synthetic or failed reply) don't count.
ctx_of() { LC_ALL=C grep -F '"usage":' | jq -Rn '[inputs | fromjson? | select(.type == "assistant" and (.isSidechain | not))
  | .message.usage // empty | (.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)
  | select(. > 0)] | last // empty' 2>/dev/null; }
ctx=$(tail -c 262144 "$tp" | ctx_of)
[ -n "$ctx" ] || ctx=$(tail -n 300 "$tp" | ctx_of)
[[ $ctx =~ ^[0-9]+$ ]] || exit 0
k=$(( ctx / 1000 ))K
if (( ctx > hard )); then
  claim "$s.hard" || exit 0; touch "$s.soft"
  say "Context is at $k, past the hard stop. Stop now: start nothing else, write the handoff ($where) from what's on disk.$tell Then end your turn."
elif (( ctx > at )) && claim "$s.soft"; then
  say "Context is at $k: hand off. Reach your stop point: finish the current edit, commit, run the checks, and start no new step. Write the handoff ($where).$tell Then end your turn."
fi
exit 0

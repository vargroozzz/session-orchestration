#!/usr/bin/env bash
# PostToolUse (every tool), UserPromptSubmit and SessionStart (compact): asks a session to hand off before it
# compacts. ctx = input + cache read + cache write of the last assistant line with usage in the transcript's tail
# (its last 256K, else its last 300 lines).
# - Kind, from the first user prompt: a `Chunk: KEY/N` line (lib.sh chunk_of) is a chunk, `Act as a coordinator` a
#   coordinator, `Session task: KEY review` a review (no messages), else a task (its `Session task: KEY` line names
#   it, else a `Work on KEY` start (lib.sh first_key), or a bare `KEY:` one in a coordinated project (an adapter or
#   key_pattern); a session with none isn't coordinated: no messages, until its name_session call finds a later
#   `Session task: KEY` line in its tail). A task
#   or review whose tail matches lib.sh's coord_re (session-status's coordinator test) is a coordinator from then on;
#   one without messages tests this call's own stdin instead, so it never reads the transcript.
# - Chunk and task texts end with the self-handover (session-status --handover --self) for when no coordinator runs.
# - Window: lib.sh compact_window (env, the project's settings, the user's, else config compact.window).
#   ceiling = window - 33000; hard = min(at + handoff.hard_after, ceiling - handoff.stop_room);
#   at = min(handoff.at.KIND, hard - 10000). handoff.at.KIND = 0: off. A window <= 0 is unknown (no clamp); one with
#   ceiling - stop_room < 20000 gets at = 60% and hard = 80% of the ceiling (of the window when ceiling <= 0).
# - Past at: one additionalContext (reach the stop point, write the handoff, tell the coordinator, end the turn);
#   past hard: one more (stop now). A window other than compact.window adds one line to the first one.
# - SessionStart after a compaction, chunk sessions only: write the handoff from what's on disk and stop. A
#   compaction or resume also clears the stamps (a resume may bring another window: the thresholds too, and the
#   compacted-mid-chunk stamp).
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
  rm -f "$s.soft" "$s.hard" "$s.noted"; [ "$src" = compact ] || { rm -f "$s.kind" "$s.compact"; exit 0; }
  [ -e "$s.compact" ] && exit 0
elif [ -e "$s.hard" ]; then exit 0
fi

# .kind: "KIND KEY N AT HARD NOTE"; a task's has coord_re on a second line, so no call sources lib.sh (13 ms).
cached=1 re=
if [ -f "$s.kind" ] && { read -r kind key n at hard note && case $kind in task|review) read -r re ;; esac; } < "$s.kind"; then :
else
  cd "${cwd:-.}" 2>/dev/null; . "$here/../lib.sh"
  first=$(first_prompt "$tp" 50)
  # no prompt yet: decide later; once past 50 lines, look further once (first_prompt stops at the first) and cache
  # what it finds, keyless when nothing
  [ -n "$first" ] || [ -z "$(sed -n '51{p;q;}' "$tp")" ] || first=$(first_prompt "$tp")
  [ -n "$first" ] || [ -n "$(sed -n '51{p;q;}' "$tp")" ] || exit 0
  key=-; n=-; cached=
  # ponytail: the adapter at the session's cwd (the project root as a rule); a subfolder session misses its status-names
  a=$(adapter_path . 2>/dev/null)
  if [ -z "$first" ]; then kind=task
  elif c=$(chunk_of "$first"); then kind=chunk; key=${c% *}; n=${c#* }
  elif grep -q '^Act as a coordinator' <<<"$first"; then kind=coordinator
  elif grep -qE '^Session task: [^ ]+ review([.,;:!)]|$)' <<<"$first"; then kind=review
  else kind=task
    if c=$(grep -m1 -E '^Session task: ' <<<"$first"); then key=${c#Session task: }; key=${key%% *}
    else KEYRE=$(key_re "$a"); key=$(first_key "$first")
      # a bare `KEY:` start names a task only where the project is coordinated; `Work on KEY` everywhere
      [ -n "$a" ] || [ -n "$(config key_pattern 2>/dev/null)" ] || grep -m1 . <<<"$first" | grep -qE '^[[:space:]]*[Ww]ork on ' || key=
    fi
  fi
  key=${key//[^A-Za-z0-9_.-]/}; while [[ $key == *. ]]; do key=${key%.}; done; key=${key:--}   # rnd.py strips .,;:!) too
  case $kind in task|review) [ -z "$a" ] || names=$("$a" status-names 2>/dev/null); re=$(coord_re "${names:-}") ;; esac
fi
thresholds() {   # at, hard and note for $kind, cached
  declare -F config >/dev/null || { cd "${cwd:-.}" 2>/dev/null; . "$here/../lib.sh"; }
  at=$(config "handoff.at.$kind" 2>/dev/null); after=$(config handoff.hard_after 2>/dev/null)
  room=$(config handoff.stop_room 2>/dev/null); expect=$(config compact.window 2>/dev/null)
  read -r w from < <(compact_window "${CLAUDE_PROJECT_DIR:-$cwd}")   # project settings live at its root, not a subfolder
  hard=$(( at + after )); small=
  # a window <= 0 is unknown: config's at and hard; one too small for the stop room: 60% and 80% of the ceiling (of
  # the window when there's no ceiling: it compacts at once anyway)
  if (( w > 0 && w - 33000 - room < 20000 )); then
    small=$(( w > 33000 ? w - 33000 : w )); hard=$(( small * 8 / 10 )); (( at > 0 )) && at=$(( small * 6 / 10 ))
  elif (( w > 0 && w - 33000 - room < hard )); then hard=$(( w - 33000 - room ))
  fi
  (( at > 0 && hard - 10000 < at && !small )) && at=$(( hard - 10000 ))
  note=; [ "$w" = "$expect" ] || note="This session's window is $w from $from; expected $expect."
  [ -z "$small" ] || note="${note:+$note }It is too small for handoff.stop_room: hand off at 60% of the $small before compaction, stop at 80%."
  mkdir -p "$d" && printf '%s %s %s %s %s %s\n%s' "$kind" "$key" "${n:--}" "$at" "$hard" "$note" "${re:+$re
}" > "$s.kind"
}
if [ -z "$cached" ]; then
  if [ "$kind" = review ] || { [ "$kind" = task ] && [ "$key" = - ]; }; then
    at=0 hard=0 note=; mkdir -p "$d" && printf '%s - - 0 0\n%s\n' "$kind" "$re" > "$s.kind"
  else thresholds; fi
fi
# A task or review without messages (no key, a review, handoff.at.task=0) only waits to turn coordinator: its own
# tool call (stdin, coord_re's tool_name branch) decides, without the tail, grep and jq (~39 ms on a 45 MB transcript).
# A keyless task's name_session call (a session that learned its key mid-run, SKILL.md) re-reads the tail for its last
# `Session task: KEY` line: found, it's that task from then on. Every other keyless call costs one regex test more.
if (( at <= 0 )); then
  case $kind in task|review) ;; *) exit 0 ;; esac
  if [ -n "$re" ] && [[ $input =~ $re ]]; then kind=coordinator key=- n= re=; rm -f "$s.soft"
  elif [ "$kind $key" = 'task -' ] && [[ $input =~ \"tool_name\":\"mcp__session-orchestration__name_session\" ]] &&
    c=$(tail -c 262144 "$tp" | grep 'Session task: ' | jq -r 'if .type=="assistant" then .message.content[]? | select(.type=="text")
      | .text elif .type=="user" and (.message.content|type)=="string" then .message.content else empty end' 2>/dev/null |
      grep -oE '^Session task: [A-Za-z0-9_.-]+( review([^a-z]|$))?' | tail -1) &&   # its own text and messages, as marks_of
    [[ $c != *' review'* ]]; then
    key=${c#*Session task: }; while [[ $key == *. ]]; do key=${key%.}; done; [ -n "$key" ] || exit 0
  else exit 0
  fi
  thresholds; (( at > 0 )) || exit 0
fi

say() {
  [ -e "$s.noted" ] || { [ -z "$note" ] || set -- "$1 $note"; touch "$s.noted"; }
  jq -nc --arg e "$ev" --arg m "$1" '{hookSpecificOutput: {hookEventName: $e, additionalContext: $m}}'
}
texts() {   # where the handoff goes, the -prev-K rename, whom to tell, and (chunk and task) the self-handover
  printf -v ss %q "${here%/hooks}/skills/orchestrating-sessions/session-status"
  local rn=" Rename yourself: call name_session with the name \`$ss --prev-name\` prints (your successor takes your name)."
  case $kind in
    chunk) where="\`## c$n: handoff ${sid:0:8}\` (your session id's first 8 characters) appended to $key-build.md in the replies folder"
           tell="$rn Message the coordinator \"handoff ready: $key c$n\"." ;;
    task) where="\`## Handoff\` in your replies file"; tell="$rn Message the coordinator \"handoff ready: $key\"." ;;
    *) where="the handover file your coordinator doc names"; tell= ;;
  esac
  case $kind in chunk|task) selfh=" If no coordinator is running (\`$ss --coordinator\` prints nothing), finish with \`$ss --handover --self -- '<next step>'\`." ;; *) selfh= ;; esac
}
if [ "$ev" = SessionStart ]; then
  [ "$kind" = chunk ] || exit 0
  texts
  claim "$s.compact" || exit 0; say "You were compacted mid-chunk. Write the handoff ($where) from what's on disk and stop.$tell"
  exit 0
fi

# The last 256K first: BSD tail -n 300 on a transcript of large tool results reads ~10 MB (150 ms); 256K takes 20 ms.
# ponytail: the last 300 lines only when 256K holds no usage (a tool result bigger than that).
# Subagent (sidechain) lines and all-zero usage (a synthetic or failed reply) don't count.
# The same pass tests a task session's tail (one with messages) against coord_re (lib.sh: session-status's definition): a match makes it
# a coordinator from then on, `Session task:` line or not, with its own at and text. Each extra process costs ~10 ms.
# A compact_boundary resets it: a manual /compact writes no assistant line before the next prompt, so the usage
# before it is stale (none after it: no ctx yet).
scan() { LC_ALL=C grep -E "\"usage\":|compact_boundary${re:+|$re}" | jq -Rrn --arg re "$re" '[inputs] | (if $re != "" and any(.[]; test($re))
  then "coordinator" else "-" end) + " " + ([.[] | fromjson? | if .type == "system" and .subtype == "compact_boundary" then -1
  else select(.type == "assistant" and (.isSidechain | not))
  | .message.usage // empty | (.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)
  | select(. > 0) end] | reduce .[] as $x (""; if $x < 0 then "" else $x end) | tostring)' 2>/dev/null; }
out=$(tail -c 262144 "$tp" | scan); ctx=${out#* }
[ -n "$ctx" ] || { ctx=$(tail -n 300 "$tp" | scan); ctx=${ctx#* }; }
if [ "${out%% *}" = coordinator ]; then kind=coordinator key=- n= re=; rm -f "$s.soft"; thresholds; fi
(( at > 0 )) || exit 0
[[ $ctx =~ ^[0-9]+$ ]] || exit 0
texts
k=$(( ctx / 1000 ))K
if (( ctx > hard )); then
  claim "$s.hard" || exit 0; touch "$s.soft"
  say "Context is at $k, past the hard stop. Stop now: start nothing else, write the handoff ($where) from what's on disk.$tell$selfh Then end your turn."
elif (( ctx > at )) && claim "$s.soft"; then
  say "Context is at $k: hand off. Reach your stop point: finish the current edit, commit, run the checks, and start no new step. Write the handoff ($where).$tell$selfh Then end your turn."
fi
exit 0

#!/usr/bin/env bash
# UserPromptSubmit, part N of 3 (hooks.json runs one entry per part, in parallel): a coordinator's Start context in its
# first prompt, as gastown's `gt prime` does, so Start needs no --start in the background, no wait for it and no
# memory reads (orchestrating-sessions SKILL.md, Start).
# - Fires only on a session's first prompt (no assistant line in its transcript yet) whose first line is `Act as a
#   coordinator` (a successor's too), or `Coordinate KEY: …` (a sub-coordinator: the header alone, no --start).
# - Part 1 runs `session-status --start` (env START_INJECT_BUDGET seconds, 120; past it the run is killed and the text
#   says to run it as today) and writes the whole text to start-<sid>.md in the cache folder; parts 2 and 3 wait for
#   that file. Text: a header, the project memory index and its coordinator.md topic (CLAUDE.md's `Project memory`
#   line), then --start's output.
# - Claude Code saves an additionalContext over 10,000 characters to a file and shows a preview, so each part carries
#   one piece of at most 9,500 bytes, cut at line ends; part 3 points to the file when the text needs more pieces.
# Self-test: bash start-inject.test.sh
part=${1:-1} input=$(cat)
# cheap gate first: this runs on every prompt of every session
[[ $input =~ \"prompt\":[[:space:]]*\"(Act\ as\ a\ coordinator|[[:space:]]*Coordinate\ ) ]] || exit 0
{ read -r sid; read -r tp; read -r cwd; read -r agent; } < <(jq -r '.session_id // "", .transcript_path // "", .cwd // "",
  .agent_id // ""' <<<"$input" 2>/dev/null)
[[ ${sid:-} =~ ^[A-Za-z0-9_-]+$ ]] && [ -f "${tp:-}" ] && [ -z "${agent:-}" ] || exit 0
! grep -q -m1 '"type":"assistant"' "$tp" || exit 0   # a resumed session: its Start is done
prompt=$(jq -r '.prompt // ""' <<<"$input"); first=$(grep -m1 . <<<"$prompt")
here=$(cd "$(dirname "$0")" && pwd); skill=${here%/hooks}/skills/orchestrating-sessions
ss=${START_INJECT_SS:-$skill/session-status}
d=${XDG_CACHE_HOME:-$HOME/.cache}/session-status; f=$d/start-$sid.md; lim=9500 parts=3
cd "${cwd:-.}" 2>/dev/null || exit 0
if [[ $first =~ ^[[:space:]]*Coordinate\  ]]; then
  . "$here/../lib.sh"; KEYRE=$(key_re "$(adapter_path . 2>/dev/null)"); key=$(sub_key "$prompt") || exit 0
  [ "$part" = 1 ] || exit 0
  jq -nc --arg m "Start context (session-orchestration hook): you are $key's sub-coordinator. In your first batch, load the orchestrating-sessions skill and Read $skill/subcoordinator.md whole (and the KEY-coordinator.md your prompt names, if any). SKILL.md's Start isn't yours: no --start, no open_pane." \
    '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $m}}'
  exit 0
fi
[[ $first == 'Act as a coordinator'* ]] || exit 0
if [ "$part" = 1 ]; then
  mkdir -p "$d"; budget=${START_INJECT_BUDGET:-120} out=$d/start-$sid.out
  set -m   # its own process group, so a run past the budget is stopped with its children
  (CLAUDE_CODE_SESSION_ID=$sid bash "$ss" --start > "$out" 2>&1; echo "$?" > "$out.rc") & pid=$!; set +m
  i=0; while [ ! -e "$out.rc" ] && (( i < budget * 2 )); do sleep 0.5; i=$((i + 1)); done
  . "$here/../lib.sh"; root=$(find_root)
  mem=$(sed -nE 's/.*Project memory[^`]*`([^`]+)`.*/\1/p' "$root/CLAUDE.md" "$root/CLAUDE.local.md" 2>/dev/null | head -1)
  mem=${mem/#\~/$HOME}; case $mem in ''|/*) ;; *) mem=$root/$mem ;; esac
  {
    echo "# Start context (session-orchestration hook)"
    echo "Injected at your first prompt so your Start needs no --start run and no memory reads (SKILL.md, Start). In your first batch: load the orchestrating-sessions skill, ToolSearch mcp__session-orchestration__open_pane, and Read the project's coordinator doc if its CLAUDE.md names one. Then go on from Start step 2 with the output below."
    if [ -e "$out.rc" ]; then rc=$(cat "$out.rc")
      printf '\n## session-status --start (run by the hook%s)\n' "$([ "$rc" = 0 ] || echo ", exit $rc")"; cat "$out"
    else { kill -- -"$pid"; kill "$pid"; wait "$pid"; } 2>/dev/null
      printf '\n## session-status --start\n(not finished in %s s, so stopped: run it yourself as Start step 1 says, in the background)\n' "$budget"
    fi
    for m in "$mem" "${mem%/*}/memory/coordinator.md"; do
      [ -n "$mem" ] && [ -f "$m" ] && printf '\n## %s\n%s\n' "$m" "$(cat "$m")"
    done
  } > "$f.$$"; mv -f "$f.$$" "$f"; rm -f "$out" "$out.rc"
else
  i=0; while [ ! -s "$f" ] && (( i < 280 )); do sleep 0.5; i=$((i + 1)); done; [ -s "$f" ] || exit 0
fi
# piece N of the text, at most lim bytes, cut at line ends (a longer line cut at lim); stderr: the count and the line
# piece N starts at
LC_ALL=C awk -v lim="$lim" -v want="$part" '
  function flush() { if (len) { n++; if (n == want) printf "%s", buf; buf = ""; len = 0 } }
  function add(s) { if (!len && n + 1 == want) at = NR; buf = buf s "\n"; len += length(s) + 1 }
  { while (length($0) > lim) { flush(); add(substr($0, 1, lim)); flush(); $0 = substr($0, lim + 1) }
    if (len + length($0) + 1 > lim) flush(); add($0) }
  END { flush(); print n, at > "/dev/stderr" }' "$f" > "$f.p$part" 2> "$f.n$part"
read -r n at < "$f.n$part"; m=$(cat "$f.p$part"); rm -f "$f.p$part" "$f.n$part"
(( n > parts && part == parts )) && m="The rest of the Start context didn't fit the hook's $parts parts: Read $f from line $at on (offset $at)."
[ -n "$m" ] || exit 0
jq -nc --arg m "Start context, part $part of $(( n < parts ? n : parts )):
$m" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $m}}'

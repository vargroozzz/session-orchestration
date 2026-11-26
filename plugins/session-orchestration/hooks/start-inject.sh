#!/usr/bin/env bash
# UserPromptSubmit, part N of 3 (hooks.json runs one entry per part, in parallel): a coordinator's Start context in its
# first prompt, as gastown's `gt prime` does, so Start needs no --start in the background, no wait for it and no
# memory reads (orchestrating-sessions SKILL.md, Start).
# - Fires only on a session's first prompt (no transcript file yet, or no assistant line in it) whose first line is `Act as a
#   coordinator` (a successor's too), or `Coordinate KEY: …` (a sub-coordinator: the header alone, no --start). Not
#   in a project with its own status command (adapter status-names): its Start runs that, as before.
# - Part 1 runs `session-status --start` (env START_INJECT_BUDGET seconds, 120; past it the run goes on, never killed
#   mid-migration, and the text says how to wait for it) and writes the whole text to start-<sid>.md in the cache
#   folder (files there over 3 days old are deleted); parts 2 and 3 wait for that file. Text: a header, --start's
#   output, then the project memory index and its coordinator.md topic (CLAUDE.md's `Project memory` line).
# - Claude Code saves an additionalContext over 10,000 characters to a file and shows a preview, so each part carries
#   one piece of at most 9,500 bytes, cut at line ends; part 3 points to the file when the text needs more pieces.
# Self-test: bash start-inject.test.sh
part=${1:-1} input=$(cat)
# cheap gate first: this runs on every prompt of every session
[[ $input =~ \"prompt\":[[:space:]]*\"(Act\ as\ a\ coordinator|[[:space:]]*Coordinate\ ) ]] || exit 0
{ read -r sid; read -r tp; read -r cwd; read -r agent; } < <(jq -r '.session_id // "", .transcript_path // "", .cwd // "",
  .agent_id // ""' <<<"$input" 2>/dev/null)
# a new session's transcript doesn't exist yet at its first prompt: Claude Code writes it after this hook
[[ ${sid:-} =~ ^[A-Za-z0-9_-]+$ ]] && [ -n "${tp:-}" ] && [ -z "${agent:-}" ] || exit 0
! grep -q -m1 '"type":"assistant"' "$tp" 2>/dev/null || exit 0   # a resumed session: its Start is done
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
# a project with its own status command (adapter status-names) runs Start as before: the hook can't call it
. "$here/../lib.sh"; a=$(adapter_path . 2>/dev/null)
[ -z "$a" ] || [ -z "$("$a" status-names 2>/dev/null)" ] || exit 0
if [ "$part" = 1 ]; then
  mkdir -p "$d"; rm -f "$f"; budget=${START_INJECT_BUDGET:-120} out=$d/start-$sid.$$.out   # per run: a retried prompt never reads an older run's files
  find "$d" -maxdepth 1 -name 'start-*' -mtime +3 -delete 2>/dev/null
  set -m   # its own process group: a run past the budget (or the hook's end) goes on; --start may be migrating files
  (CLAUDE_CODE_SESSION_ID=$sid bash "$ss" --start > "$out" 2>&1; echo "$?" > "$out.rc.tmp"; mv -f "$out.rc.tmp" "$out.rc") </dev/null & set +m
  i=0; while [ ! -e "$out.rc" ] && (( i < budget * 2 )); do sleep 0.5; i=$((i + 1)); done
  root=$(find_root)
  mem=$(sed -nE 's/.*Project memory[^`]*`([^`]+)`.*/\1/p' "$root/CLAUDE.md" "$root/CLAUDE.local.md" "$root/.claude/CLAUDE.md" 2>/dev/null | head -1)
  mem=${mem/#\~/$HOME}; case $mem in ''|/*) ;; *) mem=$root/$mem ;; esac
  {
    echo "# Start context (session-orchestration hook)"
    echo "Injected at your first prompt so your Start needs no --start run and no memory reads (SKILL.md, Start). In your first batch: load the orchestrating-sessions skill, ToolSearch mcp__session-orchestration__open_pane, and Read the project's coordinator doc if its CLAUDE.md names one. Then go on from Start step 2 with the output below."
    if [ -e "$out.rc" ]; then rc=$(cat "$out.rc")
      printf '\n## session-status --start (run by the hook%s)\n' "$([ "$rc" = 0 ] || echo ", exit $rc")"; cat "$out"; rm -f "$out" "$out.rc"
    else
      printf '\n## session-status --start\n(still running after %s s, writing %s: in your first batch, wait for it as Bash run_in_background: `while [ ! -e %s.rc ]; do sleep 2; done; cat %s`, and use its output as Start step 3 says)\n' "$budget" "$out" "$out" "$out"
    fi
    if [ -z "$mem" ]; then printf '\n(no `Project memory` line in CLAUDE.md: read the memory files yourself, if the project has any)\n'; fi
    for m in "$mem" "${mem%/*}/memory/coordinator.md"; do
      [ -n "$mem" ] && [ -f "$m" ] && printf '\n## %s\n%s\n' "$m" "$(cat "$m")"
    done
  } > "$f.$$"; mv -f "$f.$$" "$f"
else
  # only a text written since this prompt (a second's grace: part 1 may beat this part's start), not an earlier try's
  t0=$(( $(date +%s) - 1 )); fresh() { local m; [ -s "$f" ] && m=$(mtime "$f" 2>/dev/null) && (( m >= t0 )); }
  i=0; while ! fresh && (( i < 280 )); do sleep 0.5; i=$((i + 1)); done; fresh || exit 0
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

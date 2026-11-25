#!/usr/bin/env bash
# PostToolUse (every tool), UserPromptSubmit and SessionStart (compact): asks a session to hand off before it
# compacts. ctx = input + cache read + cache write of the last assistant line with usage in the transcript's tail
# (its last 256K, else its last 300 lines).
# - Kind, from the first user prompt: a `Chunk: KEY/N` line (lib.sh chunk_of) is a chunk, `Act as a coordinator` a
#   coordinator, `Coordinate KEY` a sub-coordinator (lib.sh sub_key: KEY's own coordinator; handoff.at.coordinator,
#   the self-handover with its handoff in KEY-coordinator.md; never turned coordinator), `Session task: KEY review` a review (no messages), `Session task: retro run, scope S, section group G` a section (key retro-S-G, handoff.at.task, its own
#   mark text: cut the section short, no handover), else a task (its `Session task: KEY` line names
#   it, else a `Work on KEY` start (lib.sh first_key), or a bare `KEY:` one in a coordinated project (an adapter or
#   key_pattern), else a `Work on NAME` start naming its own -n name (a tracker-less project: keyed by NAME); a session with none isn't coordinated: no messages, until its name_session call finds a later
#   `Session task: KEY` line in its tail). A task
#   or review whose tail matches lib.sh's coord_re (session-status's coordinator test; a keyed task or a review:
#   coord_pane_re, its open_pane branch alone) is a coordinator from then on;
#   one without messages tests this call's own stdin instead, so it never reads the transcript.
# - Chunk and task texts end with the self-handover (session-status --handover --self), coordinator or not; they message
#   the coordinator only when it fails or makes no progress.
# - Window: lib.sh compact_window (env, the project's settings, the user's, else config compact.window).
#   ceiling = window - 33000; hard = min(at + handoff.hard_after, ceiling - handoff.stop_room);
#   at = min(handoff.at.KIND, hard - 10000). handoff.at.KIND = 0: off. A window <= 0 is unknown (no clamp); one with
#   ceiling - stop_room < 20000 gets at = 60% and hard = 80% of the ceiling (of the window when ceiling <= 0).
# - Past at: one additionalContext (reach the stop point, write the handoff, hand over by itself (a coordinator: start its successor));
#   past hard: one more (stop now). A window other than compact.window, or one no setting gives (config), adds one
#   line to the first one.
# - SessionStart after a compaction, chunk sessions only: write the handoff from what's on disk and stop. A
#   compaction or resume also clears the stamps (a resume may bring another window: the thresholds too, and the
#   compacted-mid-chunk stamp).
# - The reply card (reply-card.txt, {dir} the skill's folder): how to answer a message without the skill. Once per
#   session, again after a compaction, never a coordinator's. A keyed task, a chunk or a review gets it at its first
#   firing after .kind is written (a first prompt only writes it, detached: below); any other session at its first message (.msg, which the module's session.receive hook writes, mid-turn
#   too). It rides on the firing's other text, if any.
# - A peer message holding relayed approvals: says, before anything else, whether each verifies (below).
# Subagents' tool calls (agent_id set) are skipped: they carry the parent's transcript.
# Stamps: ${XDG_CACHE_HOME:-~/.cache}/session-status/handoff-<sid>.<level>; .kind caches the kind and thresholds.
# ponytail: thresholds cached per session when it's classified; a config change reaches the next session.
# Self-test: bash context-watch.test.sh
here=$(cd "$(dirname "$0")" && pwd); input=$(cat)
{ read -r sid; read -r tp; read -r ev; read -r cwd; read -r src; read -r agent; } < <(jq -r '.session_id // "", .transcript_path // "",
  .hook_event_name // "", .cwd // "", .source // "", .agent_id // ""' <<<"$input" 2>/dev/null)
[[ ${sid:-} =~ ^[A-Za-z0-9_-]+$ ]] && [ -f "${tp:-}" ] && [ -z "${agent:-}" ] || exit 0
d=${XDG_CACHE_HOME:-$HOME/.cache}/session-status; s=$d/handoff-$sid
emit() { jq -nc --arg e "$ev" --arg m "$1" '{hookSpecificOutput: {hookEventName: $e, additionalContext: $m}}'; }
# A relayed approval (approvals.md's block) in a peer message: each block checked now as the approval hook will
# (verify-approval.sh; the sender is the from-name of the tag it came in, the key as approved-action.sh takes it: a
# tracker key in the Action, else its "(<this session's name>[, approved under KEY])", else REPO#N, else this session's
# name), one line each: `relay verified: ACTION` (then what the script adds) or `relay rejected: REASON (ACTION)`.
# Inline: hooks.json gives UserPromptSubmit 60 s; any other prompt pays one string test. The reply card waits for the
# next firing.
if [ -z "${CW_DETACHED:-}" ] && [ "$ev" = UserPromptSubmit ] && [[ $input == *'<cross-session-message from='*'APPROVAL relayed from the user'* ]]; then
  me=$(grep -F '"agent-name"' "$tp" | tail -1 | jq -r '.agentName // empty' 2>/dev/null) out=
  while IFS= read -r b; do
    { read -r from; read -r bsid; read -r scwd; read -r a; } < <(jq -r '.from, .sid, .scwd, .action' <<<"$b")
    k=$(grep -oE '[A-Z][A-Z0-9]+-[0-9]+' <<<"$a" | head -1)
    if [ -z "$k" ] && [[ $a =~ \(([A-Za-z0-9][A-Za-z0-9._-]*)(,[[:space:]]*approved[[:space:]]+under[[:space:]]+([A-Za-z0-9][A-Za-z0-9._-]*))?\)[[:space:]]*\.?[[:space:]]*$ ]] &&
       [ "${BASH_REMATCH[1]}" = "$me" ]; then k=${BASH_REMATCH[3]:-$me}; fi
    [ -n "$k" ] || [[ ! $a =~ ([A-Za-z0-9._-]+#[0-9]+) ]] || k=${BASH_REMATCH[1]}
    v=$(cd "$cwd" 2>/dev/null && jq -r .quote <<<"$b" |
        bash "$here/../skills/orchestrating-sessions/verify-approval.sh" "$bsid" "$scwd" "$from" "${k:-$me}" "$a")
    # what the script adds (answering:, the user's note, a handed command to withdraw) is the worker's to judge
    if [[ $v == verified* ]]; then out+="relay verified: $a${v#verified}"$'\n'
    else v=${v:-verify-approval.sh failed}; out+="relay rejected: ${v#rejected: } ($a)"$'\n'; fi
  done < <(jq -c '.prompt // "" | [scan("<cross-session-message ([^>]*)>([\\s\\S]*?)</cross-session-message>")][]
    | (.[0] | capture("from-name=\"(?<n>[^\"]*)\"").n // "") as $n
    | .[1] | [scan("APPROVAL relayed from the user\\nQuote: ([\\s\\S]*?)\\nAction: ([^\\n]*)\\nSource: ([0-9a-f-]{36}) ([^\\n]+)")][]
    | {from: $n, quote: .[0], action: .[1], sid: .[2], scwd: .[3]}' <<<"$input" 2>/dev/null)
  [ -z "$out" ] || { emit "${out%$'\n'}"; exit 0; }
fi
claim() { (set -C; : > "$1") 2>/dev/null; }   # atomic: parallel tool calls fire the hook at once
# Classifying (no .kind yet: a session's first prompt, or a resume) takes ~40 processes: 5-18 s on a loaded machine,
# past the 5 s kill, which left no .kind, so every prompt redid it. A resume and a first prompt classify in a detached
# copy (its own process group, one at a time: .classifying) and return at once; a firing while it runs skips (its
# .kind serves the next one, and a card due now goes out then). Other firings without .kind classify inline.
detach() {
  mkdir -p "$d"; rm -f "$s.classifying"; claim "$s.classifying" || return 0
  (set -m; CW_DETACHED=1 bash "$0" <<<"$input" >/dev/null 2>&1 &)
}
if [ -n "${CW_DETACHED:-}" ]; then trap 'rm -f "$s.classifying"' EXIT
elif [ "$ev" = SessionStart ]; then
  rm -f "$s.soft" "$s.hard" "$s.noted"; [ "$src" = compact ] || { rm -f "$s.kind" "$s.compact"; detach; exit 0; }
  rm -f "$s.card"; [ -e "$s.compact" ] && exit 0
elif [ ! -f "$s.kind" ]; then
  [ -z "$(find "$s.classifying" -mmin -1 2>/dev/null)" ] || exit 0   # one running (a minute: it died)
  [ "$ev" != UserPromptSubmit ] || { detach; exit 0; }
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
  # the adapter's key pattern only for a `Coordinate` first line: it costs a process, and classifying races the 5s kill
  elif grep -m 1 . <<<"$first" | grep -qE '^[[:space:]]*Coordinate ' && KEYRE=$(key_re "$a") && sk=$(sub_key "$first"); then
    kind=subcoordinator key=$sk
  elif grep -q '^Act as a coordinator' <<<"$first"; then kind=coordinator
  elif grep -qE '^Session task: [^ ]+ review([.,;:!)]|$)' <<<"$first"; then kind=review
  # a retro section (retro-run's split run): keyed by scope and group, its own mark text, no handover
  elif c=$(grep -m1 -E '^Session task: retro run, scope [a-z]+, section group [a-z0-9_-]+' <<<"$first"); then
    [[ $c =~ scope\ ([a-z]+),\ section\ group\ ([a-z0-9_-]+) ]]; kind=section key=retro-${BASH_REMATCH[1]}-${BASH_REMATCH[2]}
  else kind=task
    if c=$(grep -m1 -E '^Session task: ' <<<"$first"); then key=${c#Session task: }; key=${key%% *}
      # retro-run's `retro run, scope S`: one key per scope, or two scopes at once share one handoff file
      [[ ! $c =~ ^Session\ task:\ retro\ run,\ scope\ ([a-z]+) ]] || key=retro-${BASH_REMATCH[1]}
    else KEYRE=$(key_re "$a"); key=$(first_key "$first")
      # a bare `KEY:` start names a task only where the project is coordinated; `Work on KEY` everywhere
      [ -n "$a" ] || [ -n "$(config key_pattern 2>/dev/null)" ] || grep -m1 . <<<"$first" | grep -qE '^[[:space:]]*[Ww]ork on ' || key=
      # no key: a `Work on NAME` start naming its own -n name (a tracker-less project's task) is keyed by that name
      if [ -z "$key" ] && nm=$(head -n 50 "$tp" | jq -Rrn 'first(inputs | fromjson? | select(.type == "agent-name") | .agentName) // ""') &&
        [ -n "$nm" ] && l=$(grep -m1 . <<<"$first") && l=${l#"${l%%[![:space:]]*}"} &&
        [[ $l == [Ww]"ork on $nm" || $l == [Ww]"ork on $nm"[!A-Za-z0-9_-]* ]]; then key=$nm; fi
    fi
  fi
  key=${key//[^A-Za-z0-9_.-]/}; while [[ $key == *. ]]; do key=${key%.}; done; key=${key:--}   # retro.py strips .,;:!) too
  # a keyed task or a review runs session-status --start/--watch only to test or measure it: only open_pane counts
  case "$kind $key" in 'task -') [ -z "$a" ] || names=$("$a" status-names 2>/dev/null); re=$(coord_re "${names:-}") ;;
    task*|review*) re=$(coord_pane_re) ;; esac
fi
thresholds() {   # at, hard and note for $kind, cached
  declare -F config >/dev/null || { cd "${cwd:-.}" 2>/dev/null; . "$here/../lib.sh"; }
  [ -n "$coord_memo" ] || coord_memo=$(coord_json 2>/dev/null)   # one merge for every config read, not one each
  local k=${kind#sub}; [ "$k" != section ] || k=task   # a section marks where a task does
  at=$(config "handoff.at.$k" 2>/dev/null); after=$(config handoff.hard_after 2>/dev/null)
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
  # config = nothing set it: the real window is the model's own (1M on a 1M model), so the marks are a guess
  [ "$from" != config ] || note="No autoCompactWindow found in env, project or user settings: these marks assume compact.window $w, but this session compacts at its model's own window (a 1M model's is 1M). Set autoCompactWindow in Claude Code settings (setting-up-coordination)."
  [ -z "$small" ] || note="${note:+$note }It is too small for handoff.stop_room: hand off at 60% of the $small before compaction, stop at 80%."
  mkdir -p "$d" && printf '%s %s %s %s %s %s\n%s' "$kind" "$key" "${n:--}" "$at" "$hard" "$note" "${re:+$re
}" > "$s.kind.$$" && mv -f "$s.kind.$$" "$s.kind"   # whole or not at all: a writer may be killed
}
if [ -z "$cached" ]; then
  if [ "$kind" = review ] || { [ "$kind" = task ] && [ "$key" = - ]; }; then
    at=0 hard=0 note=; mkdir -p "$d" && printf '%s - - 0 0\n%s\n' "$kind" "$re" > "$s.kind.$$" && mv -f "$s.kind.$$" "$s.kind"
  else thresholds; fi
fi
[ -z "${CW_DETACHED:-}" ] || exit 0   # the detached copy only writes .kind
# The card goes out with this firing's other text (say), else on exit; a prompt that is a message counts as one.
card=
# a retro section sends nothing unasked: like a keyless task, its card waits for a message
if [ "$kind" != coordinator ] && [ ! -e "$s.card" ] && { { [ "$kind $key" != 'task -' ] && [ "$kind" != section ]; } || [ -e "$s.msg" ] ||
  [[ $ev = UserPromptSubmit && $input == *'<cross-session-message from='* ]]; } && claim "$s.card"; then
  card=$(cat "$here/reply-card.txt") && card=${card//'{dir}'/"${here%/hooks}/skills/orchestrating-sessions"}
  trap '[ -z "$card" ] || emit "$card"' EXIT
fi
# shortcut: a coordinator whose first prompt isn't `Act as a coordinator` is a keyless task until its first status
# run, so a message before that gets it the card; tell it by the first prompt if retro.py loads shows coordinator cards.
[ ! -e "$s.hard" ] || exit 0   # past the hard stop: told to stop, nothing more (but a card still due)
# A task or review without messages (no key, a review, handoff.at.task=0) only waits to turn coordinator: its own
# tool call (stdin, coord_re's tool_name branch) decides, without the tail, grep and jq (~39 ms on a 45 MB transcript).
# A keyless task's name_session call (a session that learned its key mid-run, worker.md) re-reads the tail for its last
# `Session task: KEY` line: found, it's that task from then on. Every other keyless call costs one regex test more.
if (( at <= 0 )); then
  case $kind in task|review) ;; *) exit 0 ;; esac
  if [ -n "$re" ] && [[ $input =~ $re ]]; then kind=coordinator key=- n= re= card=; rm -f "$s.soft"
  elif [ "$kind $key" = 'task -' ] && [[ $input =~ \"tool_name\":\"mcp__session-orchestration__name_session\" ]] &&
    c=$(tail -c 262144 "$tp" | grep 'Session task: ' | jq -r 'if .type=="assistant" then .message.content[]? | select(.type=="text")
      | .text elif .type=="user" and (.message.content|type)=="string" then .message.content else empty end' 2>/dev/null |
      grep -oE '^Session task: [A-Za-z0-9_.-]+( review([^a-z]|$))?' | tail -1) &&   # its own text and messages, as marks_of
    [[ $c != *' review'* ]]; then
    key=${c#*Session task: }; while [[ $key == *. ]]; do key=${key%.}; done; [ -n "$key" ] || exit 0
    declare -F coord_pane_re >/dev/null || { cd "${cwd:-.}" 2>/dev/null; . "$here/../lib.sh"; }; re=$(coord_pane_re)   # keyed now
  else exit 0
  fi
  thresholds; (( at > 0 )) || exit 0
fi

say() {
  [ -e "$s.noted" ] || { [ -z "$note" ] || set -- "$1 $note"; touch "$s.noted"; }
  emit "${card:+$card

}$1"; card=
}
texts() {   # where the handoff goes, the -prev-K rename, whom to tell, and (chunk and task) the self-handover
  printf -v ss %q "${here%/hooks}/skills/orchestrating-sessions/session-status"
  # The exceptions come first: a coordinator's --escalate is refused once --self has superseded the session.
  local hs=" Then, unless this handoff makes no progress on the one your first prompt's \`Supersedes:\` continued$([ "$kind" != chunk ] || echo " or you are past 2× your brief's est"), hand yourself over: \`$ss --handover --self -- '<next step>'\`, and do what it prints (rename yourself, end your turn); the coordinator needs no message. In those cases, or when that command fails, don't hand over: message it \"handoff ready: $key$([ "$kind" != chunk ] || echo " c$n")\" with why (it decides whether to escalate)."
  # A handoff naming only files and lines makes the successor re-read them, up to the mark again with nothing edited.
  # Conditional: the hook can't tell a task that changes nothing (research, a plan awaiting sign-off). Indented: the handoff files are parsed by their `## ` lines.
  edits=; case $kind in chunk|task) edits=" If your task changes files and you have edited none yet, write the edits you decided on into it as text (per file, the text to replace and the new text, indented so no line of it starts with \`## \`): your successor applies them instead of re-reading what you read." ;; esac
  case $kind in
    chunk) where="\`## c$n: handoff ${sid:0:8}\` (your session id's first 8 characters) appended to $key-build.md in the replies folder"
           tell=$hs ;;
    subcoordinator) where="\`## Handoff\` in $key-coordinator.md in the replies folder, with the status report at its top brought up to date"; tell=$hs ;;
    task) where="\`## Handoff\` in your replies file, with the status report at its top brought up to date (older handoffs and drafts move to $key-archive.md: worker.md, Replying)"; tell=$hs ;;
    *) where="coordinator-handover.md in the replies folder, the handover file: overwrite it with the state in no file, as ${here%/hooks}/skills/orchestrating-sessions/handover.md says"
       tell=" Then start your successor with \`$ss --successor\` and do what it prints (that file has the steps)." ;;
  esac
}
if [ "$ev" = SessionStart ]; then
  [ "$kind" = chunk ] || exit 0
  texts
  claim "$s.compact" || exit 0; say "You were compacted mid-chunk. Write the handoff ($where) from what's on disk and stop.$tell"
  exit 0
fi

# The last 256K first: BSD tail -n 300 on a transcript of large tool results reads ~10 MB (150 ms); 256K takes 20 ms.
# ponytail: the last 300 lines only when 256K holds no usage (a tool result bigger than that).
# Subagent (sidechain) lines and all-zero usage (a synthetic or failed reply) don't count. A line with
# usage.iterations counts its last `message` one: the totals add up every iteration (an advisor call splits the turn
# in two, each re-reading the context) and leave the advisor's own read out.
# The same pass tests a task session's tail (one with messages) against coord_re (lib.sh: session-status's definition): a match makes it
# a coordinator from then on, `Session task:` line or not, with its own at and text. Each extra process costs ~10 ms.
# A compact_boundary resets it: a manual /compact writes no assistant line before the next prompt, so the usage
# before it is stale (none after it: no ctx yet).
scan() { LC_ALL=C grep -E "\"usage\":|compact_boundary${re:+|$re}" | jq -Rrn --arg re "$re" '[inputs] | (if $re != "" and any(.[]; test($re))
  then "coordinator" else "-" end) + " " + ([.[] | fromjson? | if .type == "system" and .subtype == "compact_boundary" then -1
  else select(.type == "assistant" and (.isSidechain | not))
  | .message.usage // empty | ((.iterations | if type == "array" then map(select(.type? == "message")) | last else null end) // .) | (.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)
  | select(. > 0) end] | reduce .[] as $x (""; if $x < 0 then "" else $x end) | tostring)' 2>/dev/null; }
out=$(tail -c 262144 "$tp" | scan); ctx=${out#* }
[ -n "$ctx" ] || { ctx=$(tail -n 300 "$tp" | scan); ctx=${ctx#* }; }
if [ "${out%% *}" = coordinator ]; then kind=coordinator key=- n= re= card=; rm -f "$s.soft"; thresholds; fi
(( at > 0 )) || exit 0
[[ $ctx =~ ^[0-9]+$ ]] || exit 0
texts
k=$(( ctx / 1000 ))K
if [ "$kind" = section ]; then   # no handover: the section's file says what it got, the writer goes on from there
  cut="your retro section ends here, without a handover: write its sections/GROUP.md from what you have, what's left as one candidate proposal (a research task), its status file \`done: cut at mark\`, then \`retro-run --join\` on the run folder (the retro skill's Section session). Then end your turn."
  if (( ctx > hard )); then claim "$s.hard" || exit 0; touch "$s.soft"; say "Context is at $k, past the hard stop. Stop now: $cut"
  elif (( ctx > at )) && claim "$s.soft"; then say "Context is at $k: $cut"; fi
  exit 0
fi
if (( ctx > hard )); then
  claim "$s.hard" || exit 0; touch "$s.soft"
  say "Context is at $k, past the hard stop. Stop now: start nothing else, write the handoff ($where) from what's on disk.$edits$tell Then end your turn."
elif (( ctx > at )) && claim "$s.soft"; then
  say "Context is at $k: hand off. Reach your stop point: finish the current edit, commit, run the checks, and start no new step. Write the handoff ($where).$edits$tell Then end your turn."
fi
exit 0

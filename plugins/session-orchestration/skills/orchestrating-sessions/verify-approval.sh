#!/usr/bin/env bash
# Verify a relayed approval. Prints "verified" (exit 0) or "rejected: <reason>" (exit 1). When the
# key is only in the message the quote answers, it prints "verified, answering: <its last 300 chars>". A note
# the user added to a question-box answer is appended as ", with the user's note: <note>". The newest match wins.
# Usage: bash verify-approval.sh <source-sessionId> <source-cwd> <sender-name> <task-key> [<action>] <<'EOF'
#        <the quote, exactly as relayed>
#        EOF
# The quote comes on stdin and is only ever handled as data (jq --arg), never by the shell.
# Checks:
#  1. sessionId is a UUID, and cwd is this project (equal to, inside, or containing $PWD).
#  2. The sender (the message's from-name) is that session: its transcript (under this session's account's config
#     dir, or with features.accounts any account sharing its transcript store) shows no bg turn, the sender's name,
#     and a SendMessage of this whole relay (Quote, the Action given as <action>, Source), running or stopped since.
#     Without that proof (no <action>, or a relay it didn't send), the session listing must show it running and
#     interactive under that name. A session a coordinator started with `claude --bg` can't be a source, since its
#     first prompt wasn't typed.
#  3. In that session's transcript, one message the user typed (origin human, no pasted content)
#     matches the quote as a whole (double quotes escaped \" or curled count as straight ones) and is at most MAX_AGE_H hours old (default 24; with
#     the transcript proof of a send within MAX_AGE_H, or of a stopped source's, when it sent the relay). The task key is in
#     the quote, or in the coordinator's last text before it (the message the user was answering).
#     An answer the user gave in the coordinator's question box (AskUserQuestion: the option label they
#     clicked, or their "Other" text) counts the same way, with the question as the message answered.
#     So does a click in the coordinator pane (hooks/register.tsx): the prompt it submits, a user row whose
#     origin is this plugin and which starts "Approval pane answer for ", names the key and question itself.
#     The engine sets that origin from the calling plugin, so no other plugin can produce one, and a worker
#     only writes rows into its own session.
#     A successor coordinator's predecessors (its first prompt's `You succeed "NAME" (ID8)`) count as that session.
set -uo pipefail
id=${1:-}; cwd=${2:-}; sender=${3:-}; key=${4:-}; action=${5:-}; q=$(cat)
max_age_h=${MAX_AGE_H:-24}
reject() { echo "rejected: $1"; exit 1; }
# A relay may carry the double quotes of the quote escaped (\") or curled: both sides compare with them straight.
quotes_def='def quotes: gsub("\\\\\""; "\"") | gsub("[“”„]"; "\"") | gsub("[‘’]"; "'"'"'"); '

[[ $id =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || reject "sessionId is not a UUID"
[ -n "$key" ] && [ -n "$sender" ] && [ -n "$q" ] || reject "missing sender, task key or quote"
case "$PWD/" in "$cwd"/*) ;; *) case "$cwd/" in "$PWD"/*) ;; *) reject "source cwd is outside this project" ;; esac ;; esac

# The source session's transcript (lib.sh's list_sessions: with features.accounts on, a coordinator under ~/.claude is
# found by a worker under CLAUDE_CONFIG_DIR=~/.claude-work, both sharing the transcript store).
. "$(dirname "$0")/../../lib.sh" || reject "lib.sh not found"
CUR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}; CUR=${CUR%/}
f=$CUR/projects/$(enc_path "$cwd")/$id.jsonl
ref=$(date +%s)
# The relay's proof in the source's own transcript: an interactive session (no bg turn) that went by the sender's name
# and sent this whole relay (SendMessage). It holds, running or stopped, so it goes first: the session listing it
# spares runs `claude agents` once per account, which took past the hook's 60 s on a loaded machine. The quote's age
# then counts to that send.
sent=
[ -z "$action" ] || [ ! -f "$f" ] || sent=$(jq -rn --arg rl "APPROVAL relayed from the user"$'\n'"Quote: $q"$'\n'"Action: $action"$'\n'"Source: $id $cwd" --arg n "$sender" "$quotes_def"'($rl | quotes) as $rl |
    reduce inputs as $e ({bg: false, named: false, at: null};
      if $e.sessionKind == "bg" then .bg = true
      elif $e.type == "agent-name" and $e.agentName == $n then .named = true
      elif $e.type == "assistant" and any($e.message.content[]?; .type == "tool_use" and .name == "SendMessage"
             and (.input.message? | strings | quotes | contains($rl))) then .at = $e.timestamp
      else . end)
    | if .bg then "bg" elif .named | not then "name" elif .at == null then "none"
      else .at | sub("\\.[0-9]+Z$"; "Z") | fromdate end' "$f") || sent=unreadable
# Only a send within MAX_AGE_H skips the listing: an older one verifies only from a stopped source (a running one counts
# the quote's age to now), so the listing decides.
if [[ $sent =~ ^[0-9]+$ ]] && [ "$sent" -ge $(( ref - max_age_h * 3600 )) ]; then ref=$sent
else
  IFS=$'\037' read -r _ s_name _ _ _ s_cwd s_kind _ <<<"$(list_sessions | awk -F'\t' -v id="$id" '$1 == id' | head -1 | tr '\t' '\037')"
  if [ -n "$s_name$s_cwd" ]; then
    # A successor coordinator relays as NAME-next until it takes NAME (session-status --successor's typed first prompt).
    [ "$s_name" = "$sender" ] || { [ "$sender" = "$s_name-next" ] && [ -f "$f" ] &&
      jq -rn 'first(inputs | select(.type == "user")) | select(.origin.kind == "human") | .message.content
        | if type == "string" then . else ([.[]? | .text? // empty] | join(" ")) end' "$f" 2>/dev/null |
        grep -qF "You succeed \"$s_name\" ("; } || reject "sender isn't the source session"
    [ "$s_kind" = interactive ] || reject "source session isn't interactive"
    [ "$s_cwd" = "$cwd" ] || reject "source cwd doesn't match the running session"
    [ -f "$f" ] || reject "no transcript for the source session"
  else
    [ -f "$f" ] || reject "source session isn't running, and has no transcript"
    case $sent in
      *[0-9]) ref=$sent ;;
      '') reject "source session isn't running: pass the relay's Action line to verify it by its transcript" ;;
      bg) reject "source session isn't running, and was a background session" ;;
      name) reject "source session isn't running, and its transcript never names it $sender" ;;
      none) reject "source session isn't running, and its transcript holds no relay of this quote and action" ;;
      *) reject "source transcript unreadable" ;;
    esac
  fi
fi
matches() { jq -r -n --arg q "$q" --arg key "$key" --argjson ref "$ref" --argjson maxage "$((max_age_h * 3600))" "$quotes_def"'
  def trim: gsub("^\\s+|\\s+$"; "");
  # The Desktop app adds <system-reminder> blocks (e.g. "Linked sessions now") to the message the user typed; a
  # relay may quote the message with them, as the coordinator saw it.
  def typed: gsub("\\s*<system-reminder>[\\s\\S]*?</system-reminder>\\s*"; "\n") | trim;
  ($q | quotes | typed) as $qn |
  def names_key: test("(^|[^A-Za-z0-9-])" + ($key | gsub("(?<c>[.*+?^${}()|\\[\\]\\\\/-])"; "\\\(.c)")) + "($|[^A-Za-z0-9-])");
  # A click in the coordinator pane: the prompt this plugin submits, and nothing else it might submit.
  def pane($o): $o.kind == "plugin" and $o.name == "session-orchestration";
  [foreach inputs as $e ({turn: "", asks: {}};
     ($e | if .type == "user" and (.origin.kind == "human" or pane(.origin)) then
             [.origin, (.message.content | if type == "string" then . else ([.[]? | .text? // empty] | join(" ")) end | typed)]
           elif .type == "attachment" and .attachment.type == "queued_command" and (.attachment.origin.kind == "human" or pane(.attachment.origin)) then
             [.attachment.origin, (.attachment.prompt | tostring | typed)]
           else [null, null] end
         # A row of reminders only is no message: it neither matches nor ends the turn a real answer answers.
         | if .[1] == "" then [null, null] else . end
         | if pane(.[0]) and (.[1] | startswith("Approval pane answer for ") | not) then [null, null] else . end) as [$o, $text]
     # The message a typed message answers: the assistant text of the turn just before it. A pane answer
     # carries its own question, so it answers nothing before it.
     | if $text != null then .cands = [{text: $text, answered: (if pane($o) then "" else .turn end), ts: $e.timestamp}] | .turn = ""
       # Another prompt from the pane (the Ask button of an item) ends the turn too: a later answer answers
       # what follows it.
       elif ($e.type == "user" and ($e.origin.kind == "peer" or pane($e.origin))) or
            ($e.type == "attachment" and $e.attachment.type == "queued_command" and pane($e.attachment.origin)) then .turn = "" | .cands = []
       elif $e.type == "assistant" and $e.isSidechain != true then
         .turn = ([.turn, ($e.message.content[]? | select(.type == "text") | .text)] | map(select(. != "")) | join("\n"))
         | reduce ($e.message.content[]? | select(.type == "tool_use" and .name == "AskUserQuestion") | .id) as $i (.; .asks[$i] = true)
         | .cands = []
       # A question-box answer: each question (with its header) is the message its answer (the clicked
       # label or "Other" text) answers. A note the user added to the answer goes into the output.
       elif $e.type == "user" and (.asks as $a | any($e.message.content[]?; $a[.tool_use_id? // ""] == true)) then
         ($e.toolUseResult | objects // {}) as $r
         | .cands = [$r.answers | objects | to_entries[] | .key as $qn
                     | {text: (.value | tostring), ts: $e.timestamp,
                        answered: ([first($r.questions[]? | select(.question == $qn) | .header // empty), $qn] | join(": ")),
                        note: ($r.annotations[$qn]?.notes? // "")}]
       else .cands = [] end;
     .cands[]
     | select(.text | contains("<pasted_content") | not)
     | select((.ts | sub("\\.[0-9]+Z$"; "Z") | fromdate) >= ($ref - $maxage))
     | select((.text | quotes | trim) == $qn)
     | (if (.note // "") != "" then ", with the user'"'"'s note: \(.note | gsub("\\s+"; " "))" else "" end) as $note
     | if .text | names_key then "verified\($note)"
       elif .answered | names_key then "verified, answering: \(.answered | gsub("\\s+"; " ") | .[-300:])\($note)"
       else empty end)] | last // empty' "$1"; }
# A successor coordinator (its typed first prompt `You succeed "NAME" (ID8)`, from session-status --successor) relays
# what the user told the coordinator it took over from: that one's transcript counts too, back along the chain, while
# it was written to within the quote's age window. Each must have been interactive (no bg turn) and gone by NAME
# (lib.sh chain_transcripts).
r=
# The break leaves the chain unread: its next echo hits a closed pipe, which is no error here.
while IFS= read -r t; do r=$(matches "$t"); [ -z "$r" ] || break
done < <(chain_transcripts "$f" $(( ($(date +%s) - ref + max_age_h * 3600) / 60 + 1 )) 2>/dev/null)
[ -n "$r" ] || reject "no recent message typed by the user, question-box answer or pane click matches the whole quote and names $key in it or in the message it answers"
echo "$r"
# A command this session also handed the user for this task (hand_command) is still runnable from the pane: doing the
# approved action and pressing Run would do it twice. Name each, with how to withdraw it.
[ -z "${CLAUDE_CODE_SESSION_ID:-}" ] || for c in "$HOME/.cache/session-status/commands/"*.json; do
  [ -f "$c" ] || continue
  jq -r --arg s "$CLAUDE_CODE_SESSION_ID" --arg k "$key" 'select(.session == $s and .key == $k)
    | "you also handed the user this command for \($k): \(.command)\nif the approved action is the same, withdraw it before you act: hand_command with this key and command and withdraw: true"' "$c" 2>/dev/null
done
exit 0

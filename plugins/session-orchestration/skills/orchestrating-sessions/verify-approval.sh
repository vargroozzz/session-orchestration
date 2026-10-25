#!/usr/bin/env bash
# Verify a relayed approval. Prints "verified" (exit 0) or "rejected: <reason>" (exit 1). When the
# key is only in the message the quote answers, it prints "verified, answering: <its last 300 chars>". A note
# the user added to a question-box answer is appended as ", with the user's note: <note>". The newest match wins.
# Usage: bash verify-approval.sh <source-sessionId> <source-cwd> <sender-name> <task-key> <<'EOF'
#        <the quote, exactly as relayed>
#        EOF
# The quote comes on stdin and is only ever handled as data (jq --arg), never by the shell.
# Checks:
#  1. sessionId is a UUID, and cwd is this project (equal to, inside, or containing $PWD).
#  2. The sender (the message's from-name) is that session, running and interactive, under this session's account
#     (config dir), or with features.accounts on any account sharing its transcript store. A session a
#     coordinator started with `claude --bg` can't be a source, since its first prompt wasn't typed.
#  3. In that session's transcript, one message the user typed (origin human, no pasted content)
#     matches the quote as a whole and is at most MAX_AGE_H hours old (default 24). The task key is in
#     the quote, or in the coordinator's last text before it (the message the user was answering).
#     An answer the user gave in the coordinator's question box (AskUserQuestion: the option label they
#     clicked, or their "Other" text) counts the same way, with the question as the message answered.
#     So does a click in the coordinator pane (hooks/register.tsx): the prompt it submits, a user row whose
#     origin is this plugin and which starts "Approval pane answer for ", names the key and question itself.
#     The engine sets that origin from the calling plugin, so no other plugin can produce one, and a worker
#     only writes rows into its own session.
set -uo pipefail
id=${1:-}; cwd=${2:-}; sender=${3:-}; key=${4:-}; q=$(cat)
max_age_h=${MAX_AGE_H:-24}
reject() { echo "rejected: $1"; exit 1; }

[[ $id =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || reject "sessionId is not a UUID"
[ -n "$key" ] && [ -n "$sender" ] && [ -n "$q" ] || reject "missing sender, task key or quote"
case "$PWD/" in "$cwd"/*) ;; *) case "$cwd/" in "$PWD"/*) ;; *) reject "source cwd is outside this project" ;; esac ;; esac

# The source session among the accounts session-status asks (lib.sh's list_sessions: with features.accounts on,
# a coordinator under ~/.claude is found by a worker under CLAUDE_CONFIG_DIR=~/.claude-work).
. "$(dirname "$0")/../../lib.sh" || reject "lib.sh not found"
CUR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}; CUR=${CUR%/}
IFS=$'\037' read -r _ s_name _ _ _ s_cwd s_kind _ <<<"$(list_sessions | awk -F'\t' -v id="$id" '$1 == id' | head -1 | tr '\t' '\037')"
[ -n "$s_name$s_cwd" ] || reject "source session isn't running"
[ "$s_name" = "$sender" ] || reject "sender isn't the source session"
[ "$s_kind" = interactive ] || reject "source session isn't interactive"
[ "$s_cwd" = "$cwd" ] || reject "source cwd doesn't match the running session"

f=$CUR/projects/$(printf '%s' "$cwd" | sed 's/[^A-Za-z0-9]/-/g')/$id.jsonl
[ -f "$f" ] || reject "no transcript for the source session"
r=$(jq -r -n --arg q "$q" --arg key "$key" --argjson maxage "$((max_age_h * 3600))" '
  def trim: gsub("^\\s+|\\s+$"; "");
  def names_key: test("(^|[^A-Za-z0-9-])" + ($key | gsub("(?<c>[.*+?^${}()|\\[\\]\\\\/-])"; "\\\(.c)")) + "($|[^A-Za-z0-9])");
  # A click in the coordinator pane: the prompt this plugin submits, and nothing else it might submit.
  def pane($o): $o.kind == "plugin" and $o.name == "session-orchestration";
  [foreach inputs as $e ({turn: "", asks: {}};
     ($e | if .type == "user" and (.origin.kind == "human" or pane(.origin)) then
             [.origin, (.message.content | if type == "string" then . else ([.[]? | .text? // empty] | join(" ")) end)]
           elif .type == "attachment" and .attachment.type == "queued_command" and (.attachment.origin.kind == "human" or pane(.attachment.origin)) then
             [.attachment.origin, (.attachment.prompt | tostring)]
           else [null, null] end
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
     | select((.ts | sub("\\.[0-9]+Z$"; "Z") | fromdate) >= (now - $maxage))
     | select((.text | trim) == ($q | trim))
     | (if (.note // "") != "" then ", with the user'"'"'s note: \(.note | gsub("\\s+"; " "))" else "" end) as $note
     | if .text | names_key then "verified\($note)"
       elif .answered | names_key then "verified, answering: \(.answered | gsub("\\s+"; " ") | .[-300:])\($note)"
       else empty end)] | last // empty' "$f")
[ -n "$r" ] || reject "no recent message typed by the user, question-box answer or pane click matches the whole quote and names $key in it or in the message it answers"
echo "$r"

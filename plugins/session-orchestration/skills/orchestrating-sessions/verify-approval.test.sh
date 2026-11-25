#!/usr/bin/env bash
# Self-check for verify-approval.sh: a fake coordinator transcript with a typed approval and question-box
# (AskUserQuestion) answers, and a stubbed `claude agents`. Run: bash verify-approval.test.sh  (prints "ok" or the failure).
set -euo pipefail; unset XDG_CONFIG_HOME XDG_STATE_HOME   # the person-wide config.json: never the real one
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
root=$(mkdir -p "$tmp/proj" && cd "$tmp/proj" && pwd -P)
cid=99999999-2222-3333-4444-555555555555
# Accounts: the default config dir and ~/.claude-work share one transcript store; ~/.claude-other has its own.
home=$tmp/home; proj=$home/.claude/projects/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$root")
mkdir -p "$proj" "$tmp/bin" "$home/.claude-work" "$home/.claude-other/projects"
ln -s "$home/.claude/projects" "$home/.claude-work/projects"
now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z) old=2020-01-01T00:00:00.000Z

ask() { # $1 tool_use id, $2 question, $3 answer, $4 timestamp, $5 sidechain
  jq -nc --arg id "$1" --arg q "$2" --argjson sc "${5:-false}" \
    '{type: "assistant", isSidechain: $sc, message: {content: [{type: "tool_use", id: $id, name: "AskUserQuestion",
      input: {questions: [{question: $q, options: [{label: "Yes"}, {label: "No"}]}]}}]}}'
  jq -nc --arg id "$1" --arg q "$2" --arg a "$3" --arg ts "$4" --argjson sc "${5:-false}" \
    '{type: "user", isSidechain: $sc, timestamp: $ts, toolUseResult: {answers: {($q): $a}},
      message: {content: [{type: "tool_result", tool_use_id: $id, content: "answered"}]}}'
}
{
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Merge ABC-1?"}]}}'
  jq -nc --arg ts "$now" '{type: "user", origin: {kind: "human"}, timestamp: $ts, message: {content: "yes"}}'
  ask t1 "Patch config?" "Yes, patch the ABC-2 config and restart fe" "$now"
  ask t2 "Restart ABC-3 pods?" "Yes" "$now"
  ask t3 "Deploy ABC-4?" "Yes, deploy ABC-4" "$old"
  ask t4 "Rebase?" "Sure, rebase it" "$now"
  ask t5 "Push ABC-6?" "Yes, push ABC-6" "$now" true
  # Two questions in one box: one with a header naming the key, the other answered with "Other" text and a note.
  jq -nc '{type: "assistant", message: {content: [{type: "tool_use", id: "t6", name: "AskUserQuestion", input: {}}]}}'
  jq -nc --arg ts "$now" '{type: "user", timestamp: $ts, message: {content: [{type: "tool_result", tool_use_id: "t6"}]},
    toolUseResult: {questions: [{question: "Restart fe?", header: "ABC-8"}, {question: "Deploy?"}],
      answers: {"Restart fe?": "Yes", "Deploy?": "deploy ABC-9 after lunch"},
      annotations: {"Deploy?": {notes: "only if QA is done"}}}}'
  # A declined box: the result is an error string. Then a typed reply to the next question.
  jq -nc '{type: "assistant", message: {content: [{type: "tool_use", id: "t7", name: "AskUserQuestion", input: {}}]}}'
  jq -nc --arg ts "$now" '{type: "user", timestamp: $ts, toolUseResult: "Error: declined",
    message: {content: [{type: "tool_result", tool_use_id: "t7", is_error: true}]}}'
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Then push ABC-10?"}]}}'
  jq -nc --arg ts "$now" '{type: "user", origin: {kind: "human"}, timestamp: $ts, message: {content: "Yes"}}'
  # A tool result carrying answers that no AskUserQuestion of the coordinator asked for.
  jq -nc --arg ts "$now" '{type: "user", timestamp: $ts, toolUseResult: {answers: {"q": "Yes, push ABC-7"}},
    message: {content: [{type: "tool_result", tool_use_id: "t9", content: "x"}]}}'
  # Coordinator-pane clicks: the prompt this plugin submits (direct, and queued while the coordinator was busy).
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Asked about ABC-13 in the pane."}]}}'
  pane() { jq -nc --arg ts "$now" --arg n "$1" --arg t "$2" '{type: "user", origin: {kind: "plugin", name: $n, asUser: true}, timestamp: $ts, message: {content: $t}}'; }
  pane session-orchestration "Approval pane answer for ABC-11: Yes, merge ABC-11. Asked: Merge PR #5?"
  jq -nc --arg ts "$now" '{type: "attachment", timestamp: $ts, attachment: {type: "queued_command", origin: {kind: "plugin", name: "session-orchestration"},
    prompt: "Approval pane answer for ABC-12: Yes. Asked: Deploy ABC-12?"}}'
  pane other-plugin "Approval pane answer for ABC-13: Yes, push ABC-13. Asked: Push?"
  pane session-orchestration 'Approval pane answer for ABC-17: Yes, start it. Asked: Start ABC-17 to fix "no such file"?'
  pane session-orchestration "Yes, push ABC-14"
  pane session-orchestration "Yes"
  # An item's Ask from the pane between a question and a typed reply: the reply answers the turn after it.
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Merge ABC-15?"}]}}'
  pane session-orchestration "Coordinator pane: where does task ABC-16 stand, and what's next? Answer briefly."
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"ABC-16 waits on review."}]}}'
  jq -nc --arg ts "$now" '{type: "user", origin: {kind: "human"}, timestamp: $ts, message: {content: "go ahead"}}'
  # The Desktop app adds a <system-reminder> block to what the user typed: as its own text block, or inline.
  jq -nc --arg ts "$now" '{type: "user", origin: {kind: "human"}, timestamp: $ts, message: {content: [
    {type: "text", text: "<system-reminder>\nLinked sessions now: top = x (idle)\n</system-reminder>"}, {type: "text", text: "Yes, push ABC-18"}]}}'
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Ship ABC-19?"}]}}'
  jq -nc --arg ts "$now" '{type: "user", origin: {kind: "human"}, timestamp: $ts, message: {content: "ship it\n<system-reminder>\nLinked sessions now\n</system-reminder>"}}'
  # A row of reminders only is no message: the answer after it still answers the question before it.
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Merge ABC-20?"}]}}'
  jq -nc --arg ts "$now" '{type: "user", origin: {kind: "human"}, timestamp: $ts, message: {content: "<system-reminder>\nLinked sessions now\n</system-reminder>"}}'
  jq -nc --arg ts "$now" '{type: "user", origin: {kind: "human"}, timestamp: $ts, message: {content: "merge"}}'
  # Queued while the coordinator was busy, with a reminder in the middle.
  jq -nc --arg ts "$now" '{type: "attachment", timestamp: $ts, attachment: {type: "queued_command", origin: {kind: "human"},
    prompt: "Yes, deploy\n<system-reminder>\nLinked sessions now\n</system-reminder>\nABC-21"}}'
} > "$proj/$cid.jsonl"
# `claude agents --json` lists its own account's sessions only; the coordinator's account is in $tmp/coord.
# features.accounts is on (the person file), so every account sharing the transcript store is asked.
echo "$home/.claude" > "$tmp/coord"
mkdir -p "$root/.claude" && echo '{"features":{"accounts":true}}' > "$root/.claude/coordination.local.json"
printf '#!/bin/sh\n[ "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" = "$(cat %s)" ] && echo %s || echo []\n' "'$tmp/coord'" \
  "'[{\"sessionId\":\"$cid\",\"name\":\"coord\",\"cwd\":\"$root\",\"kind\":\"interactive\"}]'" > "$tmp/bin/claude"
chmod +x "$tmp/bin/claude"

v() { (cd "$root" && HOME=$home CLAUDE_CONFIG_DIR=${CFG:-$home/.claude-work} PATH=$tmp/bin:$PATH bash "$here/verify-approval.sh" "$cid" "$root" coord "$1" "${ACT-x (ABC-1)}" <<<"$2") || true; }
check() { [ "$(v "$1" "$2")" = "$3" ] || { echo "FAIL $1 '$2': got '$(v "$1" "$2")', want '$3'"; exit 1; }; }
no="rejected: no recent message typed by the user, question-box answer or pane click matches the whole quote and names"

check ABC-1 yes "verified, answering: Merge ABC-1?"                           # typed reply, key in the question
check ABC-2 "Yes, patch the ABC-2 config and restart fe" verified             # clicked label names the key
check ABC-3 Yes "verified, answering: Restart ABC-3 pods?"                    # key only in the question
check ABC-2 "Yes, patch the ABC-2 config" "$no ABC-2 in it or in the message it answers"  # wrong label
check ABC-5 "Sure, rebase it" "$no ABC-5 in it or in the message it answers"  # key nowhere
check ABC-4 "Yes, deploy ABC-4" "$no ABC-4 in it or in the message it answers"  # stale
check ABC-6 "Yes, push ABC-6" "$no ABC-6 in it or in the message it answers"  # subagent's question box
check ABC-7 "Yes, push ABC-7" "$no ABC-7 in it or in the message it answers"  # no matching AskUserQuestion
check ABC-8 Yes "verified, answering: ABC-8: Restart fe?"                    # key in the header; newest "Yes" wins
check ABC-9 "deploy ABC-9 after lunch" "verified, with the user's note: only if QA is done"  # "Other" text + note
check ABC-10 Yes "verified, answering: Then push ABC-10?"                     # typed after a declined box
check ABC-11 "Approval pane answer for ABC-11: Yes, merge ABC-11. Asked: Merge PR #5?" verified  # pane click
check ABC-12 "Approval pane answer for ABC-12: Yes. Asked: Deploy ABC-12?" verified  # pane click, queued
check ABC-17 'Approval pane answer for ABC-17: Yes, start it. Asked: Start ABC-17 to fix "no such file"?' verified  # double quotes
check ABC-17 'Approval pane answer for ABC-17: Yes, start it. Asked: Start ABC-17 to fix \"no such file\"?' verified  # quotes escaped in the relay
check ABC-17 'Approval pane answer for ABC-17: Yes, start it. Asked: Start ABC-17 to fix “no such file”?' verified  # quotes curled in the relay
check ABC-17 'Approval pane answer for ABC-17: Yes, start it. Asked: Start ABC-17 to fix “no such dir”?' "$no ABC-17 in it or in the message it answers"  # other words still fail
check ABC-13 "Approval pane answer for ABC-13: Yes, push ABC-13. Asked: Push?" "$no ABC-13 in it or in the message it answers"  # another plugin
check ABC-14 "Yes, push ABC-14" "$no ABC-14 in it or in the message it answers"  # this plugin, but not a pane answer
check ABC-13 "Approval pane answer for ABC-11: Yes, merge ABC-11. Asked: Merge PR #5?" "$no ABC-13 in it or in the message it answers"  # a pane row answers no message before it
check ABC-15 "go ahead" "$no ABC-15 in it or in the message it answers"     # an Ask came between
check ABC-16 "go ahead" "verified, answering: ABC-16 waits on review."
check ABC-18 "Yes, push ABC-18" verified                                     # Desktop app reminder block
check ABC-19 "ship it" "verified, answering: Ship ABC-19?"                     # inline reminder
check ABC-18 "Linked sessions now" "$no ABC-18 in it or in the message it answers"  # reminder text isn't typed text
check ABC-18 $'Yes, push ABC-18\n<system-reminder>\nLinked sessions now: top = x (idle)\n</system-reminder>' verified  # quoted as the coordinator saw it
check ABC-20 "merge" "verified, answering: Merge ABC-20?"                      # a reminder-only row between
check ABC-20 " " "$no ABC-20 in it or in the message it answers"               # a blank quote matches no reminder-only row
check ABC-21 $'Yes, deploy\nABC-21' verified                                   # queued, reminder in the middle
CFG=$home/.claude check ABC-1 yes "verified, answering: Merge ABC-1?"           # (above: worker under ~/.claude-work) same account
echo "$home/.claude-work" > "$tmp/coord"
CFG=$home/.claude check ABC-1 yes "verified, answering: Merge ABC-1?"           # coordinator under ~/.claude-work
echo "$home/.claude-other" > "$tmp/coord"
stopped="rejected: source session isn't running, and"
check ABC-1 yes "$stopped its transcript never names it coord"                 # an account with its own transcript store
# A coordinator that stopped after relaying: its transcript names it and holds the relay it sent; the quote's age
# counts to that send (ABC-4's answer is from 2020, relayed then).
relay() { jq -nc --arg ts "$1" --arg q "$2" --arg src "$cid $root" '{type: "assistant", timestamp: $ts, message: {content: [{type: "tool_use", name: "SendMessage",
  input: {to: "w", message: "APPROVAL relayed from the user\nQuote: \($q)\nAction: x (ABC-1)\nSource: \($src)"}}]}}'; }
cp "$proj/$cid.jsonl" "$tmp/t.jsonl"
{ echo '{"type":"agent-name","agentName":"coord"}'; relay "$now" yes; relay "$old" "Yes, deploy ABC-4"; } >> "$proj/$cid.jsonl"
check ABC-1 yes "verified, answering: Merge ABC-1?"
check ABC-4 "Yes, deploy ABC-4" verified
# Running (listed in the worker's account): a fresh relay verifies by its transcript alone, without listing the sessions
# (`claude agents` per account took past the hook's 60 s on a loaded machine); an old one lists them and, its source
# running, counts the quote's age to now.
echo "$home/.claude-work" > "$tmp/coord"; mv "$tmp/bin/claude" "$tmp/claude.real"
printf '#!/bin/sh\ntouch %s\nexec %s "$@"\n' "'$tmp/listed'" "'$tmp/claude.real'" > "$tmp/bin/claude"; chmod +x "$tmp/bin/claude"
check ABC-1 yes "verified, answering: Merge ABC-1?"
[ ! -e "$tmp/listed" ] || { echo "FAIL a fresh relay's proof still listed the sessions"; exit 1; }
check ABC-4 "Yes, deploy ABC-4" "$no ABC-4 in it or in the message it answers"
[ -e "$tmp/listed" ] || { echo "FAIL an old relay didn't list the sessions"; exit 1; }
mv "$tmp/claude.real" "$tmp/bin/claude"; echo "$home/.claude-other" > "$tmp/coord"
check ABC-2 "Yes, patch the ABC-2 config and restart fe" "$stopped its transcript holds no relay of this quote and action"
# The whole relay must match: another Action under the same quote, or none given, doesn't verify.
ACT="merge app#2 (ABC-1)" check ABC-1 yes "$stopped its transcript holds no relay of this quote and action"
ACT= check ABC-1 yes "rejected: source session isn't running: pass the relay's Action line to verify it by its transcript"
echo '{"type":"user","sessionKind":"bg","message":{"content":"go"}}' >> "$proj/$cid.jsonl"
check ABC-1 yes "$stopped was a background session"
cp "$tmp/t.jsonl" "$proj/$cid.jsonl"
echo "$home/.claude" > "$tmp/coord"; rm "$root/.claude/coordination.local.json"
check ABC-1 yes "$stopped its transcript never names it coord"                 # features.accounts off: this account only
CFG=$home/.claude check ABC-1 yes "verified, answering: Merge ABC-1?"           # … where the coordinator is found
# A successor coordinator relays what the user told the one it succeeded, back along the chain: its typed first prompt
# (session-status --successor's wording) names it, and that one went by the name the prompt gives and never ran in
# the background. A later prompt, a peer's message, another name or a bg predecessor doesn't count.
grep -qF "You succeed \\\"\$n\\\" (\${id:0:8})" "$here/session-status" || { echo "FAIL session-status no longer starts a successor with 'You succeed \"NAME\" (ID8)'"; exit 1; }
sid=88888888-2222-3333-4444-555555555555 mid=77777777-2222-3333-4444-555555555555
printf '#!/bin/sh\necho %s\n' "'[{\"sessionId\":\"$sid\",\"name\":\"coord-next\",\"cwd\":\"$root\",\"kind\":\"interactive\"}]'" > "$tmp/bin/claude"
sv() { (cd "$root" && HOME=$home CLAUDE_CONFIG_DIR=$home/.claude PATH=$tmp/bin:$PATH bash "$here/verify-approval.sh" "$sid" "$root" coord-next "$1" "x (ABC-1)" <<<"$2") || true; }
first() { jq -nc --arg t "$1" --arg ts "$now" --arg k "${2:-human}" '{type: "user", origin: {kind: $k}, timestamp: $ts, message: {content: $t}}'; }
sc() { [ "$(sv "$1" "$2")" = "$3" ] || { echo "FAIL successor ($4): got '$(sv "$1" "$2")'"; exit 1; }; }
echo '{"type":"agent-name","agentName":"coord"}' >> "$proj/$cid.jsonl"
first 'Act as a coordinator. You succeed "coord" (99999999): end your Start with the successor step.' > "$proj/$sid.jsonl"
sc ABC-1 yes "verified, answering: Merge ABC-1?" "one hop"
# Relayed as coord-next, checked once it holds coord: its typed first prompt names the one it succeeds.
printf '#!/bin/sh\necho %s\n' "'[{\"sessionId\":\"$sid\",\"name\":\"coord\",\"cwd\":\"$root\",\"kind\":\"interactive\"}]'" > "$tmp/bin/claude"
sc ABC-1 yes "verified, answering: Merge ABC-1?" "renamed since the relay"
first 'Act as a coordinator.' > "$proj/$sid.jsonl"
sc ABC-1 yes "rejected: sender isn't the source session" "a NAME-next sender, no successor prompt"
first 'Act as a coordinator. You succeed "coord" (99999999): end your Start with the successor step.' > "$proj/$sid.jsonl"
printf '#!/bin/sh\necho %s\n' "'[{\"sessionId\":\"$sid\",\"name\":\"coord-next\",\"cwd\":\"$root\",\"kind\":\"interactive\"}]'" > "$tmp/bin/claude"
sc ABC-4 "Yes, deploy ABC-4" "$no ABC-4 in it or in the message it answers" "stale"
{ first 'Act as a coordinator. You succeed "coord" (99999999).'; echo '{"type":"agent-name","agentName":"coord"}'; } > "$proj/$mid.jsonl"
first 'Act as a coordinator. You succeed "coord" (77777777).' > "$proj/$sid.jsonl"
sc ABC-1 yes "verified, answering: Merge ABC-1?" "two hops"
first 'Act as a coordinator. You succeed "other" (99999999).' > "$proj/$sid.jsonl"
sc ABC-1 yes "$no ABC-1 in it or in the message it answers" "another name"
{ first 'Look around'; first 'You succeed "coord" (99999999)'; } > "$proj/$sid.jsonl"
sc ABC-1 yes "$no ABC-1 in it or in the message it answers" "later prompt"
first 'You succeed "coord" (99999999)' peer > "$proj/$sid.jsonl"
sc ABC-1 yes "$no ABC-1 in it or in the message it answers" "peer message"
first 'Act as a coordinator. You succeed "coord" (99999999).' > "$proj/$sid.jsonl"
echo '{"type":"user","sessionKind":"bg","message":{"content":"go"}}' >> "$proj/$cid.jsonl"
sc ABC-1 yes "$no ABC-1 in it or in the message it answers" "bg predecessor"
cp "$tmp/t.jsonl" "$proj/$cid.jsonl"; rm "$proj/$sid.jsonl" "$proj/$mid.jsonl"
printf '#!/bin/sh\n[ "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" = "$(cat %s)" ] && echo %s || echo []\n' "'$tmp/coord'" \
  "'[{\"sessionId\":\"$cid\",\"name\":\"coord\",\"cwd\":\"$root\",\"kind\":\"interactive\"}]'" > "$tmp/bin/claude"
# A command this session handed over for the same key is named with how to withdraw it; another session's or key's isn't.
hd=$home/.cache/session-status/commands; mkdir -p "$hd"
echo '{"session":"w1","key":"ABC-1","command":"teams-send a.txt"}' > "$hd/1.json"
echo '{"session":"w2","key":"ABC-1","command":"echo other"}' > "$hd/2.json"
echo '{"session":"w1","key":"ABC-2","command":"echo key"}' > "$hd/3.json"
[ "$(CLAUDE_CODE_SESSION_ID=w1 CFG=$home/.claude v ABC-1 yes)" = "$(printf 'verified, answering: Merge ABC-1?\nyou also handed the user this command for ABC-1: teams-send a.txt\nif the approved action is the same, withdraw it before you act: hand_command with this key and command and withdraw: true')" ] ||
  { echo "FAIL handed command not named: $(CLAUDE_CODE_SESSION_ID=w1 CFG=$home/.claude v ABC-1 yes)"; exit 1; }
echo ok

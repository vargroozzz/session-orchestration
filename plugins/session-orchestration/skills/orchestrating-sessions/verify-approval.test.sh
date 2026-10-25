#!/usr/bin/env bash
# Self-check for verify-approval.sh: a fake coordinator transcript with a typed approval and question-box
# (AskUserQuestion) answers, and a stubbed `claude agents`. Run: bash verify-approval.test.sh  (prints "ok" or the failure).
set -euo pipefail
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
  pane session-orchestration "Yes, push ABC-14"
  pane session-orchestration "Yes"
  # An item's Ask from the pane between a question and a typed reply: the reply answers the turn after it.
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Merge ABC-15?"}]}}'
  pane session-orchestration "Coordinator pane: where does task ABC-16 stand, and what's next? Answer briefly."
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"ABC-16 waits on review."}]}}'
  jq -nc --arg ts "$now" '{type: "user", origin: {kind: "human"}, timestamp: $ts, message: {content: "go ahead"}}'
} > "$proj/$cid.jsonl"
# `claude agents --json` lists its own account's sessions only; the coordinator's account is in $tmp/coord.
# features.accounts is on (the person file), so every account sharing the transcript store is asked.
echo "$home/.claude" > "$tmp/coord"
mkdir -p "$root/.claude" && echo '{"features":{"accounts":true}}' > "$root/.claude/coordination.local.json"
printf '#!/bin/sh\n[ "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" = "$(cat %s)" ] && echo %s || echo []\n' "'$tmp/coord'" \
  "'[{\"sessionId\":\"$cid\",\"name\":\"coord\",\"cwd\":\"$root\",\"kind\":\"interactive\"}]'" > "$tmp/bin/claude"
chmod +x "$tmp/bin/claude"

v() { (cd "$root" && HOME=$home CLAUDE_CONFIG_DIR=${CFG:-$home/.claude-work} PATH=$tmp/bin:$PATH bash "$here/verify-approval.sh" "$cid" "$root" coord "$1" <<<"$2") || true; }
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
check ABC-13 "Approval pane answer for ABC-13: Yes, push ABC-13. Asked: Push?" "$no ABC-13 in it or in the message it answers"  # another plugin
check ABC-14 "Yes, push ABC-14" "$no ABC-14 in it or in the message it answers"  # this plugin, but not a pane answer
check ABC-13 "Approval pane answer for ABC-11: Yes, merge ABC-11. Asked: Merge PR #5?" "$no ABC-13 in it or in the message it answers"  # a pane row answers no message before it
check ABC-15 "go ahead" "$no ABC-15 in it or in the message it answers"     # an Ask came between
check ABC-16 "go ahead" "verified, answering: ABC-16 waits on review."
CFG=$home/.claude check ABC-1 yes "verified, answering: Merge ABC-1?"           # (above: worker under ~/.claude-work) same account
echo "$home/.claude-work" > "$tmp/coord"
CFG=$home/.claude check ABC-1 yes "verified, answering: Merge ABC-1?"           # coordinator under ~/.claude-work
echo "$home/.claude-other" > "$tmp/coord"
check ABC-1 yes "rejected: source session isn't running"                      # an account with its own transcript store
echo "$home/.claude" > "$tmp/coord"; rm "$root/.claude/coordination.local.json"
check ABC-1 yes "rejected: source session isn't running"                      # features.accounts off: this account only
CFG=$home/.claude check ABC-1 yes "verified, answering: Merge ABC-1?"           # … where the coordinator is found
echo ok

#!/usr/bin/env bash
# Self-check for messages/msgraph.sh: a stubbed Graph CLI and `claude` (the triage), a temp HOME and project.
# Covers each rule (DM, mention with a PR link, A, B, C, mail drop/keep/triage), the OOO accept, `mine`, and a
# second run answering from the triage cache. Run: bash msgraph.test.sh  (prints "ok" or what failed).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; trap 'echo "failed at line $LINENO: $BASH_COMMAND" >&2' ERR
F=$tmp/f; mkdir -p "$F" "$tmp/bin" "$tmp/proj/.claude"
. "$here/../lib.sh"
iso() { TZ=UTC epochfmt $(( $(date +%s) - $1 * 60 )) %FT%T.123Z; }   # iso MINUTES_AGO

cat > "$tmp/proj/.claude/coordination.local.json" <<EOF
{"messages": "msgraph", "msgraph": {"cli": "$tmp/bin/graph", "team": "Ops", "domain": "ex.org", "accept_ooo_invites": true,
  "chats": [{"id": "sup", "name": "Support", "rule": "support"}, {"id": "q", "name": "Questions", "devs": true},
            {"id": "team", "name": "Team", "rule": "team"}],
  "mail": {"drop": [{"from": "^alerts@noise\\\\.io$"}, {"from": "^bot@ex\\\\.org$", "unless_preview": "commented on"}],
           "keep_from": ["acc@books.io"]}}}
EOF
msg() { printf '{"id":"%s","messageType":"message","from":{"user":{"id":"%s","displayName":"%s"}},"body":{"content":"%s"},"createdDateTime":"%s"}' "$@"; }
chat() { printf '{"id":"%s","chatType":"%s","topic":%s,"viewpoint":{"lastMessageReadDateTime":"%s"},"lastMessagePreview":{"id":"%s","from":{"user":{"id":"%s","displayName":"%s"}},"body":{"content":"%s"},"createdDateTime":"%s"}}' "$@"; }
echo "{\"value\":[$(chat dm1 oneOnOne null "$(iso 60)" m1 u-ann Ann 'hi about PROJ-7' "$(iso 10)"),
  $(chat q group '"Questions"' "$(iso 60)" q1 u-x Xi x "$(iso 10)"), $(chat team group '"Team"' "$(iso 60)" t1 u-tm Tim x "$(iso 10)"),
  $(chat sup group '"Support"' "$(iso 0)" s1 u-cu Cu x "$(iso 120)"), $(chat g group '"General"' "$(iso 60)" x1 u-bob Bob x "$(iso 10)")]}" > "$F/chats"
echo "{\"value\":[$(msg q1 u-x Xi 'Ops, can someone look?' "$(iso 10)")]}" > "$F/q"
echo "{\"value\":[$(msg t1 u-tm Tim 'deploy done' "$(iso 10)")]}" > "$F/team"
echo "{\"value\":[$(msg s0 u-cu Cu hello "$(iso 300)"), $(msg s1 u-cu Cu 'could you check PROJ-3?' "$(iso 120)")]}" > "$F/sup"
echo "{\"results\":[{\"id\":\"x1\",\"chatId\":\"g\",\"from\":\"bob@ex.org\",\"content\":\"@Max see\",\"createdDateTime\":\"$(iso 10)\"}]}" > "$F/mentions"
echo '{"id":"x1","body":{"content":"@Max see <a href=\"https://h/p/repos/app/pull-requests/5\">PR</a>"},"from":{"user":{"displayName":"Bob"}}}' > "$F/x1"
mail() { printf '{"id":"%s","isRead":false,"receivedDateTime":"%s","from":{"emailAddress":{"address":"%s","name":"%s"}},"subject":"%s","bodyPreview":"%s"}' "$@"; }
echo "{\"values\":[$(mail a1 "$(iso 60)" alerts@noise.io Noise x x), $(mail a2 "$(iso 60)" acc@books.io Acc Invoice x),
  $(mail a3 "$(iso 60)" pat@ex.org Pat 'OOO Friday' x), $(mail a4 "$(iso 60)" lee@other.io Lee 'Question on PROJ-7' x),
  $(mail a5 "$(iso 60)" bot@ex.org Bot 'status' 'Kim changed it'), $(mail a6 "$(iso 60)" me@ex.org Me mine x)]}" > "$F/mail"
echo '{"value":[{"id":"ev1","isOrganizer":false,"responseStatus":{"response":"notResponded"},"organizer":{"emailAddress":{"address":"Pat@ex.org"}},"subject":"OOO Friday"},
  {"id":"ev2","isOrganizer":false,"responseStatus":{"response":"notResponded"},"organizer":{"emailAddress":{"address":"x@else.io"}},"subject":"OOO"}]}' > "$F/events"

cat > "$tmp/bin/graph" <<EOF
#!/bin/sh
case "\$1" in
  status) echo '{"user":{"id":"u-me","mail":"me@ex.org","displayName":"Max Power"}}' ;;
  chat) [ "\$3" = team ] && echo '{"members":[{"userId":"u-me"},{"userId":"u-tm"}]}' || echo '{"members":[{"userId":"u-dev"}]}' ;;
  message) cat $F/mentions ;;
  mail) cat $F/mail ;;
  calendar) echo "\$3" >> $F/accepted ;;
  raw) case "\$4" in /me/chats*) cat $F/chats ;; /me/events*) cat $F/events ;; /chats/g/messages/x1) cat $F/x1 ;;
         /chats/*) p=\${4#/chats/}; cat "$F/\${p%%/*}" ;; esac ;;
esac
EOF
# The triage: action for the first and third messages it's asked about, not the second.
cat > "$tmp/bin/claude" <<EOF
#!/bin/sh
cat > $F/prompt; echo 1 >> $F/calls
echo '[{"n":1,"action":true,"to":"team","ticket":null,"why":"asks the team"},{"n":2,"action":false,"to":"team","ticket":null,"why":"fyi"},{"n":3,"action":true,"to":"me","ticket":"PROJ-7","why":"asks about PROJ-7"}]'
EOF
chmod +x "$tmp/bin/graph" "$tmp/bin/claude"
adapter() { case $1 in urls) echo 'pr https://h/p/repos/{repo}/pull-requests/{id}' ;; pr-keys) [ "$2" = app#5 ] && echo PROJ-9 ;; *) return 2 ;; esac; }
. "$here/msgraph.sh"
printf 'PROJ-7    In Progress  | Fix login\nPROJ-9    In Review    | Speed up\n' > "$tmp/rows"; printf 'PROJ-9\nPROJ-7\n' > "$tmp/mine"
run() { (cd "$tmp/proj" && HOME=$tmp PATH=$tmp/bin:$PATH NOTICE_DIR=$tmp/cache NOTICE_KEYRE='(PROJ-[0-9]+)' NOTICE_ROWS=$tmp/rows NOTICE_MINE=$tmp/mine messages_notices); }

want='teams DM  Ann: hi about PROJ-7 [PROJ-7]
teams @   General · bob: @Max see [PROJ-9]
teams ?   Support · Cu: could you check PROJ-3? [PROJ-3]
teams ?   Questions · Xi: Ops, can someone look? — asks the team
mail      Acc: Invoice
mail      Lee: Question on PROJ-7 [PROJ-7] — asks about PROJ-7'
out=$(run); [ "$out" = "$want" ] || { echo "lines differ:"; diff <(echo "$want") <(echo "$out"); exit 1; }
[ "$(cat "$F/accepted")" = ev1 ] || { echo "OOO accept: $(cat "$F/accepted")"; exit 1; }
grep -q 'for Max, a developer on the Ops team' "$F/prompt" && grep -q '^PROJ-7    In Progress - Fix login' "$F/prompt" ||
  { echo "triage prompt:"; head -3 "$F/prompt"; exit 1; }
[ "$(jq -c .mine "$tmp/cache/notices.jsonl" | paste -sd' ' -)" = '["PROJ-7"] ["PROJ-9"] [] [] [] ["PROJ-7"]' ] ||
  { echo "mine: $(jq -c .mine "$tmp/cache/notices.jsonl")"; exit 1; }
grep -q '"line":"teams ?   Team · Tim: deploy done' "$tmp/cache/dropped.jsonl" || { echo "dropped.jsonl"; exit 1; }
[ "$(grep -c . "$tmp/cache/prs.tsv")" = 1 ] || { echo "prs.tsv"; exit 1; }
# Its cleanup doesn't follow it out: a caller under set -u returns normally (session-status's notices job).
[ "$(cd "$tmp/proj" && set -u && HOME=$tmp PATH=$tmp/bin:$PATH NOTICE_DIR=$tmp/cache NOTICE_KEYRE='(PROJ-[0-9]+)' NOTICE_ROWS=$tmp/rows NOTICE_MINE=$tmp/mine &&
  job() { messages_notices >/dev/null; } && job && echo returned)" = returned ] || { echo "the RETURN trap fired in the caller"; exit 1; }
# Again: the verdicts and the PR's keys come from the cache, no triage call.
[ "$(run)" = "$want" ] && [ "$(grep -c . "$F/calls")" = 1 ] || { echo "second run differs or called the triage"; exit 1; }
# A failed Graph call: exit 1 and one reason line.
rm "$tmp/cache/people.json"; printf '#!/bin/sh\necho %s >&2; exit 1\n' "'{\"error\":{\"type\":\"auth_error\"}}'" > "$tmp/bin/graph"
out=$(run) && { echo "a failure exited 0"; exit 1; }
[ "$out" = "teams: msgraph auth_error error" ] || { echo "failure: $out"; exit 1; }
echo ok

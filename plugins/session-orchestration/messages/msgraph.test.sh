#!/usr/bin/env bash
# Self-check for messages/msgraph.sh: a stubbed Graph CLI and `claude` (the triage), a temp HOME and project.
# Covers each rule (DM unread, read+unanswered, read+answered, mention with a PR link, A, B, C, mail drop/keep/triage), the OOO accept, `mine`, and a
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
# DMs read already: Kim's ask (shown), Joe's thanks (the triage drops it), Max's own reply (answered), and an
# ask from 3 days ago (outside the window, not triaged).
echo "{\"value\":[$(chat dm1 oneOnOne null "$(iso 60)" m1 u-ann Ann 'hi about PROJ-7' "$(iso 10)"),
  $(chat dm2 oneOnOne null "$(iso 5)" m2 u-kim Kim 'can you review my fix?' "$(iso 20)"),
  $(chat dm3 group null "$(iso 5)" m3 u-joe Joe 'thanks!' "$(iso 20)"),
  $(chat dm4 oneOnOne null "$(iso 5)" m4 u-me Max 'sure, will do' "$(iso 20)"),
  $(chat dm5 oneOnOne null "$(iso 4000)" m5 u-old Old 'old ask?' "$(iso 4320)"),
  $(chat q group '"Questions"' "$(iso 60)" q1 u-x Xi x "$(iso 10)"), $(chat team group '"Team"' "$(iso 60)" t1 u-tm Tim x "$(iso 10)"),
  $(chat sup group '"Support"' "$(iso 0)" s1 u-cu Cu x "$(iso 120)"), $(chat g group '"General"' "$(iso 60)" x1 u-bob Bob x "$(iso 10)")]}" > "$F/chats"
echo "{\"value\":[$(msg q1 u-x Xi 'Ops, can someone look?' "$(iso 10)")]}" > "$F/q"
echo "{\"value\":[$(msg t1 u-tm Tim 'deploy done' "$(iso 10)")]}" > "$F/team"
echo "{\"value\":[$(msg s0 u-cu Cu hello "$(iso 300)"), $(msg s1 u-cu Cu 'could you check PROJ-3?' "$(iso 120)")]}" > "$F/sup"
echo "{\"results\":[{\"id\":\"x1\",\"chatId\":\"g\",\"from\":\"bob@ex.org\",\"content\":\"@Max see\",\"createdDateTime\":\"$(iso 10)\"},
  {\"id\":\"xy\",\"teamId\":\"t\",\"channelId\":\"c\",\"from\":\"bob@ex.org\",\"content\":\"@Max yday\",\"createdDateTime\":\"$(iso $(( ($(date +%s) - $(epoch "$(dayfmt "$(date +%F)" %F -1)") - 43200) / 60 )))\"},
  {\"id\":\"x0\",\"teamId\":\"t\",\"channelId\":\"c\",\"from\":\"bob@ex.org\",\"content\":\"@Max old\",\"createdDateTime\":\"$(iso 4320)\"}]}" > "$F/mentions"
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
  raw) echo "\$4" >> $F/raw; case "\$4" in /me/chats*) cat $F/chats ;; /me/events*) cat $F/events ;; /chats/g/messages/x1) cat $F/x1 ;;
         /chats/*) p=\${4#/chats/}; cat "$F/\${p%%/*}" ;; esac ;;
esac
EOF
# The triage, by each message's text: the team question, Kim's ask and Lee's mail need action; the rest don't.
cat > "$tmp/bin/claude" <<EOF
#!/bin/sh
cat > $F/prompt; echo 1 >> $F/calls
awk '/^## Message /{n = \$3 + 0} /^The message: /{
  if (/Ops, can someone/) v = "true,\"to\":\"team\",\"ticket\":null,\"why\":\"asks the team\""
  else if (/review my fix/) v = "true,\"to\":\"me\",\"ticket\":null,\"why\":\"asks for a review\""
  else if (/PROJ-7/) v = "true,\"to\":\"me\",\"ticket\":\"PROJ-7\",\"why\":\"asks about PROJ-7\""
  else v = "false,\"to\":\"team\",\"ticket\":null,\"why\":\"fyi\""
  printf "%s{\"n\":%d,\"action\":%s}", (s++ ? "," : "["), n, v } END {print "]"}' $F/prompt
EOF
chmod +x "$tmp/bin/graph" "$tmp/bin/claude"
adapter() { case $1 in urls) echo 'pr https://h/p/repos/{repo}/pull-requests/{id}' ;; pr-keys) [ "$2" = app#5 ] && echo PROJ-9 ;; *) return 2 ;; esac; }
. "$here/msgraph.sh"
printf 'PROJ-7    In Progress  | Fix login\nPROJ-9    In Review    | Speed up\n' > "$tmp/rows"; printf 'PROJ-9\nPROJ-7\n' > "$tmp/mine"
run() { (cd "$tmp/proj" && HOME=$tmp PATH=$tmp/bin:$PATH NOTICE_DIR=$tmp/cache NOTICE_KEYRE='(PROJ-[0-9]+)' NOTICE_ROWS=$tmp/rows NOTICE_MINE=$tmp/mine messages_notices); }

want='teams DM  Ann: hi about PROJ-7 [PROJ-7]
teams DM  Kim: can you review my fix? — read, unanswered: asks for a review
teams @   General · bob: @Max see [PROJ-9]
teams @   channel · bob: @Max yday
teams ?   Support · Cu: could you check PROJ-3? [PROJ-3]
teams ?   Questions · Xi: Ops, can someone look? — asks the team
mail      Acc: Invoice
mail      Lee: Question on PROJ-7 [PROJ-7] — asks about PROJ-7'
out=$(run); [ "$out" = "$want" ] || { echo "lines differ:"; diff <(echo "$want") <(echo "$out"); exit 1; }
# The 3-day-old mention is outside the window: not shown, and its body not fetched.
! grep -q x0 "$F/raw" || { echo "fetched the out-of-window mention's body"; exit 1; }
[ "$(cat "$F/accepted")" = ev1 ] || { echo "OOO accept: $(cat "$F/accepted")"; exit 1; }
grep -q 'for Max, a developer on the Ops team' "$F/prompt" && grep -q '^PROJ-7    In Progress - Fix login' "$F/prompt" ||
  { echo "triage prompt:"; head -3 "$F/prompt"; exit 1; }
[ "$(jq -c .mine "$tmp/cache/notices.jsonl" | paste -sd' ' -)" = '["PROJ-7"] [] ["PROJ-9"] [] [] [] [] ["PROJ-7"]' ] ||
  { echo "mine: $(jq -c .mine "$tmp/cache/notices.jsonl")"; exit 1; }
grep -q '"line":"teams ?   Team · Tim: deploy done' "$tmp/cache/dropped.jsonl" &&
  grep -q '"line":"teams DM  Joe: thanks!"' "$tmp/cache/dropped.jsonl" || { echo "dropped.jsonl"; exit 1; }
# Unread DMs aren't triaged; read ones answered or older than yesterday aren't even asked about.
! grep -q 'hi about PROJ-7\|sure, will do\|old ask' "$F/prompt" || { echo "triaged a DM it shouldn't"; exit 1; }
[ "$(grep -c . "$tmp/cache/prs.tsv")" = 1 ] || { echo "prs.tsv"; exit 1; }
# Its cleanup doesn't follow it out: a caller under set -u returns normally (session-status's notices job).
[ "$(cd "$tmp/proj" && set -u && HOME=$tmp PATH=$tmp/bin:$PATH NOTICE_DIR=$tmp/cache NOTICE_KEYRE='(PROJ-[0-9]+)' NOTICE_ROWS=$tmp/rows NOTICE_MINE=$tmp/mine &&
  job() { messages_notices >/dev/null; } && job && echo returned)" = returned ] || { echo "the RETURN trap fired in the caller"; exit 1; }
# Again: the verdicts and the PR's keys come from the cache, no triage call.
# A half-written verdict file beside them is skipped, not the ones read after it.
printf %s '{"action":tr' > "$tmp/cache/triage/0-half"
[ "$(run)" = "$want" ] && [ "$(grep -c . "$F/calls")" = 1 ] || { echo "second run differs or called the triage"; exit 1; }
# A read DM not judged (the triage failed) isn't shown; Joe's DM marked unread again shows despite its old verdict.
mv "$tmp/bin/claude" "$tmp/claude.ok"; printf '#!/bin/sh\nexit 1\n' > "$tmp/bin/claude"; chmod +x "$tmp/bin/claude"
rm "$tmp/cache/triage/dm-read-m2"; cp "$F/chats" "$tmp/chats.ok"
jq --arg r "$(iso 60)" '(.value[] | select(.id == "dm3") | .viewpoint.lastMessageReadDateTime) = $r' "$tmp/chats.ok" > "$F/chats"
[ "$(run)" = "$(sed 's/^teams DM  Kim.*/teams DM  Joe: thanks!/' <<<"$want")" ] || { echo "fail-closed / re-unread: $(run)"; exit 1; }
mv "$tmp/claude.ok" "$tmp/bin/claude"; mv "$tmp/chats.ok" "$F/chats"
# A dismissed line (the mail still unread in Outlook) stays out of later runs; its message id, not its text, is kept.
dismiss() { NOTICE_DIR=$tmp/cache messages_dismiss "$1"; }
# Matched with whitespace runs collapsed; it beats a verdict written after it (a sweep judging meanwhile).
dismiss 'mail Acc: Invoice ' && ! dismiss 'mail      Nobody: x' && [ "$(run)" = "$(grep -v 'Acc: Invoice' <<<"$want")" ] &&
  dismiss 'mail      Lee: Question on PROJ-7 [PROJ-7] — asks about PROJ-7' && touch "$tmp/cache/triage/mail-a4" &&
  [ "$(run)" = "$(grep -v 'Acc: Invoice\|Lee: Question' <<<"$want")" ] && [ -f "$tmp/cache/dismissed/mail-a2" ] ||
  { echo "dismiss failed: $(run)"; exit 1; }
# A failed Graph call: exit 1 and one reason line.
rm "$tmp/cache/people.json"; printf '#!/bin/sh\necho %s >&2; exit 1\n' "'{\"error\":{\"type\":\"auth_error\"}}'" > "$tmp/bin/graph"
out=$(run) && { echo "a failure exited 0"; exit 1; }
[ "$out" = "teams: msgraph auth_error error" ] || { echo "failure: $out"; exit 1; }
echo ok

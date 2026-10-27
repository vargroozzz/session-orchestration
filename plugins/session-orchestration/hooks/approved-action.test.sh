#!/usr/bin/env bash
# Self-check for approved-action.sh: a fake coordinator transcript holding the user's approvals, a worker transcript
# holding the coordinator's relays, a stubbed `claude agents`. Run: bash approved-action.test.sh  (prints "ok" or the failure).
set -euo pipefail; unset XDG_CONFIG_HOME   # the person-wide config.json: never the real one
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
root=$(mkdir -p "$tmp/proj" && cd "$tmp/proj" && pwd -P)
cid=99999999-2222-3333-4444-555555555555
home=$tmp/home; proj=$home/.claude/projects/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$root")
mkdir -p "$proj" "$tmp/bin"
now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z) old=2020-01-01T00:00:00.000Z
printf 'Looks good to me.\n' > "$tmp/body.txt"; sha=$(shasum -a 256 "$tmp/body.txt" | cut -d' ' -f1)
printf 'Ship it.\n' > "$tmp/other.txt"

typed() { jq -nc --arg ts "$2" --arg t "$1" '{type: "user", origin: {kind: "human"}, timestamp: $ts, message: {content: $t}}'; }
{
  typed "yes, merge PROJ-1 (app#271)" "$now"
  typed "yes, post the PROJ-2 comment" "$now"
  typed "yes, post the PROJ-3 comment" "$old"
  typed "yes, merge PROJ-4" "$now"
  typed "yes, merge PROJ-5 (app#290)" "$now"
  typed "yes, merge ACME-7 (app#12)" "$now"
  typed "yes, post the ACME-8 comment" "$now"
  typed "yes, approve app#14" "$now"
  typed "yes, merge app#15" "$now"
  typed "yes, post the ACME-9 note" "$now"
  typed "yes, request changes on ACME-10" "$now"
  typed "yes, merge PROJ-11 (app#301)" "$now"
  typed "yes, post the PROJ-12 comment" "$now"
  typed "yes, approve PROJ-13" "$now"
  typed "yes, request changes on PROJ-14" "$now"
} > "$proj/$cid.jsonl"
export CLAUDE_CODE_SESSION_ATTENDED=0 # unattended (a --bg session) unless a check says otherwise
printf '#!/bin/sh\necho %s\n' "'[{\"sessionId\":\"$cid\",\"name\":\"coord\",\"cwd\":\"$root\",\"kind\":\"interactive\"}]'" > "$tmp/bin/claude"
chmod +x "$tmp/bin/claude"

relay() { # $1 quote, $2 action, [$3 sender name, $4 origin.from, $5 handback]
  jq -nc --arg b "$(printf 'Go ahead.\n\nAPPROVAL relayed from the user\nQuote: %s\nAction: %s\nSource: %s %s\n' "$1" "$2" "$cid" "$root")" \
    --arg n "${3:-coord}" --arg f "${4:-uds:/tmp/x.sock}" --argjson h "${5:-false}" \
    '{type: "user", origin: ({kind: "peer", from: $f, name: $n, body: $b} + if $h then {handback: true} else {} end), message: {content: "x"}}'
}
w=$tmp/worker.jsonl
{
  relay "yes, merge PROJ-1 (app#271)" "merge app#271 (PROJ-1)"
  relay "yes, post the PROJ-2 comment" "post comment $tmp/body.txt on app#273 (sha256 $sha) for PROJ-2"
  relay "yes, post the PROJ-2 comment" "post comment $tmp/body.txt on PROJ-2 (sha256 $sha)"
  relay "yes, post the PROJ-3 comment" "post comment $tmp/body.txt on PROJ-3 (sha256 $sha)"
  relay "yes, merge PROJ-4" "merge app#280 (PROJ-4)" coord handback-agent
  relay "yes, merge PROJ-4" "merge app#281 (PROJ-4)" coord uds:/tmp/y.sock true
  relay "yes, merge PROJ-1 (app#271)" "merge web#271 (PROJ-1)"
  relay "yes, merge PROJ-5 (app#290)" "merge app#290 (PROJ-5)"
  relay "yes, merge ACME-7 (app#12)" "merge acme/app#12 (ACME-7)"
  relay "yes, post the ACME-8 comment" "post comment $tmp/body.txt on acme/app#13 (sha256 $sha) for ACME-8"
  relay "yes, approve app#14" "approve acme/app#14"
  relay "yes, merge app#15" "merge acme/app#15 (app-fix-login)"
  relay "yes, post the ACME-9 note" "post comment $tmp/body.txt on acme/app#16 (sha256 $sha) for ACME-9"
  relay "yes, request changes on ACME-10" "post request-changes review $tmp/body.txt on acme/app#18 (sha256 $sha) for ACME-10"
  relay "yes, merge PROJ-11 (app#301)" "merge org/app#301 (PROJ-11)"
  relay "yes, post the PROJ-12 comment" "post comment $tmp/body.txt on org/app#302 (sha256 $sha) for PROJ-12"
  relay "yes, approve PROJ-13" "approve org/app#303 (PROJ-13)"
  relay "yes, request changes on PROJ-14" "post request-changes review $tmp/body.txt on org/app#304 (sha256 $sha) for PROJ-14"
} > "$w"

run() { # $1 command → allow | deny | pass | blocked (exit 2)
  local out rc
  out=$(jq -nc --arg c "$1" --arg cwd "$root" --arg tp "$w" '{tool_input: {command: $c}, cwd: $cwd, transcript_path: $tp}' |
    (cd "$root" && HOME=$home CLAUDE_CONFIG_DIR=$home/.claude PATH=$tmp/bin:$PATH bash "$here/approved-action.sh") 2>/dev/null) && rc=0 || rc=$?
  [ "$rc" = 2 ] && { echo blocked; return; }
  [ -n "$out" ] && jq -r .hookSpecificOutput.permissionDecision <<<"$out" || echo pass
}
check() { got=$(run "$1"); [ "$got" = "$2" ] || { echo "FAIL ($3): '$1': got $got, want $2"; exit 1; }; }
bb='npx -y bitbucketdc-cli@latest' jd='npx jiradc-cli@latest'

check "git status" pass "unrelated command"
check "$bb pr list --repo app" pass "other bitbucket call"
check "$bb pr merge --help" pass "help"
check "$bb pr merge 271 --project PROJ --repo app 2>&1 | head -5" allow "approved merge"
check "cd $root && $bb pr merge 271 --repo app" deny "approval used once already"
check "$bb pr merge 272 --project PROJ --repo app" deny "unapproved merge"
check "$bb pr merge 271 --repo web" allow "approved merge, other repo relay"
check "$bb pr merge 280 --repo app" deny "merge relayed by a subagent hand-back"
check "$bb pr merge 271" deny "merge without --repo"
check "$bb pr comment create 273 --project PROJ --repo app --body-file $tmp/body.txt" allow "approved PR post"
check "$jd issue comment create PROJ-2 --body-file $tmp/body.txt" allow "approved Jira post"
check "$jd issue comment create PROJ-9 --body-file $tmp/body.txt" deny "wrong key"
check "$jd issue comment create PROJ-2 --body-file $tmp/other.txt" deny "other body file"
check "$jd issue comment create PROJ-3 --body-file $tmp/body.txt" deny "expired approval"
check "$jd issue comment create PROJ-2 --body 'Looks good to me.'" deny "inline body"
check "$bb pr comment create 273 --repo app --body-file $tmp/body.txt && $bb pr merge 271 --repo app" deny "two guarded calls"
check "$bb pr merge 281 --repo app" deny "merge relayed by a subagent hand-back from a socket"
check "$bb \\
  pr merge 272 --repo app" deny "line continuation"
check "$bb pr get 271 --repo app
$bb pr merge 272 --repo app" deny "second call on the next line"
check "BB='$bb'; \$BB pr merge 272 --repo app" deny "CLI in a variable"
check "$bb --project PROJ pr merge 272 --repo app" deny "global flag before the subcommand"
check "$jd issue comment create PROJ-2 --body-file \"it's" deny "unparseable"
cp "$tmp/body.txt" "$tmp/body.bak"; echo edited >> "$tmp/body.txt"
check "$jd issue comment create PROJ-2 --body-file $tmp/body.txt" deny "edited body file"
cp "$tmp/body.bak" "$tmp/body.txt"
# Forgejo: forgejo-cli, --repo OWNER/REPO, a review's verdict in --status.
fj='npx -y forgejo-cli@latest'
check "$fj pr get 301 --repo org/app" pass "read-only forgejo call"
check "$fj raw /repos/org/app/pulls/301" pass "forgejo raw GET"
check "$fj raw /repos/org/app/pulls/301/merge --method POST" deny "forgejo raw write"
check "$fj pr merge 309 --repo org/app" deny "forgejo merge, no relay"
check "$fj pr 'merge' 309 --repo org/app" deny "forgejo merge, quoted subcommand"
check "$fj pr comment \"create\" 309 --repo org/app --body-file $tmp/body.txt" deny "forgejo comment, quoted subcommand"
check "$fj 'raw' /repos/org/app/pulls/301/merge '--method' POST" deny "forgejo raw write, quoted"
check "forgejo-cli pr merge 309 --repo org/app" deny "forgejo merge by the bare binary, no relay"
check "$fj pr merge 301 --repo app" deny "forgejo merge, --repo without owner"
check "$fj pr merge 301 --repo org/app --strategy squash" allow "forgejo merge with a relay"
check "$fj pr merge 301 --repo org/app" deny "forgejo merge, relay used once already"
check "$fj pr comment create 302 --repo org/app --body 'Looks good to me.'" deny "forgejo comment, inline body"
check "$fj pr comment create 302 --repo org/app --body-file $tmp/other.txt" deny "forgejo comment, other body file"
check "$fj pr comment create 302 --repo org/app --body-file $tmp/body.txt --path a.ts --line 3" allow "forgejo inline comment with the sha256"
check "$fj pr review 303 --repo org/app --status APPROVED" allow "forgejo bare approve"
check "$fj pr review 304 --repo org/app --body-file $tmp/body.txt" deny "forgejo review, no verdict"
check "$fj pr review 304 --repo org/app --status COMMENT --body-file $tmp/body.txt" deny "forgejo review kind differs from the relay"
check "$fj pr review 304 --repo org/app --status REQUEST_CHANGES --body-file $tmp/body.txt --comments-file /tmp/c.json" deny "forgejo review with inline comments"
check "$fj pr comment create 304 --repo org/app --body-file $tmp/body.txt" deny "a forgejo review's relay used for a plain comment"
check "$fj pr review 304 --repo org/app --status NEEDS_WORK --body-file $tmp/body.txt" allow "forgejo request-changes review, relayed as one"
check "$fj pr merge 309 --repo org/app && $bb pr merge 272 --repo app" deny "forgejo and bitbucket calls in one command"
CLAUDE_CODE_SESSION_ATTENDED=1 check "$fj pr merge 309 --repo org/app" ask "attended, unapproved forgejo merge"
got=$(jq -nc --arg c "$fj pr merge 309 --repo org/app" --arg cwd "$root" --arg tp "$w" '{tool_input: {command: $c}, cwd: $cwd, transcript_path: $tp}' |
  (cd "$root" && HOME=$home CLAUDE_CONFIG_DIR=$home/.claude PATH=$tmp/bin:$PATH bash "$here/approved-action.sh") | jq -r .hookSpecificOutput.permissionDecisionReason)
grep -qF 'needs your approval: merge org/app#309' <<<"$got" || { echo "FAIL: forgejo deny doesn't name the action: $got"; exit 1; }
# Attended (an interactive session): the missing approval asks instead of denying; anything else on the signal denies.
# GitHub: OWNER/REPO#ID from -R/--repo or the PR's URL, never from a remote.
git -C "$root" init -q && git -C "$root" remote add origin git@github.com:acme/app.git
check "gh pr list --repo acme/app" pass "read-only gh call"
check "gh api repos/acme/app/pulls/12" pass "gh api GET"
check "git log --grep gh" pass "gh as an argument"
check "git commit -m 'gate the gh merge'" pass "gh in a message, no pr/issue/api word after it"
check "gh pr merge 99 --repo acme/app" deny "gh merge, no relay"
check "gh pr merge 12" deny "gh merge, no -R (the remote isn't read)"
check "gh pr merge 12 -R app" deny "gh merge, -R without owner"
check "gh pr merge 12 -R other/app" deny "gh merge, same repo name under another owner"
check "gh pr merge 12 -R github.com/acme/app --squash" allow "gh merge with a relay, HOST/OWNER/REPO"
check "gh pr merge 12 --repo acme/app" deny "gh merge, relay used once already"
check "gh pr -R acme/app merge 99" deny "gh flag between pr and merge"
check "gh pr \"merge\" 99 -R acme/app" deny "gh quoted verb"
check "\"gh\" pr merge 99 -R acme/app" deny "gh quoted name"
check "x=gh; \$x pr merge 99 -R acme/app" deny "gh through a variable"
check "\$(which gh) pr merge 99 -R acme/app" deny "gh through \$(which)"
check "bash -c 'gh pr merge 99 -R acme/app'" deny "gh inside bash -c"
check "gh pr merge https://github.com/evil/other/pull/15 -R acme/app" deny "URL and -R disagree"
check "gh pr merge https://github.com/acme/app/pull/15 -d" allow "gh merge by URL, session-name key"
check "gh pr merge feature/x -R acme/app" deny "gh merge by branch"
check "gh pr merge 12 -m 13 -R acme/app" deny "gh -m takes no value: 13 is a stray word, 12 used up"
check "gh pr comment 13 -R acme/app --body-file $tmp/body.txt" allow "gh comment with the sha256"
check "gh pr comment 13 -R acme/app -F $tmp/other.txt" deny "gh comment, other body file"
check "gh pr comment 13 -R acme/app --body 'Looks good to me.'" deny "gh comment, inline body"
check "gh pr comment 13 -R acme/app -F body.txt" deny "gh comment, relative body file"
check "gh pr review 14 -R acme/app --approve" allow "gh bare approve"
check "gh pr review 14 -R acme/app --approve" deny "gh approve used once already"
check "gh pr review 17 -R acme/app --approve" deny "gh approve, no relay"
check "gh pr review 16 -R acme/app --request-changes -F $tmp/body.txt" deny "review relayed as a plain comment"
check "gh pr review 18 -R acme/app --comment -F $tmp/body.txt" deny "review kind differs from the relay"
check "gh pr review 18 -R acme/app -r -a -F $tmp/body.txt" deny "two review kinds"
check "gh pr review 18 -R acme/app --request-changes -F $tmp/body.txt" allow "gh request-changes review, relayed as one"
check "gh issue comment 16 -R acme/app -F $tmp/body.txt" allow "gh issue comment"
check "gh api -X PUT repos/acme/app/pulls/12/merge" deny "gh api write method"
check "gh api repos/acme/app/issues/12/comments -f body=hi" deny "gh api fields"
check "gh pr comment 13 -R acme/app -F $tmp/body.txt; gh pr merge 12 -R acme/app" deny "two gh calls"
check "gh pr view 13 -R acme/app && gh pr merge 99 -R acme/app" deny "a gated gh call with another"
check "$bb pr merge 12 --repo gh" deny "bitbucket repo named gh, unapproved (still gated, not a false 'two calls')"
check "cd /tmp &&
gh pr merge 99 -R acme/app" deny "gh on its own line"
check "gh pr view 1 -R acme/app --json title&&gh pr merge 99 -R acme/app" deny "gh glued to a separator"
check "gh pr list -R acme/app; bash -c 'gh pr merge 99 -R acme/app'" deny "bash -c beside a read-only gh call"
check "gh \$(echo pr) merge 99 -R acme/app" deny "gh words from \$(…)"
check "a=pr; gh \$a merge 99 -R acme/app" deny "gh words from a variable"
check "echo 'pr merge 99 -R acme/app' | xargs gh" deny "gh through xargs"
check "gh m 99 -R acme/app" deny "gh alias"
check "gh api -XPUT repos/acme/app/pulls/99/merge" deny "gh api glued -X"
check "gh api repos/acme/app/issues/99/comments -fbody=hi" deny "gh api glued -f"
check "gh api -X GET search/issues -f q=repo:acme/app" pass "gh api GET with query fields"
check "gh pr merge 15 -R ghe.example.com/acme/app" deny "another host's PR under a github.com relay"
check "GH_HOST=ghe.example.com gh pr merge 15 -R acme/app" deny "GH_HOST"
check "gh pr comment 18 -R acme/app -F $tmp/body.txt" deny "a review's relay used for a plain comment"
check "$bb pr merge 12 --repo app" deny "a gh relay (acme/app#12) used for a bitbucket merge"
check "which gh && gh pr merge 99 -R acme/app" deny "gh as an argument, then a gated call"
check "gh --version" pass "gh flag only"
CLAUDE_CODE_SESSION_ATTENDED=1 check "gh pr merge 99 -R acme/app" ask "attended, unapproved gh merge"
CLAUDE_CODE_SESSION_ATTENDED=1 check "gh api -X POST repos/acme/app/merges" ask "attended, gh api write"
CLAUDE_CODE_SESSION_ATTENDED=1 check "$bb pr merge 272 --repo app" ask "attended, unapproved merge"
CLAUDE_CODE_SESSION_ATTENDED=1 check "$jd issue comment create PROJ-9 --body-file $tmp/body.txt" ask "attended, wrong key"
CLAUDE_CODE_SESSION_ATTENDED=1 check "$bb pr merge 290 --repo app" allow "attended, approved merge"
CLAUDE_CODE_SESSION_ATTENDED=1 check "$bb pr merge 290 --repo app" ask "attended, approval used once already"
CLAUDE_CODE_SESSION_ATTENDED=1 check "$jd issue comment create PROJ-2 --body 'x'" deny "attended, inline body"
CLAUDE_CODE_SESSION_ATTENDED=1 check "BB='$bb'; \$BB pr merge 272 --repo app" deny "attended, CLI in a variable"
CLAUDE_CODE_SESSION_ATTENDED=yes check "$bb pr merge 272 --repo app" deny "attended signal not 1"
CLAUDE_CODE_SESSION_ATTENDED= check "$bb pr merge 272 --repo app" deny "attended signal empty"
(unset CLAUDE_CODE_SESSION_ATTENDED; check "$bb pr merge 272 --repo app" deny "attended signal unset")
for c in "0 $w deny" "1 $w ask" "1 $tmp/no-such.jsonl ask" "0 $tmp/no-such.jsonl deny"; do # attended, transcript, want
  set -- $c
  got=$(jq -nc --arg c "$bb pr merge 272 --repo app" --arg cwd "$root" --arg tp "$2" '{tool_input: {command: $c}, cwd: $cwd, transcript_path: $tp}' |
    (cd "$root" && HOME=$home CLAUDE_CONFIG_DIR=$home/.claude PATH=$tmp/bin:$PATH CLAUDE_CODE_SESSION_ATTENDED=$1 bash "$here/approved-action.sh") |
    jq -r '.hookSpecificOutput | "\(.permissionDecision) \(.permissionDecisionReason)"')
  [ "${got%% *}" = "$3" ] && grep -qF 'needs your approval: merge app#272' <<<"$got" ||
    { echo "FAIL (attended=$1, transcript $2): want $3 with the action, got: $got"; exit 1; }
done
# Fails closed: a broken verify step blocks, never allows.
mkdir -p "$tmp/broken/hooks" && cp "$here/approved-action.sh" "$tmp/broken/hooks/"
out=$(jq -nc --arg c "$bb pr merge 271 --repo app" --arg cwd "$root" --arg tp "$w" '{tool_input: {command: $c}, cwd: $cwd, transcript_path: $tp}' |
  (cd "$root" && HOME=$home PATH=$tmp/bin:$PATH bash "$tmp/broken/hooks/approved-action.sh") 2>/dev/null) || true
[ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$out" 2>/dev/null)" != allow ] || { echo "FAIL: allowed without verify-approval.sh"; exit 1; }
echo ok

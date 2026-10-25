#!/usr/bin/env bash
# Self-check for templates/github-adapter on a `gh pr list` JSON fixture and a stub `gh`: the pane's words for an
# approved PR, a conflict, a failed build, changes asked (and a bot's approval not counting), a merge;
# `done`; the minute cache; a gh failure, with and without an older answer; and `mine` (ownership).
# Run: bash github-adapter.test.sh  (prints "ok" or what failed).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/p"
sed -e 's#{{repo_slug}}#acme/app#; s#{{key_re}}#DEMO-[0-9]+#; s#{{name}}#app#; s#{{orch}}#.claude/orchestration#' \
  -e "s#{{urls}}#'pr https://github.com/acme/{repo}/pull/{id}'#; s#^{{?[a-z_]*}}##" \
  "$here/templates/github-adapter" > "$tmp/adapter" && chmod +x "$tmp/adapter"
cat > "$tmp/prs.json" <<'EOF'
[
 {"number":1,"headRefName":"DEMO-1-a","title":"One","state":"OPEN","mergeable":"MERGEABLE","statusCheckRollup":[{"conclusion":"SUCCESS"}],
  "reviews":[{"author":{"login":"alice"},"state":"APPROVED"}]},
 {"number":2,"headRefName":"feature/DEMO-2-b","title":"Two","state":"OPEN","mergeable":"CONFLICTING","statusCheckRollup":[],"reviews":[]},
 {"number":3,"headRefName":"DEMO-3-c","title":"Three","state":"OPEN","mergeable":"MERGEABLE",
  "statusCheckRollup":[{"conclusion":"SUCCESS"},{"conclusion":"FAILURE"}],"reviews":[{"author":{"login":"bob"},"state":"APPROVED"}]},
 {"number":4,"headRefName":"DEMO-4-d","title":"Four","state":"OPEN","mergeable":"UNKNOWN","statusCheckRollup":[{"state":"PENDING"}],
  "reviews":[{"author":{"login":"bob"},"state":"APPROVED"},{"author":{"login":"bob"},"state":"CHANGES_REQUESTED"},
             {"author":{"login":"carol"},"state":"COMMENTED"},{"author":{"login":"approver[bot]"},"state":"APPROVED"}]},
 {"number":5,"headRefName":"DEMO-5-e","title":"Five","state":"MERGED"},
 {"number":7,"headRefName":"readme","title":"No key","state":"OPEN","mergeable":"MERGEABLE","statusCheckRollup":[],"reviews":[]}
]
EOF
# gh pr list … --state open|merged: the fixture's PRs in that state; gh-down makes it fail; calls are counted
# mine: you are "me"; your PRs (--author @me) close #11 (unassigned: yours) and #13 (someone else's); #10 is yours.
cat > "$tmp/mine.json" <<'EOF'
[{"headRefName":"DEMO-1-a","body":"Fixes #11, closes #13"},{"headRefName":"no-key","body":""}]
EOF
cat > "$tmp/issues.json" <<'EOF'
[{"number":10,"assignees":[{"login":"me"}]},{"number":11,"assignees":[]},{"number":12,"assignees":[]},
 {"number":13,"assignees":[{"login":"alice"}]}]
EOF
cat > "$tmp/bin/gh" <<EOF
#!/bin/sh
echo x >> "$tmp/calls"
[ -e "$tmp/gh-down" ] && { echo "gh: HTTP 401: Bad credentials" >&2; exit 1; }
case "\$*" in *"--assignee @me"*) jq "[.[] | select(.assignees | map(.login) | index(\"me\"))]" "$tmp/issues.json"; exit 0 ;; *no:assignee*) jq "[.[] | select(.assignees == [])]" "$tmp/issues.json"; exit 0 ;; esac
case "\$*" in *"--author @me"*) cat "$tmp/mine.json"; exit 0 ;; esac
state=\$(echo "\$*" | sed -n 's/.*--state \([a-z]*\).*/\1/p' | tr a-z A-Z)
jq --arg s "\$state" '[.[] | select(.state == \$s)]' "$tmp/prs.json"
EOF
chmod +x "$tmp/bin/gh"
run() { (cd "$tmp/p" && HOME=$tmp PATH=$tmp/bin:$PATH "$tmp/adapter" "$@"); }
cache=$tmp/.cache/session-status/acme-app.gh.json

want=$(printf '%s\t%s\t%s\t%s\n' \
  DEMO-1 'In review' One 'app#1 OPEN approved by alice | ' \
  DEMO-2 'In review' Two 'app#2 OPEN no-human-approval CONFLICT | ' \
  DEMO-3 'In review' Three 'app#3 OPEN approved by bob CI-FAILED | ' \
  DEMO-4 'In review' Four 'app#4 OPEN changes requested by bob no-human-approval | ' \
  DEMO-5 Done Five 'app#5 MERGED | ' \
  DEMO-6 - '' '')
diff <(run tasks DEMO-1 DEMO-2 DEMO-3 DEMO-4 DEMO-5 DEMO-6) <(echo "$want") || { echo "tasks differ"; exit 1; }
[ "$(grep -c . "$tmp/calls")" = 2 ] || { echo "gh calls: $(grep -c . "$tmp/calls")"; exit 1; }   # open + merged
# the sweep: not answered without keys (session-status finds them); `done` and the lookups use the cache
rc=0; run tasks >/dev/null || rc=$?; [ "$rc" = 2 ] || { echo "tasks with no keys exited $rc"; exit 1; }
[ "$(run done DEMO-1 DEMO-5 DEMO-6)" = "DEMO-5	merged #5" ] || { echo "done: $(run done DEMO-1 DEMO-5 DEMO-6)"; exit 1; }
[ "$(grep -c . "$tmp/calls")" = 2 ] || { echo "cache unused: $(grep -c . "$tmp/calls") gh calls"; exit 1; }
[ "$(run urls)" = "pr https://github.com/acme/{repo}/pull/{id}" ] && [ "$(run key-pattern)" = 'DEMO-[0-9]+' ] || { echo "urls/key-pattern"; exit 1; }
rc=0; run status-names >/dev/null 2>&1 || rc=$?; [ "$rc" = 2 ] || { echo "unanswered call exited $rc"; exit 1; }
# gh down: an answer over a minute old is used, marked with its time; with none, the rows say why
touch "$tmp/gh-down"; touch -t 202601010930 "$cache"
[ "$(run tasks DEMO-5)" = "DEMO-5	Done	Five	app#5 MERGED (PRs as of 09:30) | " ] || { echo "stale: $(run tasks DEMO-5)"; exit 1; }
rm "$cache"
[ "$(run tasks DEMO-5)" = "DEMO-5	-		(PRs unavailable: gh: HTTP 401: Bad credentials) | " ] || { echo "no cache: $(run tasks DEMO-5)"; exit 1; }
# a failure isn't retried for a minute: one gh call for the two runs above
[ "$(grep -c . "$tmp/calls")" = 3 ] || { echo "gh retried after a failure: $(grep -c . "$tmp/calls") calls"; exit 1; }
rm "$tmp/gh-down"
[ "$(run mine | paste -sd' ' -)" = "#10 #11 DEMO-1" ] || { echo "mine: $(run mine)"; exit 1; }
echo ok

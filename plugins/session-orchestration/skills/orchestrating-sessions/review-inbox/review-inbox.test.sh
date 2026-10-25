#!/usr/bin/env bash
# Self-check for verify-row.sh and post-approved.sh: rows hashed the way inbox.html hashes them (the same
# JavaScript, run in node), a stub bitbucketdc that records its arguments and stdin. Posts nothing anywhere.
# Run: bash review-inbox.test.sh  (prints "ok" or the failure).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/rows/findings"; now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)

# The page's hash, taken from inbox.html itself, so a change there that verify-row.sh doesn't follow fails here.
{ sed -n '/^const HASH_FIELDS/,/^}/p' "$here/inbox.html"
  echo 'const fs = require("fs"); const [id, file] = process.argv.slice(2); const r = JSON.parse(fs.readFileSync(file, "utf8"));'
  echo 'decisionHash(id, r).then(h => fs.writeFileSync(file, JSON.stringify({ ...r, decisionHash: h })));'
} > "$tmp/hash.js"
row() { # $1 doc id, $2 jq patch over an approved row; hashed after the patch unless $3 = raw
  local f=$tmp/rows/findings/$1.json
  jq -n --arg now "$now" '{project: "TEST", repo: "test", pr: 7, file: "src/a.ts", line: 3, lineType: "ADDED", fileType: "TO",
    severity: "nit", draft: "x", status: "approved", final: "Use `??` here — \"\" is valid.\n\nñ ✓", note: "",
    decidedBy: "u_abcdefghijklmnopqrstuv", decidedAt: $now, deciderIsOwner: true}' | jq "$2" > "$f"
  [ "${3:-}" = raw ] || node "$tmp/hash.js" "$1" "$f"
}
row ok1 .
row general '.file = null | .line = null | .final = "General remark"'
row filelevel '.line = null'
row pending '.status = "pending"'
row noted '.note = "why not ?? everywhere"'
row guest '.deciderIsOwner = false'
row posted '.commentId = 99'
row stale '.decidedAt = "2020-01-01T00:00:00.000Z"'
row edited .; jq '.final = "something else"' "$tmp/rows/findings/edited.json" > "$tmp/e" && mv "$tmp/e" "$tmp/rows/findings/edited.json"
row moved .; jq '.line = 4' "$tmp/rows/findings/moved.json" > "$tmp/e" && mv "$tmp/e" "$tmp/rows/findings/moved.json"
row unhashed . raw
row badrepo '.repo = "a b"'
row float . ; jq '.pr = 7.0' "$tmp/rows/findings/float.json" | sed 's/"pr": 7,/"pr": 7.0,/' > "$tmp/e" && mv "$tmp/e" "$tmp/rows/findings/float.json"
grep -q '"pr": 7.0' "$tmp/rows/findings/float.json" || { echo "FAIL test setup: no 7.0"; exit 1; }

v() { bash "$here/verify-row.sh" "$tmp/rows/findings/$1.json" || true; }
check() { [ "$(v "$1")" = "$2" ] || { echo "FAIL verify $1: got '$(v "$1")', want '$2'"; exit 1; }; }
check ok1 verified
check general verified
check pending "rejected: status is pending, not approved"
check noted "rejected: it has a note: a fresh session handles it"
check guest "rejected: not decided by the inbox owner"
check posted "rejected: already posted as comment 99"
check stale "rejected: decision is older than 72h or has no time"
check edited "rejected: changed after the decision (hash mismatch)"
check moved "rejected: changed after the decision (hash mismatch)"
check unhashed "rejected: changed after the decision (hash mismatch)"
check badrepo "rejected: bad project, repo or pr"
check float verified                                                 # a stored 7.0 hashes like the page's 7

# The stub CLI: logs each call's args and body, answers like Bitbucket with an id.
cat > "$tmp/bb" <<EOF
#!/usr/bin/env bash
n=\$(( \$(cat "$tmp/n" 2>/dev/null || echo 0) + 1 )); echo \$n > "$tmp/n"
echo "npm warn exec The following package was not found and will be installed" >&2
[ -f "$tmp/fail" ] && { echo "Error: socket hang up" >&2; exit 1; }
{ printf '%s|' "\$@"; echo; cat; echo; echo ---; } >> "$tmp/calls"
echo "{\"id\": \$((1000 + n)), \"text\": \"...\"}"
EOF
chmod +x "$tmp/bb"
post() { BITBUCKETDC=$tmp/bb REVIEW_INBOX_LEDGER=$tmp/ledger AI_DISCLOSURE=$tmp/ai.on bash "$here/post-approved.sh" "$tmp/rows" | sort; }

out=$(post)
grep -qx 'posted ok1 100[0-9]' <<<"$out" || { echo "FAIL post ok1: $out"; exit 1; }
grep -qx 'skipped noted: it has a note: a fresh session handles it' <<<"$out" || { echo "FAIL skip noted: $out"; exit 1; }
[ "$(grep -c '^posted' <<<"$out")" = 4 ] || { echo "FAIL want 3 posted: $out"; exit 1; }
grep -qF 'pr|comment|create|7|--project|TEST|--repo|test|--body-file|-|--path|src/a.ts|--line|3|--line-type|ADDED|--file-type|TO|' "$tmp/calls" || { echo "FAIL inline args"; cat "$tmp/calls"; exit 1; }
grep -qxF 'pr|comment|create|7|--project|TEST|--repo|test|--body-file|-|' "$tmp/calls" || { echo "FAIL general args"; cat "$tmp/calls"; exit 1; }
grep -qxF 'pr|comment|create|7|--project|TEST|--repo|test|--body-file|-|--path|src/a.ts|' "$tmp/calls" || { echo "FAIL file-level args"; cat "$tmp/calls"; exit 1; }
grep -qF 'Use `??` here — "" is valid.' "$tmp/calls" || { echo "FAIL body not exact"; exit 1; }
grep -qi 'approve\|merge' "$tmp/calls" && { echo "FAIL the CLI was asked to approve or merge"; exit 1; }
grep -q 'AI-generated' "$tmp/calls" && { echo "FAIL marker without the switch"; exit 1; }

# A re-run posts nothing twice (the ledger), and the marker comes first once the switch is on.
out2=$(post); [ "$(cat "$tmp/n")" = 4 ] || { echo "FAIL re-run posted again: $out2"; exit 1; }
grep -q 'earlier run' <<<"$out2" || { echo "FAIL re-run: $out2"; exit 1; }
: > "$tmp/ai.on"; rm "$tmp/ledger"; : > "$tmp/calls"
post >/dev/null
[ "$(grep -c '^\[AI-generated\]$' "$tmp/calls")" = 4 ] || { echo "FAIL default marker"; cat "$tmp/calls"; exit 1; }
echo '[by AI]' > "$tmp/ai.on"; rm "$tmp/ledger"; : > "$tmp/calls"
post >/dev/null
[ "$(grep -c '^\[by AI\]$' "$tmp/calls")" = 4 ] || { echo "FAIL custom marker"; cat "$tmp/calls"; exit 1; }

# A CLI that fails (maybe after Bitbucket took the comment) leaves the row ledgered as unknown: no second post.
rm "$tmp/ledger" "$tmp/ai.on"; : > "$tmp/fail"; echo 0 > "$tmp/n"
out=$(post); grep -q '^failed ok1: .*Error: socket hang up' <<<"$out" || { echo "FAIL failure line: $out"; exit 1; }
rm "$tmp/fail"; out=$(post)
[ "$(cat "$tmp/n")" = 4 ] && grep -qx 'posted ok1 unknown (earlier run; mark it in the inbox, or check the PR if unknown)' <<<"$out" || { echo "FAIL retried after failure: $out"; exit 1; }
# A second run while one holds the lock posts nothing.
mkdir "$tmp/ledger.lock"; rm "$tmp/ledger"
BITBUCKETDC=$tmp/bb REVIEW_INBOX_LEDGER=$tmp/ledger bash "$here/post-approved.sh" "$tmp/rows" 2>/dev/null && { echo "FAIL ran under a held lock"; exit 1; }
[ "$(cat "$tmp/n")" = 4 ] || { echo "FAIL posted under a held lock"; exit 1; }
# With no REVIEW_INBOX_LEDGER, each account keeps its own ledger, in its CLAUDE_CONFIG_DIR.
rmdir "$tmp/ledger.lock"; mkdir "$tmp/acct"
CLAUDE_CONFIG_DIR=$tmp/acct BITBUCKETDC=$tmp/bb AI_DISCLOSURE=$tmp/ai.on bash "$here/post-approved.sh" "$tmp/rows" >/dev/null
grep -q '^ok1	' "$tmp/acct/review-inbox-posted.tsv" || { echo "FAIL ledger not in CLAUDE_CONFIG_DIR"; exit 1; }
echo ok

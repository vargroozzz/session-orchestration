#!/usr/bin/env bash
# Verify that a review-inbox row was approved by the inbox's owner on the page, and that nothing the decision
# covers changed since. Prints "verified" (exit 0) or "rejected: <reason>" (exit 1).
# Usage: bash verify-row.sh <row.json>   (a file ArtifactData saved with out_dir; its name is the doc id)
# Checks:
#  1. status is approved, the final text isn't empty, there is no note (a note goes to a fresh session) and
#     no comment id yet (not posted).
#  2. The page's decision fields are there: decidedBy (a viewer id), deciderIsOwner true (the inbox owner
#     clicked, not someone the page was shared with), decidedAt at most MAX_AGE_H hours old (default 72).
#  3. decisionHash equals sha256 of JSON [docId, project, repo, pr, file, line, lineType, fileType, status,
#     final, note, decidedBy, decidedAt, deciderIsOwner], as inbox.html computes it on the click. Editing
#     any of those after the click (the text, the line, the PR) breaks it.
# ponytail: jq escapes DEL (U+007F) where JSON.stringify doesn't, so a final text with one fails the hash.
# ponytail: the hash catches a row edited after the decision, not a forged one. A session writes the db as
# the user, so it could write a whole fake decision; that is a rule (review-inbox.md), not a check.
set -uo pipefail
f=${1:-}; max_age_h=${MAX_AGE_H:-72}
reject() { echo "rejected: $1"; exit 1; }
[ -f "$f" ] || reject "no row file"
id=$(basename "$f" .json)
jq -e 'type == "object"' "$f" >/dev/null 2>&1 || reject "row isn't a JSON object"
r=$(jq -r --arg id "$id" --argjson maxage "$((max_age_h * 3600))" '
  if .status != "approved" then "status is \(.status // "pending"), not approved"
  elif (.final // "" | gsub("\\s"; "")) == "" then "no final text"
  elif (.note // "") != "" then "it has a note: a fresh session handles it"
  elif .commentId != null then "already posted as comment \(.commentId)"
  elif (.decidedBy // "" | test("^u_[A-Za-z0-9_-]+$") | not) then "no viewer id in decidedBy"
  elif .deciderIsOwner != true then "not decided by the inbox owner"
  elif (.repo // "" | test("^[A-Za-z0-9._-]+$") | not) or (.project // "" | test("^[A-Za-z0-9_~-]+$") | not) or ((.pr | type) != "number") then "bad project, repo or pr"
  elif (.decidedAt | type) != "string" or ((.decidedAt | sub("\\.[0-9]+Z$"; "Z") | try fromdate catch 0) < (now - $maxage)) then "decision is older than \($maxage / 3600)h or has no time"
  else "ok" end' "$f")
[ "$r" = ok ] || reject "$r"
# Numbers through floor: jq keeps a stored 7.0 as written, JSON.stringify prints 7 (pr and line are integers).
want=$(jq -cj --arg id "$id" '[$id, .project, .repo, (.pr | floor), .file, (.line | if type == "number" then floor else . end), .lineType, .fileType, .status, .final, .note, .decidedBy, .decidedAt, .deciderIsOwner]' "$f" | shasum -a 256 | cut -d' ' -f1)
[ "$(jq -r '.decisionHash // ""' "$f")" = "$want" ] || reject "changed after the decision (hash mismatch)"
echo verified

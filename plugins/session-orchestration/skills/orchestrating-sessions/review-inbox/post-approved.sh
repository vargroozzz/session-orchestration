#!/usr/bin/env bash
# Post the review-inbox rows the user approved, each exactly as its final text. Comments only: it never
# approves, merges or changes a PR.
# Usage: bash post-approved.sh <dir>   (an ArtifactData out_dir; reads <dir>/findings/*.json, or <dir>/*.json)
# Per row: verify-row.sh must print "verified", else it's skipped with the reason. Then
#   bitbucketdc pr comment create <pr> --project --repo --body-file -  (+ --path/--line/--line-type/--file-type
#   when file and line are set; --path alone for a file-level one),
# with the AI disclosure marker first when ~/.claude/ai-disclosure.on exists (its text, or "[AI-generated]").
# Output, one line per row: "posted <docId> <commentId>", "skipped <docId>: <reason>" or "failed <docId>: <error>".
# Mark each posted row in the inbox afterwards (review-inbox.md). Until then the ledger stops a re-run from
# posting it twice.
# Env: BITBUCKETDC (the CLI command; default npx -y @first/bitbucketdc-cli@latest), REVIEW_INBOX_LEDGER
# (default review-inbox-posted.tsv in the account's ${CLAUDE_CONFIG_DIR:-~/.claude}: row ids are unique only
# within one account's inbox), AI_DISCLOSURE (default ~/.claude/ai-disclosure.on).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
dir=${1:-}; [ -d "$dir" ] || { echo "usage: post-approved.sh <dir>" >&2; exit 2; }
[ -d "$dir/findings" ] && dir=$dir/findings
read -ra cli <<<"${BITBUCKETDC:-npx -y @first/bitbucketdc-cli@latest}"
ledger=${REVIEW_INBOX_LEDGER:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/review-inbox-posted.tsv}
switch=${AI_DISCLOSURE:-$HOME/.claude/ai-disclosure.on}
touch "$ledger"
# One run at a time: two posting sessions would both pass the ledger check before either writes it.
mkdir "$ledger.lock" 2>/dev/null || { echo "another post-approved.sh run holds $ledger.lock (remove it if none runs)" >&2; exit 3; }
trap 'rmdir "$ledger.lock"' EXIT
err=$(mktemp); trap 'rmdir "$ledger.lock"; rm -f "$err"' EXIT
shopt -s nullglob
for f in "$dir"/*.json; do
  id=$(basename "$f" .json)
  # Keyed on the row alone: a row posted once is never posted again, whatever was decided since.
  if prev=$(awk -F'\t' -v id="$id" '$1 == id { print $3; exit }' "$ledger") && [ -n "$prev" ]; then
    echo "posted $id $prev (earlier run; mark it in the inbox, or check the PR if unknown)"; continue
  fi
  v=$(bash "$here/verify-row.sh" "$f") || { echo "skipped $id: ${v#rejected: }"; continue; }
  body=$(jq -r .final "$f")
  if [ -f "$switch" ]; then
    marker=$(head -c 200 "$switch" | tr -d '\n'); marker=${marker:-[AI-generated]}
    case "$body" in *"$marker"*) ;; *) body="$marker"$'\n\n'"$body" ;; esac
  fi
  args=(pr comment create "$(jq -r '.pr | floor' "$f")" --project "$(jq -r .project "$f")" --repo "$(jq -r .repo "$f")" --body-file -)
  file=$(jq -r '.file // ""' "$f"); line=$(jq -r '.line // "" | if type == "number" then floor else . end' "$f")
  if [ -n "$file" ]; then
    args+=(--path "$file")
    [ -n "$line" ] && args+=(--line "$line" --line-type "$(jq -r '.lineType // "ADDED"' "$f")" --file-type "$(jq -r '.fileType // "TO"' "$f")")
  fi
  # Ledgered before the outcome is known: a CLI that fails after Bitbucket took the comment must not lead to a
  # second post. A failure leaves it "unknown"; to retry, check the PR has no such comment and delete its line.
  printf '%s\t%s\t%s\n' "$id" "$(jq -r .decisionHash "$f")" unknown >> "$ledger"
  if ! out=$(printf '%s' "$body" | "${cli[@]}" "${args[@]}" 2>"$err"); then echo "failed $id: $(tail -n 3 "$err" | tr '\n' ' ')"; continue; fi
  cid=$(jq -r '.id // empty' <<<"$out" 2>/dev/null)
  [ -n "$cid" ] || { echo "failed $id: no comment id in the CLI's answer, check the PR: $(head -c 200 <<<"$out")"; continue; }
  awk -F'\t' -v OFS='\t' -v id="$id" -v cid="$cid" '$1 == id { $3 = cid } 1' "$ledger" > "$ledger.tmp" && mv "$ledger.tmp" "$ledger"
  echo "posted $id $cid"
done

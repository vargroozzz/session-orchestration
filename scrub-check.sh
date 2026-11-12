#!/usr/bin/env bash
# Fails when a file in the repo names a person, a company or a private path: the deny pattern (an ERE,
# case-insensitive) from $SCRUB_DENY, else the untracked file ${XDG_CONFIG_HOME:-~/.config}/scrub-deny, plus a
# macOS home path always. The pattern is kept out of the repo because it spells out what it hides; CI gets it from
# the SCRUB_DENY secret. A known hit is listed in scrub-allow.txt as `path<TAB>the whole line`; an allow-list line
# that no longer matches fails too, so the list can't go stale. Run from anywhere in the repo; CI
# runs it. Prints "ok" or each problem. No pattern: fails, except on a fork's pull request (SCRUB_FORK_PR=true, set
# by CI: it gets no secrets), where it says so and passes.
set -u
cd "$(git rev-parse --show-toplevel)" || exit 1
private=${SCRUB_DENY:-$(grep -v '^#' "${XDG_CONFIG_HOME:-$HOME/.config}/scrub-deny" 2>/dev/null | grep -m1 .)}
if [ -z "$private" ]; then
  [ "${SCRUB_FORK_PR:-}" = true ] && { echo "a fork's pull request has no SCRUB_DENY secret: skipped"; exit 0; }
  echo "no deny pattern: set SCRUB_DENY or write one ERE line to ${XDG_CONFIG_HOME:-~/.config}/scrub-deny"
  exit 1
fi
deny="$private|/[U]sers/"
allow=scrub-allow.txt
hits=$(git ls-files -co --exclude-standard -z | grep -zv -e "^$allow\$" |
  xargs -0 grep -IinE "$deny" -- 2>/dev/null | sed -E 's/^([^:]*):[0-9]+:/\1\t/')
listed=$(grep -v '^#' "$allow" 2>/dev/null | grep .)
bad=0
while IFS= read -r h; do
  [ -n "$h" ] && ! grep -qxF -- "$h" <<<"$listed" && { echo "deny-list hit: ${h/$'\t'/: }"; bad=1; }
done <<<"$hits"
while IFS= read -r a; do
  [ -n "$a" ] && ! grep -qxF -- "$a" <<<"$hits" && { echo "stale $allow line: ${a/$'\t'/: }"; bad=1; }
done <<<"$listed"
[ "$bad" = 0 ] && echo ok
exit "$bad"

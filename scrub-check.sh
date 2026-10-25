#!/usr/bin/env bash
# Fails when a file in the repo names a person, a company or a private path: the deny list below, case-insensitive,
# with vpn and greg as whole words. A known hit is listed in scrub-allow.txt as `path<TAB>the whole line`; an
# allow-list line that no longer matches fails too, so the list can't go stale. Run from anywhere in the repo;
# plugin-release and CI run it. Prints "ok" or each problem.
set -u
cd "$(git rev-parse --show-toplevel)" || exit 1
deny='btigroup|sdm-[0-9]|@first/|eduard|/Users/|(^|[^[:alnum:]_])(vpn|greg)([^[:alnum:]_]|$)'
allow=scrub-allow.txt
hits=$(git ls-files -co --exclude-standard -z | grep -zv -e '^scrub-check\.sh$' -e "^$allow\$" |
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

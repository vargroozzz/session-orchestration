# Feature docs_watch (features/docs-watch.md): the sweep's `docs` notices source. Run from the project root as
# `bash docs-watch.sh PATTERN FILE…`: one line per watched docs page (a slug PATTERN matches) that neither of a
# FILE's lists, "Last reviewed … against:" and "Skipped …:", has. The index (platform.claude.com's and
# code.claude.com's llms.txt, as slugs:
# a platform page's path after docs/en/ less its first folder, a Claude Code page's as cc/<path>) is fetched at most
# once a day, tried or not, into one cache every project shares; a failed fetch keeps the last one, no index prints nothing.
# shortcut: dropping a platform page's first folder could give two pages one slug; kept so lists in that form still
# match, until two pages collide.
export LC_ALL=C   # the shared cache and each comparison sort alike
pattern=$1; shift
C=~/.cache/session-status idx=~/.cache/session-status/docs-index.txt
mkdir -p "$C"
if [ -z "$(find "$C/docs-index.tried" -mtime -1 2>/dev/null)" ]; then
  touch "$C/docs-index.tried"; t=$(mktemp "$C/docs-index.XXXXXX")
  { curl -fsSL --max-time 20 https://platform.claude.com/llms.txt > "$t.p" &
    curl -fsSL --max-time 20 https://code.claude.com/docs/llms.txt > "$t.c" & wait; }
  # Both fetched, each with pages, or the last index stays: a half index would hide every page of the other site.
  p=$(grep -oE 'platform\.claude\.com/docs/en/[A-Za-z0-9._/-]+' "$t.p" | sed 's|.*/docs/en/||; s|\.*$||; s|\.md$||; s|/$||' | grep / | cut -d/ -f2-)
  c=$(grep -oE 'code\.claude\.com/docs/en/[A-Za-z0-9._/-]+\.md' "$t.c" | sed 's|.*/docs/en/|cc/|; s|\.md$||')
  [ -n "$p" ] && [ -n "$c" ] && printf '%s\n%s\n' "$p" "$c" | sort -u > "$t" && mv "$t" "$idx"
  rm -f "$t" "$t.p" "$t.c"
fi
[ -s "$idx" ] || exit 0
for doc in "$@"; do
  f=$doc; [[ $f == '~'/* ]] && f=$HOME/${f#'~/'}
  [ -f "$f" ] || { echo "docs watch: $doc is missing, so nothing is checked against it (tell the user: fix docs_watch.files or its path)"; continue; }
  # Each list runs from its "Last reviewed … against:" or "Skipped …:" line to the first line ending in a period,
  # that line too; each is read once, so prose naming either later adds nothing.
  grep -E -- "$pattern" "$idx" | comm -23 - <(tr -d '\r' < "$f" |
      awk '!r && /Last reviewed .* against:/ { r = on = 1; sub(/.*against:/, "") }
           !s && /^Skipped[^:]*:/ { s = on = 1; sub(/^[^:]*:/, "") }
           on { print; if (/\.$/) on = 0 }' |
      tr ', `' '\n\n\n' | sed 's/\.$//' | grep -E '^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)+$' | sort -u) |
    D=$doc awk '{ print "docs watch: new page " $0 ", re-review " ENVIRON["D"] " (offer the user a review-kind session: docs-watch.md, Acting on a notice)" }'
done
exit 0

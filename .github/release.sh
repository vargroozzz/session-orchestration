#!/usr/bin/env bash
# release.sh [--dry-run | --push]: number every plugin main changed since its last release, in one release commit
# `<plugin> <version>[, <plugin> <version>]: <text>` on HEAD, <text> being the newest such commit's subject without
# its `<plugin>: ` prefix. The release workflow runs `--push` on each push to main; --dry-run prints the commit it
# would make and changes nothing.
# A plugin is pending when a commit after the last one that changed its plugin.json "version" touches
# plugins/<plugin>/. It gets the next minor, or the next patch when every pending commit carries a `Release: patch`
# trailer. A branch that bumped version in its last commit to the plugin leaves nothing pending, so it keeps its
# number; a new plugin keeps the version it came with; a deleted one has nothing to number.
# Everything is read from main itself, so a rerun, a dropped run or two pushes close together number each change once,
# and the run on the release commit's own push finds nothing to do (no loop).
# --push: push HEAD to origin main; when origin moved meanwhile, reset to it and number again (3 tries). It resets the
# checkout: CI only.
set -euo pipefail
mode=${1:-}
case "$mode" in --dry-run | --push | "") ;; *) echo "release.sh: unknown option $mode" >&2; exit 2 ;; esac
cd "$(git rev-parse --show-toplevel)"

stamp() {
  local f p last pending c part old new stamped=() files=() names=()
  for f in plugins/*/.claude-plugin/plugin.json; do
    git cat-file -e "HEAD:$f" 2>/dev/null || continue
    p=${f#plugins/} p=${p%%/*}
    # the newest commit that changed .version's value (or added the file); a mere edit of the version line isn't one
    last=
    for c in $(git log --format=%H HEAD -- "$f"); do
      [ "$(git show "$c:$f" | jq -r .version)" = "$(git show "$c^:$f" 2>/dev/null | jq -r .version 2>/dev/null)" ] || { last=$c; break; }
    done
    pending=$(git log --format=%H "$last..HEAD" -- "plugins/$p/")
    [ -n "$pending" ] || continue
    # one trailer line per pending commit: patch only when every one says so
    part=minor
    [ "$(git log --format='%(trailers:key=Release,valueonly)' "$last..HEAD" -- "plugins/$p/" | grep -ciE '^[[:space:]]*patch[[:space:]]*$')" \
      != "$(wc -l <<<"$pending" | tr -d ' ')" ] || part=patch
    old=$(jq -r .version "$f")
    [[ "$old" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "release.sh: $f version '$old' isn't X.Y.Z" >&2; exit 1; }
    new=$(awk -F. -v part="$part" '{ if (part == "patch") print $1 "." $2 "." $3 + 1; else print $1 "." $2 + 1 ".0" }' <<<"$old")
    stamped+=("$p $new") files+=("$f") names+=("$p")
  done
  if [ ${#stamped[@]} -eq 0 ]; then echo "nothing to release"; return; fi
  local title subject
  title=$(IFS=,; echo "${stamped[*]}" | sed 's/,/, /g')
  # strip only a `<plugin>: ` or `<plugin> <version>: ` prefix naming a stamped plugin
  subject=$(git log -1 --format=%s HEAD -- "${files[@]%/.claude-plugin/plugin.json}" |
    sed -E "s/^($(IFS='|'; echo "${names[*]}"))( [0-9][^ :]*)?: //")
  if [ "$mode" = --dry-run ]; then echo "would commit: $title: $subject"; return; fi
  local i v
  for i in "${!files[@]}"; do
    v=${stamped[$i]##* }
    # the first "version" only (the top-level one; jq below checks): a nested one stays. awk, not sed -i: BSD and GNU differ
    awk -v v="$v" '!d && match($0, /"version"[[:space:]]*:[[:space:]]*"[^"]*"/) {
      s = substr($0, RSTART, RLENGTH); sub(/"[^"]*"$/, "\"" v "\"", s)
      $0 = substr($0, 1, RSTART - 1) s substr($0, RSTART + RLENGTH); d = 1 } 1' "${files[$i]}" > "${files[$i]}.tmp"
    mv "${files[$i]}.tmp" "${files[$i]}"
    [ "$(jq -r .version "${files[$i]}")" = "$v" ] || { echo "release.sh: couldn't set ${files[$i]} to $v" >&2; exit 1; }
  done
  git add -- "${files[@]}"
  git commit -qm "$title: $subject"
  echo "committed: $title: $subject"
}

if [ "$mode" != --push ]; then stamp; exit; fi
for try in 1 2 3; do
  stamp
  # nothing stamped and origin unchanged: an up-to-date push, exit 0
  git push -q origin HEAD:main && exit 0
  git fetch -q origin main
  # origin didn't move: refused for another reason (protection, credentials), and git said why above
  ! git merge-base --is-ancestor origin/main HEAD || { echo "release.sh: push refused, not a race" >&2; exit 1; }
  echo "release.sh: push $try lost a race, numbering again on origin/main" >&2
  git reset -q --hard origin/main
done
exit 1

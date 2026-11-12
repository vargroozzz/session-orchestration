#!/usr/bin/env bash
# release.sh against a scratch repo and a bare origin: numbering rules, idempotence, and a push that races another.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail() { echo "release.test: $1${2:+: $2}" >&2; exit 1; }
rel() { "$here/release.sh" "$@"; }
subj() { git -C "${1:-.}" log -1 --format=%s; }
ver() { jq -r .version "plugins/$1/.claude-plugin/plugin.json"; }
commit() { git add -A && git commit -qm "$@"; }

git init -q --bare -b main "$t/origin.git"
git clone -q "$t/origin.git" "$t/repo" 2>/dev/null
cd "$t/repo"
mkdir -p plugins/demo/.claude-plugin plugins/other/.claude-plugin
printf '{\n  "name": "demo",\n  "version": "1.0.0"\n}\n' > plugins/demo/.claude-plugin/plugin.json
printf '{\n  "name": "other",\n  "version": "0.1.0"\n}\n' > plugins/other/.claude-plugin/plugin.json
commit init

# a new plugin keeps the version it came with; a change outside plugins/ numbers nothing
[ "$(rel)" = "nothing to release" ] || fail "new plugins are released as they came"
echo x > README.md && commit "docs: readme"
[ "$(rel)" = "nothing to release" ] || fail "a non-plugin change numbered something"

# a change gets the next minor and the subject without its prefix; --dry-run changes nothing
echo a > plugins/demo/a && commit "demo: add a"
head=$(git rev-parse HEAD)
[ "$(rel --dry-run)" = "would commit: demo 1.1.0: add a" ] || fail "dry run" "$(rel --dry-run)"
[ "$(git rev-parse HEAD)" = "$head" ] && git diff --quiet || fail "dry run changed the checkout"
rel >/dev/null
[ "$(subj)" = "demo 1.1.0: add a" ] && [ "$(ver demo)" = 1.1.0 ] || fail "minor" "$(subj)"
grep -q '"name": "demo",' plugins/demo/.claude-plugin/plugin.json || fail "plugin.json reformatted"
# the run on the release commit itself finds nothing (no loop)
[ "$(rel)" = "nothing to release" ] || fail "a rerun numbered again"

# patch only when every pending commit says so
echo b > plugins/demo/b && git add -A && git commit -qm "demo: fix b" -m "Release: patch"
echo c > plugins/demo/c && git add -A && git commit -qm "demo: fix c" -m "release: Patch"
rel >/dev/null
[ "$(subj)" = "demo 1.1.1: fix c" ] || fail "patch" "$(subj)"
echo d > plugins/demo/d && git add -A && git commit -qm "demo: fix d" -m "Release: patch"
echo e > plugins/demo/e && commit "demo: add e"
rel >/dev/null
[ "$(subj)" = "demo 1.2.0: add e" ] || fail "a minor among patches" "$(subj)"

# two plugins in one push: one release commit names both; the subject is the newest plugin commit's
echo f > plugins/demo/f && commit "demo: add f"
echo g > plugins/other/g && commit "other: add g"
echo y > README.md && commit "docs: readme again"
rel >/dev/null
[ "$(subj)" = "demo 1.3.0, other 0.2.0: add g" ] || fail "two plugins" "$(subj)"

# a branch that bumped version in its last commit keeps its number
echo h > plugins/demo/h && sed -E 's/1\.3\.0/2.0.0/' plugins/demo/.claude-plugin/plugin.json > j && mv j plugins/demo/.claude-plugin/plugin.json &&
  commit "demo 2.0.0: big h"
[ "$(rel)" = "nothing to release" ] && [ "$(ver demo)" = 2.0.0 ] || fail "a self-numbered branch was renumbered"

# an edit that touches the version line without changing it is a change, not a release; a nested "version" stays;
# a subject not led by a stamped plugin's name stays whole
printf '{\n  "name": "demo",\n  "version": "2.0.0",\n  "dep": { "version": "9.9.9" }\n}\n' > plugins/demo/.claude-plugin/plugin.json &&
  commit 'Revert "demo: big h"'
rel >/dev/null
[ "$(subj)" = 'demo 2.1.0: Revert "demo: big h"' ] || fail "version-line edit / revert subject" "$(subj)"
[ "$(jq -r .dep.version plugins/demo/.claude-plugin/plugin.json)" = 9.9.9 ] || fail "nested version overwritten"
# drops the comma off the version line, same value
printf '{\n  "name": "demo",\n  "version": "2.1.0"\n}\n' > plugins/demo/.claude-plugin/plugin.json && commit "demo: tidy"
rel >/dev/null
[ "$(subj)" = "demo 2.2.0: tidy" ] || fail "tidy" "$(subj)"

# a deleted plugin has nothing to number
git rm -rq plugins/other && commit "other: remove"
[ "$(rel)" = "nothing to release" ] || fail "a deleted plugin was numbered"
git push -q origin main

# --push when origin moved meanwhile (a second push landed first): number again on origin, both changes once
echo i > plugins/demo/i && commit "demo: add i"
git push -q origin main
git clone -q "$t/origin.git" "$t/other" 2>/dev/null
(cd "$t/other" && echo j > plugins/demo/j && git add -A && git -c user.email=t@t -c user.name=t commit -qm "demo: add j" &&
  git push -q origin main)
out=$(rel --push 2>&1) || fail "--push after a race" "$out"
grep -q 'push 1 lost a race' <<<"$out" || fail "the race didn't happen" "$out"
[ "$(subj "$t/origin.git")" = "demo 2.3.0: add j" ] || fail "race release" "$(subj "$t/origin.git")"
[ "$(git -C "$t/origin.git" log --format=%s main | grep -c '^demo 2\.3\.0')" = 1 ] || fail "2.3.0 twice"
[ "$(rel --push)" = "nothing to release" ] || fail "a rerun after the push numbered again"

# a push refused for another reason (protection) fails at once, named as such, and leaves origin alone
echo k > plugins/demo/k && commit "demo: add k" && git push -q origin main
before=$(git -C "$t/origin.git" rev-parse main)
printf '#!/bin/sh\necho "protected branch"; exit 1\n' > "$t/origin.git/hooks/pre-receive" && chmod +x "$t/origin.git/hooks/pre-receive"
out=$(rel --push 2>&1) && fail "a refused push should fail"
grep -q 'not a race' <<<"$out" && ! grep -q 'lost a race' <<<"$out" || fail "refused push" "$out"
[ "$(git -C "$t/origin.git" rev-parse main)" = "$before" ] || fail "origin moved on a refused push"
rm "$t/origin.git/hooks/pre-receive"

# a version that isn't X.Y.Z stops the release
printf '{"version":"1.0.0-beta"}\n' > plugins/demo/.claude-plugin/plugin.json && commit "demo 1.0.0-beta: odd"
echo l > plugins/demo/l && commit "demo: add l"
out=$(rel 2>&1) && fail "a non-X.Y.Z version should stop" "$out"
grep -q "isn't X.Y.Z" <<<"$out" || fail "odd version" "$out"
echo "release.test: ok"

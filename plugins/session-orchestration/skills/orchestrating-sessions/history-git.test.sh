#!/usr/bin/env bash
# Self-check for history-git: the Stop hook's repo (git dir outside the folder, pre-push refusing, a file over 1 MB
# left out), a commit per changed turn and none otherwise, `versions` feeding pending's --scan and history LABEL, `run`,
# and adopting a repo set up by hand. Run: bash history-git.test.sh
set -euo pipefail; unset XDG_CONFIG_HOME XDG_STATE_HOME CLAUDE_CODE_SESSION_ID GIT_DIR GIT_WORK_TREE
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; trap 'echo "failed at line $LINENO: $BASH_COMMAND" >&2' ERR
export HOME=$tmp CLAUDE_CONFIG_DIR=$tmp/cfg XDG_CACHE_HOME=$tmp/cache
fail() { echo "history-git.test: $*"; exit 1; }
mkroot() {
  local r; r=$(mkdir -p "$tmp/$1/.claude" "$tmp/$1/notes" "$tmp/$1/$2" && cd "$tmp/$1" && pwd -P)
  echo '{"pending": {"file": "notes/pending.md"}}' > "$r/.claude/coordination.local.json"
  printf -- '- Replies folder: `%s`\n' "$2" > "$r/CLAUDE.md"; echo "$r"
}
root=$(mkroot proj replies); P=$root/notes/pending.md; R=$root/replies
stop() { printf '{"session_id":"%s-1111","cwd":"%s"}' "${2:-aaaabbbb}" "$1" | bash "$here/history-git" commit; }
H=$tmp/.local/state/session-orchestration/history
GR=$H/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$R").git; GP=$H/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$root/notes").git
log() { git --git-dir="$1" log --format=%s 2>/dev/null; }

printf '# Pending\n\n- 2026-11-01 ABC-1: first wording\n- 2026-11-01 ABC-2: goes soon\n' > "$P"
echo 'unrelated' > "$root/notes/other.md"
echo 'report one' > "$R/ABC-1.md"
head -c 1100000 /dev/zero > "$R/dump.json"
stop "$root"
[ -d "$GR" ] && [ -d "$GP" ] && [ ! -e "$R/.git" ] && [ ! -e "$root/notes/.git" ] || fail "repos not made outside the folders"
[ "$(log "$GR")" = "aaaabbbb: ABC-1.md" ] || fail "replies commit: $(log "$GR")"
[ "$(git --git-dir="$GP" ls-files)" = pending.md ] && [ -z "$(git --git-dir="$GP" remote)" ] || fail "handoff repo files: $(git --git-dir="$GP" ls-files)"
grep -qx /dump.json "$GR/info/exclude" || fail "a dump wasn't left out"
! "$GR/hooks/pre-push" 2>/dev/null || fail "pre-push lets a push through"

stop "$root"   # nothing changed: no commit
[ "$(log "$GR" | wc -l | tr -d ' ')" = 1 ] && [ "$(log "$GP" | wc -l | tr -d ' ')" = 1 ] || fail "an unchanged turn committed"

# a Bash-style write (no Edit) shows the same: reworded, one gone, a reply deleted
printf '# Pending\n\n- 2026-11-01 ABC-1: second wording\n' > "$P"; rm "$R/ABC-1.md"; echo two > "$R/ABC-3.md"
stop "$root" ccccdddd
[ "$(log "$GP" | head -1)" = "ccccdddd: pending.md" ] && [ "$(git --git-dir="$GR" ls-files)" = ABC-3.md ] ||
  fail "second commit: $(log "$GP") / $(git --git-dir="$GR" ls-files)"

# versions → pending's --scan reads git, not transcripts
[ "$(bash "$here/history-git" versions "$P" | wc -l | tr -d ' ')" = 2 ] || fail "versions"
scan=$(cd "$root" && bash "$here/pending" history --scan)
grep -q $'\tccccdddd\tABC-1\tABC-1\tchange\t2026-11-01 ABC-1: second wording$' <<<"$scan" &&
  grep -q $'\tccccdddd\tABC-2\tABC-2\tgone\tunknown$' <<<"$scan" || fail "scan from git: $scan"
hist=$(cd "$root" && bash "$here/pending" history ABC-1)
[ "$(grep -c '^- ' <<<"$hist")" = 2 ] && grep -q '(aaaabbbb) 2026-11-01 ABC-1: first wording' <<<"$hist" || fail "history from git: $hist"
grep -q 'seeded from git and transcripts: 1 open' <<<"$(cd "$root" && bash "$here/pending" history --seed)" || fail "seed from git"

# run: git on a folder's repo
[ "$(cd "$root" && bash "$here/history-git" run replies log --format=%s | wc -l | tr -d ' ')" = 2 ] || fail "run replies"
rc=0; (cd "$root" && bash "$here/history-git" run nope) >/dev/null || rc=$?; [ $rc = 2 ] || fail "run's usage"

# a repo set up by hand (the folder holding the replies, no remote) is adopted, not shadowed
root=$(mkroot adopt docs/replies); R=$root/docs/replies
git -C "$root/docs" init -q; echo mine > "$root/docs/notes.md"; git -C "$root/docs" add notes.md; printf '# Pending\n\n- 2026-11-01 X-1: x\n' > "$root/notes/pending.md"; echo r > "$R/X-1.md"
stop "$root"
[ "$(git -C "$root/docs" log --format=%s)" = "aaaabbbb: X-1.md" ] && [ ! -d "$H/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$R").git" ] ||
  fail "adopting: $(git -C "$root/docs" log --format=%s)"
[ "$(git -C "$root/docs" diff --cached --name-only)" = notes.md ] || fail "the user's staged change was committed"
# a repo holding the project root is never adopted: the project's handoff gets its own repo
mkdir -p "$tmp/mono"; git -C "$tmp/mono" init -q; root=$(mkroot mono/sub r)   # the file in the root, the repo its parent
echo '{"pending": {"file": "pending.md"}}' > "$root/.claude/coordination.local.json"
printf '# Pending\n\n- 2026-11-01 M-1: m\n' > "$root/pending.md"; stop "$root"
[ -z "$(git -C "$tmp/mono" log --oneline 2>/dev/null)" ] && [ -d "$H/$(sed 's/[^A-Za-z0-9]/-/g' <<<"$root").git" ] || fail "a repo above the root was adopted"
echo "history-git.test: ok"

#!/usr/bin/env bash
# Self-check for no-question-box.sh. Run: bash no-question-box.test.sh  (prints "ok" or the failure).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); unset CLAUDE_PROJECT_DIR
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; t=$(cd "$t" && pwd -P)
# A session started in $t/home; another repo with its own worktree in $t/other; a symlink out of home's.
mkdir -p "$t/home/.claude/worktrees/fix-1" "$t/other/.claude/worktrees/x" "$t/app/.worktrees/PROJ-1"
ln -s "$t/other/.claude/worktrees/x" "$t/home/.claude/worktrees/link"
# decision <attended> <mode> <tool_input json>: "deny" or "allow". The hook input's cwd is $t/home.
decision() {
  local env=(env CLAUDE_CODE_SESSION_ATTENDED="$1")
  [ "$1" != unset ] || env=(env -u CLAUDE_CODE_SESSION_ATTENDED)
  out=$( { [ "$3" = garbage ] && echo 'not json' || jq -nc --argjson i "$3" --arg cwd "$t/home" '{cwd: $cwd, tool_input: $i}'; } |
    "${env[@]}" bash "$here/no-question-box.sh" "$2" 2>/dev/null)
  [ -n "$out" ] && jq -r .hookSpecificOutput.permissionDecision <<<"$out" || echo allow
}
check() { got=$(decision "$1" "$2" "$3"); [ "$got" = "$4" ] || { echo "FAIL attended=$1 $2 $3: $got, want $4"; exit 1; }; }
check 0 ask '{}' deny
check 0 plan '{}' deny
check 0 worktree "{\"path\":\"$t/app/.worktrees/PROJ-1\"}" deny
check 0 worktree '{"name":"fix-1"}' allow
check 0 worktree "{\"path\":\"$t/home/.claude/worktrees/fix-1\"}" allow
check 0 worktree '{"path":".claude/worktrees/fix-1"}' allow
check 0 worktree "{\"path\":\"$t/other/.claude/worktrees/x\"}" deny   # another repo's: still prompts
check 0 worktree '{"path":".claude/worktrees/link"}' deny               # symlink out of home's
check 0 worktree "{\"path\":\"$t/home/.claude/worktrees/../../app/.worktrees/PROJ-1\"}" deny
check 0 worktree '{"path":".claude/worktrees/missing"}' deny
check 0 worktree "{\"path\":\"$t/home/.claude/worktrees\"}" deny
check 0 worktree garbage deny
check unset worktree "{\"path\":\"$t/app/.worktrees/PROJ-1\"}" allow
check 1 worktree "{\"path\":\"$t/app/.worktrees/PROJ-1\"}" allow
check 1 ask '{}' allow
check '' plan '{}' allow
# No cwd in the input: $PWD is the start dir.
out=$(cd "$t/home" && jq -nc '{tool_input: {path: ".claude/worktrees/fix-1"}}' | CLAUDE_CODE_SESSION_ATTENDED=0 bash "$here/no-question-box.sh" worktree)
[ -z "$out" ] || { echo "FAIL no cwd in input: $out"; exit 1; }
# CLAUDE_PROJECT_DIR wins over a cwd that moved (into a worktree, a subdir): a sibling worktree stays allowed.
mkdir -p "$t/home/.claude/worktrees/b"
out=$(jq -nc --arg cwd "$t/home/.claude/worktrees/fix-1" --arg p "$t/home/.claude/worktrees/b" '{cwd: $cwd, tool_input: {path: $p}}' |
  CLAUDE_PROJECT_DIR=$t/home CLAUDE_CODE_SESSION_ATTENDED=0 bash "$here/no-question-box.sh" worktree)
[ -z "$out" ] || { echo "FAIL moved cwd: $out"; exit 1; }
echo ok

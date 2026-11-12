#!/usr/bin/env bash
# Self-check for coordinator-guard.sh. Run: bash coordinator-guard.test.sh  (prints "ok" or the failure).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
root=$(mkdir -p "$tmp/proj/.claude/orchestration" "$tmp/proj/src" && cd "$tmp/proj" && pwd -P)
echo '{"pending":{"file":"docs/pending.md"}}' > "$root/.claude/coordination.local.json"
printf -- '- Replies folder (reports): `replies/`.\n- Project memory: `docs/mem/memory.md`. Handoff: `x.md`.\n' > "$root/CLAUDE.md"
mkdir -p "$tmp/.cache/session-status"; echo 'coordinator - - 0 0' > "$tmp/.cache/session-status/handoff-c1.kind"
printf 'task K-1 - 0 0\nre\n' > "$tmp/.cache/session-status/handoff-w1.kind"
# g SID TOOL INPUT_JSON: the hook's decision ("allow" when it prints nothing)
g() { local o; o=$(jq -nc --arg s "$1" --arg t "$2" --argjson i "$3" --arg c "$root/src" '{session_id: $s, tool_name: $t, tool_input: $i, cwd: $c}' |
  HOME=$tmp XDG_CACHE_HOME=$tmp/.cache XDG_CONFIG_HOME=$tmp/.config bash "$here/coordinator-guard.sh"); [ -n "$o" ] && jq -r '.hookSpecificOutput.permissionDecision' <<<"$o" || echo allow; }
w() { g c1 Write "{\"file_path\":\"$1\",\"content\":\"x\"}"; }
check() { [ "$1" = "$2" ] || { echo "FAIL $3: got $1, want $2"; exit 1; }; }
check "$(g c1 Bash '{"command":"cd /x && ls"}')" deny 'cd first'
check "$(g c1 Bash '{"command":"  pushd /x"}')" deny pushd
check "$(g c1 Bash '{"command":"ls /x; cd /y"}')" allow 'cd later in a chain (prefix only)'
check "$(g c1 Bash '{"command":"cdk deploy"}')" allow 'a word starting cd'
check "$(g w1 Bash '{"command":"cd /x"}')" allow 'a task session'
check "$(g nokind Bash '{"command":"cd /x"}')" allow 'no kind cached'
check "$(w "$root/src/a.ts")" deny 'a project file'
check "$(w "$root/CLAUDE.md")" deny 'CLAUDE.md'
check "$(g c1 Edit "{\"file_path\":\"$root/src/a.ts\"}")" deny 'Edit'
check "$(g c1 Write '{"file_path":"../src/b.ts"}')" deny 'a relative path'
check "$(w "$root/.claude/orchestration/memory.md")" allow '.claude/'
check "$(w "$root/.claude/settings.local.json")" deny '.claude/ settings'
check "$(w "$root/.claude/hooks/x.sh")" deny '.claude/hooks/'
check "$(jq -nc --arg c "$root/src" --arg p "$root/src/a.ts" '{session_id: "c1", agent_id: "a1", tool_name: "Write", tool_input: {file_path: $p}, cwd: $c}' |
  HOME=$tmp XDG_CACHE_HOME=$tmp/.cache bash "$here/coordinator-guard.sh")" '' 'a subagent of the coordinator'
check "$(w "$root/replies/PROJ-1.md")" allow 'the replies folder'
check "$(w "$root/docs/pending.md")" allow 'pending.file'
check "$(w "$root/docs/other.md")" deny 'beside pending.file'
check "$(w "$root/docs/mem/memory.md")" allow 'the memory file'
check "$(w "$root/docs/mem/memory/misc.md")" allow 'a memory topic file'
check "$(w "$root/docs/mem/plan.md")" deny 'beside the memory file'
check "$(w "$tmp/scratch.md")" allow 'outside the root'
check "$(w "$root/.claude/../src/a.ts")" deny 'a .. out of .claude/'
check "$(w "$root/.claude/worktrees/PROJ-1/src/a.ts")" deny 'a task worktree under .claude/'
check "$(w "$root/.worktrees/PROJ-1/replies/x.md")" deny 'a task worktree'
ln -s "$root" "$tmp/link"; check "$(w "$tmp/link/src/a.ts")" deny 'through a symlink'
printf -- '- Never edit memory by hand: `scripts/x.sh`.\n' > "$root/CLAUDE.local.md"
check "$(w "$root/scripts/x.sh")" deny 'a line that only mentions memory'
check "$(g w1 Write "{\"file_path\":\"$root/src/a.ts\"}")" allow 'a task session writing'
echo ok

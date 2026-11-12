#!/usr/bin/env bash
# PreToolUse in a coordinator session (context-watch.sh's cached kind): two of SKILL.md's Rules as checks.
# - Bash starting with `cd`: refused (the Bash tool keeps it, and `claude --bg` then starts outside the project).
#   Only the prefix: a `cd` later in a chain isn't parsed out of the shell text.
# - Edit/Write/MultiEdit/NotebookEdit of a file inside the project root: allowed only in .claude/ (not its settings*.json
#   or hooks/), the replies folder, the handoff file (pending.file) and the project memory CLAUDE.md names (the file and its memory/ folder); never in
#   a task's worktree (.worktrees/, .claude/worktrees/). The path is resolved first (`..`, symlinks).
#   Outside the root (scratch, ~/.claude) is not the rule's business.
# Any other session pays one bash start and a file test.
input=$(cat)
[[ $input =~ \"agent_id\":\ *\"[^\"]+\" ]] && exit 0   # a subagent: its cd and edits aren't the coordinator's
[[ $input =~ \"session_id\":\ *\"([A-Za-z0-9_-]+)\" ]] || exit 0
k=${XDG_CACHE_HOME:-$HOME/.cache}/session-status/handoff-${BASH_REMATCH[1]}.kind
[ -f "$k" ] && read -r kind _ < "$k" && [ "$kind" = coordinator ] || exit 0

deny() { jq -nc --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'; exit 0; }
{ read -r tool; read -r cwd; read -r path; } < <(jq -r '.tool_name // "", .cwd // "", (.tool_input.file_path // .tool_input.notebook_path // "")' <<<"$input")
if [ "$tool" = Bash ]; then
  cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
  [[ $cmd =~ ^[[:space:]]*(cd|pushd)([[:space:]]|$) ]] || exit 0
  deny "Coordinator rule: never cd in your shell; use absolute paths. The Bash tool keeps a cd across calls, and claude --bg then starts the new session in that folder, outside the project's settings. Run it again without the cd."
fi
[ -n "$path" ] || exit 0
here=$(cd "$(dirname "$0")" && pwd)
cd "${cwd:-.}" 2>/dev/null || exit 0
. "$here/../lib.sh"
root=$(find_root 2>/dev/null) && [ -n "$root" ] || exit 0
# realpath of a file that may not exist yet: like find_root's pwd -P, so /tmp and /private/tmp compare equal
real() { python3 -I -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
path=$(real "$path") || exit 0
case $path in "$root"/*) ;; *) exit 0 ;; esac
under() { [ -n "$2" ] && case $1 in "${2%/}"/*) true ;; *) false ;; esac; }
cd "$root" && ROOT=$root
abs() { local r=${1/#\~/$HOME}; case $r in '') ;; /*) real "$r" ;; *) real "$root/$r" ;; esac; }
if ! under "$path" "$root/.claude/worktrees" && ! under "$path" "$root/.worktrees"; then
  # .claude/ but its settings and hooks: those fixes are a session's too (SKILL.md, Rules)
  under "$path" "$root/.claude" && case ${path#"$root/.claude/"} in settings*.json|hooks/*) ;; *) exit 0 ;; esac
  under "$path" "$(abs "$(replies_path)")" && exit 0
  p=$(config pending.file 2>/dev/null) && [ -n "$p" ] && [ "$path" = "$(abs "$p")" ] && exit 0
  # the project memory: CLAUDE.md's "Project memory: `PATH`" (project-memory's setup line)
  m=$(abs "$(sed -nE 's/^[^`]*[Pp]roject memory[^`]*`([^`]+)`.*/\1/p' CLAUDE.md CLAUDE.local.md 2>/dev/null | head -1)")
  [ -n "$m" ] && { [ "$path" = "$m" ] || under "$path" "$(dirname "$m")/memory"; } && exit 0
fi
deny "Coordinator rule: the only files you change are the memory files, the handoff file and your handover (SKILL.md, Rules). ${path#"$root"/} is a session's to change, however small: give it to the session that owns it, or start one."

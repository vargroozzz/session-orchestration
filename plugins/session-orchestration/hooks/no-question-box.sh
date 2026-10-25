#!/usr/bin/env bash
# PreToolUse on AskUserQuestion ($1=ask), EnterPlanMode ($1=plan) and EnterWorktree ($1=worktree): in a
# background session each can end in a wait for the user (the question box, plan approval, or the
# "permission-root relocation" prompt EnterWorktree raises for a worktree outside the session's own
# .claude/worktrees/). While it waits no cross-session message arrives, so a coordinator can't relay the
# answer. Deny them there.
# EnterWorktree with `name`, or a `path` under <start dir>/.claude/worktrees/ ($CLAUDE_PROJECT_DIR, else the
# hook input's cwd, else $PWD; symlinks resolved), raises no prompt and stays allowed: it is the harness's own isolation step for
# --bg sessions. Another repo's .claude/worktrees/ still prompts (a session entering another
# repo's .claude/worktrees/x did, 2026-10-16), and the permissions.allow "EnterWorktree" rule doesn't
# cover that prompt.
# Signal: the harness sets CLAUDE_CODE_SESSION_ATTENDED=0 for background (--bg) sessions and 1 for
# interactive ones. Unset (older Claude Code) means allow: never block a user who is sitting there.
# `claude attach` doesn't flip it (tested on 2.1.296): an attached --bg session asks in plain text too,
# which still works.
# Self-test: bash no-question-box.test.sh
input=$(cat)
[ "${CLAUDE_CODE_SESSION_ATTENDED:-}" = 0 ] || exit 0
how='Ask the user in plain text, naming the task key and the exact action (e.g. "force-push PROJ-4668?"). If a coordinator gave you this task, send the same ask to it as a blocked status report. Then end your turn.'
case "$1" in
  plan) reason="This session started in the background: plan mode ends in a plan approval that no coordinator can relay. Work without plan mode. Only if the plan needs sign-off before you change anything: write it to a file (the folder the project's CLAUDE.md names, else your scratchpad), make no other changes, and ask for approval with the file's path, as follows. $how" ;;
  worktree)
    # Unreadable input denies: fail closed in the sessions this guards. Both sides are resolved (symlinks,
    # ..) by cd + pwd -P, so a path that doesn't exist denies too: EnterWorktree's path must exist anyway.
    path=$(jq -r 'if .tool_input.path then .tool_input.path else "" end' <<<"$input") || path=/nonexistent/..
    [ -n "$path" ] || exit 0   # `name`: a new worktree under the session's own .claude/worktrees/
    # The start dir: CLAUDE_PROJECT_DIR stays put; the input's cwd moves with a cd or an entered worktree.
    base=${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)}; base=$(cd "${base:-.}" 2>/dev/null && pwd -P) || base=
    case $path in /*) ;; *) path=${base:-/nonexistent}/$path ;; esac
    real=$(cd "$path" 2>/dev/null && pwd -P) || real=
    [ -n "$base" ] && [ -n "$real" ] && case $real/ in "$base"/.claude/worktrees/?*) exit 0 ;; esac
    reason="This session started in the background: EnterWorktree on a path outside this session's own .claude/worktrees/ (under the directory it started in) raises a permission prompt no coordinator can answer, and the session sits blocked. Don't enter it: create the worktree with \`git worktree add\` (or the script the project's CLAUDE.md names for it), then work in it by absolute path with the file tools and \`git -C <worktree>\` in Bash. If that is refused too: $how" ;;
  *) reason="This session started in the background: the question box would block it, and no cross-session message (such as a relayed approval) reaches it while it waits. $how" ;;
esac
jq -nc --arg r "$reason Full rule: the session-orchestration:orchestrating-sessions skill, Receiving a message." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'

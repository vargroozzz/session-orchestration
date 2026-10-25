#!/usr/bin/env bash
# PermissionRequest on Bash: in a background session (CLAUDE_CODE_SESSION_ATTENDED=0, as no-question-box.sh
# reads it), a compound command (a pipe, `;`, `&&`, `||`, `$(…)`, backticks, a newline) about to raise a
# permission dialog gets a deny with a "split it" hint instead. Allow rules match plain commands only, so the
# compound form of an allowed command prompts, and in a --bg session nobody sees the dialog: 08f8b3f6 and
# 30a4fef8 sat 239 and 234 minutes on `kdev … | sed …` and `kdev … "$(kdev …)"` (R&D run 4). Split, each part
# runs on its allow rule, or prompts alone. Any other request, and every interactive session, is left alone
# (no output), so what the user must approve still reaches them.
# Quoted text isn't a separator: `grep -E 'a|b'`, `awk '{x; y}'` and `jq ".a | .b"` can't be split, so they
# prompt as before. `$(…)` and backticks still count inside double quotes, where they run.
# An unquoted `<` (not `<<`) is denied too, with a hand-over hint instead: `kdev exec -i p -- node - < s.js` needs
# its script on stdin, so it can't be split (review-backlog-triage stalled on one, 2026-10-22).
# ponytail: quotes pair per line, unescaped; a `\"` or an apostrophe inside the other quote can misread one
# command, and the cost is a prompt or one turn spent splitting it.
# Self-test: bash bg-compound.test.sh
[ "${CLAUDE_CODE_SESSION_ATTENDED:-}" = 0 ] || exit 0
cmd=$(jq -r 'select(.tool_name == "Bash") | .tool_input.command // empty' 2>/dev/null) || exit 0
nl=$'\n'
bare=$(printf '%s' "$cmd" | sed "s/'[^']*'//g") # single-quoted text removed
unq=$(printf '%s' "$bare" | sed 's/"[^"]*"//g') # double-quoted text removed too
msg=
case "$bare" in
  *'$('*|*'`'*|*"$nl"*|*'<('*) ;; # <(…) is a subshell too
  *)
    case "$unq" in
      *'|'*|*';'*|*'&&'*) ;;
      *)
        # `<<` is a heredoc (a newline case) or a here-string; `<` alone feeds a file to stdin
        case "$(printf '%s' "$unq" | sed 's/<<<*//g')" in
          *'<'*) msg='Background session: this command reads a file on stdin (`<`), and would wait on a permission prompt nobody sees. If the command takes the file as an argument (`jq . f.json`, `wc -l f`), drop the `<` and run that. A script on stdin (`node - < s.js`) cannot be split: hand the command over with the hand_command tool so it shows in the coordinator pane Run box, and put the `! <command>` line in your report (session-orchestration:orchestrating-sessions skill, Handing the user a command).' ;;
          *) exit 0 ;;
        esac ;;
    esac ;;
esac
[ -n "$msg" ] && { jq -nc --arg m "$msg" '{hookSpecificOutput: {hookEventName: "PermissionRequest", decision: {behavior: "deny", message: $m}}}'; exit 0; }
jq -nc '{hookSpecificOutput: {hookEventName: "PermissionRequest", decision: {behavior: "deny",
  message: "Background session: this compound command (a pipe, ;, &&, ||, $(…), backticks or several lines) would wait on a permission prompt nobody sees, while allow rules match plain commands only. Run each part as its own plain command, one per call (read the output yourself instead of piping it into sed/head/grep; put a value you need from one command into the next by hand). If a plain command still needs the user, hand it over per the session-orchestration:orchestrating-sessions skill (Handing the user a command)."}}}'

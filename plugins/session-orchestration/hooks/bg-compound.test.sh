#!/usr/bin/env bash
# Self-check for bg-compound.sh. Run: bash bg-compound.test.sh  (prints "ok" or the failure).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# $1: CLAUDE_CODE_SESSION_ATTENDED ('' = unset), $2: tool, $3: command; prints the decision's behavior or "none".
run() {
  local out
  out=$(jq -nc --arg t "$2" --arg c "$3" '{session_id: "s", tool_name: $t, tool_input: {command: $c}}' |
    if [ -n "$1" ]; then CLAUDE_CODE_SESSION_ATTENDED=$1 bash "$here/bg-compound.sh"; else env -u CLAUDE_CODE_SESSION_ATTENDED bash "$here/bg-compound.sh"; fi)
  [ -n "$out" ] && jq -r .hookSpecificOutput.decision.behavior <<<"$out" || echo none
}
check() { local got; got=$(run "$1" "$2" "$3"); [ "$got" = "$4" ] || { echo "FAIL [$1] $2 '$3': got $got, want $4"; exit 1; }; }
check 0 Bash 'kdev -n dev describe pod x | sed -n "/Events:/,$p"' deny
check 0 Bash 'kdev get pods -l "$(kdev get deploy -o jsonpath={.x})"' deny
check 0 Bash 'a && b' deny
check 0 Bash 'a || b' deny
check 0 Bash 'a; b' deny
check 0 Bash 'echo `date`' deny
check 0 Bash $'a\nb' deny
check 0 Bash 'echo "$(date)"' deny                 # runs inside double quotes
check 0 Bash "grep -E 'a|b' f | wc -l" deny
check 0 Bash 'kdev exec -i p -- node - < s.js' deny   # a script on stdin
check 0 Bash "grep -c 'a<b' f" none
check 0 Bash 'diff <(sort a) <(sort b)' deny          # process substitution: the compound hint                # quoted <
check 0 Bash 'cat <<<"x"' none                     # here-string
check 0 Bash 'git push origin feature/x' none      # plain: the prompt still reaches the user
check 0 Bash "grep -E 'foo|bar' f" none            # quoted separators can't be split
check 0 Bash "awk '{print \$1; print \$2}' f" none
check 0 Bash 'jq ".a | .b" x' none
check 0 Bash "echo 'a \$(b)'" none                 # single quotes: nothing runs
check 1 Bash 'ls | head -1' none                    # interactive: the dialog shows as before
check '' Bash 'ls | head -1' none                   # unknown: never block a user who may be there
check 0 Write 'a | b' none                          # another tool: left alone
msg=$(jq -nc '{tool_name: "Bash", tool_input: {command: "ls | head"}}' | CLAUDE_CODE_SESSION_ATTENDED=0 bash "$here/bg-compound.sh" | jq -r .hookSpecificOutput.decision.message)
case "$msg" in *'own plain command, one per call'*) ;; *) echo "FAIL message: $msg"; exit 1 ;; esac
msg=$(jq -nc '{tool_name: "Bash", tool_input: {command: "node - < s.js"}}' | CLAUDE_CODE_SESSION_ATTENDED=0 bash "$here/bg-compound.sh" | jq -r .hookSpecificOutput.decision.message)
case "$msg" in *'drop the `<`'*hand_command*) ;; *) echo "FAIL stdin message: $msg"; exit 1 ;; esac
msg=$(jq -nc '{tool_name: "Bash", tool_input: {command: "diff <(sort a) b"}}' | CLAUDE_CODE_SESSION_ATTENDED=0 bash "$here/bg-compound.sh" | jq -r .hookSpecificOutput.decision.message)
case "$msg" in *'own plain command, one per call'*) ;; *) echo "FAIL <( message: $msg"; exit 1 ;; esac
echo ok

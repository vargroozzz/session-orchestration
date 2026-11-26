#!/usr/bin/env bash
# PreToolUse in a coordinator session (context-watch.sh's cached kind; none cached yet: its first prompt starts a line
# with `Act as a coordinator`): three of SKILL.md's Rules as checks. In a task, chunk or review session: worker.md's
# rule that it starts no session (the last bullet).
# - Bash with a `cd` or `pushd` command word (at the start, or after `;`, `&`, `|`, `(` or a newline): refused (the
#   Bash tool keeps it, and `claude --bg` then starts outside the project). A quoted `; cd` is refused too.
# - Bash holding a relay block (`APPROVAL relayed from the user`) with `--resume`, `-r` or `--send-when-idle`: refused
#   (approvals.md: a relay is a SendMessage once the session is reachable; the worker's hook can't verify it otherwise).
# - Bash that is only this plugin's `session-status --relay KEY [ACTION]` by its full path: allowed, past the classifier.
# - Claude Code Desktop's start_session or hand_off_to_session (a sidebar session): refused, in a subagent too, unless it is the call
#   `--successor` prints (title NAME-next, its prompt running `--successor --started NAME`). A task goes to
#   `claude --bg`: a sidebar session is in no listing the status reads. Config start.sidebar true (a person key,
#   default false) lets every start_session through: the user chose sidebar tasks over the status's view of them.
#   Only the user turns it on: the person config files are guarded in every session (below).
# - Edit/Write/MultiEdit/NotebookEdit of a file inside the project root: allowed only in .claude/ (not its settings*.json
#   or hooks/), the replies folder, the handoff file (pending.file), the project memory CLAUDE.md names (the file and its memory/ folder)
#   and the root's CLAUDE.local.md while git doesn't track it (a worktree session can't reach it); never in
#   a task's worktree (.worktrees/, .claude/worktrees/). The path is resolved first (`..`, symlinks).
#   Outside the root (scratch, ~/.claude) is not the rule's business.
# - In a task, chunk or review session that answers to a coordinator (keyed, or messaged): start_session and
#   hand_off_to_session refused (worker.md: a task session starts no session), but a start_session that only shows the
#   user a card (initiation own_initiative or offer, no proposal_id). start.sidebar doesn't change this. So is a Bash
#   `claude … --bg` (a start or a resume); `session-status --handover --self` runs its own, unseen here.
#   shortcut: only a cached kind is tested, so a session's first call isn't; upgrade if one starts sessions that early
# A sub-coordinator (cached kind `subcoordinator KEY`; uncached, a first line `Coordinate KEY`) gets the cd rule and
# limits of its own (subcoordinator.md): it starts only KEY's sessions with claude --bg (never a sidebar session, never
# a `Coordinate` prompt), messages (SendMessage, reply's `to`) and `claude stop`s no session whose name holds another
# key, and edits only <replies>/KEY.md, KEY-*.md and the project memory. Its open_pane is refused
# in register.tsx. A parent's start_session of a `Coordinate` prompt is refused even under start.sidebar.
# Every session and subagent: no tool call writes a pane grant (blocked.sh request; only the coordinator pane's
# Allow this call press does): a Bash command naming both session-status and grants, or a file tool's path into
# session-status/grants, is refused.
# Any other session pays one bash start and a file test (and, until context-watch caches its kind, lib.sh and a
# first-prompt read).
input=$(cat)
# deny REASON NAME: the decision, and NAME as a telemetry=full block line (lib.sh usage).
deny() {
  jq -nc --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  ( l=$(cd "${0%/*}/.." 2>/dev/null && pwd)/lib.sh; cd "${cwd:-.}" 2>/dev/null; . "$l" && usage "coordinator-guard-$2" block "" "hooks/coordinator-guard.sh:${BASH_LINENO[0]}" ) >/dev/null 2>&1
  exit 0
}
# Every session, a subagent too: the person config files (a project's .claude/coordination.local.json, the person-wide
# ${XDG_CONFIG_HOME:-~/.config}/session-orchestration/config.json) hold the approvals (approvals.*, feedback.send,
# start.sidebar), so a session that wrote them could grant itself one. An Edit/Write of either, or a Bash command that
# writes one, asks the user in an attended session and is refused in a background one. A write is a redirection to it,
# or a command word (at the start or after ; & | ( ) tee, rm, truncate, sed -i (-i.bak, -Ei, --in-place) naming it, or
# mv, cp, ln, install with it last (the target: a copy from it is a read). So is setup's `--delegate` or `--trust`
# (session-init writes approvals.delegate and .trusted without naming the file). session-status's other writers
# (--purpose, --pane-section) don't touch approvals.
# shortcut: an interpreter or script that writes it without naming it, or a write after `cd ~/.config/session-orchestration`, isn't seen; upgrade if a session does that
if [[ $input == *coordination.local.json* || $input == *session-orchestration/config.json* || $input == *--delegate* || $input == *--trust* ]]; then
  { read -r t0; read -r cwd; read -r p0; } < <(jq -r '.tool_name // "", .cwd // "", (.tool_input.file_path // .tool_input.notebook_path // "")' <<<"$input")
  f='(coordination\.local|session-orchestration/config)\.json'
  w='(^|[;&|(])[[:space:]]*(sudo[[:space:]]+)?'
  hit=
  case $t0 in
    Edit|MultiEdit|Write|NotebookEdit) [[ $p0 =~ (^|/)$f$ ]] && hit=$p0 ;;
    Bash) c0=$(jq -r '.tool_input.command // ""' <<<"$input")
      hit=$(grep -oE ">[>|]?[[:space:]]*[\"']?[^[:space:];&|\"']*$f|$w(tee|rm|truncate|sed[[:space:]]+([^;&|]*[[:space:]])?(-[A-Za-z]*i|--in-place)[^[:space:]]*)[[:space:]][^;&|]*$f|$w(mv|cp|ln|install)[[:space:]][^;&|]*$f[\"']?[[:space:]]*(\$|[;&|)])" <<<"$c0" | grep -oE "[^[:space:]\"'>]*$f" | head -1)
      [ -n "$hit" ] || ! grep -qE "session-(status|init)[[:space:]].*--(delegate|trust)" <<<"$c0" || hit="setup's --delegate/--trust (.claude/coordination.local.json)" ;;
  esac
  if [ -n "$hit" ]; then
    r="Person config: ${hit/#"$HOME"/\~} holds the user's own settings, approvals among them (approvals.*, feedback.send, start.sidebar), so only the user changes it; a session never does, or it could grant itself an approval. Don't route the change another way: give the user the exact change and why (in your report, or hand_command with the command), and go on without it."
    if [ "${CLAUDE_CODE_SESSION_ATTENDED:-}" = 1 ]; then
      jq -nc --arg r "$r" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}}'
      exit 0
    fi
    deny "$r" person-config
  fi
fi
# shortcut: text only, so code that builds the path evades it; resuming.md "Permission prompts and trust" says why
# that is accepted
if [[ $input =~ \"tool_name\":\ *\"Bash\" && $input =~ session-status && $input =~ grants ]] &&
     jq -e '.tool_input.command // "" | test("session-status") and test("grants")' <<<"$input" >/dev/null 2>&1 ||
   [[ $input =~ \"(file_path|notebook_path)\":\ *\"[^\"]*session-status/grants ]]; then
  deny "A pane grant (~/.cache/session-status/grants) is written only by the coordinator pane's Allow this call press, never by a tool call." pane-grant
fi
# a subagent: its cd and edits aren't the coordinator's, but a sidebar session it starts is just as unseen; a
# sub-coordinator's subagent keeps the sub's limits (its starts and edits), all but the cd rule
sa=; [[ $input =~ \"agent_id\":\ *\"[^\"]+\" ]] && ! [[ $input =~ \"tool_name\":\ *\"mcp__ccd_session__(start_session|hand_off_to_session)\" ]] && sa=1
[[ $input =~ \"session_id\":\ *\"([A-Za-z0-9_-]+)\" ]] || exit 0
k=${XDG_CACHE_HOME:-$HOME/.cache}/session-status/handoff-${BASH_REMATCH[1]}.kind
kind= skey=
if [ -f "$k" ]; then read -r kind skey _ < "$k"
# a subagent's transcript_path is its own: only a cached kind counts for it
elif [ -n "$sa" ]; then exit 0
# not cached yet (a first prompt or a resume classifies in a detached job): context-watch.sh's coordinator and
# sub-coordinator tests inline
elif [[ $input =~ \"transcript_path\":\ *\"([^\"]+)\" ]] && [ -f "${BASH_REMATCH[1]}" ]; then
  tp=${BASH_REMATCH[1]} c=.; [[ ! $input =~ \"cwd\":\ *\"([^\"]+)\" ]] || c=${BASH_REMATCH[1]}
  # in its order: a chunk isn't one, whatever later lines say
  read -r kind skey < <( cd "$c" 2>/dev/null; . "${0%/*}/../lib.sh" && f=$(first_prompt "$tp" 50) && { [ -n "$f" ] || [ -z "$(sed -n '51{p;q;}' "$tp")" ] || f=$(first_prompt "$tp"); } &&
    ! chunk_of "$f" >/dev/null && if grep -m 1 . <<<"$f" | grep -qE '^[[:space:]]*Coordinate '; then
      KEYRE=$(key_re "$(adapter_path . 2>/dev/null)") && echo "subcoordinator $(sub_key "$f")"
    elif grep -q '^Act as a coordinator' <<<"$f"; then echo coordinator; fi 2>/dev/null )
fi
# A task, chunk or review session starts no session (worker.md), under start.sidebar too: only its start calls go on.
# A sub-coordinator (KEY-coordinator, first line `Coordinate KEY`): the coordinator's rules, and its own limits below.
task=
case $kind in coordinator) [ -z "$sa" ] || exit 0; skey= ;;
  subcoordinator) [ -n "$skey" ] && [ "$skey" != - ] || exit 0 ;;
  task|chunk|review) task=1 skey=; [[ $input =~ \"tool_name\":\ *\"(mcp__ccd_session__(start_session|hand_off_to_session)|Bash)\" ]] || exit 0 ;;
  *) exit 0 ;;
esac

{ read -r tool; read -r cwd; read -r path; } < <(jq -r '.tool_name // "", .cwd // "", (.tool_input.file_path // .tool_input.notebook_path // "")' <<<"$input")
cmd=; [ "$tool" != Bash ] || cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
# starts CMD: each `claude … --bg` command word in CMD as NAME\x1fRESUME\x1fPROMPT\x1e; `!` for one the guard can't
# read (an unclosed quote, or one inside sh -c / eval). Its -n NAME, its --resume ID, its prompt (the last plain
# argument, past redirections and option values). Wrapper words (env, nohup, …) are looked through.
starts() {
  python3 -I -c '
import shlex, sys
P = ";&|()\n<>"
W = {"env", "nohup", "command", "exec", "time", "nice", "caffeinate", "sudo"}
V = {"--model", "--effort", "--permission-mode", "--add-dir", "--agent", "--agents", "--settings", "--mcp-config",
     "--append-system-prompt", "--system-prompt", "--fallback-model", "--allowedTools", "--allowed-tools",
     "--disallowedTools", "--disallowed-tools", "--session-id", "--output-format", "--input-format", "--max-turns"}
try:
    lx = shlex.shlex(sys.argv[1].replace("\\\n", " "), posix=True, punctuation_chars=P); lx.whitespace = " \t\r"; lx.whitespace_split = True; toks = list(lx)
except ValueError: print("!"); sys.exit()
seg = []; skip = False
for t in toks + [";"]:
    if skip: skip = False; continue
    if t and all(c in P for c in t) and ("<" in t or ">" in t):  # a redirection: drop its fd and its target
        if seg and seg[-1].isdigit(): seg.pop()
        skip = True; continue
    if t and all(c in P for c in t):
        s = seg; seg = []
        w = False
        while s and (("=" in s[0] and not s[0].startswith("-")) or s[0].rsplit("/", 1)[-1] in W or (w and (s[0].startswith("-") or s[0].isdigit()))):
            w = w or s[0].rsplit("/", 1)[-1] in W; s = s[1:]
        if not s: continue
        if s[0].rsplit("/", 1)[-1] in ("sh", "bash", "zsh", "eval") and any("claude" in a and "--bg" in a for a in s): print("!"); sys.exit()
        if s[0].rsplit("/", 1)[-1] != "claude" or "--bg" not in s: continue
        name = res = ""; pos = []; i = 1
        while i < len(s):
            a = s[i]; v = s[i + 1] if i + 1 < len(s) else ""
            if a in ("-n", "--name"): name = v; i += 1
            elif a.startswith("--name="): name = a[7:]
            elif a in ("-r", "--resume"): res = v; i += 1
            elif a in V: i += 1
            elif not a.startswith("-"): pos.append(a)
            i += 1
        sys.stdout.write(name + "\x1f" + res + "\x1f" + (pos[-1] if pos else "") + "\x1e")
    else: seg.append(t)
' "$1" || echo '!'
}
# other_key NAME: a task key NAME names that isn't the sub's own ($skey); fails when there's none. Its own sessions
# ($skey, $skey-…) and the parent (the root's coordinator) first: a session-name key pattern matches them whole.
other_key() {
  cd "${cwd:-.}" 2>/dev/null; type key_re >/dev/null 2>&1 || . "${0%/*}/../lib.sh"
  [ -n "${KEYRE:-}" ] || KEYRE=$(key_re "$(adapter_path . 2>/dev/null)")
  local n=${1%% *}
  case $n in "$skey"|"$skey"-*|"$(coord_name "$(find_root)")") return 1 ;; esac
  grep -oE "$KEYRE" <<<"$n" | grep -vxF -e "$skey" | head -1 | grep .
}
if [ -n "$task" ]; then
  # one that answers to a coordinator: a chunk, a review, keyed, or messaged (context-watch.sh's test for the reply
  # card; .card is gone after a compaction until the next PostToolUse, so a review doesn't rely on it)
  read -r _ key _ < "$k"; [ "$kind $key" != 'task -' ] || [ -e "${k%.kind}.card" ] || [ -e "${k%.kind}.msg" ] || exit 0
  if [ "$tool" = Bash ]; then
    [[ $cmd =~ claude ]] && [[ $cmd =~ --bg ]] && [ -n "$(starts "$cmd")" ] || exit 0
    deny "Worker rule: a task session starts no session (worker.md, Work a message gives you), by claude --bg (a start or a resume) either. Say in your report what needs one (what, why, whether it only reads): your coordinator starts it by the user's start mode. Your own handover at your context mark runs the command the hook prints." task-start
  fi
  # a card the user starts themselves: Desktop starts nothing for these two without a proposal_id (hand_off_to_session
  # always starts one; spawn_task only shows a chip, so it isn't matched)
  [ "$tool" = mcp__ccd_session__start_session ] &&
    jq -e '.tool_input | (.initiation == "own_initiative" or .initiation == "offer") and (.proposal_id // "" | tostring | test("^\\s*$"))' <<<"$input" >/dev/null && exit 0
  deny "Worker rule: a task session starts no session (worker.md, Work a message gives you), by start_session or hand_off_to_session. Say in your report what needs one (what, why, whether it only reads): your coordinator starts it by the user's start mode. If the user asked you for it here, show them a card to start themselves: start_session with initiation \"own_initiative\" and no proposal_id." task-start
fi
if [ "$tool" = Bash ]; then
  # a command start that persists: not ( or $(…), a subshell's cd stays in it
  re=$'(^|[;&|{\n]|(^|[;&|{\n[:space:]])(then|do|else))[[:space:]]*(cd|pushd)([[:space:]]|$)'
  [ -n "$sa" ] || [[ ! $cmd =~ $re ]] ||
    deny "Coordinator rule: never cd in your shell, not later in a chain either; use absolute paths or git -C. The Bash tool keeps a cd across calls, and claude --bg then starts the new session in that folder, outside the project's settings. Run it again without the cd." cd
  grep -q 'APPROVAL relayed from the user' <<<"$cmd" && grep -qE -e '--send-when-idle|claude[^;&|]*[[:space:]](--resume|-r)[[:space:]]' <<<"$cmd" &&
    deny "Coordinator rule: a relay goes as a SendMessage once the session is reachable, never inside a resume prompt or a --send-when-idle text (approvals.md, Relaying): the worker's hook can't verify it there. Resume or wake the session without the relay block, then send the block with SendMessage." relay-resume
  if [ -z "$skey" ]; then
    # A plain relay (approvals.md): this plugin's session-status by its full path, --relay KEY [ACTION], one line, no
    # chain, pipe, redirection or substitution. It only prints a block verify-approval.sh passes, so it skips the
    # classifier, which reads a merge Action as the act.
    # shortcut: a path given quoted, with ~ or through a symlink isn't matched; it falls through to the classifier
    ss=$(cd "${0%/*}/../skills/orchestrating-sessions" 2>/dev/null && pwd) && ss=$ss/session-status || ss=
    # [[:blank:]], never [[:space:]]: a newline between words would start a second command
    q=$'\'[^\'\n]*\'|"[^"$`\\\n]*"'
    re="^[[:blank:]]+--relay[[:blank:]]+[A-Za-z0-9._-]+([[:blank:]]+($q|[A-Za-z0-9._/#:-]+))?[[:blank:]]*\$"
    r=${cmd#"${cmd%%[![:blank:]]*}"}
    [ -n "$ss" ] && [[ $r == "$ss "* ]] && r=${r#"$ss"} && [[ $r =~ $re ]] &&
      jq -nc '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", permissionDecisionReason: "a plain session-status --relay (approvals.md)"}}'
    exit 0
  fi
  # A sub stops no other key's session: a `claude stop` whose target names another key.
  # shortcut: a target given by id isn't resolved to its name; resolve it if a sub stops another key's session by id
  [[ $cmd =~ claude[[:space:]]+stop[[:space:]]+([^[:space:]\;\&\|]+) ]] && o=$(other_key "${BASH_REMATCH[1]}") &&
    deny "Sub-coordinator rule: you stop only $skey's sessions; $o's belong to your parent: report it to your parent." sub-stop
  [[ $cmd =~ claude ]] && [[ $cmd =~ --bg ]] || exit 0
  # A sub starts only KEY's sessions: each `claude … --bg` command word's -n NAME starts `KEY-`, its prompt names KEY
  # at its start (first_key; a chunk's `Chunk: KEY/N` too, its first key, if any, being KEY; a plan file KEY-*.md's
  # `Chunk: KEY-*/N` under a `Session task:` line naming KEY) and isn't a `Coordinate`
  # (one level). A `claude --bg` inside `sh -c` or `eval` is refused (`!`).
  # shortcut: a `--resume ID` with no -n gets only the `Coordinate` check (the ID's key is in its transcript); check it if a sub misuses it
  starts=$(starts "$cmd")
  [ "$starts" != '!' ] || deny "Sub-coordinator rule: this command starts a session the guard can't read (an unclosed quote?). Start each of $skey's sessions with one plain claude --bg -n $skey-… '<first prompt>' command." sub-start
  [ -n "$starts" ] || exit 0
  [ -n "${KEYRE:-}" ] || { cd "${cwd:-.}" 2>/dev/null; . "${0%/*}/../lib.sh"; KEYRE=$(key_re "$(adapter_path . 2>/dev/null)"); }
  while IFS=$'\x1f' read -r -d $'\x1e' name res prompt; do
    fk=$(first_key "$prompt"); ck=$(chunk_of "$prompt") && ck=${ck% *} || ck=$fk
    { [ -z "$name" ] && [ -n "$res" ] && ! sub_key "$prompt" >/dev/null; } ||
    { [[ $name == "$skey"-* ]] && [[ $name != "$skey"-coordinator* ]] && { [ "$ck" = "$skey" ] || { [[ $ck == "$skey"-* ]] && [ "$fk" = "$skey" ]; }; } && { [ -z "$fk" ] || [ "$fk" = "$skey" ]; } &&
      ! sub_key "$prompt" >/dev/null; } ||
      deny "Sub-coordinator rule: you start only $skey's sessions, one level deep: name it $skey-<what> (-n), and begin its first prompt with \`Work on $skey:\`, \`Session task: $skey\` or the chunk prompt --plan --next prints; never a \`Coordinate\` prompt (a task that big is two tasks: report it to your parent). Another key's work goes to your parent coordinator." sub-start
  done <<<"$starts"
  exit 0
fi
if [ "$tool" = SendMessage ] || [ "$tool" = mcp__session-orchestration__reply ]; then
  # shortcut: a `to` given as a session id or uds: address isn't resolved to its name; resolve it if a sub misuses one
  [ -n "$skey" ] && o=$(other_key "$(jq -r '.tool_input.to // "" | strings' <<<"$input")") &&
    deny "Sub-coordinator rule: you message only $skey's sessions and your parent; $o's sessions are your parent's: report what they need to your parent (reply with no to)." sub-message
  exit 0
fi
if [ "$tool" = mcp__ccd_session__start_session ] || [ "$tool" = mcp__ccd_session__hand_off_to_session ]; then
  [ -z "$skey" ] || deny "Sub-coordinator rule: start $skey's sessions with claude --bg, never as Desktop sidebar sessions (archiving a Desktop session archives the side sessions it started)." sub-sidebar
  # a sub always runs as a background session: a sidebar one would take its chunks with it when archived
  jq -e '.tool_input.prompt // "" | strings | test("^\\s*Coordinate ")' <<<"$input" >/dev/null &&
    deny "Coordinator rule: start a sub-coordinator (a \`Coordinate KEY\` first prompt) with claude --bg, even under start.sidebar: archiving a Desktop session archives the side sessions it started, its chunks included (sessions.md, Sub-coordinators)." sidebar
  # NAME whole: `--started p` inside `--started p-v2` isn't p's successor; a hand-off is never the successor
  # shortcut: NAME is checked against the title, not this coordinator's own name; upgrade if a task ever carries that exact text
  [ "$tool" = mcp__ccd_session__start_session ] && jq -e '.tool_input | (.title // "" | strings) as $t | ($t | endswith("-next") and length > 5) and
    (.prompt // "" | strings | split("--successor --started " + ($t | rtrimstr("-next")))[1:] | any(test("^([^A-Za-z0-9._-]|$)")))' <<<"$input" >/dev/null && exit 0
  ( l=$(cd "${0%/*}/.." 2>/dev/null && pwd)/lib.sh; cd "${cwd:-.}" 2>/dev/null && . "$l" && [ "$(config start.sidebar 2>/dev/null)" = true ] ) && exit 0
  deny "Coordinator rule: start a task with claude --bg (SKILL.md, Rules), never as a Desktop sidebar session: a sidebar session gets no status row, no idle notice, no resume after a restart and no stop, so you would lose sight of it. start_session is only for your successor: if this was your handover, run session-status --successor again and pass the call it prints unchanged. If claude isn't on PATH, hand the user its install: curl -fsSL https://claude.ai/install.sh | bash. Only the user can allow sidebar tasks." sidebar
fi
[ -n "$path" ] || exit 0
here=$(cd "$(dirname "$0")" && pwd)
cd "${cwd:-.}" 2>/dev/null || exit 0
. "$here/../lib.sh"
root=$(find_root 2>/dev/null) && [ -n "$root" ] || exit 0
# realpath of a file that may not exist yet: like find_root's pwd -P, so /tmp and /private/tmp compare equal
real() { python3 -I -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
path=$(real "$path") || exit 0
under() { [ -n "$2" ] && case $1 in "${2%/}"/*) true ;; *) false ;; esac; }
cd "$root" && ROOT=$root
abs() { local r=${1/#\~/$HOME}; case $r in '') ;; /*) real "$r" ;; *) real "$root/$r" ;; esac; }
memory() { local m; m=$(abs "$(sed -nE 's/^[^`]*[Pp]roject memory[^`]*`([^`]+)`.*/\1/p' CLAUDE.md CLAUDE.local.md 2>/dev/null | head -1)")
  [ -n "$m" ] && { [ "$path" = "$m" ] || under "$path" "$(dirname "$m")/memory"; }; }
# A sub changes only its own files in the replies folder (KEY.md, KEY-*.md: the plan, briefs, its handoff) and the
# project memory, wherever they live (the replies folder is often outside the root); anything else in the replies
# folder or the root is the parent's or a session's. Outside both: scratch, not the rule's business.
if [ -n "$skey" ]; then
  rp=$(abs "$(replies_path)")
  if under "$path" "$rp"; then case ${path#"$rp"/} in */*) ;; "$skey".md|"$skey"-*.md) exit 0 ;; esac
  elif memory; then exit 0
  else case $path in "$root"/*) ;; *) exit 0 ;; esac; fi
  deny "Sub-coordinator rule: the only files you change are $skey's in the replies folder ($skey.md, $skey-*.md: the plan, the briefs, your handoff $skey-coordinator.md) and the project memory. ${path/#"$HOME"/\~} is your parent's or a session's: send it to the session that owns it, or report it to your parent." sub-edit
fi
case $path in "$root"/*) ;; *) exit 0 ;; esac
if ! under "$path" "$root/.claude/worktrees" && ! under "$path" "$root/.worktrees"; then
  # .claude/ but its settings and hooks: those fixes are a session's too (SKILL.md, Rules)
  under "$path" "$root/.claude" && case ${path#"$root/.claude/"} in settings*.json|hooks/*) ;; *) exit 0 ;; esac
  under "$path" "$(abs "$(replies_path)")" && exit 0
  p=$(config pending.file 2>/dev/null) && [ -n "$p" ] && [ "$path" = "$(abs "$p")" ] && exit 0
  # the project memory: CLAUDE.md's "Project memory: `PATH`" (project-memory's setup line)
  memory && exit 0
  # an untracked CLAUDE.local.md: no worktree has it, so no session can make the edit
  [ "$path" = "$root/CLAUDE.local.md" ] && ! git ls-files --error-unmatch CLAUDE.local.md >/dev/null 2>&1 && exit 0
fi
rp=$(abs "$(replies_path 2>/dev/null)"); rp=${rp/#"$HOME"/\~}
deny "Coordinator rule: the only files you change are the memory files, the handoff file, your handover and the replies folder${rp:+ ($rp)}, where a draft, a report or notes go (SKILL.md, Rules). ${path#"$root"/} is a session's to change, however small: give it to the session that owns it, or start one. A CLAUDE.md or settings change goes to a new session (one already running refuses it from a message); a rule for how the sessions work can go in the project memory instead, which you change yourself." edit

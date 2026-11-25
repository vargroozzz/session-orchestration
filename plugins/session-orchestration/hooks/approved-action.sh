#!/usr/bin/env bash
# PreToolUse on Bash: a PR or Jira comment post (bitbucketdc-cli pr comment create|reply|update, forgejo-cli pr
# comment create|update, jiradc-cli issue comment create|update), a PR review (forgejo-cli pr review), a PR merge
# (bitbucketdc-cli or forgejo-cli pr merge) and their GitHub twins (gh pr merge|comment|review, gh issue comment), and
# gh pr|issue create (its Action: "create pr|issue on OWNER/REPO from BODYFILE (sha256 SHA) <its other flags, word for
# word>", --title required, --fill/--template/--editor/--web denied; forgejo-cli pr create the same, its body file
# --description-file; bitbucketdc-cli pr create, whose flags aren't read, can't be relayed: asked, when attended; a
# pr create passes when approvals.pr_create is
# true, and an apply session's gh pr|issue create on the plugin's own repo when feedback.send is auto, its flags are
# on the allow-list and feedback scrub finds nothing in them and its body file; a hit or another flag is denied), run only on a relayed approval that names it: a coordinator's "APPROVAL relayed from the user" block, received by this session, whose quote
# verify-approval.sh verifies and whose Action line names the target (REPO#ID for a PR, the issue key for Jira),
# plus the body file's sha256 for a post (and, for a gh review, its kind), or "merge"/"approve" (and no sha256) for a
# merge or a bodiless approval. A forgejo-cli REPO is its --repo OWNER/REPO. A gh REPO is OWNER/REPO (HOST/OWNER/REPO off github.com), from -R/--repo or the PR's
# URL (never guessed from a remote: gh picks its base repo by rules of its own). A relay whose Action names no tracker key (a project with
# session-name keys) is verified with REPO's last part #ID as the key; a merge's Action may instead end "(<this session's name>)",
# verified with that name (approving the task covers its landing), or "(<this session's name>, approved under KEY)",
# verified with KEY (a yes under another task's key that started this session with its landing). Then: allow, once per relay
# (~/.cache/session-status/approved/; a gh merge again while its PR stays open with no auto-merge). The command must be that one CLI call alone (a gh one: beside
# read-only gh calls only, see ghro below). Anything else on
# those commands: deny, with the exact action to report. A `gh api` call with a write method or fields, a
# `forgejo-cli raw` call with a write method, or gh reached through a variable or $(…), is denied (asked, when
# attended): it can't be named as an action.
# A missing or unverified approval asks instead (the
# normal permission dialog, same text) in an interactive session: CLAUDE_CODE_SESSION_ATTENDED=1, set in every
# hook's env. A `--bg` session gets 0 even while `claude attach`ed (tested on 2.1.296: the binary forces 0 for
# CLAUDE_CODE_SESSION_KIND=bg), so it is denied; unset or any other value is denied too. Fails closed: any error
# here exits 2, which blocks (hooks.json also sets onFailure: block, for a timeout). Every other command exits 0 at once, with no decision,
# and so does every command outside coordinated work (coordinated(), below).
# gh counts as a call where a command starts; its words must be plain (no variable, $(…), alias or xargs), or it is
# denied (asked, when attended). A post or merge it can't find as a call (inside bash -c, a heredoc a shell reads) is
# denied too: post from a file. A command that only mentions one (a grep pattern, a commit message, a prompt, a
# heredoc cat writes to a file or session-status --inbox-add stores) passes when every command in it is on an allowlist of ones that never run their text
# (SAFE), or as a quoted argument when the command is only those, this plugin's own scripts and plain assignments (inert(), below); read-only calls (gh pr view, gh api GET, an inline graphql query) pass too. A gated call may share its
# command with read-only gh calls (gh pr view|checks, gh run view|watch, …, gh by name right after the subcommand), in
# $(…) or a loop too: a landing's status poll. A read-only gh call in $(…) passes alone too as echo's argument,
# on a line of plain echo calls (echo "#$n $(gh pr view $n …)", in a for loop too). A read-only call that could still
# run code is denied (asked, when attended): --web, gh browse, gh config set, a variable set in its command, an
# integer or -v test on its $(…), and its output piped into anything but a filter (jq, grep, head, …).
# ponytail: a text check, not a sandbox: a file one call writes (a script, a git hook) can run its text in a later
# call this hook never links to it. Gate at execution (a wrapper for gh and the CLIs on PATH) if that matters.
# ponytail: gh subcommands outside pr/issue/api (release, repo, workflow) aren't gated; add them when a project
# reserves them. A name split by quotes (g''h) isn't seen.
# A Teams or mail send under the user's name (msgraph message send|update, mail send|reply|forward) is gated like a
# post: the action names the body file's sha256 and everything else the call sends (chat or message id, recipients,
# mentions, subject, --format, a Teams attachment's absolute path and sha256, …) word for word. A --draft or --dry-run sends nothing and passes. What can't be named by a
# sha256 is denied (asked, when attended): mail attachments, mail draft|scheduled send, mail rule create|update (a
# rule can forward), calendar create|update|cancel|respond (they mail the attendees), file grant (mails an invite),
# msgraph raw with a write method, and msgraph through a variable or $(…).
# shortcut: the CLI is known by the names msgraph and msgraph-cli; a wrapper under another name (msgraph.cli in the
# config, node …/dist/index.js) isn't gated. Read the config's cli name here if a project uses one.
# TODO: GitLab. glab mr merge|note|approve and glab issue note pass ungated; gate them like gh (glab has no body-file
# flag: -m "$(cat /abs/file)").
# A link message to another person's coordinator (session-status --link send), and a renew of such a link, run only on
# the user's Yes in this session's own pane naming it (below, before coordinated()).
# The other gated way to post: skills/orchestrating-sessions/review-inbox/post-approved.sh, whose CLI call this hook
# doesn't see. It posts only review-inbox rows the user approved on the page, each checked by verify-row.sh.
input=$(cat)
# (The raw JSON: a newline before gh is the two characters \n.)
pre='git[^A-Za-z0-9_].*push|session-status[[:space:]]+--land|--link|bitbucketdc-cli|forgejo-cli|jiradc-cli|msgraph|\$[^[:space:]]*[[:space:]]+(message|mail|calendar|file)[[:space:]]|(^|[^A-Za-z0-9_.-]|\\[nrt])gh([^A-Za-z0-9_.-]|$)'
[[ $input =~ $pre ]] || exit 0

done=
trap 'rc=$?; [ -n "$done" ] || { fault approved-action error "$rc" hooks/approved-action.sh 2>/dev/null; echo "approved-action hook failed, so this command is blocked. Report \"needs your approval: <the exact action>\" to the coordinator and end your turn." >&2; exit 2; }' EXIT
set -uo pipefail
# Bytes, not characters: under a UTF-8 locale macOS awk dies on a multibyte character its substr cut in two (towc:
# multibyte conversion failure), which blocked any gated-looking command holding one. Every separator here is ASCII.
export LC_ALL=C
here=$(cd "$(dirname "$0")" && pwd)
pass() { done=1; exit 0; }
hit= apply= prc=
# fault NAME KIND [N [AT]]: lib.sh usage, a telemetry=full fault line (never fails, prints nothing).
fault() { ( l=${here:-${0%/*}}/../lib.sh; cd "${cwd:-.}" 2>/dev/null; . "$l" && usage "$@" ) >/dev/null 2>&1; }
decide() {
  done=1; jq -nc --arg d "$1" --arg r "$2" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
  [ "$1" = allow ] || fault "approved-action-$1" block "" "hooks/approved-action.sh:${BASH_LINENO[${#BASH_LINENO[@]}-2]}"   # the top-level line whose call decided
  exit 0
}
attended() { local d=deny; if [ "${CLAUDE_CODE_SESSION_ATTENDED:-}" = 1 ]; then d=ask; fi; decide "$d" "$1"; }
ask_for() {
  attended "Blocked: ${hit:+$hit }$1 needs the user's approval, relayed by the coordinator and naming exactly this. Don't retry it, and don't route it another way. Send the coordinator your blocked status report with the line: needs your approval: $2. Then end your turn. When the relay arrives (Action naming $3), run the same command again; this hook verifies it."
}
# first_prompt TRANSCRIPT: its first prompt as lib.sh first_prompt reads it (not sourced here), and only when it isn't a
# peer's message.
first_prompt() {
  head -n 50 "$1" | jq -Rrn 'first(inputs | fromjson? | select(.type == "user" and (.isMeta | not))
    | [.origin.kind?, (.message.content
      | if type == "string" then . elif type == "array" then map(select(.type == "text") | .text) | join("\n") else "" end)]
    | select((.[1] | length > 0) and (.[1] | startswith("This session is being continued") | not)))
    | select(.[0] != "peer") | .[1]' 2>/dev/null
}

cmd=$(jq -r '.tool_input.command // ""' <<<"$input") || exit 1
raw=$cmd sid=$(jq -r '.session_id // ""' <<<"$input") || exit 1
cwd=$(jq -r '.cwd // ""' <<<"$input") tp=$(jq -r '.transcript_path // ""' <<<"$input") || exit 1
# Only coordinated work is gated: a project set up for it (an adapter or a coordination file, the cwd or a folder
# above: worktrees sit below the root), or a session a coordinator started or messaged (its transcript). Anywhere
# else, gh and the CLIs run as without the plugin, `claude -p` and --bg automation included.
# The folder test is wider than lib.sh's find_root/shared_dir (any adapter, person file or committed folder), so the
# gate covers at least what they call coordinated. It walks the cwd as a string: a deleted worktree still counts.
# The transcript markers: the first prompts a coordinator starts sessions with (orchestrating-sessions, handover), a
# relay, a message. A yes is cached per session; a no records how far it read, so the next call reads only what's new.
coordinated() {
  local d=${cwd:-$PWD} c n=0 sz
  while [ "${d:-/}" != / ] && [ "$d" != . ]; do
    [ -e "$d/.claude/session-status-adapter" ] || [ -e "$d/.claude/coordination.local.json" ] || [ -d "$d/.claude/coordination" ] && return 0
    d=$(dirname "$d")
  done
  [ -f "$tp" ] || return 1
  [[ $sid =~ ^[A-Za-z0-9_-]+$ ]] && c=${XDG_CACHE_HOME:-$HOME/.cache}/session-status/coordinated/$sid && mkdir -p "${c%/*}" 2>/dev/null || c=
  [ -n "$c" ] && read -r n 2>/dev/null < "$c"; [ "$n" = yes ] && return 0; [[ $n =~ ^[0-9]+$ ]] || n=0
  sz=$(( $(wc -c < "$tp") )); [ "$n" -le "$sz" ] || n=0
  # From 64 bytes back: a marker the last read cut in two is read whole.
  # (Not a pipe: grep -q stops early, and pipefail would read tail's SIGPIPE as no match.)
  if LC_ALL=C grep -qE '"(Work on |Chunk: )|Session task: |Act as a coordinator|APPROVAL relayed from the user|<cross-session-message from=' \
    < <(tail -c +"$(( n > 64 ? n - 63 : 1 ))" "$tp"); then
    [ -z "$c" ] || echo yes > "$c"; return 0
  fi
  [ -z "$c" ] || echo "$sz" > "$c"; return 1
}
# A link message (session-status --link send, features/remote.md, Links) leaves for another person's coordinator, and
# a renew keeps that link open: each runs alone, and only on the user's Yes in this session's own pane (no relay: the
# coordinator acts itself), whose question names the action ("send link message FILE to PEER (sha256 SHA)", "renew
# link PEER for DAYS days"), within 24 h, once. --check sends nothing, and a send to your own other account (--link
# kind: self) carries no one else's data, so both pass. A session-status --link send|renew that isn't that one plain
# call is denied: a quoted path, a quoted word, a wrapper. Text that only mentions one (a grep, a commit message) passes. Checked before coordinated(): a link is only ever
# a coordinator's.
kpre='session-status["'"'"']?[[:space:]]+["'"'"']?--link[^A-Za-z0-9]+(send|renew)([^A-Za-z0-9]|$)'
kone='^[[:space:]]*(bash[[:space:]]+)?([^[:space:];&|<>`$"'"'"'\\]*/)?session-status[[:space:]]+--link[[:space:]]+send[[:space:]]+([A-Za-z0-9][A-Za-z0-9._-]*)[[:space:]]+--kind[[:space:]]+[a-z]+([[:space:]]+--re[[:space:]]+[0-9]+)?[[:space:]]+(/[^[:space:];&|<>`$\\"'"'"']+)([[:space:]]+--check)?[[:space:]]*$'
rone='^[[:space:]]*(bash[[:space:]]+)?([^[:space:];&|<>`$"'"'"'\\]*/)?session-status[[:space:]]+--link[[:space:]]+renew[[:space:]]+([A-Za-z0-9][A-Za-z0-9._-]*)([[:space:]]+([0-9]{1,3}))?[[:space:]]*$'
if [[ $raw =~ $kpre ]]; then
  if [[ $raw =~ $kone ]]; then
    peer=${BASH_REMATCH[3]} file=${BASH_REMATCH[5]}
    [ -z "${BASH_REMATCH[6]}" ] || pass
    [ "$(cd "${cwd:-.}" 2>/dev/null && "$here/../skills/orchestrating-sessions/session-status" --link kind "$peer" 2>/dev/null)" != self ] || pass
    [ -f "$file" ] || decide deny "Blocked: no file $file."
    action="send link message $file to $peer (sha256 $(shasum -a 256 "$file" | cut -d' ' -f1))"
    how="ask your user on your pane: ask_approval with key link-$peer, body_file $file, the question naming exactly \"$action\" (session-status --link send … --check prints it) and a first option starting Yes; on their Yes, run the same command again"
  elif [[ $raw =~ $rone ]]; then
    peer=${BASH_REMATCH[3]}
    action="renew link $peer for $((10#${BASH_REMATCH[5]:-14})) days"
    how="ask your user on your pane: ask_approval with key link-$peer, the question naming exactly \"$action\" and a first option starting Yes; on their Yes, run the same command again"
  else
    decide deny "Blocked: run session-status --link send PEER --kind K [--re N] /abs/FILE (or --link renew PEER [DAYS]) alone, as its own plain command, so the approval hook can name it."
  fi
  # The pane's click: a row this plugin submitted (the engine sets that origin; no other plugin or session can), its
  # option a yes, its question naming the action.
  row=$([ -f "$tp" ] && jq -rn --arg a "$action" --argjson since "$(( $(date +%s) - 86400 ))" '
    def pane: (. // {}) | .kind == "plugin" and .name == "session-orchestration";
    inputs | . as $e
    | (if .type == "user" and (.origin | pane) then (.message.content | if type == "string" then . else ([.[]? | .text? // empty] | join(" ")) end)
       elif .type == "attachment" and .attachment.type == "queued_command" and (.attachment.origin | pane) then .attachment.prompt | tostring
       else empty end) as $t
    | select(($e.timestamp // "" | sub("\\.[0-9]+Z$"; "Z") | try fromdate catch 0) >= $since)
    | select($t | startswith("Approval pane answer for "))
    | ($t | index(". Asked: ")) as $i | select($i != null)
    | select($t[:$i] | sub("^Approval pane answer for [^:]*: "; "") | test("^yes\\b"; "i"))
    | select($t[$i + 9:] | contains($a))
    | "\($e.uuid // $e.timestamp)"' "$tp" 2>/dev/null | tail -1)
  [ -n "$row" ] || attended "Blocked: $action needs your user's Yes on your pane first (a link to another person's coordinator): $how."
  used=~/.cache/session-status/approved/$(printf 'link|%s|%s|%s' "$tp" "$action" "$row" | shasum -a 256 | cut -c1-32)
  [ ! -e "$used" ] || attended "Blocked: that Yes was used already; $how."
  mkdir -p "${used%/*}" && : > "$used" || exit 1
  decide allow "Your user's Yes on the pane for: $action"
fi
coordinated || pass
# A force-push (worker.md, "A PR event on your PR"): a task session may force-push its own PR's branch after a rebase,
# without an ask: the branch named after the session (its agent name), while a PR from it that the gh user opened is
# open, as one plain command, `git push --force-with-lease [--force-if-includes] origin <name>`, with no push refspec
# or mirror configured for origin. Any other force-push (main, another person's branch, --force, a +refspec, an
# abbreviated --for…, one in a chain or a bash -c) asks the user (denied unattended). A push counts where a command
# starts, behind a quote too (bash -c '…'), past wrappers, keywords and git's global options; text that only mentions
# one mid-sentence (a commit message, a grep) passes on.
# shortcut: a text check; a push it can't see (a git alias, a script) is left to the permission mode, as before.
fpre='(^|[;&|({`"'"'"']|'$'\n'')[[:space:]]*((then|do|else|if|while|until|!|env|command|rtk|proxy|sudo|exec|nohup|time|nice|timeout|xargs|bash|sh|zsh|-[^[:space:]]*|[0-9]+[smhd]?|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*)[[:space:]]+)*git([[:space:]]+(-[Cc]|--git-dir|--work-tree|--namespace|--exec-path|--config-env|--super-prefix)[[:space:]]+[^[:space:]]+|[[:space:]]+-[^[:space:]]+)*[[:space:]]+push([[:space:]][^;&|'$'\n'']*)?[[:space:]](--for[a-z-]*|--mi[a-z]*|-[A-Za-z]*f[A-Za-z]*|\+[^[:space:]]*)([=[:space:]"'"'"']|$)'
fone='^[[:space:]]*git[[:space:]]+push[[:space:]]+--force-with-lease([[:space:]]+--force-if-includes)?[[:space:]]+origin[[:space:]]+([A-Za-z0-9][A-Za-z0-9._-]*)[[:space:]]*$'
if [[ $raw =~ $fpre ]]; then
  fask="Send the coordinator your blocked status report with the line: needs your approval: force-push <the branch>. Then end your turn."
  [[ $raw =~ $fone ]] || attended "Blocked: a force-push runs without the user only as \`git push --force-with-lease --force-if-includes origin <this session's name>\`, alone, while that branch's PR is open. $fask"
  fb=${BASH_REMATCH[2]}
  me=$(jq -r 'select(.type == "agent-name") | .agentName // empty' "$tp" 2>/dev/null | tail -1)
  [ -n "$me" ] && [ "$fb" = "$me" ] || attended "Blocked: force-push to $fb: a session force-pushes only its own branch, the one named after it (${me:-this session is unnamed}). $fask"
  [ -z "$(cd "$cwd" 2>/dev/null && { git config --get-all remote.origin.push; git config --get remote.origin.mirror; })" ] ||
    attended "Blocked: origin has a push refspec or mirror configured, so this force-push may update more than $fb. $fask"
  # The PR's author is the gh user: a teammate's open PR from a branch of the same name stays theirs.
  fs=$(cd "$cwd" 2>/dev/null && gh pr view "$fb" --json state,author --jq '.state + " " + .author.login' 2>/dev/null) || fs=
  fu=$(cd "$cwd" 2>/dev/null && gh api user --jq .login 2>/dev/null) || fu=
  [ -n "$fu" ] && [ "$fs" = "OPEN $fu" ] ||
    attended "Blocked: force-push to $fb: no open PR from it that ${fu:-the gh user} opened (gh pr view $fb: ${fs:-none}). $fask"
  decide allow "This session's own branch $fb, whose PR is open: a force-push after a rebase needs no approval."
fi
# A landing by fast-forward (session-status --land BRANCH, worker.md) is gated as a merge: its action is "merge
# BRANCH", relayed as "merge BRANCH (<this session's name>)". Seen where a command starts; it must run alone.
lpre='(^|[;&|(]|'$'\n'')[[:space:]]*(bash[[:space:]]+)?([^[:space:]]*/)?session-status[[:space:]]+--land([[:space:]]|$)'
lone='^[[:space:]]*(bash[[:space:]]+)?([^[:space:];&|<>`$]*/)?session-status[[:space:]]+--land[[:space:]]+([A-Za-z0-9._/#-]+)[[:space:]]*$'
landing=
if [[ $raw =~ $lpre ]]; then
  [[ $raw =~ $lone ]] || decide deny "Blocked: run session-status --land BRANCH (or OWNER/REPO#N) alone, as its own command, so the approval hook can name it."
  landing=${BASH_REMATCH[3]}
fi
if [ -z "$landing" ]; then   # (not indented: the rest of the command parsing, up to the relays)
# Text given to a command is text, not calls, only when every command in sight is one that never runs what it's
# given and the call writes no file (no > but to /dev/null or &N; a file written could be run by what comes next:
# a git hook, a config) and sets no variable (GIT_EDITOR=bash git commit, X=bash; …, printf -v). An allowlist, so
# anything else (a shell, awk, a variable, a path or `.` as the command, read, set, sudo, sort, uniq, tee) fails
# closed. git counts only as git [-C DIR] [--no-pager] add|commit|status|log|diff|show|branch|push|fetch, not with
# --output, and push/fetch not with --r…, --e…, --u… (-c, aliases, other subcommands can run text); npx only for the
# four CLIs (bitbucketdc, forgejo, jiradc, msgraph; any npm scope); rg not with --pre; and those (git push|fetch|log|diff|show,
# rg, printf) with no word the shell could rewrite into an option (below). Shared by both passes.
SAFE=' cat echo printf grep egrep fgrep rg git claude head tail wc ls cd mkdir touch test [ true false cut tr diff jq gh bitbucketdc-cli forgejo-cli jiradc-cli msgraph '
# lex(S): S with quoting resolved: quote marks dropped, and each separator, < and ( inside quotes made `_` (an escape: char 1; a $ in "…" kept), so what
# is left splits into commands as the shell would (unclosed quote: the rest counts as quoted). A # at a word start
# becomes its own command `#`, which safe() refuses: where a comment starts (x\ #y, ${x/ #/}) is the shell's call,
# so a command with one is read whole. safe(U[, CAT]): every command in lexed text U starts with a SAFE word (after
# prefixes like env, then, while), as above; with CAT, every command is cat, and it may write files.
awklib='
function lex(s,   o, c, j, n, iq) { o = ""; iq = ""; n = length(s)
  for (j = 1; j <= n; j++) { c = substr(s, j, 1)
    if (iq == "" && c == "\\" || iq == "\"" && c == "\\") { o = o sprintf("%c", 1); j++; continue }
    if (iq == "" && c == "#" && (j == 1 || substr(s, j - 1, 1) ~ /[ \t\n;|&()]/)) { o = o ";#"; continue }
    if (iq == "") { if (c == "\"" || c == Q) iq = c; else o = o c; continue }
    if (c == iq) { iq = ""; continue }
    # "…$x" expands and "…`cmd`" runs cmd: kept, so safe() sees them (its ( still becomes _: the scan below keeps a "…$(")
    if (iq == "\"" && (c == "`" || c == "$")) { o = o c; continue }
    # quoted glob and brace characters are text too, so safe() sees only live ones
    o = o (c ~ /[;|&()<>`$\n{}*?[^]/ ? "_" : c) }
  LQ = iq; return o }
# qat(S, P): the quote open at char P of S ("" none, a backslash when an escape takes char P)
function qat(s, p,   j, c, iq) { iq = ""
  for (j = 1; j < p; j++) { c = substr(s, j, 1)
    if (iq != Q && c == "\\") { if (++j >= p) return c; continue }
    if (iq == "") { if (c == "\"" || c == Q) iq = c } else if (c == iq) iq = "" }
  return iq }
function safe(u, cat,   n, seg, x, m, w, y, t, z, M) {
  # a space before each separator, so a redirect target is a whole word: >&2hook writes the file 2hook
  if (!cat) { gsub(/[;|&)]/, " &", u); gsub(/&?[0-9]*>>?[ \t]*(&[0-9]+|&-|\/dev\/null)([ \t]|$)/, " ", u); if (u ~ />/) return 0 }
  # a word M ends a command whose words a `…` or $(…) goes on (git push `echo --exec=sh`)
  M = sprintf("%c", 2); gsub(/`|\$\(/, " " M "&", u)
  n = split(u, seg, /[;|&()`\n]|\$\(/)
  for (x = 1; x <= n; x++) { m = split(seg[x], w, /[ \t]+/); t = ""
    for (y = 1; y <= m; y++) { if (w[y] == "" || w[y] == M || index(PRE, " " w[y] " ")) continue
      if (w[y] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) return 0
      t = w[y]; break }
    if (t == "") continue
    # it stores its stdin as an inbox message (a forwarded worker message), never runs it
    if (t ~ /\/skills\/orchestrating-sessions\/session-status$/ && w[y + 1] == "--inbox-add") continue
    # it writes a feedback case whose evidence may quote a gated command, never runs it
    if (t == PROOT "/skills/orchestrating-sessions/feedback" && w[y + 1] == "add") continue
    if (cat && t != "cat") return 0
    if (t == "npx") { for (y++; w[y] == "-y" || w[y] == "--yes"; y++); t = w[y]; sub(/@[^@\/]*$/, "", t); sub(/^@[^\/]*\//, "", t)
      if (t !~ /^(bitbucketdc|forgejo|jiradc|msgraph)-cli$/) return 0 }
    if (t == "rg" && seg[x] ~ /--pre/ || t == "printf" && seg[x] ~ /(^|[ \t])-v/) return 0
    # -C DIR: a DIR the shell rewrites (-C {.,-c,core.sshCommand=sh}) adds a -c before the subcommand
    if (t == "git") { for (y++; w[y] == "-C" || w[y] == "--no-pager"; y += w[y] == "-C" ? 2 : 1)
        if (w[y] == "-C" && (index(w[y + 1], "$") || w[y + 1] ~ ("[" sprintf("%c", 1) "{}*?[]"))) return 0
      if (!index(" add commit status log diff show branch push fetch ", " " w[y] " ") || seg[x] ~ /--output/) return 0 }
    # Where an option runs or writes (git push/fetch --exec, log/diff/show --output, rg --pre, printf -v), a word the
    # shell rewrites could become one the checks miss: \--exec, $'--exec', $x, `…`, --{output=f,}, a glob (* matches a
    # file named --exec=sh). Refused: a word holding a $ (origin$_ splits into origin --exec=sh), starting with an
    # escape, a brace or a glob (^ too: zsh extendedglob), or a dash word holding one.
    if (t == "git" && index(" push fetch log diff show ", " " w[y] " ") || t == "rg" || t == "printf") {
      # shortcut: M also marks a closing backtick, so `git log -1` beside a gated mention fails closed too
      if (index(seg[x], M)) return 0
      for (z = y + 1; z <= m && (t != "printf" || z == y + 1); z++)
        if (index(w[z], "$") || w[z] ~ ("^[" sprintf("%c", 1) "{}*?[^]") || w[z] ~ ("^-.*[" sprintf("%c", 1) "{}*?[]")) return 0 }
    if (t == "git") {
      # git takes any unique prefix: --rec(eive-pack), --exe(c), --upl(oad-pack) run a command
      if ((w[y] == "push" || w[y] == "fetch") && seg[x] ~ /(^|[ \t])--[reu]/) return 0 }
    if (!index(SAFE, " " t " ")) return 0 }
  return 1 }'
# PROOT: this plugin's own folder, so only its feedback script counts, not one a session wrote under that name.
awkv=(-v "PROOT=${here%/hooks}" -v "SAFE=$SAFE" -v "PRE= env command time nohup rtk proxy then do else ! { } if elif while until done fi esac " -v "Q='" -v "ID=[A-Za-z_][A-Za-z0-9_]*")
# Heredoc bodies (cat > f <<EOF … EOF) are text, not commands: dropped when nothing but cat (or session-status --inbox-add) runs in the command
# without them; else the command is printed whole, its bodies unlexed, and the first line says 1 (opaque: the scan below
# reads it all). A << inside quotes, in (( )) arithmetic, in a <<< here-string or on a line going on with \, or with
# no terminator isn't taken as a heredoc. One whose delimiter isn't a plain word, beside a second << on its line, or
# with an unquoted delimiter and a $( or ` in its body, isn't either, and makes the command opaque.
cmd=$(printf '%s\n' "$cmd" | awk "${awkv[@]}" "$awklib"'
  { L[NR] = $0 } END { i = 1; LQ = ""; q = ""; n = 0; cut = 0
    while (i <= NR) { line = L[i++]
      s = q line; u = lex(s); q = LQ   # a quote still open goes on to the next line
      O[++n] = line; lc = s
      if (q != "" || u ~ /\(\(|<<</ || match(line, /\\+$/) && RLENGTH % 2 || gsub(/<</, "&", u) != 1) continue
      # The delimiter, read from the raw line as bash does, at its one << outside quotes and escapes (not a quoted
      # "<<E" beside a split <''<): a plain word, bare or in one pair of quotes, then a blank, a separator or the
      # end. Anything else (E;F, E F, E$(x), \E, E"x") is a heredoc this cannot read: the command is opaque, since its
      # body read as commands could open a quote (it'\''s) that hides the lines after it.
      if (gsub(/<</, "&", lc) != 1 || !match(s, "<<-?[ \t]*(" ID "|" Q ID Q "|\"" ID "\")([ \t;|&<>)]|$)") || qat(s, RSTART) != "") { bad = 1; continue }
      h = substr(s, RSTART + 2, RLENGTH - 2); dash = h ~ /^-/; quoted = index(h, Q) || index(h, "\"")
      sub(/^-?[ \t]*/, "", h); gsub(/[^A-Za-z0-9_]/, "", h)
      for (k = i; k <= NR; k++) { t = L[k]; if (dash) sub(/^\t+/, "", t); if (t == h) break }
      if (k > NR) continue
      # the body of an unquoted delimiter runs its $(…) and backticks (char 96): read as commands, and opaque as above
      if (!quoted) { for (x = i; x < k && L[x] !~ /\$\(/ && !index(L[x], sprintf("%c", 96)); x++); if (x < k) { bad = 1; continue } }
      for (; i <= k; i++) { O[++n] = L[i]; B[n] = 1 }
      cut = 1 }
    d = ""; if (cut) for (x = 1; x <= n; x++) if (!B[x]) d = d O[x] "\n"
    op = bad || cut && !safe(lex(d), 1); print op
    for (x = 1; x <= n; x++) if (op || !B[x]) print O[x] }') || exit 1
opaque=${cmd:0:1} cmd=${cmd:2}
# The msgraph CLI by name: msgraph, a path to it, or its npx package; not a file named after it (msgraph-body.md).
msw='(^|[^A-Za-z0-9_.-])msgraph(-cli)?(@[^[:space:]]*)?'
# Its commands that send or forward under the user's name (a mail rule can forward, a file grant mails an invite).
msv='(message[[:space:]]+(send|update)|mail[[:space:]]+((draft|scheduled)[[:space:]]+)?(send|reply|forward)|mail[[:space:]]+rule[[:space:]]+(create|update)|calendar[[:space:]]+(create|update|cancel|respond)|file[[:space:]]+grant)([[:space:]]|$)'
ops='bitbucketdc-cli[^[:space:]]*.*[[:space:]]pr[[:space:]]+(merge|create|comment[[:space:]]+(create|reply|update))([[:space:]]|$)|forgejo-cli[^[:space:]]*.*[[:space:]]pr[[:space:]]+(merge|review|create|comment[[:space:]]+(create|update))([[:space:]]|$)|jiradc-cli[^[:space:]]*.*[[:space:]]issue[[:space:]]+comment[[:space:]]+(create|update)([[:space:]]|$)|'"$msw"'[[:space:]](.*[[:space:]])?'"$msv"
# msgraph named through a variable or $(…) ($(which msgraph), M=msgraph), or a send verb right after a variable or
# $(…) ($M mail send, "$bin" message send: a wrapper whose name isn't known here).
msind='(=["'"'"']?|\$\(|`)[[:space:]]*((which|command[[:space:]]+-v|type[[:space:]]+-p)[[:space:]]+)?([^[:space:]]*/)?msgraph(-cli)?([^A-Za-z0-9_.-]|$)|\$[^[:space:]]*[[:space:]]+'"$msv"
ghw='(^|[^A-Za-z0-9_.-])gh([^A-Za-z0-9_.-]|$)'
# gh, then pr/issue and a merge, comment or review, or api, in the same command (flags may sit between): what a gated
# gh call looks like. gh pr view or gh issue list don't.
ghops='(^|[^A-Za-z0-9_.-])gh([^A-Za-z0-9_.-][^|;&]*[[:space:]]|[[:space:]]+)((pr|issue)([[:space:]][^|;&]*)?[[:space:]](merge|comment|review|create)|api)([[:space:]]|$)'
# gh named through a variable or $(…): x=gh, $(which gh), `command -v gh`, and read as a file: bash <(gh …).
ghind='(=["'"'"']?|\$\(|`|[<>=]\()[[:space:]]*((which|command[[:space:]]+-v|type[[:space:]]+-p)[[:space:]]+)?([^[:space:]]*/)?gh([^A-Za-z0-9_.-]|$)'
# A read-only gh call (pr view|checks, run watch, …), as landing a PR polls it: chained with the merge (then it
# doesn't count as one more call), and in "$(…)" tested by [ ], [[ ]], test or case, in a wait loop too: there its
# output (a PR body, a diff, which others write) is only compared, never run; and in $(…) as an argument on a line of
# plain echo calls, only printed (below). Anywhere else (x=$(…), which $x could run, echo's output in $(…), a pipe, eval, a shell) it is
# still denied as indirect.
# shortcut: a known list of re-parsing commands (eval, shells, interpreters); add one if it shows up.
ghreparse='(^|[^A-Za-z0-9_.-])(eval|source|sh|bash|zsh|dash|ksh|fish|python3?|perl|ruby|node|xargs|awk)([^A-Za-z0-9_.-]|$)'
ghro='[[:space:]]+((pr|issue)[[:space:]]+(view|checks|list|status|diff)|run[[:space:]]+(view|list|watch)|repo[[:space:]]+view)([^A-Za-z0-9_.-]|$)'
# One line: continuations joined as bash joins them (-\<nl>-exec is --exec; a line ending \\ goes on to no next
# line), other newlines made command separators.
# (awk, not ${cmd//"$nl"/ ; }: bash 3.2's replace-all is quadratic, minutes on a 50 KB heredoc.)
cmd=$(printf '%s\n' "$cmd" | awk 'NR > 1 { printf "%s", (c ? "" : " ; ") } { c = match($0, /\\+$/) && RLENGTH % 2; if (c) sub(/\\$/, ""); printf "%s", $0 }') || exit 1
# What the CLI mentions are counted in: the command without its quoted runs of words (a grep pattern, a commit
# message, a prompt), which are arguments, not calls. A quoted single word stays (gh "pr" merge), and so do a value
# (X='npx cli', run as $X later) and a "…" holding $( or `, which the shell runs. A command that isn't all safe()
# (a plugin script, $S/feedback brief … 'a gh comment relay') drops them too when inert() says every command in it
# is one that never runs its text: then, or when the quoting can't be read (an open quote, a comment, $'…'), the whole
# command counts.
scan=$(printf '%s' "$cmd" | awk "${awkv[@]}" -v q="'" -v opaque="$opaque" "$awklib"'
# inert(U): lexed U is only commands that never run their arguments: plain NAME=VALUE (a literal path) on their own,
# the scripts of this plugin (by path or $NAME/… with NAME set so before), and safe() ones; no input (<, <<<), no $(…)
# or `…`, no redirect but to /dev/null or &N. An allowlist: a re-parser it does not know fails closed.
# An assignment may change what a later command does (an exported GIT_EDITOR, PATH): names that steer a tool are
# refused, and after any assignment only echo, printf, true, false, test or [ may follow beside the plugin scripts.
function inert(u,   r, n, seg, x, m, w, y, t, k, val, asg) {
  if (index(u, "<") || index(u, "`") || index(u, "$(")) return 0
  r = u; gsub(/&?[0-9]*>>?[ \t]*(&[0-9]+|&-|\/dev\/null)([ \t;|&)]|$)/, " ", r); if (r ~ />/) return 0
  n = split(u, seg, /[;|&()\n]/)
  for (x = 1; x <= n; x++) { m = split(seg[x], w, /[ \t]+/)
    for (y = 1; y <= m && (w[y] == "" || index(PRE, " " w[y] " ")); y++);
    if (y > m) continue
    if (w[y] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
      for (; y <= m; y++) { if (w[y] == "") continue
        if (w[y] !~ /^[A-Za-z_][A-Za-z0-9_]*=[A-Za-z0-9_.\/-]*$/) return 0
        k = w[y]; sub(/=.*/, "", k)
        if (k ~ /^(PATH|HOME|IFS|ENV|BASH_ENV|CDPATH|SHELLOPTS|BASHOPTS|PS4)$|^(GH_|GIT_|CLAUDE_|LD_|DYLD_|XDG_)/) return 0
        val[k] = substr(w[y], length(k) + 2); asg = 1 }
      continue }
    t = w[y]
    if (match(t, /^[$][A-Za-z_][A-Za-z0-9_]*/) || match(t, /^[$][{][A-Za-z_][A-Za-z0-9_]*[}]/)) {
      k = substr(t, 1, RLENGTH); gsub(/[^A-Za-z0-9_]/, "", k); if (!(k in val)) return 0
      t = val[k] substr(t, RLENGTH + 1) }
    if (index(t, PROOT "/skills/") == 1 && t !~ /\/\.\.(\/|$)/ && !index(t, "$")) continue
    if (asg && w[y] !~ /^(echo|printf|true|false|test|\[)$/ || !safe(seg[x])) return 0 }
  return 1 }
{ s = s (NR > 1 ? "\n" : "") $0 } END {
  if (opaque) { printf "%s", s; exit }
  full = s; ok = safe(u = lex(s))
  if (!ok && (LQ != "" || index(u, ";#") || index(s, "$" q))) { printf "%s", s; exit }
  while (match(s, "[\\\\\"" q "]")) {
    out = out substr(s, 1, RSTART - 1); c = substr(s, RSTART, 1); s = substr(s, RSTART + 1)
    if (c == "\\") { out = out c substr(s, 1, 1); s = substr(s, 2); continue }
    # The closing quote: for "…", the first one no backslash escapes.
    if (c == q) e = index(s, q); else { e = 0; r = s; while (match(r, /\\.|"/)) { e += RSTART + RLENGTH - 1; if (RLENGTH == 1) break; r = substr(r, RSTART + 2) } if (RLENGTH != 1) e = 0 }
    if (!e) e = length(s) + 1
    b = substr(s, 1, e - 1); s = substr(s, e + 1)
    if (b !~ /[ \t]/ || out ~ /=$/ || (c == "\"" && (index(b, "$(") || index(b, "`")))) out = out c b c
  }
  printf "%s", (ok || inert(u) ? out s : full) }') || exit 1
ghn=$(grep -oE "$ghw" <<<"$scan" | wc -l | tr -d ' ')
ghron=$(grep -oE "(^|[^A-Za-z0-9_.-])gh$ghro" <<<"$scan" | wc -l | tr -d ' ')
# Matched with quotes dropped too, so a quoted subcommand (pr 'merge') or flag is still seen.
# (tr, not ${scan//[\"\']/}: bash 3.2's is quadratic, 11 s on a 5 KB heredoc.)
uq=$(tr -d "\"'" <<<"$scan")
bbops=; grep -qE "$ops" <<<"$uq" && bbops=1
# forgejo-cli raw with a write method: the gh api twin.
grep -qiE 'forgejo-cli[^[:space:]]*.*[[:space:]]raw[[:space:]].*--method[=[:space:]]+["'"'"']?(POST|PUT|PATCH|DELETE)' <<<"$uq" &&
  attended "Blocked: a forgejo-cli raw call that writes can't be named as an approved action. Use forgejo-cli pr merge|review|comment, or hand the user the command with hand_command."
grep -qiE "$msw"'[[:space:]](.*[[:space:]])?raw[[:space:]].*--method[=[:space:]]+["'"'"']?(POST|PUT|PATCH|DELETE)' <<<"$uq" &&
  attended "Blocked: a msgraph raw call that writes can't be named as an approved action. Use msgraph message send or mail send|reply|forward, or hand the user the command with hand_command."
grep -qE "$msind" <<<"$uq" && grep -qiE "(^|[[:space:]])($msv|raw[[:space:]].*--method[=[:space:]]+(POST|PUT|PATCH|DELETE))" <<<"$uq" &&
  attended "Blocked: msgraph reached through a variable or \$(…) can't be checked by the approval hook. Run it by its name (msgraph …, or npx -y <package> …), as one plain command."
[ -n "$bbops" ] || [ "$ghn" -gt 0 ] || pass
# A read-only gh call can still run code: the browser --web or gh browse opens (gh config set picks it), another gh
# or config a variable picks (PATH=/x gh, HOME=…; gh, export, zsh's path, a function named gh), and a program its
# output is piped into (| xargs env, | sh, >(…)). Each asks (denied unattended), wherever the call sits: chained, or
# in a tested or echoed $(…). Any pipe in the command goes only into a filter that never runs its input, and a
# command word that runs or sources text (eval, ., bash, exec, coproc) shares no command with gh.
# Read from the scan with quote marks dropped and separators inside quotes made `_` (jq '.a|b' is no pipe), but
# a "$(…)" kept as code.
# shortcut: a denylist of the setters and openers seen so far; add one when it shows up.
if [ "$ghn" -gt 0 ]; then
mq=$(printf '%s' "$scan" | awk -v Q="'" '{ s = s $0 } END { n = length(s); iq = ""; d = 0
  for (j = 1; j <= n; j++) { c = substr(s, j, 1)
    if (iq != Q && c == "\\") { printf "%s%s", c, substr(s, j + 1, 1); j++; continue }
    # a "$(…)": read as code, its own quotes too, back in the "…" at its closing )
    if (d && iq == "") { d += (c == "(") - (c == ")"); if (!d) iq = "\""; if (c != Q && c != "\"") printf "%s", c; else iq = c; continue }
    if (iq == "\"" && c == "$" && substr(s, j + 1, 1) == "(") { d = 1; iq = ""; printf "$("; j++; continue }
    if (iq == "" && (c == Q || c == "\"")) { iq = c; continue }
    if (c == iq) { iq = ""; continue }
    printf "%s", (iq != "" && c ~ /[|;&<>()]/ || iq == Q && c ~ /[`$]/ ? "_" : c) }
  }') || exit 1
ghcp='(^|[;&|({`]|\$\(|[[:space:]](then|do|else|!))[[:space:]]*'
grep -qE '(^|[^A-Za-z0-9_$-])([A-Za-z_][A-Za-z0-9_]*\+?=[^[:space:]]*[[:space:]]+([^;&|()]*[[:space:]])?([^[:space:];&|()]*/)?gh([^A-Za-z0-9_.-]|$)|([A-Z_][A-Z0-9_]*|path)(\[[^]]*\])?\+?=|[A-Za-z_][A-Za-z0-9_]*\[[^]]*\]\+?=)|'"$ghcp"'((export|declare|typeset|readonly|alias|hash|function|unset)([[:space:]]|$)|for[[:space:]]+([A-Z_][A-Z0-9_]*|path)[[:space:]]|printf[[:space:]]+-v[[:space:]]*([A-Z_]|path)|read[[:space:]][^;&|]*[[:space:]]([A-Z_][A-Z0-9_]*|path)([[:space:];]|$)|gh[[:space:]]*\(\))' <<<"$mq" &&
  attended "Blocked: a variable set in a command with gh (PATH=, HOME=, export, a function named gh) can pick another gh or config, so the approval hook can't check it. Run the gh call alone, as one plain command."
grep -qE "$ghcp([^[:space:]]*/)?gh([[:space:]]|$)" <<<"$mq" && grep -qE "$ghcp"'(eval|source|\.|sh|bash|zsh|dash|ksh|fish|python3?|perl|ruby|node|xargs|awk|exec|coproc)([[:space:]]|$)' <<<"$mq" &&
  attended "Blocked: a command that runs or sources text (eval, ., bash, exec) can't share a command with gh: it could run gh's output. Run the gh call alone, as one plain command."
# (a case pattern's | (in A|B), ;; C|D)) is no pipe)
mp=$(sed -E 's/\|\|/;/g; s/\|&/|/g; s/([[:space:]]in|;;)[[:space:]]+[^;()]*\)/\1 _)/g' <<<"$mq")
while IFS= read -r s; do
  case "$s" in cat|head|tail|grep|egrep|fgrep|jq|wc|cut|tr|uniq) ;;
    *) attended "Blocked: in a command with gh, a pipe into ${s:-a command} could run gh's output, so the approval hook can't check it. Pipe only into jq, grep, head, tail, wc, cut, tr, uniq or cat." ;; esac
done < <(grep -oE '\|[[:space:]]*[^[:space:]|]*' <<<"$mp" | sed -E 's/^\|[[:space:]]*//')
ghsegs=$(sed -E 's/&&/;/g' <<<"$mp" | grep -oE '(^|[^A-Za-z0-9_.-])gh([^A-Za-z0-9_.-][^;&|)]*)?') || ghsegs=
while IFS= read -r g; do
  g=" $g "
  [[ $g == *[\<\>=]\(* ]] &&
    attended "Blocked: gh's output fed to a process substitution could run it, so the approval hook can't check it. Run the gh call alone, as one plain command."
  # -w is --web on every read verb but run list (--workflow)
  [[ $g =~ [[:space:]](--web|browse|config[[:space:]]+set)[=[:space:]] ]] ||
    { [[ $g =~ [[:space:]]-[A-Za-z]*w[A-Za-z]*[=[:space:]] ]] && ! [[ $g =~ [[:space:]]run[[:space:]]+list[[:space:]] ]]; } &&
    attended "Blocked: gh --web, gh browse and gh config set open or set the browser gh runs, which the approval hook can't check. Read it with gh pr view, without --web."
done <<<"$ghsegs"
fi
# A backtick or $ inside '…' (a perl or sed program printing `gh pr create`) runs nothing: made `_`; all else stays
# as written ("$(…)" runs, x='gh' names it). Not when the text is opaque or a quote is left open: a heredoc body's
# apostrophe would hide real code. (A gated gh call such a program runs still reads as a post or merge the walk
# can't find: denied below.)
ghl=$scan
[ "$opaque" = 1 ] || ghl=$(printf '%s' "$scan" | awk -v Q="'" '{ s = s (NR > 1 ? "\n" : "") $0 } END { n = length(s); o = ""; iq = ""
  for (j = 1; j <= n; j++) { c = substr(s, j, 1)
    if (iq != Q && c == "\\") { o = o c substr(s, j + 1, 1); j++; continue }
    if (iq == "" && (c == Q || c == "\"") || c == iq) iq = (iq == "" ? c : "")
    else if (iq == Q && (c == "`" || c == "$")) c = "_"
    o = o c }
  printf "%s", (iq == "" ? o : s) }') || exit 1
ghi=$ghl
# (Not with an integer or -v test anywhere: [[ ]] evaluates a body like a[$(cmd)] there as arithmetic.)
grep -qE "$ghreparse" <<<"$ghl" || grep -qE '(^|[[:space:]])-(eq|ne|lt|le|gt|ge|v)([[:space:]]|$)' <<<"$ghl" ||
  ghi=$(sed -E "s/((^|[^A-Za-z0-9_.-])(\\[|\\[\\[|test|case)[[:space:]]+\"(\\\$\\(|\`)[[:space:]]*)gh($ghro)/\\1_\\5/g" <<<"$ghl") || exit 1
# And a line of nothing but echo calls (in one for loop too) whose words are plain text, $var and read-only
# $(gh …) calls of plain words: echo "#$n $(gh pr view $n -R O/R --json state)", a coordinator's PR-state check. The
# output is only printed. An allowlist of that one shape, since anything more can run it: a pipe, redirect, (, {, [
# (arithmetic, a[$(cmd)]), a quote or backslash, a # (a comment hides a newline), any command but echo. The loop
# variable is lower case (for PATH in … would pick the gh that runs). An unquoted $(gh …) is also
# read as a call by the token walk below, which lets a plain $var through only past a read-only group and verb.
ghrv=${ghro%'([^A-Za-z0-9_.-]|$)'}
ghrp="\\\$\\([[:space:]]*gh$ghrv([[:space:]][A-Za-z0-9_.,/=:@%+\$[:space:]-]*)?\\)"
ghph=$(sed -E "s#$ghrp#_GHRO_#g" <<<"$ghl") || exit 1
ghew='[A-Za-z0-9_.,/=:@%+-]' ghv='\$[A-Za-z_][A-Za-z0-9_]*'
ghe="echo([[:space:]]+(($ghew|$ghv)+|\"([A-Za-z0-9_.,/=:@%+#-]|[[:space:]]|$ghv)*\")+)*"
grep -qE "^[[:space:]]*(for[[:space:]]+[a-z_][a-z0-9_]*[[:space:]]+in([[:space:]]+$ghew+)*[[:space:]]*;[[:space:]]*do[[:space:]]+)?$ghe([[:space:]]*;[[:space:]]*$ghe)*([[:space:]]*;[[:space:]]*done)?[[:space:]]*;?[[:space:]]*\$" <<<"$ghph" &&
  ghi=$ghph
grep -qE "$ghind" <<<"$ghi" &&
  attended "Blocked: gh reached through a variable or \$(…) can't be checked by the approval hook. Run it by its name (gh …), as one plain command."
alone="Run that CLI call alone, as one plain command (the CLI, then its subcommand, then the arguments)."
# Fails closed on anything it can't read as exactly one call: a second CLI call (chained, or glued to a token), a
# subcommand behind global flags or a variable.
# (npx -p PKG msgraph …: the package and the binary it runs are one call.)
bbn=$(sed -E 's/msgraph-cli(@[^[:space:]]*)?[[:space:]]+msgraph([[:space:]]|$)/msgraph-cli /g' <<<"$scan" |
  grep -oE "bitbucketdc-cli|forgejo-cli|jiradc-cli|$msw([[:space:]]|$)" | wc -l | tr -d ' ')
[ -z "$bbops" ] || [ "$bbn" = 1 ] ||
  decide deny "Blocked: a PR/Jira comment post, review, PR merge or Teams/mail send must be the only bitbucketdc-cli/forgejo-cli/jiradc-cli/msgraph call in its command. $alone"

# Tokens, quotes honoured (xargs fails on an unbalanced quote: a heredoc's text, say). An unquoted ; becomes a token
# of its own first, so x; ends a call and a quoted 'x;' (a --subject value) doesn't.
tokstr=$(printf '%s' "$cmd" | awk -v q="'" '{ s = s (NR > 1 ? "\n" : "") $0 } END { n = length(s)
  for (j = 1; j <= n; j++) { c = substr(s, j, 1)
    if (iq != q && c == "\\") { o = o c substr(s, j + 1, 1); j++; continue }
    if (iq == "") { if (c == "\"" || c == q) iq = c; else if (c == ";") { o = o " ; "; continue } } else if (c == iq) iq = ""
    o = o c }
  printf "%s", o }' | xargs printf '%s\n' 2>/dev/null) && [ -n "$tokstr" ] ||
  { [ -z "$bbops" ] && ! grep -qE "$ghops" <<<"$scan" && pass; decide deny "Blocked: this command mentions a PR/Jira comment post or a PR merge, and the approval hook can't parse it. $alone"; }
toks=()
while IFS= read -r t; do toks+=("$t"); done <<<"$tokstr"
# Walk the tokens: each CLI call (up to |, ;, &&, ||) is read as SUB TARGET [flags]; a gh call (gh where a command
# starts) as GROUP VERB TARGET with its flags anywhere.
groups=' agent-task alias api attestation auth browse cache codespace completion config copilot extension gist gpg-key help issue label org pr preview project release repo ruleset run search secret ssh-key status variable version workflow '
calls=0 ghcalls=0 apiw= kind= target= repo= bodyfile= body= help= host= mode= modes=0 fj= cm= crk= crf= crt= crx=() crn= bbc=
i=0 st=1
while [ "$i" -lt "${#toks[@]}" ]; do
  t=${toks[$i]}; i=$((i + 1)); prev=; [ "$i" -lt 2 ] || prev=${toks[$((i - 2))]}
  b=${t%;}; b=${b#\(}; b=${b#\$\(}; b=${b%\)}
  # Where a command starts: first, after a separator, or after a command prefix (env, VAR=x, sudo …) that itself
  # starts one (brew list rtk gh: rtk there is an argument, so gh is too).
  case "$prev" in ''|'|'|'||'|'&&'|';'|'&'|'('|'$(') st=1 ;;
    env|command|rtk|proxy|exec|time|nohup|sudo|xargs|then|do|else|'!'|'{'|if|while|until|[A-Za-z_]*=*) ;; *) st= ;; esac
  case "$t" in
    *bitbucketdc-cli*|*forgejo-cli*|*jiradc-cli*) h= ;;
    msgraph|*/msgraph|*msgraph-cli|*msgraph-cli@*) h=ms ;;
    *) [ "${b##*/}" = gh ] || continue
       [ -n "$st" ] || [ "$t" != "$b" ] || continue
       [ "$prev" != xargs ] || attended "Blocked: gh run through xargs can't be checked by the approval hook. $alone"
       h=gh ;;
  esac
  cli=$t args=()
  while [ "$i" -lt "${#toks[@]}" ]; do
    a=${toks[$i]}; case "$a" in '|'|'||'|'&&'|';'|'&') break ;; esac
    i=$((i + 1)); args+=("${a%)}")
  done
  if [ "$h" = ms ]; then
    [ "${args[0]:-}" != msgraph ] || args=("${args[@]:1}")   # npx -p PKG msgraph …
    case "${args[*]:0:3}" in
      'message send'*|'message update'*) mv="${args[1]} teams message" ;;
      'mail send'*) mv="send mail" ;; 'mail reply'*) mv="reply to mail" ;; 'mail forward'*) mv="forward mail" ;;
      'mail draft send'*|'mail scheduled send'*|'mail rule create'*|'mail rule update'*|'calendar create'*|'calendar update'*|'calendar cancel'*|'calendar respond'*|'file grant'*)
        attended "Blocked: msgraph ${args[*]:0:3} sends or forwards under the user's name, and what it sends can't be named by a body file's sha256. Hand the user the command with hand_command." ;;
      *) continue ;;
    esac
    # Its words go into the action: a variable or $(…) there could change after the approval.
    case "${args[*]}" in *'$'*|*'`'*) attended "Blocked: msgraph with a variable or \$(…) in its words can't be checked by the approval hook. Write every recipient and value out. $alone" ;; esac
    calls=$((calls + 1)); host= kind=send target= repo= bodyfile= body= mode= modes=0 cm= fj= att= msx=()
    # Everything the call sends but the body goes into the action word for word, in the command's order; the first
    # plain word is the chat or message id.
    set -- "${args[@]:2}"
    while [ $# -gt 0 ]; do
      case "$1" in --*=*) set -- "${1%%=*}" "${1#*=}" "${@:2}" ;; esac
      case "$1" in
        -h|--help|--draft|--dry-run) help=1 ;;
        --body-file|--comment-file) bodyfile=${2:-}; shift ;;
        --body|--comment) body=1; shift ;;
        --pretty) ;;
        # --format too: text and html render the same file differently.
        --format|--importance|--reply-to|--subject|--team-id|--message-id|--send-at|--mailbox) msx+=("$1 ${2:-}"); shift ;;
        # Variadic: every word up to the next option.
        --to|--cc|--bcc|--add-to|--remove-to|--add-cc|--remove-cc|--mention|--attachments)
          [ "$1 ${args[0]}" != '--attachments mail' ] || att=1
          # A Teams attachment is named with its sha256 too, so the approval covers the file it sends.
          v=$1 f=$1; while [ $# -gt 1 ] && [[ $2 != -* ]]; do
            x=$2
            if [ "$f" = --attachments ] && [ -z "$att" ]; then
              case "$x" in /*) ;; *) decide deny "Blocked: give each attachment as an absolute path, so the approval can name its sha256." ;; esac
              [ -f "$x" ] || decide deny "Blocked: no such attachment: $x"
              x="$x (sha256 $(shasum -a 256 "$x" | cut -d' ' -f1))"
            fi
            v="$v $x"; shift; done; msx+=("$v") ;;
        -*) msx+=("$1") ;;
        *) if [ -z "$target" ]; then target=$1; else msx+=("$1"); fi ;;
      esac
      shift
    done
    # The key a relay with no tracker key is verified with: the chat or message id, or the first --to address.
    mshort=$target
    for v in ${msx[@]+"${msx[@]}"}; do [ -n "$mshort" ] || [[ $v != '--to '* ]] || { mshort=${v#--to }; mshort=${mshort%% *}; }; done
    what="${target:+$target }${msx[*]:-}"; what=${what% } target=$what
    continue
  fi
  if [ -z "$h" ]; then
    sub="${args[*]:0:3}"
    case "$cli:$sub" in
      *bitbucketdc-cli*:'pr merge'*) k=merge; s=2 ;;
      *bitbucketdc-cli*:'pr comment create'*|*bitbucketdc-cli*:'pr comment reply'*|*bitbucketdc-cli*:'pr comment update'*) k=prpost; s=3 ;;
      *bitbucketdc-cli*:'pr create'*|*forgejo-cli*:'pr create'*) k=create; s=2 ;;
      *forgejo-cli*:'pr merge'*) k=merge; s=2 ;;
      *forgejo-cli*:'pr review'*) k=review; s=2 ;;
      *forgejo-cli*:'pr comment create'*|*forgejo-cli*:'pr comment update'*) k=prpost; s=3 ;;
      *jiradc-cli*:'issue comment create'*|*jiradc-cli*:'issue comment update'*) k=jirapost; s=3 ;;
      *) continue ;;
    esac
    calls=$((calls + 1)); host= kind=$k target= repo= bodyfile= body= mode= modes=0 cm= fj=
    case "$cli" in *forgejo-cli*) fj=1 ;; esac
    if [ "$k" = create ]; then
      crk=pr crx=() crt= crf= crn=${cli##*/} bbc=; crn="${crn%%@*} pr create"; [ -n "$fj" ] || bbc=1
      # forgejo-cli's flags, word for word like gh's; bitbucketdc-cli's aren't read here (bbc: it can't be relayed).
      # Help only right after create: later, it may be an unknown flag's value.
      case "${args[2]:-}" in -h|--help) help=1 ;; esac
      set -- "${args[@]:2}"
      while [ $# -gt 0 ]; do
        case "$1" in --*=*) set -- "${1%%=*}" "${1#*=}" "${@:2}" ;; esac
        case "$1" in
          --repo) repo=${2:-}; shift ;;
          --description-file) bodyfile=${2:-}; shift ;;
          --description) body=1; shift ;;
          --title) crt=1; crx+=("$1 ${2:-}"); shift ;;
          --from|--to|--reviewers) crx+=("$1 ${2:-}"); shift ;;
          *) crx+=("$1") ;;
        esac
        shift
      done
      continue
    fi
    set -- "${args[@]:$s}"
    while [ $# -gt 0 ]; do
      case "$1" in
        -h|--help) help=1 ;;
        --repo) repo=${2:-}; shift ;; --repo=*) repo=${1#*=} ;;
        --body-file|--comment-file) bodyfile=${2:-}; shift ;; --body-file=*|--comment-file=*) bodyfile=${1#*=} ;;
        --body|--comment) body=1; shift ;; --body=*|--comment=*) body=1 ;;
        # forgejo-cli pr review's verdict; NEEDS_WORK is its alias for REQUEST_CHANGES.
        --status|--status=*) v=${2:-}; if [ "$1" = --status ]; then shift; else v=${1#*=}; fi
          case $(tr a-z A-Z <<<"$v") in APPROVED) mode=approve ;; REQUEST_CHANGES|NEEDS_WORK) mode=request-changes ;; COMMENT) mode=comment ;; *) mode= ;; esac
          [ -z "$mode" ] || modes=$((modes + 1)) ;;
        --comments|--comments-file) cm=1; shift ;; --comments=*|--comments-file=*) cm=1 ;;
        --project|--strategy|--parent-id|--path|--line|--line-type|--file-type|--comment-id) shift ;;
        -*) ;;
        *) [ -n "$target" ] || target=$1 ;;
      esac
      shift
    done
    continue
  fi
  # gh: flags anywhere; the first two other words are GROUP VERB, the third the target.
  ghcalls=$((ghcalls + 1))
  pos=() r= bf= bd= hp= md= mc=0 meth= fields=
  set -- ${args[@]+"${args[@]}"}
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) hp=1 ;;
      -R|--repo) r=${2:-}; shift ;; --repo=*) r=${1#*=} ;;
      # -F is a body file, or an api field (gh api -F k=v).
      -F|--body-file) bf=${2:-}; fields=1; shift ;; --body-file=*) bf=${1#*=} ;;
      -b|--body) bd=1; shift ;; --body=*) bd=1 ;;
      -X|--method) meth=${2:-}; shift ;; --method=*) meth=${1#*=} ;; -X?*) meth=${1#-X} ;;
      -f|--field|--raw-field|--input) fields=1; shift ;; --field=*|--raw-field=*|--input=*|-f?*|-F?*) fields=1 ;;
      -a|--approve) md=approve; mc=$((mc + 1)) ;;
      -r|--request-changes) md=request-changes; mc=$((mc + 1)) ;;
      -c|--comment) md=comment; mc=$((mc + 1)) ;;
      -t|--subject|--title|-A|--author-email|--match-head-commit|--hostname|-H|--header|-q|--jq|--template|-p|--preview) shift ;;
      -*) ;;
      *) pos+=("$1") ;;
    esac
    shift
  done
  # Its words must be plain: a variable or $(…) there, or an unknown group (an alias), can't be read.
  # A plain $var past a plain read-only group and verb (a status poll's `for n in …; do gh pr view $n`) reads only.
  case "${pos[*]:-}" in *'$('*|*'`'*) ro= ;; *) ro=1 ;; esac
  [[ -n $ro && "${pos[0]:-}${pos[1]:-}" != *'$'* ]] && grep -qE "^$ghro" <<<" ${pos[0]:-} ${pos[1]:-}" || ro=
  [ -n "$ro" ] || case "${pos[*]:-}" in *'$'*|*'`'*) attended "Blocked: gh with a variable or \$(…) in its words can't be checked by the approval hook. $alone" ;; esac
  { [[ ${pos[0]:-} != *[[:space:]]* ]] && { [[ ${pos[0]:-} != pr && ${pos[0]:-} != issue ]] || [[ ${pos[1]:-} != *[[:space:]]* ]]; }; } ||
    attended "Blocked: gh with a quoted run of words as its command (gh pr 'merge 5') can't be checked by the approval hook. $alone"
  [ -z "${pos[0]:-}" ] || [[ $groups == *" ${pos[0]} "* ]] ||
    attended "Blocked: \"gh ${pos[0]}\" isn't a gh command the approval hook knows (an alias?). Run the gh command it stands for, as one plain command."
  case "${pos[*]:0:2}" in
    'pr merge') k=merge ;;
    'pr comment'|'issue comment') k=prpost ;;
    'pr review') k=review ;;
    # create's flags aren't the others' (-a assignee, -r reviewer, -f fill, -B base): its words are read again.
    'pr create'|'issue create') k=create crk=${pos[0]} crx=() r= bf= bd= hp= crt= cro= crn="gh ${pos[0]} create" bbc=
      set -- ${args[@]+"${args[@]}"}
      while [ $# -gt 0 ]; do
        case "$1" in --*=*) set -- "${1%%=*}" "${1#*=}" "${@:2}" ;; esac
        case "$1" in
          -h|--help|--dry-run) hp=1 ;;
          -R|--repo) r=${2:-}; shift ;;
          -F|--body-file) bf=${2:-}; shift ;;
          -b|--body) bd=1; shift ;;
          # They fill in text (commits, a template, an editor, the browser) the approval can't name.
          -f|--fill|--fill-first|--fill-verbose|-e|--editor|-w|--web|-T|--template|--recover) crf=$1; [ "$1" = -T ] || [ "$1" = --template ] || [ "$1" = --recover ] && shift ;;
          -t|--title) crt=1; crx+=("$1 ${2:-}"); shift ;;
          -H|--head) crx+=("$1 ${2:-}"); shift ;;
          -B|--base|-l|--label) crx+=("$1 ${2:-}"); shift ;;
          # cro: the flags feedback.send auto refuses (glued -F/path included: gh reads it as the body file)
          -a|--assignee|-r|--reviewer|-m|--milestone|-p|--project) cro+=" $1"; crx+=("$1 ${2:-}"); shift ;;
          -d|--draft) crx+=("$1") ;;
          -*) cro+=" $1"; crx+=("$1") ;;
        esac
        shift
      done ;;
    # A create misread above (a value flag before the verb: gh pr -B main create) still counts.
    'pr '*|'issue '*) [[ " ${pos[*]:2} " != *" create "* ]] || [[ ${pos[1]} =~ ^(list|view|status|diff|checks|edit|close|reopen|comment|merge|review|ready|checkout|lock|unlock|develop|delete|pin|unpin|transfer|revert|update-branch)$ ]] ||
        attended "Blocked: gh ${pos[0]} with a flag before create can't be checked by the approval hook. Put the flags after: gh ${pos[0]} create -R OWNER/REPO …"
      continue ;;
    # gh api sends fields as a POST unless -X says otherwise. A graphql query given inline (no =@file, --input, $
    # outside '…' (a GraphQL $variable inside one is text), or unquoted brace or glob that could rebuild one) with no
    # mutation, quotes ignored, only reads.
    'api graphql') printf '%s' "$cmd" | awk -v q="'" '{ s = s $0 "\n" } END { n = length(s)
          for (j = 1; j <= n; j++) { c = substr(s, j, 1)
            if (iq == q) { if (c == q) iq = ""; continue }
            if (c == "\\") j++; else if (c == "\"") iq = iq == "" ? c : ""; else if (c == q && iq == "") iq = q
            else if (c == "$" || c == "`" || iq == "" && index("{[*?", c)) exit 0 }
          exit 1 }'
      # (exit 1 only: an awk error counts as a write)
      [ $? = 1 ] && [ -z "$meth" ] && ! tr -d "\"'\\\\" <<<"$cmd" | grep -qiE 'mutation|=@|--input' || apiw=1; continue ;;
    api*) m=$(tr a-z A-Z <<<"$meth"); [ "${m:-${fields:+POST}}" = "" ] || [ "$m" = GET ] || apiw=1; continue ;;
    *) continue ;;
  esac
  calls=$((calls + 1)); host=$h kind=$k target=${pos[2]:-} repo=$r bodyfile=$bf body=$bd mode=$md modes=$mc
  [ -z "$hp" ] || help=1
done
[ -z "$apiw" ] || attended "Blocked: a gh api call that writes (a method other than GET, or fields) can't be named as an approved action. Use gh pr merge|comment|review, or hand the user the command with hand_command."
if [ "$calls" = 0 ]; then
  # Only read-only gh calls (pr list, issue view, api GET) or gh as a word: nothing to gate. A post or merge the walk
  # couldn't find as a call (quoted, glued, inside bash -c) fails closed.
  [ -z "$bbops" ] && { [ "$ghn" = "$ghcalls" ] || ! grep -qE "$ghops" <<<"$scan"; } && pass
  decide deny "Blocked: the approval hook can't read this as one PR/Jira comment post or PR merge. $alone"
fi
# Each read-only gh mention is one, never the gated call too: a hidden second post or merge still counts.
[ "$host" = gh ] || ghron=0
[ "$calls" = 1 ] && [ $((bbn + ghn - ghron)) = 1 ] ||
  decide deny "Blocked: a PR/issue comment post, review, merge or Teams/mail send must be the only bitbucketdc-cli/forgejo-cli/jiradc-cli/msgraph/gh call in its command (a gh one may share it with plain read-only gh calls: gh pr view|checks, gh run view|watch). $alone"
[ -z "$help" ] || pass
if [ "$kind" = create ]; then
  # An apply session (first prompt from feedback brief): its create on the plugin's repo is scrubbed below first.
  # (-R as given, a URL or HOST/ form too, any case as GitHub's: a wider match only scrubs more)
  fb="$here/../skills/orchestrating-sessions/feedback" fbr=$("$here/../skills/orchestrating-sessions/feedback" repo 2>/dev/null | tr A-Z a-z)
  apply=; [ -n "$fbr" ] && [ -f "$tp" ] && grep -qE '^Work on [^ :]+: Apply plugin feedback: ' <<<"$(first_prompt "$tp" | head -n 1)" &&
    [[ -z $repo || $(tr A-Z a-z <<<"$repo") == *"$fbr"* ]] && apply=1
  # approvals.pr_create: the session opens its own task's PR without an ask (an issue still asks).
  prc=; [ "$crk" != pr ] || [ "$(cd "$cwd" 2>/dev/null && . "$here/../lib.sh" >/dev/null 2>&1 && config approvals.pr_create 2>/dev/null)" != true ] || prc=1
  [ -z "$prc" ] || [ -n "$apply" ] || pass
  [ -z "$bbc" ] || attended "Blocked: $crn can't be named as an approved action (the approval hook doesn't read its flags). Hand the user the command with hand_command."
  [ -z "$crf" ] || attended "Blocked: gh $crk create $crf fills in text the approval can't name. Give --title and --body-file <absolute path>, or hand the user the command with hand_command."
  [ -n "$crt" ] || decide deny "Blocked: give $crn its --title, so the approval can name it."
  # the action names the text as written: a variable or $(…) there could hold anything when it runs
  [[ "${crx[*]:-}$bodyfile$repo" != *[\$\`]* ]] || attended "Blocked: $crn with a \$ or backtick in its flags, repo or body file: the approval names them as written, not what they expand to. Write the values out."
  target=$crk
fi
[ -n "$target" ] || decide deny "Blocked: no PR id, issue key, chat, message id or recipient in this command."
short=
if [ -n "$host" ]; then
  # OWNER/REPO, from -R ([HOST/]OWNER/REPO or a URL) or the target's URL; the two must agree. A host other than
  # github.com stays in front (HOST/OWNER/REPO), so an approval for one host's PR doesn't cover another's.
  grep -qE '(^|[[:space:]])GH_HOST=' <<<"$cmd" && decide deny "Blocked: name the host in -R HOST/OWNER/REPO, not GH_HOST. $alone"
  norm() { local x=${1%/}; x=${x%.git}; x=${x#*://}; x=${x#github.com/}; echo "$x"; }
  if [[ $target =~ ^https?://([^/]+/[^/]+/[^/]+)/(pull|issues)/([0-9]+)/?$ ]]; then
    u=$(norm "${BASH_REMATCH[1]}") target=${BASH_REMATCH[3]}
    [ -z "$repo" ] || [ "$(norm "$repo")" = "$u" ] ||
      decide deny "Blocked: -R names $(norm "$repo") but the URL is in $u. Name one repository."
    repo=$u
  fi
  [ -z "$repo" ] || repo=$(norm "$repo")
  [[ $repo == */* ]] ||
    decide deny "Blocked: name the repository as -R OWNER/REPO (or give the PR's URL), so the approval can name OWNER/REPO#ID; gh's default repo isn't read here."
  if [ "$kind" = create ]; then what=$repo
  else
    [[ $target =~ ^[0-9]+$ ]] || decide deny "Blocked: the PR or issue id must be a number (or its URL), not a branch or nothing."
    what="$repo#$target" short="${repo##*/}#$target"
  fi
else
  case $kind in
    merge|prpost|review) [[ $target =~ ^[0-9]+$ ]] || decide deny "Blocked: the PR id must be a number."
                  [ -n "$repo" ] || decide deny "Blocked: name the repository with --repo, so the approval can name REPO#ID."
                  [ -z "$fj" ] || [[ $repo == */* ]] || decide deny "Blocked: name the repository as --repo OWNER/REPO, so the approval can name OWNER/REPO#ID."
                  what="$repo#$target"; [ -z "$fj" ] || short="${repo##*/}#$target" ;;
    jirapost) what=$target ;;
    create) [[ $repo == */* ]] || decide deny "Blocked: name the repository as --repo OWNER/REPO, so the approval can name it."
            what=$repo ;;
    send) short=$mshort
          [ -z "$att" ] || decide deny "Blocked: mail attachments can't be named by the body file's sha256. Send the text alone, or hand the user the command with hand_command." ;;
  esac
fi
if [ "$kind" = review ]; then
  [ "$modes" = 1 ] || decide deny "Blocked: give the review exactly one verdict (gh: one of --approve, --request-changes or --comment; forgejo-cli: --status APPROVED, REQUEST_CHANGES or COMMENT)."
  # Inline comments are text the body file's sha256 doesn't cover.
  [ -z "$cm" ] || decide deny "Blocked: a review's inline comments (--comments, --comments-file) can't be named by one sha256. Post each with forgejo-cli pr comment create --path --line --body-file <absolute path>, one approval each."
  # A review that approves with no body is a bare approval.
  [ "$mode$body$bodyfile" != approve ] || kind=approve
fi

if [ "$kind" = merge ] || [ "$kind" = approve ]; then
  action="$kind $what"
else
  bf='--body-file <absolute path>'; [ "$kind" != send ] || bf="$bf (mail forward: --comment-file)"
  [ "$kind$fj" != create1 ] || bf='--description-file <absolute path>'
  [ -z "$body" ] || decide deny "Blocked: post the comment with $bf, not inline text, so the approval can name the file's sha256."
  [ -n "$bodyfile" ] && [ "$bodyfile" != - ] || decide deny "Blocked: post the comment with $bf, so the approval can name the file's sha256."
  case "$bodyfile" in /*) ;; *) decide deny "Blocked: give the body file as an absolute path: $bf." ;; esac
  [ -f "$bodyfile" ] || decide deny "Blocked: no such body file: $bodyfile"
  # An apply session's create on the plugin's own repo, under feedback.send auto (the person's standing yes for plugin
  # feedback) or approvals.pr_create, passes once feedback scrub finds nothing personal in its flags and body. A hit
  # goes the relay way with the scrub's lines, so the user can still pass a false positive.
  # Cheapest test first: feedback repo and config each source lib.sh, and the scrub is slow (up to a minute on a busy
  # machine: hooks.json gives this hook 180 s).
  if [ "$kind" = create ] && [ -n "$apply" ] && [ "$host" = gh ] && [ "$(tr A-Z a-z <<<"$repo")" = "$fbr" ]; then
    auto=; [ "$(cd "$cwd" 2>/dev/null && . "$here/../lib.sh" >/dev/null 2>&1 && config feedback.send 2>/dev/null)" != auto ] || auto=1
    if [ -n "$auto$prc" ]; then
      # (a glued -F/path among them: gh reads it as the body file, which the scrub below wouldn't see)
      [ -z "$cro" ] || decide deny "Blocked: under feedback.send auto (or approvals.pr_create in an apply session), gh $crk create takes only -R, -t/--title, -F/--body-file <absolute path> (space-separated), -l/--label, -B/--base, -H/--head and -d/--draft; not:$cro. Drop it and run it again."
      # The scrubbed flags: all, but -H only its branch, and not when it is the session's own (its name, which matches
      # key_pattern): its fork owner is public, and git push publishes that branch anyway.
      own=$(git -C "$cwd" branch --show-current 2>/dev/null)
      ft=$(mktemp) || exit 1
      for x in ${crx[@]+"${crx[@]}"}; do case $x in
        '-H '*|'--head '*) x=${x#* }; x=${x#*:}; [ "$x" = "$own" ] || printf -- '-H %s\n' "$x" ;;
        *) printf '%s\n' "$x" ;; esac; done > "$ft"
      out=$("$fb" scrub "$ft" "$bodyfile" 2>&1); fr=$?; rm -f "$ft"
      [ "$fr" != 0 ] || pass
      hit="feedback scrub found something personal in this gh $crk create (the flags or $bodyfile):
${out//"$ft"/the flags}
Reword it and run it again. Only if every line is a false positive (a commit SHA, a test key in quoted code), ask:"
    fi
  fi
  [ "$kind" != create ] || [ -z "$prc" ] || [ -n "$hit" ] || pass
  sha=$(shasum -a 256 "$bodyfile" | cut -d' ' -f1); [ "${#sha}" = 64 ] || exit 1
  if [ "$kind" = review ]; then action="post $mode review $bodyfile on $what (sha256 $sha)"
  elif [ "$kind" = send ]; then action="$mv $bodyfile to $what (sha256 $sha)"
  elif [ "$kind" = create ]; then x=${crx[*]:-}; action="create $crk on $what from $bodyfile (sha256 $sha)${x:+ $x}"
  else action="post comment $bodyfile on $what (sha256 $sha)"; fi
fi

else
  kind=merge what=$landing target=$landing short= host= fj= action="merge $landing"
  # session-status --land OWNER/REPO#N (the same regex it uses) merges a GitHub PR: gated as gh pr merge N -R OWNER/REPO,
  # so one relay covers either command, used once over both.
  if [[ $landing =~ ^([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)#([0-9]+)$ ]]; then
    host=gh repo=${BASH_REMATCH[1]} target=${BASH_REMATCH[2]} short=${BASH_REMATCH[1]##*/}#${BASH_REMATCH[2]}
  fi
fi
# The relays this session received: peer messages from another session (not a subagent's hand-back), newest
# first: sender name, quote, action, source sessionId, source cwd, the transcript it came in (tab-free JSON lines).
# A handover's successor (`Supersedes: ID` in its first prompt, ID's transcript beside its own) also has the relays
# its predecessors received, so an approval relayed before the handover still holds; each is used once over the chain.
[ -f "$tp" ] || ask_for "$action" "$action" "$what"
relays= f=$tp hops=0
while [ -f "$f" ] && (( hops++ < 20 )); do
  ! grep -q 'APPROVAL relayed from the user' "$f" || relays="$(jq -c --arg f "$f" '
    (if .type == "user" then .origin elif .type == "attachment" and .attachment.type == "queued_command" then .attachment.origin else null end) as $o
    | select($o.kind? == "peer" and (($o.from // "") | startswith("uds:")) and ($o.handback | not))
    | ($o.body // "") as $b
    | $b | [scan("APPROVAL relayed from the user\\nQuote: ([\\s\\S]*?)\\nAction: ([^\\n]*)\\nSource: ([0-9a-f-]{36}) ([^\\n]+)")]
    | .[] | {name: $o.name, quote: .[0], action: .[1], sid: .[2], scwd: .[3], tp: $f}' "$f" 2>/dev/null)${relays:+
$relays}" || exit 1   # the predecessor's go first: older, and the loop below reads newest first
  first=$(first_prompt "$f")
  sup=$(grep -m1 -oE 'Supersedes: [0-9a-f]{8}-[0-9a-f-]{27}' <<<"$first") || break; sup=${sup#Supersedes: }
  # --handover's task prompt names the predecessor's transcript (another account's projects folder, maybe); a chunk's
  # doesn't: then it is beside this one's.
  nf=$(grep -m1 -oE "Supersedes: $sup \\(transcript [^;]+;" <<<"$first"); nf=${nf#*(transcript }; nf=${nf%;}
  [ "${nf##*/}" = "$sup.jsonl" ] && f=$nf || f=$(dirname "$tp")/$sup.jsonl
done
# A relay counts for this command when its Action names the target as a whole word, and the sha256 for a post or
# "merge"/"approve" with no sha256 for a merge or bare approval (a gh review: its kind and "review" too); then the quote must verify, with the task key the Action names.
tried= me=$(jq -r 'select(.type == "agent-name") | .agentName // empty' "$tp" 2>/dev/null | tail -1) now=$(date +%s)
# The user's Yes on the coordinator pane to an ask that names this session as the one that runs its action: the pane
# wrote a grant (register.tsx writeGrant; coordinator-guard keeps sessions from writing one), good for a day, to this
# session's name or an 8+ hex prefix of its id. Last line: tried first.
for g in ~/.cache/session-status/grants/act-*.json; do
  [ -f "$g" ] || continue
  l=$(jq -c --arg me "$me" --arg sid "$sid" --argjson now "$now" --arg f "$g" '
    select(.kind == "action" and ([.action, .quote, .session, .key] | all(type == "string")) and (.at | type == "number")
      and .at >= $now - 86400 and .at <= $now + 5
      and (.session as $s | ($s == $me and $me != "") or (($s | test("^[0-9a-f]{8}[0-9a-f-]*$")) and ($sid | startswith($s)))))
    | {grant: 1, name: .session, quote, action, tp: $f}' "$g" 2>/dev/null) || continue
  [ -z "$l" ] || relays=${relays:+$relays
}$l
done
while IFS= read -r r; do
  [ -n "$r" ] || continue
  act=$(jq -r .action <<<"$r") alt= hint=
  # A send names all it sends: the whole action, word for word (none dropped or added, not another verb or target).
  if [ "$kind" = send ] || [ "$kind" = create ]; then grep -qF -- "$action" <<<"$act" || continue
    # a create's flags end its action: after them only the key or the session's name, so none was cut short
    [ "$kind" != create ] || [[ ${act#*"$action"} =~ ^([[:space:]]+for[[:space:]]+[A-Z][A-Z0-9]+-[0-9]+)?([[:space:]]*\([^()]*\))?[.[:space:]]*$ ]] || continue
  else w=${what//./\\.}; grep -qE "(^|[^A-Za-z0-9#/.-])$w([^A-Za-z0-9]|$)" <<<"$act" || continue; fi
  if [ "$kind" = merge ] || [ "$kind" = approve ]; then
    grep -qiE "(^|[^a-z])$kind([^a-z]|$)" <<<"$act" && ! grep -qE '[0-9a-f]{64}' <<<"$act" || continue
  else
    grep -qF "$sha" <<<"$act" || continue
    # A gh comment's relay isn't a review's, and a review's names its kind: read outside the body file's path,
    # whose name may hold either word (…-review-pr-12-comment.md).
    nb=${act//"$bodyfile"/}
    [ "$kind" != prpost ] || [ -z "$host$fj" ] || ! grep -qiw review <<<"$nb" || continue
    [ "$kind" != review ] || { grep -qiE "(^|[^a-z-])$mode([^a-z-]|$)" <<<"$nb" && grep -qiw review <<<"$nb"; } || continue
  fi
  # A pane grant is the user's click itself, written by the pane: no quote to verify.
  if [ "$(jq -r '.grant // empty' <<<"$r")" = 1 ]; then v="verified: the user's Yes on the coordinator pane: $(jq -r .quote <<<"$r")"
  else
    # (A send's key from outside its action: a subject or id there may hold words like UTF-8.)
    a=$act; [ "$kind" != send ] && [ "$kind" != create ] || a=${act/"$action"/}
    key=$target; [ "$kind" = jirapost ] || key=$(grep -oE '[A-Z][A-Z0-9]+-[0-9]+' <<<"$a" | head -1)
    # A merge is the task's landing, which approving the task covers: with session-name keys, an Action ending
    # "(<this session's name>)" is verified with that name, so the user's yes to the task itself verifies. A yes given
    # under another key whose answer started this session with its landing (a design task's pane ask): "(<this
    # session's name>, approved under <that key>)", verified with that key.
    # (A sentence's closing . after the bracket is allowed: it claims nothing.)
    if [ -z "$key" ] && { [ "$kind" = merge ] || [ "$kind" = create ]; } && [[ $act =~ \(([A-Za-z0-9][A-Za-z0-9._-]*)(,[[:space:]]*approved[[:space:]]+under[[:space:]]+([A-Za-z0-9][A-Za-z0-9._-]*))?\)[[:space:]]*\.?[[:space:]]*$ ]]; then
      nm=${BASH_REMATCH[1]} under=${BASH_REMATCH[3]}
      [ "$nm" = "$me" ] || hint=" (its Action names the session $nm, but this session is ${me:-unnamed})"
      # Under another key, the yes itself must speak of the landing: a yes to start some task approves no merge.
      if [ -n "$under" ] && ! jq -r .quote <<<"$r" | sed 's/ Asked:.*//' | grep -qiE '(^|[^a-z])(land|merg)'; then
        tried=${tried:-"the quote approved under $under doesn't speak of landing or merging"}; fault not-landing relay; continue; fi
      [ "$nm" != "$me" ] || key=${under:-$me}
      # A coordinator may have asked under the name without its project prefix (the "<project>-" of its own
      # "<project>-coordinator"): that key verifies the yes too, only as a pane answer asked under exactly it
      # (a short name is often a plain word a typed yes merely mentions).
      sn=$(jq -r .name <<<"$r"); pfx=${sn%-coordinator*}-
      if [ "$nm" = "$me" ] && [ -z "$under" ] && [[ $sn == ?*-coordinator* && $me == "$pfx"?* ]] &&
         [[ $(jq -r .quote <<<"$r") == "Approval pane answer for ${me#"$pfx"}:"* ]]; then alt=${me#"$pfx"}; fi
    elif [ -z "$key" ] && [ "$kind" = merge ] && [[ $act =~ \([A-Za-z0-9][^\)]*\)[^\)]*[^[:space:].\)][^\)]*$ ]]; then
      # A hand-written Action with words after its bracket (a merge instruction) isn't the landing form: say which is.
      hint=" (its Action has text after the closing bracket: relay exactly \"merge $what (<session name>)\", or \"merge $what (<session name>, approved under KEY)\", with nothing after it: session-status --relay KEY writes that)"
    fi
    # No tracker key (session-name keys): the user's words must name the target itself (REPO#ID; OWNER/ may precede).
    [ -n "$key" ] || key=$short
    [ -n "$key" ] || { tried=${tried:-"the matching relay's Action names no task key"}; fault no-key relay; continue; }
    v1=
    for k in "$key" ${alt:+"$alt"}; do
      v=$(cd "$cwd" 2>/dev/null && jq -r .quote <<<"$r" |
          bash "$here/../skills/orchestrating-sessions/verify-approval.sh" "$(jq -r .sid <<<"$r")" "$(jq -r .scwd <<<"$r")" "$(jq -r .name <<<"$r")" "$k" "$act")
      [[ $v != verified* ]] || break
      v1=${v1:-$v}
    done
    # Both keys failed: the deny gives the full key's reason.
    [[ $v == verified* ]] || v=${v1:-$v}
  fi
  # One use per relay: a rerun (the CLI timed out after the server took it) needs a new approval.
  # ponytail: used up when allowed, not when the command succeeds; the deny says to check before asking again. A gh
  # merge whose PR is still open with no auto-merge queued (gh refused it: --auto on a clean PR) didn't use it, while
  # the PR's head is the one the first run saw (the used stamp holds it): new commits need a new approval.
  used=~/.cache/session-status/approved/$(printf '%s|%s|%s' "$(jq -r .tp <<<"$r")" "$action" "$(jq -c "del(.tp)" <<<"$r")" | shasum -a 256 | cut -c1-32)
  case "$v" in
    verified*) pr=; [ "$kind" != merge ] || [ "$host" != gh ] || pr=$(gh pr view "$target" -R "$repo" --json state,autoMergeRequest,headRefOid 2>/dev/null) || pr=
               [ ! -e "$used" ] || jq -e --arg h "$(cat "$used")" '$h != "" and .headRefOid == $h and .state == "OPEN" and .autoMergeRequest == null' <<<"${pr:-null}" >/dev/null 2>&1 ||
                 { tried=${tried:-"this relay was used once already: check whether that run landed before asking again"}; fault used-once relay; continue; }
               mkdir -p "${used%/*}" && { jq -r '.headRefOid // empty' <<<"${pr:-null}" 2>/dev/null || :; } > "$used" || exit 1
               # This exact command, also handed to the user (hand_command): withdrawn, or the pane's Run posts it again.
               w=
               [ -z "$sid" ] || for c in ~/.cache/session-status/commands/*.json; do
                 [ -f "$c" ] && jq -e --arg s "$sid" --arg c "$raw" '.session == $s and .command == $c' "$c" >/dev/null 2>&1 || continue
                 rm -f "$c" && w=" (the same command you handed the user is withdrawn from the pane)"
               done
               decide allow "Relayed approval for $action (good for this one run)$w: $v" ;;
  esac
  tried=${tried:-${v:-verify-approval.sh failed}$hint}; fault unverified relay   # relays run newest first: the newest one's reason is the deny's
done < <(awk '{ l[NR] = $0 } END { for (i = NR; i > 0; i--) print l[i] }' <<<"$relays")   # newest first (no tail -r on Linux)
ask_for "$action${tried:+ (the relay found: $tried)}" "$action" "$what"

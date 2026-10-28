#!/usr/bin/env bash
# PreToolUse on Bash: a PR or Jira comment post (bitbucketdc-cli pr comment create|reply|update, forgejo-cli pr
# comment create|update, jiradc-cli issue comment create|update), a PR review (forgejo-cli pr review), a PR merge
# (bitbucketdc-cli or forgejo-cli pr merge) and their GitHub twins (gh pr merge|comment|review, gh issue comment) run only on a relayed approval that names it: a coordinator's "APPROVAL relayed from the user" block, received by this session, whose quote
# verify-approval.sh verifies and whose Action line names the target (REPO#ID for a PR, the issue key for Jira),
# plus the body file's sha256 for a post (and, for a gh review, its kind), or "merge"/"approve" (and no sha256) for a
# merge or a bodiless approval. A forgejo-cli REPO is its --repo OWNER/REPO. A gh REPO is OWNER/REPO (HOST/OWNER/REPO off github.com), from -R/--repo or the PR's
# URL (never guessed from a remote: gh picks its base repo by rules of its own). A relay whose Action names no tracker key (a project with
# session-name keys) is verified with REPO's last part #ID as the key. Then: allow, once per relay
# (~/.cache/session-status/approved/). The command must be that one CLI call alone. Anything else on
# those commands: deny, with the exact action to report. A `gh api` call with a write method or fields, a
# `forgejo-cli raw` call with a write method, or gh reached through a variable or $(…), is denied (asked, when
# attended): it can't be named as an action.
# A missing or unverified approval asks instead (the
# normal permission dialog, same text) in an interactive session: CLAUDE_CODE_SESSION_ATTENDED=1, set in every
# hook's env. A `--bg` session gets 0 even while `claude attach`ed (tested on 2.1.296: the binary forces 0 for
# CLAUDE_CODE_SESSION_KIND=bg), so it is denied; unset or any other value is denied too. Fails closed: any error
# here exits 2, which blocks (hooks.json also sets onFailure: block, for a timeout). Every other command exits 0 at once, with no decision.
# gh counts as a call where a command starts; its words must be plain (no variable, $(…), alias or xargs), or it is
# denied (asked, when attended). A post or merge it can't find as a call (inside bash -c, a heredoc a shell reads) is
# denied too: post from a file. A command that only mentions one (a grep pattern, a commit message, a prompt, a
# heredoc written to a file) passes when every command in it is on an allowlist of ones that never run their text
# (SAFE); read-only calls (gh pr view, gh api GET, an inline graphql query) pass too.
# ponytail: gh subcommands outside pr/issue/api (release, repo, workflow) aren't gated; add them when a project
# reserves them. A name split by quotes (g''h) isn't seen.
# TODO: GitLab. glab mr merge|note|approve and glab issue note pass ungated; gate them like gh (glab has no body-file
# flag: -m "$(cat /abs/file)").
# The other gated way to post: skills/orchestrating-sessions/review-inbox/post-approved.sh, whose CLI call this hook
# doesn't see. It posts only review-inbox rows the user approved on the page, each checked by verify-row.sh.
input=$(cat)
# (The raw JSON: a newline before gh is the two characters \n.)
pre='bitbucketdc-cli|forgejo-cli|jiradc-cli|(^|[^A-Za-z0-9_.-]|\\[nrt])gh([^A-Za-z0-9_.-]|$)'
[[ $input =~ $pre ]] || exit 0

done=
trap '[ -n "$done" ] || { echo "approved-action hook failed, so this command is blocked. Report \"needs your approval: <the exact action>\" to the coordinator and end your turn." >&2; exit 2; }' EXIT
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
pass() { done=1; exit 0; }
decide() { done=1; jq -nc --arg d "$1" --arg r "$2" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'; exit 0; }
attended() { local d=deny; if [ "${CLAUDE_CODE_SESSION_ATTENDED:-}" = 1 ]; then d=ask; fi; decide "$d" "$1"; }
ask_for() {
  attended "Blocked: $1 needs the user's approval, relayed by the coordinator and naming exactly this. Don't retry it, and don't route it another way. Send the coordinator your blocked status report with the line: needs your approval: $2. Then end your turn. When the relay arrives (Action naming $3), run the same command again; this hook verifies it."
}

cmd=$(jq -r '.tool_input.command // ""' <<<"$input") || exit 1
cwd=$(jq -r '.cwd // ""' <<<"$input") tp=$(jq -r '.transcript_path // ""' <<<"$input") || exit 1
# Text given to a command is text, not calls, only when every command in sight is one that never runs what it's
# given: an allowlist, so anything else (a shell, awk, a variable, a path or `.` as the command, read, set, sudo)
# fails closed. git counts only as git [-C DIR] add|commit|status|log|diff|show (-c, aliases and other subcommands
# can run text); npx only as `npx [-y] CLI[@version]` for the three CLIs (no scope: any publisher can take one);
# rg and sort not with --pre or --compress-program. Shared by both passes below.
SAFE=' cat tee echo printf grep egrep fgrep rg git claude head tail wc ls cd mkdir touch test [ true false sort uniq cut tr diff jq gh bitbucketdc-cli forgejo-cli jiradc-cli '
# lex(S): S with quoting resolved: quote marks dropped, and each separator, < and ( inside quotes made `_`, so what
# is left splits into commands as the shell would (unclosed quote: the rest counts as quoted). A # at a word start
# becomes its own command `#`, which safe() refuses: where a comment starts (x\ #y, ${x/ #/}) is the shell's call,
# so a command with one is read whole. safe(U): every command in lexed text U starts with a SAFE word (after VAR=x
# and prefixes like env, then, while).
awklib='
function lex(s,   o, c, j, n, iq) { o = ""; iq = ""; n = length(s)
  for (j = 1; j <= n; j++) { c = substr(s, j, 1)
    if (iq == "" && c == "\\" || iq == "\"" && c == "\\") { o = o "_"; j++; continue }
    if (iq == "" && c == "#" && (j == 1 || substr(s, j - 1, 1) ~ /[ \t\n;|&()]/)) { o = o ";#"; continue }
    if (iq == "") { if (c == "\"" || c == Q) iq = c; else o = o c; continue }
    if (c == iq) { iq = ""; continue }
    # "…$(cmd)" and "…`cmd`" run cmd: kept, so safe() sees it
    if (iq == "\"" && (c == "`" || c == "$" && substr(s, j + 1, 1) == "(")) { o = o c; continue }
    o = o (c ~ /[;|&()<>`$\n]/ ? "_" : c) }
  LQ = iq; return o }
function safe(u,   n, seg, x, m, w, y, t) { n = split(u, seg, /[;|&()`\n]|\$\(/)
  for (x = 1; x <= n; x++) { m = split(seg[x], w, /[ \t]+/); t = ""
    for (y = 1; y <= m; y++) { if (w[y] == "" || w[y] ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || index(PRE, " " w[y] " ")) continue; t = w[y]; break }
    if (t == "") continue
    if (t == "npx") { for (y++; w[y] == "-y" || w[y] == "--yes"; y++); t = w[y]; sub(/@[^@\/]*$/, "", t)
      if (t !~ /^(bitbucketdc|forgejo|jiradc)-cli$/) return 0 }
    if ((t == "rg" || t == "sort") && seg[x] ~ /--(pre|compress-program)/) return 0
    if (t == "git") { for (y++; w[y] == "-C"; y += 2); if (!index(" add commit status log diff show ", " " w[y] " ")) return 0 }
    if (!index(SAFE, " " t " ")) return 0 }
  return 1 }'
awkv=(-v "SAFE=$SAFE" -v "PRE= env command time nohup rtk proxy then do else ! { } if elif while until done fi esac " -v "Q='")
# Heredoc bodies (cat > f <<EOF … EOF) are text, not commands: dropped when the whole command without them is
# safe(); else the command is printed whole, its bodies unlexed, and the first line says 1 (opaque: the scan below
# reads it all). A << inside quotes, in (( )) arithmetic, in a <<< here-string or on a line going on with \, or with
# no terminator, isn't taken as a heredoc.
cmd=$(printf '%s\n' "$cmd" | awk "${awkv[@]}" "$awklib"'
  { L[NR] = $0 } END { i = 1; LQ = ""; q = ""; n = 0; cut = 0
    while (i <= NR) { line = L[i++]
      u = lex(q line); q = LQ   # a quote still open goes on to the next line
      O[++n] = line
      if (q != "" || u ~ /\(\(|<<</ || line ~ /\\$/ || !match(u, /<<-?[ \t]*[A-Za-z_][A-Za-z0-9_]*/) || gsub(/<</, "&", u) > 1) continue
      h = substr(u, RSTART + 2, RLENGTH - 2); dash = h ~ /^-/; gsub(/[- \t]/, "", h)
      for (k = i; k <= NR; k++) { t = L[k]; if (dash) sub(/^\t+/, "", t); if (t == h) break }
      if (k > NR) continue
      for (; i <= k; i++) { O[++n] = L[i]; B[n] = 1 }
      cut = 1 }
    d = ""; if (cut) for (x = 1; x <= n; x++) if (!B[x]) d = d O[x] "\n"
    op = cut && !safe(lex(d)); print op
    for (x = 1; x <= n; x++) if (op || !B[x]) print O[x] }')
opaque=${cmd:0:1} cmd=${cmd:2}
ops='bitbucketdc-cli[^[:space:]]*.*[[:space:]]pr[[:space:]]+(merge|comment[[:space:]]+(create|reply|update))([[:space:]]|$)|forgejo-cli[^[:space:]]*.*[[:space:]]pr[[:space:]]+(merge|review|comment[[:space:]]+(create|update))([[:space:]]|$)|jiradc-cli[^[:space:]]*.*[[:space:]]issue[[:space:]]+comment[[:space:]]+(create|update)([[:space:]]|$)'
ghw='(^|[^A-Za-z0-9_.-])gh([^A-Za-z0-9_.-]|$)'
# gh, then pr/issue and a merge, comment or review, or api, in the same command (flags may sit between): what a gated
# gh call looks like. gh pr view or gh issue list don't.
ghops='(^|[^A-Za-z0-9_.-])gh([^A-Za-z0-9_.-][^|;&]*[[:space:]]|[[:space:]]+)((pr|issue)([[:space:]][^|;&]*)?[[:space:]](merge|comment|review)|api)([[:space:]]|$)'
# gh named through a variable or $(…): x=gh, $(which gh), `command -v gh`.
ghind='(=["'"'"']?|\$\(|`)[[:space:]]*((which|command[[:space:]]+-v|type[[:space:]]+-p)[[:space:]]+)?([^[:space:]]*/)?gh([^A-Za-z0-9_.-]|$)'
# One line: continuations joined, other newlines made command separators.
# (awk, not ${cmd//"$nl"/ ; }: bash 3.2's replace-all is quadratic, minutes on a 50 KB heredoc.)
cmd=$(printf '%s\n' "$cmd" | awk 'NR > 1 { printf "%s", (c ? " " : " ; ") } { c = sub(/\\$/, ""); printf "%s", $0 }')
# What the CLI mentions are counted in: the command without its quoted runs of words (a grep pattern, a commit
# message, a prompt), which are arguments, not calls. A quoted single word stays (gh "pr" merge), and so do a value
# (X='npx cli', run as $X later) and a "…" holding $( or `, which the shell runs. Unless every command is safe(),
# the whole command counts.
scan=$(printf '%s' "$cmd" | awk "${awkv[@]}" -v q="'" -v opaque="$opaque" "$awklib"'{ s = s (NR > 1 ? "\n" : "") $0 } END {
  if (opaque || !safe(lex(s))) { printf "%s", s; exit }
  while (match(s, "[\\\\\"" q "]")) {
    out = out substr(s, 1, RSTART - 1); c = substr(s, RSTART, 1); s = substr(s, RSTART + 1)
    if (c == "\\") { out = out c substr(s, 1, 1); s = substr(s, 2); continue }
    # The closing quote: for "…", the first one no backslash escapes.
    if (c == q) e = index(s, q); else { e = 0; r = s; while (match(r, /\\.|"/)) { e += RSTART + RLENGTH - 1; if (RLENGTH == 1) break; r = substr(r, RSTART + 2) } if (RLENGTH != 1) e = 0 }
    if (!e) e = length(s) + 1
    b = substr(s, 1, e - 1); s = substr(s, e + 1)
    if (b !~ /[ \t]/ || out ~ /=$/ || (c == "\"" && (index(b, "$(") || index(b, "`")))) out = out c b c
  }
  printf "%s", out s }')
ghn=$(grep -oE "$ghw" <<<"$scan" | wc -l | tr -d ' ')
# Matched with quotes dropped too, so a quoted subcommand (pr 'merge') or flag is still seen.
# (tr, not ${scan//[\"\']/}: bash 3.2's is quadratic, 11 s on a 5 KB heredoc.)
uq=$(tr -d "\"'" <<<"$scan")
bbops=; grep -qE "$ops" <<<"$uq" && bbops=1
# forgejo-cli raw with a write method: the gh api twin.
grep -qiE 'forgejo-cli[^[:space:]]*.*[[:space:]]raw[[:space:]].*--method[=[:space:]]+["'"'"']?(POST|PUT|PATCH|DELETE)' <<<"$uq" &&
  attended "Blocked: a forgejo-cli raw call that writes can't be named as an approved action. Use forgejo-cli pr merge|review|comment, or hand the user the command with hand_command."
[ -n "$bbops" ] || [ "$ghn" -gt 0 ] || pass
grep -qE "$ghind" <<<"$scan" &&
  attended "Blocked: gh reached through a variable or \$(…) can't be checked by the approval hook. Run it by its name (gh …), as one plain command."
alone="Run that CLI call alone, as one plain command (the CLI, then its subcommand, then the arguments)."
# Fails closed on anything it can't read as exactly one call: a second CLI call (chained, or glued to a token), a
# subcommand behind global flags or a variable.
bbn=$(grep -oE 'bitbucketdc-cli|forgejo-cli|jiradc-cli' <<<"$scan" | wc -l | tr -d ' ')
[ -z "$bbops" ] || [ "$bbn" = 1 ] ||
  decide deny "Blocked: a PR/Jira comment post, review or PR merge must be the only bitbucketdc-cli/forgejo-cli/jiradc-cli call in its command. $alone"

# Tokens, quotes honoured (xargs fails on an unbalanced quote: a heredoc's text, say).
tokstr=$(printf '%s' "$cmd" | xargs printf '%s\n' 2>/dev/null) && [ -n "$tokstr" ] ||
  { [ -z "$bbops" ] && ! grep -qE "$ghops" <<<"$scan" && pass; decide deny "Blocked: this command mentions a PR/Jira comment post or a PR merge, and the approval hook can't parse it. $alone"; }
toks=()
while IFS= read -r t; do toks+=("$t"); done <<<"$tokstr"
# Walk the tokens: each CLI call (up to |, ;, &&, ||) is read as SUB TARGET [flags]; a gh call (gh where a command
# starts) as GROUP VERB TARGET with its flags anywhere.
groups=' agent-task alias api attestation auth browse cache codespace completion config copilot extension gist gpg-key help issue label org pr preview project release repo ruleset run search secret ssh-key status variable version workflow '
calls=0 ghcalls=0 apiw= kind= target= repo= bodyfile= body= help= host= mode= modes=0 fj= cm=
i=0
while [ "$i" -lt "${#toks[@]}" ]; do
  t=${toks[$i]}; i=$((i + 1)); prev=; [ "$i" -lt 2 ] || prev=${toks[$((i - 2))]}
  b=${t%;}; b=${b#\(}; b=${b#\$\(}; b=${b%\)}
  case "$t" in
    *bitbucketdc-cli*|*forgejo-cli*|*jiradc-cli*) h= ;;
    *) [ "${b##*/}" = gh ] || continue
       # Where a command starts: first, after a separator or a command prefix (env, VAR=x, sudo …).
       case "$prev" in ''|'|'|'||'|'&&'|';'|'&'|*';'|'('|'$('|env|command|rtk|proxy|exec|time|nohup|sudo|xargs|then|do|else|'!'|[A-Za-z_]*=*) ;; *)
         [ "$t" != "$b" ] || continue ;; esac
       [ "$prev" != xargs ] || attended "Blocked: gh run through xargs can't be checked by the approval hook. $alone"
       h=gh ;;
  esac
  cli=$t args=()
  while [ "$i" -lt "${#toks[@]}" ]; do
    a=${toks[$i]}; case "$a" in '|'|'||'|'&&'|';'|'&') break ;; esac
    i=$((i + 1)); a=${a%;}; args+=("${a%)}"); case "$a" in *';') break ;; esac
  done
  if [ -z "$h" ]; then
    sub="${args[*]:0:3}"
    case "$cli:$sub" in
      *bitbucketdc-cli*:'pr merge'*) k=merge; s=2 ;;
      *bitbucketdc-cli*:'pr comment create'*|*bitbucketdc-cli*:'pr comment reply'*|*bitbucketdc-cli*:'pr comment update'*) k=prpost; s=3 ;;
      *forgejo-cli*:'pr merge'*) k=merge; s=2 ;;
      *forgejo-cli*:'pr review'*) k=review; s=2 ;;
      *forgejo-cli*:'pr comment create'*|*forgejo-cli*:'pr comment update'*) k=prpost; s=3 ;;
      *jiradc-cli*:'issue comment create'*|*jiradc-cli*:'issue comment update'*) k=jirapost; s=3 ;;
      *) continue ;;
    esac
    calls=$((calls + 1)); host= kind=$k target= repo= bodyfile= body= mode= modes=0 cm= fj=
    case "$cli" in *forgejo-cli*) fj=1 ;; esac
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
  case "${pos[*]:-}" in *'$'*|*'`'*) attended "Blocked: gh with a variable or \$(…) in its words can't be checked by the approval hook. $alone" ;; esac
  { [[ ${pos[0]:-} != *[[:space:]]* ]] && { [[ ${pos[0]:-} != pr && ${pos[0]:-} != issue ]] || [[ ${pos[1]:-} != *[[:space:]]* ]]; }; } ||
    attended "Blocked: gh with a quoted run of words as its command (gh pr 'merge 5') can't be checked by the approval hook. $alone"
  [ -z "${pos[0]:-}" ] || [[ $groups == *" ${pos[0]} "* ]] ||
    attended "Blocked: \"gh ${pos[0]}\" isn't a gh command the approval hook knows (an alias?). Run the gh command it stands for, as one plain command."
  case "${pos[*]:0:2}" in
    'pr merge') k=merge ;;
    'pr comment'|'issue comment') k=prpost ;;
    'pr review') k=review ;;
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
[ "$calls" = 1 ] && [ $((bbn + ghn)) = 1 ] ||
  decide deny "Blocked: a PR/issue comment post, review or merge must be the only bitbucketdc-cli/forgejo-cli/jiradc-cli/gh call in its command. $alone"
[ -z "$help" ] || pass
[ -n "$target" ] || decide deny "Blocked: no PR id or issue key in this command."
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
  [[ $target =~ ^[0-9]+$ ]] || decide deny "Blocked: the PR or issue id must be a number (or its URL), not a branch or nothing."
  what="$repo#$target" short="${repo##*/}#$target"
else
  case $kind in
    merge|prpost|review) [[ $target =~ ^[0-9]+$ ]] || decide deny "Blocked: the PR id must be a number."
                  [ -n "$repo" ] || decide deny "Blocked: name the repository with --repo, so the approval can name REPO#ID."
                  [ -z "$fj" ] || [[ $repo == */* ]] || decide deny "Blocked: name the repository as --repo OWNER/REPO, so the approval can name OWNER/REPO#ID."
                  what="$repo#$target"; [ -z "$fj" ] || short="${repo##*/}#$target" ;;
    jirapost) what=$target ;;
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
  bf='--body-file <absolute path>'
  [ -z "$body" ] || decide deny "Blocked: post the comment with $bf, not inline text, so the approval can name the file's sha256."
  [ -n "$bodyfile" ] && [ "$bodyfile" != - ] || decide deny "Blocked: post the comment with $bf, so the approval can name the file's sha256."
  case "$bodyfile" in /*) ;; *) decide deny "Blocked: give the body file as an absolute path: $bf." ;; esac
  [ -f "$bodyfile" ] || decide deny "Blocked: no such body file: $bodyfile"
  sha=$(shasum -a 256 "$bodyfile" | cut -d' ' -f1); [ "${#sha}" = 64 ] || exit 1
  if [ "$kind" = review ]; then action="post $mode review $bodyfile on $what (sha256 $sha)"
  else action="post comment $bodyfile on $what (sha256 $sha)"; fi
fi

# The relays this session received: peer messages from another session (not a subagent's hand-back), newest
# first: sender name, quote, action, source sessionId, source cwd (tab-free JSON lines).
[ -f "$tp" ] || ask_for "$action" "$action" "$what"
relays=$(jq -c '
  (if .type == "user" then .origin elif .type == "attachment" and .attachment.type == "queued_command" then .attachment.origin else null end) as $o
  | select($o.kind? == "peer" and (($o.from // "") | startswith("uds:")) and ($o.handback | not))
  | ($o.body // "") as $b
  | $b | [scan("APPROVAL relayed from the user\\nQuote: ([\\s\\S]*?)\\nAction: ([^\\n]*)\\nSource: ([0-9a-f-]{36}) ([^\\n]+)")]
  | .[] | {name: $o.name, quote: .[0], action: .[1], sid: .[2], scwd: .[3]}' "$tp" 2>/dev/null) || exit 1
# A relay counts for this command when its Action names the target as a whole word, and the sha256 for a post or
# "merge"/"approve" with no sha256 for a merge or bare approval (a gh review: its kind and "review" too); then the quote must verify, with the task key the Action names.
tried=
while IFS= read -r r; do
  [ -n "$r" ] || continue
  act=$(jq -r .action <<<"$r")
  w=${what//./\\.}
  grep -qE "(^|[^A-Za-z0-9#/.-])$w([^A-Za-z0-9]|$)" <<<"$act" || continue
  if [ "$kind" = merge ] || [ "$kind" = approve ]; then
    grep -qiE "(^|[^a-z])$kind([^a-z]|$)" <<<"$act" && ! grep -qE '[0-9a-f]{64}' <<<"$act" || continue
  else
    grep -qF "$sha" <<<"$act" || continue
    # A gh comment's relay isn't a review's, and a review's names its kind.
    [ "$kind" != prpost ] || [ -z "$host$fj" ] || ! grep -qiw review <<<"$act" || continue
    [ "$kind" != review ] || { grep -qiE "(^|[^a-z-])$mode([^a-z-]|$)" <<<"$act" && grep -qiw review <<<"$act"; } || continue
  fi
  key=$target; [ "$kind" = jirapost ] || key=$(grep -oE '[A-Z][A-Z0-9]+-[0-9]+' <<<"$act" | head -1)
  # No tracker key (session-name keys): the user's words must name the target itself (REPO#ID; OWNER/ may precede).
  [ -n "$key" ] || key=$short
  [ -n "$key" ] || { tried="the matching relay's Action names no task key"; continue; }
  v=$(cd "$cwd" 2>/dev/null && jq -r .quote <<<"$r" |
      bash "$here/../skills/orchestrating-sessions/verify-approval.sh" "$(jq -r .sid <<<"$r")" "$(jq -r .scwd <<<"$r")" "$(jq -r .name <<<"$r")" "$key")
  # One use per relay: a rerun (the CLI timed out after the server took it) needs a new approval.
  # ponytail: used up when allowed, not when the command succeeds; the deny says to check before asking again.
  used=~/.cache/session-status/approved/$(printf '%s|%s|%s' "$tp" "$action" "$r" | shasum -a 256 | cut -c1-32)
  case "$v" in
    verified*) [ ! -e "$used" ] || { tried="this relay was used once already: check whether that run landed before asking again"; continue; }
               mkdir -p "${used%/*}" && touch "$used" || exit 1
               decide allow "Relayed approval for $action (good for this one run): $v" ;;
  esac
  tried=${v:-verify-approval.sh failed}
done < <(awk '{ l[NR] = $0 } END { for (i = NR; i > 0; i--) print l[i] }' <<<"$relays")   # newest first (no tail -r on Linux)
ask_for "$action${tried:+ (the relay found: $tried)}" "$action" "$what"

# session-orchestration's shell library, sourced by the skills' scripts: the project's coordination config and
# the date/file-time helpers that differ between GNU (Linux) and BSD (macOS).
#
# Config: two JSON files, each the nearest one up from the cwd within the project (a folder with its own adapter
# ends the walk: a subproject never reads its parent's), merged key by key (the person's file wins), over the
# person-wide user_config (any key but team, which only the project's file sets):
#   .claude/coordination/coordination.json   repo keys: tracker, host, key_pattern, features.review_inbox
#                                            (excluded from git until shared mode commits it; read from the team
#                                            repo's when the person file names one, see shared_dir)
#   .claude/coordination.local.json          person keys: approvals.delegate, features.accounts, terminal, messages
#                                            (and its module's block, e.g. msgraph), trusted, team, feedback.mode,
#                                            feedback.repo_dir, telemetry, handoff.*, compact.window (always excluded;
#                                            the repo file can't set them)
# No file means every default. `config KEY` prints the key's value; an unknown value prints the default and one
# warning line on stderr.
# Modules (terminals/<name>.sh, messages/<name>.sh, features/<name>.sh): found by find_module, checked and sourced by load_module.
# ponytail: modules found by name along a fixed path (project-local, committed+trusted, person, plugin); a registry
# with manifests and dependencies when a module needs another, or a catalog of third-party modules appears.
LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# coord_file NAME: the nearest .claude/NAME up from the cwd, stopping after the first folder with its own adapter
# (the project's root). A worktree below finds the main checkout's person file even when it has the repo file.
coord_file() {
  local d
  d=$(pwd -P)
  while [ "$d" != / ]; do
    [ -e "$d/.claude/$1" ] && { echo "$d/.claude/$1"; return 0; }
    [ -x "$d/.claude/session-status-adapter" ] && return 1
    d=$(dirname "$d")
  done
  return 1
}

# tracked FILE: git tracks FILE. The person's paths (coordination.local.json, coordination.local/, the local
# adapter) are never taken from a commit: a committed one would trust, delegate or run code for everyone who clones.
tracked() {
  git -C "$(dirname "$1")" ls-files --error-unmatch -- "$(basename "$1")" >/dev/null 2>&1 || return 1
  echo "warning: $1 is committed: a personal file is never read from git: ignored" >&2
}
# person_file: the person's coordination.local.json, unless it's committed.
person_file() { local f; f=$(coord_file coordination.local.json) && ! tracked "$f" && echo "$f"; }

# The files merged; {} when there are none. A file that isn't a JSON object is skipped with a warning. The person
# keys are dropped from the repo file: a committed file never delegates for anyone, nor picks your terminal.
user_config() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/session-orchestration/config.json"; }

coord_json() {
  local f out='{}' j s m p d drop
  # The block of the person's messages module too (e.g. .slack): its settings can name a command to run.
  # Its name from either person's file, the project's winning.
  p=$(person_file)
  for f in "$(user_config)" "${p:-}"; do
    [ -n "$f" ] && [ -f "$f" ] && j=$(jq -r '.messages // empty | strings' "$f" 2>/dev/null) && [ -n "$j" ] && m=$j
  done
  drop="del(.approvals, .terminal, .messages, .msgraph, .trusted, .team, .feedback, .telemetry, .handoff, .compact$( [[ ${m:-} =~ ^[A-Za-z0-9_-]+$ ]] && echo ", .[\"$m\"]")) | if .features | type == \"object\" then del(.features.accounts) else . end"
  s=$(shared_dir 2>/dev/null) && s=$s/coordination.json
  # Lowest first: the person's file for every project (person-wide keys such as feedback.*), the repo file, the
  # project's person file.
  for f in "$(user_config)" "$s" "${p:-}"; do
    [ "$f" = "$s" ] && d=$drop || d=.
    [ -n "$f" ] && [ -f "$f" ] || continue
    j=$(jq -ce "if type == \"object\" then $d else error end" "$f" 2>/dev/null) || { echo "warning: $f is not a JSON object: ignored" >&2; continue; }
    out=$(jq -cn --argjson a "$out" --argjson b "$j" '$a * $b')
  done
  echo "$out"
}

# shared_dir: the folder with the committed files, .claude/coordination: the one in the repo the person key team
# names (a path, relative to the project root: a workspace that isn't the repo itself), else the nearest one up.
shared_dir() {
  local p t
  if p=$(person_file) && t=$(jq -r '.team // empty | strings' "$p" 2>/dev/null) && [ -n "$t" ]; then
    t=${t/#\~/$HOME}; [[ $t == /* ]] || t=${p%/.claude/coordination.local.json}/$t
    [ -d "$t/.claude/coordination" ] && { echo "$t/.claude/coordination"; return 0; }
    echo "warning: team=$t has no .claude/coordination: ignored" >&2
  fi
  coord_file coordination
}

sha256_of() { { sha256sum "$1" 2>/dev/null || shasum -a 256 "$1"; } | cut -d' ' -f1; }

# trusted REL: the committed .claude/coordination/REL (shared_dir), when its sha256 is the one the person recorded
# under trusted (setup records it once they've read the file). A new or changed file fails with a warning; no file
# fails silently.
trusted() {
  local d f want
  d=$(shared_dir) && f=$d/$1 && [ -f "$f" ] || return 1
  want=$(coord_json | jq -r --arg k "$1" '.trusted | if type == "object" then .[$k] // empty | strings else empty end')
  [ -n "$want" ] && [ "$(sha256_of "$f")" = "$want" ] && { echo "$f"; return 0; }
  echo "warning: $1 $([ -n "$want" ] && echo changed upstream || echo is not trusted yet): run setup to review it" >&2
  return 1
}

# find_root: the project root up from the cwd.
find_root() {
  local d
  d=$(pwd -P)   # Claude names transcript dirs and reports cwd by the physical path
  # The root has an adapter, or the person file (a team workspace uses the team repo's committed adapter).
  while [ "$d" != / ]; do
    { [ -x "$d/.claude/session-status-adapter" ] || [ -f "$d/.claude/coordination.local.json" ]; } && { echo "$d"; return; }
    d=$(dirname "$d")
  done
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# adapter_path ROOT: the project's adapter: ROOT/.claude/session-status-adapter when executable, else the committed
# one once trusted; prints nothing when there's neither. (The plugin's templates are what setup copies, not a
# fallback: they have placeholders.)
adapter_path() {
  [ -x "$1/.claude/session-status-adapter" ] && ! tracked "$1/.claude/session-status-adapter" &&
    { echo "$1/.claude/session-status-adapter"; return 0; }
  local f; f=$(cd "$1" && trusted session-status-adapter) && [ -x "$f" ] && echo "$f"
}

# The code host from the origin remote of the repo at DIR (default: the cwd), else of the first repo below it (a
# workspace), as setup picks it. GitLab isn't supported yet (TODO: GitLab support): none, with a warning.
detect_host() {
  local d=${1:-.} g
  git -C "$d" rev-parse --git-dir >/dev/null 2>&1 ||
    { g=$(find "$d" -mindepth 2 -maxdepth 3 -name .git 2>/dev/null | sort | head -1); [ -z "$g" ] || d=${g%/.git}; }
  case $(git -C "$d" remote get-url origin 2>/dev/null) in
    *github.com*) echo github ;; *bitbucket*) echo bitbucket ;;
    *gitlab*) echo "warning: a GitLab remote: host=none until GitLab support (a TODO)" >&2; echo none ;;
    *) echo none ;;
  esac
}

# config KEY: the key's value, or its default. Keys and values:
#   tracker             none | github | jira                          default none
#   host                github | bitbucket | none                     default from the origin remote
#   key_pattern         an ERE matching a task key                    default empty (session-status's own)
#   approvals.delegate  true | false: a coordinator's message counts as the user's approval, except what the
#                       project's CLAUDE.md reserves                    default false
#   features.accounts   true | false: ask every Claude account sharing this transcript store (features/accounts.*)
#                                                                       default false
#   features.review_inbox  true | false: PR findings go to the review inbox page (features/review-inbox.md);
#                       Bitbucket only (TODO: GitHub support)           default false
#   terminal            plain | ghostty | your own module's name (find_module terminals NAME): where the pane's
#                       Attach in tab and Logs in split open             default plain
#   messages            none | msgraph | your own module's name (find_module messages NAME): the chat and mail
#                       notices under the status table (messages/msgraph.md)                default none
#   feedback.mode       auto | pr | fork-pr | issue | local: how plugin feedback cases are sent
#                       (skills/orchestrating-sessions/feedback.md)    default auto
#   feedback.repo_dir   a clone of the plugin repo you can push to (~ expanded)     default empty
#   telemetry           local | off: pane presses to the local usage log (usage below)     default off
#   plan.enabled        true | false: the task planner splits big tasks into chunks         default true
#   plan.max_parallel   integer >= 1: chunk sessions at once                                default 3
#   plan.models.KIND    MODEL/EFFORT (effort low|medium|high|xhigh|max; never fable), KIND design | build | mechanical | review
#                       | release | scan     default opus/xhigh, opus/medium, sonnet/medium, opus/xhigh,
#                       sonnet/medium, haiku/low
#   handoff.at.KIND     integer tokens, 0 = off: context where hooks/context-watch.sh asks a session to hand off,
#                       KIND chunk | task | coordinator (person only)   default 125000, 120000, 145000
#   handoff.hard_after  integer tokens: the hard stop, this far past handoff.at (person only)   default 25000
#   handoff.stop_room   integer tokens: room left under the compaction ceiling (person only)   default 15000
#   compact.window      integer tokens: the autoCompactWindow sessions are expected to have (person only)
#                                                                       default 220000
config() {
  local key=${1:-} v ok=
  case $key in
    tracker|host|key_pattern|approvals.delegate|features.accounts|features.review_inbox|terminal|messages|feedback.mode|feedback.repo_dir|telemetry) ;;
    plan.enabled|plan.max_parallel|plan.models.design|plan.models.build|plan.models.mechanical|plan.models.review|plan.models.release|plan.models.scan) ;;
    handoff.at.chunk|handoff.at.task|handoff.at.coordinator|handoff.hard_after|handoff.stop_room|compact.window) ;;
    *) echo "unknown config key: ${key:-(none)} (one of tracker host key_pattern approvals.delegate features.accounts features.review_inbox terminal messages feedback.mode feedback.repo_dir telemetry plan.enabled plan.max_parallel plan.models.{design,build,mechanical,review,release,scan} handoff.at.{chunk,task,coordinator} handoff.hard_after handoff.stop_room compact.window)" >&2; return 2 ;;
  esac
  v=$(coord_json | jq -r --arg k "$key" 'getpath($k | split(".")) | if . == null then empty else tostring end')
  [ -n "$v" ] && case $key in
    tracker) case $v in none|github|jira) ok=1 ;; esac ;;
    host) case $v in github|bitbucket|none) ok=1 ;; esac ;;
    key_pattern) { grep -qE -- "$v" </dev/null; [ $? -le 1 ]; } 2>/dev/null && ok=1 ;;
    approvals.delegate|features.accounts|plan.enabled) case $v in true|false) ok=1 ;; esac ;;
    features.review_inbox) case $v in false) ok=1 ;;
      true) [ "$(config host 2>/dev/null)" = bitbucket ] && ok=1 ||
              { echo "warning: features.review_inbox needs host=bitbucket (GitHub support is a TODO): off" >&2; echo false; return 0; } ;;
    esac ;;
    terminal) [[ $v =~ ^[A-Za-z0-9_-]+$ ]] && find_module terminals "$v" >/dev/null && ok=1 ;;
    messages) [ "$v" = none ] && ok=1 || { [[ $v =~ ^[A-Za-z0-9_-]+$ ]] && find_module messages "$v" >/dev/null && ok=1; } ;;
    feedback.mode) case $v in auto|pr|fork-pr|issue|local) ok=1 ;; esac ;;
    telemetry) case $v in local|off) ok=1 ;; esac ;;
    plan.max_parallel) [[ $v =~ ^[1-9][0-9]{0,2}$ ]] && ok=1 ;;
    plan.models.*) [[ $v =~ ^[a-z][a-z0-9.-]*/(low|medium|high|xhigh|max)$ && $v != fable* ]] && ok=1 ;;
    handoff.*|compact.window) [[ $v =~ ^(0|[1-9][0-9]{0,6})$ ]] && ok=1 ;;
    feedback.repo_dir) [[ $v == '~'/* ]] && v=$HOME/${v#'~/'}; [ -d "$v" ] && ok=1 ;;
  esac
  [ -n "$ok" ] && { echo "$v"; return 0; }
  local kind=; [ "$key" = terminal ] && kind=terminals; [ "$key" = messages ] && kind=messages
  [ -z "$v" ] || echo "warning: config $key=$v is not valid${kind:+ (no $kind/$v.sh found)}: using the default" >&2
  case $key in
    tracker) echo none ;; host) detect_host ;; key_pattern) ;; approvals.delegate|features.*) echo false ;; terminal) echo plain ;; messages) echo none ;;
    feedback.mode) echo auto ;; feedback.repo_dir) ;; telemetry) echo off ;;
    plan.enabled) echo true ;; plan.max_parallel) echo 3 ;;
    plan.models.design|plan.models.review) echo opus/xhigh ;; plan.models.build) echo opus/medium ;;
    plan.models.mechanical|plan.models.release) echo sonnet/medium ;; plan.models.scan) echo haiku/low ;;
    handoff.at.chunk) echo 125000 ;; handoff.at.task) echo 120000 ;; handoff.at.coordinator) echo 145000 ;;
    handoff.hard_after) echo 25000 ;; handoff.stop_room) echo 15000 ;; compact.window) echo 220000 ;;
  esac
}

# usage NAME [KIND [MODEL EFFORT EST [ACT]]]: with telemetry=local, one line in the local usage log:
# {"t":EPOCH,"k":KIND,"what":NAME}. KIND is press (a pane button, from the mod), path (default: a script counting a
# path no transcript shows) or chunk (session-status --plan --done: NAME is the chunk's kind, then its model, effort,
# est and act in K of context growth; act may be left out). NAME is a fixed word (lowercase, digits, -), never a key,
# path or id, and every field is validated, so the file is shareable as is. Never fails its caller.
usage_log() { echo "${XDG_STATE_HOME:-$HOME/.local/state}/session-orchestration/usage.jsonl"; }
usage() {
  local f x=
  [[ ${1:-} =~ ^[a-z0-9-]{1,40}$ && ${2:-path} =~ ^(press|path|chunk)$ ]] || return 0
  if [ "${2:-}" = chunk ]; then
    [[ ${3:-} =~ ^[a-z][a-z0-9.-]{0,39}$ && ${4:-} =~ ^(low|medium|high|xhigh|max)$ && ${5:-} =~ ^[0-9]{1,4}$ &&
       ${6:-0} =~ ^[0-9]{1,5}$ && $# -le 6 ]] || return 0
    x=",\"model\":\"$3\",\"effort\":\"$4\",\"est\":$((10#$5))${6:+,\"act\":$((10#$6))}"
  fi
  [ "$(config telemetry 2>/dev/null)" = local ] || return 0
  f=$(usage_log); mkdir -p "${f%/*}" 2>/dev/null &&
    printf '{"t":%s,"k":"%s","what":"%s"%s}\n' "$(date +%s)" "${2:-path}" "$1" "$x" >> "$f" 2>/dev/null
  return 0
}

# coord_re [NAMES]: an ERE matching a coordinator's transcript line: a run of session-status (or NAMES, the adapter's
# status-names alternation) with --changes, --watch or --owner, or an open_pane tool use. A plain run (a worker
# checking its own task) doesn't match. session-status and hooks/context-watch.sh both read it.
coord_re() { echo "\"command\":\"[^\"]*(session-status${1:+|$1}) +--(changes|watch|owner)|\"name\":\"mcp__session-orchestration__open_pane\""; }

# find_module KIND NAME: the first KIND/NAME.sh along the lookup path; fails when there's none.
#   1. <root>/.claude/coordination.local/KIND/NAME.sh   this person, this project (excluded from git)
#   2. .claude/coordination/KIND/NAME.sh   committed (shared mode): only once trusted, else warned and skipped
#   3. ${XDG_CONFIG_HOME:-~/.config}/session-orchestration/KIND/NAME.sh   this person, every project
#   4. the plugin's KIND/NAME.sh
find_module() {
  local f
  f=$(coord_file "coordination.local/$1/$2.sh") && [ -f "$f" ] && ! tracked "$f" && { echo "$f"; return 0; }
  trusted "$1/$2.sh" && return 0   # checked only when tier 1 has none: a warning only for a file that would run
  for f in "${XDG_CONFIG_HOME:-$HOME/.config}/session-orchestration/$1/$2.sh" "$LIB_DIR/$1/$2.sh"; do
    [ -f "$f" ] && { echo "$f"; return 0; }
  done
  return 1
}

# load_module KIND NAME FUNCTION…: sources KIND/NAME.sh over the defaults already defined. Skipped whole, with a
# warning naming file and line, when it doesn't parse. A contract FUNCTION it doesn't define keeps the default, with
# a warning, and the call fails (so does one for a module found nowhere). One that shadows the plugin's is noted.
load_module() {
  local kind=$1 name=$2 f err miss; shift 2
  f=$(find_module "$kind" "$name") || { echo "warning: $kind/$name.sh found nowhere: not loaded" >&2; return 1; }
  err=$(bash -n "$f" 2>&1) || { echo "warning: ${f/#$HOME/~} skipped: $(head -1 <<<"${err#"$f": }")" >&2; return 1; }
  [ "$f" = "$LIB_DIR/$kind/$name.sh" ] || [ ! -e "$LIB_DIR/$kind/$name.sh" ] || echo "note: $name: using ${f/#$HOME/~}" >&2
  miss=$(unset -f "$@"; . "$f" >/dev/null 2>&1; for fn; do declare -F "$fn" >/dev/null || printf '%s ' "$fn"; done)
  . "$f" >/dev/null || true # its status is its last top-level line's; the probe above checked the functions
  [ -z "$miss" ] || { echo "warning: $kind/$name.sh: no ${miss% }, using the default" >&2; return 1; }
}

# load_terminal: open_view and open_split of the configured terminal (config terminal), over plain's.
load_terminal() {
  local t
  . "$LIB_DIR/terminals/plain.sh" || return 1
  t=$(config terminal) && [ "$t" != plain ] || return 0
  load_module terminals "$t" open_view open_split || true
}

# Sessions.
# ponytail: Claude Code only; another CLI adds runtimes/<name>.sh overriding these two, plus a start/attach command —
# workers of that kind report through the replies file and never get gated actions; a non-Claude coordinator also
# needs send_message and coordinator_log there.

# list_accounts: "CONFIG_DIR<TAB>command prefix" per Claude account whose sessions are asked. The current one only;
# with features.accounts on, every config dir sharing its transcript store (features/accounts.sh replaces this).
list_accounts() {
  if [ "$(config features.accounts 2>/dev/null)" = true ]; then
    load_module features accounts list_accounts 2>/dev/null && { list_accounts; return; }
  fi
  local d=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
  printf '%s\tclaude\n' "${d%/}"
}

# list_sessions [--all]: one session per line of every account list_accounts names: id, name, state, command prefix
# to reach it, started (epoch s), cwd, kind (background/interactive), status, pid (tabs). `--all` adds retired ones
# (stopped, done: no process, no pid). A listing that failed touches $TMP/ask.failed (when TMP is set): callers
# mustn't read "not listed" into it.
# state vs status: a background session's state is blocked both when it has finished its turn (status idle) and
# when it waits on a permission prompt or a question (status waiting); a running one is busy.
list_sessions() {
  local d pre out
  while IFS=$'\t' read -r d pre; do
    if [ "$pre" = claude ]; then out=$(claude agents --json "$@" 2>/dev/null)
    elif [ "$d" = "$HOME/.claude" ]; then out=$(env -u CLAUDE_CONFIG_DIR claude agents --json "$@" 2>/dev/null)
    else out=$(CLAUDE_CONFIG_DIR=$d claude agents --json "$@" 2>/dev/null)
    fi
    jq -e 'type == "array"' <<<"$out" >/dev/null 2>&1 || { [ -z "${TMP:-}" ] || : > "$TMP/ask.failed"; continue; }
    # Background sessions report `state` (e.g. blocked) beside `status`.
    jq -r --arg pre "$pre" '.[]? | select(.sessionId)
      | "\(.sessionId)\t\(.name)\t\(.state // .status // "?")\t\($pre)\t\((.startedAt // 0) / 1000 | floor)\t\(.cwd)\t\(.kind // "")\t\(.status // "")\t\(.pid // "")"' <<<"$out"
  done < <(list_accounts) | awk -F'\t' '!s[$1]++'
}

# activity_of TRANSCRIPT: session-activity.jq's line (doing, since, last text line, …); last_text: its last text line.
activity_of() { tail -n 2000 "$1" | jq -rRn -f "$LIB_DIR/skills/orchestrating-sessions/session-activity.jq" 2>/dev/null; }
last_text() { activity_of "$1" | cut -f3; }

# mtime FILE…: each file's modification time (epoch s). mtime_named FILE…: "EPOCH PATH" per file.
if stat -c %Y / >/dev/null 2>&1; then
  mtime() { stat -c %Y -- "$@"; }
  mtime_named() { stat -c '%Y %n' -- "$@"; }
else
  mtime() { stat -f %m -- "$@"; }
  mtime_named() { stat -f '%m %N' -- "$@"; }
fi

# dayfmt YYYY-MM-DD FORMAT [±N]: that day (local midnight), N days later or earlier, in date's FORMAT; fails on a
# date that doesn't exist. epoch YYYY-MM-DD: its local midnight in epoch seconds. epochfmt SECONDS FORMAT: that
# moment, local time, in date's FORMAT.
if date -d @0 +%s >/dev/null 2>&1; then
  dayfmt() { date -d "$1 ${3:-+0} days" +"$2" 2>/dev/null; }
  epochfmt() { date -d "@$1" +"$2"; }
else
  dayfmt() { date -j -v"${3:-+0}"d -f '%F %T' "$1 00:00:00" +"$2" 2>/dev/null; }
  epochfmt() { date -r "$1" +"$2"; }
fi
epoch() { dayfmt "$1" %s; }
